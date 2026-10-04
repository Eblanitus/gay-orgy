-- Общий физический слой: всё, что в игре лежит не закреплённым и подчиняется физике движка
-- (трупы, оторванные лапы, осколки, крошки, а дальше и обломки турелей). Работает и на сервере,
-- и на клиенте: вид (трупы, крошки) считает клиент, детали, от которых зависит игра, — сервер.
--
-- Здесь одно на всех: группы столкновений, метка «толкать», толчок, поиск незакреплённого
-- рядом, взрыв и отдача, папки, растворение и потолок числа деталей. Системы останков
-- (CorpseFX, CorpseRemains) и толчков (ImpulseFX, Impulse) берут всё это отсюда, а не держат
-- по своей копии. Числа — в PhysicsFX.
local CollectionService = game:GetService("CollectionService")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local PhysicsFX = require(ReplicatedStorage:WaitForChild("PhysicsFX"))
local Arena = require(ReplicatedStorage:WaitForChild("Arena"))

local Loose = {}

-- Метка «физический объект, толкать»: у трупов и кусков CanQuery = false, пространственный
-- запрос их не видит, поэтому взрыв ищет их по метке.
Loose.Tag = "Loose"

-- Имена групп столкновений. Только отсюда, а не строкой в других скриптах: две копии
-- названия разойдутся при первой же опечатке.
Loose.Groups = {
	Default = "Default",
	Enemies = "Enemies", -- видимые тела жуков: толкают трупы, больше ни с чем не сталкиваются
	Corpses = "Corpses", -- трупы, лапы, осколки: лежат на полу и платформах, толкаются друг о друга
	Car = "ArcadeCar", -- корпус машины Аркады
	Wheel = "ArcadeWheel", -- колёса машины: пол держат лучи подвески, колёса только расшвыривают останки
	Barrier = "PlayerBarrier", -- невидимые крышки над стенами и сердечники турелей: держат только игрока
	Probe = "Probe", -- группа лучей (линия огня, лапы, обломки): видит всё, кроме Barrier
}

-- Кто с кем сталкивается. Пары, которых нет в списке, — как задано движком по умолчанию.
local COLLIDE = {
	-- Жук толкает трупы и игрока: сквозь живого жука не пройти. Жук анкорнут и ходит
	-- маршрутом, так что пол и постройки (тоже на якоре) физически на него не влияют.
	{ "Enemies", "Corpses", true },
	{ "Enemies", "Default", true },
	{ "Enemies", "Enemies", false },
	{ "Corpses", "Default", true },
	{ "Corpses", "Corpses", true },
	-- Машина сталкивается с полем, ограждением и останками, но не с жуками: давку считает код,
	-- и жук под колёсами не должен подбрасывать машину.
	{ "Car", "Default", true },
	{ "Car", "Car", false },
	{ "Car", "Wheel", false },
	{ "Car", "Enemies", false },
	{ "Car", "Corpses", true },
	{ "Wheel", "Default", false },
	{ "Wheel", "Wheel", false },
	{ "Wheel", "Enemies", false },
	{ "Wheel", "Corpses", true },
	-- Крышка над стенами не даёт игроку уйти поверху, а всё остальное пропускает: труп,
	-- подброшенный выше потолка, не должен остаться лежать на невидимой плите.
	{ "Barrier", "Default", true },
	{ "Barrier", "Barrier", false },
	{ "Barrier", "Enemies", false },
	{ "Barrier", "Corpses", false },
	{ "Barrier", "Car", false },
	{ "Barrier", "Wheel", false },
	-- Лучи с группой Probe проходят сквозь невидимые сердечники и крышки.
	{ "Probe", "Barrier", false },
}

