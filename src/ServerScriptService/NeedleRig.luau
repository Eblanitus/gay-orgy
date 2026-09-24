-- Модель иглы Инжектора.
--
-- Форма собрана по референсам автора (четыре снимка стреловидного дротика-флешетты):
-- длинное пологое остриё на четверть корпуса, ровное полированное тело без перепадов
-- диаметра, поясок на стыке острия с телом, четыре стреловидных пера в самой корме
-- и короткое сопло, выступающее за перья. Прежняя игла была устроена наоборот —
-- тонкое жало впереди и толстая ампула в корме, — и читалась как шприц, а не как дротик.
--
-- Стеклянное окно с элементом убрано в корму и сделано ВРОВЕНЬ с телом: силуэт остаётся
-- ровным цилиндром, как на референсах, а цвет залитого элемента всё равно видно —
-- по нему игрок отличает свою иглу (тот же принцип, что у дрона: корпус есть корпус,
-- задача #74).
--
-- Как и у дрона (DroneRig), оснастка ПРИВАРЕНА к корню (WeldConstraint), а не анкорнута
-- по деталям: сервер двигает одну деталь, остальные едут за ней сами, и в сеть уходит
-- один CFrame вместо двадцати шести. Анкорнутая за сваркой не едет и осталась бы в точке сборки.
--
-- Шаблон собирается один раз на радиус хитбокса, каждый выстрел — его клон.
--
-- ХИТБОКС сюда не входит вовсе: попадание считает Projectile.findHit шаром радиуса
-- projectileRadius вокруг точки снаряда, а вся геометрия ниже — картинка вокруг неё.
-- Задеть иглу «за оперение» нельзя, ровно как дрона — за винт.
local NeedleRig = {}

-- Нос смотрит в -Z, как у любого CFrame.lookAt и как у дрона.
-- Своя ось у цилиндра-примитива — локальный X (см. «Грабли Roblox» в STATE.md),
-- поэтому всё, что должно лежать вдоль курса, доворачивается на 90° по Y.
local FORWARD_AXIS = CFrame.Angles(0, math.rad(90), 0)

-- Металл иглы — тот же светлый цвет, что у фурнитуры самой турели (Brass_Fitting
-- из авторского .glb, 237/239/243): иглу делали на этой же машине, и читаться она
-- должна как её изделие. Тёмными идут только пояски и сопло: на референсах перо
-- того же металла, что и тело, а тёмным там читается лишь утопленное — стыки
-- секций и жерло сопла.
local STEEL_COLOR = Color3.fromRGB(237, 239, 243)
local DARK_COLOR = Color3.fromRGB(80, 80, 89)

-- Металл на референсах полированный, а не матовый: без отражения тело иглы выходит
-- плоским пятном. Немного: на светлой арене большее выбеливает иглу целиком.
local POLISH = 0.12

-- Что красится в цвет залитого элемента.
local TINTED = { "Charge", "Ampoule" }

-- Вся геометрия — в радиусах хитбокса, а не в студах: поменяется projectileRadius —
-- игла вырастет целиком, а не разъедется.
--
-- Габарит взят с самой турели, а не выдуман: капсула в барабане (Capsule_Needle0) —
-- 4.9 в длину и 0.49 в поперечнике при радиусе хитбокса 0.7, то есть ровно 7.00 и 0.70
-- радиуса. Игла — то, что вылетает из этой капсулы, и мерить её больше не с чего.
-- Отношение длины к толщине выходит 10:1 против 13-14:1 на референсах: чтобы догнать
-- референс, иглу пришлось бы сделать длиннее собственного патрона.
--
-- Секции заданы отрезком вдоль курса (from..to, нос в минусе): так соседние куски
-- стыкуются числами, которые видно, а не суммой длин, которую надо держать в уме.
local SHAPE = {
	-- Остриё: длинный пологий конус на четверть всей длины — главная примета
	-- референса, по ней дротик и отличается от пули. Конуса среди примитивов Roblox
	-- нет, поэтому он набран из сужающихся цилиндров (тот же приём, что у сверла
	-- Бура, задача #53).
	point = { from = -3.50, to = -1.75, width = 0.70, segments = 14 },
	-- Поясок на стыке: он есть на всех четырёх референсах и служит границей,
	-- по которой глаз отделяет остриё от тела.
	collar = { from = -1.84, to = -1.66, width = 0.80 },
	body = { from = -1.80, to = 1.10, width = 0.70 },
	-- Окно с элементом: стекло вровень с телом, светящийся заряд внутри него.
	band1 = { from = 1.04, to = 1.16, width = 0.78 },
	ampoule = { from = 1.10, to = 2.10, width = 0.70 },
	charge = { from = 1.16, to = 2.04, width = 0.46 },
	band2 = { from = 2.04, to = 2.16, width = 0.78 },
	-- Кормовая секция: на ней сидят перья.
	tail = { from = 2.10, to = 3.16, width = 0.70 },
	-- Оперение: четыре пера, размах втрое больше радиуса тела — как на референсе.
	-- Без оперения цилиндр симметричен и не видно, где у него нос, а где корма.
	fin = { from = 2.20, to = 3.30, span = 1.05, thick = 0.08, count = 4 },
	-- Сопло: короткий стакан, выступающий за перья, — есть на трёх референсах.
	cap = { from = 3.12, to = 3.50, width = 0.50 },
}

local templates = {}

local function weldIn(model, part)
	part.Anchored = false
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false -- иначе игла ловила бы луч подсветки клетки при постройке
	part.Massless = true
	if part.Material == Enum.Material.Metal then
		part.Reflectance = POLISH
	end
	part.Parent = model

	local joint = Instance.new("WeldConstraint")
	joint.Part0 = model.PrimaryPart
	joint.Part1 = part
	joint.Parent = part

	return part
end

-- Цилиндр вдоль курса по отрезку sec.from..sec.to.
local function tube(model, name, sec, r, color, material)
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = Enum.PartType.Cylinder
	-- Минимальный размер детали в Roblox — 0.05 студа: у самого острия расчётная
	-- толщина уходит ниже, и движок всё равно подрезал бы её до 0.05. Подрезаем сами,
	-- чтобы в таблице стояла честная образующая конуса, а не подогнанное под движок число.
	local width = math.max(sec.width * r, 0.05)
	part.Size = Vector3.new((sec.to - sec.from) * r, width, width)
	part.CFrame = CFrame.new(0, 0, (sec.from + sec.to) * 0.5 * r) * FORWARD_AXIS
	part.Color = color
	part.Material = material
	return weldIn(model, part)
end

local function buildTemplate(radius)
	local r = radius
	local model = Instance.new("Model")
	model.Name = "Needle"

	-- Корень — невидимая точка в центре иглы: её двигает сервер, к ней приварено
	-- всё остальное. Видимого тела у неё нет нарочно: тело иглы — это её корпус,
	-- а не шар в середине.
	local core = Instance.new("Part")
	core.Name = "Projectile"
	core.Size = Vector3.new(0.1, 0.1, 0.1)
	core.CFrame = CFrame.identity
	core.Transparency = 1
	core.Anchored = true
	core.CanCollide = false
	core.CanTouch = false
	core.CanQuery = false
	core.Parent = model
	model.PrimaryPart = core

	-- Остриё: каждый следующий кусок толще предыдущего. Толщина берётся по СЕРЕДИНЕ
	-- своего отрезка — тогда лесенка идёт ровно по образующей конуса, а не срезает
	-- его углы и не торчит из него.
	local p = SHAPE.point
	local step = (p.to - p.from) / p.segments
	for i = 1, p.segments do
		tube(model, "Point" .. i, {
			from = p.from + (i - 1) * step,
			to = p.from + i * step,
			width = p.width * (i - 0.5) / p.segments,
		}, r, STEEL_COLOR, Enum.Material.Metal)
	end

	tube(model, "Collar", SHAPE.collar, r, DARK_COLOR, Enum.Material.Metal)
	tube(model, "Body", SHAPE.body, r, STEEL_COLOR, Enum.Material.Metal)
	tube(model, "Band1", SHAPE.band1, r, DARK_COLOR, Enum.Material.Metal)

	local ampoule = tube(model, "Ampoule", SHAPE.ampoule, r,
		Color3.new(1, 1, 1), Enum.Material.Glass)
	ampoule.Transparency = 0.5

	tube(model, "Charge", SHAPE.charge, r, Color3.new(1, 1, 1), Enum.Material.Neon)
	tube(model, "Band2", SHAPE.band2, r, DARK_COLOR, Enum.Material.Metal)
	tube(model, "Tail", SHAPE.tail, r, STEEL_COLOR, Enum.Material.Metal)
	tube(model, "Cap", SHAPE.cap, r, DARK_COLOR, Enum.Material.Metal)

	-- Оперение: перья стоят радиально, каждое вынесено от оси на полразмаха, так что
	-- корень пера прячется в теле и щели между ними нет.
	--
	-- Клин, а не пластина: у пера на референсе скошено ребро — узкое у тела
	-- и расходящееся к корме. Доворачивать клин не нужно: высокий торец у него
	-- смотрит в +Z, то есть уже в корму. Проверено лучом по самому перу: у носового
	-- края высота 0.02 студа, у кормового 0.73.
	local f = SHAPE.fin
	local finZ = (f.from + f.to) * 0.5 * r
	for i = 1, f.count do
		local angle = math.rad(360 / f.count * (i - 1))
		local fin = Instance.new("WedgePart")
		fin.Name = "Fin" .. i
		fin.Size = Vector3.new(f.thick * r, f.span * r, (f.to - f.from) * r)
		fin.CFrame = CFrame.Angles(0, 0, angle)
			* CFrame.new(0, f.span * 0.5 * r, finZ)
		fin.Color = STEEL_COLOR
		fin.Material = Enum.Material.Metal
		weldIn(model, fin)
	end

	-- Хвост цепляется за корму (+Z): нос иглы смотрит в -Z. Ширина — в толщину
	-- заряда, а не в диаметр хитбокса: широкая лента за тонкой иглой читалась бы
	-- как шар со следом — ровно то, от чего уходим.
	local tailZ = SHAPE.cap.to * r
	local half = SHAPE.charge.width * 0.5 * r

	local top = Instance.new("Attachment")
	top.Name = "TrailTop"
	top.Position = Vector3.new(0, half, tailZ)
	top.Parent = core

	local bottom = Instance.new("Attachment")
	bottom.Name = "TrailBottom"
	bottom.Position = Vector3.new(0, -half, tailZ)
	bottom.Parent = core

	local trail = Instance.new("Trail")
	trail.Attachment0 = top
	trail.Attachment1 = bottom
	trail.Lifetime = 0.22
	trail.MinLength = 0
	trail.LightEmission = 1
	trail.FaceCamera = true
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.25),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.WidthScale = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(1, 0),
	})
	trail.Parent = core

	local light = Instance.new("PointLight")
	light.Range = 7
	light.Brightness = 2
	light.Shadows = false
	light.Parent = core

	return model
end

-- Готовая игла под радиус хитбокса radius, покрашенная под залитый элемент.
-- PrimaryPart модели — невидимый корень в центре иглы: его и двигает Projectile.
function NeedleRig.Build(radius, color)
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

	local core = model.PrimaryPart
	local trail = core:FindFirstChildOfClass("Trail")
	if trail then
		trail.Color = ColorSequence.new(color)
	end
	local light = core:FindFirstChildOfClass("PointLight")
	if light then
		light.Color = color
	end

	return model
end

return NeedleRig
