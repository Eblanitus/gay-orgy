-- Дроны-носильщики (по вики): наземные дроны на колёсах ездят от Биореактора к трупам и
-- обратно. Труп возят по частям: лапу тянет один дрон, тушу гиганта — только несколько
-- вместе (Corpses: record.crew). Ездят по карте, поэтому глухой лабиринт отрезает доход:
-- постройки для них непроходимы, путь ищется по сетке (Grid.GetOccupant).
--
-- Сколько дронов: Towers.Bioreactor.carriers плюс Towers.CarrierStation.carriers за каждую
-- Станцию носильщиков на поле. Нет реактора — нет и дронов: Станции без него молчат.
-- Числа движения — Economy (carrierSpeed и прочие).
--
-- Дрон смертен: жук, у которого он оказался под жвалами, кусает его (охоты за дронами нет —
-- только то, что попалось на пути). Погибший взрывается, его груз падает на поле обрезком
-- (Corpses.Drop) и ждёт следующего дрона, бригада без него разворачивается домой, а взамен
-- через Economy.carrierRespawn выезжает новый. Числа — Economy (carrierHp и прочие).
--
-- Упрощения (в вики открыто или не про это): элемент в реакторе/станции дронов не меняет; путь считается от реактора в момент выезда
-- и на ходу не пересчитывается — новая постройка на пути его не остановит.
--
-- Точки подключения для модели и интерфейса: модель дрона — EconomyModels.Carrier
-- (атрибуты State, Loaded, Crew, HP, MaxHP; деталь Cargo), папка Workspace.Carriers; на реакторе —
-- атрибуты Carriers (всего дронов) и Unreachable (трупов без проезда).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Towers = require(ReplicatedStorage:WaitForChild("Towers"))
local Economy = require(ReplicatedStorage:WaitForChild("Economy"))
local Grid = require(ServerScriptService:WaitForChild("Grid"))
local Corpses = require(ServerScriptService:WaitForChild("Corpses"))
local Bioreactor = require(ServerScriptService:WaitForChild("Bioreactor"))
local EconomyModels = require(ServerScriptService:WaitForChild("EconomyModels"))
local Impulse = require(ServerScriptService:WaitForChild("Impulse"))
local Enemies = require(ReplicatedStorage:WaitForChild("Enemies"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local ExplosionRemote = Remotes:WaitForChild("Explosion")
local DamageDealtRemote = Remotes:WaitForChild("DamageDealt")

local towersFolder = Workspace:WaitForChild("Towers")
local enemiesFolder = Workspace:WaitForChild("Enemies")

local folder = Workspace:FindFirstChild("Carriers")
if not folder then
	folder = Instance.new("Folder")
	folder.Name = "Carriers"
	folder.Parent = Workspace
end

local Carriers = {}

local reactor = nil -- модель Биореактора на поле (он один, Towers.Bioreactor.limit)
local drones = {} -- { model, state, path, index, at, job, share, retire }
local jobs = {} -- [record] = { record, members = {дроны}, arrived = число }
local pending = 0 -- погибших, чья замена ещё не выехала (Economy.carrierRespawn)
local epoch = 0 -- растёт при сбросе: замена из прежнего забега/реактора не выезжает
local dropped = {} -- [record] = видимый ком упавшего груза (Corpses.Drop)

-- ===== Проезд: одна волна от реактора на всю сетку =====
--
-- Дешевле, чем путь на каждый труп: занятость меняется редко (стройка, снос), а трупов
-- десятки. parent[клетка] — откуда в неё пришли от реактора; путь к трупу — цепочка родителей.
local flood = nil -- { parent = {}, dist = {} } или nil — пересчитать
local cols = Grid.Cols

local function key(cx, cz)
	return (cz - 1) * cols + cx
end

local NEIGHBOURS = {
	{ 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 },
	{ 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 },
}

-- Дрон проезжает клетку, если в ней ничего не стоит — кроме самого реактора и Станций:
-- из них дроны и выезжают.
local function passable(cx, cz)
	if not Grid.InBounds(cx, cz) then
		return false
	end
	local occupant = Grid.GetOccupant(cx, cz)
	if not occupant then
		return true
	end
	local kind = occupant:GetAttribute("Type")
	return occupant == reactor or kind == "CarrierStation"
end

local function buildFlood()
	cols = Grid.Cols
	local parent, dist = {}, {}
	local sx, sz = Grid.ToCell(reactor:GetPivot().Position)
	local start = key(sx, sz)
	dist[start] = 0
	local queue, head = { { sx, sz } }, 1
	while queue[head] do
		local cell = queue[head]
		head += 1
		local cx, cz = cell[1], cell[2]
		local here = dist[key(cx, cz)]
		for _, step in NEIGHBOURS do
			local nx, nz = cx + step[1], cz + step[2]
			local nk = key(nx, nz)
			-- Диагональ — только если обе смежные клетки проезжие: иначе дрон срезал бы угол постройки.
			if dist[nk] == nil and passable(nx, nz)
				and (step[1] == 0 or step[2] == 0 or (passable(cx + step[1], cz) and passable(cx, cz + step[2]))) then
				dist[nk] = here + 1
				parent[nk] = key(cx, cz)
				table.insert(queue, { nx, nz })
			end
		end
	end
	flood = { parent = parent, dist = dist, cols = cols }
end

local function floodReady()
	if not reactor or not reactor.Parent then
		return nil
	end
	if not flood or flood.cols ~= Grid.Cols then
		buildFlood()
	end
	return flood
end

-- Ближайшая к точке проезжая клетка, до которой есть проезд (труп мог упасть у самой стены).
local function reachableCell(position)
	local f = floodReady()
	if not f then
		return nil
	end
	local cx, cz = Grid.ToCell(position)
	local best, bestDist = nil, math.huge
	for radius = 0, 3 do
		for dz = -radius, radius do
			for dx = -radius, radius do
				if math.max(math.abs(dx), math.abs(dz)) == radius then
					local k = key(cx + dx, cz + dz)
					local d = Grid.InBounds(cx + dx, cz + dz) and f.dist[k]
					if d and d < bestDist then
						best, bestDist = k, d
					end
				end
			end
		end
		if best then
			return best, bestDist
		end
	end
	return nil
end

-- Путь от реактора до клетки: точки в мире, спрямлённые по поворотам.
local function pathTo(targetKey)
	local f = flood
	local cells = {}
	local k = targetKey
	while k do
		table.insert(cells, 1, k)
		k = f.parent[k]
	end
	local points = {}
	local lastDir = nil
	for i, cellKey in cells do
		local cz = math.floor((cellKey - 1) / f.cols) + 1
		local cx = cellKey - (cz - 1) * f.cols
		local dir = nil
		if i < #cells then
			dir = cells[i + 1] - cellKey
		end
		if i == 1 or i == #cells or dir ~= lastDir then
			table.insert(points, Grid.ToWorld(cx, cz) + Vector3.new(0, Economy.carrierLift, 0))
		end
		lastDir = dir
	end
	return points
end

Grid.Changed.Event:Connect(function()
	flood = nil
end)

-- ===== Дроны =====

local function setState(drone, state)
	drone.state = state
	if drone.model.Parent then
		drone.model:SetAttribute("State", state)
	end
end

local function setLoaded(drone, loaded)
	drone.model:SetAttribute("Loaded", loaded)
	local cargo = drone.model:FindFirstChild("Cargo")
	if cargo and cargo:IsA("BasePart") then
		cargo.Transparency = loaded and 0 or 1
	end
end

local function homePoint(index)
	local center = reactor:GetPivot().Position
	local angle = index * 2.4
	local ring = (Towers.Bioreactor.footprint or 4) / 2 + 1
	local floor = Grid.ToWorld(Grid.ToCell(center))
	return Vector3.new(center.X + math.cos(angle) * ring, floor.Y + Economy.carrierLift, center.Z + math.sin(angle) * ring)
end

-- Объезд реактора по кругу стоянок: от стоянки до точки, где путь выходит из-под реактора,
-- прямая шла бы сквозь корпус Завода (след у него крупный). Точки — по дуге через ~30°.
local function ringDetour(route, from, to)
	local center = reactor:GetPivot().Position
	local ring = (Towers.Bioreactor.footprint or 4) / 2 + 1
	local a0 = math.atan2(from.Z - center.Z, from.X - center.X)
	local a1 = math.atan2(to.Z - center.Z, to.X - center.X)
	local turn = (a1 - a0 + math.pi) % (2 * math.pi) - math.pi
	local steps = math.floor(math.abs(turn) / math.rad(30))
	for i = 1, steps do
		local angle = a0 + turn * i / (steps + 1)
		table.insert(route, Vector3.new(center.X + math.cos(angle) * ring, from.Y, center.Z + math.sin(angle) * ring))
	end
end

local function spawnDrone()
	local model = EconomyModels.Carrier()
	local drone = { model = model, at = homePoint(#drones + 1), hp = Economy.carrierHp }
	model:PivotTo(CFrame.new(drone.at))
	model:SetAttribute("Loaded", false)
	model:SetAttribute("MaxHP", Economy.carrierHp)
	model:SetAttribute("HP", Economy.carrierHp)
	model.Parent = folder
	table.insert(drones, drone)
	setState(drone, "idle")
	setLoaded(drone, false)
	return drone
end

local function removeDrone(drone)
	local index = table.find(drones, drone)
	if index then
		table.remove(drones, index)
	end
	if drone.model.Parent then
		drone.model:Destroy()
	end
end

local function leaveJob(drone)
	local job = drone.job
	drone.job = nil
	if not job then
		return
	end
	local index = table.find(job.members, drone)
	if index then
		table.remove(job.members, index)
	end
	if #job.members == 0 then
		jobs[job.record] = nil
	end
end

-- Дрон разворачивается домой по тому же пути (без груза — задание сорвалось).
local function sendBack(drone, loaded)
	-- Пройденные точки в обратном порядке, последняя — точка стоянки у реактора.
	local back = {}
	for i = math.min(drone.index - 1, #drone.path), 1, -1 do
		table.insert(back, drone.path[i])
	end
	if #back == 0 then
		back = { drone.at }
	end
	drone.path, drone.index = back, 1
	setLoaded(drone, loaded)
	setState(drone, "back")
end

local function wanted()
	if not reactor or not reactor.Parent then
		return 0
	end
	local count = Towers.Bioreactor.carriers or 0
	local perStation = Towers.CarrierStation and Towers.CarrierStation.carriers or 0
	for _, tower in towersFolder:GetChildren() do
		if tower:GetAttribute("Type") == "CarrierStation" and (tower:GetAttribute("HP") or 0) > 0 then
			count += perStation
		end
	end
	return count
end

-- Число дронов под реактор и Станции: новых — сразу, лишних — по мере возвращения.
-- Погибшие, чья замена ещё в пути, считаются за живых: иначе замена выехала бы сразу.
local function syncCount()
	local need = wanted()
	local active = pending
	for _, drone in drones do
		if not drone.retire then
			active += 1
		end
	end
	while active < need do
		spawnDrone()
		active += 1
	end
	-- Лишние: сперва отменяются ещё не выехавшие замены, потом уходят дроны.
	while active > need and pending > 0 do
		pending -= 1
		active -= 1
	end
	for i = #drones, 1, -1 do
		if active <= need then
			break
		end
		local drone = drones[i]
		if not drone.retire then
			drone.retire = true
			active -= 1
			if drone.state == "idle" then
				removeDrone(drone)
			end
		end
	end
	if reactor and reactor.Parent then
		reactor:SetAttribute("Carriers", need)
	end
end

local function dropAll()
	for _, drone in table.clone(drones) do
		removeDrone(drone)
	end
	table.clear(jobs)
	pending = 0
	epoch += 1
end

local function adoptReactor(model)
	if reactor == model then
		return
	end
	dropAll()
	reactor = model
	flood = nil
	model.Destroying:Once(function()
		if reactor == model then
			reactor = nil
			dropAll() -- реактор снесли: дроны и всё, что они везли, пропадают
		end
	end)
	syncCount()
end

towersFolder.ChildAdded:Connect(function(child)
	local kind = child:GetAttribute("Type")
	if kind == "Bioreactor" then
		adoptReactor(child)
	elseif kind == "CarrierStation" then
		syncCount()
	end
end)
towersFolder.ChildRemoved:Connect(function(child)
	if child:GetAttribute("Type") == "CarrierStation" then
		syncCount()
	end
end)

-- ===== Задания =====

local function idleDrones()
	local list = {}
	for _, drone in drones do
		if drone.state == "idle" and not drone.retire then
			table.insert(list, drone)
		end
	end
	return list
end

local function assign()
	if not floodReady() then
		return
	end
	local free = idleDrones()
	local total = #drones
	local unreachable = 0

	-- Кандидаты: ближние по проезду первыми; бригаду собирают целиком из свободных разом —
	-- тушу Гиганта, на которую дронов пока не хватает, обходят и возят мелочь.
	local candidates = {}
	for _, record in Corpses.Valuable() do
		if not jobs[record] then
			local cellKey, distance = reachableCell(record.position)
			if cellKey then
				table.insert(candidates, { record = record, cell = cellKey, distance = distance })
			else
				unreachable += 1
			end
		end
	end
	if reactor then
		reactor:SetAttribute("Unreachable", unreachable)
	end
	if #free == 0 then
		return
	end
	table.sort(candidates, function(a, b)
		return a.distance < b.distance
	end)

	for _, candidate in candidates do
		local crew = candidate.record.crew or 1
		if crew <= #free and crew <= total then
			local path = pathTo(candidate.cell)
			local job = { record = candidate.record, members = {}, arrived = 0 }
			jobs[candidate.record] = job
			for _ = 1, crew do
				local drone = table.remove(free)
				drone.job = job
				-- Из точки стоянки — к первой точке пути и дальше.
				-- Точки под самим реактором пропускаются: дрон выезжает со своей стоянки рядом.
				local route = { drone.at }
				local center = reactor:GetPivot().Position
				local inside = (Towers.Bioreactor.footprint or 4) / 2 + 0.5
				for _, point in path do
					local flat = (point - center) * Vector3.new(1, 0, 1)
					if #route > 1 or flat.Magnitude > inside then
						if #route == 1 then
							ringDetour(route, drone.at, point)
						end
						table.insert(route, point)
					end
				end
				drone.path, drone.index = route, 1
				table.insert(job.members, drone)
				drone.model:SetAttribute("Crew", crew)
				setState(drone, "out")
			end
		end
		if #free == 0 then
			break
		end
	end
end

-- Все в бригаде на месте: туша уходит с поля, её ценность делится поровну.
local function pickUp(job)
	local value = Corpses.Take(job.record)
	jobs[job.record] = nil
	local share = value / math.max(#job.members, 1)
	for _, drone in job.members do
		drone.job = nil
		drone.share = share
		sendBack(drone, value > 0)
	end
end

local function arrive(drone)
	if drone.state == "out" then
		local job = drone.job
		if not job or not job.record.alive then
			leaveJob(drone)
			sendBack(drone, false)
			return
		end
		job.arrived += 1
		setState(drone, "wait")
		if job.arrived >= #job.members then
			task.delay(Economy.pickupTime, function()
				if jobs[job.record] == job then
					if job.record.alive then
						pickUp(job)
					else
						jobs[job.record] = nil
						for _, member in job.members do
							member.job = nil
							sendBack(member, false)
						end
					end
				end
			end)
		end
	elseif drone.state == "back" then
		local share = drone.share or 0
		drone.share = nil
		setLoaded(drone, false)
		drone.model:SetAttribute("Crew", nil)
		if share > 0 and reactor and reactor.Parent then
			Bioreactor.Process(reactor, share)
		end
		if drone.retire then
			removeDrone(drone)
		else
			setState(drone, "idle")
		end
	end
end

-- ===== Гибель дронов =====

-- Бригада осталась без участника: туша снова свободна (её возьмёт полная бригада на
-- следующей раздаче), остальные разворачиваются домой порожняком — ждать некого.
local function breakJob(job)
	if jobs[job.record] == job then
		jobs[job.record] = nil
	end
	for _, member in table.clone(job.members) do
		member.job = nil
		if member.state == "out" or member.state == "wait" then
			sendBack(member, false)
		end
	end
end

-- Груз погибшего падает на место: запись трупа (её снова повезут) и видимый ком из кузова.
local function dropCargo(drone, position, value)
	local floor = Grid.ToWorld(Grid.ToCell(position))
	local record = Corpses.Drop(Vector3.new(position.X, floor.Y, position.Z), value)
	if not record then
		return
	end
	local cargo = drone.model:FindFirstChild("Cargo")
	if cargo and cargo:IsA("BasePart") then
		local lump = cargo:Clone()
		lump.Name = "DroppedCargo"
		lump.Anchored = true
		lump.CanCollide = false
		lump.CanQuery = false
		lump.Transparency = 0
		lump.CFrame = CFrame.new(position.X, floor.Y + lump.Size.Y / 2, position.Z)
			* drone.model:GetPivot().Rotation
		lump.Parent = folder
		dropped[record] = lump
	end
end

local function killDrone(drone)
	if not table.find(drones, drone) then
		return
	end
	local position = drone.model:GetPivot().Position
	local share = drone.share or 0
	drone.share = nil
	if drone.job then
		local job = drone.job
		leaveJob(drone)
		breakJob(job)
	end
	if share > 0 and drone.model:GetAttribute("Loaded") then
		dropCargo(drone, position, share)
	end

	-- Взрыв — тот же, что у подорвавшегося FPV-дрона (CombatFX рисует, GameAudio — звук
	-- SoundBank.Blast.drone). Урона нет: только толчок незакреплённого вокруг.
	ExplosionRemote:FireAllClients(position, Economy.carrierBlastRadius, Economy.carrierBlastColor)
	Impulse.Blast(position, Economy.carrierBlastRadius)
	print(("[Носильщики] дрон взорван%s"):format(share > 0 and (", груз %.0f упал"):format(share) or ""))

	local retired = drone.retire
	removeDrone(drone)
	if retired then
		return -- его и так убирали: замена не нужна
	end
	pending += 1
	local myEpoch = epoch
	task.delay(Economy.carrierRespawn, function()
		if epoch == myEpoch and pending > 0 then
			pending -= 1
			syncCount()
		end
	end)
end

local function hurtDrone(drone, damage, from)
	drone.hp = math.max(0, drone.hp - damage)
	drone.model:SetAttribute("HP", drone.hp)
	DamageDealtRemote:FireAllClients(drone.model:GetPivot().Position, damage, false)
	if from then
		-- Укус виден так же, как грызня постройки (EnemySpawner.markBite).
		from:SetAttribute("Bite", (from:GetAttribute("Bite") or 0) + 1)
	end
	if drone.hp <= 0 then
		killDrone(drone)
	end
end

-- Укусы: наземный жук кусает ближайшего дрона, оказавшегося у него под жвалами, с той же
-- частотой и силой, что грызёт постройки (Холод и Кислота ослабляют так же). Летуны, свои
-- (очищенные) и оглушённые не кусают.
local lastBite = setmetatable({}, { __mode = "k" })

local function bites()
	if #drones == 0 then
		return
	end
	local now = os.clock()
	for _, enemy in enemiesFolder:GetChildren() do
		if enemy:IsA("Model") and not enemy:GetAttribute("Flying") and not enemy:GetAttribute("Ally")
			and (enemy:GetAttribute("HP") or 0) > 0 and now >= (enemy:GetAttribute("StunnedUntil") or 0) then
			local data = Enemies[enemy:GetAttribute("Type")]
			local damage = data and data.chewDamage or 0
			local attackSlow = math.clamp(enemy:GetAttribute("AttackSlowPercent") or 0, 0, 0.9)
			local rate = (data and data.chewRate or 1) * (1 - attackSlow)
			if damage > 0 and now - (lastBite[enemy] or -math.huge) >= 1 / rate then
				local at = enemy:GetPivot().Position
				local reach = (enemy:GetAttribute("FootFront") or 0) + (enemy:GetAttribute("FootRadius") or 1.5)
					+ Economy.carrierBiteReach
				local best, bestDistance = nil, reach
				for _, drone in drones do
					local distance = ((drone.model:GetPivot().Position - at) * Vector3.new(1, 0, 1)).Magnitude
					if distance <= bestDistance then
						best, bestDistance = drone, distance
					end
				end
				if best then
					lastBite[enemy] = now
					local weakened = math.clamp(enemy:GetAttribute("Weakened") or 0, 0, 0.9)
					hurtDrone(best, math.max(1, math.floor(damage * (1 - weakened) + 0.5)), enemy)
				end
			end
		end
	end
end

-- Упавший груз увезли, съели или стёрли сбросом поля — ком убирается.
local function sweepDropped()
	for record, lump in dropped do
		if not record.alive then
			dropped[record] = nil
			lump:Destroy()
		end
	end
end

-- Движение: по точкам пути с постоянной скоростью, груз — медленнее.
RunService.Heartbeat:Connect(function(dt)
	for _, drone in table.clone(drones) do
		local state = drone.state
		if state == "out" or state == "back" then
			-- Туша пропала, пока ехали (съел Пеликан, лопнула, осыпалась в ничто) — домой.
			if state == "out" and drone.job and not drone.job.record.alive then
				local job = drone.job
				jobs[job.record] = nil
				for _, member in table.clone(job.members) do
					member.job = nil
					if member.state == "out" or member.state == "wait" then
						sendBack(member, false)
					end
				end
			end
			local speed = drone.model:GetAttribute("Loaded") and Economy.carrierLoadedSpeed or Economy.carrierSpeed
			local step = speed * dt
			local position = drone.model:GetPivot().Position
			while step > 0 do
				local target = drone.path[drone.index]
				if not target then
					break
				end
				local delta = target - position
				local distance = delta.Magnitude
				if distance <= step then
					position = target
					step -= distance
					drone.index += 1
				else
					position += delta.Unit * step
					step = 0
				end
			end
			local heading = drone.path[drone.index]
			local look = heading and (heading - position) * Vector3.new(1, 0, 1)
			if look and look.Magnitude > 1e-3 then
				drone.model:PivotTo(CFrame.lookAt(position, position + look))
			else
				drone.model:PivotTo(CFrame.new(position) * drone.model:GetPivot().Rotation)
			end
			if drone.index > #drone.path then
				if state == "back" then
					drone.model:PivotTo(CFrame.new(drone.at))
				end
				arrive(drone)
			end
		end
	end
end)

task.spawn(function()
	while true do
		task.wait(Economy.assignInterval)
		local ok, err = pcall(assign)
		if not ok then
			warn("[Носильщики] " .. tostring(err))
		end
	end
end)

task.spawn(function()
	while true do
		task.wait(Economy.carrierBiteCheck)
		local ok, err = pcall(bites)
		if not ok then
			warn("[Носильщики] " .. tostring(err))
		end
		sweepDropped()
	end
end)

-- Новый забег: дроны и задания прежнего уходят вместе с ним (реактор сносит WaveRunner,
-- стартовый ставит TowerBootstrap — его подхватит ChildAdded).
function Carriers.Reset()
	dropAll()
	reactor = nil
	flood = nil
end

-- Для проверок: сколько дронов и сколько из них в деле.
function Carriers.Stats()
	local busy = 0
	for _, drone in drones do
		if drone.state ~= "idle" then
			busy += 1
		end
	end
	return #drones, busy
end

return Carriers
