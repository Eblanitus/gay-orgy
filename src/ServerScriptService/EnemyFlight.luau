-- Летуны и неподвижные со своим циклом: Моль, Матка, Личинка, Пеликан.
--
-- Они не ходят по сетке и не толкаются (Crowd): у каждого свой цикл движения вместо общего
-- в EnemySpawner. Каждый цикл кончается смертью жука — кроме Матки (улетает сама) и
-- Пеликана (садится и дальше идёт пешком, отдавая управление общему циклу).
--
-- Вынесено из EnemyBehavior, когда механики видов выросли: здесь всё про полёт —
-- облёт построек, шаг летуна и сами циклы.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local RunService = game:GetService("RunService")

local Effects = require(ReplicatedStorage:WaitForChild("Effects"))
local LabTable = require(ServerScriptService:WaitForChild("LabTable"))
local EnemyStructures = require(ServerScriptService:WaitForChild("EnemyStructures"))
local Corpses = require(ServerScriptService:WaitForChild("Corpses"))
local ConcreteFloor = require(ServerScriptService:WaitForChild("ConcreteFloor"))
local Sense = require(ServerScriptService:WaitForChild("EnemySense"))

local alive, flat, naps = Sense.alive, Sense.flat, Sense.naps
local towersFolder = Sense.towersFolder
local enemiesFolder = Sense.enemiesFolder

local EnemyFlight = {}

-- ============================ Облёт построек ============================

