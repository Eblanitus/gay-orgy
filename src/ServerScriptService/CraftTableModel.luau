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

-- Импорт может переименовать детали («CanLid.001» -> «CanLid_001»), поэтому сравнение без знаков.
local function key(name)
	return (string.lower(name):gsub("[^%w]", ""))
end

local styleOf = {}
for style, list in NAMES do
	for _, name in list do
		styleOf[key(name)] = style
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

-- Шаблон один на сервер: ищется в ServerStorage, иначе забирается из импорта в Workspace.
local function getTemplate()
	if template then
		return template
	end
	template = ServerStorage:FindFirstChild(TEMPLATE_NAME)
	if template then
		return template
	end

	local location = Workspace:FindFirstChild("Location")
	local source
	for _, d in Workspace:GetDescendants() do
		if d:IsA("Model") and d.Name == "CraftTable" and not (location and d:IsDescendantOf(location)) then
			source = d
			break
		end
	end
	if not source then
		return nil
	end

	-- Импорт целиком (со станциями) уходит с карты; стол из него становится шаблоном.
	local imported = source
	while imported.Parent ~= Workspace do
		imported = imported.Parent
	end
	source.Parent = nil
	if imported ~= source then
		imported:Destroy()
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
	local tpl = getTemplate()
	local root = craftTable:FindFirstChild("Root")
	local top = craftTable:FindFirstChild("Top")
	if not (tpl and root and top) then
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
end

return CraftTableModel
