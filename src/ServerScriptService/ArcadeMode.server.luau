-- Аркада: отдельный от лабораторной обороны режим. Открытое поле, машина, медленные жуки,
-- которых можно давить.
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
local PhysicsService = game:GetService("PhysicsService")

local Balance = require(ReplicatedStorage:WaitForChild("Arcade"))
-- Жук аркады на сервере — невидимый якорь (EnemyModel.Strip); модель и походку рисует клиент
-- (StarterPlayerScripts.EnemyRender), как и у жуков арены.
local EnemyModel = require(ReplicatedStorage:WaitForChild("EnemyModel"))
local Corpses = require(ServerScriptService:WaitForChild("Corpses"))

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
local BUG_TEMPLATE = "NormalBeetleTemplate"
local bugTemplate = ReplicatedStorage:WaitForChild(BUG_TEMPLATE)
local lobbySpawn = Workspace:WaitForChild("SpawnLocation")

-- Отступ от ограждения: жук или машина у самой стены выглядят так, будто вот-вот
-- провалятся за карту, хотя стена их честно держит.
local HALF = (arcadeFolder:GetAttribute("Half") or 130) - Balance.bugs.fieldMargin
local GROUND_Y = field.Position.Y + field.Size.Y / 2
-- Высота пивота машины при появлении: низ всех колёс шаблона выровнен на -2.0 от пивота
-- (атрибут Wheel в ArcadeCarTemplate) — машина встаёт на поле на свою подвеску, а не падает.
local CAR_RIDE_HEIGHT = 2.0
-- Жуки аркады втрое крупнее шаблона (просьба автора). Высота пивота растёт вместе с масштабом —
-- то же правило, что RideHeight = templateScale в EnemySpawner.buildTemplateModel.
local BUG_SCALE = Balance.bugs.scale
local BUG_RIDE_HEIGHT = BUG_SCALE

local BUG_COUNT = Balance.bugs.count
local BUG_SPEED = Balance.bugs.speed
local BUG_TURN_MIN, BUG_TURN_MAX = Balance.bugs.turnMin, Balance.bugs.turnMax
-- Давится, если машина задела тело, а не только центр: к радиусу машины добавлен
-- полуразмер туловища жука в его аркадном масштабе.
local BUG_REACH = (function()
	local _, size = bugTemplate:GetBoundingBox()
	return math.max(size.X, size.Z) / 2 * BUG_SCALE * Balance.bugs.reach
end)()
local SQUASH_RADIUS = (carTemplate:GetAttribute("SquashRadius") or Balance.car.squashRadius) + BUG_REACH
local RESPAWN_DELAY = Balance.bugs.respawnDelay

-- LOD хода. Походку теперь рисует клиент, сервер двигает один якорь, — но каждый
-- сдвиг якоря уходит по сети. Рядом с машиной жук идёт каждый кадр, дальше — раз
-- в несколько кадров с накопленным dt: клиент сглаживает, а давить можно только тех, кто рядом.
local GAIT_NEAR = Balance.gait.near
local GAIT_MID = Balance.gait.mid
local GAIT_MID_EVERY = Balance.gait.midEvery
local GAIT_FAR_EVERY = Balance.gait.farEvery
local GAIT_MAX_DT = Balance.gait.maxDt -- потолок накопленного шага, чтобы жук не прыгал после фриза сервера

-- Те же числа, что и у обычной смерти в EnemySpawner (DEATH_SPLAT_SIZE/DROPS) —
-- труп и кровь того же жука, что и на арене.
local SPLAT_SIZE = Balance.splat.size -- на жука масштаба 3, как у арены (Corpses считает scale = Scale / 3)
local SPLAT_DROPS = Balance.splat.drops

-- Корпус сталкивается с полем, ограждением и трупами — это настоящая физика, — но не с жуками:
-- давку считает код, и жук под колёсами не должен подбрасывать машину. Колёса — своя группа:
-- пол держат лучи подвески (клиент), а сами колёса только расшвыривают трупы и куски,
-- в которые въехали. Группы заводятся в коде, как в Corpses.
local CAR_GROUP = "ArcadeCar"
local WHEEL_GROUP = "ArcadeWheel"
for _, group in { CAR_GROUP, WHEEL_GROUP } do
	if not PhysicsService:IsCollisionGroupRegistered(group) then
		PhysicsService:RegisterCollisionGroup(group)
	end
