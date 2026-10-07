-- Мешки Стены ведут себя как мешки с песком, а не как приклеенные шары. Чисто клиентская
-- картинка: сервер собирает кладку (TowerModels.buildWallModel) и дальше её не трогает,
-- а здесь мешки двигаются у каждого игрока сами. На игру это не влияет никак: сердечник
-- стены, её HP, высота перелезания (атрибут Height) и след остаются ровно теми же.
--
-- Что делает:
--   * стройка — ряды падают сверху один за другим и плюхаются, сминаясь и отпружинивая;
--   * укус и взрыв рядом — мешки вздрагивают, из пробитого сыплется облачко песка;
--   * износ — чем меньше HP, тем сильнее кладка оседает и расползается наружу, а под конец
--     из порванных мешков струится песок и верхние угловые мешки сползают на пол. Кладка
--     лечится (Plants) — сползшие мешки возвращаются наверх;
--   * вес — жук, который перелез наверх, продавливает мешки под собой; ушёл — они
--     распрямляются.
--
-- Кладка остаётся на якоре: по ней ходят жуки и по ней же сервер считает высоту, а полсотни
-- стен по двадцать четыре незакреплённых мешка — это тысяча тел в симуляции. Мешки в ней
-- ведёт пружина к своей позе (износ, вес). Сползший мешок уже отпущен: на его месте
-- появляется клиентская копия и уходит в общий физический слой (Loose) — как трупы, её
-- толкают тела жуков и ударная волна взрывов (ImpulseFX), потолок числа — PhysicsFX.cleanup.
-- Числа — PhysicsFX.sandbag.
--
-- Дёшево на толпе: кадр обходит только «проснувшиеся» мешки — те, что ещё не доехали до
-- цели. Стоящая кладка не стоит ничего. Вес жуков проверяется не каждый кадр, а PLAN.weightScan
-- раз в секунду, и через сетку корзин: жук смотрит только на стены своей корзины.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Loose = require(ReplicatedStorage:WaitForChild("Loose"))
local PhysicsFX = require(ReplicatedStorage:WaitForChild("PhysicsFX"))
local PLAN = PhysicsFX.sandbag

local towersFolder = Workspace:WaitForChild("Towers")
local enemiesFolder = Workspace:WaitForChild("Enemies")
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

-- Корзины сетки для веса: сторона в студах (не меньше следа стены).
local BUCKET = 4

local SAND_COLOR = Color3.fromRGB(196, 178, 134)

local startedAt = os.clock()
local walls = {} -- [model] = wall
local awake = {} -- [bag] = true
local loopConnection = nil

-- Одно и то же число на мешок у всех заходов: поза износа не должна дёргаться при каждом
-- пересчёте, а у разных мешков она своя.
local function hash01(text, salt)
	local h = salt * 2654435761 % 4294967296
	for i = 1, #text do
		h = (h * 31 + string.byte(text, i)) % 4294967296
	end
	return (h % 10007) / 10007
end

local function wear(wall)
	local hp = wall.model:GetAttribute("HP") or 0
	local maxHp = wall.model:GetAttribute("MaxHP") or hp
	return maxHp > 0 and 1 - math.clamp(hp / maxHp, 0, 1) or 0
end

local function cameraFar(position)
	local camera = Workspace.CurrentCamera
	return camera and (camera.CFrame.Position - position).Magnitude > PLAN.far
end

-- Поза, к которой тянется мешок: износ + вес.
local function retarget(bag)
	local wall = bag.wall
	local w = wall.wearShown
	local rowFactor = (bag.row + 1) / wall.rows
	local amount = w * rowFactor * bag.luck
	local sink = PLAN.sag * amount + PLAN.weightSink * bag.weight
	bag.targetPos = bag.outward * (PLAN.spread * amount) - Vector3.new(0, sink, 0)
	bag.targetRot = Vector3.new(bag.leanX * PLAN.lean * amount, 0, bag.leanZ * PLAN.lean * amount)
	bag.targetSquash = PLAN.wearSquash * w * bag.luck + PLAN.weightSquash * bag.weight
