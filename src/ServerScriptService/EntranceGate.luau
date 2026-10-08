-- Большая гермодверь и портал входа в зал: через них приходят волны.
--
-- Было: голая дыра в стене. Проём — три детали в папке Walls (DoorLintel, DoorJambA, DoorJambB),
-- створка Corridor.HermeticDoor — плоская плита с красным штурвалом из восьми палочек, а вокруг
-- ничего: тёмный проём без рамы, света и маркировки.
-- Стало: модель Location.EntranceGate — портал со стороны зала (цоколи, пилястры со световой
-- щелью, ребра, балка-перемычка с зеброй, табличка, сигнальные маяки, вентрешётки, карниз),
-- подсвеченный тоннель проёма, облицовка со стороны коридора и тяжёлая створка, откатанная к
-- стене коридора: панели, зебра по низу, штурвал, гнёзда запорных штырей, рельс и упор.
--
-- Проход не тронут: чистый проём (ширина между косяками, высота до низа перемычки) остаётся
-- прежним. Всё, что стоит в нём, — гермоуплотнитель толщиной 0.1, как и раньше (старый FrameSeal);
-- остальное — на лицевых плоскостях стены и в нише коридора мимо коридора жуков.
-- Нет косяков и перемычки — размеры берутся из маркера Entrance и пола.
--
-- Строится кодом, а не руками в Studio: правка живёт в src/, место сохранять не нужно. Тот же
-- принцип, что у CraftTableModel. Звать на каждой загрузке локации: уже построенная модель
-- второй раз не ставится. Старая Corridor.HermeticDoor убирается только после успешной сборки.
--
-- Стиль — по вики: тёмный металл, три холодных серых, неон только световые линии и индикаторы
-- (бирюза — показания, янтарь — предупреждение), тёплых металлов и заклёпок нет, белый — лишь
-- в тексте таблички. Деталь делается геометрией: щель, рёбра, ступени, а не краской.
--
-- Мягкие детали (световые линии, зебра в проёме, плоская подсветка) лежат в папке GateSoft без
-- коллизии: MapCollision такую папку обходит. Твёрдое — рама, карниз, створка, рельс.
local EntranceGate = {}

local MODEL_NAME = "EntranceGate"
local SOFT_NAME = "GateSoft"
local MONO = "rbxasset://fonts/families/RobotoMono.json"

-- Три холодных серых: корпус, стойки и ободки, мелкие рёбра и кромки.
local BODY = Color3.fromRGB(40, 43, 49)
local MID = Color3.fromRGB(82, 88, 97)
local LIGHT = Color3.fromRGB(150, 157, 166)
local BLACK = Color3.fromRGB(20, 21, 24) -- щели, решётки
local LINING = Color3.fromRGB(50, 54, 61) -- облицовка тоннеля: темнее стали, но не чёрная дыра
local PANEL = Color3.fromRGB(106, 112, 121) -- вставки створки: светлее корпуса, не светлее ободка
local PLATE = Color3.fromRGB(24, 27, 31) -- фон таблички
local TEAL = Color3.fromRGB(70, 225, 230) -- показания
local AMBER = Color3.fromRGB(255, 165, 40) -- предупреждение
local YELLOW = Color3.fromHex("d9a520") -- та же зебра, что и в разметке пола
local STRIPE_BLACK = Color3.fromHex("2e3034")
local TEXT = Color3.fromRGB(215, 235, 238)

local METAL = Enum.Material.Metal
local PLASTIC = Enum.Material.SmoothPlastic
local NEON = Enum.Material.Neon
local DIAMOND = Enum.Material.DiamondPlate

-- Запасные размеры, если в локации нет косяков и перемычки.
local DEFAULT_HEIGHT = 7
local DEFAULT_DEPTH = 4

