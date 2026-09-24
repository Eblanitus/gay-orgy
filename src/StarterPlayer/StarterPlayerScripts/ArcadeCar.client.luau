-- Езда машины аркады. Машина — физическая сборка, и владеет ею клиент водителя (ArcadeMode
-- отдаёт её через SetNetworkOwner): игра рассчитана на одного, и удар корпусом по трупу
-- считается там, где его видно, без задержки сети. Сервер ставит машину, давит жуков по её
-- позиции и отдаёт этому же клиенту трупы на поле аркады.
--
-- Подвеска — лучи-пружины из точек колёс, а не колёсные шарниры (см. ArcadeMode.startSession).
-- Газ и руль не крутят колёса, а правят скорость рамы, пока хоть одно колесо на земле: тачка
-- слушается как аркадная, а удары, кочки из трупов и полёты остаются физикой.
--
-- Давку тоже решает клиент, а сервер (ArcadeSquash) ставит труп. Жука заранее не прячем:
-- сервер убирает его тем же пакетом, что привозит труп, а спрятанный локально исчезал на время в пути. Туша приходит
-- по сети позже, когда машина уже проехала дальше, — её доводят туда, куда она бы успела улететь,
-- и выталкивают из корпуса: иначе физика растаскивает вставшие друг в друга тела рывком или насквозь.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local CAR = require(ReplicatedStorage:WaitForChild("Arcade")).car

local player = Players.LocalPlayer
local arcadeFolder = Workspace:WaitForChild("Arcade")
local SquashRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("ArcadeSquash")

local CLEARANCE = 0.3 -- studs зазора между вытолкнутым трупом и корпусом
local ARRIVAL_WAIT = 1 -- сек: дольше туша не считается «только что раздавленной»

local squashed = setmetatable({}, { __mode = "k" }) -- [жук] = true: уже отправлен серверу
local recentSquashes = {} -- { at = точка, time = os.clock() } — чтобы узнать, сколько туша ехала по сети
local arrivals = {} -- { model, time } — пришедшие трупы и куски, ещё не разведённые с машиной

local function watchRemains(folder)
	if folder.Name == "Corpses" or folder.Name == "Debris" then
		folder.ChildAdded:Connect(function(model)
			if model:IsA("Model") then
				table.insert(arrivals, { model = model, time = os.clock() })
			end
		end)
	end
end
Workspace.ChildAdded:Connect(watchRemains)
for _, child in Workspace:GetChildren() do
	watchRemains(child)
end

-- Габарит твёрдых деталей в кадре frame.
local function extents(parts, frame)
	local low, high
	for _, part in parts do
		if part:IsA("BasePart") and part.CanCollide then
			local half = part.Size / 2
			for _, sx in { -1, 1 } do
				for _, sy in { -1, 1 } do
					for _, sz in { -1, 1 } do
						local corner = frame:PointToObjectSpace(part.CFrame * Vector3.new(half.X * sx, half.Y * sy, half.Z * sz))
						low = low and low:Min(corner) or corner
						high = high and high:Max(corner) or corner
					end
				end
			end
		end
	end
	return low, high
end

-- Туша пришла по сети. Довести её туда, куда она улетела бы за время в пути, вытолкнуть из корпуса
-- по кратчайшей стороне и дать скорость прочь от него. true — готово (или делать нечего).
local function settleArrival(model, base, drive)
	local root = model.PrimaryPart
	if not model.Parent then
		return true
	end
	if not root or root.Anchored or root.ReceiveAge > 0 then
		return false -- ещё не дошла целиком или считает не этот клиент
	end
	local flatPos = Vector3.new(root.Position.X, 0, root.Position.Z)
	local carFlat = Vector3.new(base.Position.X, 0, base.Position.Z)
	if (flatPos - carFlat).Magnitude > 60 then
		return true -- далеко от машины (или труп арены)
	end

	-- Время в пути — по ближайшей свежей давке.
	local now = os.clock()
	local flight
	for _, squash in recentSquashes do
		local d = Vector3.new(squash.at.X - flatPos.X, 0, squash.at.Z - flatPos.Z).Magnitude
		if d < 25 then
			flight = math.min(now - squash.time, 0.5)
			break
		end
	end
	if flight then
		local v = root.AssemblyLinearVelocity
		root.CFrame += Vector3.new(v.X, 0, v.Z) * flight
	end

	local low, high = extents(model:GetDescendants(), base)
	if not low then
		return false -- коллайдеры ещё не пришли
	end
	local box = drive.box
	-- Зазор по каждой стороне (отрицательный — влезла): выход — там, где он больше всего.
	local side, gap
	for _, exit in {
		{ Vector3.xAxis, low.X - box.max.X },
		{ -Vector3.xAxis, box.min.X - high.X },
		{ Vector3.zAxis, low.Z - box.max.Z },
		{ -Vector3.zAxis, box.min.Z - high.Z },
	} do
		if not gap or exit[2] > gap then
			side, gap = exit[1], exit[2]
		end
	end
	if low.Y > box.max.Y then
		return true -- летит над машиной
	end
	local away = base:VectorToWorldSpace(side)
	if gap < CLEARANCE then
		root.CFrame += away * (CLEARANCE - gap)
	end
	if gap < 3 then
		local relative = (root.AssemblyLinearVelocity - drive.chassis:GetVelocityAtPosition(root.Position)):Dot(away)
		if relative < CAR.squashKick then
			root.AssemblyLinearVelocity += away * (CAR.squashKick - relative)
		end
	end
	return true
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true