-- Постройки — преграда для Моли и Лицехвата (задача #331): сквозь корпус они не пролетают,
-- а перелетают поверх. Корпус — коробка модели (GetBoundingBox), раздутая на габарит
-- летуна. Коробку пересчитываем не чаще раза в полсекунды: обход всех деталей турели
-- каждый кадр на каждого летуна обходился бы дорого, а турель за это время не сдвинется.
local BOX_REFRESH = 0.5
local AVOID_LOOKAHEAD = 6 -- за сколько студов летун «видит» корпус впереди и начинает набирать высоту
local AVOID_CLEARANCE = 1 -- зазор между летуном и корпусом
local towerBoxes = setmetatable({}, { __mode = "k" })
local flyerSizes = setmetatable({}, { __mode = "k" })

local function towerBox(tower)
	local box = towerBoxes[tower]
	local now = os.clock()
	if not box or now - box.at > BOX_REFRESH then
		local cf, size = tower:GetBoundingBox()
		box = { cf = cf, half = size / 2, at = now }
		towerBoxes[tower] = box
	end
	return box
end

-- Габарит летуна: radius — полуразмах по горизонтали (у Моли это крылья), half — полувысота.
local function flyerSize(enemy)
	local size = flyerSizes[enemy]
	if not size then
		local extents = enemy:GetExtentsSize()
		size = { radius = math.max(extents.X, extents.Z) / 2, half = extents.Y / 2 }
		flyerSizes[enemy] = size
	end
	return size
end

-- Высота, выше которой летун над этой постройкой ничего не задевает (по его пивоту).
local function clearTop(box, size)
	return box.cf.Position.Y + box.half.Y + size.half + AVOID_CLEARANCE
end

-- Постройка, в чей раздутый корпус попадает точка. ignore — какую не считать.
local function blockingTower(point, size, ignore)
	for _, tower in towersFolder:GetChildren() do
		if tower ~= ignore then
			local box = towerBox(tower)
			local p = box.cf:PointToObjectSpace(point)
			local h = box.half
			if math.abs(p.X) < h.X + size.radius + AVOID_CLEARANCE
				and math.abs(p.Z) < h.Z + size.radius + AVOID_CLEARANCE
				and math.abs(p.Y) < h.Y + size.half + AVOID_CLEARANCE then
				return box
			end
		end
	end
	return nil
end

-- Куда сдвинуться за шаг, не влетая в постройки. Впереди корпус — летун набирает высоту
-- на месте; уже выше него — летит ровно, не снижаясь, пока корпус не останется позади.
-- Оказался внутри (турель поставили прямо под ним) — тоже просто всплывает.
local function avoidStep(enemy, position, heading, step, reach, ignore)
	local size = flyerSize(enemy)
	local at = position + heading * step
	local ahead = position + heading * math.min(math.max(step, AVOID_LOOKAHEAD), reach)
	local box = blockingTower(at, size, ignore) or blockingTower(ahead, size, ignore)
	if not box then
		return at
	end

	local level = flat(heading)
	if position.Y >= clearTop(box, size) and level.Magnitude > 1e-3 then
		local over = position + level.Unit * step
		if not blockingTower(over, size, ignore) then
			return over
		end
	end
	return position + Vector3.new(0, step, 0)
end

-- Общий шаг любого летуна к точке. Возвращает true, когда долетел.
-- avoid — облетать постройки (true; или сама постройка, которую облетать не надо —
-- Лицехват на последнем отрезке садится на свою турель).
function EnemyFlight.FlyStep(enemy, target, speed, dt, arrive, avoid)
	local position = enemy:GetPivot().Position
	local delta = target - position
	local distance = delta.Magnitude
	if distance <= (arrive or 2) then
		return true
	end

	local heading = delta.Unit
	local step = math.min(speed * dt, distance)
	local at = position + heading * step
	if avoid then
		at = avoidStep(enemy, position, heading, step, distance, typeof(avoid) == "Instance" and avoid or nil)
	end

	-- Смотрит туда, куда летит; набирая высоту строго вверх — туда, куда собирался.
	local move = at - position
	local look = flat(move).Magnitude > 1e-3 and move.Unit or flat(heading)
	if look.Magnitude < 1e-3 then
		look = heading
	end
	enemy:PivotTo(CFrame.lookAt(at, at + look) * CFrame.Angles(0, math.pi, 0))
	enemy:SetAttribute("Velocity", move.Magnitude > 1e-3 and move.Unit * speed or Vector3.zero)
	return false
end

local flyStep = EnemyFlight.FlyStep

-- Точка над постройкой, где летун её уже не задевает: для Моли (вьётся над турелью)
-- и Лицехвата (подлетает сверху, а не сквозь корпус).
function EnemyFlight.AboveTower(enemy, tower)
	return clearTop(towerBox(tower), flyerSize(enemy))
end

-- ============================ Моль ============================
--
-- «Летит к светящимся элементам. Не разрушает. Не наносит урона. Просто летает и мешает.»
-- Светящийся элемент — это залитая турель (атрибут Element).
--
-- Как ведёт себя:
--   • летит к ближайшему свету, но на одном огне больше share молей не толпится — следующая
--     ищет другой залитый огонь: стая растаскивает на себя сразу несколько турелей;
--   • вьётся рваными кругами, а не по циркулю: радиус дрожит, высота качается, ход
--     то ускоряется, то стихает, и время от времени она разворачивается на обратный круг;
--   • разведчик по касте — пугается, как разведчики: получив урон, шарахается прочь от
--     огня, вверх и в сторону, и через panicReturn возвращается к свету.
-- Залитых нет — вьётся над любой турелью; нет и турелей — над столом.
local function lightOf(enemy, plan)
	local position = enemy:GetPivot().Position
	local crowd = {}
	for other, otherState in Sense.states do
		if other ~= enemy and otherState.light and alive(other) then
			crowd[otherState.light] = (crowd[otherState.light] or 0) + 1
		end
	end

	local best, bestDistance = nil, math.huge
	local any, anyDistance = nil, math.huge
	for _, tower in towersFolder:GetChildren() do
		if Sense.isTurret(tower) and tower:GetAttribute("Element") ~= nil then
			local distance = flat(tower:GetPivot().Position - position).Magnitude
			if distance < anyDistance then
				any, anyDistance = tower, distance
			end
			if (crowd[tower] or 0) < plan.share and distance < bestDistance then
				best, bestDistance = tower, distance
			end
		end
	end
	return best or any or Sense.nearestTurret(position)
end

local function mothLoop(enemy, enemyData, state)
	local plan = enemyData.glow
	local seed = state.seed or 0
	local angle = seed
	local turn = state.side or 1
	local nextPick, nextTurn = 0, os.clock() + plan.turnEvery * (0.5 + math.random())

	while alive(enemy) do
		local dt = RunService.Heartbeat:Wait()
		if not alive(enemy) then
			break
		end
		local now = os.clock()

		-- Свет выбирается не каждый кадр: подсчёт стаи по огням — проход по всем жукам.
		if now >= nextPick or not (state.light and state.light.Parent) then
			state.light = lightOf(enemy, plan)
			nextPick = now + 1
		end
		local anchor = state.light
		local center = anchor and anchor:GetPivot().Position or LabTable.Position()
		-- Высота кругов — от верха корпуса турели, а не от её пивота: иначе круги
		-- проходили сквозь Колбу (её верх ≈ 7.6 над пивотом).
		local height = anchor and (EnemyFlight.AboveTower(enemy, anchor) + plan.hover) or (center.Y + plan.hover)

		if state.panicUntil and now < state.panicUntil then
			-- Шарахнулась: прочь от огня, вверх и в сторону. Круги прерываются, и турель
			-- на эти секунды остаётся без помехи — испуг виден по траектории.
			local away = flat(enemy:GetPivot().Position - (state.fleeFrom or center))
			if away.Magnitude < 1e-3 then
				away = Vector3.new(math.cos(seed), 0, math.sin(seed))
			end
			local target = center + away.Unit * (plan.orbit + plan.scare)
				+ Vector3.new(0, height - center.Y + plan.scare * 0.5, 0)
			flyStep(enemy, target, enemyData.speed * 1.25, dt, 0.6, true)
		else
			if now >= nextTurn then
				turn = -turn
				nextTurn = now + plan.turnEvery * (0.5 + math.random())
			end
			-- Ход рывками: скорость облёта гуляет вокруг средней, а не держится ровно.
			local pace = 1 + 0.35 * math.sin(now * 1.7 + seed)
			angle += dt * math.pi * 2 / plan.period * pace * turn
			local radius = plan.orbit + plan.flutter * math.sin(now * 2.9 + seed * 3)
			local bob = plan.bob * math.sin(now * 3.3 + seed * 2)
			local target = Vector3.new(
				center.X + math.cos(angle) * radius,
				height + bob,
				center.Z + math.sin(angle) * radius)
			flyStep(enemy, target, enemyData.speed, dt, 0.4, true)
		end
	end
	state.light = nil
end

-- ============================ Матка ============================
--
-- «Прилетает на карту, откладывает личинку и уходит.» Уход — это уход с карты, а не
-- прорыв: она никуда не прорывается и в счёт прорывов не идёт.
--
-- Как ведёт себя:
--   • гнездо выбирает, а не роняет куда попало: из нескольких мест вокруг лаборатории —
--     то, которое держит меньше всего турелей. Личинка оказывается в глубине обороны,
--     но в её слепом пятне;
--   • откладывает, сев на пол: всё это время она наземная цель, и её достают турели,
--     которые по воздуху не бьют. Отложив — взлетает и уходит вверх;
--   • подбитая на подлёте (HP ниже abortBelow) не дотягивает до гнезда: садится и
--     откладывает там, где её застали.
local function nestSpot(plan)
	local lab = LabTable.Position()
	local best, bestScore = nil, math.huge
	for _ = 1, plan.tries do
		local a = math.random() * math.pi * 2
		local r = plan.near + math.random() * (plan.far - plan.near)
		local spot = lab + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
		if Sense.standable(spot) then
			-- Главное — слепое пятно; при равном прикрытии ближе к столу лучше.
			local score = Sense.coverage(spot) + r / plan.far * 0.5
			if score < bestScore then
				best, bestScore = spot, score
			end
		end
	end
	if best then
		return best
	end
	return lab + Vector3.new((math.random() - 0.5) * 60, 0, (math.random() - 0.5) * 60)
end

local function wounded(enemy, share)
	local hp, maxHp = enemy:GetAttribute("HP") or 0, enemy:GetAttribute("MaxHP") or 1
	return hp < maxHp * share
end

local function queenLoop(enemy, enemyData, state)
	local plan = enemyData.lays
	local spot = nestSpot(plan)
	local cruise = Vector3.new(spot.X, spot.Y + plan.cruise, spot.Z)

	while alive(enemy) do
		local dt = RunService.Heartbeat:Wait()
		if not alive(enemy) then
			return
		end
		if wounded(enemy, plan.abortBelow) then
			print("[Матка] подбита на подлёте — откладывает там, где застали")
			break
		end
		if flyStep(enemy, cruise, enemyData.speed, dt, 3, true) then
			break
		end
	end

	-- Садится на пол отвесно и становится наземной целью.
	local at = enemy:GetPivot().Position
	local floor = ConcreteFloor.HeightAt(at.X, at.Z) + plan.perch
	local ground = Vector3.new(at.X, floor, at.Z)
	while alive(enemy) do
		local dt = RunService.Heartbeat:Wait()
		if not alive(enemy) then
			return
		end
		if flyStep(enemy, ground, enemyData.speed * 0.6, dt, 0.3) then
			break
		end
	end
	if not alive(enemy) then
		return
	end
	enemy:SetAttribute("Flying", nil)
	enemy:SetAttribute("Velocity", Vector3.zero)

	if not naps(enemy, plan.after) then
		return
	end

	at = enemy:GetPivot().Position
	if Sense.Spawn then
		print("[Матка] отложила личинку и уходит")
		Sense.Spawn(plan.type, Vector3.new(at.X, 1.5, at.Z))
	end

	-- Взлетает и уходит с карты вверх. Это НЕ прорыв: она сделала ровно то, зачем прилетала.
	enemy:SetAttribute("Flying", true)
	local exitPoint = enemy:GetPivot().Position + Vector3.new(0, 80, 0)
	while alive(enemy) do
		local dt = RunService.Heartbeat:Wait()
		if not alive(enemy) or flyStep(enemy, exitPoint, enemyData.speed * 2, dt, 4) then
			break
		end
	end
	if enemy.Parent then
		enemy:Destroy()
	end
end

-- ============================ Личинка ============================
--
-- «Стоит на месте. Через время вылупляется большая группа мелких жуков.» Подбитая, но не
-- добитая личинка вылупляется группой поменьше (но не меньше minShare от полной):
-- недобитая личинка — всё равно беда, но каждое попадание по ней было не зря.
local function larvaLoop(enemy, enemyData, state)
	local plan = enemyData.hatches
	if not naps(enemy, plan.after) then
		return -- успели расстрелять до вылупления — ровно то, чего требует документ
	end
	-- На спине Медика не вылупляется: мелочь высыпалась бы в воздухе.
	while Sense.carried[enemy] and alive(enemy) do
		RunService.Heartbeat:Wait()
	end
	if not alive(enemy) then
		return
	end

	local share = (enemy:GetAttribute("HP") or 0) / math.max(enemy:GetAttribute("MaxHP") or 1, 1)
	local count = math.max(math.ceil(plan.count * plan.minShare), math.floor(plan.count * share + 0.5))
	local at = enemy:GetPivot().Position
	print(("[Личинка] вылупилась: %d x %s"):format(count, plan.type))
	if Sense.Spawn then
		for _ = 1, count do
			local offset = Vector3.new((math.random() - 0.5) * 6, 0, (math.random() - 0.5) * 6)
			Sense.Spawn(plan.type, at + offset)
		end
	end
	Effects.MarkHit(enemy, nil) -- не элемент убил: тело
	enemy:SetAttribute("HP", 0)
end

-- ============================ Пеликан ============================
--
-- «Ест трупы жуков. Труп исчезает... Умеет летать, а когда съест трупы — становится
-- наземным. Перемещается между трупами по воздуху. Когда наестся — оставляет
-- строительный материал для жуков. И идёт в бой.»
--
-- Как ведёт себя:
--   • летит от трупа к трупу; крупный труп сытнее мелкого (сытость — по размеру туши);
--   • с каждым съеденным тяжелеет и летит медленнее;
--   • трупов нет — не садится сразу, а кружит над боем, как стервятник, и ждёт, пока
--     появятся, но не дольше circle секунд;
--   • наевшись, несёт материал к ближайшему Строителю (если тот недалеко) и садится
--     рядом с ним: «оставляет строительный материал для жуков» — тем, кто из него строит.
-- Возвращает false, когда сел и отдаёт управление общему циклу («я больше не веду»),
-- и true, если погиб в воздухе.
local function battleCenter()
	local sum, count = Vector3.zero, 0
	for _, other in enemiesFolder:GetChildren() do
		if alive(other) and not other:GetAttribute("Flying") then
			sum += other:GetPivot().Position
			count += 1
		end
	end
	if count == 0 then
		return LabTable.Position()
	end
	return sum / count
end

local function nearestBuilder(position, radius)
	local best, bestDistance = nil, radius
	for _, other in Sense.enemiesAround(position, radius) do
		local data = Sense.dataOf(other)
		if data and data.builds and not other:GetAttribute("Flying") then
			local distance = flat(other:GetPivot().Position - position).Magnitude
			if distance < bestDistance then
				best, bestDistance = other, distance
			end
		end
	end
	return best
end

local function pelicanLoop(enemy, enemyData, state)
	local plan = enemyData.scavenges
	local meals, eaten = 0, 0
	local speed = enemyData.speed
	local hungrySince = os.clock()
	local circle = state.seed or 0

	while alive(enemy) and meals < plan.eat do
		-- Туши живут на клиентах; сервер знает лишь точки смерти (Corpses.Nearest).
		local best = Corpses.Nearest(enemy:GetPivot().Position)

		if not best then
			if os.clock() - hungrySince > plan.circle then
				break -- нечего ждать: садится и идёт в бой с тем, что успел съесть
			end
			local dt = RunService.Heartbeat:Wait()
			if not alive(enemy) then
				return true
			end
			local center = battleCenter()
			circle += dt * speed / plan.circleRadius
			local target = Vector3.new(
				center.X + math.cos(circle) * plan.circleRadius,
				center.Y + plan.cruise + 3,
				center.Z + math.sin(circle) * plan.circleRadius)
			flyStep(enemy, target, speed, dt, 1, true)
		else
			hungrySince = os.clock()
			local target = best.position + Vector3.new(0, plan.cruise, 0)
			while alive(enemy) and best.alive do
				local dt = RunService.Heartbeat:Wait()
				if not alive(enemy) then
					return true
				end
				if flyStep(enemy, target, speed, dt, 2, true) then
					break
				end
			end

			if not alive(enemy) then
				return true
			end

			if best.alive then
				if not naps(enemy, plan.bite) then
					return true
				end
				if best.alive then
					Corpses.Eat(best) -- «Труп исчезает»
					eaten += 1
					meals += math.clamp(best.scale or 1, plan.minMeal, plan.maxMeal)
					speed = enemyData.speed * math.max(plan.slowest, 1 - plan.heavy * eaten)
				end
			end
		end
	end

	if not alive(enemy) then
		return true
	end

	-- Наелся: несёт материал Строителю, если тот недалеко, и садится рядом с ним.
	if eaten > 0 then
		local builder = nearestBuilder(enemy:GetPivot().Position, plan.deliver)
		if builder then
			while alive(enemy) and alive(builder) do
				local dt = RunService.Heartbeat:Wait()
				if not alive(enemy) then
					return true
				end
				local drop = builder:GetPivot().Position + Vector3.new(0, plan.cruise, 0)
				if flyStep(enemy, drop, speed, dt, 3, true) then
					break
				end
			end
			if not alive(enemy) then
				return true
			end
		end
	end

	local at = enemy:GetPivot().Position
	enemy:SetAttribute("Flying", nil)
	enemy:PivotTo(CFrame.new(Vector3.new(at.X, 1.5, at.Z)))
	if eaten > 0 then
		EnemyStructures.DropMaterial(Vector3.new(at.X, 1.5, at.Z), plan.material)
		print(("[Пеликан] съел %d трупов, оставил %d обломков и пошёл в бой")
			:format(eaten, plan.material))
	end
	return false
end

-- Собственный цикл движения вместо общего. Возвращает true, если ведёт жука до конца
-- и спавнеру делать больше нечего.
function EnemyFlight.OwnLoop(enemy, enemyData, state)
	if enemyData.glow then
		mothLoop(enemy, enemyData, state)
		return true
	end
	if enemyData.lays then
		queenLoop(enemy, enemyData, state)
		return true
	end
	if enemyData.hatches then
		larvaLoop(enemy, enemyData, state)
		return true
	end
	if enemyData.scavenges then
		-- Пеликан возвращает управление, когда наелся и сел на землю.
		return pelicanLoop(enemy, enemyData, state)
	end
	return false
end

return EnemyFlight