-- Полупроём по поперечной оси: габарит детали вдоль направления axis.
local function extentAlong(part, axis)
	local cf, s = part.CFrame, part.Size / 2
	return math.abs(cf.RightVector:Dot(axis)) * s.X + math.abs(cf.UpVector:Dot(axis)) * s.Y
		+ math.abs(cf.LookVector:Dot(axis)) * s.Z
end

-- Где проём: система координат на лицевой плоскости стены, на верху пола, по центру проёма.
-- u — вдоль стены (вправо, если смотреть из зала на стену), v — вверх, w — в зал.
-- Возвращает nil и причину, если расставить нечего.
local function locate(location)
	local markers = location:FindFirstChild("Markers")
	local entrance = markers and markers:FindFirstChild("Entrance")
	local floor = location:FindFirstChild("ArenaFloor")
	if not (entrance and floor and entrance:IsA("BasePart") and floor:IsA("BasePart")) then
		return nil, "нет Markers.Entrance или ArenaFloor"
	end

	-- Наружу — той осью, по которой вход дальше от центра пола (как Arena.findSpawn).
	local out = entrance.CFrame.Position - floor.CFrame.Position
	local outward
	if math.abs(out.X) >= math.abs(out.Z) then
		outward = Vector3.new(math.sign(out.X), 0, 0)
	else
		outward = Vector3.new(0, 0, math.sign(out.Z))
	end
	if outward.Magnitude < 0.5 then
		return nil, "вход в центре пола"
	end
	local toRoom = -outward
	local up = Vector3.yAxis
	local across = up:Cross(toRoom)
	local floorTop = floor.CFrame.Position.Y + floor.Size.Y / 2

	-- Лицевая плоскость стены: край пола с той стороны.
	local half = math.abs(outward.X) > 0.5 and floor.Size.X / 2 or floor.Size.Z / 2
	local face = floor.CFrame.Position:Dot(toRoom) - half
	-- Поперёк: центр и ширина проёма по маркеру.
	local center = entrance.CFrame.Position:Dot(across)
	local width = extentAlong(entrance, across) * 2
	local height, depth = DEFAULT_HEIGHT, DEFAULT_DEPTH
	local top = nil -- верх стены над проёмом, от верха пола

	-- Настоящий проём — между косяками и под перемычкой, если они на месте.
	local walls = location:FindFirstChild("Walls")
	local lintel = walls and walls:FindFirstChild("DoorLintel")
	local jambA = walls and walls:FindFirstChild("DoorJambA")
	local jambB = walls and walls:FindFirstChild("DoorJambB")
	if lintel and lintel:IsA("BasePart") then
		height = lintel.CFrame.Position.Y - extentAlong(lintel, up) - floorTop
		depth = extentAlong(lintel, toRoom) * 2
		top = lintel.CFrame.Position.Y + extentAlong(lintel, up) - floorTop
		face = lintel.CFrame.Position:Dot(toRoom) + extentAlong(lintel, toRoom)
	end
	if jambA and jambB and jambA:IsA("BasePart") and jambB:IsA("BasePart") then
		local a, b = jambA.CFrame.Position:Dot(across), jambB.CFrame.Position:Dot(across)
		local ea, eb = extentAlong(jambA, across), extentAlong(jambB, across)
		local lo, hi
		if a < b then
			lo, hi = a + ea, b - eb
		else
			lo, hi = b + eb, a - ea
		end
		if hi - lo > 4 then
			center = (lo + hi) / 2
			width = hi - lo
		end
	end
	if height < 3 or width < 4 then
		return nil, "проём слишком мал для двери"
	end

	-- Начало координат: на лицевой плоскости, по центру проёма, на верху пола. toRoom и across —
	-- оси мира, поэтому плоскость и центр складываются покомпонентно.
	local origin = toRoom * face + across * center + up * floorTop
	return {
		frame = CFrame.fromMatrix(origin, across, up, toRoom),
		width = width,
		height = height,
		top = top or height + 9,
		depth = depth,
	}
end