end
PhysicsService:CollisionGroupSetCollidable(CAR_GROUP, "Default", true)
PhysicsService:CollisionGroupSetCollidable(CAR_GROUP, CAR_GROUP, false)
PhysicsService:CollisionGroupSetCollidable(CAR_GROUP, WHEEL_GROUP, false)
PhysicsService:CollisionGroupSetCollidable(CAR_GROUP, Corpses.EnemyCollisionGroup, false)
PhysicsService:CollisionGroupSetCollidable(CAR_GROUP, Corpses.CorpseCollisionGroup, true)
PhysicsService:CollisionGroupSetCollidable(WHEEL_GROUP, "Default", false)
PhysicsService:CollisionGroupSetCollidable(WHEEL_GROUP, WHEEL_GROUP, false)
PhysicsService:CollisionGroupSetCollidable(WHEEL_GROUP, Corpses.EnemyCollisionGroup, false)
PhysicsService:CollisionGroupSetCollidable(WHEEL_GROUP, Corpses.CorpseCollisionGroup, true)

local function randomEdge()
	return (math.random() * 2 - 1) * HALF
end

-- ============ Жуки ============

local bugsFolder = Instance.new("Folder")
bugsFolder.Name = "ArcadeBugs"
bugsFolder.Parent = arcadeFolder

-- Фиксированный список мест-слотов: раздавленный жук освобождает свой слот, а не
-- выпадает из списка — так respawn не может ни потерять слот, ни расплодить лишние.
local bugs = {}
for i = 1, BUG_COUNT do
	bugs[i] = { model = nil, heading = Vector3.new(0, 0, 1), nextTurn = 0, pos = Vector3.zero, pending = 0 }
end

local function fillBugSlot(slot)
	-- Тот же шаблон и масштаб, что строит клиент; серверу от него нужен только якорь с атрибутами
	-- Scale/Template (по ним клиент собирает тело, а труп — свой размер).
	local model = EnemyModel.Strip(EnemyModel.FromTemplate(BUG_TEMPLATE, BUG_SCALE, nil))
	model.Name = "ArcadeBug"
	model:SetAttribute("Template", BUG_TEMPLATE)

	local worldPos = Vector3.new(randomEdge(), GROUND_Y + BUG_RIDE_HEIGHT, randomEdge())
	local angle = math.random() * math.pi * 2
	local heading = Vector3.new(math.sin(angle), 0, math.cos(angle))
	model:PivotTo(CFrame.lookAt(worldPos, worldPos + heading) * CFrame.Angles(0, math.pi, 0))
	model.Parent = bugsFolder

	slot.model = model
	slot.heading = heading
	slot.pos = worldPos -- маршрутная точка: пивот модели качается походкой и для маршрута не годится
	slot.pending = 0
	slot.nextTurn = os.clock() + BUG_TURN_MIN + math.random() * (BUG_TURN_MAX - BUG_TURN_MIN)
end

local function emptyBugSlot(slot)
	if slot.model then
		slot.model:Destroy()
		slot.model = nil
	end
end

-- ============ Сессии игроков ============

local sessions = {} -- [player] = { car, seat, yaw, speed, squashCount, characterConn }
local activeCount = 0

local function fillAllBugs()
	for _, slot in bugs do
		if not slot.model then
			fillBugSlot(slot)
		end
	end
end

local function emptyAllBugs()
	for _, slot in bugs do
		emptyBugSlot(slot)
	end
end

-- carPos — откуда наехала машина: давка — удар в 100% HP, конечности летят от неё (см. Corpses.Leave).
-- carry — скорость, которую туша и куски берут у машины.
local function killBug(slot, carPos, carry)
	local model = slot.model
	if model then
		-- Труп и кровь — до уничтожения, пока модель ещё цела и стоит там, где её
		-- раздавили (тот же порядок, что и в EnemySpawner) — поле аркады на своей
		-- высоте, отличной от пола арены, поэтому Corpses.Splat принимает GROUND_Y явно.
		Corpses.Splat(model:GetPivot().Position, SPLAT_SIZE * BUG_SCALE / 3, SPLAT_DROPS, GROUND_Y)
		Corpses.Leave(model, { fraction = 1, from = carPos, floorY = GROUND_Y, carry = carry })
	end
	emptyBugSlot(slot)
	task.delay(RESPAWN_DELAY, function()
		-- Поле опустело, пока жук ждал возрождения — досыпать жертву уже некому.
		if activeCount > 0 and not slot.model then
			fillBugSlot(slot)
		end
	end)
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

	ArcadeExitedRemote:FireClient(player)
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

	if activeCount == 0 then
		fillAllBugs()
	end
	activeCount += 1

	local hrp = character:FindFirstChild("HumanoidRootPart")
	if hrp then
		hrp:SetNetworkOwner(nil)
	end
	character:PivotTo(arcadeSpawn.CFrame + Vector3.new(0, 3, 0))

	local car = carTemplate:Clone()
	car.Name = "ArcadeCar_" .. player.Name
	car:SetAttribute("ArcadeCar", true) -- по нему клиент узнаёт машину, в которой сидит
	car:SetAttribute("SquashReach", SQUASH_RADIUS) -- радиус давки для клиента: габарит жука он не знает

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
		squashCount = 0,
	}
	sessions[player] = session

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

	ArcadeEnteredRemote:FireClient(player)
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