-- Заводит группы. Только на сервере (клиенту группы реплицируются) и один раз при загрузке,
-- а не руками в Studio: иначе работающий код зависит от настройки, которой нет ни в одном файле.
local groupsReady = false
function Loose.SetupGroups()
	if groupsReady or not RunService:IsServer() then
		return
	end
	groupsReady = true
	for key, name in Loose.Groups do
		if key ~= "Default" and not PhysicsService:IsCollisionGroupRegistered(name) then
			PhysicsService:RegisterCollisionGroup(name)
		end
	end
	for _, pair in COLLIDE do
		PhysicsService:CollisionGroupSetCollidable(Loose.Groups[pair[1]], Loose.Groups[pair[2]], pair[3])
	end
end

-- Папка в Workspace по имени (Corpses, Debris, Blood): создаётся при первом обращении.
function Loose.Folder(name)
	local folder = Workspace:FindFirstChild(name)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = name
		folder.Parent = Workspace
	end
	return folder
end

-- Растворяет и сносит. Не мгновенный Destroy нарочно: деталь, пропавшая на глазах
-- в один кадр, читается как поломка. time — секунды, по умолчанию PhysicsFX.cleanup.fadeTime.
function Loose.Dissolve(instance, time)
	if not instance or not instance.Parent then
		return
	end
	time = time or PhysicsFX.cleanup.fadeTime

	local info = TweenInfo.new(time, Enum.EasingStyle.Linear)
	for _, part in instance:GetDescendants() do
		if part:IsA("BasePart") then
			TweenService:Create(part, info, { Transparency = 1 }):Play()
		end
	end
	if instance:IsA("BasePart") then
		TweenService:Create(instance, info, { Transparency = 1 }):Play()
	end

	task.delay(time, function()
		if instance.Parent then
			instance:Destroy()
		end
	end)
end

-- Список с потолком: новое в конец, при превышении limit самые старые растворяются.
function Loose.Remember(list, instance, limit)
	table.insert(list, instance)
	while #list > limit do
		Loose.Dissolve(table.remove(list, 1))
	end
end

-- Общий учёт живых деталей по видам: у каждого вида свой потолок (PhysicsFX.cleanup.limits),
-- лишние самые старые растворяются. Ушедшее само (растаяло, разбилось, снесено по таймеру)
-- выпадает из учёта по Destroying — отдельно «забывать» его не нужно.
local tracked = {} -- [вид] = { экземпляры по порядку появления }
function Loose.Track(instance, kind)
	local limit = PhysicsFX.cleanup.limits[kind]
	assert(limit, "Loose.Track: нет потолка для вида " .. tostring(kind))
	local list = tracked[kind]
	if not list then
		list = {}
		tracked[kind] = list
	end
	instance.Destroying:Once(function()
		local index = table.find(list, instance)
		if index then
			table.remove(list, index)
		end
	end)
	Loose.Remember(list, instance, limit)
end

-- Сколько деталей вида сейчас живо (для отладки и проверок).
function Loose.Count(kind)
	return tracked[kind] and #tracked[kind] or 0
end

-- Сносит всё учтённое сразу, без растворения (конец забега).
function Loose.ClearTracked()
	for _, list in tracked do
		for _, instance in table.clone(list) do
			if instance.Parent then
				instance:Destroy()
			end
		end
		table.clear(list)
	end
end

function Loose.RandomSpin(amount)
	return Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 2 * amount
end

-- Толчок сборки: прибавка к скорости и вращению. На сервере сборка забирается серверу:
-- иначе толчок уйдёт в симуляцию, которую ведёт не он.
function Loose.Kick(root, velocity, spin)
	if RunService:IsServer() then
		pcall(function()
			root:SetNetworkOwner(nil)
		end)
	end
	root.AssemblyLinearVelocity += velocity
	root.AssemblyAngularVelocity += spin or Vector3.zero
end

