-- Модель лабораторного стола — авторский меш «Алхимический хер.glb».
--
-- Меш импортируется в Studio руками (Import 3D) и лежит в месте как есть: в Workspace, где его
-- оставил импорт, или уже в ServerStorage.CraftTableTemplate. Всё остальное делает этот модуль
-- при старте сервера, чтобы правка жила в src/, а не в месте:
--   * берёт из импорта модель CraftTable (в файле ещё 4 станции — их просто убирает с карты);
--   * красит детали по стилю вики (alchemy_td_art_style_v1): тёмный металл, голубое стекло,
--     без латуни. Материал — по таблице имён NAMES, она снята с .glb;
--   * ставит копию в стол локации вместо старых деталей: длина как у старого стола, центр
--     над Root, низ на полу.
-- Root и Top стола остаются: на них держатся LabTable, подсказка крафта и полоска прочности.
-- Top становится невидимым и встаёт на высоту столешницы.
--
-- Зовётся из Arena.bind (сервер) до того, как тот меряет стол: габарит стола (TableHalf)
-- должен считаться уже по новой модели. Нет импорта — стол остаётся старым.
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local TEMPLATE_NAME = "CraftTableTemplate"

-- Длина старого стола по X. От неё LabTable.REACH и запрет стройки вокруг стола.
local TABLE_LENGTH = 7

local STYLE = {
	Dark = { Material = Enum.Material.Metal, Color = Color3.fromRGB(45, 48, 55) },
	Mid = { Material = Enum.Material.Metal, Color = Color3.fromRGB(80, 86, 96) },
	Light = { Material = Enum.Material.Metal, Color = Color3.fromRGB(150, 156, 168) },
	Glass = { Material = Enum.Material.Glass, Color = Color3.fromRGB(190, 220, 255), Transparency = 0.7 },
	-- Акцент: холодный неон. Помечен атрибутом Accent, чтобы потом перекрашивать, как у турелей.
	Glow = { Material = Enum.Material.Neon, Color = Color3.fromRGB(140, 215, 255), Accent = true },
}