-- Набор для расстановки деталей в системе (u, v, w) выбранной рамки.
local function newKit(model, soft)
	local kit = { frame = CFrame.identity }

	-- Прямоугольный брус по границам в системе рамки (u0..u1, v0..v1, w0..w1).
	function kit.box(name, u0, u1, v0, v1, w0, w1, color, material, isSoft)
		if u0 > u1 then
			u0, u1 = u1, u0
		end
		if v0 > v1 then
			v0, v1 = v1, v0
		end
		if w0 > w1 then
			w0, w1 = w1, w0
		end
		local part = Instance.new("Part")
		part.Name = name
		part.Anchored = true
		part.CanTouch = false
		part.Size = Vector3.new(u1 - u0, v1 - v0, w1 - w0)
		part.CFrame = kit.frame * CFrame.new((u0 + u1) / 2, (v0 + v1) / 2, (w0 + w1) / 2)
		part.Color = color
		part.Material = material or METAL
		if isSoft then
			part.CanCollide = false
			part.CanQuery = false
			part.CastShadow = false
			part.Parent = soft
		else
			part.Parent = model
		end
		return part
	end

	-- Световая деталь: неон без коллизии.
	function kit.glow(name, u0, u1, v0, v1, w0, w1, color)
		return kit.box(name, u0, u1, v0, v1, w0, w1, color, NEON, true)
	end

	-- Цилиндр: axis — вдоль какой оси рамки лежит его длина ("u", "v" или "w").
	function kit.cylinder(name, u, v, w, length, diameter, axis, color, material, isSoft)
		local part = Instance.new("Part")
		part.Name = name
		part.Anchored = true
		part.CanTouch = false
		part.Shape = Enum.PartType.Cylinder
		part.Size = Vector3.new(length, diameter, diameter)
		local turn = CFrame.identity
		if axis == "v" then
			turn = CFrame.Angles(0, 0, math.pi / 2)
		elseif axis == "w" then
			turn = CFrame.Angles(0, math.pi / 2, 0)
		end
		part.CFrame = kit.frame * CFrame.new(u, v, w) * turn
		part.Color = color
		part.Material = material or METAL
		if isSoft then
			part.CanCollide = false
			part.CanQuery = false
			part.CastShadow = false
			part.Parent = soft
		else
			part.Parent = model
		end
		return part
	end

	-- Брус, повёрнутый вокруг оси u (штурвал): длинная сторона по v, поворот theta в плоскости (v, w).
	function kit.bar(name, u0, u1, v, w, length, thickness, theta, color, material)
		local part = Instance.new("Part")
		part.Name = name
		part.Anchored = true
		part.CanTouch = false
		part.Size = Vector3.new(math.abs(u1 - u0), length, thickness)
		part.CFrame = kit.frame * CFrame.new((u0 + u1) / 2, v, w) * CFrame.Angles(theta, 0, 0)
		part.Color = color
		part.Material = material or METAL
		part.Parent = model
		return part
	end

	-- Лампа: SurfaceLight на светящейся детали (так устроены лампы карты, и настройки графики
	-- их находят: яркость и тени ламп меняет Graphics.client по классу SurfaceLight).
	function kit.lamp(part, face, color, brightness, range, angle)
		local light = Instance.new("SurfaceLight")
		light.Face = face
		light.Color = color
		light.Brightness = brightness
		light.Range = range
		light.Angle = angle
		light.Shadows = false
		light.Parent = part
		return light
	end

	-- Зебра вдоль u: жёлтая основа и чёрные секции через одну.
	function kit.zebra(name, u0, u1, v0, v1, w0, w1, step, isSoft)
		kit.box(name .. "Base", u0, u1, v0, v1, w0, w1, YELLOW, PLASTIC, isSoft)
		local x, i = u0, 0
		while x < u1 - 1e-3 do
			local xn = math.min(x + step, u1)
			if i % 2 == 1 then
				kit.box(name .. "Bar", x, xn, v0, v1, w0, w1 + 0.03, STRIPE_BLACK, PLASTIC, isSoft)
			end
			x, i = xn, i + 1
		end
	end

	-- Зебра вдоль w (по полу или рельсу): секции по w.
	function kit.zebraW(name, u0, u1, v0, v1, w0, w1, step, isSoft)
		kit.box(name .. "Base", u0, u1, v0, v1, w0, w1, YELLOW, PLASTIC, isSoft)
		local lo, hi = math.min(w0, w1), math.max(w0, w1)
		local x, i = lo, 0
		while x < hi - 1e-3 do
			local xn = math.min(x + step, hi)
			if i % 2 == 1 then
				kit.box(name .. "Bar", u0 - 0.01, u1 + 0.01, v0, v1 + 0.01, x, xn, STRIPE_BLACK, PLASTIC, isSoft)
			end
			x, i = xn, i + 1
		end
	end

	-- Надпись на стороне детали, обращённой к +w рамки (Back у неповёрнутой детали рамки).
	function kit.label(part, lines)
		local gui = Instance.new("SurfaceGui")
		gui.Name = "Label"
		gui.Face = Enum.NormalId.Back
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 80
		gui.LightInfluence = 0
		gui.Parent = part
		local total = 0
		for _, line in lines do
			total += line.weight
		end
		local y = 0
		for _, line in lines do
			local label = Instance.new("TextLabel")
			label.BackgroundTransparency = 1
			label.Size = UDim2.fromScale(1, line.weight / total)
			label.Position = UDim2.fromScale(0, y)
			label.Text = line.text
			label.TextColor3 = line.color or TEXT
			label.TextScaled = true
			label.FontFace = Font.new(MONO, Enum.FontWeight.Bold)
			label.Parent = gui
			y += line.weight / total
		end
	end

	return kit
