-- Шаблоны жуков из авторских .glb (Мини, Хмурый брон, Моль, Работяга, Строитель, Пеликан).
--
-- Порядок:
--   1. Studio → Avatar/Home → Import 3D, по очереди все шесть файлов из папки «Модели/Жуки»:
--      mini_beetle.glb, hmuryi_bron.glb, moth.glb, worker_beetle.glb, builder_beetle.glb,
--      pelican_beetle.glb. Настройки импорта — по умолчанию. Импорт ляжет в Workspace
--      моделью с именем файла (worker_beetle и т.д.), так его скрипт и находит.
--   2. View → Command Bar, вставить весь файл, Enter. В Output — отчёт по каждому жуку.
--   3. Ctrl+S / Save to Roblox.
-- Отменить: Ctrl+Z сразу после запуска.
--
-- Что делает с каждым импортом — приводит к устройству ReplicatedStorage.NormalBeetleTemplate,
-- по которому собирают жука EnemyModel и EnemyGait:
--   * имена без хвостов импорта: Femur010 → Femur, leg_front_left001 → leg_front_left;
--   * масштаб: 1 единица .glb = 1 стад (Studio может импортировать в другой единице);
--   * лапы leg_* — модели с CoxaJoint (это ROOT_0x из .glb) в PrimaryPart;
--   * прямо в шаблоне группы head (HeadBase, глаза и всё, что сидит на голове),
--     mandible_left/right, antenna_left/right, wing_L/wing_R, body (остальное);
--   * BeetleBodyInner / abdomen → AbdomenCore (вместе с ThoraxCore — коллайдер и хитбокс);
--   * Root — копия Root у NormalBeetleTemplate: на 1 стад выше ступней, смотрит на голову;
--   * шаблон кладётся в ReplicatedStorage под именем из Enemies.luau, сам импорт удаляется.
-- Атрибутов Color* у новых шаблонов нет: игра перекрашивает их по BugPalette по именам деталей
-- (EnemyModel.ROLE_BY_NAME); COLORS — авторские цвета для Аркады и запасной вид.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

-- length — длина тела в .glb (перед головы → зад брюшка), по ней ставится масштаб.
-- head — детали, которые сидят на голове и должны двигаться вместе с ней (шаблоны Lua).
-- mandible — детали, которые ходят вместе с жвалой своей стороны.
-- flap — частота (взмахов/с) и угол (градусы) крыльев, если шаблону нужны не умолчания.
local SPECS = {
	{ source = "mini_beetle", template = "MiniBeetleTemplate", length = 2.96 },
	{
		source = "hmuryi_bron",
		template = "ArmoredBeetleTemplate",
		length = 3.45,
		head = { "^head_casque$", "^brow_ridge$", "^part_66$", "^part_67$", "^jaw_[LR]$", "^bite_muscle$" },
	},
	{
		source = "moth",
		template = "MothTemplate",
		length = 3.38,
		head = { "^labial_palp", "^part_44$", "^part_46$", "^part_48$" },
		flap = { freq = 2.2, angle = 40 },
	},
	{ source = "worker_beetle", template = "WorkerBeetleTemplate", length = 3.82 },
	{
		source = "builder_beetle",
		template = "BuilderBeetleTemplate",
		length = 4.35,
		head = { "^cheek_[LR]$", "^shovel_" },
	},
	{
		source = "pelican_beetle",
		template = "PelicanBeetleTemplate",
		length = 2.72,
		mandible = { "^beak_tooth$" },
		flap = { freq = 3.5, angle = 30 },
	},
}

local LEGS = {
	"leg_front_left", "leg_front_right",
	"leg_mid_left", "leg_mid_right",
	"leg_rear_left", "leg_rear_right",
}
local LEG_PARTS = { "Femur", "KneeJoint", "Tibia", "AnkleJoint", "Tarsus1", "Tarsus2" }
local WING_PARTS = { "^forewing$", "^hindwing$", "^wing_costa$", "^wing_membrane$", "^wing_vein" }
local ANTENNA_PARTS = { "^AntSeg%d", "^AntNode%d" }

local function baseName(name)
	return (name:gsub("%d%d%d$", ""))
end

local function matchesAny(name, patterns)
	for _, pattern in patterns or {} do
		if name:match(pattern) then
			return true
		end
	end
	return false
end

local function inGroup(part, name)
	local p = part.Parent
	while p and p:IsA("Model") do
		if baseName(p.Name) == name then
			return true
		end
		p = p.Parent
	end
	return false
end

local function findImport(source)
	for _, container in { workspace, ServerStorage, ReplicatedStorage } do
		for _, child in container:GetChildren() do
			if child:IsA("Model") and child.Name:lower() == source then
				return child
			end
		end
	end
	return nil
end