-- Помеченное незакреплённое в радиусе: { root, distance } по одному на сборку.
function Loose.Around(center, radius)
	local list, seen = {}, {}
	for _, tagged in CollectionService:GetTagged(Loose.Tag) do
		local part = tagged:IsA("Model") and tagged.PrimaryPart or tagged
		local root = part and part:IsA("BasePart") and part.AssemblyRootPart
		if root and not root.Anchored and not seen[root] and tagged:IsDescendantOf(Workspace) then
			seen[root] = true
			local distance = (root.Position - center).Magnitude
			if distance <= radius then
				table.insert(list, { root = root, distance = distance })
			end
		end
	end
	return list
end

-- Любые незакреплённые сборки в радиусе по пространственному запросу (видны только детали
-- с CanQuery). По корню, а не по деталям: сваренную сборку из двадцати деталей иначе толкнуло
-- бы вдвадцатеро сильнее. skip(root) -> true — пропустить (например, персонажа игрока).
function Loose.AroundInBounds(center, radius, skip)
	local roots, list = {}, {}
	for _, part in Workspace:GetPartBoundsInRadius(center, radius) do
		local root = not part.Anchored and part.AssemblyRootPart
		if root and not root.Anchored and roots[root] == nil then
			roots[root] = true
			if not (skip and skip(root)) then
				table.insert(list, { root = root, distance = (root.Position - center).Magnitude })
			end
		end
	end
	return list
end

-- Дальность ударной волны взрыва радиуса radius (числа — PhysicsFX.blast).
function Loose.BlastReach(radius)
	local plan = PhysicsFX.blast
	return math.max(radius or plan.referenceRadius, 1) * plan.reach
end

-- Взрыв: толкает найденное (список из Around / AroundInBounds) от центра и вверх.
function Loose.Blast(found, center, radius, power)
	local plan = PhysicsFX.blast
	radius = math.max(radius or plan.referenceRadius, 1)
	local reach = radius * plan.reach
	local strength = plan.speed
		* math.clamp(radius / plan.referenceRadius, plan.powerMin, plan.powerMax)
		* (power or 1)

	for _, item in found do
		local falloff = 1 - item.distance / reach
		local away = item.root.Position - center
		away = Vector3.new(away.X, 0, away.Z)
		if away.Magnitude < 1e-3 then
			local angle = math.random() * math.pi * 2
			away = Vector3.new(math.cos(angle), 0, math.sin(angle))
		end
		local direction = (away.Unit + Vector3.yAxis * plan.lift).Unit
		Loose.Kick(item.root, direction * strength * falloff, Loose.RandomSpin(plan.spin * falloff))
	end
end

-- Отдача: жука сдвинуло на offset — лежащее вокруг него (found) летит туда же. Числа — PhysicsFX.push.
function Loose.Push(found, offset)
	local plan = PhysicsFX.push
	local flat = Vector3.new(offset.X, 0, offset.Z)
	local amount = flat.Magnitude
	if amount < 1e-3 then
		return
	end
	local speed = math.min(amount * plan.speedPerStud, plan.speedMax)
	local direction = (flat.Unit + Vector3.yAxis * plan.lift).Unit
	for _, item in found do
		local falloff = 1 - item.distance / plan.radius
		Loose.Kick(item.root, direction * speed * falloff, Loose.RandomSpin(speed * 0.2 * falloff))
	end
end

-- Высота опоры в точке (x, z): бетонные плиты пола (с ямами Строителя и Литосферы)
-- и лежащие обломки турелей. Раньше всё, что ложится на пол (кровь, лужи, лепёшки, угли),
-- клалось на одну плоскую высоту арены и висело в воздухе над ямой. fallback — если под
-- точкой нет ни плит, ни обломков (Аркада, меню); по умолчанию пол арены.
local FLOOR_FOLDERS = { "ConcreteFloor", "TowerDebris" }
local FLOOR_PROBE = 30 -- studs над полом арены, откуда пускается луч: выше любого вздутия рельефа
local floorParams = RaycastParams.new()
floorParams.FilterType = Enum.RaycastFilterType.Include