end

-- Стена над порталом. Над карнизом до самого верха стены тянулась голая тёмная плита перемычки —
-- две мёртвые плоскости по бокам от балки. Здесь она закрыта щитом: панели со швами, световые линии
-- от пилястр, вентрешётки, позывной шлюза и верхний кант. Всё плоское, не толще 0.35: короба и лотки
-- на стенах по вики запрещены.
local function upperField(kit, W, H, top)
	local HW = W / 2
	local base = H + 2.75 -- верх карниза
	local EDGE = HW + 9 -- щит шире портала на девять студов с каждой стороны
	local roof = top - 0.2 -- под верхним кантом
	if roof - base < 2 then
		return
	end

	-- Подложка: тёмная, швы между панелями — это зазоры, в которых видна она.
	kit.box("FieldBacking", -EDGE, EDGE, base, roof, 0, 0.12, BLACK, METAL)

	local function panelColumn(u0, u1, tag)
		kit.box("FieldPanel" .. tag, u0, u1, base + 0.3, roof - 0.3, 0.12, 0.28, BODY)
		-- Вставка: ступенька внутри панели, ниже и выше — прорезь.
		kit.box("FieldInset" .. tag, u0 + 0.35, u1 - 0.35, base + 0.9, roof - 0.9, 0.28, 0.36, MID)
	end
	-- Панели по бокам от портала: три на сторону, ширина панели подогнана под край щита.
	local gap = 0.35
	local inner = HW + 1.4 -- внутри от пилястры остаётся место световой линии
	local count = 3
	local width = (EDGE - inner - gap * (count - 1)) / count
	for _, s in { -1, 1 } do
		for i = 0, count - 1 do
			local a = inner + i * (width + gap)
			panelColumn(s * a, s * (a + width), s < 0 and "A" or "B")
		end
		-- Вентрешётка в крайней панели: рама и ряд прорезей.
		local a = inner + (count - 1) * (width + gap)
		local c = s * (a + width / 2)
		kit.box("FieldVent", c - 1.3, c + 1.3, base + 1.6, base + 3.6, 0.36, 0.42, BLACK, PLASTIC)
		for k = 0, 7 do
			local v = base + 1.75 + k * 0.23
			kit.box("FieldVentSlat", c - 1.15, c + 1.15, v, v + 0.1, 0.42, 0.55, MID)
		end
	end

	-- Центральный щит над проёмом: тёмная плита с позывным шлюза и рамкой.
	local crest = kit.box("FieldCrest", -4.2, 4.2, base + 0.9, roof - 0.9, 0.12, 0.36, PLATE, PLASTIC)
	kit.box("FieldCrestFrame", -4.5, 4.5, base + 0.7, roof - 0.7, 0.12, 0.2, MID)
	kit.glow("FieldCrestLineTop", -4.2, 4.2, roof - 0.9, roof - 0.84, 0.36, 0.4, TEAL)
	kit.glow("FieldCrestLineBottom", -4.2, 4.2, base + 0.84, base + 0.9, 0.36, 0.4, TEAL)
	kit.label(crest, {
		{ text = "01", weight = 3 },
		{ text = "ПРОХОД ПО ДОПУСКУ", weight = 0.9, color = TEAL },
	})
	-- Стойки между центром и панелями.
	for _, s in { -1, 1 } do
		kit.box("FieldPost", s * 4.6, s * (HW + 0.35), base + 0.3, roof - 0.3, 0.12, 0.3, MID)
	end

	-- Световые линии продолжают пилястры вверх, по краю портала.
	for _, s in { -1, 1 } do
		local tag = s < 0 and "A" or "B"
		kit.box("FieldLightSlot" .. tag, s * (HW + 0.55), s * (HW + 1.1), base + 0.3, roof - 0.3, 0.12, 0.2, BLACK, PLASTIC)
		local line = kit.glow("FieldLight" .. tag, s * (HW + 0.7), s * (HW + 0.95), base + 0.45, roof - 0.45, 0.2, 0.26, TEAL)
		kit.lamp(line, Enum.NormalId.Back, TEAL, 0.6, 9, 120)
	end

	-- Верхний кант щита.
	kit.box("FieldCap", -EDGE - 0.2, EDGE + 0.2, roof, top, 0, 0.35, MID)
	kit.box("FieldCapLip", -EDGE - 0.2, EDGE + 0.2, roof, roof + 0.08, 0.35, 0.42, BLACK, PLASTIC)
