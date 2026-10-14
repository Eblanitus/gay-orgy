-- Модель дрона-носильщика Биореактора: колба с биомассой на низком шасси, ездит на четырёх колёсах.
-- Подключена в EconomyModels.Carrier; ездит по тому же пути, по которому раньше ездил ровер.
--
-- Root анкорнут, остальное приварено к нему. Что должно двигаться само, висит на Motor6D:
-- колёса — «WheelJoint» (крутятся по пройденному пути), крышка колбы — «BinHinge» (откидывается,
-- когда груз сдан). Это ведёт клиент (BioreactorVisuals), меняя C0 у себя.
--
-- Договор EconomyModels: пивот — центр корпуса на полу, Carriers ставит его на высоту пола + Economy.carrierLift.
-- Перед — -Z (LookVector). Деталь Cargo — биомасса на дне колбы и прямой ребёнок модели: Carriers
-- показывает её, только когда дрон везёт тушу.
--
-- Геометрия записана в студах полноразмерного дрона (пол — y = 0) и при сборке ужимается в scale раз.
-- Радиус колеса в атрибуте WheelJoint.Radius — уже после ужатия: по нему клиент считает поворот.
-- Габарит после ужатия около 1.5 × 2.3 × 2 студа; у прежнего ровера было 1.5 × 2.8 × 2.15.
local CarrierRig = {}

local dark = Color3.fromRGB(46, 49, 55)
local mid = Color3.fromRGB(70, 75, 83)
local light = Color3.fromRGB(98, 104, 114)
local black = Color3.fromRGB(24, 25, 28)
local GLOW = Color3.fromRGB(80, 235, 175) -- акцент Биореактора: дрон — его изделие
local GLASS = Color3.fromRGB(150, 200, 230)
local CARGO = Color3.fromRGB(96, 78, 58)
local metal, plastic, neon = Enum.Material.Metal, Enum.Material.SmoothPlastic, Enum.Material.Neon

-- Размеры полноразмерного дрона в студах (до ужатия).
local WHEEL_R = 1.0 -- радиус колеса: касается пола
local WHEEL_W = 0.6 -- ширина колеса
local WHEEL_X = 1.4 -- колёса по бортам шасси
local WHEEL_Z = 1.75 -- передние и задние колёса
local CHASSIS_BOTTOM = 0.5 -- низ шасси над полом
local DECK = 1.6 -- верх шасси: на нём стоит колба
local VIAL_R = 1.25 -- радиус колбы
local VIAL_H = 2.9 -- высота колбы над шасси
local LID_Y = DECK + VIAL_H -- верх колбы: на нём крышка
local LID_R = VIAL_R + 0.05 -- крышка чуть шире горла; её задний край — ось петли

-- Ось цилиндра в Roblox — локальный X, поэтому «стоймя» и «вперёд» приходится доворачивать.
local UP_AXIS = CFrame.Angles(0, 0, math.rad(90))
local FORWARD_AXIS = CFrame.Angles(0, math.rad(90), 0)
-- Колесо развёрнуто так, что его локальный X смотрит против X модели. Клиент крутит колесо на
-- положительный угол при езде вперёд (по LookVector), и при таком повороте колесо катится без проскальзывания.
local WHEEL_TURN = CFrame.Angles(0, math.rad(180), 0)

-- Ужатие и опускание текущей сборки (ставит buildTemplate).
local SCALE = 1
local LIFT = Vector3.zero

local function fit(cframe)
	return CFrame.new(cframe.Position * SCALE - LIFT) * cframe.Rotation
end

local function weld(part, root)
	local joint = Instance.new("WeldConstraint")
	joint.Part0 = root
	joint.Part1 = part
	joint.Parent = part
end

local function addPart(model, name, size, cframe, color, material, shape)
	local part = Instance.new("Part")
	part.Name = name
	if shape then
		part.Shape = shape
	end
	part.Size = size * SCALE
	part.CFrame = fit(cframe)
	part.Color = color
	part.Material = material
	part.Anchored = false
	part.Massless = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Parent = model
	return part
end

local function motor(name, root, part, at)
	at = fit(at)
	local joint = Instance.new("Motor6D")
	joint.Name = name
	joint.Part0 = root
	joint.Part1 = part
	joint.C0 = at
	joint.C1 = part.CFrame:Inverse() * at
	joint.Parent = root
	return joint
end

local templates = {}

