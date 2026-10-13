-- Модель наземного дрона-носильщика Биореактора (по вики: ровер с опрокидным кузовом).
-- Подключена в EconomyModels.Carrier; ездит им Carriers.
--
-- Root анкорнут, остальное приварено к нему (как у FPV-дрона, DroneRig). Кузов и колёса
-- висят на Motor6D, а не на сварке: опрокидывание кузова и вращение колёс ведёт клиент
-- (BioreactorVisuals), меняя C0 у себя.
--
-- Договор EconomyModels: пивот — центр корпуса на полу, Carriers ставит его на высоту пола
-- + Economy.carrierLift, поэтому вся модель опущена на lift. Перед — -Z (LookVector).
-- Деталь Cargo — груз в кузове: Carriers показывает её, только когда дрон везёт тушу.
--
-- Геометрия записана в студах полноразмерного ровера (дно кузова на высоте полотна
-- конвейера Завода, 4 студа) и при сборке ужимается в scale раз: Carriers ищет путь по
-- занятости клеток без запаса на ширину тела, и широкий ровер задевал бы постройки.
local CarrierRig = {}

local dark = Color3.fromRGB(46, 49, 55)
local mid = Color3.fromRGB(70, 75, 83)
local light = Color3.fromRGB(98, 104, 114)
local black = Color3.fromRGB(24, 25, 28)
local GLOW = Color3.fromRGB(80, 235, 175) -- акцент Биореактора: дрон — его изделие
local metal, plastic, neon = Enum.Material.Metal, Enum.Material.SmoothPlastic, Enum.Material.Neon

-- Габарит полноразмерного ровера в студах (до ужатия).
CarrierRig.LENGTH = 6.2
CarrierRig.WIDTH = 3.3
local WHEEL_R = 0.85
local WHEEL_Z = 2.1

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