end

local function apply(bag)
	local cf = CFrame.new(bag.pos) * bag.base * CFrame.Angles(bag.rot.X, bag.rot.Y, bag.rot.Z)
	bag.part.CFrame = cf
	if bag.ear and bag.ear.part.Parent then
		bag.ear.part.CFrame = cf * bag.ear.offset
	end
	if bag.mesh then
		local s = bag.squash
		bag.mesh.Scale = Vector3.new(1 + s * 0.5, 1 - s, 1 + s * 0.5)
	end
end

local function step(dt)
	dt = math.min(dt, 1 / 20) -- после подвисания пружина не должна выстрелить
	local now = os.clock()
	for bag in awake do
		if not bag.part.Parent then
			awake[bag] = nil
		elseif now >= (bag.wakeAt or 0) then
			local dp = bag.targetPos - bag.pos
			local dr = bag.targetRot - bag.rot
			local ds = bag.targetSquash - bag.squash
			bag.vel += (dp * PLAN.stiffness - bag.vel * PLAN.damping) * dt
			bag.rotVel += (dr * PLAN.stiffness - bag.rotVel * PLAN.damping) * dt
			bag.squashVel += (ds * PLAN.stiffness - bag.squashVel * PLAN.damping) * dt
			bag.pos += bag.vel * dt
			bag.rot += bag.rotVel * dt
			bag.squash += bag.squashVel * dt
			if dp.Magnitude < PLAN.rest and bag.vel.Magnitude < PLAN.rest and dr.Magnitude < PLAN.rest
				and bag.rotVel.Magnitude < PLAN.rest and math.abs(ds) < PLAN.rest and math.abs(bag.squashVel) < PLAN.rest then
				bag.pos, bag.rot, bag.squash = bag.targetPos, bag.targetRot, bag.targetSquash
				bag.vel, bag.rotVel, bag.squashVel = Vector3.zero, Vector3.zero, 0
				awake[bag] = nil
			end
			apply(bag)
		end
	end

	if next(awake) == nil and loopConnection then
		loopConnection:Disconnect()
		loopConnection = nil
	end
end

local function wake(bag)
	if bag.fallen then
		return -- сполз: на кладке его нет, за него теперь копия в физике
	end
	if cameraFar(bag.base.Position) then
		bag.pos, bag.rot, bag.squash = bag.targetPos, bag.targetRot, bag.targetSquash
		bag.vel, bag.rotVel, bag.squashVel = Vector3.zero, Vector3.zero, 0
		apply(bag)
		return
	end
	awake[bag] = true
	if not loopConnection then
		loopConnection = RunService.RenderStepped:Connect(step)
	end
end

local function kick(bag, away, strength)
	if bag.fallen then
		return
	end
	bag.vel += (away * 0.6 - Vector3.new(0, 0.4, 0)) * PLAN.hitPush * strength
	bag.rotVel += Vector3.new((math.random() - 0.5), 0, (math.random() - 0.5)) * 2 * PLAN.hitTilt * strength
	bag.squashVel += PLAN.hitSquash * strength
	wake(bag)
end

-- Облачко песка. Один излучатель на стену, на вложении, которое переносится к мешку перед
-- выбросом, — а не по излучателю на каждый мешок.
local function sandPuff(wall, position, count)
	if not wall.puff then
		local attachment = Instance.new("Attachment")
		attachment.Name = "SandPuff"
		attachment.Parent = wall.root
		local emitter = Instance.new("ParticleEmitter")
		emitter.Color = ColorSequence.new(SAND_COLOR)
		emitter.LightEmission = 0
		emitter.Rate = 0
		emitter.Lifetime = NumberRange.new(0.4, 0.8)
		emitter.Speed = NumberRange.new(1.5, 3.5)
		emitter.SpreadAngle = Vector2.new(60, 60)
		emitter.Acceleration = Vector3.new(0, -14, 0)
		emitter.Drag = 2
		emitter.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.18),
			NumberSequenceKeypoint.new(1, 0.05),
		})
		emitter.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.2),
			NumberSequenceKeypoint.new(1, 1),
		})
		emitter.Parent = attachment
		wall.puff = { attachment = attachment, emitter = emitter }
	end
	wall.puff.attachment.WorldPosition = position
	wall.puff.emitter:Emit(count)
