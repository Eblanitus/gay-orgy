-- Шаблоны жуков из .glb (Мини, Хмурый брон, Моль, Работяга, Строитель, Пеликан, Стандарт).
-- Сами .glb собирает tools/beetles/build_all.py (python3, numpy) — правка формы там, не в Blender.
--
-- Порядок:
--   1. Studio → Avatar/Home → Import 3D, по очереди все семь файлов из папки «Модели/Жуки»:
--      mini_beetle.glb, hmuryi_bron.glb, moth.glb, worker_beetle.glb, builder_beetle.glb,
--      pelican_beetle.glb, standard_beetle.glb. Настройки импорта — по умолчанию. Импорт ляжет в Workspace;
--      переименовывать не нужно — корень каждого .glb назван видом (worker_beetle и т.д.),
--      по нему скрипт и находит импорт.
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
--   * цвета деталей — из таблицы COLORS (сняты с материалов .glb: Import 3D их теряет).
-- Цвета остаются авторскими: атрибутов Color* у новых шаблонов нет, игра их не перекрашивает.
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
		head = { "^head_casque$", "^brow_ridge$", "^bite_muscle$" },
	},
	{
		source = "moth",
		template = "MothTemplate",
		length = 3.38,
		head = { "^labial_palp" },
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
	-- Стандарт — последним: Root всех шаблонов берётся с прежнего NormalBeetleTemplate,
	-- а его самого prepare заменяет новым (старый удаляется).
	{ source = "standard_beetle", template = "NormalBeetleTemplate", length = 3.1 },
}