RunService.Heartbeat:Connect(function(dt)
	if activeCount == 0 then
		return
	end
	dt = math.min(dt, 0.1)
	frameIndex += 1

	-- ---- машины едут на клиенте; сервер только читает, где они (давка и LOD походки) ----
	for _, session in sessions do
		local chassis = session.chassis
		if chassis and chassis.Parent then
			session.pos = (chassis.CFrame * session.baseInverse).Position
		end
	end

	-- ---- жуки: медленно бродят и подставляются под колёса ----
	local now = os.clock()
	for index, slot in bugs do
		local model = slot.model
		if model then
			slot.pending += dt
			local nearestSq = math.huge
			for _, session in sessions do
				local dx, dz = slot.pos.X - session.pos.X, slot.pos.Z - session.pos.Z
				nearestSq = math.min(nearestSq, dx * dx + dz * dz)
			end
			local every = nearestSq <= GAIT_NEAR * GAIT_NEAR and 1
				or nearestSq <= GAIT_MID * GAIT_MID and GAIT_MID_EVERY
				or GAIT_FAR_EVERY
			-- Сдвиг по номеру слота: дальние жуки шагают вразнобой, а не все в один кадр.
			if (frameIndex + index) % every == 0 then
				local stepDt = math.min(slot.pending, GAIT_MAX_DT)
				slot.pending = 0
				if now >= slot.nextTurn then
					local angle = math.random() * math.pi * 2
					slot.heading = Vector3.new(math.sin(angle), 0, math.cos(angle))
					slot.nextTurn = now + BUG_TURN_MIN + math.random() * (BUG_TURN_MAX - BUG_TURN_MIN)
				end

				local pos = slot.pos
				local nextPos = pos + slot.heading * BUG_SPEED * stepDt

				-- Отражение от ограждения, а не остановка: жук у края читается живым,
				-- только если он от края тут же убегает, а не липнет к нему.
				local bounced = false
				if nextPos.X > HALF or nextPos.X < -HALF then
					slot.heading = Vector3.new(-slot.heading.X, 0, slot.heading.Z)
					bounced = true
				end
				if nextPos.Z > HALF or nextPos.Z < -HALF then
					slot.heading = Vector3.new(slot.heading.X, 0, -slot.heading.Z)
					bounced = true
				end
				if bounced then
					nextPos = pos + slot.heading * BUG_SPEED * stepDt
					slot.nextTurn = now + BUG_TURN_MIN + math.random() * (BUG_TURN_MAX - BUG_TURN_MIN)
				end
				nextPos = Vector3.new(
					math.clamp(nextPos.X, -HALF, HALF),
					GROUND_Y + BUG_RIDE_HEIGHT,
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
local SQUASH_TRUST = SQUASH_RADIUS + 40
local MAX_CARRY = Balance.car.maxSpeed * 2
ArcadeSquashRemote.OnServerEvent:Connect(function(player, model, carPos, carry)
	local session = sessions[player]
	if not session or typeof(model) ~= "Instance" or model.Parent ~= bugsFolder
		or typeof(carPos) ~= "Vector3" or typeof(carry) ~= "Vector3" then
		return
	end
	local flat = Vector3.new(carPos.X - session.pos.X, 0, carPos.Z - session.pos.Z)
	if flat.Magnitude > SQUASH_TRUST or carry.Magnitude ~= carry.Magnitude then
		return
	end
	if carry.Magnitude > MAX_CARRY then
		carry = carry.Unit * MAX_CARRY
	end
	for _, slot in bugs do
		if slot.model == model then
			session.squashCount += 1
			ArcadeSquashCountRemote:FireClient(player, session.squashCount)
			killBug(slot, carPos, carry)
			return
		end
	end
end)

print("[Arcade] режим готов: поле half =", HALF, "жуков =", BUG_COUNT)