end

-- Струйка из порванного мешка: тонкая, редкая, вниз по стенке.
local function setTrickle(wall, on)
	if on == (wall.trickle ~= nil) then
		return
	end
	if not on then
		wall.trickle.Parent:Destroy()
		wall.trickle = nil
		return
	end
	local source
	for _, bag in wall.bags do
		if bag.row == wall.rows - 2 and not bag.fallen then
			source = bag
			break
		end
	end
	if not source then
		return
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = "SandTrickle"
	attachment.Parent = wall.root
	attachment.WorldPosition = source.base.Position + source.outward * 0.7
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(SAND_COLOR)
	emitter.LightEmission = 0
	emitter.Rate = 14
	emitter.Lifetime = NumberRange.new(0.5, 0.7)
	emitter.Speed = NumberRange.new(0.2, 0.5)
	emitter.SpreadAngle = Vector2.new(8, 8)
	emitter.EmissionDirection = Enum.NormalId.Bottom
	emitter.Acceleration = Vector3.new(0, -9, 0)
	emitter.Size = NumberSequence.new(0.07)
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(1, 0.9),
	})
	emitter.Parent = attachment
	wall.trickle = emitter
end

-- Мешок на кладке прячется у этого игрока (сервер о нём не знает и знать не должен).
local function setHidden(bag, hidden)
	local value = hidden and 1 or 0
	bag.part.Transparency = value
	if bag.ear and bag.ear.part.Parent then
		bag.ear.part.Transparency = value
	end
end

-- Сползает: прячется сам, а вместо него с того же места наружу и вниз валится его копия —
-- уже незакреплённая, в общем физическом слое. Тяжёлая, без отскока: мешок песка шлёпается
-- и лежит, а не прыгает мячиком.
local function dropBag(wall, bag)
	bag.fallen = true
	awake[bag] = nil
	local at = bag.part.CFrame

	local copy = Instance.new("Model")
	copy.Name = "Sandbag"
	local body = bag.part:Clone()
	for _, child in body:GetChildren() do
		if not child:IsA("SpecialMesh") then
			child:Destroy()
		end
	end
	local mesh = body:FindFirstChildOfClass("SpecialMesh")
	if mesh then
		mesh.Scale = Vector3.one
	end
	body.Transparency = 0
	body.CanCollide = true
	body.CanQuery = false
	body.CanTouch = false
	body.CFrame = at
	body.Parent = copy
	copy.PrimaryPart = body
	if bag.ear and bag.ear.part.Parent then
		local tie = bag.ear.part:Clone()
		tie.Transparency = 0
		tie.CanCollide = false
		tie.Massless = true
		tie.CFrame = at * bag.ear.offset
		tie.Parent = copy
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = body
		weld.Part1 = tie
		weld.Parent = body
	end
	copy.Parent = Loose.Folder("Debris")
	setHidden(bag, true)

	local out = bag.outward.Magnitude > 1e-3 and bag.outward or Vector3.xAxis
	Loose.Spawn(copy, {
		physics = PhysicalProperties.new(PLAN.density, PLAN.friction, 0, 1, 1),
		velocity = out * PLAN.fallSpeed + Vector3.new(0, 1.5, 0),
		spin = out:Cross(Vector3.yAxis) * -PLAN.fallSpin + Loose.RandomSpin(PLAN.fallSpin * 0.3),
	})
	Loose.LayFlat(body)
	Loose.Track(copy, "sandbag")
	bag.copy = copy
	sandPuff(wall, bag.base.Position, 10)
end

-- Вылечили: копия тает, мешок снова на кладке — падает на своё место сверху, как при стройке.
local function restoreBag(bag)
	bag.fallen = false
	if bag.copy then
		Loose.Dissolve(bag.copy, 0.3)
		bag.copy = nil
	end
	setHidden(bag, false)
	bag.pos = Vector3.new(0, PLAN.settleDrop, 0)
	bag.vel, bag.rot, bag.rotVel = Vector3.zero, Vector3.zero, Vector3.zero
	bag.squash, bag.squashVel = -0.12, 0
	retarget(bag)
	apply(bag)
	wake(bag)