local NAMES = {
	Dark = {
		"CT_Steel_Dark.059",
		"CT_Steel_Dark.060",
		"CT_Steel_Dark.061",
		"CT_Steel_Dark.062",
		"CT_Steel_Dark.065",
		"CT_Steel_Dark.080",
		"CT_Steel_Dark.081",
		"CT_Steel_Dark.082",
		"CT_Steel_Dark.083",
		"CT_Steel_Dark.084",
		"CT_Steel_Dark.087",
		"CT_Steel_Dark.088",
		"CT_Steel_Dark.089",
		"CT_Steel_Dark.090",
		"CT_Steel_Dark.091",
		"CT_Steel_Dark.092",
		"CT_Steel_Dark.093",
		"CT_Steel_Dark.094",
		"CT_Steel_Dark.095",
		"CT_Steel_Dark.096",
		"CT_Steel_Dark.097",
		"CT_Steel_Dark.098",
		"CT_Steel_Dark.099",
		"CT_Steel_Dark.101",
		"CT_Steel_Dark.103",
		"CT_Steel_Dark.105",
		"CT_Steel_Dark.107",
		"Port_L_Bottom",
		"Port_L_Sleeve",
		"Port_R_Bottom",
		"Port_R_Sleeve",
		"Port_Show_Bottom",
		"Port_Show_Sleeve",
		"Press_Body",
		"Press_Die",
		"Press_FlangeB",
		"Press_FlangeT",
		"Press_GaugeFace",
		"Press_Niche",
		"Show_Base",
		"StorT_B00_Disc",
		"StorT_B01_Disc",
		"StorT_B10_Disc",
		"StorT_B11_Disc",
		"StorT_B20_Disc",
		"StorT_B21_Disc",
		"StorT_B30_Disc",
		"StorT_B31_Disc",
		"StorT_Base",
		"StorU_B00_Disc",
		"StorU_B01_Disc",
		"StorU_B10_Disc",
		"StorU_B11_Disc",
		"StorU_B20_Disc",
		"StorU_B21_Disc",
		"StorU_B30_Disc",
		"StorU_B31_Disc",
		"StorU_Base",
		"Track_L_Bed",
		"Track_R_Bed",
		"Track_S1_Bed",
		"Track_S2_Bed",
	},
	Mid = {
		"CT_Steel_Cylinder",
		"CT_Steel_Cylinder.001",
		"CT_Steel_Cylinder.002",
		"CT_Steel_Cylinder.003",
		"CT_Steel_Cylinder.004",
		"CT_Steel_Cylinder.005",
		"CT_Steel_Cylinder.006",
		"CT_Steel_Cylinder.007",
		"CT_Steel_Cylinder.008",
		"CT_Steel_Cylinder.009",
		"CT_Steel_Cylinder.010",
		"CT_Steel_Cylinder.011",
		"CT_Steel_Cylinder.015",
		"CT_Steel_Cylinder.016",
		"CT_Steel_Cylinder.017",
		"CT_Steel_Cylinder.018",
		"CT_Steel_Cylinder.032",
		"CT_Steel_Cylinder.033",
		"CT_Steel_Cylinder.034",
		"CT_Steel_Cylinder.035",
		"CT_Steel_Cylinder.036",
	},
	Light = {
		"CT_Brass_Fitting",
		"CT_Brass_Fitting.001",
		"CT_Brass_Fitting.002",
		"CT_Brass_Fitting.003",
		"CT_Brass_Fitting.004",
		"CT_Brass_Fitting.005",
		"CT_Brass_Fitting.006",
		"CT_Brass_Fitting.009",
		"CT_Brass_Fitting.010",
		"CT_Brass_Fitting.018",
		"CT_Brass_Fitting.019",
		"CT_Brass_Fitting.020",
		"CT_Brass_Fitting.021",
		"CT_Brass_Fitting.022",
		"CT_Brass_Fitting.023",
		"CT_Brass_Fitting.024",
		"CT_Brass_Fitting.025",
		"CT_Brass_Fitting.026",
		"CT_Brass_Fitting.027",
		"Mix_Outlet",
		"Port_L_Lip",
		"Port_L_Pin",
		"Port_L_Rim",
		"Port_R_Lip",
		"Port_R_Pin",
		"Port_R_Rim",
		"Port_Show_Lip",
		"Port_Show_Pin",
		"Port_Show_Rim",
		"Press_BandB",
		"Press_BandT",
		"Press_BoltB0",
		"Press_BoltB1",
		"Press_BoltB2",
		"Press_BoltB3",
		"Press_BoltB4",
		"Press_BoltB5",
		"Press_BoltT0",
		"Press_BoltT1",
		"Press_BoltT2",
		"Press_BoltT3",
		"Press_BoltT4",
		"Press_BoltT5",
		"Press_PortBolt0",
		"Press_PortBolt1",
		"Press_PortBolt2",
		"Press_PortBolt3",
		"Press_PortBolt4",
		"Press_PortBolt5",
		"Press_PortRim",
		"Press_ValveHub",
		"Press_ValveSeat",
		"Press_ValveStemY",
		"Press_ValveWheel",
		"StorT_B00_Pin",
		"StorT_B00_Rim",
		"StorT_B01_Pin",
		"StorT_B01_Rim",
		"StorT_B10_Pin",
		"StorT_B10_Rim",
		"StorT_B11_Pin",
		"StorT_B11_Rim",
		"StorT_B20_Pin",
		"StorT_B20_Rim",
		"StorT_B21_Pin",
		"StorT_B21_Rim",
		"StorT_B30_Pin",
		"StorT_B30_Rim",
		"StorT_B31_Pin",
		"StorT_B31_Rim",
		"StorU_B00_Pin",
		"StorU_B00_Rim",
		"StorU_B01_Pin",
		"StorU_B01_Rim",
		"StorU_B10_Pin",
		"StorU_B10_Rim",
		"StorU_B11_Cap",
		"StorU_B11_Pin",
		"StorU_B11_Rim",
		"StorU_B20_Pin",
		"StorU_B20_Rim",
		"StorU_B21_Cap",
		"StorU_B21_Pin",
		"StorU_B21_Rim",
		"StorU_B30_Pin",
		"StorU_B30_Rim",
		"StorU_B31_Cap",
		"StorU_B31_Pin",
		"StorU_B31_Rim",
		"Track_L_RailL",
		"Track_L_RailR",
		"Track_R_RailL",
		"Track_R_RailR",
		"Track_S1_RailL",
		"Track_S1_RailR",
		"Track_S2_RailL",
		"Track_S2_RailR",
	},
	Glass = {
		"StorU_B00_Body",
		"StorU_B11_Body",
		"StorU_B21_Body",
		"StorU_B31_Body",
	},
	Glow = {
		"CT_Glow_Core.001",
	},}