function Loose.FloorAt(x, z, fallback)
	fallback = fallback or Arena.floorY
	local include = {}
	for _, name in FLOOR_FOLDERS do
		local folder = Workspace:FindFirstChild(name)
		if folder then
			table.insert(include, folder)
		end
	end
	if #include == 0 or not Arena.floorY then
		return fallback
	end
	floorParams.FilterDescendantsInstances = include
	local from = Vector3.new(x, Arena.floorY + FLOOR_PROBE, z)
	local hit = Workspace:Raycast(from, Vector3.new(0, -FLOOR_PROBE * 2, 0), floorParams)
	return hit and hit.Position.Y or fallback
end

-- Укладка плашмя: деталь, которая замерла стоймя (длинная сторона смотрит вверх), получает
-- мягкий толчок вращения поперёк и валится набок. Одна проверка на всех, а не своя у каждой
-- системы. Числа — PhysicsFX.layFlat. Сборки, ушедшие из мира, выпадают из списка сами.
local flatWatch = {} -- [корень] = проверок подряд стоймя
local flatLoop = false

local function longestAxis(part)
	local size = part.Size
	local axis = size.X >= size.Y and size.X >= size.Z and Vector3.xAxis
		or (size.Y >= size.Z and Vector3.yAxis or Vector3.zAxis)
	return part.CFrame:VectorToWorldSpace(axis)
end

function Loose.LayFlat(root)
	if not root then
		return
	end
	flatWatch[root] = 0
	if flatLoop then
		return
	end
	flatLoop = true
	task.spawn(function()
		local plan = PhysicsFX.layFlat
		while true do
			task.wait(plan.check)
			for watched, count in flatWatch do
				if not watched.Parent then
					flatWatch[watched] = nil
				elseif not watched.Anchored
					and watched.AssemblyLinearVelocity.Magnitude < plan.still
					and watched.AssemblyAngularVelocity.Magnitude < plan.still then
					local axis = longestAxis(watched)
					if math.abs(axis.Y) > plan.standing then
						count += 1
						if count >= plan.after then
							local across = axis:Cross(Vector3.yAxis)
							if across.Magnitude < 1e-3 then
								across = Vector3.xAxis
							end
							watched.AssemblyAngularVelocity = across.Unit * plan.spin * (math.random() < 0.5 and -1 or 1)
							count = 0
						end
					else
						count = 0
					end
					flatWatch[watched] = count
				end
			end
		end
	end)
end

-- Выпускает деталь или сборку в физику: снимает якорь, ставит группу столкновений,
-- метку «толкать» и кладёт в папку. opts (всё необязательно):
--   group    — ключ Loose.Groups (по умолчанию Corpses);
--   folder   — имя папки в Workspace;
--   physics  — PhysicalProperties для всех деталей;
--   tag      — false, если толкать взрывами не надо;
--   velocity, spin — начальный толчок корня.
-- Возвращает корень сборки.
function Loose.Spawn(target, opts)
	opts = opts or {}
	local group = Loose.Groups[opts.group or "Corpses"]
	local parts = target:IsA("BasePart") and { target } or {}
	for _, part in target:GetDescendants() do
		if part:IsA("BasePart") then
			table.insert(parts, part)
		end
	end
	for _, part in parts do
		part.CollisionGroup = group
		if opts.physics then
			part.CustomPhysicalProperties = opts.physics
		end
		part.Anchored = false
	end
	if opts.folder then
		target.Parent = Loose.Folder(opts.folder)
	end
	if opts.tag ~= false then
		CollectionService:AddTag(target, Loose.Tag)
	end

	local first = target:IsA("Model") and target.PrimaryPart or parts[1]
	local root = first and first.AssemblyRootPart or first
	if root and (opts.velocity or opts.spin) then
		Loose.Kick(root, opts.velocity or Vector3.zero, opts.spin)
	end
	return root
end

return Loose
