-- Аркада: отдельный от лабораторной обороны режим. Открытое поле, машина и жуки разных видов,
-- которые бродят стаями и разбегаются от машины, — их можно давить. Цели нет: очки, комбо
-- и рекорд только для удовольствия, изредка пробегает золотой жук.
--
-- Исключение из правила «вся логика на сервере» (решение автора, #176): машина — настоящая
-- физическая сборка, и считает её клиент водителя (StarterPlayerScripts.ArcadeCar) вместе с
-- трупами на поле. Игра рассчитана на одного, а удар корпусом по туше должен считаться там,
-- где его видно, без задержки сети. Сервер ставит машину и водит жуков; кого раздавили, решает
-- тот же клиент (ArcadeSquash): по серверной позиции машины, опоздавшей на сеть, труп
-- появлялся там, где машина уже стоит у игрока, — дёргался и проваливался сквозь корпус.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local Balance = require(ReplicatedStorage:WaitForChild("Arcade"))
local Enemies = require(ReplicatedStorage:WaitForChild("Enemies"))
-- Жук аркады на сервере — невидимый якорь (EnemyModel.Strip); модель и походку рисует клиент
-- (StarterPlayerScripts.EnemyRender), как и у жуков арены.
local EnemyModel = require(ReplicatedStorage:WaitForChild("EnemyModel"))
local Corpses = require(ServerScriptService:WaitForChild("Corpses"))
local Loose = require(ReplicatedStorage:WaitForChild("Loose"))
local PhysicsFX = require(ReplicatedStorage:WaitForChild("PhysicsFX"))
local PlayerData = require(ServerScriptService:WaitForChild("PlayerData"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RequestEnterArcadeRemote = Remotes:WaitForChild("RequestEnterArcade")
local RequestExitArcadeRemote = Remotes:WaitForChild("RequestExitArcade")
local ArcadeEnteredRemote = Remotes:WaitForChild("ArcadeEntered")
local ArcadeExitedRemote = Remotes:WaitForChild("ArcadeExited")
local ArcadeSquashCountRemote = Remotes:WaitForChild("ArcadeSquashCount")
local ArcadeSquashRemote = Remotes:WaitForChild("ArcadeSquash")

local arcadeFolder = Workspace:WaitForChild("Arcade")
local field = arcadeFolder:WaitForChild("Field")
local arcadeSpawn = arcadeFolder:WaitForChild("ArcadeSpawn")
local carTemplate = ServerStorage:WaitForChild("ArcadeCarTemplate")
local lobbySpawn = Workspace:WaitForChild("SpawnLocation")

-- Отступ от ограждения: жук или машина у самой стены выглядят так, будто вот-вот
-- провалятся за карту, хотя стена их честно держит.
local HALF = (arcadeFolder:GetAttribute("Half") or 130) - Balance.bugs.fieldMargin
local GROUND_Y = field.Position.Y + field.Size.Y / 2
-- Высота пивота машины при появлении: низ всех колёс шаблона выровнен на -2.0 от пивота
-- (атрибут Wheel в ArcadeCarTemplate) — машина встаёт на поле на свою подвеску, а не падает.
local CAR_RIDE_HEIGHT = 2.0

local BUGS = Balance.bugs
local BUG_COUNT = BUGS.count
local BUG_TURN_MIN, BUG_TURN_MAX = BUGS.turnMin, BUGS.turnMax
local RESPAWN_DELAY = BUGS.respawnDelay
local GOLDEN = Balance.golden
local COMBO = Balance.combo

-- Радиус давки машины; полуразмер туловища жука прибавляет к нему клиент по атрибуту Reach
-- самого жука — у Гиганта и Мини он разный.
local CAR_REACH = carTemplate:GetAttribute("SquashRadius") or Balance.car.squashRadius

-- ---- виды на поле ----
-- Вид аркады = строка Balance.species + данные вида из Enemies (шаблон, масштаб, высота хода).
-- Вид без шаблона в месте не выходит на поле: EnemyModel.FromTemplate ждал бы его вечно.
local function makeKind(row)
	local data = Enemies[row.type]
	local template = data and data.model and ReplicatedStorage:FindFirstChild(data.model)
	if not template then
		warn(("[Arcade] вид %s пропущен: нет шаблона в ReplicatedStorage"):format(tostring(row.type)))
		return nil
	end
	local base = data.scale or (data.scaleRange and (data.scaleRange[1] + data.scaleRange[2]) / 2) or 3
	local scale = base * (row.size or 1)
	local _, size = template:GetBoundingBox()
	return {
		type = row.type,
		template = data.model,
		scale = scale,
		-- Высота пивота растёт с масштабом — то же правило, что в EnemyModel.Build.
		rideHeight = (data.rideHeight or base) * (row.size or 1),
		speed = BUGS.speed * (row.speed or 1),
		points = row.points or 10,
		weight = row.weight or 1,
		-- Давится, если машина задела тело, а не только центр.
		reach = math.max(size.X, size.Z) / 2 * scale * BUGS.reach,
	}
end

local kinds = {}
local totalWeight = 0
for _, row in Balance.species do
	local kind = makeKind(row)
	if kind then
		table.insert(kinds, kind)
		totalWeight += kind.weight
	end
end
assert(#kinds > 0, "[Arcade] ни одного вида жуков с шаблоном")
local maxReach = 0
for _, kind in kinds do
	maxReach = math.max(maxReach, kind.reach)
end

local goldenKind = makeKind({ type = GOLDEN.type, speed = GOLDEN.speed, points = GOLDEN.points }) or kinds[1]

local function pickKind()
	local roll = math.random() * totalWeight
	for _, kind in kinds do
		roll -= kind.weight
		if roll <= 0 then
			return kind
		end
	end
	return kinds[#kinds]
end

-- LOD хода. Походку теперь рисует клиент, сервер двигает один якорь, — но каждый
-- сдвиг якоря уходит по сети. Рядом с машиной жук идёт каждый кадр, дальше — раз
-- в несколько кадров с накопленным dt: клиент сглаживает, а давить можно только тех, кто рядом.
local GAIT_NEAR = Balance.gait.near
local GAIT_MID = Balance.gait.mid
local GAIT_MID_EVERY = Balance.gait.midEvery
local GAIT_FAR_EVERY = Balance.gait.farEvery
local GAIT_MAX_DT = Balance.gait.maxDt -- потолок накопленного шага, чтобы жук не прыгал после фриза сервера

-- Кровь давки: машина выжимает больше, чем смерть на арене (PhysicsFX.blood.death), — свои
-- числа. Форма, брызги и высыхание — те же, что у арены (BloodFX).
local SPLAT_SIZE = Balance.splat.size -- на жука масштаба 3, как у арены (Corpses считает scale = Scale / 3)
local SPLAT_DROPS = Balance.splat.drops

-- Корпус сталкивается с полем, ограждением и трупами — это настоящая физика, — но не с жуками:
-- давку считает код, и жук под колёсами не должен подбрасывать машину. Колёса — своя группа:
-- пол держат лучи подвески (клиент), а сами колёса только расшвыривают трупы и куски,
-- в которые въехали. Группы и кто с кем сталкивается — в общем физическом слое (Loose).
Loose.SetupGroups()
local CAR_GROUP = Loose.Groups.Car
local WHEEL_GROUP = Loose.Groups.Wheel

local function randomEdge()
	return (math.random() * 2 - 1) * HALF
end

local function clampToField(pos)
	return Vector3.new(math.clamp(pos.X, -HALF, HALF), pos.Y, math.clamp(pos.Z, -HALF, HALF))
end

local function headingAt(angle)
	return Vector3.new(math.sin(angle), 0, math.cos(angle))
end

local function nextTurnTime(now)
	return now + BUG_TURN_MIN + math.random() * (BUG_TURN_MAX - BUG_TURN_MIN)
end

-- ============ Жуки ============

local bugsFolder = Instance.new("Folder")
bugsFolder.Name = "ArcadeBugs"
bugsFolder.Parent = arcadeFolder

-- Фиксированный список мест-слотов: раздавленный жук освобождает свой слот, а не
-- выпадает из списка — так respawn не может ни потерять слот, ни расплодить лишние.
-- Слоты поделены на стаи по herdSize: у стаи общий курс, жук держится рядом со своими.
local herds = {}
local bugs = {}
for i = 1, BUG_COUNT do
	local herdIndex = math.ceil(i / BUGS.herdSize)
	local herd = herds[herdIndex]
	if not herd then
		herd = { heading = Vector3.new(0, 0, 1), nextTurn = 0, center = nil, sum = Vector3.zero, alive = 0 }
		herds[herdIndex] = herd
	end
	bugs[i] = {
		model = nil,
		herd = herd,
		heading = Vector3.new(0, 0, 1),
		wander = 0,
		pos = Vector3.zero,
		pending = 0,
		panicUntil = 0,
	}
end
-- Отдельный слот золотого жука: он не из стаи и не занимает место обычного.
local goldenSlot = { model = nil, golden = true, heading = Vector3.new(0, 0, 1), wander = 0, pos = Vector3.zero,
	pending = 0, panicUntil = 0, nextTurn = 0 }
table.insert(bugs, goldenSlot)
local nextGoldenAt = math.huge

-- Сессии объявлены здесь: место появления жука зависит от того, где машины.
local sessions = {} -- [player] = { car, seat, chassis, pos, speed, squashCount, score, combo... }
local activeCount = 0

-- Точка появления: рядом с живыми из своей стаи, иначе — на кольце вокруг случайной машины;
-- машин нет — где угодно. Не ближе spawnMin к машине: жук не рождается под колёсами.
local function farFromCars(pos)
	for _, session in sessions do
		local dx, dz = pos.X - session.pos.X, pos.Z - session.pos.Z
		if dx * dx + dz * dz < BUGS.spawnMin * BUGS.spawnMin then
			return false
		end
	end
	return true
end

local function spawnPoint(slot)
	local herd = slot.herd
	if herd and herd.center and herd.alive > 0 then
		for _ = 1, 6 do
			local angle = math.random() * math.pi * 2
			local pos = clampToField(herd.center + headingAt(angle) * math.random() * BUGS.herdSpread)
			if farFromCars(pos) then
				return pos
			end
		end
	end
	local anchors = {}
	for _, session in sessions do
		table.insert(anchors, session.pos)
	end
	for _ = 1, 8 do
		local pos
		if #anchors > 0 then
			local around = anchors[math.random(#anchors)]
			local distance = BUGS.spawnMin + math.random() * (BUGS.spawnMax - BUGS.spawnMin)
			pos = clampToField(around + headingAt(math.random() * math.pi * 2) * distance)
		else
			pos = Vector3.new(randomEdge(), 0, randomEdge())
		end
		if farFromCars(pos) then
			return pos
		end
	end
	return Vector3.new(randomEdge(), 0, randomEdge())
end

local function fillBugSlot(slot, kind)
	kind = kind or pickKind()
	-- Тот же шаблон и масштаб, что строит клиент; серверу от него нужен только якорь с атрибутами
	-- Scale/Template (по ним клиент собирает тело, а труп — свой размер).
	local model = EnemyModel.Strip(EnemyModel.FromTemplate(kind.template, kind.scale, nil))
	model.Name = "ArcadeBug"
	model:SetAttribute("Template", kind.template)
	model:SetAttribute("Reach", kind.reach)
	model:SetAttribute("Kind", kind.type)
	if slot.golden then
		model:SetAttribute("Golden", true)
	end

	local flat = spawnPoint(slot)
	local worldPos = Vector3.new(flat.X, GROUND_Y + kind.rideHeight, flat.Z)
	local heading = slot.herd and slot.herd.heading or headingAt(math.random() * math.pi * 2)
	model:PivotTo(CFrame.lookAt(worldPos, worldPos + heading) * CFrame.Angles(0, math.pi, 0))
	model.Parent = bugsFolder

	slot.model = model
	slot.kind = kind
	slot.heading = heading
	slot.wander = (math.random() * 2 - 1) * BUGS.wander
	slot.pos = worldPos -- маршрутная точка: пивот модели качается походкой и для маршрута не годится
	slot.pending = 0
	slot.panicUntil = 0
	slot.nextTurn = nextTurnTime(os.clock())
	if slot.golden then
		slot.expires = os.clock() + GOLDEN.lifetime
	end
end

local function emptyBugSlot(slot)
	if slot.model then
		slot.model:Destroy()
		slot.model = nil
	end
	if slot.golden then
		nextGoldenAt = os.clock() + GOLDEN.everyMin + math.random() * (GOLDEN.everyMax - GOLDEN.everyMin)
	end
end

local function updateHerds()
	for _, herd in herds do
		herd.sum = Vector3.zero
		herd.alive = 0
	end
	for _, slot in bugs do
		local herd = slot.herd
		if herd and slot.model then
			herd.sum += slot.pos
			herd.alive += 1
		end
	end
	for _, herd in herds do
		herd.center = herd.alive > 0 and herd.sum / herd.alive or nil
	end
end

-- ============ Сессии игроков ============

local function fillAllBugs()
	updateHerds()
	for _, slot in bugs do
		if not slot.model and not slot.golden then
			fillBugSlot(slot)
			updateHerds() -- следующий из той же стаи встаёт рядом с этим
		end
	end
	nextGoldenAt = os.clock() + GOLDEN.everyMin + math.random() * (GOLDEN.everyMax - GOLDEN.everyMin)
end

local function emptyAllBugs()
	for _, slot in bugs do
		emptyBugSlot(slot)
	end
	nextGoldenAt = math.huge
end

-- carPos — откуда наехала машина: давка — удар в 100% HP, конечности летят от неё (см. Corpses.Leave).
-- carry — скорость, которую туша и куски берут у машины.
local function killBug(slot, carPos, carry)
	local model = slot.model
	if model then
		-- Труп и кровь — до уничтожения, пока модель ещё цела и стоит там, где её
		-- раздавили (тот же порядок, что и в EnemySpawner) — поле аркады на своей
		-- высоте, отличной от пола арены, поэтому Corpses.Splat принимает GROUND_Y явно.
		local scale = model:GetAttribute("Scale") or 3
		-- Брызги — по ходу машины (а стоит — от неё).
		local at = model:GetPivot().Position
		local push = carry and Vector3.new(carry.X, 0, carry.Z) or Vector3.zero
		if push.Magnitude < 1 and carPos then
			push = Vector3.new(at.X - carPos.X, 0, at.Z - carPos.Z)
		end
		Corpses.Splat(at, SPLAT_SIZE * scale / 3, SPLAT_DROPS, GROUND_Y,
			push.Magnitude > 1e-3 and push.Unit * PhysicsFX.blood.stretch or nil)
		Corpses.Leave(model, { fraction = 1, from = carPos, floorY = GROUND_Y, carry = carry, remains = "crush" })
	end
	emptyBugSlot(slot)
	if slot.golden then
		return -- золотой приходит по своему таймеру, а не сразу на место пойманного
	end
	task.delay(RESPAWN_DELAY, function()
		-- Поле опустело, пока жук ждал возрождения — досыпать жертву уже некому.
		if activeCount > 0 and not slot.model then
			fillBugSlot(slot)
		end
	end)
end

-- ---- очки, комбо, рекорд ----
-- Ступень комбо по длине серии: множитель очков и её номер (для звука и цвета на клиенте).
local function comboTier(combo)
	local tier, mult = 1, 1
	for index, row in COMBO.tiers do
		if combo >= row.from then
			tier, mult = index, row.mult
		end
	end
	return tier, mult
end

-- Лучшее из сохранения. Таблица arcade досыпается Reconcile'ом у старых профилей целиком;
-- поля внутри читаются с запасом на случай, если их добавят позже.
local function readBest(player)
	local data = PlayerData.Get(player)
	local arcade = data and data.arcade
	return arcade and (arcade.bestScore or 0) or 0, arcade and (arcade.bestCombo or 0) or 0
end

-- Пишется на каждой давке, а не на выходе: при выходе из игры профиль может закрыться
-- раньше, чем дойдёт очередь до сессии аркады.
local function recordSquash(player, session)
	local data = PlayerData.Get(player)
	if not data then
		return
	end
	data.arcade = data.arcade or {}
	local arcade = data.arcade
	arcade.bestScore = math.max(arcade.bestScore or 0, session.score)
	arcade.bestCombo = math.max(arcade.bestCombo or 0, session.bestCombo)
	arcade.squashed = (arcade.squashed or 0) + 1
end

local function teleportToLobby(player)
	local character = player.Character
	if not character then
		return
	end
	-- HumanoidRootPart принадлежит клиенту по сети: без явной передачи владения
	-- серверу клиент через мгновение реплицирует свою старую позицию
	-- поверх PivotTo, и телепорт откатывается через долю секунды.
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if hrp then
		hrp:SetNetworkOwner(nil)
	end
	character:PivotTo(lobbySpawn.CFrame + Vector3.new(0, 3, 0))
	if hrp then
		task.delay(1, function()
			if hrp.Parent then
				local ok = pcall(function()
					hrp:SetNetworkOwnershipAuto()
				end)
			end
		end)
	end
end

local function endSession(player, skipTeleport)
	local session = sessions[player]
	if not session then
		return
	end
	sessions[player] = nil
	activeCount = math.max(0, activeCount - 1)

	if session.characterConn then
		session.characterConn:Disconnect()
	end
	if session.seatConn then
		session.seatConn:Disconnect()
	end

	-- Снять с сиденья до телепорта: иначе SeatWeld ещё держит HumanoidRootPart,
	-- и PivotTo не может утащить персонажа с места машины.
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.Sit = false
	end

	if session.car then
		session.car:Destroy()
	end

	if activeCount == 0 then
		emptyAllBugs()
	end

	if not skipTeleport then
		teleportToLobby(player)
	end

	-- Итог заезда для плашки на клиенте (ArcadeHud). Меню второй аргумент не читает.
	ArcadeExitedRemote:FireClient(player, {
		squashed = session.squashCount,
		score = session.score,
		bestCombo = session.bestCombo,
		record = session.score > session.startBest and session.score > 0,
		best = math.max(session.startBest, session.score),
	})
end

local function startSession(player)
	if sessions[player] then
		return
	end
	local character = player.Character
	if not character then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	local firstDriver = activeCount == 0
	activeCount += 1

	local hrp = character:FindFirstChild("HumanoidRootPart")
	if hrp then
		hrp:SetNetworkOwner(nil)
	end
	character:PivotTo(arcadeSpawn.CFrame + Vector3.new(0, 3, 0))

	local car = carTemplate:Clone()
	car.Name = "ArcadeCar_" .. player.Name
	car:SetAttribute("ArcadeCar", true) -- по нему клиент узнаёт машину, в которой сидит
	car:SetAttribute("SquashReach", CAR_REACH) -- радиус давки машины; полуразмер жука — его атрибут Reach

	-- Физическая сборка. Корпус держит подвеска на лучах (клиент), а не колёсные шарниры:
	-- колёса у тачки разного размера, и шарнирная подвеска на них валила бы её набок.
	-- Колёса висят на Motor6D — клиент крутит, поворачивает и поднимает их по ходу подвески.
	-- Всё, кроме рамы, невесомое: центр тяжести в раме, и тачка не кувыркается от первого трупа.
	local chassis = car.PrimaryPart
	local templatePivot = car:GetPivot()
	local chassisOffset = templatePivot:ToObjectSpace(chassis.CFrame)
	chassis:SetAttribute("BaseOffset", chassisOffset) -- кадр «нос по +Z» = chassis.CFrame * BaseOffset:Inverse()
	chassis.RootPriority = 127
	chassis.CustomPhysicalProperties = PhysicalProperties.new(Balance.car.chassisDensity, 0.3, 0.1, 1, 1)
	for _, p in car:GetDescendants() do
		if p:IsA("BasePart") then
			local wheel = p:GetAttribute("Wheel") == true
			p.CanCollide = p:GetAttribute("Detail") ~= true
			p.CanTouch = false
			p.CollisionGroup = wheel and WHEEL_GROUP or CAR_GROUP
			p.Massless = p ~= chassis
			if wheel then
				local offset = templatePivot:ToObjectSpace(p.CFrame)
				p:SetAttribute("RestOffset", offset)
				local axle = Instance.new("Motor6D")
				axle.Name = "Axle"
				axle.Part0 = chassis
				axle.Part1 = p
				axle.C0 = chassisOffset:Inverse() * CFrame.new(offset.Position)
				axle.C1 = offset.Rotation:Inverse()
				axle.Parent = p
			elseif p ~= chassis then
				-- Диски и болты (WheelPart) — на своё колесо, остальное — на раму.
				local wheelName = p:GetAttribute("WheelPart")
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = wheelName and car:FindFirstChild(wheelName) or chassis
				weld.Part1 = p
				weld.Parent = p
			end
		end
	end

	local startPos = Vector3.new(arcadeSpawn.Position.X, GROUND_Y + CAR_RIDE_HEIGHT, arcadeSpawn.Position.Z)
	-- Носом к центру поля: спавн у северной стены, и с yaw = 0 машина стояла носом в
	-- ограждение — первое нажатие газа вдавливало её в стену. forward = (sin yaw, 0, cos yaw).
	local startYaw = (startPos.X ~= 0 or startPos.Z ~= 0) and math.atan2(-startPos.X, -startPos.Z) or 0
	car:PivotTo(CFrame.new(startPos) * CFrame.Angles(0, startYaw, 0) * templatePivot.Rotation)
	car.Parent = arcadeFolder
	for _, p in car:GetDescendants() do
		if p:IsA("BasePart") then
			p.Anchored = false
		end
	end

	-- Сборку считает водитель. Повторяется при каждой посадке: персонаж вваривается в сборку,
	-- и владение не должно достаться кому-то по умолчанию.
	local function giveCar()
		pcall(function()
			chassis:SetNetworkOwner(player)
		end)
	end
	giveCar()

	local seat = car:FindFirstChild("DriverSeat")

	local session = {
		car = car,
		seat = seat,
		chassis = chassis,
		baseInverse = chassisOffset:Inverse(),
		pos = startPos,
		speed = 0,
		squashCount = 0,
		score = 0,
		combo = 0,
		comboUntil = 0,
		bestCombo = 0,
	}
	local bestScore, bestCombo = readBest(player)
	session.startBest = bestScore
	sessions[player] = session
	-- После записи сессии: жуки встают кольцом вокруг машины, а не под ней.
	if firstDriver then
		fillAllBugs()
	end

	session.characterConn = player.CharacterAdded:Connect(function()
		endSession(player, true)
	end)

	task.defer(function()
		if seat and humanoid.Parent then
			seat:Sit(humanoid)
		end
	end)

	-- Прыжок (Space, кнопка прыжка на телефоне) выкидывает из VehicleSeat, и игрок
	-- оставался пешком посреди поля без машины. Выход из аркады — только через меню,
	-- поэтому водителя сразу сажают обратно.
	if seat then
		session.seatConn = seat:GetPropertyChangedSignal("Occupant"):Connect(function()
			if seat.Occupant ~= nil then
				giveCar()
			else
				task.delay(0.1, function()
					if sessions[player] == session and seat.Parent and seat.Occupant == nil and humanoid.Parent and humanoid.Health > 0 then
						seat:Sit(humanoid)
					end
				end)
			end
		end)
	end

	ArcadeEnteredRemote:FireClient(player, { best = bestScore, bestCombo = bestCombo })
end

RequestEnterArcadeRemote.OnServerEvent:Connect(function(player)
	startSession(player)
end)

RequestExitArcadeRemote.OnServerEvent:Connect(function(player)
	endSession(player)
end)

Players.PlayerRemoving:Connect(function(player)
	endSession(player, true)
end)

-- ============ Кадр ============

local frameIndex = 0

-- Ближайшая к точке машина, которая едет достаточно быстро, чтобы пугать: её позиция и
-- квадрат расстояния до неё. Медленная машина жуков не пугает, но LOD считает и её.
local function nearestCar(pos)
	local nearestSq, scary, scarySq = math.huge, nil, math.huge
	for _, session in sessions do
		local dx, dz = pos.X - session.pos.X, pos.Z - session.pos.Z
		local d = dx * dx + dz * dz
		nearestSq = math.min(nearestSq, d)
		if session.speed >= BUGS.fleeCarSpeed and d < scarySq then
			scary, scarySq = session.pos, d
		end
	end
	return nearestSq, scary, scarySq
end

RunService.Heartbeat:Connect(function(dt)
	if activeCount == 0 then
		return
	end
	dt = math.min(dt, 0.1)
	frameIndex += 1

	-- ---- машины едут на клиенте; сервер только читает, где они (давка, испуг и LOD походки) ----
	for _, session in sessions do
		local chassis = session.chassis
		if chassis and chassis.Parent then
			session.pos = (chassis.CFrame * session.baseInverse).Position
			local v = chassis.AssemblyLinearVelocity
			session.speed = Vector3.new(v.X, 0, v.Z).Magnitude
		end
	end

	local now = os.clock()

	-- ---- стаи: общий курс, середина — куда подтягиваются отставшие ----
	updateHerds()
	for _, herd in herds do
		if now >= herd.nextTurn then
			herd.heading = headingAt(math.random() * math.pi * 2)
			herd.nextTurn = nextTurnTime(now)
		end
	end

	-- ---- золотой: появляется по таймеру, не пойманный — уходит ----
	if goldenSlot.model and now >= (goldenSlot.expires or math.huge) then
		emptyBugSlot(goldenSlot)
	elseif not goldenSlot.model and now >= nextGoldenAt then
		nextGoldenAt = math.huge
		fillBugSlot(goldenSlot, goldenKind)
	end

	-- ---- жуки: бродят стаями, от машины разбегаются ----
	for index, slot in bugs do
		local model = slot.model
		if model then
			slot.pending += dt
			local nearestSq, scary, scarySq = nearestCar(slot.pos)
			local every = nearestSq <= GAIT_NEAR * GAIT_NEAR and 1
				or nearestSq <= GAIT_MID * GAIT_MID and GAIT_MID_EVERY
				or GAIT_FAR_EVERY
			-- Сдвиг по номеру слота: дальние жуки шагают вразнобой, а не все в один кадр.
			if (frameIndex + index) % every == 0 then
				local stepDt = math.min(slot.pending, GAIT_MAX_DT)
				slot.pending = 0
				local pos = slot.pos

				-- Испуг: прочь от машины с разбросом — стая рассыпается веером.
				local fleeRadius = slot.golden and GOLDEN.fleeRadius or BUGS.fleeRadius
				if scary and scarySq <= fleeRadius * fleeRadius then
					local away = Vector3.new(pos.X - scary.X, 0, pos.Z - scary.Z)
					if away.Magnitude > 1e-3 then
						local angle = math.atan2(away.X, away.Z) + (math.random() * 2 - 1) * BUGS.fleeJitter
						slot.heading = headingAt(angle)
					end
					slot.panicUntil = now + BUGS.fleeTime
				elseif now >= slot.panicUntil then
					local herd = slot.herd
					if herd then
						-- Курс стаи со своим разбросом; отставший доворачивает к середине.
						local base = herd.heading
						local angle = math.atan2(base.X, base.Z) + slot.wander
						local want = headingAt(angle)
						if herd.center then
							local toCenter = Vector3.new(herd.center.X - pos.X, 0, herd.center.Z - pos.Z)
							if toCenter.Magnitude > BUGS.herdSpread then
								want = (want * (1 - BUGS.herdPull) + toCenter.Unit * BUGS.herdPull).Unit
							end
						end
						slot.heading = want
					elseif now >= slot.nextTurn then
						slot.heading = headingAt(math.random() * math.pi * 2)
						slot.nextTurn = nextTurnTime(now)
					end
				end

				local speed = slot.kind.speed * (now < slot.panicUntil and BUGS.fleeSpeed or 1)
				local nextPos = pos + slot.heading * speed * stepDt

				-- Отражение от ограждения, а не остановка: жук у края читается живым,
				-- только если он от края тут же убегает, а не липнет к нему. Стая
				-- отражается целиком, иначе её курс снова вдавит жука в стену.
				local bounced = false
				local hx, hz = slot.heading.X, slot.heading.Z
				if nextPos.X > HALF or nextPos.X < -HALF then
					hx = -hx
					bounced = true
				end
				if nextPos.Z > HALF or nextPos.Z < -HALF then
					hz = -hz
					bounced = true
				end
				if bounced then
					slot.heading = Vector3.new(hx, 0, hz)
					local herd = slot.herd
					if herd then
						local h = herd.heading
						herd.heading = Vector3.new(
							(nextPos.X > HALF and -math.abs(h.X)) or (nextPos.X < -HALF and math.abs(h.X)) or h.X,
							0,
							(nextPos.Z > HALF and -math.abs(h.Z)) or (nextPos.Z < -HALF and math.abs(h.Z)) or h.Z
						)
						herd.nextTurn = nextTurnTime(now)
					end
					nextPos = pos + slot.heading * speed * stepDt
				end
				nextPos = Vector3.new(
					math.clamp(nextPos.X, -HALF, HALF),
					GROUND_Y + slot.kind.rideHeight,
					math.clamp(nextPos.Z, -HALF, HALF)
				)

				-- Сервер ставит якорь в маршрутный кадр; шаги и качание тела по ступням —
				-- клиентская EnemyGait в EnemyRender, та же, что у жуков арены.
				slot.pos = nextPos
				model:PivotTo(CFrame.lookAt(nextPos, nextPos + slot.heading) * CFrame.Angles(0, math.pi, 0))
			end
		end
	end
end)

-- ---- давилка: кого переехал, сообщает водитель (StarterPlayerScripts.ArcadeCar) ----
-- Проверка мягкая, игра на одного: жук живой, машина своя, и наезд не за полполя от неё.
local SQUASH_TRUST = CAR_REACH + math.max(maxReach, goldenKind.reach) + 40
local MAX_CARRY = Balance.car.maxSpeed * 2
ArcadeSquashRemote.OnServerEvent:Connect(function(player, model, carPos, carry)
	local session = sessions[player]
	if not session or typeof(model) ~= "Instance" or model.Parent ~= bugsFolder
		or typeof(carPos) ~= "Vector3" or typeof(carry) ~= "Vector3" then
		return
	end
	local flat = Vector3.new(carPos.X - session.pos.X, 0, carPos.Z - session.pos.Z)
	-- «not <=», а не «>»: NaN в carPos проходил сравнение и уходил трупу направлением разлёта.
	if not (flat.Magnitude <= SQUASH_TRUST) or carry.Magnitude ~= carry.Magnitude then
		return
	end
	if carry.Magnitude > MAX_CARRY then
		carry = carry.Unit * MAX_CARRY
	end
	for _, slot in bugs do
		if slot.model == model then
			-- Сам жук тоже должен быть у машины, а не на другом краю поля: иначе клиент
			-- «давил» бы всех жуков подряд, не сдвинувшись, — и это шло в рекорд профиля.
			local gap = Vector3.new(slot.pos.X - session.pos.X, 0, slot.pos.Z - session.pos.Z)
			if gap.Magnitude > SQUASH_TRUST then
				return
			end
			local now = os.clock()
			session.combo = now <= session.comboUntil and session.combo + 1 or 1
			session.comboUntil = now + COMBO.window
			session.bestCombo = math.max(session.bestCombo, session.combo)
			local tier, mult = comboTier(session.combo)
			local points = slot.kind.points * mult
			session.squashCount += 1
			session.score += points
			recordSquash(player, session)
			ArcadeSquashCountRemote:FireClient(player, session.squashCount, {
				score = session.score,
				points = points,
				combo = session.combo,
				tier = tier,
				mult = mult,
				window = COMBO.window,
				at = slot.pos,
				golden = slot.golden == true,
			})
			killBug(slot, carPos, carry)
			return
		end
	end
end)

print("[Arcade] режим готов: поле half =", HALF, "жуков =", BUG_COUNT, "видов =", #kinds)