-- Цвета из .glb (baseColorFactor, линейные): Import 3D их не переносит, детали приходят серыми.
-- Таблицу печатает tools/beetles/colors_lua.py — после правки жуков в species.py вставить её сюда.
-- Группа — один цвет: { r, g, b, имена деталей..., alpha = непрозрачность, если не 1 }.
-- Имя ищется целиком, затем без цифр в конце, без «_L/_R», затем по началу имени (cheek_L → cheek).
local COLORS = {
	NormalBeetleTemplate = {
		{ 0.075, 0.032, 0.012, "BeetleBodyInner", "ThoraxCore", "ROOT", "HeadBase", "AntSeg", "AntNode" },
		{ 0.16, 0.07, 0.025, "BeetlePlate" },
		{ 0.66, 0.57, 0.39, "elytra_spot" },
		{ 0.035, 0.016, 0.008, "Femur", "KneeJoint", "Tibia", "AnkleJoint", "Tarsus" },
		{ 0.01, 0.01, 0.012, "EyeLeft", "EyeRight" },
		{ 0.022, 0.01, 0.005, "MandibleJoint", "MandibleBase", "MandibleTip", "Tooth" },
	},
	WorkerBeetleTemplate = {
		{ 0.11, 0.05, 0.015, "BeetleBodyInner", "BeetleSternite", "ThoraxCore", "ROOT", "HeadBase", "AntSeg", "AntNode" },
		{ 0.2, 0.1, 0.03, "BeetlePlate" },
		{ 0.04, 0.02, 0.008, "Femur", "KneeJoint", "Tibia", "AnkleJoint", "Tarsus" },
		{ 0.01, 0.01, 0.012, "EyeLeft", "EyeRight" },
		{ 0.02, 0.01, 0.004, "MandibleJoint", "MandibleBase", "MandibleTip", "Tooth" },
	},
	MiniBeetleTemplate = {
		{ 0.055, 0.02, 0.008, "BeetleBodyInner", "BeetleSternite", "ThoraxCore", "ROOT", "HeadBase", "MandibleJoint", "MandibleBase", "MandibleTip", "AntSeg", "AntNode" },
		{ 0.34, 0.085, 0.016, "BeetlePlate" },
		{ 0.025, 0.01, 0.006, "elytra_spot" },
		{ 0.035, 0.014, 0.006, "Femur", "KneeJoint", "Tibia", "AnkleJoint", "Tarsus" },
		{ 0.01, 0.01, 0.012, "EyeLeft", "EyeRight" },
	},
	BuilderBeetleTemplate = {
		{ 0.195, 0.068, 0.019, "BeetleBodyInner", "BeetlePlate", "ThoraxCore", "ROOT", "HeadBase", "cheek" },
		{ 0.687, 0.546, 0.332, "belly_fill" },
		{ 0.254, 0.144, 0.065, "belly_seam" },
		{ 0.045, 0.018, 0.007, "Femur", "KneeJoint", "Tibia", "AnkleJoint", "Tarsus" },
		{ 0.01, 0.01, 0.012, "EyeLeft", "EyeRight" },
		{ 0.068, 0.023, 0.007, "shovel_plate", "MandibleJoint", "MandibleBase", "MandibleTip", "AntSeg", "AntNode" },
	},
	ArmoredBeetleTemplate = {
		{ 0.03, 0.018, 0.01, "BeetleBodyInner", "BeetleSternite", "ThoraxCore", "ROOT", "HeadBase", "bite_muscle", "AntSeg", "AntNode" },
		{ 0.107, 0.133, 0.162, "Armor_BeetlePlate", "Armor_pronotum", "head_casque" },
		{ 0.2, 0.23, 0.26, "Armor_edge" },
		{ 0.028, 0.02, 0.014, "Femur", "KneeJoint", "Tibia", "AnkleJoint", "Tarsus" },
		{ 0.042, 0.051, 0.065, "brow_ridge", "MandibleJoint", "MandibleBase", "MandibleTip", "Tooth" },
	},
	PelicanBeetleTemplate = {
		{ 0.056, 0.021, 0.01, "BeetleBodyInner", "BeetlePlate", "ThoraxCore", "neck", "ROOT", "HeadBase", "AntSeg", "AntNode" },
		{ 0.13, 0.06, 0.03, "abdomen_fold" },
		{ 0.61, 0.479, 0.296, "wing_membrane", alpha = 0.55 },
		{ 0.048, 0.019, 0.008, "wing_vein" },
		{ 0.013, 0.006, 0.003, "neck_ruff" },
		{ 0.03, 0.014, 0.007, "Femur", "KneeJoint", "Tibia", "AnkleJoint", "Tarsus" },
		{ 0.687, 0.651, 0.539, "EyeLeft", "EyeRight" },
		{ 0.023, 0.01, 0.005, "MandibleJoint", "MandibleBase", "MandibleTip", "beak_tooth" },
	},
	MothTemplate = {
		{ 0.509, 0.456, 0.371, "abdomen", "ThoraxCore", "thorax_plate", "ROOT", "HeadBase", "labial_palp", "AntSeg", "AntNode" },
		{ 0.2, 0.16, 0.11, "abdomen_band" },
		{ 0.03, 0.036, 0.028, "neck_collar", "wing_costa" },
		{ 0.06, 0.05, 0.04, "Femur", "KneeJoint", "Tibia", "AnkleJoint", "Tarsus" },
		{ 0.01, 0.01, 0.012, "EyeLeft", "EyeRight" },
		{ 0.62, 0.55, 0.42, "forewing", "hindwing", alpha = 0.7 },
		{ 0.16, 0.12, 0.08, "wing_vein_spot" },
	},
}
-- Детали, у которых цвет в вершинах меша: Color не трогать (сейчас таких нет).
local VERTEX_COLORED = {}

local function srgb(x)
	x = math.clamp(x, 0, 1)
	return x <= 0.0031308 and x * 12.92 or 1.055 * x ^ (1 / 2.4) - 0.055
end

