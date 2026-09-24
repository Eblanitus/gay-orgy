-- Поведение жуков по кастам и особые механики отдельных видов
-- (design: alchemy_td_enemies.md).
--
-- Движение по маршруту, грызня и перелезание остались в EnemySpawner — они общие
-- для всех. Здесь то, что различает виды:
--
--   Goal        — куда вести маршрут (стол, выход, периметр)
--   Hold        — должен ли жук стоять на месте этот кадр (копает, маскируется,
--                 нацеливается, ждёт группу)
--   Panic       — реакция на урон, своя у каждой касты
--   TRAITS      — особые механики: одно поле в Enemies = одна функция здесь
--
-- Новый жук без новой механики добавляется СТРОКОЙ в Enemies и сюда не лезет вовсе —
-- это требование RULES.md, а не удобство.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Enemies = require(ReplicatedStorage:WaitForChild("Enemies"))
local Towers = require(ReplicatedStorage:WaitForChild("Towers"))
local Elements = require(ReplicatedStorage:WaitForChild("Elements"))
local Effects = require(ReplicatedStorage:WaitForChild("Effects"))
local Grid = require(ServerScriptService:WaitForChild("Grid"))
local LabTable = require(ServerScriptService:WaitForChild("LabTable"))
-- Справочник и производитель: целью не бывают, но взрывы их задевают.
local LabStations = require(ServerScriptService:WaitForChild("LabStations"))
local EnemyStructures = require(ServerScriptService:WaitForChild("EnemyStructures"))
local Corpses = require(ServerScriptService:WaitForChild("Corpses"))
-- Рельеф бетонного пола: Окопщик копает в нём настоящую яму.
local ConcreteFloor = require(ServerScriptService:WaitForChild("ConcreteFloor"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local DamageDealtRemote = Remotes:WaitForChild("DamageDealt")
local ExplosionRemote = Remotes:WaitForChild("Explosion")
-- Каждый взрыв расбрасывает всё незакреплённое (трупы, оторванные конечности) — см. Impulse.
local Impulse = require(game:GetService("ServerScriptService"):WaitForChild("Impulse"))

local enemiesFolder = Workspace:WaitForChild("Enemies")
local towersFolder = Workspace:WaitForChild("Towers")

local EnemyBehavior = {}

-- Кого Координатор навёл на какую турель: enemy -> { turret, expires }.
--
-- Таблицей, а НЕ атрибутом на жуке: атрибуты Roblox не держат ссылки на Instance —
-- записанная туда турель возвращалась обратно не моделью, а пустым хандлом, и чтение
-- .Parent у неё падало (найдено живым прогоном). Ключи слабые: убитый жук не должен
-- держаться в памяти ради своего прошлого фокуса.
local focus = setmetatable({}, { __mode = "k" })

-- Спавн жука из поведения (личинка вылупляется, Носитель высыпается, Матка кладёт).
-- Назначает EnemySpawner — прямой require спавнера зациклил бы модули.
EnemyBehavior.Spawn = nil

-- ============================ Общее ============================

local function alive(enemy)
	return enemy.Parent ~= nil and (enemy:GetAttribute("HP") or 0) > 0
end

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

-- Настоящая турель — та, у чьего типа есть fireRate. Стена и Гора — преграды,
-- и ни паника, ни Координатор, ни Моль их турелями не считают.
local function isTurret(tower)
	local data = Towers[tower:GetAttribute("Type")]
	return data ~= nil and data.fireRate ~= nil
end

local function nearestTurret(position, filter)
	local best, bestDistance = nil, math.huge
	for _, tower in towersFolder:GetChildren() do
		if isTurret(tower) and (not filter or filter(tower)) then
			local distance = (tower:GetPivot().Position - position).Magnitude
			if distance < bestDistance then
				best, bestDistance = tower, distance
			end
		end
	end
	return best, bestDistance
end

-- Жуки вокруг точки. except — кого не считать (обычно себя самого).
local function enemiesAround(position, radius, except)
	local found = {}
	for _, other in enemiesFolder:GetChildren() do
		if other ~= except and alive(other)
			and (other:GetPivot().Position - position).Magnitude <= radius then
			table.insert(found, other)
		end
	end
	return found
end

-- Засыпает на t секунд и возвращает false, если жук за это время погиб. Все трейты
-- ждут через неё, чтобы ни один не продолжал работать на убитом.
local function naps(enemy, t)
	task.wait(t)
	return alive(enemy)
end

-- ============================ Цель ============================

-- Периметр арены для Хмурого брона: четыре угла с отступом от стены. «Идёт вдоль
-- стен. Разрушает всё что попадается» — разрушение само собой выходит из того, что
-- общая грызня в EnemySpawner останавливает его перед любой постройкой на пути.
local PERIMETER_INSET = 8 -- studs от края поля

local function perimeterCells()
	local inset = math.max(2, math.floor(PERIMETER_INSET / Grid.CellSize))
	local minX, maxX = inset, Grid.Cols - inset
	local minZ, maxZ = inset, Grid.Rows - inset
	return {
		{ x = minX, z = minZ },
		{ x = maxX, z = minZ },
		{ x = maxX, z = maxZ },
		{ x = minX, z = maxZ },
	}
end

-- Куда вести маршрут. Возвращает клетку и то, что там ждёт по прибытии.
function EnemyBehavior.Goal(enemy, enemyData, state)
	local goal = enemyData.goal

	-- Группа работяг вышла и встретила турель, или солдатам её указал Координатор —
	-- турель перебивает любую свою цель. Сносят её той же общей грызнёй: подошли
	-- вплотную — постройка встала переградой на пути, и механика грызни сама её ломает.
	local focus = state.focusTurret
	if focus and focus.Parent then
		local cx, cz = Grid.ToCell(focus:GetPivot().Position)
		return cx, cz, "turret"
	end

	if goal == "table" then
		-- Стол разбит — грызть больше нечего, и жук идёт к выходу. Без этой ветки
		-- вся волна вставала бы вокруг обломков стола и никогда не кончалась.
		if LabTable.IsAlive() then
			local cx, cz = LabTable.Cell()
			return cx, cz, "table"
		end
		local cx, cz = Grid.GetExitCell()
		return cx, cz, "exit"
	end

	if goal == "perimeter" then
		local ring = state.ring
		if not ring then
			ring = perimeterCells()
			state.ring = ring
			-- Начинает с ближайшего угла, а не всегда с первого: иначе все броны
			-- идут одной колонной в один и тот же угол.
			local cx, cz = Grid.ToCell(enemy:GetPivot().Position)
			local best, bestDistance = 1, math.huge
			for i, cell in ring do
				local distance = math.abs(cell.x - cx) + math.abs(cell.z - cz)
				if distance < bestDistance then
					best, bestDistance = i, distance
				end
			end
			state.ringIndex = best
		end
		local cell = ring[state.ringIndex]
		return cell.x, cell.z, "perimeter"
	end

	local cx, cz = Grid.GetExitCell()
	return cx, cz, "exit"
end

-- Жук дошёл до конца маршрута. Возвращает "breach", если это прорыв, и nil, если
-- жук просто продолжает жить на месте (грызёт стол, идёт по периметру дальше).
function EnemyBehavior.Arrived(enemy, enemyData, state, mode)
	if mode == "perimeter" then
		-- Следующий угол. Круг замкнут: «пока не уничтожен» — то есть бесконечно.
		state.ringIndex = state.ringIndex % #state.ring + 1
		return nil
	end

	if mode == "table" then
		return nil -- грызёт стол, см. EnemyBehavior.BiteTable
	end

	if mode == "turret" then
		return nil -- турель стоит переградой, её грызёт обычная механика
	end

	return "breach"
end

-- Грызня стола. Жук стоит у стола и бьёт его со своим темпом — тем же, что и постройки.
function EnemyBehavior.BiteTable(enemy, enemyData, state)
	local chewDamage = enemyData.chewDamage or 0
	if chewDamage <= 0 or not LabTable.IsAlive() then
		return false
	end

	local now = os.clock()
	local attackSlow = math.clamp(enemy:GetAttribute("AttackSlowPercent") or 0, 0, 0.9)
	local rate = (enemyData.chewRate or 1) * (1 - attackSlow)
	if now - (state.lastTableBite or 0) < 1 / math.max(rate, 0.05) then
		return true
	end
	state.lastTableBite = now

	local weakened = math.clamp(enemy:GetAttribute("Weakened") or 0, 0, 0.9)
	local bite = math.max(1, math.floor(chewDamage * (1 - weakened) + 0.5))
	LabTable.Bite(bite)
	return true
end

-- ============================ Паника ============================

-- Сколько секунд работяга ждёт группу, прежде чем выйти в одиночку. Без потолка
-- последние четверо работяг волны стояли бы в укрытии вечно, и волна не кончалась бы.
local WORKER_PATIENCE = 20

-- Как далеко отходит испуганный и в каком радиусе считается группа.
local PANIC_STEP = 1
local GROUP_RADIUS = 18

-- Урон по жуку. Зовётся из EnemySpawner по падению HP — там же, где считается кровь.
--
-- Откуда стреляли, жуку никто не говорит (урон приходит из полудюжины мест),
-- поэтому отходит он ОТ БЛИЖАЙШЕЙ ТУРЕЛИ — в девяти случаях из десяти это она
-- и есть. Турелей нет вовсе — паниковать не от чего.
function EnemyBehavior.Damaged(enemy, enemyData, state)
	local panic = enemyData.panic
	if not panic then
		return -- Хмурый брон слеп: не видит турели и не пугается
	end

	local turret = nearestTurret(enemy:GetPivot().Position)
	if not turret then
		return
	end

	state.fleeFrom = turret:GetPivot().Position

	if panic == "scout" then
		-- «Пугаются — отходят, через 3 секунды возвращаются.» Каждое новое попадание
		-- продлевает срок: под непрерывным огнём жук так и не возвращается, и это верно.
		state.panicUntil = os.clock() + (enemyData.panicReturn or 3)
	elseif panic == "worker" then
		-- «Отходит в безопасное место. Ждёт пока рядом соберётся 5 работяг.»
		if not state.regrouping then
			state.regrouping = true
			state.regroupUntil = os.clock() + WORKER_PATIENCE
		end
	end
end

-- Что жук делает этот кадр: nil — идёт по маршруту, "flee" — отходит, "hold" — стоит.
function EnemyBehavior.State(enemy, enemyData, state)
	local now = os.clock()

	-- Трейт держит жука на месте (копает, маскируется, нацеливается, строит).
	if state.holdUntil and now < state.holdUntil then
		return "hold"
	end

	if state.panicUntil and now < state.panicUntil then
		return "flee"
	end

	if state.regrouping then
		-- Выходят вместе, когда рядом набралось groupSize своих (считая себя).
		-- Свои — это любые работяги (каста 1), а не только тот же вид: группа в документе
		-- — это каста, а не вид.
		local need = enemyData.groupSize or 5
		local gathered = 1
		for _, other in enemiesAround(enemy:GetPivot().Position, GROUP_RADIUS, enemy) do
			local otherData = Enemies[other:GetAttribute("Type")]
			if otherData and otherData.caste == enemyData.caste then
				gathered += 1
			end
		end

		if gathered >= need or now >= (state.regroupUntil or 0) then
			state.regrouping = false
			state.fleeFrom = nil
			-- «Группой выходят. Встретили турель — группой атакуют.» Один — никогда:
			-- цель-турель ставится только тому, кто дождался группы, а не вышедшему
			-- по истечении терпения.
			if gathered >= need then
				local turret = nearestTurret(enemy:GetPivot().Position)
				if turret then
					state.focusTurret = turret
					-- Тот же флаг, что и у приказа Координатора: без него группа «выходит
					-- на турель» только в логе, а ногами идёт по старому маршруту к столу.
					state.repath = true
					print(("[Работяги] группа из %d вышла на %s"):format(gathered, turret.Name))
				end
			end
			return nil
		end

		return "hold"
	end

	return nil
end

-- Куда отходит испуганный: прочь от того, от чего бежит.
function EnemyBehavior.FleeStep(enemy, state, step)
	local position = enemy:GetPivot().Position
	local away = flat(position - (state.fleeFrom or position))
	if away.Magnitude < 1e-3 then
		away = Vector3.new(math.cos(state.seed or 0), 0, math.sin(state.seed or 0))
	end
	return away.Unit * step * PANIC_STEP
end

-- Множитель скорости от пола под ногами: на хитине жуки быстрее. Заодно
-- проставляет атрибут InTrench, по которому турели теряют по нему радиус (см. Targeting):
-- пол спрашивается один раз на кадр и сразу на оба вопроса.
function EnemyBehavior.Ground(enemy, state)
	local at = enemy:GetPivot().Position
	local onChitin = EnemyStructures.OnChitin(at)
	-- Укрытие теперь спрашивается у самого пола, а не у списка конструкций: в яме можно
	-- оказаться не только из-за Окопщика, но и из-за Литосферы — а прячет одинаково.
	local inTrench = ConcreteFloor.IsCover(at.X, at.Z)

	if inTrench ~= (state.inTrench or false) then
		state.inTrench = inTrench
		enemy:SetAttribute("InTrench", inTrench or nil)
	end

	return onChitin and 1.4 or 1
end

-- ============================ Летающие ============================

-- Общий шаг любого летуна к точке. Возвращает true, когда долетел.
local function flyStep(enemy, target, speed, dt, arrive)
	local position = enemy:GetPivot().Position
	local delta = target - position
	local distance = delta.Magnitude
	if distance <= (arrive or 2) then
		return true
	end

	local heading = delta.Unit
	local at = position + heading * math.min(speed * dt, distance)
	enemy:PivotTo(CFrame.lookAt(at, at + heading) * CFrame.Angles(0, math.pi, 0))
	enemy:SetAttribute("Velocity", heading * speed)
	return false
end

EnemyBehavior.FlyStep = flyStep

-- Летуны со своим циклом движения не ходят по сетке и не толкаются. Каждый цикл кончается
-- смертью жука — кроме Матки (улетает сама) и Пеликана (садится и дальше идёт пешком).
local RunService = game:GetService("RunService")

-- Моль: «Летит к светящимся элементам». Светящийся элемент — это залитая турель
-- (атрибут Element). Залитых нет — вьётся над любой турелью; нет и турелей — над столом.
local function mothLoop(enemy, enemyData, state)
	local plan = enemyData.glow
	local angle = state.seed or 0

	while alive(enemy) do
		local dt = RunService.Heartbeat:Wait()
		if not alive(enemy) then
			break
		end

		local lit = nearestTurret(enemy:GetPivot().Position, function(tower)
			return tower:GetAttribute("Element") ~= nil
		end)
		local anchor = lit or nearestTurret(enemy:GetPivot().Position)
		local center = anchor and anchor:GetPivot().Position or LabTable.Position()

		-- Круги вокруг цели: именно они и есть всё её поведение — «просто летает
		-- и мешает»: турель тратит на неё выстрелы, которые могла бы потратить на жуков.
		angle += dt * math.pi * 2 / plan.period
		local target = center + Vector3.new(
			math.cos(angle) * plan.orbit,
			plan.hover,
			math.sin(angle) * plan.orbit)
		flyStep(enemy, target, enemyData.speed, dt, 0.4)
	end
end

-- Матка: «Прилетает на карту, откладывает личинку и уходит.»
local function queenLoop(enemy, enemyData, state)
	local plan = enemyData.lays

	-- Летит в случайную точку поближе к лаборатории, а не точно на стол: личинка
	-- должна оказаться в глубине обороны, но не всегда в одной и той же точке.
	local drop = LabTable.Position()
		+ Vector3.new((math.random() - 0.5) * 60, 6, (math.random() - 0.5) * 60)

	while alive(enemy) do
		local dt = RunService.Heartbeat:Wait()
		if not alive(enemy) then
			return
		end
		if flyStep(enemy, drop, enemyData.speed, dt, 3) then
			break
		end
	end

	if not naps(enemy, plan.after) then
		return
	end

	local at = enemy:GetPivot().Position
	if EnemyBehavior.Spawn then
		print("[Матка] отложила личинку и уходит")
		EnemyBehavior.Spawn(plan.type, Vector3.new(at.X, 1.5, at.Z))
	end

	-- Уходит с карты вверх и пропадает. Это НЕ прорыв: она никуда не прорвалась,
	-- а сделала ровно то, зачем прилетала.
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

-- Летающий координатор: «смотрит на лабораторию сверху, передаёт роевику куда копать».
local function swarmEyeLoop(enemy, enemyData, state)
	local plan = enemyData.directs
	local post = LabTable.Position() + Vector3.new(0, plan.hover, 0)

	while alive(enemy) do
		local dt = RunService.Heartbeat:Wait()
		if not alive(enemy) then
			break
		end

		flyStep(enemy, post, enemyData.speed, dt, 2)

		-- Ведёт всех Роевиков в радиусе. Смерть координатора ничего не снимает руками:
		-- метка ставится с окончанием срока, и без живого координатора она просто истекает.
		local at = enemy:GetPivot().Position
		for _, other in enemiesFolder:GetChildren() do
			local otherData = Enemies[other:GetAttribute("Type")]
			if otherData and otherData.burrows
				and (other:GetPivot().Position - at).Magnitude <= plan.radius then
				other:SetAttribute("GuidedUntil", os.clock() + 1)
			end
		end
	end
end

-- Личинка: стоит на месте и вылупляется большой группой мелких.
local function larvaLoop(enemy, enemyData, state)
	local plan = enemyData.hatches
	if not naps(enemy, plan.after) then
		return -- успели расстрелять до вылупления — ровно то, чего требует документ
	end

	local at = enemy:GetPivot().Position
	print(("[Личинка] вылупилась: %d x %s"):format(plan.count, plan.type))
	if EnemyBehavior.Spawn then
		for _ = 1, plan.count do
			local offset = Vector3.new((math.random() - 0.5) * 6, 0, (math.random() - 0.5) * 6)
			EnemyBehavior.Spawn(plan.type, at + offset)
		end
	end
	enemy:SetAttribute("HP", 0)
end

-- Пеликан: летает между трупами, ест их, наевшись — садится, оставляет материал
-- и идёт в бой как обычный работяга. Возвращает управление спавнеру, а не ведёт
-- жука до смерти: оттого и возвращает false в конце («я больше не веду»).
local function pelicanLoop(enemy, enemyData, state)
	local plan = enemyData.scavenges
	local eaten = 0
	local cruise = 5 -- studs над трупом: перемещается между трупами по воздуху

	while alive(enemy) and eaten < plan.eat do
		-- Ближайший труп. Нет трупов — есть нечего, и он сразу садится в бой.
		-- Туши живут на клиентах; сервер знает лишь точки смерти (Corpses.Nearest).
		local best = Corpses.Nearest(enemy:GetPivot().Position)

		if not best then
			break
		end

		local target = best.position + Vector3.new(0, cruise, 0)
		while alive(enemy) and best.alive do
			local dt = RunService.Heartbeat:Wait()
			if not alive(enemy) then
				return true
			end
			if flyStep(enemy, target, enemyData.speed, dt, 2) then
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
			end
		end
	end

	if not alive(enemy) then
		return true
	end

	-- Наелся: становится наземным, оставляет материал и идёт в бой.
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

-- ============================ Трейты ============================
--
-- Одно поле в Enemies — одна запись здесь. Каждый трейт — отдельная корутина,
-- которая живёт, пока жив жук.

local TRAITS = {}

-- Строитель: собирает обломки, строит одну из трёх конструкций. Какую именно —
-- решает обстановка, а не жребий: есть рядом стена игрока — пандус; есть раненые
-- соседи — кормушка; иначе — стена против линии огня.
TRAITS.builds = function(enemy, enemyData, state)
	local plan = enemyData.builds
	local carried = 0

	while alive(enemy) do
		if not naps(enemy, 1) then
			return
		end

		local at = enemy:GetPivot().Position

		-- «Ест обломки стены или мебели.» Пока не набрал нужного — не строит.
		if carried < plan.needMaterial then
			if EnemyStructures.TakeMaterial(at, plan.gather) then
				carried += 1
			end
		else
			state.holdUntil = os.clock() + 1.5 -- строит, стоя на месте
			if not naps(enemy, 1.5) then
				return
			end
			at = enemy:GetPivot().Position

			local ramped = nil
			for _, tower in towersFolder:GetChildren() do
				if tower:GetAttribute("Height") and not tower:GetAttribute("Ramped")
					and (tower:GetPivot().Position - at).Magnitude <= 14 then
					ramped = tower
					break
				end
			end

			local wounded = 0
			for _, other in enemiesAround(at, 16, enemy) do
				local hp, maxHp = other:GetAttribute("HP"), other:GetAttribute("MaxHP")
				if hp and maxHp and hp < maxHp * 0.6 then
					wounded += 1
				end
			end

			if ramped then
				EnemyStructures.Ramp(ramped)
			elseif wounded >= 3 then
				EnemyStructures.Feeder(at)
			else
				-- Стена ставится ПОПЕРЁК направления на ближайшую турель — только так
				-- она закрывает линию огня, а не стоит вдоль неё.
				local turret = nearestTurret(at)
				local facing = turret and flat(turret:GetPivot().Position - at) or Vector3.zAxis
				if facing.Magnitude < 1e-3 then
					facing = Vector3.zAxis
				end
				EnemyStructures.Wall(at + facing.Unit * 5, facing.Unit)
			end

			carried -= plan.needMaterial
			if not naps(enemy, plan.interval) then
				return
			end
		end
	end
end

-- Окопщик: копает неподвижно (уязвим), оставляет окоп и обломки Строителю.
TRAITS.digs = function(enemy, enemyData, state)
	local plan = enemyData.digs

	while alive(enemy) do
		if not naps(enemy, plan.interval) then
			return
		end

		state.holdUntil = os.clock() + plan.time
		print("[Окопщик] копает — пока копает, стоит на месте")
		if not naps(enemy, plan.time) then
			return -- расстреляли за работой: окопа не будет
		end

		-- Окоп — это выемка в самом полу, а не плоская картонка поверх него: «жук в окопе
		-- ниже линии огня турелей» — значит он действительно ниже. Прятать его будет тот же
		-- атрибут InTrench, который теперь ставится по глубине пола (см. EnemyBehavior.Ground).
		local at = enemy:GetPivot().Position
		ConcreteFloor.Shape(at, plan.radius, -plan.depth, { tag = "trench", core = plan.core })
		EnemyStructures.DropMaterial(at, plan.material)
		print(("[Окопщик] выкопал окоп: радиус %.0f, глубина %.1f")
			:format(plan.radius, plan.depth))
	end
end

-- Кислотник: помечает постройку атрибутом SoftenedUntil. Грызня читает его сама
-- (см. EnemySpawner) — точно так же, как читает ChewResist Бура.
TRAITS.spits = function(enemy, enemyData, state)
	local plan = enemyData.spits

	while alive(enemy) do
		if not naps(enemy, plan.interval) then
			return
		end

		local at = enemy:GetPivot().Position
		local best, bestDistance = nil, math.huge
		for _, tower in towersFolder:GetChildren() do
			local distance = (tower:GetPivot().Position - at).Magnitude
			if distance <= plan.range and distance < bestDistance then
				best, bestDistance = tower, distance
			end
		end

		if best then
			best:SetAttribute("SoftenedUntil", os.clock() + plan.duration)
			best:SetAttribute("Softens", plan.softens)
			print(("[Кислотник] размягчил %s на %.0f сек — грызётся втрое быстрее")
				:format(best.Name, plan.duration))
		end
	end
end

-- Медик: лечит раненых вокруг. Сам не атакует вовсе (chewDamage = 0 в таблице).
TRAITS.heals = function(enemy, enemyData, state)
	local plan = enemyData.heals

	while alive(enemy) do
		if not naps(enemy, plan.interval) then
			return
		end

		local at = enemy:GetPivot().Position
		-- «Выбирает зоны для лечения» — лечит самого раненого, а не всех понемногу.
		local best, bestRatio = nil, 1
		for _, other in enemiesAround(at, plan.radius, enemy) do
			local hp, maxHp = other:GetAttribute("HP"), other:GetAttribute("MaxHP")
			if hp and maxHp and maxHp > 0 and hp < maxHp then
				local ratio = hp / maxHp
				if ratio < bestRatio then
					best, bestRatio = other, ratio
				end
			end
		end

		if best then
			local hp, maxHp = best:GetAttribute("HP"), best:GetAttribute("MaxHP")
			best:SetAttribute("HP", math.min(maxHp, hp + plan.amount))
		end
	end
end

-- Подрывник: подошёл к постройке — активировал заряд — взрыв. Сам гибнет вместе с ним.
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
			if not naps(enemy, plan.arm) then
				return -- успели снять во время активации — взрыв сделает ветка смерти
			end
			EnemyBehavior.Detonate(enemy, enemyData)
			return
		end
	end
end

-- Взрыв заряда. Зовётся и по активации у стены, и по смерти от урона — «попадание
-- в заряд — преждевременная детонация». Разница только в том, где он в этот момент
-- стоит, а это и есть цена раннего выстрела по нему.
function EnemyBehavior.Detonate(enemy, enemyData)
	local plan = enemyData.charge
	if not plan or enemy:GetAttribute("Detonated") then
		return
	end
	enemy:SetAttribute("Detonated", true)

	local at = enemy:GetPivot().Position
	ExplosionRemote:FireAllClients(at, plan.radius)

	local hits = 0
	for _, tower in towersFolder:GetChildren() do
		if (tower:GetPivot().Position - at).Magnitude <= plan.radius then
			local hp = tower:GetAttribute("HP") or 0
			tower:SetAttribute("HP", math.max(0, hp - plan.damage))
			DamageDealtRemote:FireAllClients(tower:GetPivot().Position, math.min(hp, plan.damage), false)
			hits += 1
		end
	end

	-- Стол тоже в радиусе: для заряда он такое же препятствие, как стена.
	if (LabTable.Position() - at).Magnitude <= plan.radius then
		LabTable.Bite(plan.damage)
		hits += 1
	end
	hits += LabStations.Blast(at, plan.radius, plan.damage)

	EnemyStructures.Blast(at, plan.radius, plan.damage)

	print(("[Подрывник] взрыв: %d урона по %d целям в радиусе %.0f")
		:format(plan.damage, hits, plan.radius))

	if enemy.Parent then
		enemy:SetAttribute("HP", 0)
	end
end

-- Щитоносец: атрибуты читает Effects.ApplyArmor. Здесь же — прикрытие идущих сзади:
-- «Закрывает не только себя, но и идущих сзади.»
TRAITS.shield = function(enemy, enemyData, state)
	local plan = enemyData.shield
	enemy:SetAttribute("ShieldArc", plan.arc)
	enemy:SetAttribute("ShieldReduction", plan.reduction)

	while alive(enemy) do
		if not naps(enemy, 0.25) then
			return
		end

		-- Сзади — это против его собственного взгляда: щит смотрит вперёд, и тень от него
		-- падает назад. Метка ставится со сроком и истекает сама — так смерть Щитоносца
		-- мгновенно снимает прикрытие со всех без единого списка подопечных.
		local pivot = enemy:GetPivot()
		local back = -pivot.LookVector
		for _, other in enemiesAround(pivot.Position, plan.cover, enemy) do
			local toOther = flat(other:GetPivot().Position - pivot.Position)
			if toOther.Magnitude > 1e-3 and toOther.Unit:Dot(flat(back).Unit) > 0.3 then
				other:SetAttribute("CoveredUntil", os.clock() + 0.5)
				other:SetAttribute("CoverReduction", plan.reduction)
			end
		end
	end
end

-- Координатор: выбирает ОДНУ турель и шлёт на неё всех солдат вокруг.
-- «Уничтожить координатора — солдаты теряют фокус»: цель ставится со сроком и
-- без живого координатора просто истекает.
TRAITS.commands = function(enemy, enemyData, state)
	local plan = enemyData.commands

	while alive(enemy) do
		if not naps(enemy, plan.interval) then
			return
		end

		local at = enemy:GetPivot().Position
		local turret = nearestTurret(at)
		if turret then
			-- Срок вдвое больше шага: пока Координатор жив, он его продлевает; убили его —
			-- фокус истекает сам, и «солдаты теряют фокус» без единого списка подопечных.
			local expires = os.clock() + plan.interval * 2
			for _, other in enemiesAround(at, plan.radius, enemy) do
				local otherData = Enemies[other:GetAttribute("Type")]
				if otherData and otherData.caste == 2 then
					focus[other] = { turret = turret, expires = expires }
				end
			end
		end
	end
end

-- Таран: нацеливание — разгон по прямой — столкновение — оглушение.
-- На разгоне не поворачивает: направление берётся один раз и больше не пересчитывается.
TRAITS.rams = function(enemy, enemyData, state)
	local plan = enemyData.rams

	while alive(enemy) do
		if not naps(enemy, plan.cooldown) then
			return
		end

		-- Нацеливание: стоит на месте и смотрит туда, куда пойдёт.
		state.holdUntil = os.clock() + plan.windup
		print("[Таран] нацеливается")
		if not naps(enemy, plan.windup) then
			return
		end

		-- Направление фиксируется здесь и больше не меняется — в этом весь контр:
		-- смещённые стены и повороты выводят разгон в пустоту.
		state.dash = {
			direction = flat(enemy:GetPivot().LookVector * -1).Unit,
			left = plan.distance,
			speed = plan.speed,
			damage = plan.damage,
			stun = plan.stun,
		}
		state.holdUntil = nil

		-- Ждём, пока разгон отработает в общем цикле движения (см. EnemySpawner).
		while alive(enemy) and state.dash do
			if not naps(enemy, 0.1) then
				return
			end
		end
	end
end

-- Разносчик: впитывает элементы, которыми в него стреляют. Сам трейт ничего
-- не делает в цикле: накопление идёт через Absorb из Effects, взрыв — через Burst по смерти.
TRAITS.absorbs = function(enemy, enemyData, state)
	enemy:SetAttribute("Absorbs", enemyData.absorbs.capacity)
end

-- Впитать элемент. Зовётся из Effects при каждом попадании элементом.
local absorbed = setmetatable({}, { __mode = "k" })

function EnemyBehavior.Absorb(enemy, elementKey, damage)
	local capacity = enemy:GetAttribute("Absorbs")
	if not capacity then
		return
	end

	local store = absorbed[enemy]
	if not store then
		store = { keys = {}, damage = 0 }
		absorbed[enemy] = store
	end

	-- «Может впитать несколько элементов» — счёт по РАЗНЫМ элементам, а не по выстрелам:
	-- иначе любая очередь из одной турели мгновенно забивала бы ему всю ёмкость.
	if not store.keys[elementKey] and #store.keys < capacity then
		store.keys[elementKey] = true
	end
	store.damage += damage
end

-- Взрыв впитанным. Зовётся по смерти из EnemySpawner.
function EnemyBehavior.Burst(enemy, enemyData)
	local plan = enemyData.absorbs
	local store = absorbed[enemy]
	if not plan or not store or store.damage <= 0 then
		return
	end

	local at = enemy:GetPivot().Position
	local amount = math.floor(store.damage * plan.share + 0.5)
	ExplosionRemote:FireAllClients(at, plan.radius)

	-- Взрывается ИМЕННО впитанными элементами: каждый вешает на задетых свои эффекты,
	-- а не просто снимает HP. Пострадавшие — постройки и стол, как у Подрывника.
	local names = {}
	for key in store.keys do
		table.insert(names, key)
	end

	for _, tower in towersFolder:GetChildren() do
		if (tower:GetPivot().Position - at).Magnitude <= plan.radius then
			local hp = tower:GetAttribute("HP") or 0
			tower:SetAttribute("HP", math.max(0, hp - amount))
			DamageDealtRemote:FireAllClients(tower:GetPivot().Position, math.min(hp, amount), false)
		end
	end

	if (LabTable.Position() - at).Magnitude <= plan.radius then
		LabTable.Bite(amount)
	end
	LabStations.Blast(at, plan.radius, amount)

	EnemyStructures.Blast(at, plan.radius, amount)

	print(("[Разносчик] взрывается впитанным (%s): %d урона в радиусе %.0f")
		:format(#names > 0 and table.concat(names, ", ") or "ничего", amount, plan.radius))
end

-- Роевик: уходит под пол и появляется в другом месте. Копает только пока его
-- ведёт летающий координатор; без него «идёт в атаку слепо», то есть просто идёт.
TRAITS.burrows = function(enemy, enemyData, state)
	local plan = enemyData.burrows

	while alive(enemy) do
		if not naps(enemy, 3) then
			return
		end

		if os.clock() < (enemy:GetAttribute("GuidedUntil") or 0) then
			-- Нырок: пока под землёй — не цель для турелей (Hidden) и не толкается.
			state.holdUntil = os.clock() + plan.dive
			if not naps(enemy, plan.dive) then
				return
			end

			local at = enemy:GetPivot().Position
			enemy:SetAttribute("Hidden", true)
			enemy:PivotTo(CFrame.new(at - Vector3.new(0, plan.depth, 0)))
			state.burrowed = true
			print("[Роевик] ушёл под пол — координатор ведёт его к лаборатории")

			if not naps(enemy, plan.under) then
				return
			end

			-- Появляется из-под земли там, куда его вёл маршрут всё это время.
			state.burrowed = false
			enemy:SetAttribute("Hidden", nil)
			local now = enemy:GetPivot().Position
			enemy:PivotTo(CFrame.new(Vector3.new(now.X, 1.5, now.Z)))
		end
	end
end

-- Эволюционер: привыкает к тому элементу, которым игрок нанёс больше всего урона
-- за забег. Счёт ведёт Effects (Effects.ElementUsage) — он единственный, кто видит
-- все попадания сразу.
TRAITS.evolves = function(enemy, enemyData, state)
	local plan = enemyData.evolves

	while alive(enemy) do
		if not naps(enemy, plan.recheck) then
			return
		end

		local best, bestAmount = nil, 0
		for key, amount in Effects.ElementUsage do
			if amount > bestAmount then
				best, bestAmount = key, amount
			end
		end

		if best and best ~= enemy:GetAttribute("ResistElement") then
			enemy:SetAttribute("ResistElement", best)
			enemy:SetAttribute("ResistShare", plan.resistance)
			local data = Elements[best]
			print(("[Эволюционер] привык к %s — урон по нему срезан на %.0f%%")
				:format(data and data.name or best, plan.resistance * 100))
		end
	end
end

-- Носитель: высыпает жуков и по смерти, и по прибытии к лаборатории.
-- Сам трейт следит только за вторым: первое делает ветка смерти в EnemySpawner.
TRAITS.carries = function(enemy, enemyData, state)
	while alive(enemy) do
		if not naps(enemy, 0.5) then
			return
		end

		if (enemy:GetPivot().Position - LabTable.Position()).Magnitude <= LabTable.REACH + 4 then
			print("[Носитель] добрался до лаборатории и выпускает жуков внутри обороны")
			EnemyBehavior.Spill(enemy, enemyData)
			return
		end
	end
end

function EnemyBehavior.Spill(enemy, enemyData)
	local plan = enemyData.carries
	if not plan or enemy:GetAttribute("Spilled") then
		return
	end
	enemy:SetAttribute("Spilled", true)

	local at = enemy:GetPivot().Position
	if EnemyBehavior.Spawn then
		for _ = 1, plan.count do
			local offset = Vector3.new((math.random() - 0.5) * 6, 0, (math.random() - 0.5) * 6)
			EnemyBehavior.Spawn(plan.type, at + offset)
		end
	end
	print(("[Носитель] высыпалось %d x %s"):format(plan.count, plan.type))
end

-- Кукольник: заворачивает раненого в кокон. Завёрнутый исчезает с поля, а из кокона
-- выходит жук следующей касты — в этом вся цена оставленного раненого.
TRAITS.cocoons = function(enemy, enemyData, state)
	local plan = enemyData.cocoons

	while alive(enemy) do
		if not naps(enemy, plan.interval) then
			return
		end

		local at = enemy:GetPivot().Position
		local victim = nil
		for _, other in enemiesAround(at, plan.radius, enemy) do
			local hp, maxHp = other:GetAttribute("HP"), other:GetAttribute("MaxHP")
			local otherData = Enemies[other:GetAttribute("Type")]
			if hp and maxHp and hp < maxHp * plan.woundedBelow
				and otherData and otherData.caste and otherData.caste < 3 then
				victim = other
				break
			end
		end

		if victim then
			local victimData = Enemies[victim:GetAttribute("Type")]
			local nextCaste = Enemies.ByCaste[victimData.caste + 1]
			if nextCaste and #nextCaste > 0 then
				local hatchType = nextCaste[math.random(#nextCaste)]
				local spot = victim:GetPivot().Position
				print(("[Кукольник] завернул %s — из кокона выйдет %s")
					:format(victim.Name, hatchType))
				-- Сначала кокон, потом снос жука: его Destroy гасит его собственные трейты,
				-- и делать что-то после него с его же позицией было бы поздно.
				EnemyStructures.Cocoon(spot, hatchType, plan.hatch, plan.hp)
				victim:Destroy()
			end
		end
	end
end

-- Архитектор улья: стелит хитин под собой на ходу.
TRAITS.chitin = function(enemy, enemyData, state)
	local plan = enemyData.chitin

	while alive(enemy) do
		if not naps(enemy, plan.interval) then
			return
		end
		EnemyStructures.Chitin(enemy:GetPivot().Position)
	end
end

-- Мимик: стоит неподвижно и не числится целью, пока не раскроется.
TRAITS.mimics = function(enemy, enemyData, state)
	local plan = enemyData.mimics

	enemy:SetAttribute("Hidden", true)
	state.holdUntil = os.clock() + plan.patience
	local deadline = os.clock() + plan.patience

	while alive(enemy) do
		if not naps(enemy, 0.25) then
			return
		end

		local turret, distance = nearestTurret(enemy:GetPivot().Position)
		local close = turret ~= nil and distance <= plan.reveal
		if close or os.clock() >= deadline then
			enemy:SetAttribute("Hidden", nil)
			state.holdUntil = nil
			print("[Мимик] раскрылся и атакует")
			return
		end
	end
end

-- Тень: турели реагируют с задержкой. Сама задержка — в Targeting; здесь только число.
TRAITS.shadow = function(enemy, enemyData, state)
	enemy:SetAttribute("ShadowDelay", enemyData.shadow.delay)
end

-- Работяга: «Могут таскать строй-материалы» — подбирает обломок и относит его
-- к ближайшему Строителю: так замыкается связка «окопщик — работяга — строитель».
TRAITS.carriesMaterial = function(enemy, enemyData, state)
	while alive(enemy) do
		if not naps(enemy, 4) then
			return
		end

		local at = enemy:GetPivot().Position
		if not state.hauling then
			if EnemyStructures.TakeMaterial(at, 10) then
				state.hauling = true
			end
		else
			-- Нёс обломок и дошёл до Строителя — кладёт его туда, где тот его найдёт.
			for _, other in enemiesAround(at, 20, enemy) do
				local otherData = Enemies[other:GetAttribute("Type")]
				if otherData and otherData.builds then
					EnemyStructures.DropMaterial(other:GetPivot().Position, 1)
					state.hauling = false
					break
				end
			end
		end
	end
end

-- ============================ Запуск ============================

-- Собственный цикл движения вместо общего. Возвращает true, если ведёт жука до конца
-- и спавнеру делать больше нечего.
function EnemyBehavior.OwnLoop(enemy, enemyData, state)
	if enemyData.glow then
		mothLoop(enemy, enemyData, state)
		return true
	end
	if enemyData.lays then
		queenLoop(enemy, enemyData, state)
		return true
	end
	if enemyData.directs then
		swarmEyeLoop(enemy, enemyData, state)
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

-- Заводит состояние жука и запускает все его трейты. Трейт запускается тем и только
-- тем, что в записи врага есть поле с его именем.
function EnemyBehavior.Attach(enemy, enemyData)
	local state = { seed = math.random() * math.pi * 2 }

	for field, start in TRAITS do
		if enemyData[field] then
			task.spawn(start, enemy, enemyData, state)
		end
	end

	-- Фокус от Координатора приходит атрибутом со сроком; в state он перекладывается
	-- здесь, чтобы Goal не читал два атрибута каждый пересчёт маршрута.
	task.spawn(function()
		while alive(enemy) do
			task.wait(0.5)
			if not alive(enemy) then
				return
			end

			local before = state.focusTurret

			local order = focus[enemy]
			if order and os.clock() < order.expires and order.turret.Parent then
				state.focusTurret = order.turret
			else
				focus[enemy] = nil
				-- Группа работяг ставит свою цель сама (см. EnemyBehavior.State) — её сносить
				-- истекшим приказом Координатора нельзя.
				if state.focusTurret and not state.focusTurret.Parent then
					state.focusTurret = nil
				end
			end

			-- Смена цели САМА ПО СЕБЕ ничего не делает: маршрут пересчитывается только по
			-- смене занятости клеток (Grid.Changed), а приказ Координатора занятость не меняет.
			-- Без этого флага солдаты продолжали идти к лаборатории по старому пути, и ни
			-- Координатор, ни вышедшая группа работяг не доходили до турели вовсе
			-- (найдено замером: щитоносцы уходили от турели с 48 студов на 112).
			if state.focusTurret ~= before then
				state.repath = true
			end
		end
	end)

	return state
end

return EnemyBehavior
