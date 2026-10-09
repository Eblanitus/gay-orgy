-- Особые механики отдельных видов: одно поле в Enemies — одна функция здесь.
--
-- Каждая механика — отдельная корутина, которая живёт, пока жив жук. Запускает их
-- EnemyBehavior.Attach ровно по наличию поля в записи врага: нет поля — нет поведения,
-- и отдельных флагов под них нет (требование RULES.md: новый вид — строка в таблице).
--
-- Механики не двигают жука сами. Они ставят ему заявки в state, а ведёт его общий цикл
-- движения (EnemySpawner):
--   Sense.GoTo     — пойти в точку (укрытие, к Строителю, к раненому, в засаду);
--   holdUntil      — стоять (строит, целится, линяет, заворачивает);
--   face           — куда смотреть, пока стоит или идёт (щит, прицел тарана);
--   focusTurret    — идти на эту турель и ломать её;
--   dash           — разгон Тарана по прямой;
--   biteBoost      — усиленные первые укусы (засада Мимика).
-- Так ни одна механика не может увести жука сквозь стену или из толкучки.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Enemies = require(ReplicatedStorage:WaitForChild("Enemies"))
local EnemyBody = require(ReplicatedStorage:WaitForChild("EnemyBody"))
local Elements = require(ReplicatedStorage:WaitForChild("Elements"))
local Effects = require(ReplicatedStorage:WaitForChild("Effects"))
local Grid = require(ServerScriptService:WaitForChild("Grid"))
local LabTable = require(ServerScriptService:WaitForChild("LabTable"))
-- Справочник и производитель: целью не бывают, но взрывы их задевают.
local LabStations = require(ServerScriptService:WaitForChild("LabStations"))
local EnemyStructures = require(ServerScriptService:WaitForChild("EnemyStructures"))
local TowerDebris = require(ServerScriptService:WaitForChild("TowerDebris"))
-- Рельеф бетонного пола: Строитель роет в нём настоящую ямку.
local ConcreteFloor = require(ServerScriptService:WaitForChild("ConcreteFloor"))
-- Груз Медика на время выходит из толкучки и возвращается в неё, когда его кладут.
local Crowd = require(ServerScriptService:WaitForChild("Crowd"))
local Sense = require(ServerScriptService:WaitForChild("EnemySense"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local DamageDealtRemote = Remotes:WaitForChild("DamageDealt")
local ExplosionRemote = Remotes:WaitForChild("Explosion")

local alive, flat, naps = Sense.alive, Sense.flat, Sense.naps
local towersFolder = Sense.towersFolder
local carried = Sense.carried

local EnemyTraits = {}
local TRAITS = {}
EnemyTraits.TRAITS = TRAITS

-- Куда смотрит голова жука: кадр маршрута довёрнут на 180° (см. EnemySpawner),
-- поэтому вперёд — это -LookVector.
local function ahead(enemy)
	local look = flat(-enemy:GetPivot().LookVector)
	return look.Magnitude > 1e-3 and look.Unit or Vector3.zAxis
end

local function distance(a, b)
	return flat(a - b).Magnitude
end

-- Полудлина тела по масштабу — та же 1.7 × масштаб, что и в EnemySpawner (bodyReach).
local function bodyReach(enemy)
	return 1.7 * (enemy:GetAttribute("Scale") or 1)
end

local function hpShare(enemy)
	local hp, maxHp = enemy:GetAttribute("HP"), enemy:GetAttribute("MaxHP")
	if not hp or not maxHp or maxHp <= 0 then
		return 1
	end
	return hp / maxHp
end

-- Центр группы своих вокруг точки (кроме тех, кого отсеет skip), или nil.
local function groupCenter(position, radius, except, accept)
	local sum, count = Vector3.zero, 0
	for _, other in Sense.enemiesAround(position, radius, except) do
		if not other:GetAttribute("Flying") then
			local data = Sense.dataOf(other)
			if data and accept(other, data) then
				sum += other:GetPivot().Position
				count += 1
			end
		end
	end
	if count == 0 then
		return nil, 0
	end
	return sum / count, count
end

-- Точка позади группы — по ту сторону от ближайшей турели. Там держатся Медик
-- («за спинами работяг») и Кукольник: свои между ними и огнём.
local function behind(center, keep, fallbackFrom)
	local turret = Sense.nearestTurret(center)
	local back = turret and flat(center - turret:GetPivot().Position) or flat(center - fallbackFrom)
	if back.Magnitude < 1e-3 then
		return Sense.onFloor(center)
	end
	local spot = center + back.Unit * keep
	if Sense.standable(spot) then
		return Sense.onFloor(spot)
	end
	return Sense.onFloor(center)
end

-- Первая постройка на прямой между точками (по клеткам сетки), или nil.
local function firstBlocker(from, to)
	local delta = flat(to - from)
	local length = delta.Magnitude
	if length < 1e-3 then
		return nil
	end
	local stepLength = Grid.CellSize
	for i = 1, math.floor(length / stepLength) do
		local point = from + delta.Unit * (i * stepLength)
		local cx, cz = Grid.ToCell(point)
		local blocker = Grid.GetBlocker(cx, cz)
		if blocker then
			return blocker, point, i * stepLength
		end
	end
	return nil
end

-- ============================ Разведчики ============================

-- «Разведчики ищут лабораторию. Нашли — грызут стол.» Нашёл тот, кто подошёл к столу
-- ближе sight; дальше он докладывает колонии (Sense.ReportLab). Сам маршрут — блуждание
-- или прямой путь — выбирает EnemyBehavior.Goal по тому, знает ли жук, где стол.
TRAITS.explores = function(enemy, enemyData, state)
	local plan = Sense.rules(enemyData.caste).explore
	if not plan then
		return
	end
	local knew = state.found or Sense.LabKnown()
	while alive(enemy) do
		if not naps(enemy, 0.5) then
			return
		end
		if not state.found and LabTable.IsAlive()
			and distance(enemy:GetPivot().Position, LabTable.Position()) <= plan.sight then
			state.found = true
			Sense.ReportLab(plan.report)
		end
		local knows = state.found or Sense.LabKnown()
		if knows ~= knew then
			knew = knows
			state.repath = true -- блуждание кончилось: маршрут к столу напрямую
		end
		if knows then
			return
		end
	end
end

-- ============================ Строитель ============================
--
-- «Толстый. Ест обломки стены или мебели. Из собранного строит на карте.»
--   • ест — значит идёт к куче: детали разрушенных турелей и руины в радиусе forage;
--   • набрав needMaterial, строит то, что нужно колонии прямо здесь:
--       Пандус — к стене игрока, в которую упёрлись свои (её кто-то грызёт), иначе к ближней;
--       Кормушку — если вокруг трое и больше раненых;
--       Стену — поперёк огня ближней турели, перед теми, кто прячется: «жуки за ней
--       группируются безопасно»;
--   • после постройки роет ямку там, где стоял.
local function pileNear(position, radius)
	local piece = TowerDebris.NearestMaterial(position, radius)
	local ruin = EnemyStructures.NearestMaterial(position, radius)
	if piece and ruin then
		return distance(piece, position) <= distance(ruin, position) and piece or ruin
	end
	return piece or ruin
end

local function rampTarget(at, reach)
	local best, bestDistance = nil, reach
	-- Стена, которую грызут свои, — первой: пандус к ней снимает затор колонии.
	for chewer, building in Sense.chewing do
		if building.Parent and alive(chewer) and Sense.isWall(building) and not building:GetAttribute("Ramped") then
			local d = distance(building:GetPivot().Position, at)
			if d <= bestDistance then
				best, bestDistance = building, d
			end
		end
	end
	if best then
		return best
	end
	for _, tower in towersFolder:GetChildren() do
		if Sense.isWall(tower) and not tower:GetAttribute("Ramped") then
			local d = distance(tower:GetPivot().Position, at)
			if d <= bestDistance then
				best, bestDistance = tower, d
			end
		end
	end
	return best
end

TRAITS.builds = function(enemy, enemyData, state)
	local plan = enemyData.builds
	local stock = 0
	local restUntil = 0

	while alive(enemy) do
		if not naps(enemy, 0.5) then
			return
		end

		local at = enemy:GetPivot().Position
		local now = os.clock()

		if stock < plan.needMaterial then
			-- «Ест обломки стены или мебели.» Детали турелей — первыми, руины следом.
			if TowerDebris.Consume(at, plan.eat) or EnemyStructures.TakeMaterial(at, plan.eat) then
				stock += 1
				Sense.ClearGoTo(state, "forage")
			elseif now >= restUntil then
				if Sense.GoToFailed(state, "forage") then
					-- Куча за стеной, дойти нельзя: не ломится в неё каждые полсекунды.
					Sense.ClearGoTo(state, "forage")
					restUntil = now + plan.rest
				else
					local pile = pileNear(at, plan.forage)
					if pile then
						Sense.GoTo(state, Sense.onFloor(pile), plan.eat * 0.5, "forage", 2)
					else
						Sense.ClearGoTo(state, "forage")
					end
				end
			end
		else
			Sense.ClearGoTo(state, "forage")
			state.holdUntil = now + plan.work -- строит, стоя на месте
			if not naps(enemy, plan.work) then
				return
			end
			at = enemy:GetPivot().Position

			local wounded = 0
			for _, other in Sense.enemiesAround(at, plan.feederRadius, enemy) do
				if hpShare(other) < plan.woundedBelow then
					wounded += 1
				end
			end

			local ramp = rampTarget(at, plan.rampReach)
			if ramp then
				EnemyStructures.Ramp(ramp)
			elseif wounded >= plan.feederWounded then
				EnemyStructures.Feeder(at)
			else
				-- Стена ставится ПОПЕРЁК направления на ближайшую турель — только так
				-- она закрывает линию огня, а не стоит вдоль неё. Встаёт перед теми, кто
				-- прячется (если такие рядом), иначе перед самим Строителем.
				local hidden = groupCenter(at, plan.coverFor, enemy, function(other)
					local otherState = Sense.states[other]
					return otherState ~= nil and otherState.hiding == true
				end)
				local base = hidden or at
				local turret = Sense.nearestTurret(base)
				local facing = turret and flat(turret:GetPivot().Position - base) or Vector3.zAxis
				if facing.Magnitude < 1e-3 then
					facing = Vector3.zAxis
				end
				EnemyStructures.Wall(base + facing.Unit * plan.wallGap, facing.Unit)
			end

			-- Ямка: роет там, где стоял при стройке, — у самой постройки, а у стены —
			-- за ней, с той стороны, куда турель не видит. Убит за работой — ямки нет.
			local pit = plan.pit
			if pit then
				state.holdUntil = os.clock() + pit.time
				if not naps(enemy, pit.time) then
					return
				end
				ConcreteFloor.Shape(enemy:GetPivot().Position, pit.radius, -pit.depth,
					{ tag = "trench", core = pit.core })
			end

			stock -= plan.needMaterial
			if not naps(enemy, plan.interval) then
				return
			end
		end
	end
end

-- ============================ Кислотник ============================
--
-- «Не разрушает. Плюёт кислоту на стену. Стена размягчается. Работяги разрушают
-- размягчённую стену в разы быстрее.»
--   • плюёт туда, где от этого толк: в постройку, которую уже грызут работяги рядом;
--     нет такой — в ту, в которую упёрся сам, нет и её — в ближнюю в радиусе плевка;
--   • не плюёт в ещё мягкую стену — ищет другую, сухую;
--   • до далёкой стены подходит на дистанцию плевка;
--   • плюя, останавливается и смотрит на стену aim секунд — его в этот миг легко снять.
-- Сам эффект — атрибут SoftenedUntil на постройке: грызня читает его сама (EnemySpawner).
local function spitTarget(enemy, plan, state)
	local at = enemy:GetPivot().Position
	local now = os.clock()
	local function score(building)
		local d = distance(building:GetPivot().Position, at)
		local wet = now < (building:GetAttribute("SoftenedUntil") or 0) - plan.refresh
		return d + (wet and plan.follow or 0)
	end

	local mine = Sense.dataOf(enemy)
	local myCaste = mine and mine.caste
	local best, bestScore = nil, plan.follow
	for chewer, building in Sense.chewing do
		if building.Parent and chewer ~= enemy and alive(chewer) then
			local data = Sense.dataOf(chewer)
			if data and data.caste == myCaste then
				local s = score(building)
				if s < bestScore then
					best, bestScore = building, s
				end
			end
		end
	end
	if best then
		return best
	end
	if state.blocker and state.blocker.Parent then
		return state.blocker
	end
	for _, tower in towersFolder:GetChildren() do
		local s = score(tower)
		if distance(tower:GetPivot().Position, at) <= plan.range and s < bestScore then
			best, bestScore = tower, s
		end
	end
	return best
end

TRAITS.spits = function(enemy, enemyData, state)
	local plan = enemyData.spits
	local ready = os.clock() + plan.interval * 0.5

	while alive(enemy) do
		if not naps(enemy, 0.25) then
			return
		end
		local now = os.clock()
		local at = enemy:GetPivot().Position
		local target = spitTarget(enemy, plan, state)

		if not target then
			Sense.ClearGoTo(state, "spit")
		else
			local where = target:GetPivot().Position
			local d = distance(where, at)
			if d > plan.range then
				local back = flat(at - where)
				local spot = back.Magnitude > 1e-3 and where + back.Unit * (plan.range - 3) or at
				Sense.GoTo(state, Sense.onFloor(spot), 3, "spit", 2)
			else
				Sense.ClearGoTo(state, "spit")
				local wet = now < (target:GetAttribute("SoftenedUntil") or 0) - plan.refresh
				if now >= ready and not wet then
					state.holdUntil = now + plan.aim
					state.face = flat(where - at).Magnitude > 1e-3 and flat(where - at).Unit or nil
					if not naps(enemy, plan.aim) then
						return
					end
					state.face = nil
					if target.Parent then
						target:SetAttribute("SoftenedUntil", os.clock() + plan.duration)
						target:SetAttribute("Softens", plan.softens)
						print(("[Кислотник] размягчил %s на %.0f сек — грызётся в %d раза быстрее")
							:format(target.Name, plan.duration, plan.softens))
					end
					ready = os.clock() + plan.interval
				end
			end
		end
	end
end

-- ============================ Медик ============================

-- Кто несёт этого жука, или nil. EnemySpawner по нему не ведёт груз сам.
function EnemyTraits.CarriedBy(enemy)
	return carried[enemy]
end

-- «Переносит личинок и раненых.» Носит только своих — разведчиков и работяг,
-- и только тех, кто ходит по земле; солдаты «самостоятельны», им медик не нужен.
-- Раненый — тот, кто ещё пугается (слепой Хмурый брон медика не ждёт).
local function canCarry(other, plan)
	if carried[other] then
		return false
	end
	local data = Sense.dataOf(other)
	if not data or data.flying or data.heals or (data.caste or 0) > 1 then
		return false
	end
	if data.hatches then
		return true
	end
	if not data.panic then
		return false
	end
	return hpShare(other) < plan.carryBelow
end

-- Несёт груз на спине прочь от турели, пока не выйдет срок, потом кладёт на пол.
-- Убили медика — груз падает, где был; убили груз — медик идёт дальше налегке.
local function carry(enemy, cargo, plan, state, turret)
	local pivot = cargo:GetPivot()
	-- Насколько пивот груза выше пола — чтобы положить его обратно на ту же высоту.
	local lift = pivot.Position.Y - ConcreteFloor.HeightAt(pivot.Position.X, pivot.Position.Z)

	carried[cargo] = enemy
	Crowd.Remove(cargo)
	state.carrying = cargo
	state.fleeFrom = turret:GetPivot().Position
	print(("[Медик] уносит %s от %s"):format(cargo.Name, turret.Name))

	local untilTime = os.clock() + plan.carryTime
	while alive(enemy) and alive(cargo) and os.clock() < untilTime do
		cargo:PivotTo(enemy:GetPivot() * CFrame.new(0, plan.carryLift, 0))
		RunService.Heartbeat:Wait()
	end

	carried[cargo] = nil
	state.carrying = nil
	if cargo.Parent then
		local at = cargo:GetPivot().Position
		local drop = Vector3.new(at.X, ConcreteFloor.HeightAt(at.X, at.Z) + lift, at.Z)
		drop = Crowd.FindFree(cargo, drop) or drop
		cargo:PivotTo(CFrame.new(drop) * cargo:GetPivot().Rotation)
		if alive(cargo) then
			Crowd.Add(cargo)
		end
	end
end

-- «Выбирает зоны для лечения... он за спинами работяг.» Зона — центр раненых вокруг
-- (тяжелее ранен — сильнее тянет), место медика — позади неё, по ту сторону от огня.
-- Раненых нет — держится за спинами группы работяг. Нет и группы — идёт с волной.
local function medicPosition(enemy, enemyData, state)
	local plan = enemyData.heals
	while alive(enemy) do
		if not naps(enemy, plan.reposition) then
			return
		end
		local at = enemy:GetPivot().Position
		local sum, weight = Vector3.zero, 0
		for _, other in Sense.enemiesAround(at, plan.zone, enemy) do
			if not other:GetAttribute("Flying") then
				local hp, maxHp = other:GetAttribute("HP") or 0, other:GetAttribute("MaxHP") or 0
				local missing = maxHp - hp
				if missing > maxHp * plan.zoneBelow then
					sum += other:GetPivot().Position * missing
					weight += missing
				end
			end
		end

		local center = weight > 0 and sum / weight or nil
		if not center then
			center = groupCenter(at, plan.zone, enemy, function(_, data)
				return data.caste == 1 and not data.heals
			end)
		end

		if center then
			Sense.GoTo(state, behind(center, plan.keepBehind, at), 3, "medic", 1)
		else
			Sense.ClearGoTo(state, "medic")
		end
	end
end

-- Медик: лечит раненых вокруг и уносит из-под огня личинок и тяжело раненых.
-- Сам не атакует вовсе (chewDamage = 0 в таблице).
TRAITS.heals = function(enemy, enemyData, state)
	local plan = enemyData.heals
	task.spawn(medicPosition, enemy, enemyData, state)

	while alive(enemy) do
		if not naps(enemy, plan.interval) then
			return
		end

		local at = enemy:GetPivot().Position

		-- Подобрать груз, если руки свободны и есть от чего уносить. Несёт отдельной
		-- задачей: груз ставится каждый кадр, а лечение идёт своим темпом.
		if not state.carrying then
			local turret = Sense.nearestTurret(at)
			if turret then
				for _, other in Sense.enemiesAround(at, plan.reach, enemy) do
					if canCarry(other, plan) then
						task.spawn(carry, enemy, other, plan, state, turret)
						break
					end
				end
			end
		end
		-- Лечит самого раненого в радиусе, а не всех понемногу.
		local best, bestRatio = nil, 1
		for _, other in Sense.enemiesAround(at, plan.radius, enemy) do
			local ratio = hpShare(other)
			if ratio < bestRatio then
				best, bestRatio = other, ratio
			end
		end

		if best then
			local hp, maxHp = best:GetAttribute("HP"), best:GetAttribute("MaxHP")
			best:SetAttribute("HP", math.min(maxHp, hp + plan.amount))
		end
	end
end

-- ============================ Подрывник ============================
--
-- «Несёт взрывной заряд. Подходит к стене, активирует. Стена получает множество урона.
-- Сам уничтожается вместе с зарядом. Попадание в заряд — преждевременная детонация.»
--   • маршрут ему считается так, будто стены для него почти не преграда (routeChewDps):
--     он не обходит лабиринт, а идёт к ближней стене на пути — заряд её снесёт;
--   • упёрся — стоит arm секунд и взводит заряд; любое попадание в это окно рвёт заряд
--     сразу (EnemyBehavior.Damaged), смерть от урона — тоже;
--   • взрыв задевает заряды других Подрывников рядом — они рвутся следом цепочкой.
TRAITS.charge = function(enemy, enemyData, state)
	local plan = enemyData.charge

	while alive(enemy) do
		if not naps(enemy, 0.25) then
			return
		end

		-- Грызть он не умеет, поэтому признак «упёрся» у него тот же, что и у всех:
		-- атрибут Chewing, который ставит общий цикл движения.
		if enemy:GetAttribute("Chewing") then
			print("[Подрывник] активировал заряд")
			state.arming = true
			state.holdUntil = os.clock() + plan.arm
			if not naps(enemy, plan.arm) then
				return -- успели снять во время активации — взрыв сделает ветка смерти
			end
			EnemyTraits.Detonate(enemy, enemyData)
			return
		end
	end
end

-- Сколько от точки взрыва до постройки: до края её следа (Grid.DistanceTo), а не до пивота.
-- След Мортиры — квадрат в 26 студов: заряд, взорванный вплотную к её краю, по пивоту
-- был за радиусом и не наносил ей ничего. Постройки вне сетки — по пивоту, как раньше.
local function towerDistance(tower, at)
	return Grid.DistanceTo(tower, at) or (tower:GetPivot().Position - at).Magnitude
end

-- Взрыв заряда. Зовётся и по активации у стены, и по смерти, и по попаданию во время
-- активации — «попадание в заряд — преждевременная детонация». Разница только в том,
-- где он в этот момент стоит, а это и есть цена раннего выстрела по нему.
function EnemyTraits.Detonate(enemy, enemyData)
	local plan = enemyData.charge
	if not plan or enemy:GetAttribute("Detonated") then
		return
	end
	enemy:SetAttribute("Detonated", true)

	local at = enemy:GetPivot().Position
	ExplosionRemote:FireAllClients(at, plan.radius)

	local hits = 0
	for _, tower in towersFolder:GetChildren() do
		if towerDistance(tower, at) <= plan.radius then
			local hp = tower:GetAttribute("HP") or 0
			tower:SetAttribute("HP", math.max(0, hp - plan.damage))
			DamageDealtRemote:FireAllClients(tower:GetPivot().Position, math.min(hp, plan.damage), false)
			hits += 1
		end
	end

	-- Стол тоже в радиусе: для заряда он такое же препятствие, как стена.
	if LabTable.DistanceTo(at) <= plan.radius then
		LabTable.Bite(plan.damage)
		hits += 1
	end
	hits += LabStations.Blast(at, plan.radius, plan.damage)

	EnemyStructures.Blast(at, plan.radius, plan.damage)

	print(("[Подрывник] взрыв: %d урона по %d целям в радиусе %.0f")
		:format(plan.damage, hits, plan.radius))

	-- Цепочка: взрыв задевает заряды соседних Подрывников. Чуть позже, а не в этом же
	-- кадре: так цепочка читается волной, а не одним хлопком.
	if plan.chain then
		for _, other in Sense.enemiesAround(at, plan.radius, enemy) do
			local otherData = Sense.dataOf(other)
			if otherData and otherData.charge and not other:GetAttribute("Detonated") then
				task.delay(plan.chain, function()
					if other.Parent then
						EnemyTraits.Detonate(other, otherData)
					end
				end)
			end
		end
	end

	if enemy.Parent then
		Effects.MarkHit(enemy, nil) -- подорвал себя сам: тело
		enemy:SetAttribute("HP", 0)
	end
end

-- ============================ Щитоносец ============================
--
-- «Несёт широкий лобовой щит. Закрывает не только себя, но и идущих сзади. Турель стреляет
-- в щит — эффект минимальный. За ним идут работяги без огня. Перекрёстный огонь обходит щит.»
--   • щит — сектор спереди (атрибуты читает Effects.ApplyArmor);
--   • прикрывает тех, кто идёт сзади в пределах cover;
--   • поворачивается щитом к ближней турели впереди (face): идёт к цели, но держит
--     щит к огню. Турель сзади или сбоку — не довернуться, и там он открыт;
--   • за ним строятся работяги (поле escort, общая механика вожака ниже).
TRAITS.shield = function(enemy, enemyData, state)
	local plan = enemyData.shield
	enemy:SetAttribute("ShieldArc", plan.arc)
	enemy:SetAttribute("ShieldReduction", plan.reduction)
	local braceCos = math.cos(math.rad(plan.braceArc))

	while alive(enemy) do
		if not naps(enemy, 0.25) then
			return
		end

		local pivot = enemy:GetPivot()
		local position = pivot.Position

		-- Сзади — против взгляда: голова смотрит по -LookVector (кадр довёрнут на 180°),
		-- значит тень от щита падает по +LookVector. Метка ставится со сроком и истекает
		-- сама — так смерть Щитоносца мгновенно снимает прикрытие без списка подопечных.
		local back = flat(pivot.LookVector)
		if back.Magnitude > 1e-3 then
			back = back.Unit
			for _, other in Sense.enemiesAround(position, plan.cover, enemy) do
				local toOther = flat(other:GetPivot().Position - position)
				if toOther.Magnitude > 1e-3 and toOther.Unit:Dot(back) > 0.3 then
					other:SetAttribute("CoveredUntil", os.clock() + 0.5)
					other:SetAttribute("CoverReduction", plan.reduction)
				end
			end
		end

		-- Щит к огню: ближняя турель в радиусе face и не за спиной — смотрит на неё.
		local turret, d = Sense.nearestTurret(position)
		local face = nil
		if turret and d <= plan.face then
			local toTurret = flat(turret:GetPivot().Position - position)
			local velocity = enemy:GetAttribute("Velocity") or Vector3.zero
			local going = flat(velocity).Magnitude > 0.5 and flat(velocity).Unit or ahead(enemy)
			if toTurret.Magnitude > 1e-3 and toTurret.Unit:Dot(going) >= braceCos then
				face = toTurret.Unit
			end
		end
		state.face = face
	end
end

-- ============================ Вожак ============================
--
-- Общая механика тех, за кем идут другие: «за ним идут работяги без огня» (Щитоносец),
-- «за ним идут мелкие» (Гигант). Вожак раз в полсекунды зовёт подходящих соседей встать
-- позади себя веером; заявка у них слабая и со сроком — паника, укрытие, своя турель
-- её перебивают, а смерть вожака гасит сама.
local function follows(plan, other, data)
	if data.escort or data.flying then
		return false
	end
	local key = other:GetAttribute("Type")
	if plan.who and plan.who[key] then
		return true
	end
	return plan.castes ~= nil and plan.castes[data.caste or -1] == true
end

TRAITS.escort = function(enemy, enemyData, state)
	local plan = enemyData.escort

	while alive(enemy) do
		if not naps(enemy, 0.5) then
			return
		end
		local position = enemy:GetPivot().Position
		local forward = ahead(enemy)
		local side = Vector3.new(-forward.Z, 0, forward.X)
		local back = position - forward * plan.behind
		local now = os.clock()

		-- Вожак дошёл до дела (грызёт преграду, стоит у стола) — свиту больше не держит:
		-- её заявки истекут сами, и каждый возьмётся за своё, а не будет ждать за спиной.
		local busy = enemy:GetAttribute("Chewing")
			or (LabTable.IsAlive() and distance(position, LabTable.Position()) <= LabTable.REACH + bodyReach(enemy) + 2)

		for _, other in (busy and {} or Sense.enemiesAround(position, plan.radius, enemy)) do
			local data = Sense.dataOf(other)
			local otherState = Sense.states[other]
			if data and otherState and follows(plan, other, data)
				and not otherState.regrouping and not otherState.carrying and not carried[other]
				and not otherState.focusTurret and not otherState.ally
				and not (otherState.panicUntil and now < otherState.panicUntil) then
				-- Веер: каждый встаёт со своим боковым сдвигом (по своему seed),
				-- иначе вся свита ломилась бы в одну точку за спиной вожака.
				local fan = ((otherState.seed or 0) / (math.pi * 2)) * 2 - 1
				local spot = back + side * fan * plan.spread
				if Sense.standable(spot) then
					Sense.GoTo(otherState, Sense.onFloor(spot), plan.close, "follow", 1, now + plan.hold)
				end
			end
		end
	end
end

-- ============================ Координатор ============================
--
-- «Не трогает стены. Указывает солдатам какую турель атаковать. Без координатора солдаты
-- идут каждый на ближайшую. С координатором — все на одну. Уничтожить координатора —
-- солдаты теряют фокус.»
--   • выбирает самую побитую турель в радиусе приказа — её снесут быстрее всего;
--     при равной побитости — ближнюю;
--   • приказ — всем солдатам вокруг, кроме тех, кто «мимо всего» (ignoresOrders);
--   • сам держится поодаль: у края радиуса огня цели, на линии между ней и собой;
--   • приказ ставится со сроком: убили координатора — он истекает, и солдаты на миг
--     теряются (EnemyBehavior: lostFocus у касты солдат).
local function weakestTurret(position, radius)
	local best, bestScore = nil, math.huge
	for _, tower in towersFolder:GetChildren() do
		if Sense.isTurret(tower) then
			local d = distance(tower:GetPivot().Position, position)
			if d <= radius then
				local hp, maxHp = tower:GetAttribute("HP") or 0, tower:GetAttribute("MaxHP") or 1
				local score = hp / math.max(maxHp, 1) + d / radius * 0.25
				if score < bestScore then
					best, bestScore = tower, score
				end
			end
		end
	end
	return best or Sense.nearestTurret(position)
end

TRAITS.commands = function(enemy, enemyData, state)
	local plan = enemyData.commands

	while alive(enemy) do
		if not naps(enemy, plan.interval) then
			return
		end

		local at = enemy:GetPivot().Position
		local turret = weakestTurret(at, plan.radius)
		if turret then
			-- Срок вдвое больше шага: пока Координатор жив, он его продлевает; убили его —
			-- фокус истекает сам, без единого списка подопечных.
			local expires = os.clock() + plan.interval * 2
			local ordered = 0
			for _, other in Sense.enemiesAround(at, plan.radius, enemy) do
				local otherData = Sense.dataOf(other)
				if otherData and otherData.caste == 2 and not otherData.ignoresOrders and not otherData.commands then
					Sense.focus[other] = { turret = turret, expires = expires, by = enemy }
					ordered += 1
				end
			end

			-- Поодаль держится, только пока есть кем командовать: без солдат он идёт к столу,
			-- как все, — иначе встал бы за краем огня навсегда, и волна не кончилась бы.
			local from = turret:GetPivot().Position
			local away = flat(at - from)
			if ordered == 0 then
				Sense.ClearGoTo(state, "command")
			elseif away.Magnitude > 1e-3 then
				local keep = math.clamp(Sense.turretRange(turret) + plan.standoff, plan.keepMin, plan.keepMax)
				local spot = from + away.Unit * keep
				if Sense.standable(spot) then
					Sense.GoTo(state, Sense.onFloor(spot), 3, "command", 2)
				end
			end
		else
			Sense.ClearGoTo(state, "command")
		end
	end
end

-- ============================ Таран ============================
--
-- «Тяжёлый. Долго нацеливается. Разгоняется по прямой. Проламывает препятствия. На разгоне
-- не поворачивает. После столкновения оглушается. Смещённые стены и повороты — контр.»
--   • цель тарана — своя турель (если он на неё вышел), иначе стол, иначе точка впереди
--     по маршруту; бьёт он то, что стоит на прямой между ним и целью;
--   • разгон нужен: удар тем сильнее, чем больше скорость в момент столкновения, а
--     скорость набирается с ходу (accel). Короткий разбег — слабый удар (не ниже minImpact);
--   • разбег короче minRun он не начинает вовсе — идёт и грызёт, как все. Отсюда контр:
--     стены со смещением и повороты не дают ему прямой;
--   • нацеливаясь, стоит windup секунд и разворачивается к цели — его видно заранее;
--   • направление фиксируется перед разгоном и больше не меняется.
local function ramAim(enemy, enemyData, state, plan)
	local position = state.pathPosition or enemy:GetPivot().Position

	local target = nil
	local focus = state.focusTurret
	if focus and focus.Parent and distance(focus:GetPivot().Position, position) <= plan.aim then
		target = focus:GetPivot().Position
	elseif LabTable.IsAlive() and distance(LabTable.Position(), position) <= plan.aim then
		target = LabTable.Position()
	elseif state.points and state.index then
		-- Точка на маршруте на дистанции разгона впереди.
		local points, index = state.points, state.index
		local travelled = 0
		local last = position
		for i = index, #points do
			travelled += distance(points[i], last)
			last = points[i]
			if travelled >= plan.aim then
				break
			end
		end
		target = last
	end
	if not target then
		return nil
	end

	local blocker, hitPoint, run = firstBlocker(position, target)
	if blocker then
		if run >= plan.minRun then
			return flat(hitPoint - position).Unit, run
		end
		return nil
	end
	-- Прямая до цели свободна: таранить стоит только турель или стол — по точке маршрута
	-- он и так дойдёт ногами.
	local direct = flat(target - position)
	if direct.Magnitude >= plan.minRun and (target == LabTable.Position()
		or (focus and focus.Parent and target == focus:GetPivot().Position)) then
		return direct.Unit, direct.Magnitude
	end
	return nil
end

TRAITS.rams = function(enemy, enemyData, state)
	local plan = enemyData.rams
	local ready = os.clock() + plan.cooldown * 0.5

	while alive(enemy) do
		if not naps(enemy, 0.25) then
			return
		end
		local now = os.clock()
		local stunned = now < (enemy:GetAttribute("StunnedUntil") or 0)
		if now >= ready and not state.dash and not stunned and not state.regrouping then
			local direction, run = ramAim(enemy, enemyData, state, plan)
			if direction then
				-- Нацеливание: стоит и разворачивается туда, куда пойдёт.
				state.holdUntil = now + plan.windup
				state.face = direction
				print("[Таран] нацеливается")
				if not naps(enemy, plan.windup) then
					return
				end
				state.face = nil

				-- Направление фиксируется здесь и больше не меняется — в этом весь контр:
				-- смещённые стены и повороты выводят разгон в пустоту.
				state.dash = {
					direction = direction,
					left = math.min(run + plan.overshoot, plan.distance),
					speed = enemyData.speed,
					walk = enemyData.speed,
					top = plan.speed,
					accel = plan.accel,
					damage = plan.damage,
					minImpact = plan.minImpact,
					stun = plan.stun,
				}
				state.holdUntil = nil

				-- Ждём, пока разгон отработает в общем цикле движения (см. EnemySpawner).
				while alive(enemy) and state.dash do
					if not naps(enemy, 0.1) then
						return
					end
				end
				ready = os.clock() + plan.cooldown
			end
		end
	end
end

-- ============================ Разносчик ============================
--
-- «Впитывает элементы которыми в него стреляют. Накапливает. Взрывается впитанными
-- элементами. Может впитать несколько элементов.»
--   • впитывает до capacity РАЗНЫХ элементов: первый попавший занимает ячейку;
--   • часть каждого удара впитанным элементом (soak) уходит не в тело, а в заряд —
--     Effects снимает её ДО брони (свойство жука, как щит);
--   • элемент, которому места не хватило, бьёт его в полную силу и в заряд не идёт;
--   • взрывается накопленным на смерти — и сам, если дошёл до лаборатории с зарядом:
--     «разносит» впитанное прямо в стол.
local absorbed = setmetatable({}, { __mode = "k" })

TRAITS.absorbs = function(enemy, enemyData, state)
	local plan = enemyData.absorbs
	enemy:SetAttribute("Absorbs", plan.capacity)

	while alive(enemy) do
		if not naps(enemy, 0.5) then
			return
		end
		local store = absorbed[enemy]
		if store and store.charge >= plan.atTable and LabTable.IsAlive()
			and distance(enemy:GetPivot().Position, LabTable.Position()) <= LabTable.REACH + bodyReach(enemy) + 1 then
			print("[Разносчик] дошёл до лаборатории и взрывается впитанным")
			Effects.MarkHit(enemy, nil)
			enemy:SetAttribute("HP", 0) -- сам взрыв сделает ветка смерти (Burst)
			return
		end
	end
end

-- Впитать элемент. Зовётся из Effects при каждом ударе элементом, ДО брони. Возвращает,
-- сколько урона ушло в заряд (его Effects и вычтет из удара).
function EnemyTraits.Absorb(enemy, elementKey, damage)
	local data = Sense.dataOf(enemy)
	local plan = data and data.absorbs
	if not plan or damage <= 0 then
		return 0
	end

	local store = absorbed[enemy]
	if not store then
		store = { keys = {}, count = 0, charge = 0 }
		absorbed[enemy] = store
	end

	-- «Может впитать несколько элементов» — счёт по РАЗНЫМ элементам, а не по выстрелам:
	-- иначе любая очередь из одной турели мгновенно забивала бы ему всю ёмкость.
	if not store.keys[elementKey] then
		if store.count >= plan.capacity then
			return 0
		end
		store.keys[elementKey] = true
		store.count += 1
	end
	local soaked = damage * plan.soak
	store.charge += soaked
	return soaked
end

-- Взрыв впитанным. Зовётся по смерти из EnemySpawner.
function EnemyTraits.Burst(enemy, enemyData)
	local plan = enemyData.absorbs
	local store = absorbed[enemy]
	if not plan or not store or store.charge <= 0 then
		return
	end

	local at = enemy:GetPivot().Position
	local amount = math.floor(store.charge * plan.share + 0.5)
	store.charge = 0
	ExplosionRemote:FireAllClients(at, plan.radius)

	local names = {}
	for key in store.keys do
		local data = Elements[key]
		table.insert(names, data and data.name or key)
	end

	for _, tower in towersFolder:GetChildren() do
		if towerDistance(tower, at) <= plan.radius then
			local hp = tower:GetAttribute("HP") or 0
			tower:SetAttribute("HP", math.max(0, hp - amount))
			DamageDealtRemote:FireAllClients(tower:GetPivot().Position, math.min(hp, amount), false)
		end
	end

	if LabTable.DistanceTo(at) <= plan.radius then
		LabTable.Bite(amount)
	end
	LabStations.Blast(at, plan.radius, amount)

	EnemyStructures.Blast(at, plan.radius, amount)

	print(("[Разносчик] взрывается впитанным (%s): %d урона в радиусе %.0f")
		:format(#names > 0 and table.concat(names, ", ") or "ничего", amount, plan.radius))
end

-- ============================ Эволюционер ============================
--
-- «Адаптируется к самому эффективному оружию игрока. Если игрок использует преимущественно
-- огонь — эволюционер становится устойчивым к огню. Игрок вынужден менять тактику.»
--   • «самое эффективное» он узнаёт из двух источников: что больше всего ранило ЕГО
--     самого (своя шкура, вес personal) и чем игрок больше всего бьёт за весь забег
--     (память колонии, Effects.ElementUsage);
--   • привычка растёт, пока игрок бьёт тем же: начинает со start (или known, если это
--     и есть главное оружие игрока за забег — колония к нему уже готова) и прибавляет step
--     каждую проверку до resistance;
--   • игрок сменил оружие — эволюционер линяет: molt секунд стоит без всякой привычки,
--     потом привыкает заново, уже к новому. Смена тактики окупается, но не навсегда;
--   • своя память выветривается (fade): старые попадания весят меньше новых.
local learned = setmetatable({}, { __mode = "k" })

function EnemyTraits.ElementHit(enemy, elementKey, damage)
	local memory = learned[enemy]
	if not memory then
		memory = {}
		learned[enemy] = memory
	end
	memory[elementKey] = (memory[elementKey] or 0) + damage
end

local function shares(source)
	local total = 0
	for _, amount in source do
		total += amount
	end
	return total
end

TRAITS.evolves = function(enemy, enemyData, state)
	local plan = enemyData.evolves
	enemy:SetAttribute("Learns", true)
	local current, resist = nil, 0

	while alive(enemy) do
		if not naps(enemy, plan.recheck) then
			return
		end

		local memory = learned[enemy] or {}
		local own, run = shares(memory), shares(Effects.ElementUsage)
		local globalTop, globalAmount = nil, 0
		for key, amount in Effects.ElementUsage do
			if amount > globalAmount then
				globalTop, globalAmount = key, amount
			end
		end

		local best, bestScore = nil, 0
		local candidates = {}
		for key in memory do
			candidates[key] = true
		end
		for key in Effects.ElementUsage do
			candidates[key] = true
		end
		for key in candidates do
			local score = (own > 0 and (memory[key] or 0) / own or 0) * plan.personal
				+ (run > 0 and (Effects.ElementUsage[key] or 0) / run or 0) * (1 - plan.personal)
			if score > bestScore then
				best, bestScore = key, score
			end
		end

		if best and best == current then
			resist = math.min(plan.resistance, resist + plan.step)
			enemy:SetAttribute("ResistShare", resist)
		elseif best then
			-- Линька: между старой и новой привычкой — окно без защиты, и он стоит.
			enemy:SetAttribute("ResistElement", nil)
			enemy:SetAttribute("ResistShare", nil)
			state.holdUntil = os.clock() + plan.molt
			print(("[Эволюционер] линяет: привыкает к %s"):format(best))
			if not naps(enemy, plan.molt) then
				return
			end
			current = best
			resist = best == globalTop and plan.known or plan.start
			enemy:SetAttribute("ResistElement", best)
			enemy:SetAttribute("ResistShare", resist)
		end

		for key, amount in memory do
			memory[key] = amount * plan.fade
		end
	end
end

-- ============================ Носитель ============================
--
-- «Несёт внутри других жуков. Уничтожен — жуки высыпаются. Если добрался до лаборатории —
-- выпускает внутри обороны.» Выпущенные у стола выходят сразу в бой; высыпавшиеся из
-- убитого — оглушены падением на daze секунд.
TRAITS.carries = function(enemy, enemyData, state)
	while alive(enemy) do
		if not naps(enemy, 0.5) then
			return
		end

		if (enemy:GetPivot().Position - LabTable.Position()).Magnitude <= LabTable.REACH + 4 then
			print("[Носитель] добрался до лаборатории и выпускает жуков внутри обороны")
			EnemyTraits.Spill(enemy, enemyData, true)
			return
		end
	end
end

function EnemyTraits.Spill(enemy, enemyData, deliberate)
	local plan = enemyData.carries
	if not plan or enemy:GetAttribute("Spilled") then
		return
	end
	enemy:SetAttribute("Spilled", true)

	local at = enemy:GetPivot().Position
	local daze = not deliberate and plan.daze or nil
	if Sense.Spawn then
		for _ = 1, plan.count do
			local offset = Vector3.new((math.random() - 0.5) * 6, 0, (math.random() - 0.5) * 6)
			Sense.Spawn(plan.type, at + offset, daze and function(bug)
				bug:SetAttribute("StunnedUntil", os.clock() + daze)
				bug:SetAttribute("Stunned", true)
			end or nil)
		end
	end
	print(("[Носитель] высыпалось %d x %s%s"):format(plan.count, plan.type, daze and " (оглушены)" or ""))
end

-- ============================ Кукольник ============================
--
-- «Заворачивает раненого жука в кокон. Через время из кокона выходит жук следующей касты.
-- Разведчик — работяга. Работяга — солдат. Нельзя оставлять раненых.»
--   • охотится: идёт к ближайшему раненому в радиусе hunt;
--   • заворачивает не мгновенно: wrap секунд стоит вплотную, а жертва замирает в его
--     лапах (Sense.carried) — убей Кукольника в это окно, и раненый уйдёт живым;
--   • раненых нет — держится позади толпы, по ту сторону от огня, и ждёт.
local function victimNear(enemy, plan)
	local at = enemy:GetPivot().Position
	local best, bestDistance = nil, plan.hunt
	for _, other in Sense.enemiesAround(at, plan.hunt, enemy) do
		local data = Sense.dataOf(other)
		if data and data.caste and data.caste < 3 and not data.flying and not carried[other]
			and hpShare(other) < plan.woundedBelow then
			local nextCaste = Enemies.ByCaste[data.caste + 1]
			if nextCaste and #nextCaste > 0 then
				local d = distance(other:GetPivot().Position, at)
				if d < bestDistance then
					best, bestDistance = other, d
				end
			end
		end
	end
	return best, bestDistance
end

TRAITS.cocoons = function(enemy, enemyData, state)
	local plan = enemyData.cocoons
	local ready = os.clock() + plan.interval * 0.5

	while alive(enemy) do
		if not naps(enemy, 0.5) then
			return
		end
		local now = os.clock()
		local victim, d = nil, math.huge
		if now >= ready then
			victim, d = victimNear(enemy, plan)
		end

		if victim then
			Sense.ClearGoTo(state, "lurk")
			local reach = bodyReach(enemy) + bodyReach(victim) + plan.margin
			if d > reach then
				Sense.GoTo(state, Sense.onFloor(victim:GetPivot().Position), reach * 0.8, "hunt", 2)
			else
				Sense.ClearGoTo(state, "hunt")
				carried[victim] = enemy -- держит: собственный цикл жертвы стоит
				local toVictim = flat(victim:GetPivot().Position - enemy:GetPivot().Position)
				state.face = toVictim.Magnitude > 1e-3 and toVictim.Unit or nil
				state.holdUntil = now + plan.wrap
				local ok = naps(enemy, plan.wrap)
				state.face = nil
				if carried[victim] == enemy then
					carried[victim] = nil
				end
				if ok and alive(victim) then
					local victimData = Sense.dataOf(victim)
					local nextCaste = victimData and Enemies.ByCaste[victimData.caste + 1]
					if nextCaste and #nextCaste > 0 then
						local hatchType = nextCaste[math.random(#nextCaste)]
						local spot = victim:GetPivot().Position
						print(("[Кукольник] завернул %s — из кокона выйдет %s"):format(victim.Name, hatchType))
						-- Сначала кокон, потом снос жука: его Destroy гасит его собственные механики.
						EnemyStructures.Cocoon(spot, hatchType, plan.hatch, plan.hp)
						victim:Destroy()
						ready = os.clock() + plan.interval
					end
				end
			end
		else
			Sense.ClearGoTo(state, "hunt")
			local at = enemy:GetPivot().Position
			local center = groupCenter(at, plan.hunt, enemy, function(_, data)
				return (data.caste or 3) < 3
			end)
			if center then
				Sense.GoTo(state, behind(center, plan.keepBehind, at), 3, "lurk", 1)
			else
				Sense.ClearGoTo(state, "lurk")
			end
		end
	end
end

-- ============================ Архитектор улья ============================
--
-- «Заменяет пол и стены хитином. На хитине жуки быстрее. Обычный ремонт невозможен.
-- Меняет карту навсегда.»
--   • стелет хитин сплошной дорожкой: новую плиту — через каждые step студов пути, а не
--     по часам, — за ним остаётся тракт для всей колонии;
--   • стены игрока, мимо которых проходит ближе coat, покрывает хитином: по такой стене
--     забегают все (как по Пандусу), а Жизнь её больше не чинит.
TRAITS.chitin = function(enemy, enemyData, state)
	local plan = enemyData.chitin
	local last = nil

	while alive(enemy) do
		if not naps(enemy, plan.interval) then
			return
		end
		local at = enemy:GetPivot().Position
		if not last or distance(at, last) >= plan.step then
			EnemyStructures.Chitin(at)
			last = at
		end
		for _, tower in towersFolder:GetChildren() do
			if Sense.isWall(tower) and not tower:GetAttribute("Chitin")
				and distance(tower:GetPivot().Position, at) <= plan.coat then
				EnemyStructures.CoatChitin(tower)
			end
		end
	end
end

-- ============================ Мимик ============================
--
-- «Маскируется под мешок, обломок или даже турель. Стоит неподвижно. Турели не распознают
-- как цель. В какой-то момент раскрывается и атакует.»
--   • засада: идёт (видимым) к турели, что ближе всех к лаборатории, — она стережёт стол, —
--     и встаёт рядом с ней;
--   • облик выбирает по месту: у турели — турель, у руин и обломков — обломок, иначе мешок;
--   • стоит, пока не выйдет терпение (patience — от и до), пока рядом не пройдёт игрок
--     (reveal) или пока его не заденет — тогда раскрывается;
--   • раскрывшись, бросается на турель засады, и первые его укусы втрое злее (ambushBite);
--   • под огнём на ходу «притворяется» — замирает мешком или обломком на playDead секунд,
--     и турели теряют цель. Не чаще раза в cooldown и только пока не тяжело ранен.
local mimicry = setmetatable({}, { __mode = "k" })

local function disguiseFor(enemy)
	local at = enemy:GetPivot().Position
	local turret, d = Sense.nearestTurret(at)
	if turret and d <= 9 then
		return "turret", turret:GetAttribute("Type")
	end
	if #EnemyStructures.Near(at, 8, "ruin") > 0 or TowerDebris.NearestMaterial(at, 8) then
		return "debris"
	end
	return "sack"
end

local function hide(enemy, state, untilTime)
	local look, towerType = disguiseFor(enemy)
	enemy:SetAttribute("Hidden", true)
	enemy:SetAttribute("DisguiseTower", towerType)
	enemy:SetAttribute("Disguise", look)
	state.holdUntil = untilTime
end

local function reveal(enemy, state)
	enemy:SetAttribute("Hidden", nil)
	enemy:SetAttribute("Disguise", nil)
	enemy:SetAttribute("DisguiseTower", nil)
	state.holdUntil = nil
end

local function playerNear(position, radius)
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and distance(root.Position, position) <= radius then
			return true
		end
	end
	return false
end

local function ambushTurret()
	if not LabTable.IsAlive() then
		return Sense.nearestTurret(LabTable.Position())
	end
	return Sense.nearestTurret(LabTable.Position())
end

local function ambushSpot(turret, plan)
	local at = turret:GetPivot().Position
	for _ = 1, 10 do
		local a = math.random() * math.pi * 2
		local r = plan.ambush[1] + math.random() * (plan.ambush[2] - plan.ambush[1])
		local spot = at + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
		if Sense.standable(spot) then
			return Sense.onFloor(spot)
		end
	end
	return nil
end

TRAITS.mimics = function(enemy, enemyData, state)
	local plan = enemyData.mimics
	local memory = { cooldownUntil = 0, phase = "sneak" }
	mimicry[enemy] = memory

	local target = ambushTurret()
	local spot = target and ambushSpot(target, plan)
	if spot then
		Sense.GoTo(state, spot, 2.5, "ambush", 3)
	end

	-- Идёт к засаде видимым. Нет турелей — подбирается к лаборатории и прячется у неё.
	while alive(enemy) do
		if not naps(enemy, 0.25) then
			return
		end
		if spot then
			if Sense.GoToReached(state, "ambush") or Sense.GoToFailed(state, "ambush")
				or not (target and target.Parent) then
				break
			end
		elseif not LabTable.IsAlive() or distance(enemy:GetPivot().Position, LabTable.Position()) <= plan.lurk then
			break
		end
	end
	if not alive(enemy) then
		return
	end
	Sense.ClearGoTo(state, "ambush")

	-- Засада: стоит неподвижно, турели его не видят.
	memory.phase = "ambush"
	memory.revealNow = false
	local patience = plan.patience[1] + math.random() * (plan.patience[2] - plan.patience[1])
	local deadline = os.clock() + patience
	hide(enemy, state, deadline)
	while alive(enemy) do
		if not naps(enemy, 0.25) then
			return
		end
		local at = enemy:GetPivot().Position
		if os.clock() >= deadline or memory.revealNow or playerNear(at, plan.reveal)
			or (target and not target.Parent) then
			break
		end
	end
	if not alive(enemy) then
		return
	end

	reveal(enemy, state)
	memory.phase = "attack"
	print("[Мимик] раскрылся и атакует")
	local victim = (target and target.Parent) and target or Sense.nearestTurret(enemy:GetPivot().Position)
	if victim then
		state.focusTurret = victim
		state.repath = true
	end
	state.biteBoost = { mult = plan.ambushBite, count = plan.ambushBites }
end

-- Удар по Мимику. В засаде — раскрывает его; на ходу — он «притворяется».
function EnemyTraits.MimicHit(enemy, enemyData, state)
	local plan = enemyData.mimics
	local memory = mimicry[enemy]
	if not plan or not memory then
		return
	end
	if memory.phase == "ambush" then
		memory.revealNow = true
		return
	end
	local now = os.clock()
	if now < memory.cooldownUntil or enemy:GetAttribute("Hidden") or hpShare(enemy) < plan.playDead.above then
		return
	end
	memory.cooldownUntil = now + plan.playDead.cooldown
	print("[Мимик] под огнём притворился")
	hide(enemy, state, now + plan.playDead.time)
	task.delay(plan.playDead.time, function()
		-- Засада могла начаться, пока он «лежал»: её не снимаем.
		if alive(enemy) and memory.phase ~= "ambush" then
			reveal(enemy, state)
		end
	end)
end

-- ============================ Тень ============================

-- Тень: турели реагируют с задержкой. Сама задержка — в Targeting; здесь только числа.
TRAITS.shadow = function(enemy, enemyData, state)
	enemy:SetAttribute("ShadowDelay", enemyData.shadow.delay)
	enemy:SetAttribute("ShadowForget", enemyData.shadow.forget)
end

-- ============================ Работяга ============================
--
-- «Могут таскать строй-материалы»: подбирает обломок рядом и несёт его к ближайшему
-- Строителю, если тот в радиусе seek, — так замыкается связка «работяга — строитель».
-- Строителя нет — несёт с собой, пока тот не появится рядом.
local function nearestBuilder(position, radius)
	local best, bestDistance = nil, radius
	for _, other in Sense.enemiesAround(position, radius) do
		local data = Sense.dataOf(other)
		if data and data.builds and not other:GetAttribute("Flying") then
			local d = distance(other:GetPivot().Position, position)
			if d < bestDistance then
				best, bestDistance = other, d
			end
		end
	end
	return best, bestDistance
end

TRAITS.carriesMaterial = function(enemy, enemyData, state)
	local plan = enemyData.carriesMaterial
	local nextPick = os.clock() + plan.every

	while alive(enemy) do
		if not naps(enemy, 0.5) then
			return
		end

		local at = enemy:GetPivot().Position
		if not state.hauling then
			if os.clock() >= nextPick then
				nextPick = os.clock() + plan.every
				-- Деталь разрушенной турели несёт на спине — её видно, пока он идёт. Руину
				-- (от Горы, от Пеликана) нести нечем: просто «взял единицу».
				local part = TowerDebris.Carry(enemy, at, plan.pick, EnemyBody.HalfHeight(enemy))
				if part then
					state.hauling = part
				elseif EnemyStructures.TakeMaterial(at, plan.pick) then
					state.hauling = true
				end
			end
		else
			local builder, d = nearestBuilder(at, plan.seek)
			if builder and d <= plan.drop then
				if typeof(state.hauling) == "Instance" then
					TowerDebris.Drop(state.hauling, builder:GetPivot().Position)
				else
					EnemyStructures.DropMaterial(builder:GetPivot().Position, 1)
				end
				state.hauling = false
				Sense.ClearGoTo(state, "haul")
			elseif builder then
				Sense.GoTo(state, Sense.onFloor(builder:GetPivot().Position), plan.drop * 0.6, "haul", 2)
			else
				Sense.ClearGoTo(state, "haul")
			end
		end
	end
end

return EnemyTraits