end

-- Портал со стороны зала: всё стоит на лицевой плоскости стены (w от 0 в зал).
local function labFace(kit, W, H, top)
	local HW = W / 2
	local OUT = 3.4 -- на сколько пилястра уходит вбок от проёма

	for _, s in { -1, 1 } do
		local tag = s < 0 and "A" or "B"
		-- Цоколь, плита, колонна и губа у кромки проёма: стопка, каждый слой чуть отступает.
		kit.box("Plinth" .. tag, s * HW, s * (HW + OUT), 0, 0.9, 0, 0.6, BODY)
		kit.box("PilasterPlate" .. tag, s * HW, s * (HW + OUT), 0.9, H + 2.4, 0, 0.22, BODY)
		kit.box("PilasterColumn" .. tag, s * HW, s * (HW + 2.2), 0.9, H + 1.9, 0.22, 0.5, MID)
		kit.box("PilasterLip" .. tag, s * HW, s * (HW + 0.2), 0.9, H + 1.9, 0.5, 0.62, BODY)
		-- Световая щель: в чёрном пазе — линия показаний.
		kit.box("LightSlot" .. tag, s * (HW + 0.55), s * (HW + 1.65), 1.7, H + 1.2, 0.5, 0.58, BLACK, PLASTIC)
		local strip = kit.glow("LightStrip" .. tag, s * (HW + 0.9), s * (HW + 1.3), 1.9, H + 1.0, 0.58, 0.64, TEAL)
		kit.lamp(strip, Enum.NormalId.Back, TEAL, 0.7, 9, 120)
		-- Рёбра на внешней ступени.
		for i = 0, 4 do
			local v = 1.8 + i * 1.6
			kit.box("PilasterRib" .. tag, s * (HW + 2.2), s * (HW + OUT), v, v + 0.2, 0.22, 0.42, LIGHT)
		end
	end

	-- Перемычка: плита, лента-основа, нижняя зебра по кромке.
	kit.box("HeaderPlate", -HW, HW, H, H + 2.4, 0, 0.22, BODY)
	kit.box("HeaderBand", -HW, HW, H, H + 1.9, 0.22, 0.55, MID)
	kit.zebra("HeaderZebra", -HW, HW, H, H + 0.55, 0.55, 0.62, 1, true)

	-- Табличка: тёмная, с неоновой подчёркивающей линией, текст — в пазе шрифта прибора.
	local plate = kit.box("SignPlate", -3, 3, H + 0.75, H + 1.7, 0.55, 0.7, PLATE, PLASTIC)
	kit.glow("SignUnderline", -3, 3, H + 0.68, H + 0.75, 0.55, 0.72, TEAL)
	kit.label(plate, {
		{ text = "ШЛЮЗ 01", weight = 3 },
		{ text = "ГЕРМОЗОНА · ДОПУСК 2", weight = 1.6, color = TEAL },
	})

	-- Сигнальные маяки по бокам таблички: корпус-кольцо и янтарная линза.
	for _, s in { -1, 1 } do
		local tag = s < 0 and "A" or "B"
		kit.cylinder("BeaconHousing" .. tag, s * 4.6, H + 1.2, 0.72, 0.35, 1.1, "w", BODY)
		local lens = kit.cylinder("BeaconLens" .. tag, s * 4.6, H + 1.2, 0.95, 0.2, 0.74, "w", AMBER, NEON, true)
		kit.lamp(lens, Enum.NormalId.Back, AMBER, 1.2, 10, 140)
		-- Вентрешётка: рама и пять прорезей-рёбер.
		kit.box("VentFrame" .. tag, s * 5.7, s * 7.7, H + 0.7, H + 1.7, 0.55, 0.62, BLACK, PLASTIC)
		for k = 0, 4 do
			local v = H + 0.82 + k * 0.17
			kit.box("VentSlat" .. tag, s * 5.8, s * 7.6, v, v + 0.09, 0.62, 0.76, MID)
		end
	end

	-- Карниз над порталом.
	kit.box("Cornice", -(HW + OUT + 0.3), HW + OUT + 0.3, H + 2.4, H + 2.75, 0, 0.7, MID)
	kit.box("CorniceLip", -(HW + OUT + 0.3), HW + OUT + 0.3, H + 2.4, H + 2.48, 0.7, 0.78, BLACK, PLASTIC)
	upperField(kit, W, H, top)