local function flat(v)
	v = Vector3.new(v.X, 0, v.Z)
	return v.Magnitude > 1e-3 and v.Unit or nil
end

-- Газ и руль — из Humanoid.MoveDirection (WASD, стик на телефоне, геймпад): штатное управление
-- внутри движка газ сиденья не ставит (замерено в #174). MoveDirection повёрнут камерой —
-- разложение по её осям возвращает чистые газ и руль.
local function readInput(humanoid, seat)
	local throttle, steer = 0, 0
	local camera = Workspace.CurrentCamera
	local move = humanoid.MoveDirection
	if camera and move.Magnitude > 1e-3 then
		local look = flat(camera.CFrame.LookVector)
		local right = flat(camera.CFrame.RightVector)
		if look and right then
			throttle = math.clamp(move:Dot(look), -1, 1)
			steer = math.clamp(move:Dot(right), -1, 1)
		end
	end
	if throttle == 0 and steer == 0 then
		throttle, steer = seat.ThrottleFloat, seat.SteerFloat
	end
	return throttle, steer
end

local drive -- машина, в которой сидит игрок

local function bind(seat, character)
	local car = seat.Parent
	local chassis = car.PrimaryPart
	local baseOffset = chassis and chassis:GetAttribute("BaseOffset")
	if not baseOffset then
		return nil
	end
	local wheels = {}
	for _, part in car:GetChildren() do
		local offset = part:IsA("BasePart") and part:GetAttribute("RestOffset")
		local axle = offset and part:FindFirstChild("Axle")
		if axle then
			table.insert(wheels, {
				axle = axle,
				position = offset.Position,
				rotation = offset.Rotation,
				radius = part.Size.Y / 2,
				front = part.Name:sub(-2, -2) == "F",
				spin = 0,
				lift = 0,
			})
		end
	end
	if #wheels == 0 then
		return nil
	end
	local ignore = { car, character }
	local bugs = arcadeFolder:FindFirstChild("ArcadeBugs")
	if bugs then
		table.insert(ignore, bugs) -- жуки давятся кодом, на них не наезжают
	end
	rayParams.FilterDescendantsInstances = ignore
	local boxLow, boxHigh = extents(car:GetDescendants(), chassis.CFrame * baseOffset:Inverse())
	return {
		seat = seat,
		car = car,
		box = { min = boxLow, max = boxHigh },
		chassis = chassis,
		baseOffset = baseOffset,
		baseInverse = baseOffset:Inverse(),
		wheels = wheels,
		tipped = 0,
		foreign = 0,
	}
end

RunService.PreSimulation:Connect(function(dt)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local seat = humanoid and humanoid.SeatPart
	local car = seat and seat.Parent
	if not (car and seat:IsA("VehicleSeat") and car:GetAttribute("ArcadeCar")) then
		drive = nil
		table.clear(arrivals) -- трупы арены разводить не с чем
		return
	end
	if not drive or drive.seat ~= seat then
		drive = bind(seat, character)
		if not drive then
			return
		end
	end
	local chassis = drive.chassis
	if chassis.Anchored or not chassis.Parent then
		return
	end
	-- Сборку считает не этот клиент (сервер ещё не отдал): толкать чужую симуляцию бесполезно.
	if chassis.ReceiveAge > 0 then
		drive.foreign += dt
		if drive.foreign > 2 and not drive.warned then
			drive.warned = true
			warn("[ArcadeCar] машину считает не этот клиент — езда не работает")
		end
		return
	end
	drive.foreign = 0

	local throttle, steer = readInput(humanoid, seat)
	if not drive.reported and (throttle ~= 0 or steer ~= 0) then
		drive.reported = true
		print("[ArcadeCar] ввод есть, машина у клиента:", throttle, steer)
	end

	local base = chassis.CFrame * drive.baseInverse
	local up = base.UpVector
	local wheelCount = #drive.wheels
	local mass = chassis.AssemblyMass

	-- ---- подвеска: пружина на колесо, в покое держит свою долю веса ровно на высоте посадки ----
	local travel = CAR.suspensionTravel
	local weight = mass * Workspace.Gravity / wheelCount
	local stiffness = weight / travel -- на полном отбое пружина уже не толкает
	local damping = 2 * math.sqrt(stiffness * mass / wheelCount) * CAR.suspensionDamping
	local grounded = 0
	for _, wheel in drive.wheels do
		local anchor = base * wheel.position
		local reach = travel + wheel.radius
		local hit = Workspace:Raycast(anchor + up * travel, -up * (reach + travel), rayParams)
		if hit then
			grounded += 1
			local compression = reach - hit.Distance
			local force = weight + stiffness * compression - damping * chassis:GetVelocityAtPosition(anchor):Dot(up)
			if force > 0 then
				chassis:ApplyImpulseAtPosition(up * force * dt, anchor)
			end
			wheel.lift = math.clamp(compression, -travel, travel)
		else
			wheel.lift = -travel
		end
	end

	-- ---- газ, занос, руль: только пока есть сцепление ----
	local velocity = chassis.AssemblyLinearVelocity
	local forward = flat(base.ZVector)
	local right = flat(base.XVector)
	local forwardSpeed = forward and velocity:Dot(forward) or 0
	local grip = grounded / wheelCount
	if grip > 0 and forward and right then
		local target = throttle >= 0 and throttle * CAR.maxSpeed or throttle * CAR.maxReverse
		local rate = throttle == 0 and CAR.coastDecel
			or (forwardSpeed * target < 0 and CAR.brakeDecel or CAR.accel)
		local newForward = forwardSpeed + math.clamp(target - forwardSpeed, -rate * dt, rate * dt)
		-- Занос: боковая скорость гаснет со сцеплением traction, а не сразу — на резком
		-- повороте тачку тащит юзом.
		local sideSpeed = velocity:Dot(right)
		local newSide = sideSpeed * (1 - math.clamp(CAR.traction * dt, 0, 1))
		chassis.AssemblyLinearVelocity = velocity
			+ (forward * (newForward - forwardSpeed) + right * (newSide - sideSpeed)) * grip

		-- Руль слушается и на месте, но слабее: на телефоне педаль и руль — два разных пальца.
		local turnFactor = CAR.turnAtRest + (1 - CAR.turnAtRest) * math.min(math.abs(forwardSpeed) / CAR.maxSpeed, 1)
		local wanted = -steer * CAR.turnRate * turnFactor
		local spin = chassis.AssemblyAngularVelocity
		local newYaw = spin.Y + (wanted - spin.Y) * math.clamp(CAR.steerResponse * dt, 0, 1) * grip
		chassis.AssemblyAngularVelocity = Vector3.new(spin.X, newYaw, spin.Z)
	end

	-- ---- давка: кого переехали — решает клиент, труп ставит сервер ----
	local now = os.clock()
	local reach = drive.car:GetAttribute("SquashReach")
	local bugsFolder = arcadeFolder:FindFirstChild("ArcadeBugs")
	if reach and bugsFolder then
		local carPos = base.Position
		local carry = velocity * CAR.squashCarry
		for _, bug in bugsFolder:GetChildren() do
			if not squashed[bug] and bug:IsA("Model") then
				local at = bug:GetPivot().Position
				local dx, dz = at.X - carPos.X, at.Z - carPos.Z
				if dx * dx + dz * dz <= reach * reach then
					squashed[bug] = true
					table.insert(recentSquashes, { at = at, time = now })
					SquashRemote:FireServer(bug, carPos, carry)
				end
			end
		end
	end
	for i = #recentSquashes, 1, -1 do
		if now - recentSquashes[i].time > ARRIVAL_WAIT then
			table.remove(recentSquashes, i)
		end
	end

	-- ---- пришедшие трупы: развести с машиной ----
	for i = #arrivals, 1, -1 do
		local arrival = arrivals[i]
		if now - arrival.time > ARRIVAL_WAIT or settleArrival(arrival.model, base, drive) then
			table.remove(arrivals, i)
		end
	end

	-- ---- лёг на бок или улетел с поля: ставим на колёса ----
	if up.Y < 0.4 and velocity.Magnitude < 8 then
		drive.tipped += dt
	else
		drive.tipped = 0
	end
	local spawnPart = arcadeFolder:FindFirstChild("ArcadeSpawn")
	local fell = spawnPart ~= nil and base.Position.Y < spawnPart.Position.Y - 40
	if drive.tipped > CAR.flipResetAfter or fell then
		drive.tipped = 0
		local at = (fell and spawnPart.Position or base.Position) + Vector3.yAxis * 4
		local look = forward or Vector3.zAxis
		chassis.CFrame = CFrame.lookAt(at, at - look) * drive.baseOffset
		chassis.AssemblyLinearVelocity = Vector3.zero
		chassis.AssemblyAngularVelocity = Vector3.zero
	end

	-- ---- колёса: крутятся по ходу, передние рулят, все ходят вместе с подвеской ----
	for _, wheel in drive.wheels do
		wheel.spin = (wheel.spin + forwardSpeed * dt / wheel.radius) % (math.pi * 2)
		local steerAngle = wheel.front and -steer * CAR.maxWheelSteer or 0
		wheel.axle.Transform = CFrame.new(0, wheel.lift, 0)
			* CFrame.Angles(0, steerAngle, 0)
			* wheel.rotation
			* CFrame.Angles(wheel.spin, 0, 0)
			* wheel.rotation:Inverse()
	end
end)