-- Края детали вдоль направления dir (мировые углы её коробки).
local function extent(part, dir)
	local half = part.Size * 0.5
	local lo, hi = math.huge, -math.huge
	for _, sx in { -1, 1 } do
		for _, sy in { -1, 1 } do
			for _, sz in { -1, 1 } do
				local d = (part.CFrame * Vector3.new(half.X * sx, half.Y * sy, half.Z * sz)):Dot(dir)
				lo = math.min(lo, d)
				hi = math.max(hi, d)
			end
		end
	end
	return lo, hi
end

local function prepare(spec, normalRoot)
	local source = findImport(spec.source)
	if not source then
		return false, "нет импорта " .. spec.source .. " в Workspace / ServerStorage / ReplicatedStorage"
	end
	-- Работа на копии: на любой ошибке исходный импорт остаётся как был.
	local import = source:Clone()

	-- Все детали по базовому имени. Каждая — отдельно, в том числе вложенные друг в друга
	-- (у Моли полоска крыла сидит внутри меша крыла).
	local parts = {}
	for _, d in import:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(parts, d)
		end
	end
	local function first(name)
		for _, part in parts do
			if baseName(part.Name) == name then
				return part
			end
		end
		return nil
	end

	local headBase, thorax = first("HeadBase"), first("ThoraxCore")
	local abdomen = first("BeetleBodyInner") or first("abdomen")
	if not (headBase and thorax and abdomen) then
		return false, "не найдены HeadBase / ThoraxCore / брюшко"
	end

	-- Масштаб: 1 единица .glb = 1 стад.
	local center = (thorax.Position + abdomen.Position) / 2
	local dir = Vector3.new(headBase.Position.X - center.X, 0, headBase.Position.Z - center.Z).Unit
	local _, front = extent(headBase, dir)
	local rear = extent(abdomen, dir)
	local plate5 = first("BeetlePlate_05")
	if plate5 then
		rear = math.min(rear, (extent(plate5, dir)))
	end
	import:ScaleTo(import:GetScale() * spec.length / (front - rear))

	center = (thorax.Position + abdomen.Position) / 2
	dir = Vector3.new(headBase.Position.X - center.X, 0, headBase.Position.Z - center.Z).Unit

	-- Ступни: Root на 1 стад выше их низа — тогда RideHeight = scale ставит лапы на пол
	-- в авторской позе (так же стоит NormalBeetleTemplate).
	local footSum, footCount = 0, 0
	for _, part in parts do
		if baseName(part.Name) == "Tarsus2" then
			footSum += part.Position.Y - part.Size.Y / 2
			footCount += 1
		end
	end
	if footCount == 0 then
		return false, "нет ступней Tarsus2"
	end
	local rootPos = Vector3.new(center.X, footSum / footCount + 1, center.Z)
	-- Голова — по +Z кадра Root (так у NormalBeetleTemplate и так ждёт EnemyGait),
	-- левые лапы — по +X.
	local rootCF = CFrame.fromMatrix(rootPos, Vector3.yAxis:Cross(dir), Vector3.yAxis, dir)

	local template = Instance.new("Model")
	template.Name = spec.template
	local root
	if normalRoot then
		root = normalRoot:Clone()
		root:ClearAllChildren()
	else
		root = Instance.new("Part")
		root.Size = Vector3.new(1.4, 1, 1.4)
		root.Transparency = 1
	end
	root.Name = "Root"
	root.CFrame = rootCF
	root.Anchored = true
	root.Parent = template
	template.PrimaryPart = root

	local function group(name)
		local model = Instance.new("Model")
		model.Name = name
		model.Parent = template
		return model
	end
	local body = group("body")
	local head = group("head")
	local placed = {}
	local function put(part, parent, name)
		placed[part] = true
		part.Name = name or baseName(part.Name)
		part.Parent = parent
	end
	-- Сторона в кадре Root: +1 / -1 по X.
	local function side(part)
		return rootCF:PointToObjectSpace(part.Position).X >= 0 and 1 or -1
	end

	-- Лапы.
	local roots = {}
	for _, part in parts do
		if baseName(part.Name):match("^ROOT_%d+$") then
			table.insert(roots, part)
		end
	end
	local leftSide
	for _, legName in LEGS do
		local legModel
		for _, d in import:GetDescendants() do
			if d:IsA("Model") and baseName(d.Name) == legName then
				legModel = d
				break
			end
		end
		if not legModel then
			return false, "нет лапы " .. legName
		end
		local leg = group(legName)
		local femur
		for _, d in legModel:GetDescendants() do
			if d:IsA("BasePart") then
				put(d, leg)
				if d.Name == "Femur" then
					femur = d
				end
			end
		end
		for _, partName in LEG_PARTS do
			if not leg:FindFirstChild(partName) then
				return false, legName .. ": нет " .. partName
			end
		end
		-- Внутренний конец бедра — тот край коробки, что ближе к оси тела.
		local best, bestAxis = -1, nil
		for _, axis in { Enum.Axis.X, Enum.Axis.Y, Enum.Axis.Z } do
			local v = Vector3.FromAxis(axis)
			local world = femur.CFrame:VectorToWorldSpace(v)
			local toCenter = (rootPos - femur.Position)
			local d = math.abs(world:Dot(toCenter.Unit))
			if d > best then
				best, bestAxis = d, v
			end
		end
		local world = femur.CFrame:VectorToWorldSpace(bestAxis)
		local sign = world:Dot(rootPos - femur.Position) >= 0 and 1 or -1
		local hip = femur.Position + world * sign * (femur.Size:Dot(bestAxis) / 2)
		-- Сустав-шар ROOT_0x .glb, если он у бедра; иначе — невидимая точка.
		local coxa, coxaDist = nil, femur.Size.Magnitude
		for _, r in roots do
			local dist = (r.Position - hip).Magnitude
			if not placed[r] and dist < coxaDist then
				coxa, coxaDist = r, dist
			end
		end
		if not coxa then
			coxa = Instance.new("Part")
			coxa.Size = Vector3.one * 0.15
			coxa.Transparency = 1
			coxa.CFrame = CFrame.new(hip)
			coxa.Anchored = true
		end
		put(coxa, leg, "CoxaJoint")
		leg.PrimaryPart = coxa
		if legName == "leg_front_left" then
			leftSide = side(femur)
		end
	end

	-- Голова, жвалы, усики, крылья — по именам; что осталось — тело.
	local mandibles = {}
	for _, d in import:GetDescendants() do
		local name = baseName(d.Name)
		if d:IsA("Model") and (name == "mandible_left" or name == "mandible_right") then
			local m = group(name)
			for _, p in d:GetDescendants() do
				if p:IsA("BasePart") then
					put(p, m)
				end
			end
			local anchor = m:FindFirstChild("MandibleBase") or m:FindFirstChildWhichIsA("BasePart")
			if anchor then
				mandibles[side(anchor)] = m
			end
		end
	end
	local antennae, wings = {}, {}
	local function sideGroup(store, prefixLeft, prefixRight, part)
		local s = side(part)
		if not store[s] then
			store[s] = group(s == leftSide and prefixLeft or prefixRight)
		end
		return store[s]
	end
	for _, d in import:GetDescendants() do
		if d:IsA("Model") and (d.Name == "wing_L" or d.Name == "wing_R") then
			for _, p in d:GetDescendants() do
				if p:IsA("BasePart") then
					put(p, sideGroup(wings, "wing_L", "wing_R", p))
				end
			end
		end
	end
	for _, part in parts do
		if not placed[part] then
			local name = baseName(part.Name)
			if name == "HeadBase" or name:match("^Eye") or matchesAny(name, spec.head) or inGroup(part, "head") then
				put(part, head)
			elseif matchesAny(name, spec.mandible) and mandibles[side(part)] then
				put(part, mandibles[side(part)])
			elseif matchesAny(name, ANTENNA_PARTS) then
				put(part, sideGroup(antennae, "antenna_left", "antenna_right", part))
			elseif matchesAny(name, WING_PARTS) then
				put(part, sideGroup(wings, "wing_L", "wing_R", part))
			elseif part == abdomen then
				put(part, body, "AbdomenCore")
			else
				put(part, body)
			end
		end
	end

	for _, d in template:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanTouch = false
		end
	end
	if spec.flap then
		template:SetAttribute("WingFlapFreq", spec.flap.freq)
		template:SetAttribute("WingFlapAngle", math.rad(spec.flap.angle))
	end
	template.WorldPivot = rootCF

	local old = ReplicatedStorage:FindFirstChild(spec.template)
	if old then
		old:Destroy()
	end
	template.Parent = ReplicatedStorage
	import:Destroy()
	source:Destroy()

	local _, size = template:GetBoundingBox()
	return true, ("%d деталей, %.1f × %.1f × %.1f стад (в игре × scale из Enemies.luau)")
		:format(#parts, size.X, size.Y, size.Z)
end

local recording = ChangeHistoryService:TryBeginRecording("Шаблоны жуков из .glb")
local normal = ReplicatedStorage:FindFirstChild("NormalBeetleTemplate")
local normalRoot = normal and normal:FindFirstChild("Root")
for _, spec in SPECS do
	local ran, ok, message = pcall(prepare, spec, normalRoot)
	if not ran then
		ok, message = false, "ошибка скрипта: " .. tostring(ok)
	end
	print(("[Жуки] %s %s: %s"):format(ok and "✔" or "✘", spec.template, message))
end
if recording then
	ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
end