end

-- Тоннель проёма: облицовка, подсветка потолка и пола. Всё в пределах 0.1 от кромок проёма.
local function tunnel(kit, W, H, D)
	local HW = W / 2
	-- Облицовка тоннеля, как прежний уплотнитель: толщина 0.1 на боках и под перемычкой.
	for _, s in { -1, 1 } do
		kit.box("Lining" .. (s < 0 and "A" or "B"), s * HW, s * (HW - 0.1), 0, H, -D, 0, LINING)
	end
	kit.box("LiningTop", -HW, HW, H - 0.1, H, -D, 0, LINING)

	-- Потолок: две линии света вдоль прохода, под ними мягкая заливка пола.
	for _, s in { -1, 1 } do
		local tag = s < 0 and "A" or "B"
		local line = kit.glow("CeilingLine" .. tag, s * 3.2 - 0.12, s * 3.2 + 0.12, H - 0.14, H - 0.1, -D + 0.4, -0.4, TEAL)
		kit.lamp(line, Enum.NormalId.Bottom, Color3.fromRGB(170, 235, 240), 1.1, 12, 160)
		-- Поручневая линия на стенах тоннеля и янтарные пунктиры по кромке пола вдоль прохода.
		kit.glow("RailLine" .. tag, s * (HW - 0.14), s * (HW - 0.1), 1.1, 1.2, -D + 0.3, -0.3, TEAL)
		for i = 0, 3 do
			local w = -D + 0.5 + i * ((D - 1.6) / 3)
			kit.glow("FloorDash" .. tag, s * (HW - 0.75), s * (HW - 0.45), 0, 0.04, w, w + 0.6, AMBER)
		end
	end