end

local function updateFalls(wall)
	local hp = 1 - wear(wall)
	for index, threshold in PLAN.fallAt do
		local bag = wall.fallers[index]
		if bag and bag.part.Parent then
			if not bag.fallen and hp <= threshold and hp > 0 then
				dropBag(wall, bag)
			elseif bag.fallen and hp > threshold + PLAN.healMargin then
				restoreBag(bag)
			end
		end
	end
end

local function retargetAll(wall)
	wall.wearShown = wear(wall)
	for _, bag in wall.bags do
		retarget(bag)
		wake(bag)
	end
end

local function onHealth(wall)
	local hp = wall.model:GetAttribute("HP") or 0
	local last = wall.lastHp or hp
	wall.lastHp = hp

	local w = wear(wall)
	if math.abs(w - wall.wearShown) >= PLAN.wearStep or w == 0 then
		retargetAll(wall)
	end
	updateFalls(wall)
	setTrickle(wall, 1 - w < PLAN.trickleAt and hp > 0)

	if hp < last and #wall.bags > 0 then
		-- Укус: вздрагивают случайные мешки, чаще верхние — их и грызут.
		for _ = 1, PLAN.hitBags do
			local bag = wall.bags[math.random(#wall.bags)]
			if bag.row < wall.rows - 2 and math.random() < 0.6 then
				bag = wall.bags[math.random(#wall.bags)]
			end
			kick(bag, bag.outward, 1)
		end
		local bag = wall.bags[math.random(#wall.bags)]
		sandPuff(wall, bag.base.Position + bag.outward * 0.6, 4)
	end
end

local function addBag(wall, part)
	local row, long, wide = part.Name:match("^Bag(%d+)_(%d)(%d)$")
	if not row then
		return
	end
	row = tonumber(row)
	-- Мешок уже знаком (стриминг выгрузил и вернул деталь): новая деталь встаёт в старую запись.
	local known = wall.byName[part.Name]
	if known then
		known.part = part
		known.mesh = part:FindFirstChildOfClass("SpecialMesh")
		if known.fallen then
			setHidden(known, true)
		else
			apply(known)
		end
		return nil
	end
	local centre = wall.root.Position
	local base = part.CFrame
	local outward = Vector3.new(base.Position.X - centre.X, 0, base.Position.Z - centre.Z)
	outward = outward.Magnitude > 1e-3 and outward.Unit or Vector3.zero
	local bag = {
		wall = wall,
		part = part,
		mesh = part:FindFirstChildOfClass("SpecialMesh"),
		name = part.Name,
		row = row,
		base = base,
		outward = outward,
		luck = 0.55 + 0.45 * hash01(part.Name, 1),
		leanX = hash01(part.Name, 2) * 2 - 1,
		leanZ = hash01(part.Name, 3) * 2 - 1,
		weight = 0,
		pos = Vector3.zero,
		vel = Vector3.zero,
		rot = Vector3.zero,
		rotVel = Vector3.zero,
		squash = 0,
		squashVel = 0,
		far = (base.Position - centre).Magnitude,
	}
	if row + 1 > wall.rows then
		wall.rows = row + 1
	end
	local ear = wall.ears[part.Name]
	if ear then
		bag.ear = { part = ear, offset = base:Inverse() * ear.CFrame }
	end
	wall.byName[part.Name] = bag
	table.insert(wall.bags, bag)
	retarget(bag)

	-- Строится на глазах — мешок начинает сверху и падает в свою очередь.
	if wall.settling then
		bag.pos = Vector3.new(0, PLAN.settleDrop + PLAN.settleRowExtra * row, 0)
		bag.squash = -0.12 -- в полёте мешок вытянут, при ударе — смят
		bag.wakeAt = wall.addedAt + PLAN.settleRowDelay * row
		apply(bag)
		wake(bag)
	elseif bag.targetPos ~= Vector3.zero or bag.targetSquash ~= 0 then
		bag.pos, bag.rot, bag.squash = bag.targetPos, bag.targetRot, bag.targetSquash
		apply(bag)
	end
	return bag
end

local function addEar(wall, part)
	local owner = part.Name:match("^(Bag%d+_%d%d)Ear$")
	if not owner then
		return
	end
	wall.ears[owner] = part
	local bag = wall.byName[owner]
	if bag then
		-- Завязка доехала позже мешка: смещение берётся от исходной позы мешка, а не от
		-- текущей (мешок мог уже сдвинуться).
		bag.ear = { part = part, offset = bag.base:Inverse() * part.CFrame }
		apply(bag)
	end
end

-- Угловые мешки верхнего ряда — дальние от центра: они сползают первыми.
local function pickFallers(wall)
	local top = {}
	for _, bag in wall.bags do
		if bag.row == wall.rows - 1 then
			table.insert(top, bag)
		end
	end
	table.sort(top, function(a, b)
		return a.far > b.far
	end)
	wall.fallers = { top[1], top[3] or top[2] }
end

local function onDescendant(wall, part)
	if not part:IsA("BasePart") then
		return
	end
	if part.Name:sub(-3) == "Ear" then
		addEar(wall, part)
	elseif addBag(wall, part) then
		pickFallers(wall)
	end
end

local function addWall(model)
	if not model:IsA("Model") or model:GetAttribute("Type") ~= "Wall" then
		return
	end
	local root = model:WaitForChild("Root", 10)
	if not root or not model.Parent then
		return
	end
	local core = model:FindFirstChild("Block")
	local half = core and core.Size.X / 2 or 1.8
	local height = core and core.Size.Y or 3.2
	local now = os.clock()
	local wall = {
		model = model,
		root = root,
		half = half,
		floor = root.Position.Y - height / 2,
		top = root.Position.Y + height / 2,
		rows = 1,
		bags = {},
		byName = {},
		ears = {},
		fallers = {},
		wearShown = wear({ model = model }),
		addedAt = now,
		settling = now - startedAt > PLAN.loadGrace and wear({ model = model }) == 0,
	}
	walls[model] = wall

	-- Завязки сначала: мешок, доехавший в том же проходе, сразу найдёт свою.
	local descendants = model:GetDescendants()
	for _, part in descendants do
		if part:IsA("BasePart") and part.Name:sub(-3) == "Ear" then
			addEar(wall, part)
		end
	end
	for _, part in descendants do
		if part:IsA("BasePart") and part.Name:sub(-3) ~= "Ear" then
			addBag(wall, part)
		end
	end
	pickFallers(wall)
	model.DescendantAdded:Connect(function(part)
		onDescendant(wall, part)
	end)
	-- Доехавшие позже мешки ещё падают вместе с кладкой; после этого — уже нет.
	task.delay(1, function()
		wall.settling = false
	end)

	wall.lastHp = model:GetAttribute("HP")
	updateFalls(wall)
	setTrickle(wall, 1 - wear(wall) < PLAN.trickleAt)
	model:GetAttributeChangedSignal("HP"):Connect(function()
		onHealth(wall)
	end)
end

towersFolder.ChildRemoved:Connect(function(model)
	local wall = walls[model]
	if wall then
		walls[model] = nil
		for _, bag in wall.bags do
			awake[bag] = nil
			-- Стена распалась на обломки (TowerDebris) вместе с этим мешком: копия рядом
			-- стала бы его двойником.
			if bag.copy then
				Loose.Dissolve(bag.copy, 0.3)
				bag.copy = nil
			end
		end
	end
end)

for _, model in towersFolder:GetChildren() do
	task.spawn(addWall, model)
end
towersFolder.ChildAdded:Connect(function(model)
	task.spawn(addWall, model)
end)

-- Взрыв рядом: мешки со стороны взрыва толкает от него, чем ближе — тем сильнее.
Remotes:WaitForChild("Explosion").OnClientEvent:Connect(function(position, radius)
	if typeof(position) ~= "Vector3" then
		return
	end
	local reach = (tonumber(radius) or 4) + PLAN.blastReach
	for _, wall in walls do
		local centre = wall.root.Position
		local flat = Vector3.new(centre.X - position.X, 0, centre.Z - position.Z)
		local distance = flat.Magnitude - wall.half
		if distance < reach then
			local strength = math.clamp(1 - math.max(distance, 0) / reach, 0.2, 1) * 1.5
			local away = flat.Magnitude > 1e-3 and flat.Unit or Vector3.zero
			for _, bag in wall.bags do
				-- Ближняя к взрыву сторона и верх получают больше, дальняя — почти ничего.
				local facing = math.clamp(0.5 - bag.outward:Dot(away) * 0.5, 0, 1)
				local share = facing * (0.4 + 0.6 * (bag.row + 1) / wall.rows)
				if share > 0.15 then
					kick(bag, away, strength * share)
				end
			end
			if distance < reach * 0.5 then
				sandPuff(wall, centre + Vector3.new(0, wall.top - centre.Y, 0) - away * wall.half, 8)
			end
		end
	end
end)

-- Вес: кто стоит на кладке и как продавливает мешки под собой.
local function bucketKey(x, z)
	return math.floor(x / BUCKET) .. ":" .. math.floor(z / BUCKET)
end

local scanClock = 0
RunService.Heartbeat:Connect(function(dt)
	scanClock += dt
	if scanClock < 1 / PLAN.weightScan then
		return
	end
	scanClock = 0
	if next(walls) == nil then
		return
	end

	-- Стена ложится во все корзины, которые задевает её след.
	local buckets = {}
	for _, wall in walls do
		local c = wall.root.Position
		local h = wall.half
		for _, sx in { -h, h } do
			for _, sz in { -h, h } do
				local key = bucketKey(c.X + sx, c.Z + sz)
				local list = buckets[key]
				if not list then
					list = {}
					buckets[key] = list
				end
				if list[#list] ~= wall then
					local seen = false
					for _, other in list do
						if other == wall then
							seen = true
							break
						end
					end
					if not seen then
						table.insert(list, wall)
					end
				end
			end
		end
		wall.loads = nil
	end

	for _, enemy in enemiesFolder:GetChildren() do
		local radius = enemy:IsA("Model") and enemy:GetAttribute("BodyRadius")
		if radius then
			local p = enemy:GetPivot().Position
			local list = buckets[bucketKey(p.X, p.Z)]
			if list then
				local feet = p.Y - (enemy:GetAttribute("RideHeight") or 1.5)
				for _, wall in list do
					local c = wall.root.Position
					if feet > wall.top - PLAN.onTopBelow and feet < wall.top + PLAN.onTopAbove
						and math.abs(p.X - c.X) < wall.half + 0.3 and math.abs(p.Z - c.Z) < wall.half + 0.3 then
						wall.loads = wall.loads or {}
						table.insert(wall.loads, { x = p.X, z = p.Z, radius = radius,
							heft = math.clamp(radius / PLAN.heavyRadius, 0.3, 1) })
					end
				end
			end
		end
	end

	for _, wall in walls do
		local loads = wall.loads
		if loads or wall.loaded then
			wall.loaded = loads ~= nil
			for _, bag in wall.bags do
				-- Давит на верхний ряд, через него — вполсилы на ряд под ним.
				local depth = wall.rows - 1 - bag.row
				local weight = 0
				if loads and depth <= 1 then
					local bp = bag.base.Position
					for _, load in loads do
						local d = math.sqrt((bp.X - load.x) ^ 2 + (bp.Z - load.z) ^ 2)
						local near = math.clamp(1 - d / (load.radius + PLAN.weightReach), 0, 1)
						weight = math.max(weight, near * load.heft * (depth == 0 and 1 or 0.5))
					end
				end
				if math.abs(weight - bag.weight) > 0.02 then
					bag.weight = weight
					retarget(bag)
					wake(bag)
				end
			end
		end
	end
end)
