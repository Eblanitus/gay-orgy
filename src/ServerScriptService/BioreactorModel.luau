-- Модель Биореактора (Завод Материи, по вики). Собрана из примитивов в студах игры, без растяжки.
--
-- Тракт по вики прямой и низкий, без лифтов и эстакад:
--   приёмный конвейер (полотно на высоте кузова ровера, Towers.Bioreactor.beltHeight)
--   -> прижимной валец над лентой -> портал двухвального шредера (два встречных вала с клыками)
--   -> под шредером шнек с форсунками кислоты -> шламовый насос -> напорная труба наверх
--   -> экстракционная колонна: кварцевый цилиндр в решётчатом пилоне, внутри изумрудная материя.
--
-- Платформа — приплюснутый восьмиугольник (footprintShape kind = "octagon"): у каждой постройки
-- своя фигура. Конвейер заходит с +Z (там дроны сдают туши), колонна — в заднем правом углу.
--
-- Цвета — та же сталь, что у остальных турелей; белого нет. Элемента реактор не принимает,
-- поэтому акцент не нейтральный белый, а свой — цвет материи (GLOW), его же светится колонна.
--
-- Что двигается, ведёт клиент (BioreactorVisuals) по атрибутам деталей; пока реактор
-- перерабатывает груз (атрибут Processing > 0, ставит Bioreactor), всё крутится быстрее:
--   Slide (studs/сек), SlideWrap (шаг возврата), SlideDir (направление в осях модели),
--     SlidePhase (сколько деталь уже проехала от начала хода) —
--     планки ленты и пузыри в колонне;
--   Roll (град/сек), RollAxis (точка оси в осях модели), RollDir (ось) — валец, валы шредера, шнек.
-- Точки BeltPath1..3 — путь груза по ленте в зев шредера (невидимые).
return function(deps)
	local addPart = deps.addPart
	local addRoot = deps.addRoot

	local dark = Color3.fromRGB(46, 49, 55) -- корпус
	local mid = Color3.fromRGB(70, 75, 83) -- рамы и стойки
	local light = Color3.fromRGB(98, 104, 114) -- кромки и плиты
	local black = Color3.fromRGB(24, 25, 28) -- щели, полотно, решётки
	local steel = Color3.fromRGB(138, 144, 153) -- валы и клыки шредера
	local GLOW = Color3.fromRGB(80, 235, 175) -- акцент реактора: цвет материи
	local MATTER = Color3.fromRGB(60, 225, 110) -- жидкая материя в колонне
	local metal, plastic, neon = Enum.Material.Metal, Enum.Material.SmoothPlastic, Enum.Material.Neon
	local plate = Enum.Material.DiamondPlate
	local cylinder = Enum.PartType.Cylinder

	local FLOOR = -1.6 -- низ модели: пол арены (пивот постройки на TOWER_Y над ним)

	-- Цилиндр Roblox лежит осью вдоль своей X. Эти повороты ставят его ось по нужной оси мира.
	local ALONG_X = CFrame.new()
	local ALONG_Y = CFrame.Angles(0, 0, math.rad(90))
	local ALONG_Z = CFrame.Angles(0, math.rad(90), 0)

	local function box(model, name, size, position, color, material)
		return addPart(model, name, size, CFrame.new(position), color, material or metal)
	end

	local function cyl(model, name, length, radius, position, along, color, material)
		return addPart(model, name, Vector3.new(length, radius * 2, radius * 2),
			CFrame.new(position) * along, color, material or metal, cylinder)
	end

	-- Стержень между двумя точками (раскосы пилона, наклонные цилиндры гидравлики).
	local function rod(model, name, a, b, thick, color, material)
		local length = (b - a).Magnitude
		return addPart(model, name, Vector3.new(thick, thick, length),
			CFrame.lookAt((a + b) / 2, b), color, material or metal)
	end

	-- Треугольник на полу: прямой угол в corner, катеты длиной c вдоль sx·X и sz·Z.
	-- Грабли WedgePart (см. TowerInteraction.rebuildHexWedges): тапер вдоль локальной Z,
	-- нож у -Z, основание по -Y — поэтому базис задаётся вручную.
	local function cornerWedge(model, name, corner, sx, sz, c, y, thick, color, material)
		local u = Vector3.new(0, 0, sz) -- локальная Y: катет, у которого полная грань
		local w = Vector3.new(-sx, 0, 0) -- локальная Z: от катета к ножу
		local x = u:Cross(w)
		local center = Vector3.new(corner.X + sx * c / 2, y, corner.Z + sz * c / 2)
		local wedge = Instance.new("WedgePart")
		wedge.Name = name
		wedge.Size = Vector3.new(thick, c, c)
		wedge.CFrame = CFrame.fromMatrix(center, x, u, w)
		wedge.Anchored = true
		wedge.CanCollide = false
		wedge.Color = color
		wedge.Material = material
		wedge.Parent = model
		return wedge
	end

	-- Восьмиугольник side со срезом chamfer на высоте y: средняя плита, две полосы и 4 угла
	-- без нахлёста.
	local function octagon(model, name, side, chamfer, y, thick, color, material)
		local half = side / 2
		local inner = side - 2 * chamfer
		local parts = {
			addPart(model, name, Vector3.new(side, thick, inner), CFrame.new(0, y, 0), color, material),
			addPart(model, name, Vector3.new(inner, thick, chamfer), CFrame.new(0, y, half - chamfer / 2), color, material),
			addPart(model, name, Vector3.new(inner, thick, chamfer), CFrame.new(0, y, -(half - chamfer / 2)), color, material),
		}
		for _, sx in { 1, -1 } do
			for _, sz in { 1, -1 } do
				local corner = Vector3.new(sx * (half - chamfer), 0, sz * (half - chamfer))
				table.insert(parts, cornerWedge(model, name, corner, sx, sz, chamfer, y, thick, color, material))
			end
		end
		return parts
	end

	-- Вершины восьмиугольника по кругу (для световой кромки).
	local function octagonPoints(side, chamfer)
		local h, k = side / 2, side / 2 - chamfer
		return {
			Vector3.new(k, 0, h), Vector3.new(h, 0, k), Vector3.new(h, 0, -k), Vector3.new(k, 0, -h),
			Vector3.new(-k, 0, -h), Vector3.new(-h, 0, -k), Vector3.new(-h, 0, k), Vector3.new(-k, 0, h),
		}
	end

	local function tagRoll(part, speed, axisPoint, axisDir)
		part:SetAttribute("Roll", speed)
		part:SetAttribute("RollAxis", axisPoint)
		part:SetAttribute("RollDir", axisDir)
		return part
	end

	-- phase — на сколько деталь уже уехала от начала хода (она стоит на своём месте, клиент
	-- ведёт её от rest - dir * phase): планки ленты и пузыри идут цепочкой, а не стопкой.
	local function tagSlide(part, speed, wrap, dir, phase)
		part:SetAttribute("SlidePhase", phase or 0)
		part:SetAttribute("Slide", speed)
		part:SetAttribute("SlideWrap", wrap)
		part:SetAttribute("SlideDir", dir)
		return part
	end

	return function(towerData)
		local model = Instance.new("Model")
		model.Name = towerData.name
		addRoot(model)

		local shape = towerData.footprintShape
		local SIDE, CHAMFER = shape.side, shape.chamfer
		local HALF = SIDE / 2

		-- ===== ПЛАТФОРМА =====
		octagon(model, "Platform", SIDE, CHAMFER, FLOOR + 0.175, 0.35, mid, metal)
		octagon(model, "Deck", SIDE - 1, CHAMFER - 0.4, FLOOR + 0.425, 0.15, dark, plate)
		local TOP = FLOOR + 0.5 -- верх настила
		-- Световая кромка по краю настила: восемь отрезков.
		local points = octagonPoints(SIDE - 1.6, CHAMFER - 0.65)
		for i, a in points do
			local b = points[i % #points + 1]
			local y = Vector3.new(0, TOP + 0.03, 0)
			rod(model, "EdgeGlow", a + y, b + y, 0.12, GLOW, neon)
		end

		-- ===== ПРИЁМНЫЙ КОНВЕЙЕР =====
		-- Строго горизонтальный, без уклонов (по вики: лапы ложатся плашмя и не клинят).
		local BX = -4.5 -- ось ленты
		local BT = FLOOR + towerData.beltHeight -- верх полотна = высота кузова ровера
		local BELT_IN = HALF - 0.4 -- начало ленты у края платформы
		local BELT_OUT = 1.0 -- лента уходит в зев шредера
		local beltLength = BELT_IN - BELT_OUT
		local beltMid = (BELT_IN + BELT_OUT) / 2
		local BELT_W = 3.6

		box(model, "Belt", Vector3.new(BELT_W, 0.3, beltLength), Vector3.new(BX, BT - 0.15, beltMid), black, plastic)
		for _, side in { 1, -1 } do
			box(model, "BeltBeam", Vector3.new(0.3, 0.55, beltLength + 0.4),
				Vector3.new(BX + side * (BELT_W / 2 + 0.15), BT - 0.3, beltMid), mid)
			-- Направляющие борта и световая полоса по их верху.
			box(model, "BeltRail", Vector3.new(0.15, 0.6, beltLength - 0.6),
				Vector3.new(BX + side * (BELT_W / 2 + 0.05), BT + 0.3, beltMid - 0.3), light)
			box(model, "RailGlow", Vector3.new(0.08, 0.08, beltLength - 1.2),
				Vector3.new(BX + side * (BELT_W / 2 + 0.05), BT + 0.64, beltMid - 0.3), GLOW, neon)
			-- Раструб приёмного лотка: борта расходятся к краю, куда ровер высыпает кузов.
			local flare = addPart(model, "TrayFlare", Vector3.new(0.15, 1.1, 1.8),
				CFrame.new(BX + side * (BELT_W / 2 + 0.45), BT + 0.55, BELT_IN - 0.7)
					* CFrame.Angles(0, math.rad(-side * 28), 0), light, metal)
			flare.Name = "TrayFlare"
		end
		-- Барабаны на концах ленты.
		for _, z in { BELT_IN, BELT_OUT } do
			cyl(model, "BeltDrum", BELT_W, 0.32, Vector3.new(BX, BT - 0.32, z), ALONG_X, mid)
		end
		-- Опоры рамы: снаружи корпуса шредера.
		for _, z in { BELT_IN - 0.6, BELT_IN - 3.6, BELT_IN - 6.6 } do
			for _, side in { 1, -1 } do
				local height = BT - 0.55 - TOP
				box(model, "BeltLeg", Vector3.new(0.35, height, 0.35),
					Vector3.new(BX + side * (BELT_W / 2 + 0.15), TOP + height / 2, z), dark)
			end
		end
		-- Пластинчатое полотно с упорными планками: планки едут к шредеру (клиент).
		local SLAT_STEP = beltLength / 8
		for i = 0, 7 do
			local slat = box(model, "BeltSlat", Vector3.new(BELT_W - 0.2, 0.12, 0.22),
				Vector3.new(BX, BT + 0.06, BELT_IN - 0.15 - i * SLAT_STEP), mid)
			tagSlide(slat, 2, SLAT_STEP * 8, Vector3.new(0, 0, -1), i * SLAT_STEP)
		end
		-- Путь туши: начало ленты, под вальцом, зев шредера (оси точек — ход ленты).
		local pathZ = { BELT_IN - 0.8, 4.2, BELT_OUT - 0.6 }
		for i, z in pathZ do
			local point = addPart(model, "BeltPath" .. i, Vector3.new(0.2, 0.2, 0.2),
				CFrame.new(BX, BT + (i == #pathZ and -0.4 or 0), z), black, plastic)
			point.Transparency = 1
			point.CanQuery = false
			point.CanTouch = false
		end

		-- ===== ПРИЖИМНОЙ ВАЛЕЦ =====
		-- Над лентой на входе в портал: радиальные кулаки заминают лапы и проталкивают тушу.
		local DRUM_Z, DRUM_Y, DRUM_R = 3.4, BT + 2.0, 0.75
		local drumAxis = Vector3.new(BX, DRUM_Y, DRUM_Z)
		tagRoll(cyl(model, "ForceDrum", BELT_W - 0.4, DRUM_R, drumAxis, ALONG_X, mid), -160, drumAxis, Vector3.xAxis)
		for i = 0, 5 do
			local angle = math.rad(60 * i)
			for _, offset in { -1, 0, 1 } do
				local at = drumAxis + Vector3.new(offset * 1.0, math.sin(angle) * (DRUM_R + 0.15), math.cos(angle) * (DRUM_R + 0.15))
				local cam = addPart(model, "DrumCam", Vector3.new(0.5, 0.3, 0.3),
					CFrame.new(at) * CFrame.Angles(angle, 0, 0), steel, metal)
				tagRoll(cam, -160, drumAxis, Vector3.xAxis)
			end
		end
		for _, side in { 1, -1 } do
			local x = BX + side * (BELT_W / 2 - 0.05)
			cyl(model, "DrumGlow", 0.08, DRUM_R + 0.05, Vector3.new(x - side * 0.15, DRUM_Y, DRUM_Z), ALONG_X, GLOW, neon)
			-- Щёки с осью вальца на раме и гидравлический прижим наклоном от рамы.
			box(model, "DrumCheek", Vector3.new(0.3, 2.6, 1.0), Vector3.new(x + side * 0.15, BT + 1.1, DRUM_Z), dark)
			rod(model, "DrumRam", Vector3.new(x + side * 0.15, BT, DRUM_Z + 2.4),
				Vector3.new(x + side * 0.15, DRUM_Y + 0.3, DRUM_Z + 0.4), 0.3, light)
			rod(model, "DrumRamRod", Vector3.new(x + side * 0.15, DRUM_Y - 0.3, DRUM_Z + 1.1),
				Vector3.new(x + side * 0.15, DRUM_Y + 0.4, DRUM_Z + 0.3), 0.16, steel)
		end

		-- ===== ПОРТАЛ ШРЕДЕРА =====
		local HX0, HX1 = -8.5, -0.5 -- корпус по X
		local HZ0, HZ1 = -6.5, 1.5 -- по Z (перед с зевом — +Z)
		local HTOP = TOP + 8.5
		local hx, hz = (HX0 + HX1) / 2, (HZ0 + HZ1) / 2
		local hw, hd, hh = HX1 - HX0, HZ1 - HZ0, HTOP - TOP
		box(model, "HousingBack", Vector3.new(hw, hh, 0.5), Vector3.new(hx, TOP + hh / 2, HZ0 + 0.25), dark)
		box(model, "HousingLeft", Vector3.new(0.5, hh, hd), Vector3.new(HX0 + 0.25, TOP + hh / 2, hz), dark)
		box(model, "HousingRight", Vector3.new(0.5, hh, hd), Vector3.new(HX1 - 0.25, TOP + hh / 2, hz), dark)
		box(model, "HousingRoof", Vector3.new(hw + 0.4, 0.6, hd + 0.4), Vector3.new(hx, HTOP - 0.3, hz), mid)
		-- Перед с зевом: столбы, перемычка и порог вокруг проёма.
		local MX0, MX1 = BX - 2.3, BX + 2.3
		local MY0, MY1 = BT - 0.7, BT + 3.6
		box(model, "MouthPillarL", Vector3.new(MX0 - HX0, hh, 0.6), Vector3.new((HX0 + MX0) / 2, TOP + hh / 2, HZ1 - 0.3), dark)
		box(model, "MouthPillarR", Vector3.new(HX1 - MX1, hh, 0.6), Vector3.new((HX1 + MX1) / 2, TOP + hh / 2, HZ1 - 0.3), dark)
		box(model, "MouthLintel", Vector3.new(MX1 - MX0, HTOP - MY1, 0.6), Vector3.new(BX, (HTOP + MY1) / 2, HZ1 - 0.3), dark)
		box(model, "MouthSill", Vector3.new(MX1 - MX0, MY0 - TOP, 0.6), Vector3.new(BX, (TOP + MY0) / 2, HZ1 - 0.3), dark)
		-- Обвод зева: светлая рамка и световая полоса над проёмом.
		box(model, "MouthFrameTop", Vector3.new(MX1 - MX0 + 0.6, 0.3, 0.2), Vector3.new(BX, MY1 + 0.15, HZ1 + 0.05), light)
		for _, x in { MX0 - 0.15, MX1 + 0.15 } do
			box(model, "MouthFrameSide", Vector3.new(0.3, MY1 - MY0, 0.2), Vector3.new(x, (MY0 + MY1) / 2, HZ1 + 0.05), light)
		end
		box(model, "MouthGlow", Vector3.new(2.4, 0.18, 0.1), Vector3.new(BX, MY1 + 0.9, HZ1 + 0.02), GLOW, neon)
		-- Тёмное нутро за зевом.
		box(model, "HousingVoid", Vector3.new(MX1 - MX0, MY1 - MY0, 0.2), Vector3.new(BX, (MY0 + MY1) / 2, HZ0 + 2.2), black, plastic)
		-- Швы панелей на боках.
		for _, x in { HX0 - 0.02, HX1 + 0.02 } do
			for _, y in { TOP + 2.8, TOP + 5.6 } do
				box(model, "PanelSeam", Vector3.new(0.06, 0.1, hd - 0.6), Vector3.new(x, y, hz), black, plastic)
			end
		end

		-- Два встречных вала с серповидными клыками, за зевом (видны в проём).
		local SHAFT_Y = BT + 0.4
		for i, z in { HZ1 - 1.4, HZ1 - 3.1 } do
			local axis = Vector3.new(BX, SHAFT_Y, z)
			local speed = i == 1 and 220 or -220 -- встречное вращение
			tagRoll(cyl(model, "ShredShaft", MX1 - MX0 - 0.2, 0.5, axis, ALONG_X, steel), speed, axis, Vector3.xAxis)
			for ring = -2, 2 do
				for k = 0, 3 do
					local angle = math.rad(90 * k + ring * 25 + (i == 1 and 0 or 45))
					local at = axis + Vector3.new(ring * 0.85, math.sin(angle) * 0.75, math.cos(angle) * 0.75)
					local tooth = addPart(model, "ShredTooth", Vector3.new(0.22, 0.25, 0.7),
						CFrame.new(at) * CFrame.Angles(angle - math.rad(90), 0, 0) * CFrame.Angles(math.rad(20), 0, 0),
						steel, metal)
					tagRoll(tooth, speed, axis, Vector3.xAxis)
				end
			end
		end

		-- Тяжёлый электропривод шредера на крыше: корпус, мотор, рёбра, вытяжки.
		box(model, "DriveBase", Vector3.new(4.2, 1.2, 3.2), Vector3.new(hx, HTOP + 0.6, hz - 0.8), mid)
		cyl(model, "DriveMotor", 3.4, 0.9, Vector3.new(hx, HTOP + 1.9, hz - 0.8), ALONG_X, dark)
		for k = -2, 2 do
			cyl(model, "DriveFin", 0.12, 1.05, Vector3.new(hx + k * 0.6, HTOP + 1.9, hz - 0.8), ALONG_X, light)
		end
		box(model, "DriveGlow", Vector3.new(2.2, 0.12, 0.08), Vector3.new(hx, HTOP + 0.8, hz + 0.82), GLOW, neon)
		for _, at in { Vector3.new(HX0 + 1.2, 0, HZ0 + 1.2), Vector3.new(HX0 + 2.6, 0, HZ0 + 1.0) } do
			cyl(model, "Vent", 1.2, 0.35, Vector3.new(at.X, HTOP + 0.6, at.Z), ALONG_Y, dark)
			cyl(model, "VentCap", 0.2, 0.45, Vector3.new(at.X, HTOP + 1.25, at.Z), ALONG_Y, mid)
		end

		-- ===== ШНЕК С КИСЛОТОЙ =====
		-- Под ножами шредера: фарш падает в шнек, форсунки льют растворитель. Выходит
		-- из правого бока корпуса к насосу.
		local AZ = hz -- ось шнека по Z
		local AX0, AX1 = HX0 + 0.5, 2.7
		local AY = TOP + 0.55
		local ax = (AX0 + AX1) / 2
		box(model, "TroughBottom", Vector3.new(AX1 - AX0, 0.2, 1.5), Vector3.new(ax, TOP + 0.1, AZ), mid)
		for _, side in { 1, -1 } do
			box(model, "TroughWall", Vector3.new(AX1 - AX0, 0.8, 0.15), Vector3.new(ax, TOP + 0.5, AZ + side * 0.8), mid)
		end
		local augerAxis = Vector3.new(ax, AY, AZ)
		tagRoll(cyl(model, "AugerShaft", AX1 - AX0 - 0.2, 0.16, augerAxis, ALONG_X, steel), 200, augerAxis, Vector3.xAxis)
		-- Витки — наклонные шайбы: вращаясь, качаются как винт.
		for x = HX1 + 0.1, AX1 - 0.3, 0.45 do
			local flight = addPart(model, "AugerFlight", Vector3.new(0.06, 1.2, 1.2),
				CFrame.new(x, AY, AZ) * CFrame.Angles(0, math.rad(18), 0), light, metal, cylinder)
			tagRoll(flight, 200, augerAxis, Vector3.xAxis)
		end
		-- Решётка над видимым куском шнека.
		for x = HX1 + 0.3, AX1 - 0.2, 0.5 do
			box(model, "TroughGrate", Vector3.new(0.08, 0.08, 1.7), Vector3.new(x, TOP + 0.95, AZ), black, plastic)
		end
		-- Форсунки кислоты: трубки сверху с каплей-индикатором.
		for _, x in { 0.6, 1.9 } do
			cyl(model, "AcidPipe", 1.6, 0.1, Vector3.new(x, TOP + 1.85, AZ - 0.55), ALONG_Y, dark)
			cyl(model, "AcidPipeTop", 1.0, 0.1, Vector3.new(x, TOP + 2.65, AZ - 1.05), ALONG_Z, dark)
			addPart(model, "AcidTip", Vector3.new(0.24, 0.24, 0.24), CFrame.new(x, TOP + 1.05, AZ - 0.55),
				MATTER, neon, Enum.PartType.Ball)
		end

		-- ===== ШЛАМОВЫЙ НАСОС =====
		local PX = 4.1
		local PY = TOP + 1.25
		cyl(model, "PumpFlange", 0.3, 0.75, Vector3.new(AX1 + 0.1, AY + 0.3, AZ), ALONG_X, light)
		cyl(model, "PumpInlet", 0.6, 0.4, Vector3.new(AX1 + 0.45, AY + 0.45, AZ), ALONG_X, dark)
		cyl(model, "PumpBody", 1.9, 1.1, Vector3.new(PX, PY, AZ), ALONG_X, dark)
		cyl(model, "PumpCap", 0.25, 0.85, Vector3.new(PX - 1.05, PY, AZ), ALONG_X, mid)
		cyl(model, "PumpGlow", 0.14, 1.13, Vector3.new(PX + 0.3, PY, AZ), ALONG_X, GLOW, neon)
		cyl(model, "PumpMotor", 1.4, 0.75, Vector3.new(PX + 1.7, PY - 0.2, AZ), ALONG_X, mid)
		for _, x in { PX - 0.5, PX + 0.6, PX + 1.8 } do
			box(model, "PumpFoot", Vector3.new(0.4, PY - 0.6 - TOP, 1.8), Vector3.new(x, TOP + (PY - 0.6 - TOP) / 2, AZ), black, plastic)
		end

		-- ===== ЭКСТРАКЦИОННАЯ КОЛОННА =====
		local CX, CZ = 5.6, -5.9
		local CR = 1.6 -- радиус кварцевого цилиндра
		local C0 = TOP + 0.9 -- низ стекла
		local CH = 9 -- высота стекла
		cyl(model, "ColumnBase", 0.7, 2.3, Vector3.new(CX, TOP + 0.35, CZ), ALONG_Y, mid)
		cyl(model, "ColumnBaseGlow", 0.1, 2.32, Vector3.new(CX, TOP + 0.55, CZ), ALONG_Y, GLOW, neon)
		local glass = cyl(model, "ColumnGlass", CH, CR, Vector3.new(CX, C0 + CH / 2, CZ), ALONG_Y,
			Color3.fromRGB(190, 215, 205), Enum.Material.Glass)
		glass.Transparency = 0.6
		local LIQ = CH - 1.6 -- высота столба материи
		local liquid = cyl(model, "Matter", LIQ, CR - 0.15, Vector3.new(CX, C0 + 0.1 + LIQ / 2, CZ), ALONG_Y, MATTER, neon)
		liquid.Transparency = 0.35
		liquid.CanQuery = false
		-- Пузыри: всплывают и возвращаются вниз (клиент).
		for i = 1, 7 do
			local angle = math.rad(i * 137)
			local r = 0.4 + (i % 3) * 0.35
			local bubble = addPart(model, "Bubble", Vector3.new(0.3, 0.3, 0.3),
				CFrame.new(CX + math.cos(angle) * r, C0 + 0.4 + (i - 1) * LIQ / 7, CZ + math.sin(angle) * r),
				Color3.fromRGB(190, 255, 215), neon, Enum.PartType.Ball)
			bubble.Transparency = 0.2
			bubble.CanQuery = false
			tagSlide(bubble, 1.2 + (i % 3) * 0.4, LIQ - 0.6, Vector3.yAxis, (i - 1) * LIQ / 7 % (LIQ - 0.6))
		end
		-- Стальной решётчатый пилон: четыре стойки и раскосы на каждой грани.
		local POST = CR + 0.35
		local PTOP = C0 + CH + 0.4
		local corners = {
			Vector3.new(POST, 0, POST), Vector3.new(POST, 0, -POST), Vector3.new(-POST, 0, -POST), Vector3.new(-POST, 0, POST),
		}
		for _, corner in corners do
			box(model, "PylonPost", Vector3.new(0.28, PTOP - TOP - 0.7, 0.28),
				Vector3.new(CX + corner.X, (TOP + 0.7 + PTOP) / 2, CZ + corner.Z), dark)
		end
		local LEVELS = 4
		local step = (PTOP - C0) / LEVELS
		for i, a in corners do
			local b = corners[i % 4 + 1]
			for level = 0, LEVELS - 1 do
				local y0, y1 = C0 + level * step, C0 + (level + 1) * step
				local from = Vector3.new(CX + a.X, level % 2 == 0 and y0 or y1, CZ + a.Z)
				local to = Vector3.new(CX + b.X, level % 2 == 0 and y1 or y0, CZ + b.Z)
				rod(model, "PylonBrace", from, to, 0.14, mid)
			end
			rod(model, "PylonRing", Vector3.new(CX + a.X, PTOP - 0.2, CZ + a.Z), Vector3.new(CX + b.X, PTOP - 0.2, CZ + b.Z), 0.2, mid)
		end
		-- Кольца-индикаторы на стекле и крышка.
		for _, y in { C0 + 0.15, C0 + CH - 0.15 } do
			cyl(model, "ColumnRing", 0.3, CR + 0.12, Vector3.new(CX, y, CZ), ALONG_Y, mid)
		end
		cyl(model, "ColumnRingGlow", 0.12, CR + 0.14, Vector3.new(CX, C0 + 0.4, CZ), ALONG_Y, GLOW, neon)
		cyl(model, "ColumnCap", 0.8, CR + 0.3, Vector3.new(CX, C0 + CH + 0.4, CZ), ALONG_Y, dark)
		cyl(model, "ColumnDome", 0.5, 0.9, Vector3.new(CX, C0 + CH + 1.05, CZ), ALONG_Y, mid)
		-- Нижний шиберный затвор (сброс шлама): коробка у основания и штурвал.
		box(model, "SlagGate", Vector3.new(1.0, 0.7, 0.6), Vector3.new(CX - 1.4, TOP + 0.5, CZ + 1.4), mid)
		cyl(model, "SlagWheel", 0.12, 0.35, Vector3.new(CX - 1.4, TOP + 1.0, CZ + 1.75), ALONG_Z, light)

		-- Напорная труба от насоса наверх в колонну и верхняя магистраль выдачи материи.
		local PIPE_R = 0.3
		local riseX, riseZ = PX + 0.6, AZ - 1.2
		local riseTop = C0 + CH + 0.4
		cyl(model, "PumpOutlet", 1.2, PIPE_R, Vector3.new(PX + 0.6, PY + 0.2, AZ - 0.6), ALONG_Z, dark)
		cyl(model, "PressurePipe", riseTop - PY, PIPE_R, Vector3.new(riseX, (PY + riseTop) / 2, riseZ), ALONG_Y, dark)
		for _, y in { PY + 1.5, PY + 4.5, riseTop - 1.2 } do
			cyl(model, "PipeGlow", 0.16, PIPE_R + 0.04, Vector3.new(riseX, y, riseZ), ALONG_Y, GLOW, neon)
		end
		rod(model, "PressureHead", Vector3.new(riseX, riseTop, riseZ), Vector3.new(CX, riseTop, CZ), PIPE_R * 2, dark)
		-- Выдача: от крышки вбок к краю настила и вниз, в сеть базы. Труба тёмная, светятся
		-- только кольца — белой и сплошь светящейся детали в моделях нет.
		local mainY = C0 + CH + 0.9
		local outX = CX + 3.4
		rod(model, "MatterMain", Vector3.new(CX, mainY, CZ), Vector3.new(outX, mainY, CZ), 0.4, dark)
		cyl(model, "MatterDown", mainY - TOP, 0.2, Vector3.new(outX, (TOP + mainY) / 2, CZ), ALONG_Y, dark)
		for _, y in { TOP + 1.2, (TOP + mainY) / 2, mainY - 1 } do
			cyl(model, "MatterGlow", 0.14, 0.24, Vector3.new(outX, y, CZ), ALONG_Y, GLOW, neon)
		end
		box(model, "MatterFlange", Vector3.new(0.8, 0.3, 0.8), Vector3.new(outX, TOP + 0.15, CZ), mid)

		return model
	end
end