end

-- Облицовка проёма со стороны коридора: лёгкая, без выступов — вдоль стен коридора идут трубы.
-- Система рамки уже повёрнута лицом в коридор, w — в коридор.
local function corridorFace(kit, W, H)
	local HW = W / 2
	for _, s in { -1, 1 } do
		local tag = s < 0 and "A" or "B"
		kit.box("Architrave" .. tag, s * HW, s * (HW + 1.2), 0, H + 1.5, 0, 0.2, BODY)
		kit.box("ArchitraveLip" .. tag, s * HW, s * (HW + 0.18), 0, H + 1.5, 0.2, 0.3, MID)
	end
	kit.box("CorridorHeader", -HW, HW, H, H + 1.5, 0, 0.3, MID)
	kit.zebra("CorridorZebra", -HW, HW, H, H + 0.5, 0.3, 0.36, 1, true)
	local plate = kit.box("CorridorSign", -3.4, 3.4, H + 0.7, H + 1.35, 0.3, 0.42, PLATE, PLASTIC)
	kit.glow("CorridorUnderline", -3.4, 3.4, H + 0.64, H + 0.7, 0.3, 0.44, TEAL)
	kit.label(plate, {
		{ text = "ВНЕШНИЙ ПЕРИМЕТР", weight = 1 },
	})
	for _, s in { -1, 1 } do
		local tag = s < 0 and "A" or "B"
		kit.cylinder("CorridorBeaconHousing" .. tag, s * 5.2, H + 0.95, 0.45, 0.3, 0.9, "w", BODY)
		local lens = kit.cylinder("CorridorBeaconLens" .. tag, s * 5.2, H + 0.95, 0.65, 0.18, 0.62, "w", AMBER, NEON, true)
		kit.lamp(lens, Enum.NormalId.Back, AMBER, 1, 9, 140)
	end
end