local function paint(template)
	local byName = {}
	for _, group in COLORS[template.Name] or {} do
		for i = 4, #group do
			byName[group[i]] = group
		end
	end
	local function lookup(name)
		local found = byName[name] or byName[(name:gsub("%d+$", ""))]
			or byName[(name:gsub("_?[%-%d]+$", ""):gsub("_[LR]$", ""))]
		if found then
			return found
		end
		for key, group in byName do
			if name:sub(1, #key) == key then
				return group
			end
		end
		return nil
	end

	local keep = VERTEX_COLORED[template.Name] or {}
	local missing = {}
	for _, d in template:GetDescendants() do
		if d:IsA("BasePart") and d.Name ~= "Root" and d.Transparency < 1 then
			local group = lookup(d.Name)
			if group then
				if not keep[d.Name] and not (d:IsA("MeshPart") and d.TextureID ~= "") then
					d.Color = Color3.new(srgb(group[1]), srgb(group[2]), srgb(group[3]))
				end
				d.Material = Enum.Material.SmoothPlastic
				d.Transparency = 1 - (group.alpha or 1)
			elseif not keep[d.Name] and d.Name ~= "AbdomenCore" and d.Name ~= "CoxaJoint" then
				table.insert(missing, d.Name)
			end
		end
	end
	-- Брюшко и тазики — тем же хитином, что грудь (в .glb у них свой узел без материала).
	local thorax = template:FindFirstChild("ThoraxCore", true)
	if thorax then
		for _, d in template:GetDescendants() do
			if d:IsA("BasePart") and (d.Name == "AbdomenCore" or d.Name == "CoxaJoint")
				and d.Transparency < 1 and not keep[d.Name] then
				d.Color = thorax.Color
				d.Material = Enum.Material.SmoothPlastic
			end
		end
	end
	return missing
end

local LEGS = {
	"leg_front_left", "leg_front_right",
	"leg_mid_left", "leg_mid_right",
	"leg_rear_left", "leg_rear_right",
}
local LEG_PARTS = { "Femur", "KneeJoint", "Tibia", "AnkleJoint", "Tarsus1", "Tarsus2" }
-- Studio дописывает цифру ко второму узлу с тем же именем: hindwing2, wing_costa2.
local WING_PARTS = { "^forewing%d*$", "^hindwing%d*$", "^wing_costa%d*$", "^wing_membrane%d*$", "^wing_vein" }
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

-- Импорт ищется по имени вида на любой глубине (корень .glb назван видом, Import 3D может
-- обернуть его в AuxScene) — переименовывать руками ничего не нужно.
local function findImport(source)
	for _, container in { workspace, ServerStorage, ReplicatedStorage } do
		for _, d in container:GetDescendants() do
			if d:IsA("Model") and baseName(d.Name):lower() == source then
				return d
			end
		end
	end
	return nil
end

-- Удаляет импорт и опустевшие обёртки над ним (AuxScene и т.п.).
local function removeImport(source)
	local parent = source.Parent
	source:Destroy()
	while parent and parent:IsA("Model") and #parent:GetChildren() == 0 do
		local up = parent.Parent
		parent:Destroy()
		parent = up
	end
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

	-- Import 3D называет деталь по мешу (колено — AntNode1002, голень — Tarsus1006), а имя узла
	-- .glb отдаёт модели-обёртке (KneeJoint006, Femur006_Node). Детали — имя узла.
	for _, d in import:GetDescendants() do
		local p = d.Parent
		if d:IsA("BasePart") and p:IsA("Model") and #p:GetChildren() == 1 then
			d.Name = (p.Name:gsub("_Node$", ""))
		end
	end

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
	local unpainted = paint(template)

	local old = ReplicatedStorage:FindFirstChild(spec.template)
	if old then
		old:Destroy()
	end
	template.Parent = ReplicatedStorage
	import:Destroy()
	removeImport(source)

	local _, size = template:GetBoundingBox()
	local note = #unpainted > 0 and ("; без цвета: " .. table.concat(unpainted, ", ")) or ""
	return true, ("%d деталей, %.1f × %.1f × %.1f стад (в игре × scale из Enemies.luau)%s")
		:format(#parts, size.X, size.Y, size.Z, note)
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
