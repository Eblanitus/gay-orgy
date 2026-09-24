-- Сборка моделей турелей, стены и горного барьера (процедурные и из мешей-шаблонов)
-- Вынесено из TowerBuilder.luau без изменений кода (задача #203): файл был слишком
-- велик, чтобы агент читал его целиком. deps — локальные основного файла, которые нужны
-- этому куску; возвращается то, что основной файл использует дальше.
return function(deps)
	local Elements = deps.Elements
	local SPHERE_HEIGHT = deps.SPHERE_HEIGHT
	local STAND_UP = deps.STAND_UP
	local BARREL_LENGTH = deps.BARREL_LENGTH
	local BARREL_REACH = deps.BARREL_REACH
	local colbaMeshTemplate = deps.colbaMeshTemplate
	local ACCENT_NEUTRAL_COLOR = deps.ACCENT_NEUTRAL_COLOR
	local Grid = deps.Grid
	local WALL_HEIGHT = deps.WALL_HEIGHT
	local WALL_ROWS = deps.WALL_ROWS
	local SANDBAG_COLOR = deps.SANDBAG_COLOR
	local MOUNTAIN_HEIGHT = deps.MOUNTAIN_HEIGHT
	local TOWER_Y = deps.TOWER_Y
	local BARRELS = deps.BARRELS
	local droneStationTemplate = deps.droneStationTemplate
	local injectorTemplate = deps.injectorTemplate

	local function bindElementTint(model, parts, emptyTransparency, filledTransparency, neutralColor)
		emptyTransparency = emptyTransparency or 1
		filledTransparency = filledTransparency or 0

		local function update()
			local elementKey = model:GetAttribute("Element")
			local elementData = elementKey and Elements[elementKey]
			for _, part in parts do
				if elementData then
					part.Transparency = filledTransparency
					part.Color = elementData.color
				else
					part.Transparency = emptyTransparency
					if neutralColor then
						part.Color = neutralColor
					end
				end
			end
		end

		model:GetAttributeChangedSignal("Element"):Connect(update)
		update()
	end

	-- Невидимый якорь в начале координат с нулевым поворотом — он же PrimaryPart любой постройки.
	-- Пивот модели — это CFrame её PrimaryPart, поэтому ставить PrimaryPart'ом повёрнутую деталь
	-- нельзя: PivotTo с обычным CFrame.new(x, y, z) выровнял бы её поворот в ноль и завалил всю
	-- башню набок (см. «Грабли Roblox» в STATE.md).
	local function addRoot(model)
		local root = Instance.new("Part")
		root.Name = "Root"
		root.Size = Vector3.new(0.2, 0.2, 0.2)
		root.Anchored = true
		root.CanCollide = false
		root.CanQuery = false
		root.Transparency = 1
		root.CFrame = CFrame.new(0, 0, 0)
		root.Parent = model
		model.PrimaryPart = root
		return root
	end

	-- Корпусная деталь турели одной строкой: пять моделей задачи #53 собраны из десятков
	-- таких деталей, и восемь строк Instance.new на каждую спрятали бы саму геометрию.
	-- CanCollide всегда false: жуки анкорнуты и ходят по сетке, физическое столкновение с моделью
	-- ни на что не влияет (занятость клетки держит Grid).
	local function addPart(model, name, size, cframe, color, material, shape)
		local part = Instance.new("Part")
		part.Name = name
		if shape then
			part.Shape = shape
		end
		part.Size = size
		part.Anchored = true
		part.CanCollide = false
		part.Color = color
		part.Material = material
		part.CFrame = cframe
		part.Parent = model
		return part
	end

	-- Прежняя процедурная Колба (Sci-Fi из примитивов) — не используется с задачи #63 (MODELS.Ballista
	-- ниже указывает на buildTowerModelMesh), но код нарочно не тронут и не удалён: вернуть старый
	-- визуал — значит вернуть одну строку в MODELS.
	--
	-- Собирает Колбу (Ballista) в Sci-Fi стиле: статичная база-платформа с неоновыми акцентами
	-- и подвижная башенная головка (стеклянная сфера со стволом). Головка собрана в папке TurretHead,
	-- которую клиент плавно поворачивает к ближайшему врагу (см. BuildingVisuals.addTracker).
	-- Серверный aimBarrel для Колбы не трогает CFrame ствола (geometry.clientTracked).
	local function buildTowerModel(towerData)
		local model = Instance.new("Model")
		model.Name = towerData.name

		addRoot(model)

		-- Палитра Sci-Fi
		local darkSteel = Color3.fromRGB(45, 48, 55)
		local midSteel = Color3.fromRGB(65, 70, 78)
		local lightSteel = Color3.fromRGB(95, 100, 110)
		local accent = Color3.fromRGB(80, 200, 255) -- голубой неон
		local glassColor = Color3.fromRGB(225, 240, 245)

		-- ===== СТАТИЧНАЯ БАЗА =====
		-- Широкая плита-основание: подошва на -1.6, там же, где ножки прежней Колбы (TOWER_Y).
		local basePlate = addPart(model, "BasePlate", Vector3.new(3.6, 0.4, 3.6),
			CFrame.new(0, -1.4, 0), darkSteel, Enum.Material.DiamondPlate)
		basePlate.CanCollide = true

		-- Неоновое кольцо-акцент на плите
		addPart(model, "BaseRing", Vector3.new(3.2, 0.1, 3.2),
			CFrame.new(0, -1.15, 0), accent, Enum.Material.Neon)

		-- Внутренняя площадка
		addPart(model, "BaseInner", Vector3.new(2.4, 0.3, 2.4),
			CFrame.new(0, -1.0, 0), midSteel, Enum.Material.Metal)

		-- Четыре угловых колонны
		for i, angle in { 45, 135, 225, 315 } do
			local rad = math.rad(angle)
			local dir = Vector3.new(math.cos(rad), 0, math.sin(rad))
			local pos = dir * 1.45 + Vector3.new(0, -0.7, 0)
			addPart(model, "Pillar" .. i, Vector3.new(0.35, 0.8, 0.35),
				CFrame.new(pos), lightSteel, Enum.Material.Metal)
		end

		-- Центральный посадочный воротник
		addPart(model, "Collar", Vector3.new(1.2, 0.5, 1.2),
			CFrame.new(0, -0.6, 0), midSteel, Enum.Material.Metal)
		addPart(model, "CollarRing", Vector3.new(1.3, 0.15, 1.3),
			CFrame.new(0, -0.4, 0), accent, Enum.Material.Neon)

		-- ===== ПОДВИЖНАЯ БАШЕННАЯ ГОЛОВКА =====
		local head = Instance.new("Folder")
		head.Name = "TurretHead"
		head.Parent = model

		-- Стеклянная сфера-колба
		local housing = addPart(head, "Housing", Vector3.new(2.8, 2.8, 2.8),
			CFrame.new(0, SPHERE_HEIGHT, 0), glassColor, Enum.Material.Glass, Enum.PartType.Ball)
		housing.Transparency = 0.5

		-- Жидкость внутри (индикатор элемента)
		local liquid = addPart(head, "Liquid", Vector3.new(2.1, 2.1, 2.1),
			CFrame.new(0, SPHERE_HEIGHT, 0), glassColor, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
		liquid.Transparency = 1
		liquid.CanQuery = false

		-- Металлическая шапка на сфере
		addPart(head, "TopCap", Vector3.new(1.0, 0.3, 1.0),
			CFrame.new(0, SPHERE_HEIGHT + 1.3, 0), lightSteel, Enum.Material.Metal)

		-- Сенсор-антенна (вертикальный неоновый цилиндр)
		addPart(head, "Sensor", Vector3.new(0.5, 0.15, 0.15),
			CFrame.new(0, SPHERE_HEIGHT + 1.7, 0) * STAND_UP, accent, Enum.Material.Neon, Enum.PartType.Cylinder)

		-- Кронштейн ствола
		addPart(head, "BarrelMount", Vector3.new(0.8, 0.8, 0.5),
			CFrame.new(0, SPHERE_HEIGHT, -1.0), midSteel, Enum.Material.Metal)

		-- Основной ствол: смотрит вперёд (-Z), цилиндр повёрнут на 90° по Y
		addPart(head, "Barrel", Vector3.new(BARREL_LENGTH, 0.45, 0.45),
			CFrame.new(0, SPHERE_HEIGHT, -BARREL_REACH) * CFrame.Angles(0, math.rad(90), 0),
			darkSteel, Enum.Material.Metal, Enum.PartType.Cylinder)

		-- Декоративные кольца на стволе
		for i, offset in { -0.4, 0.0, 0.4 } do
			addPart(head, "BarrelRing" .. i, Vector3.new(0.15, 0.6, 0.6),
				CFrame.new(0, SPHERE_HEIGHT, -BARREL_REACH + offset) * CFrame.Angles(0, math.rad(90), 0),
				lightSteel, Enum.Material.Metal, Enum.PartType.Cylinder)
		end

		-- Неоновое дуло
		addPart(head, "Muzzle", Vector3.new(0.2, 0.7, 0.7),
			CFrame.new(0, SPHERE_HEIGHT, -BARREL_REACH - BARREL_LENGTH / 2) * CFrame.Angles(0, math.rad(90), 0),
			accent, Enum.Material.Neon, Enum.PartType.Cylinder)

		bindElementTint(model, { liquid })

		return model
	end

	-- Новая Колба (задача #63): клон импортированного меша вместо процедурной сборки выше.
	-- Root у шаблона уже стоит в пивоте (ноги на -1.6, как у процедурной версии, см. правку
	-- пивота в Studio), поэтому дополнительный addRoot() не нужен и модель ставится в клетку
	-- точно так же через placeTower/PivotTo, как и любая другая башня.
	--
	-- Акцентные детали красятся в цвет залитого элемента через ту же bindElementTint, что и у
	-- процедурной версии — задача #65 распространила это на ВСЕ несерые (не-стальные/не-стеклянные)
	-- цвета меша, а не только на трубки и N-полоски:
	--   - трубки жидкости (LiquidTube{0,1,2}_CurveObj), N-полоски (NPlateL/R_Strip), индикаторы
	--     (DetailIndicator_{L,R}_{0,1}), вентиляция (Vent{0,1,2}_Node) и катушки (Coil{1..6}_Node) —
	--     все они в исходном меше неоновые/латунные (не серо-стальные), видны всегда — белые
	--     в пустой турели, в цвет элемента после заливки.
	--   - Liquid — жидкость внутри стеклянной Колбы (задача #65): в отличие от остальных акцентов
	--     красится, а не прячется транспарентностью, потому что видимость и подъём уровня даёт
	--     BuildingVisuals.trackStep через fillLevel (масштабирует Size.Y). Здесь только цвет,
	--     поэтому прозрачность у неё всегда 0. Сам меш у Liquid — уменьшенная копия стеклянного
	--     меша Колбы (задача #68, правлено один раз в самом ServerStorage.ColbaTurretTemplate), а не Part-блок:
	--     блок постоянной ширины торчал углами за стенки там, где Колба сужается к горлышку и к ножке —
	--     копия того же меша на 80% по XZ и 88% по Y повторяет ту же сужающуюся форму и никогда не
	--     вылезает за стенки на любой высоте.
	--   - FlaskCap (крышка) неподвижна (задача #66): раньше она ещё и ездила вверх-вниз вместе с
	--     fillLevel, но это только путало — крышка теперь просто часть корпуса, как и остальные
	--     неакцентные детали.
	--   - FlaskFiller убрана из шаблона совсем (задача #67): декоративная воронка на крышке не несла
	--     игровой информации и только загромождала силуэт. Стеклянный корпус Колбы
	--     (MeshPart «Колба») правится там же, в ServerStorage.ColbaTurretTemplate: прозрачность поднята,
	--     чтобы залитый Liquid было отчётливо видно сквозь стекло, а не только через щель
	--     в горлышке.
	-- В меше из Workspace.ColbaTower эти узлы — Model-обёртки на несколько уровней вложенности
	-- (TurretHead ищется глубоким поиском, а не прямым ребёнком модели), а не голые MeshPart
	-- прямо в TurretHead, как было в прежнем шаблоне — отсюда рекурсивный поиск и разбор
	-- обёртки на актуальный MeshPart внутри неё.
	local function buildTowerModelMesh(towerData)
		if not colbaMeshTemplate then
			warn("[TowerBuilder] ColbaTurretTemplate не найден в ServerStorage, откат на процедурную Колбу")
			return buildTowerModel(towerData)
		end

		local model = colbaMeshTemplate:Clone()
		model.Name = towerData.name

		-- Игрок не должен проходить сквозь турель — тот же принцип, что у базы Sci-Fi Колбы,
		-- блока Стены и станины Мортиры. Импортированный меш это не наследует сам: у всех ~70
		-- деталей клона CanCollide=false, как выставлено при импорте (см. addPart выше — там
		-- это оправдано тем, что жуки анкорнуты и ходят по сетке, а не физикой; игрок ходит
		-- физикой, и без этого свободно проходит через всю башню).
		local base = model:FindFirstChild("OctoBase", true)
		if base then
			base.CanCollide = true
		end

		local head = model:FindFirstChild("TurretHead", true)
		if head then
			local function findMeshPart(nodeName)
				local node = head:FindFirstChild(nodeName, true)
				return node and (node:IsA("BasePart") and node or node:FindFirstChildWhichIsA("MeshPart"))
			end

			local alwaysVisible = {}
			for _, nodeName in {
				"LiquidTube0_CurveObj", "LiquidTube1_CurveObj", "LiquidTube2_CurveObj",
				"NPlateL_Strip", "NPlateR_Strip",
				"DetailIndicator_L_0", "DetailIndicator_L_1", "DetailIndicator_R_0", "DetailIndicator_R_1",
				"Vent0_Node", "Vent1_Node", "Vent2_Node",
				"Coil1_Node", "Coil2_Node", "Coil3_Node", "Coil4_Node", "Coil5_Node", "Coil6_Node",
			} do
				local part = findMeshPart(nodeName)
				if part then
					table.insert(alwaysVisible, part)
				end
			end
			bindElementTint(model, alwaysVisible, 0, 0, ACCENT_NEUTRAL_COLOR)

			local liquid = findMeshPart("Liquid")
			if liquid then
				bindElementTint(model, { liquid }, 0, 0, ACCENT_NEUTRAL_COLOR)
			end
		end

		return model
	end

	-- Собирает стену — кладку мешков с песком почти во всю клетку. Силуэт по-прежнему
	-- простой и приземистый: игрок с высоты камеры обязан мгновенно отличать преграду
	-- от турели, не всматриваясь, — поэтому габарит, высота и след остались те же, что были
	-- у глухого блока. Меняется только то, из чего он сложен.
	--
	-- Отдельный Root с нулевым поворотом — по той же причине, что и у Колбы (см. «Грабли Roblox»
	-- в STATE.md): пивот модели — это CFrame её PrimaryPart.
	local function buildWallModel(towerData)
		local model = Instance.new("Model")
		model.Name = towerData.name

		-- Сторона идёт от размера ПОСТРОЙКИ, а не от шага сетки: клетка теперь в пять раз
		-- мельче стены, и по CellSize вышел бы кубик в 0.4 студа вместо блока.
		local side = Grid.BuildSize - 0.4 -- зазор, чтобы соседние стены читались как отдельные блоки

		local root = Instance.new("Part")
		root.Name = "Root"
		root.Size = Vector3.new(0.2, 0.2, 0.2)
		root.Anchored = true
		root.CanCollide = false
		root.CanQuery = false
		root.Transparency = 1
		root.CFrame = CFrame.new(0, 0, 0)
		root.Parent = model

		-- Низ кладки на -1.6 в локальных координатах — там же, где подошвы ножек Колбы,
		-- поэтому обе постройки ставятся одним и тем же TOWER_Y.
		--
		-- Столкновение — на одном невидимом сердечнике, а не на каждом мешке: игрок не должен
		-- проходить сквозь стену, но шестнадцати отдельных коллизий для этого не нужно. Сердечник
		-- же держит ровный след постройки: мешки лежат внахлёст и торчат за края, как и положено
		-- мешкам.
		local core = Instance.new("Part")
		core.Name = "Block"
		core.Size = Vector3.new(side, WALL_HEIGHT, side)
		core.Anchored = true
		core.CanCollide = true
		core.CanQuery = false -- лучи всегда попадают в мешки, а не в невидимый куб поверх них
		core.Transparency = 1
		core.CFrame = CFrame.new(0, 0, 0)
		core.Parent = model

		-- Кладка: четыре ряда по четыре мешка, каждый следующий ряд развёрнут поперёк
		-- предыдущего — так кладут настоящие мешки с песком, и так стена читается кладкой,
		-- а не одним кубом. Мешок — Sphere-меш с неравномерным Size (тот же приём, что у тела
		-- жука): скруглённый приплюснутый куль вместо кирпича.
		--
		-- Размер мешка чуть больше четверти следа: шары скруглены по углам, и без нахлёста
		-- между ними просвечивала бы дыра на месте невидимого сердечника.
		local rowHeight = WALL_HEIGHT / WALL_ROWS

		-- Мешок продолговатый, примерно 3:2, как настоящий: в ряду их шесть — два вдоль
		-- ряда и три поперёк. Квадратный мешок кладки не даёт вовсе: разверни его на 90° —
		-- разницы не видно, и стена читается стопкой блинов (так и вышло в первом прогоне).
		local bagLong = side / 2 + 0.2
		local bagWide = side / 3 + 0.15
		local bagTall = rowHeight + 0.22 -- ряды заходят друг на друга: между скруглёнными мешками иначе щели

		for row = 0, WALL_ROWS - 1 do
			-- Низ самого нижнего ряда — ровно где подошва сердечника.
			local y = -WALL_HEIGHT / 2 + rowHeight * (row + 0.5)
			local across = row % 2 == 1 -- ряды чередуются: вдоль — поперёк — вдоль
			-- Смещение на полмешка: шов следующего ряда не должен приходиться на шов предыдущего.
			local shift = (row % 2 == 0) and 0.3 or -0.3

			for long = 0, 1 do
			for wide = 0, 2 do
				local alongRow = (long == 0 and -1 or 1) * (side / 4) + shift
				local acrossRow = (wide - 1) * (side / 3)
				local dx = across and acrossRow or alongRow
				local dz = across and alongRow or acrossRow

				local bag = Instance.new("Part")
				bag.Name = ("Bag%d_%d%d"):format(row, long, wide)
				bag.Size = across and Vector3.new(bagWide, bagTall, bagLong)
					or Vector3.new(bagLong, bagTall, bagWide)
				bag.Anchored = true
				bag.CanCollide = false
				-- Оттенок у каждого мешка чуть свой: один цвет на всю кладку снова читается кубом.
				local shade = (math.random() - 0.5) * 0.09
				bag.Color = Color3.new(
					math.clamp(SANDBAG_COLOR.R + shade, 0, 1),
					math.clamp(SANDBAG_COLOR.G + shade, 0, 1),
					math.clamp(SANDBAG_COLOR.B + shade * 1.4, 0, 1)
				)
				bag.Material = Enum.Material.Sand
				-- Небольшой разворот и просадка: мешки лежат как легли, а не по линейке.
				bag.CFrame = CFrame.new(dx, y, dz)
					* CFrame.Angles(0, (math.random() - 0.5) * 0.22, 0)
					* CFrame.Angles((math.random() - 0.5) * 0.09, 0, (math.random() - 0.5) * 0.09)
				bag.Parent = model

				local mesh = Instance.new("SpecialMesh")
				mesh.MeshType = Enum.MeshType.Sphere
				mesh.Parent = bag
			end
			end
		end

		model.PrimaryPart = root
		return model
	end

	-- Преграда Горы (v2.2, killBarrier элемента Mountain в Elements): тот же принцип блока, что
	-- у Стены, но сторона и высота идут не из Grid.BuildSize напрямую, а со своим scale — Effects
	-- решает его из HP убитого жука (см. Effects.OnKillBarrier). Подошва всегда на TOWER_Y независимо
	-- от масштаба, иначе крупная гора проваливалась бы под пол, а мелкая повисала бы над ним.
	local function buildMountainBarrierModel(scale)
		local model = Instance.new("Model")
		model.Name = "Гора"

		local root = Instance.new("Part")
		root.Name = "Root"
		root.Size = Vector3.new(0.2, 0.2, 0.2)
		root.Anchored = true
		root.CanCollide = false
		root.CanQuery = false
		root.Transparency = 1
		root.CFrame = CFrame.new(0, 0, 0)
		root.Parent = model

		local side = (Grid.BuildSize - 0.4) * scale
		local height = MOUNTAIN_HEIGHT * scale

		local block = Instance.new("Part")
		block.Name = "Block"
		block.Size = Vector3.new(side, height, side)
		block.Anchored = true
		block.CanCollide = true
		block.Color = Color3.fromRGB(110, 115, 120)
		block.Material = Enum.Material.Rock
		block.CFrame = CFrame.new(0, height / 2 - TOWER_Y, 0)
		block.Parent = model

		model.PrimaryPart = root
		return model
	end

	-- Химический миномет (Мортира): тяжёлая чугунная станина всей подошвой на земле и широкая
	-- наклонная шахта-ствол на ней. Ствол ставится под тем же постоянным углом, под которым потом
	-- доворачивается на цель (BARRELS.Mortar.pitch): модель и стрельба берут число из одного места.
	local function buildMortarModel(towerData)
		local model = Instance.new("Model")
		model.Name = towerData.name
		addRoot(model)

		local iron = Color3.fromRGB(58, 56, 58)

		-- Низ станины на -1.6, там же, где подошвы ножек Колбы: все постройки ставятся одним TOWER_Y.
		-- Корпус твёрдый, как база Колбы и блок Стены: игрок не должен проходить сквозь турель.
		addPart(model, "Base", Vector3.new(3.2, 1.2, 3.2), CFrame.new(0, -1.0, 0), iron, Enum.Material.Metal).CanCollide = true
		addPart(model, "Mount", Vector3.new(0.9, 2.2, 2.2), CFrame.new(0, -0.2, 0) * STAND_UP,
			Color3.fromRGB(78, 74, 70), Enum.Material.Metal, Enum.PartType.Cylinder)

		-- Начальное положение — ровно то, что даст aimBarrel для цели прямо по -Z.
		local geometry = BARRELS.Mortar
		local pitch = math.rad(geometry.pitch)
		local direction = Vector3.new(0, math.sin(pitch), -math.cos(pitch))
		local center = Vector3.new(0, geometry.height, 0) + direction * geometry.reach
		addPart(model, "Barrel", Vector3.new(geometry.length, 1.5, 1.5),
			CFrame.lookAt(center, center + direction) * CFrame.Angles(0, math.rad(90), 0),
			Color3.fromRGB(44, 42, 44), Enum.Material.Metal, Enum.PartType.Cylinder)

		-- Сфера-снаряд в лотке у казённика: по ней видно, чем турель заряжена.
		local shell = addPart(model, "Liquid", Vector3.new(0.9, 0.9, 0.9), CFrame.new(0, 0.1, 1.25),
			Color3.fromRGB(225, 240, 245), Enum.Material.Glass, Enum.PartType.Ball)
		bindElementTint(model, { shell })

		return model
	end

	-- Станция FPV-дронов (изменение 3.1 вики): вместо процедурной мортиры ставится клон
	-- авторского меша. Сам шаблон собран из импорта разовым execute_luau (как и шаблон
	-- Колбы в задаче #63): команды импорта файла в наборе MCP нет, модель завозит автор
	-- руками через Import 3D.
	--
	-- Здесь делается ровно два действия, всё остальное (геометрия, масштаб, цвета, пивот,
	-- Anchored) уже впечатано в шаблон:
	--  * коллизия на несущих объёмах — так же, как buildTowerModelMesh включает её у OctoBase
	--    Колбы: игрок ходит физикой и без этого проходит сквозь станцию насквозь.
	--    На каждую трубку и решётку её не вешаем: сквозь корпус и так не пройти,
	--    а полтораста коллизионных мешей стоят дороже, чем дают;
	--  * индикатор залитого элемента — только светящиеся детали станции (у автора в .glb это
	--    материалы DS_EmisW и DS_EmisB2). Остальные цветные материалы автора
	--    (DS_Plate/DS_Detail/DS_Cavity/DS_Rubber/DS_Armour/DS_Void/DS_Hazard) — это корпус станции,
	--    он остаётся в своих авторских цветах навсегда (была попытка расширить акцент
	--    на весь не-чёрный материал — откачено по прямому запросу: корпус есть корпус,
	--    а акцент — это только индикаторные огоньки, как у Колбы). Пустая станция горит
	--    белым (ACCENT_NEUTRAL_COLOR), а не гаснет — точно как акценты Колбы.
	local DRONE_STATION_SOLID = { "DSFoot", "DSBase", "DSDeck", "StorBody", "FacBody", "FacUpper",
		"TwrBody", "TwrRoof", "StorRoof", "AddCoolTower" }
	-- AddCoolStripe — жёлтая лента на градирне, добавлена в индикатор по прямому запросу автора.
	-- У автора в .glb это единственная деталь материала DS_Hazard — янтарная (235,170,55) и уже Neon,
	-- то есть она и до этого была светящимся акцентом, просто со своим цветом. Теперь живёт по общему
	-- правилу индикатора: цвет залитого элемента, а у пустой станции — белый, как и остальные девять.
	local DRONE_STATION_GLOW = { "CoreSlab", "CoreGlowV0", "CoreGlowV1", "AddCoreSidePanel", "FacEmbGlow",
		"TwrRingTop", "HatchLidRingGlow", "AddSensorTip", "PolishFacAntTip", "PolishTwrAntTip", "AddCoolStripe" }

	local function buildDroneStationModel(towerData)
		if not droneStationTemplate then
			warn("[TowerBuilder] DroneStationTemplate не найден в ServerStorage, откат на процедурную мортиру")
			return buildMortarModel(towerData)
		end

		local model = droneStationTemplate:Clone()
		model.Name = towerData.name

		for _, name in DRONE_STATION_SOLID do
			local part = model:FindFirstChild(name, true)
			if part then
				part.CanCollide = true
			end
		end

		local glow = {}
		for _, name in DRONE_STATION_GLOW do
			local part = model:FindFirstChild(name, true)
			if part then
				table.insert(glow, part)
			end
		end
		bindElementTint(model, glow, 0, 0, ACCENT_NEUTRAL_COLOR)

		return model
	end

	-- ПРЕЖНЯЯ процедурная Пневматическая винтовка из примитивов — не используется с тех пор,
	-- как MODELS.Injector указывает на buildInjectorMeshModel (авторский меш), но нарочно
	-- не тронута и не удалена: вернуть старый визуал — это одна строка в MODELS,
	-- ровно как у Колбы (задача #63) и Мортиры (#72).
	--
	-- Длинный тонкий ствол из латуни, револьверный
	-- барабан и два баллона высокого давления по бокам. Барабан стоит по центру, а не «сзади»:
	-- ствол доворачивается на цель каждым выстрелом, и всё, что привязано к его хвосту, с ним бы разъехалось.
	local function buildInjectorModel(towerData)
		local model = Instance.new("Model")
		model.Name = towerData.name
		addRoot(model)

		local steel = Color3.fromRGB(70, 72, 78)
		local brass = Color3.fromRGB(186, 148, 62)
		-- Собственные размеры этой модели, а не BARRELS.Injector: там теперь замеры меша,
		-- и откат на примитивы собрал бы себя по чужой геометрии (ствол нулевой длины).
		local geometry = { height = 2.2, reach = 1.7, length = 3.0 }

		addPart(model, "Base", Vector3.new(1.2, 1.8, 1.8), CFrame.new(0, -1.0, 0) * STAND_UP,
			steel, Enum.Material.Metal, Enum.PartType.Cylinder).CanCollide = true
		addPart(model, "Post", Vector3.new(0.7, 3.4, 0.7), CFrame.new(0, 0.7, 0), steel, Enum.Material.Metal)
		addPart(model, "Drum", Vector3.new(0.9, 1.7, 1.7), CFrame.new(0, geometry.height, 0) * STAND_UP,
			Color3.fromRGB(96, 92, 88), Enum.Material.Metal, Enum.PartType.Cylinder)

		for i, side in { -1, 1 } do
			addPart(model, "Tank" .. i, Vector3.new(1.9, 0.7, 0.7), CFrame.new(side * 1.15, 0.55, 0) * STAND_UP,
				brass, Enum.Material.Metal, Enum.PartType.Cylinder)
		end

		addPart(model, "Barrel", Vector3.new(geometry.length, 0.35, 0.35),
			CFrame.new(0, geometry.height, -geometry.reach) * CFrame.Angles(0, math.rad(90), 0),
			brass, Enum.Material.Metal, Enum.PartType.Cylinder)

		-- Кольцо вокруг барабана, а не капсула внутри него: сквозь металлический барабан
		-- залитого элемента не видно, а по ободу — видно с высоты камеры.
		local ring = addPart(model, "Liquid", Vector3.new(0.5, 2.0, 2.0), CFrame.new(0, geometry.height, 0) * STAND_UP,
			Color3.fromRGB(225, 240, 245), Enum.Material.Neon, Enum.PartType.Cylinder)
		bindElementTint(model, { ring })

		return model
	end

	-- Акценты Инжектора — индикатор залитого элемента. Список имён деталей тут
	-- не нужен: шаблон помнит имя авторского материала на каждой детали (атрибут
	-- GlbMaterial), и акцент задан МАТЕРИАЛОМ — переимпорт с другими именами мешей
	-- ничего здесь не сломает.
	--
	-- Акцентными считаются все НЕ-корпусные материалы .glb: свечение (Glow_Core —
	-- полосы на люльке, кольцо ствола, точка прицела, ободок барабана), светлая
	-- фурнитура (Brass_Fitting — пружины, штуцера, трубки, дульное кольцо, плита
	-- станины) и стекло (Glass_Tank — баллоны, Glass_Capsule — сама игла-капсула,
	-- которая по вики и несёт элемент в цель). Корпус (Steel_Dark, Steel_Cylinder,
	-- Vent_Dark) остаётся тёмным металлом: перекрашивать целиком и его уже пробовали
	-- у Станции ФПВ-дронов и откатили (задача #74).
	local INJECTOR_ACCENT = {
		Glow_Core = true,
		Brass_Fitting = true,
		Glass_Tank = true,
		Glass_Capsule = true,
	}

	-- Твёрдые детали: только станина. Игрок не должен проходить сквозь турель (он ходит
	-- физикой), а вешать коллизию на все сорок мешей значит платить за неё ни за что:
	-- сквозь станину шириной во всю постройку и так не пройти, а ствол ещё и крутится
	-- (тот же принцип, что у Станции ФПВ-дронов, задача #72). Жуков коллизия не касается
	-- вовсе: они анкорнуты и ходят по сетке, занятость клеток держит Grid.
	local INJECTOR_SOLID = { "BaseStatic", "BaseStatic_2" }

	-- Пневматическая винтовка (Инжектор) на авторском меше: клон шаблона, коллизия
	-- на станине и цвет элемента на светящихся деталях — ровно та же тройка шагов, что
	-- у Станции ФПВ-дронов. Доворот ствола здесь не заводится: его делает aimRig по rig
	-- из BARRELS.Injector в тот же момент, когда турель стреляет.
	local function buildInjectorMeshModel(towerData)
		if not injectorTemplate then
			warn("[TowerBuilder] InjectorTurretTemplate не найден в ServerStorage, откат на процедурный Инжектор")
			return buildInjectorModel(towerData)
		end

		local model = injectorTemplate:Clone()
		model.Name = towerData.name

		for _, name in INJECTOR_SOLID do
			local part = model:FindFirstChild(name, true)
			if part then
				part.CanCollide = true
			end
		end

		-- Группируются по ПРОЗРАЧНОСТИ: bindElementTint выставляет её всем деталям списка
		-- разом, и один общий вызов затёр бы стекло в ноль. Каждая деталь остаётся
		-- со своей авторской прозрачностью и залитой, и пустой.
		--
		-- Пустая турель горит белым, а не гаснет — точно как акценты Колбы и Станции.
		local byTransparency = {}
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") and INJECTOR_ACCENT[part:GetAttribute("GlbMaterial")] then
				local group = byTransparency[part.Transparency]
				if not group then
					group = {}
					byTransparency[part.Transparency] = group
				end
				table.insert(group, part)
			end
		end
		for transparency, parts in byTransparency do
			bindElementTint(model, parts, transparency, transparency, ACCENT_NEUTRAL_COLOR)
		end

		return model
	end

	-- Газообразная машина (Испаритель): вертикальная вентиляционная коробка, лопасти под
	-- решёткой и само облако над ней. Облако — не украшение, а ровно та зона, в которой турель
	-- бьёт (towerData.range и areaHeight), видимая глазами.
	local function buildVaporizerModel(towerData)
		local model = Instance.new("Model")
		model.Name = towerData.name
		addRoot(model)

		addPart(model, "Box", Vector3.new(2.6, 2.6, 2.6), CFrame.new(0, -0.3, 0),
			Color3.fromRGB(66, 70, 74), Enum.Material.Metal).CanCollide = true

		-- Лопасти крест-накрест. Крутит их клиент по атрибуту Spin (см. BuildingVisuals):
		-- серверу двигать анкорнутую деталь каждый кадр — это репликация ради одной картинки.
		for i, angle in { 0, 90 } do
			local blade = addPart(model, "Fan" .. i, Vector3.new(2.2, 0.1, 0.5),
				CFrame.new(0, 0.8, 0) * CFrame.Angles(0, math.rad(angle), 0),
				Color3.fromRGB(150, 155, 160), Enum.Material.Metal)
			blade:SetAttribute("Spin", 900) -- градусов в секунду
		end

		addPart(model, "Grate", Vector3.new(2.8, 0.2, 2.8), CFrame.new(0, 1.2, 0),
			Color3.fromRGB(48, 50, 54), Enum.Material.DiamondPlate)

		-- Размер облака задан мешем, а не Size детали, нарочно: по Size считается габарит
		-- модели, и шар в 16 студов унёс бы HP-полоску постройки под небо (см. BuildingVisuals).
		local cloud = addPart(model, "Cloud", Vector3.new(1, 1, 1), CFrame.new(0, towerData.areaHeight, 0),
			Color3.fromRGB(225, 240, 245), Enum.Material.Neon, Enum.PartType.Ball)
		cloud.CanQuery = false

		local cloudMesh = Instance.new("SpecialMesh")
		cloudMesh.MeshType = Enum.MeshType.Sphere
		cloudMesh.Scale = Vector3.new(towerData.range * 2, towerData.range * 1.1, towerData.range * 2)
		cloudMesh.Parent = cloud

		-- Газ обязан просвечивать в обоих состояниях: под ним ходят жуки и стоят соседние турели.
		bindElementTint(model, { cloud }, 0.93, 0.82)

		return model
	end

	-- Турель-дрель (Бур): низкая бронеплита во всю клетку и конусное сверло из её центра.
	-- Своего конуса среди примитивов Roblox нет, поэтому он собран из четырёх сужающихся
	-- цилиндров — ступенчатый с высоты камеры читается так же.
	local function buildDrillModel(towerData)
		local model = Instance.new("Model")
		model.Name = towerData.name
		addRoot(model)

		local steel = Color3.fromRGB(150, 152, 158)
		local side = Grid.BuildSize - 0.4

		-- Плита почти вровень с полом: Бур ставится на саму дорогу лабиринта.
		addPart(model, "Plate", Vector3.new(side, 0.6, side), CFrame.new(0, -1.3, 0),
			Color3.fromRGB(74, 70, 66), Enum.Material.DiamondPlate).CanCollide = true

		for i, segment in { { 1.7, -0.72 }, { 1.3, -0.17 }, { 0.9, 0.38 }, { 0.45, 0.93 } } do
			local bit = addPart(model, "Bit" .. i, Vector3.new(0.55, segment[1], segment[1]),
				CFrame.new(0, segment[2], 0) * STAND_UP, steel, Enum.Material.Metal, Enum.PartType.Cylinder)
			bit:SetAttribute("Spin", 540)
		end

		-- Спиральные желоба: по ним подаётся элемент, поэтому красятся они, а не само сверло.
		local grooves = {}
		for i, at in { { -0.5, 0 }, { 0.15, 60 } } do
			local groove = addPart(model, "Groove" .. i, Vector3.new(1.6, 0.16, 0.3),
				CFrame.new(0, at[1], 0) * CFrame.Angles(0, math.rad(at[2]), math.rad(12)),
				Color3.fromRGB(225, 240, 245), Enum.Material.Neon)
			groove:SetAttribute("Spin", 540)
			table.insert(grooves, groove)
		end

		bindElementTint(model, grooves)

		return model
	end

	-- Центробежный распылитель (Центрифуга): стеклянный резервуар с элементом и горизонтально
	-- вращающаяся головка с форсунками на нём.
	local function buildCentrifugeModel(towerData)
		local model = Instance.new("Model")
		model.Name = towerData.name
		addRoot(model)

		local steel = Color3.fromRGB(78, 80, 86)
		local glassColor = Color3.fromRGB(225, 240, 245)

		addPart(model, "Base", Vector3.new(0.5, 2.2, 2.2), CFrame.new(0, -1.35, 0) * STAND_UP,
			steel, Enum.Material.Metal, Enum.PartType.Cylinder)

		local tank = addPart(model, "Tank", Vector3.new(2.0, 2.2, 2.2), CFrame.new(0, -0.1, 0) * STAND_UP,
			glassColor, Enum.Material.Glass, Enum.PartType.Cylinder)
		tank.Transparency = 0.55
		tank.CanCollide = true

		local liquid = addPart(model, "Liquid", Vector3.new(1.5, 1.7, 1.7), CFrame.new(0, -0.35, 0) * STAND_UP,
			glassColor, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
		liquid.CanQuery = false

		-- Головка и форсунки вращаются вместе вокруг оси самой турели (см. BuildingVisuals):
		-- вращай клиент каждую деталь вокруг её собственного центра, форсунки крутились бы на месте
		-- вместо того, чтобы ходить по кругу.
		local head = addPart(model, "SprayHead", Vector3.new(0.35, 2.6, 2.6), CFrame.new(0, 1.15, 0) * STAND_UP,
			steel, Enum.Material.Metal, Enum.PartType.Cylinder)
		head:SetAttribute("Spin", 720)

		for i = 1, 4 do
			local angle = math.rad(90 * (i - 1))
			local direction = Vector3.new(math.sin(angle), 0, math.cos(angle))
			local at = direction * 1.45 + Vector3.new(0, 1.15, 0)
			local nozzle = addPart(model, "Nozzle" .. i, Vector3.new(0.6, 0.28, 0.28),
				CFrame.lookAt(at, at + direction) * CFrame.Angles(0, math.rad(90), 0),
				Color3.fromRGB(150, 152, 158), Enum.Material.Metal, Enum.PartType.Cylinder)
			nozzle:SetAttribute("Spin", 720)
		end

		bindElementTint(model, { liquid })

		return model
	end

	-- Модель по типу постройки. До задачи #53 выбор был двоичным (есть fireRate — Колба,
	-- нет — Стена); теперь у каждой турели своя модель. Фолбэк по fireRate остался на случай
	-- типа без собственной записи: постройка встанет хоть какой-то, а не уронит стройку.
	local MODELS = {
		Ballista = buildTowerModelMesh,
		Wall = buildWallModel,
		Mortar = buildDroneStationModel, -- изменение 3.1: мортира стала Станцией FPV-дронов; откат — buildMortarModel
		Injector = buildInjectorMeshModel, -- авторский меш; откат — buildInjectorModel
		Vaporizer = buildVaporizerModel,
		Drill = buildDrillModel,
		Centrifuge = buildCentrifugeModel,
	}

	-- Доворачивает ствол на точку прицеливания и возвращает мировую точку дульного среза — оттуда
	-- стартует снаряд. Пока выстрел был мгновенным лучом, направление ствола ни на что не влияло;
	-- теперь снаряд видимо вылетает из дула, и ствол, смотрящий в другую сторону, читался бы как поломка.
	--
	-- Ствол ставится заново от центра сферы, а не поворачивается «на месте»: своего шарнира у детали
	-- нет, а пивот всей башни трогать нельзя — по нему считается клетка. Поворот вписан прямо
	-- в CFrame (ось цилиндра — локальная X, отсюда +90° по Y к lookAt): отдельный Orientation стёрся бы
	-- этим же присваиванием, см. «Грабли Roblox» в STATE.md.
	--
	-- У ствола с постоянным углом (geometry.pitch, Мортира) от точки прицеливания берётся только
	-- направление по горизонтали: поднять или опустить шахту мортира не умеет.
	--
	-- Для турелей с клиентским наведением (Колба, geometry.clientTracked) ствол не доворачивается
	-- сервером: визуальное наведение делает клиент в BuildingVisuals, а серверу нужен только дульный срез.
	-- Настоящий дульный срез меша (Колба). У этого меша ствол сдвинут от оси турели вбок
	-- (колба слева, пушка справа), а точка, которую даёт reach/height, лежит на самой оси —
	-- снаряд вылетал из воздуха рядом с колбой, а не из ствола. Замерено по шаблону:
	-- срез стоит в (1.50, 4.34, -7.75) координат модели, то есть мимо оси на 1.5 студа вбок
	-- и на 1.2 вперёд (всего 1.9) — ровно то расхождение, что числилось в открытых с задачи #69.
	--
	-- Спрашивается у самой модели, а не задаётся числом: переимпорт меша не должен требовать
	-- правки кода. На сервере детали меша стоят в ИСХОДНОЙ позе (поворот башни рисует клиент),
	-- поэтому берётся их смещение в координатах модели и доворачивается на тот же угол, который в этот
	-- момент рисует клиент: угол общий, он считается одной формулой Aiming на обеих сторонах
	-- (задача #70). Собрано теми же двумя деталями и тем же выносом, что и вспышка на клиенте
	-- (CombatFX.muzzleOf) — иначе они бы снова разошлись.
	--
	-- Вертикальная наводка учтена тоже: без неё точка пуска уезжала от среза попёрек ствола
	-- тем сильнее, чем круче опущен ствол (замерено живым прогоном: 0.6 студа при тангаже 9°
	-- и 2.4 при 16°). Цапфы и пределы хода берутся из Towers[тип].gun — из той же таблицы,
	-- по которой качает ствол клиент.
	--
	-- Сглаживание угла места живёт только на клиенте, поэтому берётся НАЦЕЛЕННЫЙ угол
	-- (тот же, что ушёл в AimPitch), а не сглаженный: в установившемся состоянии они равны,
	-- а на ходу остаётся только отставание клиента — угадывать чужое состояние хуже.
	local MUZZLE_LEAD = 1.2 -- studs от центра министвола до среза, как в CombatFX.muzzleOf


	return {
		MUZZLE_LEAD = MUZZLE_LEAD,
		MODELS = MODELS,
		buildTowerModel = buildTowerModel,
		buildWallModel = buildWallModel,
		buildMountainBarrierModel = buildMountainBarrierModel,
	}
end
