-- Модель дрона-носильщика Биореактора: квадрокоптер с подвесным грузовым контейнером.
-- Подключена в EconomyModels.Carrier; летает ею Carriers по тому же пути, по которому раньше ездил ровер.
--
-- Root анкорнут, остальное приварено к нему (как у FPV-дрона, DroneRig). Что должно двигаться само,
-- висит на Motor6D: винты — «RotorJoint» (крутятся всё время), контейнер — «BinHinge» (качается на
-- подвесе и опрокидывается, когда груз сдан). Это ведёт клиент (BioreactorVisuals), меняя C0 у себя.
--
-- Договор EconomyModels: пивот — центр корпуса, Carriers ставит его на высоту пола + Economy.carrierLift.
-- Перед — -Z (LookVector). Деталь Cargo — груз в контейнере и прямой ребёнок модели: Carriers
-- показывает её, только когда дрон везёт тушу.
--
-- Геометрия записана в студах полноразмерного дрона (пол — y = 0) и при сборке ужимается в scale раз.
-- Размах винтов после ужатия около 1.4 студа: Carriers ищет путь по занятости клеток без запаса на
-- ширину тела, поэтому дрон не шире ровера. Низ контейнера висит над полом на HOVER·scale студа.
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
local HOVER = 1.6 -- низ контейнера над полом
local POD_W, POD_D = 1.4, 1.5 -- контейнер в плане
local POD_TOP = HOVER + 1.3 -- верх контейнера: там ось шарнира
local HULL_BOTTOM = POD_TOP + 0.3 -- низ корпуса; между ним и осью — ярмо
local HULL_H = 0.8
local HULL_TOP = HULL_BOTTOM + HULL_H
local HULL_CENTER = HULL_BOTTOM + HULL_H / 2
local ARM_Y = 3.75 -- высота моторов над полом
local ARM = 1.1 -- моторы стоят на этом расстоянии от оси по X и по Z
local ROTOR_R = 0.6 -- радиус винта
local HUB_Y = ARM_Y + 0.27 -- ступица винта — над мотором
local BLADE = 2 * ROTOR_R - 0.1

