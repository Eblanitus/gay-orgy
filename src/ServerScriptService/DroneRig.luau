-- Модель FPV-дрона Станции (задача #75).
--
-- Дрон — это и есть снаряд, а не украшение вокруг него: корпус-сфера ровно по хитбоксу —
-- тот самый шар, который летал до этой задачи (см. Projectile: «видимый шар и хитбокс —
-- один объект и разойтись не могут»). Лучи, ограждения винтов, камера и заряд навешаны
-- вокруг него и на попадание не влияют вовсе: задеть дрона «за винт» нельзя, хитбокс
-- по-прежнему ровно projectileRadius.
--
-- Оснастка ПРИВАРЕНА к корпусу (WeldConstraint), а не анкорнута по деталям. Сервер двигает
-- одну деталь — корпус, остальные три десятка едут за ним сами, и в сеть уходит один CFrame
-- вместо тридцати. Тот же довод, по которому вращение, наведение и створку люка ведёт клиент,
-- а не сервер (см. BuildingVisuals). Анкорнуть оснастку нельзя ровно поэтому: анкорнутая
-- деталь за сваркой не едет и осталась бы висеть в точке сборки.
--
-- Модель собирается ОДИН раз в шаблон, каждый пуск — его клон: три десятка Instance.new
-- со сваркой на каждый выстрел — это работа на ровном месте, а летит дрон около секунды.
-- Шаблон свой на каждый радиус хитбокса, потому что вся геометрия ниже задана в радиусах,
-- а не в студах: поменяется projectileRadius — дрон вырастет целиком, а не разъедется.
local DroneRig = {}

-- Раскраска — СТАНЦИОННАЯ, а не своя (правка после #75): дрон собран на том же заводе
-- и обязан читаться как его изделие. Числа замерены по ServerStorage.DroneStationTemplate
-- (гистограмма цветов его деталей), то есть это авторские материалы из .glb, а не подбор на глаз:
--   43,43,48   Metal          DS_Black_Worn — основной корпус станции (77 деталей из 143)
--   90,97,107  Metal          DS_Plate      — плиты и обшивка (27)
--   66,72,81   Metal          DS_Armour     — броня корпусов (5)
--   13,14,17   SmoothPlastic  DS_Void       — ниши и швы (10)
--
-- Цвет элемента на корпус не идёт вовсе (корпус есть корпус, см. задачу #74): им горят
-- только объектив камеры и заряд под брюхом, плюс хвост и подсветка — см. TINTED.
local HULL_COLOR = Color3.fromRGB(43, 43, 48)
local PLATE_COLOR = Color3.fromRGB(90, 97, 107)
local ARMOUR_COLOR = Color3.fromRGB(66, 72, 81)
local DARK_COLOR = Color3.fromRGB(13, 14, 17)
-- Материалы тоже станционные: корпус и плиты — Metal, ниши — SmoothPlastic. До этой правки
-- всё было SmoothPlastic ради того, чтобы металл не отражал небо и не синил; сейчас это
-- наоборот нужно — станция синит точно так же, и разные материалы читались бы как разные цвета.
local HULL_MATERIAL = Enum.Material.Metal
local VOID_MATERIAL = Enum.Material.SmoothPlastic

-- Что красится в цвет залитого элемента. Список имён, а не отдельная папка: папка внутри
-- модели ничего бы не дала — сварка про иерархию не знает, а искать по имени и так дёшево.
local TINTED = { "Lens", "WarheadGlow" }

-- Вся геометрия — в радиусах хитбокса. Числа не из ТЗ: это обводка референса, а не баланс,
-- поэтому они здесь, а не в таблице Towers.
local SHAPE = {
	-- Пояс по экватору корпуса: на референсе у сферы виден стык двух половин.
	seam = { thick = 0.16, span = 2.04 },
	-- Камера в носу: тёмная оправа и светящийся объектив — тот самый «глаз» с картинки.
	camera = { depth = 0.34, dish = 0.88, lens = 0.46, forward = 0.90, lift = 0.04 },
	-- Микрозаряд под брюхом (по вики — «небольшая сфера с откидными стабилизаторами
	-- и микрозарядом»): шайба и светящийся торец под ней.
	warhead = { height = 0.46, width = 0.82, drop = 0.86, glow = 0.12 },
	-- Четыре луча «иксом», нос проходит между передними. Наклон вниз — тот же, что
	-- у референса: винты стоят чуть ниже экватора корпуса.
	arm = { yaw = 46, tilt = 5, length = 1.45, width = 0.22, height = 0.16, root = 0.78 },
	-- Ограждение винта: не кольцо целиком, а дуга, открытая внутрь, к корпусу — ровно как
	-- на референсе. Собирается из отрезков: тора среди примитивов Roblox нет.
	duct = { radius = 0.80, span = 195, segments = 6, height = 0.46, thick = 0.11 },
	-- Винт нарисован размытым диском, а не лопастями: он не крутится (приваренная деталь
	-- вращаться не может), и на скорости работающего винта диск читается ровно так же.
	rotor = { diameter = 1.42, thick = 0.10, transparency = 0.62 },
}

-- Своя ось у цилиндра — локальный X, поэтому «стоймя» и «вперёд» приходится доворачивать.
-- Заводить их константами, а не писать по месту: их тут дюжина.
local UP_AXIS = CFrame.Angles(0, 0, math.rad(90))
local FORWARD_AXIS = CFrame.Angles(0, math.rad(90), 0)

-- Готовые шаблоны по радиусу хитбокса. Ключ целый: радиус приходит числом с плавающей
-- точкой, и сравнивать его как ключ таблицы напрямую — просить о промахе на 1e-9.
local templates = {}

-- Деталь оснастки: не анкорнута, ничего не ловит и ничего не весит — она только картинка.
-- CanQuery = false по той же причине, что и у самого снаряда: иначе дрон ловил бы луч
-- подсветки клетки при постройке.
local function addPart(model, name, size, cframe, color, material, shape)
	local part = Instance.new("Part")
	part.Name = name
	if shape then
		part.Shape = shape
	end
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material
	part.Anchored = false
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Massless = true
	part.Parent = model

	local joint = Instance.new("WeldConstraint")
	joint.Part0 = model.PrimaryPart
	joint.Part1 = part
	joint.Parent = part

	return part
end

local function buildTemplate(radius)
	local r = radius
	local model = Instance.new("Model")
	model.Name = "Drone"

	-- Корпус — он же хитбокс, он же то, что двигает сервер. Единственная анкорнутая деталь
	-- модели: она корень сборки, всё остальное приварено к ней.
	local hull = Instance.new("Part")
	hull.Name = "Projectile"
	hull.Shape = Enum.PartType.Ball
	hull.Size = Vector3.new(r * 2, r * 2, r * 2)
	hull.CFrame = CFrame.identity
	hull.Anchored = true
	hull.CanCollide = false
	hull.CanTouch = false
	hull.CanQuery = false
	hull.Color = HULL_COLOR
	hull.Material = HULL_MATERIAL
	hull.Parent = model
	model.PrimaryPart = hull

	addPart(model, "Seam", Vector3.new(SHAPE.seam.thick * r, SHAPE.seam.span * r, SHAPE.seam.span * r),
		UP_AXIS, DARK_COLOR, VOID_MATERIAL, Enum.PartType.Cylinder)

	local camera = SHAPE.camera
	addPart(model, "CameraDish", Vector3.new(camera.depth * r, camera.dish * r, camera.dish * r),
		CFrame.new(0, camera.lift * r, -camera.forward * r) * FORWARD_AXIS,
		DARK_COLOR, VOID_MATERIAL, Enum.PartType.Cylinder)
	addPart(model, "Lens", Vector3.new(camera.depth * 0.6 * r, camera.lens * r, camera.lens * r),
		CFrame.new(0, camera.lift * r, -(camera.forward + camera.depth * 0.4) * r) * FORWARD_AXIS,
		Color3.new(1, 1, 1), Enum.Material.Neon, Enum.PartType.Cylinder)

	local warhead = SHAPE.warhead
	addPart(model, "Warhead", Vector3.new(warhead.height * r, warhead.width * r, warhead.width * r),
		CFrame.new(0, -warhead.drop * r, -0.1 * r) * UP_AXIS,
		ARMOUR_COLOR, HULL_MATERIAL, Enum.PartType.Cylinder)
	addPart(model, "WarheadGlow", Vector3.new(warhead.glow * r, warhead.width * 0.72 * r, warhead.width * 0.72 * r),
		CFrame.new(0, -(warhead.drop + warhead.height / 2) * r, -0.1 * r) * UP_AXIS,
		Color3.new(1, 1, 1), Enum.Material.Neon, Enum.PartType.Cylinder)

	local arm, duct, rotor = SHAPE.arm, SHAPE.duct, SHAPE.rotor
	local step = math.rad(duct.span) / duct.segments
	-- Отрезок дуги чуть длиннее хорды: со стыком впритык между сегментами видны щели.
	local chord = 2 * duct.radius * r * math.sin(step / 2) * 1.08

	for index, yaw in { arm.yaw, -arm.yaw, 180 - arm.yaw, arm.yaw - 180 } do
		-- Система координат луча: его локальный -Z смотрит наружу от корпуса, и вся
		-- геометрия винта считается уже в ней — иначе каждый луч пришлось бы разворачивать
		-- вручную, а четыре ручных разворота — четыре места, где можно ошибиться.
		local armFrame = CFrame.Angles(0, math.rad(yaw), 0) * CFrame.Angles(-math.rad(arm.tilt), 0, 0)
		local hub = armFrame * CFrame.new(0, 0, -(arm.root + arm.length) * r)

		addPart(model, "Arm" .. index,
			Vector3.new(arm.width * r, arm.height * r, arm.length * r),
			armFrame * CFrame.new(0, 0, -(arm.root + arm.length / 2) * r),
			PLATE_COLOR, HULL_MATERIAL)

		local disc = addPart(model, "Rotor" .. index,
			Vector3.new(rotor.thick * r, rotor.diameter * r, rotor.diameter * r),
			hub * UP_AXIS, DARK_COLOR, VOID_MATERIAL, Enum.PartType.Cylinder)
		disc.Transparency = rotor.transparency

		-- Дуга центрируется на «наружу» (угол 0 — это -Z луча) и расходится в обе стороны:
		-- закрытой оказывается внешняя сторона винта, открытой — та, что смотрит на корпус.
		for segment = 1, duct.segments do
			local angle = -math.rad(duct.span) / 2 + (segment - 0.5) * step
			addPart(model, ("Duct%d_%d"):format(index, segment),
				Vector3.new(duct.thick * r, duct.height * r, chord),
				hub * CFrame.Angles(0, angle, 0) * CFrame.new(0, 0, -duct.radius * r) * FORWARD_AXIS,
				ARMOUR_COLOR, HULL_MATERIAL)
		end
	end

	-- Хвост, подсветка и цвет — как у обычного снаряда (Projectile.dressShot), только тише:
	-- у снаряда светилось само тело, а у дрона тело — тёмный корпус, и заливать его
	-- неоном значило бы потерять и модель, и референс. Хвост цепляется за корму (+Z):
	-- нос дрона смотрит в -Z, как у любого CFrame.lookAt.
	local top = Instance.new("Attachment")
	top.Name = "TrailTop"
	top.Position = Vector3.new(0, r * 0.45, r * 0.62)
	top.Parent = hull

	local bottom = Instance.new("Attachment")
	bottom.Name = "TrailBottom"
	bottom.Position = Vector3.new(0, -r * 0.35, r * 0.62)
	bottom.Parent = hull

	local trail = Instance.new("Trail")
	trail.Attachment0 = top
	trail.Attachment1 = bottom
	trail.Lifetime = 0.35
	trail.MinLength = 0
	trail.LightEmission = 1
	trail.FaceCamera = true
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.4),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.WidthScale = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(1, 0),
	})
	trail.Parent = hull

	local light = Instance.new("PointLight")
	light.Range = 8
	light.Brightness = 1.6
	light.Shadows = false
	light.Parent = hull

	return model
end

-- Готовый дрон радиуса radius, покрашенный под залитый элемент. PrimaryPart модели —
-- корпус: он же хитбокс, его и двигает Projectile.
function DroneRig.Build(radius, color)
	local key = math.floor(radius * 1000 + 0.5)
	local template = templates[key]
	if not template then
		template = buildTemplate(radius)
		templates[key] = template
	end

	local model = template:Clone()
	for _, name in TINTED do
		local part = model:FindFirstChild(name, true)
		if part then
			part.Color = color
		end
	end

	local hull = model.PrimaryPart
	local trail = hull:FindFirstChildOfClass("Trail")
	if trail then
		trail.Color = ColorSequence.new(color)
	end
	local light = hull:FindFirstChildOfClass("PointLight")
	if light then
		light.Color = color
	end

	return model
end

return DroneRig