local function buildTemplate(scale, lift)
	SCALE = scale
	LIFT = Vector3.new(0, lift, 0)
	local model = Instance.new("Model")
	model.Name = "Носильщик"

	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(0.2, 0.2, 0.2)
	root.CFrame = CFrame.new()
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.Transparency = 1
	root.Parent = model
	model.PrimaryPart = root

	-- Деталь, приваренная к Root. turn — поворот детали (для цилиндров по оси).
	local function body(name, size, position, color, material, shape, turn)
		local part = addPart(model, name, size, CFrame.new(position) * (turn or CFrame.identity), color, material or metal, shape)
		weld(part, root)
		return part
	end

	-- ===== ШАССИ =====
	body("Chassis", Vector3.new(2.2, DECK - CHASSIS_BOTTOM, 4.4), Vector3.new(0, (DECK + CHASSIS_BOTTOM) / 2, 0), dark)
	body("Deck", Vector3.new(2.0, 0.08, 4.0), Vector3.new(0, DECK + 0.04, 0), mid)
	-- Светящаяся полоса на лобовой панели: тот же акцент, что у колбы и датчика.
	body("FrontGlow", Vector3.new(1.6, 0.06, 0.04), Vector3.new(0, 1.2, -2.22), GLOW, neon)

	-- ===== КОЛЁСА =====
	-- Колесо — WheelJoint на Motor6D: клиент крутит его вокруг оси. Ступица и спицы приварены к колесу.
	for _, corner in { { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } } do
		local at = CFrame.new(corner[1] * WHEEL_X, WHEEL_R, corner[2] * WHEEL_Z) * WHEEL_TURN
		local wheel = addPart(model, "Wheel", Vector3.new(WHEEL_W, 2 * WHEEL_R, 2 * WHEEL_R), at, black, plastic, Enum.PartType.Cylinder)
		local wheelJoint = motor("WheelJoint", root, wheel, at)
		wheelJoint:SetAttribute("Radius", WHEEL_R * SCALE)
		local function onWheel(name, size, offset, color, material, shape)
			local part = addPart(model, name, size, at * offset, color, material, shape)
			weld(part, wheel)
			return part
		end
		onWheel("Hub", Vector3.new(0.7, 0.9, 0.9), CFrame.identity, light, metal, Enum.PartType.Cylinder)
		-- Крест спиц на обоих торцах: по нему видно, что колесо крутится.
		for _, side in { 1, -1 } do
			local face = CFrame.new(side * 0.32, 0, 0)
			onWheel("Spoke", Vector3.new(0.08, 1.7, 0.12), face, mid, metal)
			onWheel("Spoke", Vector3.new(0.08, 0.12, 1.7), face, mid, metal)
		end
	end

	-- ===== ДАТЧИК ВПЕРЕДИ =====
	-- Мачта с головой и зелёным объективом (перед — -Z).
	body("Mast", Vector3.new(0.5, 1.2, 0.5), Vector3.new(0, DECK + 0.6, -1.9), dark)
	body("Head", Vector3.new(0.9, 0.5, 0.6), Vector3.new(0, DECK + 1.45, -1.9), mid)
	body("Lens", Vector3.new(0.06, 0.34, 0.34), Vector3.new(0, DECK + 1.45, -2.23), GLOW, neon, Enum.PartType.Cylinder, FORWARD_AXIS)

	-- ===== КОЛБА =====
	-- Стекло с двумя ободами снизу и сверху. Груз — ком биомассы на дне: виден через стекло, когда дрон везёт тушу.
	local glass = body("Glass", Vector3.new(VIAL_H, 2 * VIAL_R, 2 * VIAL_R), Vector3.new(0, DECK + VIAL_H / 2, 0), GLASS,
		Enum.Material.Glass, Enum.PartType.Cylinder, UP_AXIS)
	glass.Transparency = 0.45
	for _, y in { DECK + 0.11, LID_Y - 0.11 } do
		body("Rim", Vector3.new(0.22, 2 * VIAL_R + 0.14, 2 * VIAL_R + 0.14), Vector3.new(0, y, 0), mid, metal, Enum.PartType.Cylinder, UP_AXIS)
	end
	-- Прячется, пока дрон пустой: Carriers ставит ему Transparency 0, когда дрон везёт груз.
	local cargo = body("Cargo", Vector3.new(2, 2, 2), Vector3.new(0, DECK + 1.22, 0), CARGO, Enum.Material.Slate, Enum.PartType.Ball)
	cargo.Transparency = 1

	-- ===== КРЫШКА =====
	-- Откидывается на заднем крае (BinHinge): клиент поднимает переднюю часть, когда груз сдан.
	local lid = addPart(model, "Lid", Vector3.new(0.2, 2 * LID_R, 2 * LID_R), CFrame.new(0, LID_Y + 0.1, 0) * UP_AXIS, mid, metal, Enum.PartType.Cylinder)
	local hinge = motor("BinHinge", root, lid, CFrame.new(0, LID_Y + 0.1, LID_R))
	hinge:SetAttribute("TipAngle", 70)
	local function onLid(name, size, cframe, color, material, shape)
		local part = addPart(model, name, size, cframe, color, material, shape)
		weld(part, lid)
		return part
	end
	-- Ось петли и ручка приварены к крышке и едут вместе с ней.
	onLid("Pin", Vector3.new(1.6, 0.22, 0.22), CFrame.new(0, LID_Y + 0.1, LID_R), dark, metal, Enum.PartType.Cylinder)
	onLid("Handle", Vector3.new(0.7, 0.12, 0.2), CFrame.new(0, LID_Y + 0.26, -0.8), dark, plastic)

	return model
end

-- Новый дрон: клон шаблона. scale — ужатие, lift — на сколько пивот (центр корпуса) выше пола.
-- Ставить — PivotTo.
function CarrierRig.Build(scale, lift)
	local id = ("%.3f:%.3f"):format(scale, lift)
	local template = templates[id]
	if not template then
		template = buildTemplate(scale, lift)
		templates[id] = template
	end
	return template:Clone()
end

return CarrierRig