-- Те же детали по именам мешей: Import 3D называет детали то по узлу («CT_Steel_Dark.059»),
-- то по мешу («CanLid.001»). Имена мешей стола не повторяются в других станциях файла.
local MESH_NAMES = {
	Dark = {
		"CanLid.001",
		"CanLid.003",
		"CanLid.005",
		"CanLid.006",
		"CanLid.009",
		"CanLid.024",
		"CanLid.025",
		"CanLid.026",
		"CanLid.027",
		"CanLid.028",
		"CanLid.031",
		"CanLid.032",
		"CanLid.033",
		"CanLid.034",
		"CanLid.035",
		"CanLid.036",
		"CanLid.037",
		"CanLid.038",
		"CanLid.039",
		"CanLid.040",
		"CanLid.041",
		"CanLid.042",
		"CanLid.043",
		"CanLid.045",
		"CanLid.047",
		"CanLid.049",
		"CanLid.051",
		"Куб.005",
		"Куб.006",
		"Куб.022",
		"Куб.028",
		"Куб.031",
		"Куб.034",
		"Цилиндр",
		"Цилиндр.061",
		"Цилиндр.062",
		"Цилиндр.071",
		"Цилиндр.073",
		"Цилиндр.075",
		"Цилиндр.082",
		"Цилиндр.083",
		"Цилиндр.084",
		"Цилиндр.092",
		"Цилиндр.093",
		"Цилиндр.109",
		"Цилиндр.112",
		"Цилиндр.121",
		"Цилиндр.125",
		"Цилиндр.129",
		"Цилиндр.134",
		"Цилиндр.138",
		"Цилиндр.143",
		"Цилиндр.147",
		"Цилиндр.151",
		"Цилиндр.216",
		"Цилиндр.218",
		"Цилиндр.220",
		"Цилиндр.222",
		"Цилиндр.224",
		"Цилиндр.226",
		"Цилиндр.228",
		"Цилиндр.230",
	},
	Mid = {
		"CanisterEarth.043",
		"CanisterEarth.397",
		"CanisterEarth.398",
		"CanisterEarth.399",
		"CanisterEarth.400",
		"CanisterEarth.401",
		"CanisterEarth.402",
		"CanisterEarth.403",
		"CanisterEarth.404",
		"CanisterEarth.405",
		"CanisterEarth.406",
		"CanisterEarth.407",
		"CanisterEarth.411",
		"CanisterEarth.412",
		"CanisterEarth.413",
		"CanisterEarth.414",
		"CanisterEarth.428",
		"CanisterEarth.429",
		"CanisterEarth.430",
		"CanisterEarth.431",
		"CanisterEarth.432",
	},
	Light = {
		"Cable.031",
		"Cable.208",
		"Cable.209",
		"Cable.210",
		"Cable.211",
		"Cable.212",
		"Cable.213",
		"Cable.216",
		"Cable.217",
		"Cable.225",
		"Cable.226",
		"Cable.227",
		"Cable.228",
		"Cable.229",
		"Cable.230",
		"Cable.231",
		"Cable.232",
		"Cable.233",
		"Cable.234",
		"Куб.023",
		"Куб.024",
		"Куб.029",
		"Куб.030",
		"Куб.032",
		"Куб.033",
		"Куб.035",
		"Куб.036",
		"Тор.002",
		"Тор.003",
		"Тор.004",
		"Тор.005",
		"Тор.006",
		"Тор.007",
		"Тор.009",
		"Тор.010",
		"Тор.011",
		"Тор.012",
		"Тор.013",
		"Тор.014",
		"Тор.015",
		"Тор.016",
		"Тор.017",
		"Тор.018",
		"Тор.019",
		"Тор.020",
		"Тор.029",
		"Тор.030",
		"Тор.031",
		"Тор.032",
		"Тор.033",
		"Тор.034",
		"Тор.035",
		"Тор.036",
		"Цилиндр.009",
		"Цилиндр.052",
		"Цилиндр.053",
		"Цилиндр.054",
		"Цилиндр.055",
		"Цилиндр.060",
		"Цилиндр.063",
		"Цилиндр.068",
		"Цилиндр.069",
		"Цилиндр.070",
		"Цилиндр.076",
		"Цилиндр.077",
		"Цилиндр.079",
		"Цилиндр.080",
		"Цилиндр.085",
		"Цилиндр.087",
		"Цилиндр.090",
		"Цилиндр.091",
		"Цилиндр.096",
		"Цилиндр.106",
		"Цилиндр.107",
		"Цилиндр.108",
		"Цилиндр.110",
		"Цилиндр.111",
		"Цилиндр.117",
		"Цилиндр.122",
		"Цилиндр.126",
		"Цилиндр.131",
		"Цилиндр.135",
		"Цилиндр.137",
		"Цилиндр.139",
		"Цилиндр.144",
		"Цилиндр.146",
		"Цилиндр.148",
		"Цилиндр.152",
		"Цилиндр.155",
		"Цилиндр.217",
		"Цилиндр.219",
		"Цилиндр.221",
		"Цилиндр.223",
		"Цилиндр.225",
		"Цилиндр.227",
		"Цилиндр.229",
		"Цилиндр.231",
	},
	Glass = {
		"Цилиндр.123",
		"Цилиндр.136",
		"Цилиндр.145",
		"Цилиндр.153",
	},
	Glow = {
		"RetortLiquid.037",
	},
}