-- Тяжёлая створка, откатанная к стене коридора (сторона +u), и её рельс.
-- Рамка — лицом в зал, как у портала; створка лежит в коридоре за стеной, w < -D.
local function leaf(kit, W, H, D, side)
	local HW = W / 2
	local near = HW + 0.95 -- ближняя к проёму плоскость створки
	local far = HW + 1.95 -- дальняя, у стены коридора
	local w0 = -D - 1.0 -- передний край (ближе к двери)
	local len = 15.6
	local w1 = w0 - len
	local function s(a)
		return side * a
	end

	kit.box("LeafCore", s(near), s(far), 0, H, w1, w0, BODY)

	-- Три панели на стороне, обращённой к проходу: рама и стамповка внутри.
	for i = 0, 2 do
		local top = w0 - 0.4 - i * 5
		local pa, pb = top - 4.5, top
		kit.box("LeafPanel", s(near - 0.12), s(near), 0.65, H - 0.65, pa, pb, MID)
		kit.box("LeafInset", s(near - 0.17), s(near - 0.12), 1.05, H - 1.05, pa + 0.4, pb - 0.4, PANEL)
	end
	-- Зебра по нижней кромке.
	kit.zebraW("LeafZebra", s(near - 0.05), s(near), 0, 0.45, w1 + 0.3, w0 - 0.3, 1, true)

	-- Штурвал на средней панели: ступица, бобышка, восемь спиц и обод из двенадцати звеньев.
	local wheelW = w0 - 0.4 - 5 - 2.25
	local wheelV = H / 2
	local wu = near - 0.17
	kit.cylinder("WheelBoss", s(wu - 0.1), wheelV, wheelW, 0.2, 1.7, "u", MID)
	kit.cylinder("WheelHub", s(wu - 0.3), wheelV, wheelW, 0.4, 0.9, "u", LIGHT)
	for i = 0, 3 do
		kit.bar("WheelSpoke", s(wu - 0.34), s(wu - 0.2), wheelV, wheelW, 2.5, 0.14, i * math.pi / 4, LIGHT)
	end
	local R, N = 1.2, 12
	local chord = 2 * R * math.sin(math.pi / N) + 0.05
	for i = 0, N - 1 do
		local phi = i * 2 * math.pi / N
		kit.bar("WheelRim", s(wu - 0.34), s(wu - 0.2), wheelV + R * math.cos(phi), wheelW + R * math.sin(phi),
			chord, 0.16, phi + math.pi / 2, LIGHT)
	end

	-- Передний торец: гнёзда запорных штырей, штырь убран, видна лишь коротышка-заглушка.
	for i = 0, 5 do
		local v = 0.85 + i * ((H - 1.7) / 5)
		kit.box("BoltSleeve", s(near + 0.1), s(far - 0.1), v - 0.28, v + 0.28, w0, w0 + 0.22, MID)
		kit.cylinder("BoltStub", s((near + far) / 2), v, w0 + 0.3, 0.16, 0.4, "w", LIGHT)
	end
	-- Индикатор створки: янтарная лампа над передним краем.
	local lamp = kit.glow("LeafLamp", s(near + 0.3), s(far - 0.3), H, H + 0.3, w0 - 0.5, w0 - 0.2, AMBER)
	kit.lamp(lamp, Enum.NormalId.Back, AMBER, 0.8, 8, 140)
	-- Верхняя направляющая под трубами коридора: выше верха створки, ниже труб.
	kit.box("LeafTrack", s(near + 0.3), s(far - 0.3), H, H + 0.2, w0 + 0.2, w1, MID)

	-- Рельс по полу и упор в конце хода.
	kit.box("LeafRail", s(near + 0.1), s(far - 0.1), 0, 0.14, w0 + 0.2, w1 - 0.5, MID, DIAMOND)
	kit.box("LeafStop", s(near), s(far), 0, 1.0, w1 - 1.1, w1 - 0.5, BODY)
	kit.box("LeafStopMark", s(near), s(far), 0.45, 0.75, w1 - 0.5, w1 - 0.46, YELLOW, PLASTIC, true)
end

-- Построить модель в локации. Возвращает модель или nil и причину.
function EntranceGate.Build(location)
	if location:FindFirstChild(MODEL_NAME) then
		return location[MODEL_NAME]
	end
	local info, reason = locate(location)
	if not info then
		return nil, reason
	end
	local W, H, D = info.width, info.height, info.depth

	local model = Instance.new("Model")
	model.Name = MODEL_NAME
	local soft = Instance.new("Folder")
	soft.Name = SOFT_NAME
	soft.Parent = model
	local kit = newKit(model, soft)

	kit.frame = info.frame
	labFace(kit, W, H, info.top)
	tunnel(kit, W, H, D)
	-- Створка откатана к стене коридора на стороне +u: там труба идёт выше створки, а у противоположной
	-- стены трубы на высоте створки.
	leaf(kit, W, H, D, 1)

	-- Коридорная облицовка: рамка повёрнута на 180° вокруг вертикали и сдвинута к дальнему
	-- краю стены, так что u зеркален, а w идёт в коридор.
	kit.frame = info.frame * CFrame.new(0, 0, -D) * CFrame.Angles(0, math.pi, 0)
	corridorFace(kit, W, H)
	kit.frame = info.frame

	model.Parent = location

	-- Прежняя створка и уплотнитель больше не нужны: новая модель делает то же самое.
	local corridor = location:FindFirstChild("Corridor")
	local old = corridor and corridor:FindFirstChild("HermeticDoor")
	if old then
		old:Destroy()
	end
	return model
end

return EntranceGate