-- Ось цилиндра в Roblox — локальный X, поэтому «стоймя» и «вперёд» приходится доворачивать.
local UP_AXIS = CFrame.Angles(0, 0, math.rad(90))
local FORWARD_AXIS = CFrame.Angles(0, math.rad(90), 0)

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

	-- ===== КОРПУС =====
	body("Hull", Vector3.new(1.6, HULL_H, 1.8), Vector3.new(0, HULL_CENTER, 0), dark)
	body("Skirt", Vector3.new(1.5, 0.08, 1.7), Vector3.new(0, HULL_BOTTOM - 0.04, 0), mid)
	body("Deck", Vector3.new(1.5, 0.08, 1.7), Vector3.new(0, HULL_TOP + 0.04, 0), mid)
	-- Щели вентиляции на крыше: гладкий почти чёрный пластик.
	for _, z in { -0.5, 0, 0.5 } do
		body("Vent", Vector3.new(0.9, 0.02, 0.1), Vector3.new(0, HULL_TOP + 0.09, z), black, plastic)
	end
	-- Рёбра жёсткости на бортах: тот же ритм мелких деталей, что у остальных моделей.
	for _, side in { 1, -1 } do
		for _, z in { -0.5, 0.5 } do
			body("Rib", Vector3.new(0.08, 0.5, 0.12), Vector3.new(side * 0.84, HULL_CENTER, z), dark)
		end
	end
	-- Сенсорный купол на крыше и камера в носу (перед — -Z) со светящимся объективом.
	body("Sensor", Vector3.new(0.5, 0.5, 0.5), Vector3.new(0, HULL_TOP + 0.12, -0.2), GLASS, Enum.Material.Glass,
		Enum.PartType.Ball)
	body("Cam", Vector3.new(0.3, 0.34, 0.34), Vector3.new(0, HULL_CENTER, -1.0), black, plastic, Enum.PartType.Cylinder,
		FORWARD_AXIS)
	body("Lens", Vector3.new(0.05, 0.22, 0.22), Vector3.new(0, HULL_CENTER, -1.18), GLOW, neon, Enum.PartType.Cylinder,
		FORWARD_AXIS)

	-- ===== РАМА, МОТОРЫ, ВИНТЫ =====
	-- Четыре луча «иксом»: у каждого мотор, над ним винт. Соседние винты крутятся в разные стороны.
	for index, corner in { { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } } do
		local sx, sz = corner[1], corner[2]
		local from = Vector3.new(sx * 0.5, ARM_Y, sz * 0.5) -- от корпуса
		local to = Vector3.new(sx * ARM, ARM_Y, sz * ARM) -- к мотору
		local arm = addPart(model, "Arm" .. index, Vector3.new(0.2, 0.14, (to - from).Magnitude + 0.1),
			CFrame.lookAt((from + to) / 2, to), mid, metal)
		weld(arm, root)

		body("Motor" .. index, Vector3.new(0.4, 0.42, 0.42), to, dark, metal, Enum.PartType.Cylinder, UP_AXIS)
		-- Подсветка под мотором: акцент, как у глаза и контейнера.
		body("Led" .. index, Vector3.new(0.06, 0.26, 0.26), Vector3.new(to.X, ARM_Y - 0.23, to.Z), GLOW, neon,
			Enum.PartType.Cylinder, UP_AXIS)

		-- Ступица винта — на Motor6D «RotorJoint»: клиент крутит её вокруг вертикальной оси (X детали — вверх).
		local hubAt = Vector3.new(to.X, HUB_Y, to.Z)
		local hub = addPart(model, "Hub" .. index, Vector3.new(0.14, 0.18, 0.18), CFrame.new(hubAt) * UP_AXIS, light, metal,
			Enum.PartType.Cylinder)
		local rotor = motor("RotorJoint", root, hub, CFrame.new(hubAt) * UP_AXIS)
		rotor:SetAttribute("Spin", (sx * sz > 0) and 1 or -1)

		-- Лопасти и диск-размытие приварены к ступице и крутятся вместе с ней.
		local function onHub(name, size, cframe, color, material, shape)
			local part = addPart(model, name, size, cframe, color, material, shape)
			weld(part, hub)
			return part
		end
		onHub("Blade", Vector3.new(0.12, 0.04, BLADE), CFrame.new(hubAt), mid, metal)
		onHub("Blade", Vector3.new(BLADE, 0.04, 0.12), CFrame.new(hubAt), mid, metal)
		local disc = onHub("Disc", Vector3.new(0.02, 2 * ROTOR_R, 2 * ROTOR_R), CFrame.new(hubAt) * UP_AXIS, dark, plastic,
			Enum.PartType.Cylinder)
		disc.Transparency = 0.7
	end

	-- ===== ЯРМО, ОСЬ, КОНТЕЙНЕР =====
	body("Axle", Vector3.new(POD_W + 0.3, 0.16, 0.16), Vector3.new(0, POD_TOP, 0), dark, metal, Enum.PartType.Cylinder)
	body("Yoke", Vector3.new(0.5, HULL_BOTTOM - POD_TOP, 0.5), Vector3.new(0, (HULL_BOTTOM + POD_TOP) / 2, 0), mid)

	-- Контейнер висит на шарнире по центру верхней плиты: BinHinge. Клиент качает его и опрокидывает.
	local base = addPart(model, "BinBase", Vector3.new(POD_W, 0.16, POD_D), CFrame.new(0, POD_TOP - 0.08, 0), mid, metal)
	local hinge = motor("BinHinge", root, base, CFrame.new(0, POD_TOP, 0))
	hinge:SetAttribute("TipAngle", 48)
	local function bin(name, size, position, color, material, shape)
		local part = addPart(model, name, size, CFrame.new(position), color, material or metal, shape)
		weld(part, base)
		return part
	end

	local wallTop = POD_TOP - 0.16
	local wallH = wallTop - HOVER
	local wallY = (wallTop + HOVER) / 2
	for _, side in { 1, -1 } do
		bin("PodSide", Vector3.new(0.1, wallH, POD_D), Vector3.new(side * (POD_W / 2 - 0.05), wallY, 0), mid)
	end
	for _, side in { 1, -1 } do
		bin("PodEnd", Vector3.new(POD_W, wallH, 0.1), Vector3.new(0, wallY, side * (POD_D / 2 - 0.05)), mid)
	end
	bin("PodGrate", Vector3.new(POD_W - 0.1, 0.06, POD_D - 0.1), Vector3.new(0, HOVER + 0.03, 0), black,
		Enum.Material.DiamondPlate)
	-- Груз: ком биомассы на решётке. Видно только с грузом (Carriers).
	local cargo = bin("Cargo", Vector3.new(POD_W - 0.3, 0.7, POD_D - 0.3), Vector3.new(0, HOVER + 0.41, 0), CARGO,
		Enum.Material.Slate)
	cargo.Transparency = 1
	-- Светящаяся полоса на переднем борту контейнера.
	bin("PodGlow", Vector3.new(POD_W - 0.5, 0.06, 0.04), Vector3.new(0, POD_TOP - 0.45, -(POD_D / 2) - 0.02), GLOW, neon)

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