-- Импорт может переименовать детали («CanLid.001» -> «CanLid_001»), поэтому сравнение без знаков.
local function key(name)
	return (string.lower(name):gsub("[^%w]", ""))
end

local styleOf = {}
for _, names in { NAMES, MESH_NAMES } do
	for style, list in names do
		for _, name in list do
			styleOf[key(name)] = style
		end
	end
end

local CraftTableModel = {}

local template

local function paint(model)
	local missed = 0
	for _, d in model:GetDescendants() do
		if d:IsA("JointInstance") or d:IsA("WeldConstraint") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanTouch = false
			d.CanQuery = false
			local style = STYLE[styleOf[key(d.Name)] or ""]
			if style then
				for _, sa in d:GetChildren() do
					if sa:IsA("SurfaceAppearance") then
						sa:Destroy()
					end
				end
				d.Material = style.Material
				d.Color = style.Color
				d.Transparency = style.Transparency or 0
				d.CastShadow = not style.Accent
				if style.Accent then
					d:SetAttribute("Accent", true)
				end
			else
				missed += 1
			end
		end
	end
	if missed > 0 then
		warn(("[Стол] %d деталей модели не нашлись в таблице цветов — оставлены как в импорте"):format(missed))
	end
end

-- Шаблон один на сервер: ServerStorage.CraftTableTemplate, иначе — импорт, где бы он ни лежал
-- (Workspace, ServerStorage, даже внутри стола локации). Импорт узнаётся не по имени (Import 3D
-- называет модели по-разному), а по деталям из таблицы NAMES: берётся самая маленькая модель,
-- в которой есть все найденные детали стола, — это и есть стол без остальных станций.
local function findImport()
	local counts = {}
	local best = 0
	for _, root in { Workspace, ServerStorage } do
		for _, p in root:GetDescendants() do
			if p:IsA("BasePart") and styleOf[key(p.Name)] then
				local m = p.Parent
				while m and m ~= root do
					if m:IsA("Model") then
						counts[m] = (counts[m] or 0) + 1
						best = math.max(best, counts[m])
					end
					m = m.Parent
				end
			end
		end
	end
	if best < 20 then
		return nil
	end
	local source, sourceSize
	for m, n in counts do
		if n == best then
			local size = #m:GetDescendants()
			if not source or size < sourceSize then
				source, sourceSize = m, size
			end
		end
	end
	return source