local function buildTemplate(height, scale, lift)
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

	local function body(name, size, position, color, material, shape)
		local part = addPart(model, name, size, CFrame.new(position), color, material or metal, shape)
		weld(part, root)
		return part
	end

	-- ===== ШАССИ =====
	local L = CarrierRig.LENGTH
	local bodyTop = height - 0.55 -- под рамой кузова
	local bodyH = bodyTop - 0.55
	body("Hull", Vector3.new(2.6, bodyH, L - 0.2), Vector3.new(0, 0.55 + bodyH / 2, 0), dark)
	body("Skirt", Vector3.new(2.8, 0.35, L), Vector3.new(0, 0.75, 0), mid)
	for _, side in { 1, -1 } do
		body("SidePlate", Vector3.new(0.08, bodyH - 0.9, L - 1.6), Vector3.new(side * 1.33, 0.55 + bodyH / 2 + 0.2, 0), mid)
		body("SideGlow", Vector3.new(0.06, 0.1, L - 2.2), Vector3.new(side * 1.38, 1.25, 0), GLOW, neon)
		for _, z in { WHEEL_Z, -WHEEL_Z } do
			body("Fender", Vector3.new(0.6, 0.22, 2.1), Vector3.new(side * 1.5, WHEEL_R * 2 + 0.15, z), mid)
		end
	end
	-- Нос (перед — -Z): сенсорная планка и низкая световая полоса, как у референса AGV.
	body("Nose", Vector3.new(2.6, 0.9, 1.3), Vector3.new(0, bodyTop + 0.2, -(L / 2 - 0.65)), mid)
	body("SensorBar", Vector3.new(2.0, 0.18, 0.1), Vector3.new(0, bodyTop + 0.25, -L / 2 - 0.01), GLOW, neon)
	body("Bumper", Vector3.new(2.9, 0.35, 0.3), Vector3.new(0, 0.95, -L / 2 - 0.05), black, plastic)
	body("BumperGlow", Vector3.new(2.4, 0.08, 0.06), Vector3.new(0, 1.2, -L / 2 - 0.22), GLOW, neon)
	-- Задний бампер — им ровер упирается в лоток.
	body("RearBumper", Vector3.new(2.9, 0.35, 0.3), Vector3.new(0, 0.95, L / 2 + 0.05), black, plastic)

	-- ===== КОЛЁСА =====
	for _, side in { 1, -1 } do
		for _, z in { WHEEL_Z, -WHEEL_Z } do
			local at = CFrame.new(side * 1.45, WHEEL_R, z)
			local wheel = addPart(model, "Wheel", Vector3.new(0.5, WHEEL_R * 2, WHEEL_R * 2), at, black, plastic,
				Enum.PartType.Cylinder)
			local hub = addPart(model, "Hub", Vector3.new(0.52, 0.8, 0.8), at, light, metal, Enum.PartType.Cylinder)
			weld(hub, wheel)
			-- Спица на ступице: видно, что колесо крутится.
			local spoke = addPart(model, "Spoke", Vector3.new(0.54, 0.16, 1.2), at, mid, metal)
			weld(spoke, wheel)
			local joint = motor("WheelJoint", root, wheel, at)
			joint:SetAttribute("Radius", WHEEL_R)
		end
	end

	-- ===== КУЗОВ =====
	-- Шарнир — у заднего нижнего края: кузов поднимается передом, туша ссыпается назад.
	local BIN_FRONT, BIN_BACK = -1.7, L / 2 - 0.3
	local binLength = BIN_BACK - BIN_FRONT
	local binMid = (BIN_FRONT + BIN_BACK) / 2
	local base = addPart(model, "BinBase", Vector3.new(2.9, 0.3, binLength), CFrame.new(0, height - 0.35, binMid), mid, metal)
	local hinge = motor("BinHinge", root, base, CFrame.new(0, height - 0.5, BIN_BACK))
	hinge:SetAttribute("TipAngle", 48)
	local function bin(name, size, position, color, material)
		local part = addPart(model, name, size, CFrame.new(position), color, material or metal)
		weld(part, base)
		return part
	end
	bin("Bed", Vector3.new(2.7, 0.2, binLength - 0.2), Vector3.new(0, height - 0.1, binMid), black, Enum.Material.DiamondPlate)
	for _, side in { 1, -1 } do
		bin("BinSide", Vector3.new(0.15, 0.95, binLength), Vector3.new(side * 1.42, height + 0.35, binMid), light)
		bin("BinRib", Vector3.new(0.2, 0.15, binLength + 0.1), Vector3.new(side * 1.45, height + 0.8, binMid), dark)
	end
	bin("BinFront", Vector3.new(2.9, 1.25, 0.18), Vector3.new(0, height + 0.5, BIN_FRONT), light)
	bin("BinFrontGlow", Vector3.new(1.8, 0.1, 0.06), Vector3.new(0, height + 0.95, BIN_FRONT - 0.1), GLOW, neon)
	bin("BinLip", Vector3.new(2.9, 0.22, 0.14), Vector3.new(0, height + 0.02, BIN_BACK - 0.05), dark)
	-- Груз: ком биомассы на дне кузова. Видно только с грузом (Carriers).
	local cargo = bin("Cargo", Vector3.new(2.3, 0.9, binLength - 1.0), Vector3.new(0, height + 0.45, binMid),
		Color3.fromRGB(96, 78, 58), Enum.Material.Slate)
	cargo.Transparency = 1

	return model
end

-- Новый дрон: клон шаблона. height — высота дна кузова полноразмерного ровера, scale —
-- ужатие, lift — на сколько пивот (центр корпуса) выше пола. Ставить — PivotTo.
function CarrierRig.Build(height, scale, lift)
	local id = ("%.2f:%.3f:%.3f"):format(height, scale, lift)
	local template = templates[id]
	if not template then
		template = buildTemplate(height, scale, lift)
		templates[id] = template
	end
	return template:Clone()
end

return CarrierRig