end

local function getTemplate(craftTable)
	if template then
		return template
	end
	template = ServerStorage:FindFirstChild(TEMPLATE_NAME)
	if template then
		print("[Стол] модель — ServerStorage." .. TEMPLATE_NAME)
		return template
	end

	local source = findImport()
	if not source then
		warn("[Стол] импорт «Алхимический хер.glb» не найден ни в Workspace, ни в ServerStorage — стол старый")
		-- Подсказка, что лежит на сцене: по ней видно, как импорт назвал детали.
		for _, c in Workspace:GetChildren() do
			if c:IsA("Model") or c:IsA("Folder") then
				local names = {}
				for _, d in c:GetDescendants() do
					if d:IsA("BasePart") and #names < 8 then
						table.insert(names, d.Name)
					end
				end
				print(("[Стол]   Workspace.%s (%s, %d объектов): %s"):format(c.Name, c.ClassName, #c:GetDescendants(), table.concat(names, ", ")))
			end
		end
		return nil
	end
	print("[Стол] модель найдена: " .. source:GetFullName())

	-- Остальное из импорта (станции) — с карты в ServerStorage. Наверх идём только по моделям:
	-- папку Location и сам стол локации не трогаем.
	local imported = source
	while imported.Parent and imported.Parent:IsA("Model") and imported.Parent ~= craftTable do
		imported = imported.Parent
	end
	source.Parent = nil
	if imported ~= source and imported:IsDescendantOf(Workspace) then
		imported.Name = "Import_AlchemyStations"
		imported.Parent = ServerStorage
	end

	source.Name = TEMPLATE_NAME
	paint(source)
	source.Parent = ServerStorage
	template = source
	return template
end

function CraftTableModel.Apply(craftTable)
	if craftTable:GetAttribute("AuthorModel") then
		return
	end
	local tpl = getTemplate(craftTable)
	local root = craftTable:FindFirstChild("Root")
	local top = craftTable:FindFirstChild("Top")
	if not (tpl and root and top) then
		if tpl then
			warn("[Стол] у CraftTable нет Root или Top — модель не поставлена")
		end
		return
	end

	-- Пол — низ старых деталей стола (ножки). Старые детали после этого не нужны.
	local floorY = math.huge
	for _, c in craftTable:GetChildren() do
		if c ~= root and c ~= top and not c:IsA("BaseScript") then
			for _, p in { c, table.unpack(c:GetDescendants()) } do
				if p:IsA("BasePart") then
					floorY = math.min(floorY, p.Position.Y - p.Size.Y / 2)
				end
			end
			c:Destroy()
		end
	end
	if floorY == math.huge then
		floorY = root.Position.Y - 2.6
	end

	local build = tpl:Clone()
	build.Name = "Build"
	build.Parent = craftTable

	local _, size = build:GetBoundingBox()
	build:ScaleTo(build:GetScale() * TABLE_LENGTH / math.max(size.X, size.Z))
	if size.Z > size.X then
		build:PivotTo(build:GetPivot() * CFrame.Angles(0, math.rad(90), 0))
	end
	local cf, s = build:GetBoundingBox()
	local rootPos = root.Position
	build:PivotTo(build:GetPivot() + Vector3.new(rootPos.X - cf.X, floorY - (cf.Y - s.Y / 2), rootPos.Z - cf.Z))

	-- Top — невидимая столешница: на ней подсказка крафта и полоска прочности.
	local worktop = build:FindFirstChild("Worktop", true)
	local topY = if worktop and worktop:IsA("BasePart")
		then worktop.Position.Y + worktop.Size.Y / 2
		else floorY + s.Y / 2
	top.Size = Vector3.new(s.X, 0.4, s.Z)
	top.CFrame = CFrame.new(rootPos.X, topY - 0.2, rootPos.Z)
	top.Transparency = 1
	top:SetAttribute("BaseTransparency", 1)

	craftTable:SetAttribute("AuthorModel", true)
	print(("[Стол] новый стол поставлен, размер %s"):format(tostring(s)))
end

return CraftTableModel
