local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Towers = require(ReplicatedStorage:WaitForChild("Towers"))
local Elements = require(ReplicatedStorage:WaitForChild("Elements"))
-- У турелей со снарядом — только за ShotDamage: сами эффекты вешает снаряд. У площадных
-- (задача #53) снаряда нет вовсе, и весь урон с бронёй и эффектами считается здесь же.
local Effects = require(ReplicatedStorage:WaitForChild("Effects"))
-- Доворот ствола (задача #70): одна формула на сервер и клиент, потому и в ReplicatedStorage.
local Aiming = require(ReplicatedStorage:WaitForChild("Aiming"))
local Arena = require(ReplicatedStorage:WaitForChild("Arena")) -- только за floorY: навес Мортиры целится в пол, а не в тело жука
local Targeting = require(ServerScriptService:WaitForChild("Targeting"))
local EnemyProgress = require(ServerScriptService:WaitForChild("EnemyProgress")) -- только для отладочной печати прицела
local Projectile = require(ServerScriptService:WaitForChild("Projectile"))
local Matter = require(ServerScriptService:WaitForChild("Matter"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local ShotFiredRemote = Remotes:WaitForChild("ShotFired") -- вспышка у дула; урон и его цифра теперь за Projectile
-- Цифра урона над жуком для площадных турелей: у них нет снаряда, который сделал бы это за них.
local DamageDealtRemote = Remotes:WaitForChild("DamageDealt")

local Grid = require(ServerScriptService:WaitForChild("Grid"))
local WaveState = require(ServerScriptService:WaitForChild("WaveState"))
-- Только за Absorb: выросшая Гора забирает труп, из которого выросла.
local Corpses = require(ServerScriptService:WaitForChild("Corpses"))
-- Только за Ruin: разрушенная постройка оставляет руину, из которой строит
-- Строитель (design: alchemy_td_enemies.md, каста 1).
local EnemyStructures = require(ServerScriptService:WaitForChild("EnemyStructures"))

local towersFolder = Workspace:WaitForChild("Towers")
local enemiesFolder = Workspace:WaitForChild("Enemies")


-- Высота преграды Горы при единичном масштабе, studs. Читают её двое: сама модель
-- (buildMountainBarrierModel) и атрибут Height в BuildBarrier, по которому жук решает, лезть
-- ему или грызть (Grid.Crossing). Две копии числа разошлись бы, и жук лез бы мимо вершины.
local MOUNTAIN_HEIGHT = 3.2

-- Стена — кладка мешков с песком. Высота та же, что была у глухого блока (3.2),
-- и та же, что стоит в Towers.Wall.climbHeight: по ней жук решает, лезть ему или грызть,
-- и разойдись они — жук лез бы на высоту, которой у стены нет.
local WALL_HEIGHT = 3.2
-- Рядов мешков в кладке, по шесть в каждом. Четыре, а не три: на трёх мешок выходит
-- почти таким же толстым, как широким, и читается яйцом, а не мешком (видно на плейтесте).
local WALL_ROWS = 4
local SANDBAG_COLOR = Color3.fromRGB(191, 172, 126)

local TOWER_Y = 1.6 -- studs над полом: на этой высоте пивота ножки Колбы стоят на земле

-- Геометрия Колбы, нужная не только сборке модели: по этим же числам считается, куда
-- доворачивается ствол и откуда вылетает снаряд (см. aimBarrel). Одно место на оба
-- применения — чтобы пушка не начала стрелять мимо собственного дула после правки модели.
local SPHERE_HEIGHT = 2.1 -- центр стеклянной сферы над пивотом башни
local BARREL_REACH = 1.6 -- от центра сферы до центра ствола
local BARREL_LENGTH = 1.6 -- длина ствола: дульный срез ещё на полдлины дальше

-- То же самое для остальных ствольных турелей (задача #53), одной таблицей: по этим
-- числам и собирается модель, и считается дульный срез.
--
-- pitch — постоянный угол наклона ствола к горизонту. Есть он — ствол доворачивается на
-- цель только по горизонтали, поднимать и опускать себя не умеет (Мортира) — это и есть
-- причина её слепой зоны, а не отдельная проверка «слишком близко».
local BARRELS = {
	-- Пересчитано под меш из Workspace.ColbaTower (см. colbaMeshTemplate ниже): у него ствол
	-- заметно выше и длиннее прежнего — height/reach подобраны по фактическому положению
	-- дульного среза (кластер MiniBarrel*) над Root в этом меше.
	Ballista = { height = 4.44, reach = 6.3, length = 0.5, clientTracked = true },
	-- Пневматическая винтовка (Инжектор). Числа замерены по готовому шаблону
	-- InjectorTurretTemplate. Прежние (height 2.2, reach 1.7, length 3.0) описывали процедурную
	-- модель из примитивов и уехали вместе с ней в саму buildInjectorModel: та собиралась
	-- ИЗ этих же чисел, и оставь их здесь — откат собрал бы себя по размерам меша.
	--
	-- height — высота оси ствола над пивотом, reach — вынос дульного среза вперёд.
	-- length = 0: reach уже указывает на сам срез, а не на центр ствола.
	--
	-- rig — узлы поворота из самого .glb: горизонталь крутит Pivot_Yaw, вертикаль —
	-- вложенный в него Pivot_Pitch вокруг своей цапфы. Ствол у этого меша не одна деталь,
	-- а полсотни, и пересобрать его одной деталью Barrel нельзя (см. aimRig).
	Injector = {
		height = 5.88, reach = 17.1, length = 0,
		-- Сам риг лежит в Towers.Injector.rig, а не здесь: по нему же клиент крутит пушку
		-- и играет выстрел (BuildingVisuals), и две копии одних и тех же точек разошлись бы
		-- при первой же правке — тот же довод, что у gun Колбы в задаче #77.
		rig = Towers.Injector.rig,
	},
	-- Станция FPV-дронов (бывшая Мортира, изменение 3.1 вики). Заряд уходит не с оси модели,
	-- а из люка на крыше модуля, поэтому вместо одной высоты у неё mount — целая точка
	-- в координатах модели (замерена по HatchLidDisc готового шаблона, см. aimBarrel). Последующим
	-- увеличением станции в 1.75 раза точка переизмерена заново, а не просто умножена на 1.75 —
	-- Model:ScaleTo таскает вокруг пивота, но переизмерение надёжнее догадок.
	-- Прежние числа мортирной шахты (height 1.0, reach 1.3, length 2.6) относились к старой
	-- процедурной модели (buildMortarModel ниже) — она больше не вызывается, как и старая
	-- процедурная Колба после задачи #63.
	-- clearance (задача #75) — высота над пивотом, ниже которой дрон не идёт над своей же
	-- станцией. 11.0 — это крыши модулей плюс запас, а НЕ верх градирни (17.74) и не верх
	-- сенсорной мачты: взять их значило бы задрать трассу на высоту прежнего навеса — ровно то,
	-- чего просили не делать. Замерено прогоном по 216 курсам (3 дистанции × 72 направления):
	-- с нуля до 11.0 задевание корпусов и крыш падает с 64 курсов до 32, а потолок растёт всего
	-- с 12.2 до 13.8 над полом. Градирню это не чинит и починить не может — см. STATE.md.
	-- lid — откинутая створка люка, её дрон облетает. Замерено поворотом папки Hatch
	-- на те самые 100° вокруг HatchHingePin, которые крутит клиент (BuildingVisuals):
	-- открытая створка занимает X -9.91..-4.26, Y 6.94..12.60, Z -1.10..0.44 — то есть стоит
	-- стеной в двух студах от точки пуска, со стороны +Z. Ось петли — локальный X (замерена
	-- той же формулой «самая длинная сторона штыря», что и у клиента), вдоль неё створка
	-- и обходится. Числа подобраны прогоном по 432 трассам (3 дистанции x 72 курса x 2 стороны
	-- ески), а не на глаз: side 4.6 оставлял 13 прошивок, 6.0 — ни одной. lift 3.7, а не меньше,
	-- потому что точка отхода со стороны +X попадала внутрь крыши завода (FacUpper, верх 10.0):
	-- дрон облетал створку и влетал в модуль.
	-- cone — порог по курсу: отход делает только тот, чей курс вообще идёт в сторону створки
	-- (скалярное произведение больше нуля), — уходящему в другую сторону она не мешает вовсе,
	-- и манёвр там читался бы как дёрганье. Половина курсов (117 из 216) отход делает.
	Mortar = { height = 7.06, mount = Vector3.new(-7.082, 7.063, -3.350), reach = 1.4, length = 1.4, pitch = 55, clearance = 11.0,
		lid = { facing = Vector3.new(0, 0, 1), axis = Vector3.new(1, 0, 0), side = 6.0, lift = 3.7, cone = 0 } },
}

-- Готовая модель Колбы (задача #63, замена визуала по FBX-импорту; повторно обновлена под
-- новый меш из Workspace.ColbaTower): клон шаблона, собранного в Studio из очередного
-- FBX-импорта -> ServerStorage.ColbaTurretTemplate. Пивот и масштаб шаблона подогнаны под
-- старую геометрию (see BARRELS.Ballista выше: числа пересчитаны под реальное дуло нового
-- меша). Если шаблон когда-нибудь пропадёт/переименуется, buildTowerModelMesh молча
-- откатывается на процедурную buildTowerModel ниже. Старый шаблон оставлен рядом как
-- ColbaTurretTemplate_OLD_backup, а не удалён.
local colbaMeshTemplate = ServerStorage:WaitForChild("ColbaTurretTemplate", 10)

-- Готовая модель Станции FPV-дронов — тот же приём, что и у Колбы: авторский импорт
-- разобран в шаблон ServerStorage.DroneStationTemplate (плоский список анкорнутых деталей
-- плюс папка Hatch со створкой люка), а сборка — это клон шаблона. Нет шаблона — молча
-- откат на старую процедурную мортиру, чтобы стройка не падала целиком.
local droneStationTemplate = ServerStorage:WaitForChild("DroneStationTemplate", 10)

-- Готовая модель Пневматической винтовки (Инжектора) — тот же приём, что у Колбы
-- и Станции: авторский импорт Injector_Turret.glb разобран в шаблон
-- ServerStorage.InjectorTurretTemplate: обёртки узлов сняты, покраска взята из материалов
-- самого .glb, а риг Pivot_Yaw/Pivot_Pitch сохранён — по нему турель доворачивается
-- (см. aimRig). Нет шаблона — молча откат на процедурный Инжектор, чтобы стройка
-- не падала целиком.
local injectorTemplate = ServerStorage:WaitForChild("InjectorTurretTemplate", 10)

-- Цилиндр вытянут вдоль локальной X, а нужен стоячий — поворот на 90° по Z впечатан в сам
-- CFrame. Отдельное поле Orientation бесполезно: присваивание CFrame стёрло бы поворот.
local STAND_UP = CFrame.Angles(0, 0, math.rad(90))

-- Нейтральный цвет акцентных деталей Колбы (трубки жидкости, N-полоски), пока элемент не
-- залит — см. параметр neutralColor у bindElementTint.
local ACCENT_NEUTRAL_COLOR = Color3.fromRGB(255, 255, 255)

-- Цвет выстрела ПУСТОЙ турели. Задача #69: был тёплый жёлтый, оставшийся от прежнего луча,
-- стал тем же нейтральным белым, которым покрашены акценты пустой Колбы. Снаряд и вспышка
-- обязаны быть одного цвета с турелью, из которой вылетели: жёлтый шар из белой турели
-- читался как чужой. Залитый элемент перебивает нейтральный цвет своим из Elements —
-- по цвету снаряда видно, чем стреляет соседняя башня.
local SHOT_COLOR = ACCENT_NEUTRAL_COLOR

-- Запас дальности снаряда сверх радиуса башни: цель могла стоять у самой кромки радиуса
-- и уходить дальше, а упреждение уводит точку прицеливания ещё на несколько студов за неё.
-- Без запаса снаряд гас бы в воздухе в шаге от врага.
local RANGE_OVERSHOOT = 12

local TowerBuilder = {}

-- Красит детали модели в цвет залитого элемента и прячет их, пока турель пуста. Одна функция
-- на все турели: у каждой своя деталь-«жидкость» (шар в колбе, кольцо на барабане, облако
-- над испарителем), но правило одно — цвет берётся только из Elements[ключ].color, в этом
-- файле цветов элементов нет.
--
-- Реагирует на атрибут Element, а не на факт вызова PourElement — поэтому что-либо другое,
-- сбросившее Element в ничто, тоже корректно спрячет жидкость обратно.
--
-- Жидкость Колбы всегда либо полностью непрозрачна (залита), либо полностью прозрачна
-- (пусто). Промежуточная прозрачность там ломается: два вложенных прозрачных шара с общим
-- центром (жидкость внутри стеклянной Sphere) Roblox сортирует на глаз, и внутренний шар
-- может просто не отрисоваться. Transparency = 0 переводит жидкость в непрозрачный проход
-- рендера, и она гарантированно видна под полупрозрачным стеклом сверху. У облака
-- Испарителя случай обратный — газ обязан просвечивать всегда, поэтому обе прозрачности
-- задаются параметрами.
-- neutralColor — необязательный: если задан, детали красятся в этот цвет, пока турель пуста,
-- а не только прячутся. Нужен деталям Колбы (задача #64), которые обязаны быть видны и без
-- элемента (белыми) — остальные вызовы его не передают и ведут себя как раньше.
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

local function meshMuzzle(tower, gun, aimAngle, aimPitch)
	local nose = tower:FindFirstChild("MiniBarrelC", true)
	local breech = tower:FindFirstChild("BreechNew", true)
	if not (nose and breech and nose:IsA("BasePart") and breech:IsA("BasePart")) then
		return nil -- у турели нет такого меша — пускай считает aimBarrel по числам
	end

	local axis = nose.Position - breech.Position
	if axis.Magnitude < 1e-3 then
		return nil
	end

	local pivot = tower:GetPivot()
	-- Смещение среза в координатах модели — от ПОЛНОГО пивота (с поворотом постройки),
	-- а наведение прикладывается от пивота БЕЗ поворота: ровно та же арифметика, что
	-- у клиента в BuildingVisuals.trackStep — иначе у повёрнутой при стройке турели (задача #76)
	-- поворот считался бы дважды.
	local offset = pivot:PointToObjectSpace(nose.Position + axis.Unit * MUZZLE_LEAD)
	local frame = CFrame.new(pivot.Position) * CFrame.Angles(0, aimAngle, 0)

	if gun and aimPitch then
		-- Ствол качается на цапфах — той же формулой и теми же числами, что рисует клиент.
		local trunnion = CFrame.new(gun.trunnion)
		local pitch = math.clamp(aimPitch - math.rad(gun.restPitch),
			math.rad(gun.pitchMin), math.rad(gun.pitchMax))
		frame = frame * trunnion * CFrame.Angles(pitch, 0, 0) * trunnion:Inverse()
	end

	return (frame * CFrame.new(offset)).Position
end

-- Доворот турели, у которой ствол — не одна деталь, а целый узел импортированного
-- меша (Инжектор). Путь ниже переставляет одну деталь Barrel; здесь целиком
-- поворачиваются два АВТОРСКИХ узла рига: Pivot_Yaw по горизонтали и вложенный
-- в него Pivot_Pitch — по вертикали, вокруг своей цапфы. Имена узлов не выдуманы:
-- они так названы в самом .glb и ровно для этого там стоят.
--
-- Как и у Колбы на клиенте, берётся только ПОЛОЖЕНИЕ пивота, без его собственного
-- поворота: угол наведения мировой, а поворот постройки при стройке (задача #76)
-- уже сидит в запомненной позе детали. Умножай мы на полный пивот — поворот
-- считался бы дважды.
--
-- Исходные позы запоминаются один раз на башню: поворот считается ОТ них, иначе
-- каждый выстрел докручивал бы модель от предыдущего положения. Ключи слабые —
-- снесённая турель уходит из таблицы сама.
-- Наведение турели, у которой ствол — не одна деталь, а узел импортированного меша
-- (Инжектор). Сервер здесь НЕ трогает CFrame ни одной детали: он только говорит
-- атрибутами AimAngle/AimPitch, куда смотреть, а пушку ставит клиент (BuildingVisuals) —
-- тот же приём, что у Колбы с задачи #70. До этого сервер переставлял детали сам,
-- и анимация выстрела на клиенте дралась бы с ним за один и тот же CFrame.
--
-- Возвращает мировую точку дульного среза, посчитанную тем же углом, который уехал
-- клиенту: разойдись они — снаряд вылетал бы из воздуха рядом со стволом, ровно
-- как было у Колбы до задачи #77.
--
-- Порога на публикацию угла (AIM_PUBLISH_STEP у publishAim) здесь не нужно: эта
-- функция зовётся ровно в момент выстрела, а не двадцать раз в секунду.
-- Сектор обстрела (Towers[тип].arc): ствол не выходит за половину сектора от фронта
-- ПОСТРОЙКИ, а не от мира: повернуть турель при стройке можно (задача #76).
-- Страховка к тому же сектору в Targeting: туда цель вне сектора вообще не попадает,
-- но упреждение уводит точку прицела дальше самой цели и может вынести её за край.
local function clampArc(tower, yaw, arc)
	if not arc then
		return yaw
	end
	local look = tower:GetPivot().LookVector
	local facing = math.atan2(-look.X, -look.Z)
	local half = math.rad(arc) / 2
	return facing + math.clamp(Aiming.Delta(facing, yaw), -half, half)
end

-- Мировая точка дульного среза турели на риге по УЖЕ посчитанным углам наведения.
-- Та же арифметика, по которой клиент ставит ствол (BuildingVisuals): разойдись они —
-- снаряд вылетал бы из воздуха рядом со стволом, ровно как было у Колбы до задачи #77.
-- Отдача тут не учитывается нарочно: она начинается ПОСЛЕ выстрела и живёт только
-- на клиенте (так же устроен meshMuzzle у Колбы).
local function rigMuzzle(tower, rig, yaw, pitch)
	local base = CFrame.new(tower:GetPivot().Position) * CFrame.Angles(0, yaw, 0)
	local trunnion = CFrame.new(rig.trunnion)
	local gun = base * trunnion * CFrame.Angles(pitch or 0, 0, 0) * trunnion:Inverse()
	return (gun * CFrame.new(rig.muzzle)).Position
end

-- Запасной путь для турели с ригом, но БЕЗ доворота (нет turnSpeed в Towers, то есть
-- нет и aimState): углы считаются тут же и сразу уезжают клиенту. С доворотом углы
-- публикует fireProjectile (publishAim/publishPitch), и сюда управление не доходит.
local function aimRig(tower, rig, direction, arc)
	local flat = Vector3.new(direction.X, 0, direction.Z)
	if flat.Magnitude < 1e-3 then
		return nil -- цель ровно над башней: доворачиваться не на что
	end

	-- Ноль угла — это -Z модели, та же система, что у Aiming.AngleTo.
	local yaw = clampArc(tower, math.atan2(-direction.X, -direction.Z), arc)
	local pitch = math.asin(math.clamp(direction.Y, -1, 1))

	tower:SetAttribute("AimAngle", yaw)
	tower:SetAttribute("AimPitch", pitch)
	return rigMuzzle(tower, rig, yaw, pitch)
end

local function aimBarrel(tower, aimPosition, geometry, towerData)
	geometry = geometry or BARRELS.Ballista
	-- Откуда вылетает снаряд. Обычно это точка на оси башни на высоте height, но у Станции
	-- FPV-дронов люк стоит сбоку, на крыше своего модуля: такой геометрии одной высоты мало,
	-- и она задаёт mount — точку целиком, в координатах модели.
	local center = (tower:GetPivot() * CFrame.new(geometry.mount or Vector3.new(0, geometry.height, 0))).Position

	local delta = aimPosition - center
	if delta.Magnitude < 1e-3 then
		return center -- цель внутри самой башни: стреляем из центра сферы
	end

	local direction
	if geometry.pitch then
		local flat = Vector3.new(delta.X, 0, delta.Z)
		if flat.Magnitude < 1e-3 then
			return center
		end
		local pitch = math.rad(geometry.pitch)
		direction = (flat.Unit * math.cos(pitch) + Vector3.new(0, math.sin(pitch), 0)).Unit
	else
		direction = delta.Unit
	end

	-- У турели с ригом (Инжектор) доворот и дульный срез считаются по самой модели.
	-- Не вышло (откат на процедурную модель — рига в ней нет) — считаем по числам ниже.
	if geometry.rig then
		local muzzle = aimRig(tower, geometry.rig, direction, towerData and towerData.arc)
		if muzzle then
			return muzzle
		end
	end

	if not geometry.clientTracked then
		local barrel = tower:FindFirstChild("Barrel")
		if barrel then
			local barrelCenter = center + direction * geometry.reach
			barrel.CFrame = CFrame.lookAt(barrelCenter, barrelCenter + direction) * CFrame.Angles(0, math.rad(90), 0)
		end
	end

	return center + direction * (geometry.reach + geometry.length / 2)
end

-- Желаемый угол ствола уезжает клиенту атрибутом AimAngle (задача #70): сам поворот
-- рисует BuildingVisuals по той же формуле Aiming, а сервер шлёт только «куда смотреть».
-- Так картинка не может разойтись с тем, куда уходит выстрел: до этого клиент искал ближайшего
-- врага сам и вполне мог выбрать не того, в кого стреляет сервер.
--
-- Атрибут пишется, лишь когда угол заметно изменился: иначе это была бы репликация числа
-- по двадцать раз в секунду на каждую турель ради разницы в сотые доли градуса.
local AIM_PUBLISH_STEP = math.rad(1)

-- Как часто турель пересматривает цель и доворачивается, пока не стреляет. С темпом
-- стрельбы не связано вовсе: выстрелившая турель всё равно ждёт свой 1/fireRate.
local AIM_TICK = 0.05

-- Полуширина «пятна», которое ствол должен накрывать, чтобы выстрел читался как прицельный:
-- радиус жука (1.5) плюс радиус снаряда (0.7), округлённо. По нему считается допуск на
-- доворот: важно не «сколько градусов», а накрывает ли ствол цель. Вблизи те же восемь
-- градусов — это полстуда мимо, вдали — три; без этой поправки турель переставала бы стрелять
-- по жукам, проходящим вплотную: их угловая скорость выше, чем у самой башни.
local AIM_SPAN = 2.2

local function publishAim(tower, desired)
	local previous = tower:GetAttribute("AimAngle")
	if previous == nil or math.abs(Aiming.Delta(previous, desired)) >= AIM_PUBLISH_STEP then
		tower:SetAttribute("AimAngle", desired)
	end
end

-- Вертикальный аналог publishAim (задача #71): тот же порог публикации, но без цикличности
-- Aiming.Delta — угол места не оборачивается через ±180°, обычной разности достаточно.
local function publishPitch(tower, desired)
	local previous = tower:GetAttribute("AimPitch")
	if previous == nil or math.abs(desired - previous) >= AIM_PUBLISH_STEP then
		tower:SetAttribute("AimPitch", desired)
	end
end

-- Ограничения самой турели для Targeting — слепая зона, земля/воздух и радиус кучи.
-- Одно место на все три режима стрельбы, чтобы они не разошлись в том, по кому турель бьёт.
local function aimFilter(towerData, tower)
	local filter = {
		minRange = towerData.minRange,
		targets = towerData.targets,
		groupRadius = towerData.splash and towerData.splash.radius,

		-- Линия огня: сквозь стены, постройки и поднятый пол турель не стреляет.
		--
		-- Исключение — Станция FPV-дронов (fireMode = "drone"): дрон не летит по прямой
		-- из ствола, а выходит из люка и облетает препятствия — ему преграда не помеха.
		-- Признак берётся из режима стрельбы, а не отдельным флагом в таблице: любая
		-- будущая турель на дронах получит то же свойство сама, без правки здесь.
		lineOfSight = towerData.fireMode ~= "drone",
		shooter = tower,
	}

	-- Сектор обстрела (Towers[тип].arc, Инжектор): цель вне сектора турель не выбирает
	-- вовсе. Без этого она «стреляла бы» по врагу за спиной, а ствол, упёртый в край
	-- сектора, смотрел бы в другую сторону — то же расхождение картинки и выстрела,
	-- ради которого доворот вообще считается одной формулой на обеих сторонах.
	--
	-- Центр сектора — фронт САМОЙ ПОСТРОЙКИ, а не мира: повернуть её при стройке
	-- можно (задача #76), и сектор обязан ехать вместе с ней. Нет arc в таблице —
	-- турель бьёт кругом, как и била: поля фильтра просто не появляются.
	if tower and towerData.arc then
		local look = tower:GetPivot().LookVector
		filter.arcCenter = math.atan2(-look.X, -look.Z)
		filter.arc = math.rad(towerData.arc) / 2
	end

	return filter
end

-- Снаряд по прямой (Колба, Инжектор) — ровно то, что делала StartFiring до задачи #53.
--
-- Башня решает только «в кого целиться и чем зарядить»: цель выбирает Targeting по режиму
-- towerData.targeting, а в снаряд кладутся залитый элемент и уже посчитанный урон
-- (Effects.ShotDamage). Самого урона здесь нет: HP цели меняется в момент попадания
-- (см. Projectile), а по дороге снаряд может промазать или задеть вовсе не того, в кого целились.
local function fireProjectile(tower, towerData, elementData, aimState)
	local geometry = BARRELS[tower:GetAttribute("Type")] or BARRELS.Ballista
	local towerPosition = tower:GetPivot().Position

	-- Куда смотрит ствол — часть условий поиска цели (задача #70): у турели с доворотом
	-- цель выбирается ещё и по тому, успеет ли башня на неё повернуться (closestReachable).
	local filter = aimFilter(towerData, tower)
	if aimState then
		filter.facing = aimState.angle
		filter.turnSpeed = towerData.turnSpeed
		filter.turnAccel = towerData.turnAccel
		filter.projectileSpeed = towerData.projectileSpeed
		filter.current = aimState.target -- кого турель ведёт: без этого она мечется по толпе
	end

	local target, distance = Targeting.FindTarget(towerPosition, towerData.range,
		enemiesFolder, towerData.targeting, filter)

	if not (target and target.Parent and (target:GetAttribute("HP") or 0) > 0) then
		if aimState then
			aimState.target = nil

			-- Пред-наводка: даже без цели в радиусе турель заранее поворачивается к ближайшему
			-- жуку на всей арене, чтобы к моменту его входа в радиус ствол уже смотрел в его
			-- сторону, а не начинал доворот с нуля. Радиус не ограничен нарочно — «ближайший»
			-- сам по себе всегда самый актуальный кандидат: не тот, кто дальше, а тот, кто раньше
			-- войдёт в радиус. Не трогает aimState.target — это поле только про цель в
			-- радиусе, по которой гистерезис closestReachable ведёт цель.
			-- Пред-наводка линию огня не спрашивает. Две причины. По сути: ствол ворочается
			-- заранее к тому, кто вот-вот войдёт в радиус, а тот вполне может сейчас идти
			-- за стеной и выйти из-за неё уже открытым. По цене: радиус здесь не ограничен,
			-- и луч на каждого жука арены с каждой молчащей турели — тысячи лучей в секунду
			-- ради одного поворота ствола.
			local aiming = filter.lineOfSight
			filter.lineOfSight = false

			local nearest, nearestDistance = nil, math.huge
			for _, enemy in Targeting.EnemiesInRange(towerPosition, math.huge, enemiesFolder, filter) do
				local enemyDistance = (enemy:GetPivot().Position - towerPosition).Magnitude
				if enemyDistance < nearestDistance then
					nearest, nearestDistance = enemy, enemyDistance
				end
			end

			filter.lineOfSight = aiming

			if nearest then
				local angle = Aiming.AngleTo(towerPosition, nearest:GetPivot().Position)
				if angle then
					-- Пред-наводка тоже сидит в секторе: кандидатов вне него и так отсеивает
					-- фильтр выше, но подрезка здесь стоит дёшево и держит инвариант
					-- «в AimAngle всегда угол из сектора» в одном месте.
					angle = clampArc(tower, angle, towerData.arc)
					aimState.desired = angle
					publishAim(tower, angle)
				end
			end
		end
		return false
	end

	if aimState then
		aimState.target = target
	end

	-- Упреждение считается от центра сферы, а ствол доворачивается уже на готовую точку:
	-- дуло сдвинуто от центра на пару студов, и уточнять прицел по нему — гоняться за
	-- собственным хвостом ради поправки меньше размера самого снаряда.
	local center = (tower:GetPivot() * CFrame.new(0, geometry.height, 0)).Position
	local aim = Projectile.PredictAim(center, target, towerData.projectileSpeed)

	-- Доворот (задача #70). Башня стреляет не в тот миг, когда увидела цель, а когда
	-- ствол на неё смотрит. Целимся в упреждённую точку, а не в самого жука: туда же
	-- уйдёт и снаряд, и ствол должен смотреть туда же, куда уйдёт выстрел.
	--
	-- Угол места запоминается: по нему не только качается картинка на клиенте, но и считается
	-- точка пуска снаряда ниже (meshMuzzle).
	local aimPitch = nil
	if aimState then
		local desired = Aiming.AngleTo(towerPosition, aim)
		if desired then
			-- Сектор обстрела (Инжектор): за край сектора ствол не выходит даже
			-- к упреждённой точке. Заодно это чинит и допуск ниже: требовать от ствола
			-- доехать туда, куда он по сектору доехать не может, значило бы запереть
			-- её стрельбу навсегда.
			desired = clampArc(tower, desired, towerData.arc)
			aimState.desired = desired
			publishAim(tower, desired)

			-- Допуск шире у близкой цели и уже у далёкой — это угловой размер самого жука
			-- (см. AIM_SPAN), а не постоянное число градусов.
			local tolerance = math.max(Aiming.TOLERANCE, math.atan(AIM_SPAN / math.max(distance, 1)))
			if math.abs(Aiming.Delta(aimState.angle, desired)) > tolerance then
				return false -- ещё доворачивается
			end
		end

		-- Вертикаль (задача #71): угол места на ту же упреждённую точку aim, что и по
		-- горизонтали: ствол должен смотреть туда же, куда уйдёт снаряд, а не в тело жука.
		-- Сам снаряд летит по aim независимо от того, довернулся ли меш по вертикали
		-- (Projectile.Fire берёт полностью трёхмерное направление), поэтому задержки выстрела
		-- на этот угол нет — только публикация для картинки.
		aimPitch = Aiming.PitchTo(center, aim)
		-- Пределы хода ствола по вертикали (rig.pitchMin/pitchMax, Инжектор). Подрезается
		-- ОДИН раз и здесь, до публикации: по этому же числу клиент ставит ствол, а ниже
		-- считается точка пуска — две подрезки в разных местах разошлись бы.
		--
		-- Сам снаряд летит по aim, а не по углу ствола (так же, как у Колбы с её
		-- подрезанными цапфами): подрезка — это предел картинки, а не правило стрельбы.
		local rig = geometry.rig
		if rig and rig.pitchMin and rig.pitchMax then
			aimPitch = math.clamp(aimPitch, math.rad(rig.pitchMin), math.rad(rig.pitchMax))
		end
		publishPitch(tower, aimPitch)
	end

	-- Снаряд стартует из НАСТОЯЩЕГО дула меша, а не с оси турели: у Колбы ствол
	-- сдвинут вбок, и точка на оси лежала между колбой и пушкой. У турелей без такого меша
	-- (Инжектор) meshMuzzle отдаёт nil, и всё считается по-старому — aimBarrel им ещё и ствол
	-- доворачивает, этого терять нельзя.
	-- У турели на риге с доворотом (Инжектор) снаряд стартует из дула в ТЕКУЩЕМ его
	-- положении (aimState.angle), а не в желаемом: стрелять она начинает, когда довернулась
	-- в пределах допуска, и этот остаток допуска точка пуска обязана учитывать.
	local muzzle = (aimState and geometry.rig and rigMuzzle(tower, geometry.rig, aimState.angle, aimPitch))
		or (aimState and meshMuzzle(tower, towerData.gun, aimState.angle, aimPitch))
		or aimBarrel(tower, aim, geometry, towerData)
	local color = elementData and elementData.color or SHOT_COLOR

	Projectile.Fire({
		origin = muzzle,
		aim = aim,
		speed = towerData.projectileSpeed,
		radius = towerData.projectileRadius,
		maxDistance = towerData.range + RANGE_OVERSHOOT,
		damage = Effects.ShotDamage(towerData.damage, elementData),
		element = elementData,
		color = color,
		ownerName = tower.Name,
		-- Форма снаряда и пробитие — свойства турели, а не снаряда: лежат в таблице
		-- (Towers[тип].projectileShape / .pierce) и просто передаются дальше. Нет полей —
		-- шар без пробития, то есть ровно то, что было у всех до этого.
		shape = towerData.projectileShape,
		pierce = towerData.pierce,
	})

	-- Третьим аргументом — сама турель (задача #69). По ней клиент находит настоящий дульный
	-- срез меша (CombatFX) и играет отдачу именно той башне, которая выстрелила
	-- (BuildingVisuals). Позиция muzzle остаётся первым аргументом и по-прежнему единственным
	-- источником для турелей без такого меша: сервер не знает, что клиент умеет с моделью.
	ShotFiredRemote:FireAllClients(muzzle, color, tower)

	print(("[%s] выстрел по %s (до выхода %.1f, дистанция %.1f)")
		:format(tower.Name, target.Name, EnemyProgress.Get(target) or 0, distance))

	return true
end

-- Пуск дрона (Станция FPV-дронов). Отличий от обычного выстрела два. Первое: целится не в тело
-- жука, а в точку на полу под ним — дрон подрывается у земли, а не в теле цели. Второе:
-- уронов два, и оба считаются от базовых чисел башни через тот же ShotDamage: элемент множит
-- и прямой удар, и долю по площади — площадь здесь принадлежит турели, а не тому, чем она залита.
--
-- До задачи #75 это называлось навесом и ставило снаряду arc = true. Считается всё то же
-- и теми же числами; поменялась одна строка — траектория (см. Projectile). Откат к мортирной
-- дуге — вернуть там же arc = true вместо drone = true.
local function fireDrone(tower, towerData, elementData)
	local geometry = BARRELS.Mortar
	-- Пивот берётся один раз: по нему считаются и поиск цели, и точка пуска, и обход
	-- створки — всё в одних координатах модели.
	local pivot = tower:GetPivot()
	local target, distance = Targeting.FindTarget(pivot.Position, towerData.range,
		enemiesFolder, towerData.targeting, aimFilter(towerData, tower))

	local hasTarget = target ~= nil and target.Parent ~= nil and (target:GetAttribute("HP") or 0) > 0

	-- Люк Станции FPV-дронов открыт ровно тогда, когда у станции есть цель в радиусе
	-- атаки — то есть тот же поиск, которым она выбирает, куда стрелять: со своей слепой
	-- зоной и со своим «только наземные». Второго поиска ради картинки заводить нельзя:
	-- разойдись они — и люк бы стоял открытым у станции, которая ни по кому не бьёт.
	-- Сама створка едет на клиенте (BuildingVisuals), сервер шлёт только «открыт/закрыт» —
	-- тот же довод, что у Spin и у наведения: каждый кадр гонять CFrame крышки с сервера
	-- значит реплицировать его ради одной картинки.
	if tower:GetAttribute("HatchOpen") ~= hasTarget then
		tower:SetAttribute("HatchOpen", hasTarget)
	end

	if not hasTarget then
		-- Пред-наводка (по образцу Колбы выше, fireProjectile): даже без цели в радиусе атаки
		-- антенна заранее разворачивается к ближайшему жуку на всей арене, чтобы к моменту
		-- его входа в радиус тарелка уже смотрела в его сторону, а не начинала доворот
		-- с нуля. Радиус не ограничен нарочно — тот же довод, что и у Колбы.
		local nearest, nearestDistance = nil, math.huge
		for _, enemy in Targeting.EnemiesInRange(pivot.Position, math.huge, enemiesFolder, aimFilter(towerData, tower)) do
			local enemyDistance = (enemy:GetPivot().Position - pivot.Position).Magnitude
			if enemyDistance < nearestDistance then
				nearest, nearestDistance = enemy, enemyDistance
			end
		end

		if nearest then
			local angle = Aiming.AngleTo(pivot.Position, nearest:GetPivot().Position)
			if angle then
				publishAim(tower, angle)
			end
		end

		return false
	end

	-- Антенна станции смотрит на ту же цель, по которой станция бьёт. Угол — тот же
	-- мировой AimAngle, что и у Колбы, а саму тарелку ведёт клиент (BuildingVisuals) —
	-- тот же довод, что у створки люка: гонять её CFrame с сервера значило бы реплицировать
	-- его каждый кадр ради одной картинки. Второго поиска цели ради антенны нет по той же
	-- причине, что и у люка — разойдись они, и тарелка смотрела бы не на того, кого бьёт.
	-- Обновляется ровно так же часто, как HatchOpen: цикл стрельбы переспрашивает цель каждые
	-- AIM_TICK, а после выстрела спит свой темп — в это время антенна держит прошлый пеленг.
	local bearing = Aiming.AngleTo(pivot.Position, target:GetPivot().Position)
	if bearing then
		publishAim(tower, bearing)
	end

	local center = (pivot * CFrame.new(0, geometry.height, 0)).Position
	local aim = Projectile.PredictAim(center, target, towerData.projectileSpeed)
	local landing = Vector3.new(aim.X, Arena.floorY, aim.Z)
	local muzzle = aimBarrel(tower, landing, geometry)
	local color = elementData and elementData.color or SHOT_COLOR

	-- Отход от откинутой створки: дрон поднимается из шахты и уходит вбок вдоль оси петли,
	-- а не прошивает крышку насквозь. Сторона выбирается та, куда и цель: отход тогда
	-- сразу идёт в счёт пути, а не отматывается назад. Вся геометрия — в координатах модели,
	-- поэтому повёрнутая при стройке станция облетает свою створку так же верно.
	local exit = nil
	local lid = geometry.lid
	if lid then
		local course = pivot:VectorToObjectSpace(landing - muzzle)
		local flatCourse = Vector3.new(course.X, 0, course.Z)
		if flatCourse.Magnitude > 1e-3 and flatCourse.Unit:Dot(lid.facing) > lid.cone then
			local side = course:Dot(lid.axis) >= 0 and 1 or -1
			exit = (pivot * CFrame.new(geometry.mount
				+ lid.axis * (side * lid.side)
				+ Vector3.new(0, lid.lift, 0))).Position
		end
	end

	Projectile.Fire({
		origin = muzzle,
		aim = landing,
		drone = true,
		-- Высота собственных крыш: дрон выходит из шахты над них, а не сквозь градирню.
		clearance = (pivot * CFrame.new(0, geometry.clearance, 0)).Position.Y,
		exit = exit,
		speed = towerData.projectileSpeed,
		radius = towerData.projectileRadius,
		damage = Effects.ShotDamage(towerData.damage, elementData),
		splash = {
			radius = towerData.splash.radius,
			damage = Effects.ShotDamage(towerData.splash.damage, elementData),
		},
		targets = towerData.targets,
		element = elementData,
		color = color,
		ownerName = tower.Name,
	})

	ShotFiredRemote:FireAllClients(muzzle, color, tower)

	print(("[%s] дрон пошёл на %s (дистанция %.1f)"):format(tower.Name, target.Name, distance))
	return true
end

-- Площадь вокруг себя (Испаритель, Бур, Центрифуга). Турель ни в кого не целится
-- и ничего не выпускает: раз в тик она бьёт СРАЗУ по всем подходящим целям в радиусе.
-- Снаряда нет, поэтому урон, броня и эффекты считаются здесь теми же Effects, что и при
-- попадании снаряда — модель урона одна на всех.
--
-- Центр зоны не всегда совпадает с турелью: areaHeight поднимает его над ней (облако
-- Испарителя — на 6 studs). От облака до земли при этом ближе, чем его радиус (6.2 против 8),
-- поэтому наземных под собой облако не трогает именно из-за фильтра targets = "air",
-- а не из-за высоты: убери фильтр — и начнёт трогать.
--
-- Лога на тик нет нарочно: пять тиков в секунду у Испарителя превратили бы вывод в поток,
-- в котором не видно ничего остального. Цифры урона над жуками показывает DamageDealt.
local function fireArea(tower, towerData, elementData)
	local center = tower:GetPivot().Position
	if towerData.areaHeight then
		center += Vector3.new(0, towerData.areaHeight, 0)
	end

	local targets = Targeting.EnemiesInRange(center, towerData.range, enemiesFolder, aimFilter(towerData, tower))
	if #targets == 0 then
		return false
	end

	local damage = Effects.ShotDamage(towerData.damage, elementData)
	for _, enemy in targets do
		-- Проверка повторяется внутри цикла: список снят один раз, а эффекты предыдущей
		-- цели (цепочка, детонация) вполне могли убить следующую ещё до того, как до неё дошла очередь.
		if enemy.Parent and (enemy:GetAttribute("HP") or 0) > 0 then
			-- Откуда ударили — для лобового щита Щитоносца, точно так же, как это
			-- делает снаряд (см. Projectile.dealDamage). У площадной это центр её зоны.
			enemy:SetAttribute("HitFrom", center)
			local dealt = Effects.HitDamage(enemy, elementData, damage)
			if dealt > 0 then
				local hp = math.max(0, (enemy:GetAttribute("HP") or 0) - dealt)
				enemy:SetAttribute("HP", hp)
				DamageDealtRemote:FireAllClients(enemy:GetPivot().Position, dealt, true)
			end
			if elementData then
				-- Четвёртым — откуда ударили: притяжение (Воздух и вся его ветка) тянет
				-- к стрелявшей турели, а у площадной это центр её зоны, а не сам пивот:
				-- облако Испарителя висит над ней.
				Effects.Apply(enemy, elementData, dealt, center)
			end
		end
	end

	return true
end

local FIRE_MODES = {
	projectile = fireProjectile,
	drone = fireDrone, -- до задачи #75 ключ звался mortar, а функция — fireMortar
	area = fireArea,
}

-- Запускает боевой цикл башни. Работает для любой построенной башни независимо —
-- каждая вызывает это отдельно при постройке.
--
-- Здесь осталось только общее для всех турелей: залитый элемент, разгон Воздуха и темп.
-- Сам удар — за fireMode (FIRE_MODES выше): он возвращает, состоялся ли выстрел, и больше
-- цикл о нём ничего не знает.
function TowerBuilder.StartFiring(tower, towerType)
	local towerData = Towers[towerType]
	assert(towerData, ("[TowerBuilder] неизвестный тип башни: %s"):format(tostring(towerType)))

	local fire = FIRE_MODES[towerData.fireMode or "projectile"]
	assert(fire, ("[TowerBuilder] неизвестный режим стрельбы: %s"):format(tostring(towerData.fireMode)))

	task.spawn(function()
		-- Темп бывает дробным (0.2 у Инжектора, 1.5 у Центрифуги), поэтому %.2f, а не %d:
		-- целочисленный формат на дроби в Luau падает с ошибкой, а не округляет.
		print(("[%s] готова: радиус %s, темп %.2f/сек, базовый урон %d, режим %s")
			:format(
				tower.Name,
				towerData.minRange and ("%d–%d"):format(towerData.minRange, towerData.range) or tostring(towerData.range),
				towerData.fireRate,
				towerData.damage,
				towerData.fireMode or "projectile"
			))

		-- Разгон воздуха (fireRateRamp): выстрелы подряд и момент последнего выстрела. Живёт
		-- здесь, а не в Effects — это тайминг стрельбы конкретной башни, а не эффект на цели.
		local rampStreak = 0
		local lastFireClock = os.clock()

		-- Состояние доворота ствола (задача #70) живёт здесь, а не в общей таблице по башням:
		-- оно нужно ровно на время жизни турели, а этот цикл и есть её жизнь — снесли постройку,
		-- кончился цикл, и убирать за собой нечего. Заводится только у турели с turnSpeed в Towers;
		-- у остальных aimState — nil, и все ветки доворота просто не включаются.
		--
		-- Стартовый угол — фронт САМОЙ ПОСТРОЙКИ, а не мировой ноль: повёрнутая при
		-- стройке турель (задача #76) считала бы, что ствол смотрит в мировой ноль,
		-- и на первой же цели прокручивалась бы к ней от чужого направления. Клиент
		-- стартует именно оттуда (BuildingVisuals, restYaw), и две стороны обязаны совпадать.
		local aimState = nil
		if towerData.turnSpeed then
			local look = tower:GetPivot().LookVector
			aimState = { angle = math.atan2(-look.X, -look.Z), velocity = 0, clock = os.clock() }
		end

		while tower.Parent do
			-- Ствол едет к прошлой выбранной точке независимо от того, стреляли мы или нет:
			-- пока он в пути, выстрелов не будет, а угол меняться обязан.
			if aimState then
				local now = os.clock()
				aimState.angle, aimState.velocity = Aiming.Step(aimState.angle, aimState.velocity,
					aimState.desired or aimState.angle, now - aimState.clock,
					towerData.turnSpeed, towerData.turnAccel)
				aimState.clock = now
			end

			local elementKey = tower:GetAttribute("Element")
			local elementData = elementKey and Elements[elementKey]
			local ramp = elementData and elementData.fireRateRamp

			-- Лицехват присосался (Enemies.Facehugger, см. EnemySpawner.flyToTurret): турель вообще не ищет
			-- и не бьёт цель, пока висит атрибут Suppressed — его ставит и снимает сам Лицехват.
			-- Площадных это касается так же: глушится любая турель, а не только стреляющая снарядом.
			local fired = false
			if not tower:GetAttribute("Suppressed") then
				fired = fire(tower, towerData, elementData, aimState)
			elseif tower:GetAttribute("HatchOpen") then
				-- Заглушённая Лицехватом станция никого не выпускает — значит и люк закрыт.
				-- Формально это общий цикл, но атрибут есть только у неё: без этой ветки люк
				-- застывал бы открытым на всё время, пока висит Suppressed: fireMortar,
				-- который его закрывает, в этот момент вообще не вызывается.
				tower:SetAttribute("HatchOpen", false)
			end

			if not ramp then
				-- Разгон осмыслен только пока залит элемент с fireRateRamp: вынули Воздух — следующая
				-- заливка начинает раскрутку с нуля, а не с прежнего темпа.
				rampStreak = 0
			elseif not fired and (os.clock() - lastFireClock) > ramp.resetAfter then
				rampStreak = 0
			end

			if fired then
				lastFireClock = os.clock()
				if ramp then
					rampStreak += 1
				end
			end

			-- Скорострельность пересчитывается каждый выстрел: элемент можно залить или вынуть
			-- на лету, бонус должен подхватываться сразу, а не со следующей башни. У Воздуха
			-- вместо плоского множителя — разгон: темп растёт на ramp.step за каждый выстрел
			-- подряд, до потолка ramp.max.
			local fireRate = towerData.fireRate
			if elementData and elementData.fireRateBonus then
				-- Бонус бывает отрицательным (Гора: −0.6, то есть выстрел раз в 2.5 сек) —
				-- это «цена в темпе стрельбы» из документа, отдельного поля под неё не нужно.
				fireRate *= (1 + elementData.fireRateBonus)
			elseif ramp then
				-- exponent > 1 делает разгон нелинейным (Торнадо): первые выстрелы прибавляют
				-- меньше, чем у Ветра, зато к пятому подряд темп уже у потолка. ramp.base
				-- переопределяет точку отсчёта вместо towerData.fireRate (Извержение: старт выше,
				-- шаг почти незаметный, не как у Воздуха) — без него все четыре разгонных
				-- элемента стартуют с одной и той же точки.
				fireRate = math.min((ramp.base or towerData.fireRate) + ramp.step * rampStreak ^ (ramp.exponent or 1), ramp.max)
			end
			-- Нижняя граница — страховка от опечатки в таблице: fireRateBonus <= −1 дал бы
			-- ноль или минус, а task.wait от этого завис башню навсегда.
			-- Отстрелявшаяся турель ждёт свой полный темп — скорострельность от этой задачи
			-- не меняется. А вот НЕ отстрелявшаяся (нет цели, ствол ещё в пути или висит
			-- Лицехват) переспрашивает часто: иначе доворот стоил бы ей целого выстрела —
			-- ствол доезжает через полсекунды после проверки, а ждать её пришлось бы секунду.
			task.wait(fired and (1 / math.max(fireRate, 0.05)) or AIM_TICK)
		end
	end)
end

-- Общая часть постройки: ставит модель в клетку сетки, занимает клетку, запускает
-- автонаведение. Материю не трогает — этим отдельно занимаются Build/BuildFree.
--
-- Клетка запоминается атрибутами CellX/CellZ, чтобы освобождать её по самой постройке,
-- без обратного поиска по всей сетке. Атрибут Type хранит ключ из Towers: по нему видно,
-- что это за постройка, без разбора её имени или содержимого.
--
-- Стреляет ли постройка, решает всё тот же один признак — есть ли у типа fireRate (см. Towers);
-- модель берётся из MODELS по типу.
-- Радиус следа постройки в клетках — по её ФАКТИЧЕСКОМУ размеру (footprint в Towers),
-- а не по общему шагу сетки. Одно место на всех, кто занимает и проверяет клетки:
-- разойдись проверка «свободно» с записью занятости — и постройка встала бы туда,
-- куда сама себя не пустила.
local function reachOf(towerType)
	local towerData = Towers[towerType]
	return Grid.ReachFor(towerData and towerData.footprint)
end

-- Поворот постройки — четвертями, а не произвольным углом: след постройки в клетках —
-- квадрат по footprint (Grid.ReachFor), и только поворот на 90° оставляет его тем же самым.
-- Поверни мы станцию на 45° — её платформа торчала бы из занятых клеток углами, и проверка
-- «свободно» разошлась бы с тем, что реально стоит на полу.
local function turnCFrame(turn)
	return CFrame.Angles(0, math.rad(90 * ((turn or 0) % 4)), 0)
end

local function placeTower(cx, cz, towerType, turn)
	local towerData = Towers[towerType]
	local build = MODELS[towerType] or (towerData.fireRate and buildTowerModel or buildWallModel)
	local tower = build(towerData)
	tower.Name = ("%s (%d,%d)"):format(towerData.name, cx, cz)
	tower:PivotTo(CFrame.new(Grid.ToWorld(cx, cz) + Vector3.new(0, TOWER_Y, 0)) * turnCFrame(turn))
	tower:SetAttribute("Type", towerType)
	tower:SetAttribute("CellX", cx)
	tower:SetAttribute("CellZ", cz)
	tower:SetAttribute("MaxHP", towerData.hp)
	tower:SetAttribute("HP", towerData.hp)
	-- Стойкость к грызне (Бур, задача #53) — атрибутом, а не поиском в Towers: её читают
	-- и сама грызня (EnemySpawner), и цена клетки в поиске пути (Grid) — оба и так смотрят
	-- на саму постройку, а не на её тип.
	if towerData.chewResist then
		tower:SetAttribute("ChewResist", towerData.chewResist)
	end
	-- Высота преграды — атрибутом по той же причине, что и стойкость к грызне: её читают
	-- и цена клетки в поиске пути, и сам жук в момент, когда упёрся (Grid.Crossing) — оба
	-- смотрят на саму постройку, а не на её тип. Нет climbHeight в таблице — нет атрибута,
	-- и постройка непреодолима сверху.
	if towerData.climbHeight then
		tower:SetAttribute("Height", towerData.climbHeight)
	end
	tower.Parent = towersFolder

	Grid.Occupy(cx, cz, tower, reachOf(towerType))

	-- Разрушенная постройка освобождает клетку. Grid.Free шлёт Changed, и все живые враги
	-- пересчитывают маршрут: проход, который они грызли, только что открылся. Порядок важен:
	-- сначала убираем модель (цикл стрельбы живёт на tower.Parent), потом освобождаем клетку.
	tower:GetAttributeChangedSignal("HP"):Connect(function()
		if tower.Parent and (tower:GetAttribute("HP") or 0) <= 0 then
			print(("[Постройка] %s разрушена, клетка (%d, %d) снова свободна")
				:format(tower.Name, cx, cz))
			-- Руина на месте постройки: Строитель «ест обломки стены или мебели» и строит
			-- из них (design: alchemy_td_enemies.md, каста 1). Размер кучи и запас материала
			-- в ней считаются от прочности снесённого: Стена оставляет больше, чем Испаритель.
			EnemyStructures.Ruin(tower:GetPivot().Position, tower:GetAttribute("MaxHP"))
			tower:Destroy()
			Grid.Free(cx, cz)
		end
	end)

	if towerData.fireRate then
		TowerBuilder.StartFiring(tower, towerType)
	end

	return tower
end

-- Ставит башню типа towerType в свободную клетку за материю. Возвращает (true, tower) либо
-- (false, причина) при отказе. Башня ставится пустой — элемент заливается отдельно через PourElement.
--
-- Запереть арену наглухо постройками разрешено и нигде не проверяется: занятая клетка для
-- поиска пути дорогая, но проходимая, и полное запирание ведёт к прогрызанию, а не к тупику.
--
-- turn (0..3) — на сколько четвертей повернута постройка. На занятость клеток не влияет
-- вовсе (след квадратный и при повороте на 90° тот же), поэтому все проверки ниже
-- о нём не знают и знать не должны.
function TowerBuilder.Build(cx, cz, towerType, turn)
	local towerData = Towers[towerType]
	assert(towerData, ("[TowerBuilder] неизвестный тип башни: %s"):format(tostring(towerType)))

	-- Стройка — только между волнами: пока волна идёт, WaveRunner держит WaveState активным.
	-- BuildFree и BuildBarrier эту проверку намеренно не проходят — первая ставит стартовую
	-- башню ещё до начала волн, вторая встаёт от смерти жука посреди волны, это не действие игрока.
	if WaveState.IsActive() then
		return false, "во время волны строить нельзя"
	end

	-- Не InBounds, а FitsBuilding: постройка крупнее клетки, и у самого края поля клетка
	-- свободна, а след уже свисает за край.
	local reach = reachOf(towerType)
	if not Grid.FitsBuilding(cx, cz, reach) then
		return false, "постройка сюда не помещается"
	end
	if Grid.IsEntranceCell(cx, cz, reach) then
		return false, "в проломе строить нельзя"
	end
	if Grid.IsExitCell(cx, cz, reach) then
		return false, "на выходе строить нельзя"
	end
	-- Стол проверяется по всему его габариту: раньше турель вставала в край столешницы.
	if Grid.IsTableCell(cx, cz, reach) then
		return false, "на столе строить нельзя"
	end
	if not Grid.IsFree(cx, cz, reach) then
		return false, "клетка занята"
	end
	if not Matter.Spend(towerData.cost) then
		return false, ("не хватает материи (нужно %d, есть %d)"):format(towerData.cost, Matter.Get())
	end

	local tower = placeTower(cx, cz, towerType, turn)
	print(("[Постройка] %s поставлена в клетку (%d, %d) за %d материи, поворот %d°")
		:format(tower.Name, cx, cz, towerData.cost, 90 * ((turn or 0) % 4)))
	return true, tower
end

-- То же самое, но бесплатно — для стартовой башни (см. TowerBootstrap). Отдельная функция,
-- а не флаг в Build, чтобы нельзя было случайно вызвать бесплатную постройку из игры.
function TowerBuilder.BuildFree(cx, cz, towerType)
	local reach = reachOf(towerType)
	if not Grid.FitsBuilding(cx, cz, reach) then
		return false, "постройка сюда не помещается"
	end
	if Grid.IsEntranceCell(cx, cz, reach) then
		return false, "в проломе строить нельзя"
	end
	if Grid.IsExitCell(cx, cz, reach) then
		return false, "на выходе строить нельзя"
	end
	if Grid.IsTableCell(cx, cz, reach) then
		return false, "на столе строить нельзя"
	end
	if not Grid.IsFree(cx, cz, reach) then
		return false, "клетка занята"
	end

	local tower = placeTower(cx, cz, towerType)
	print(("[Постройка] %s поставлена в клетку (%d, %d) бесплатно (стартовая)")
		:format(tower.Name, cx, cz))
	return true, tower
end

-- Заливает элемент в построенную турель. Пустая турель стреляет базовым уроном башни;
-- элемент множит его своим тиром и своим свойством и вешает эффекты поверх.
function TowerBuilder.PourElement(tower, elementKey)
	if not Elements[elementKey] then
		return false, "нет такого элемента"
	end

	-- Элемент принимают только турели: у стены нет fireRate, и лить в неё некуда.
	local towerData = Towers[tower:GetAttribute("Type")]
	if towerData and not towerData.fireRate then
		return false, ("%s элемент не принимает"):format(towerData.name)
	end

	tower:SetAttribute("Element", elementKey)
	print(("[%s] залит элемент %s"):format(tower.Name, Elements[elementKey].name))
	return true
end

-- Преграда Горы: не покупается и не встаёт в очередь на Matter.Spend — это последействие
-- смерти жука, а не постройка игрока (см. Effects.OnKillBarrier). Молча отказывается, если
-- клетка занята, в проломе, на выходе или вне арены — на месте смерти вполне может уже стоять
-- другая постройка или сам пролом, и тогда гора просто не появляется, без ошибки игроку.
function TowerBuilder.BuildBarrier(cx, cz, hp, scale)
	if not Grid.FitsBuilding(cx, cz) or Grid.IsEntranceCell(cx, cz) or Grid.IsExitCell(cx, cz)
		or Grid.IsTableCell(cx, cz)
		or not Grid.IsFree(cx, cz) then
		return false
	end

	local tower = buildMountainBarrierModel(scale)
	tower.Name = ("Гора (%d,%d)"):format(cx, cz)
	tower:PivotTo(CFrame.new(Grid.ToWorld(cx, cz) + Vector3.new(0, TOWER_Y, 0)))
	tower:SetAttribute("Type", "MountainBarrier")
	-- Крошка от Мини — и низкая, и хлипкая (дизайн, раздел 1.3): обе метрики идут от HP
	-- убитого. Прочность — это hp выше, высота — это scale, и отсюда же время перелезания.
	tower:SetAttribute("Height", MOUNTAIN_HEIGHT * scale)
	tower:SetAttribute("CellX", cx)
	tower:SetAttribute("CellZ", cz)
	tower:SetAttribute("MaxHP", hp)
	tower:SetAttribute("HP", hp)
	tower.Parent = towersFolder

	Grid.Occupy(cx, cz, tower)

	-- Та же связка HP → Destroy → Grid.Free, что и у любой другой постройки (см. placeTower):
	-- гору можно прогрызть точно так же, как Стену, у неё просто нет fireRate и цены.
	tower:GetAttributeChangedSignal("HP"):Connect(function()
		if tower.Parent and (tower:GetAttribute("HP") or 0) <= 0 then
			print(("[Постройка] %s разрушена, клетка (%d, %d) снова свободна")
				:format(tower.Name, cx, cz))
			-- Гора — такая же постройка, как остальные, и руину оставляет точно так же:
			-- «любая постройка» — значит и та, что выросла из трупа.
			EnemyStructures.Ruin(tower:GetPivot().Position, tower:GetAttribute("MaxHP"))
			tower:Destroy()
			Grid.Free(cx, cz)
		end
	end)

	-- Гора поглощает труп (подтверждённое решение автора): игрок видит связку «упал крупный —
	-- выросла стена», и моделей на поле меньше. Радиус — половина следа горы в студах.
	Corpses.Absorb(tower:GetPivot().Position, Grid.BuildSize * scale / 2)

	print(("[Гора] выросла в клетке (%d, %d): %d HP, масштаб %.2f"):format(cx, cz, hp, scale))
	return true, tower
end

-- Effects не может звать Grid/TowerBuilder напрямую — TowerBuilder уже требует Effects,
-- и обратный require зациклил бы модули. Поэтому Гора сообщает о преграде через колбек,
-- как EnemySpawner.OnBreach: назначается один раз при загрузке этого модуля.
Effects.OnKillBarrier = function(position, hp, scale)
	-- Клетка смерти поджимается так, чтобы след горы поместился на поле: жук вполне
	-- может умереть в двух клетках от края, а раньше гора там вставала — клетка была
	-- ровно постройкой, и свисать было нечему.
	local cx, cz = Grid.ClampBuildCell(Grid.ToCell(position))
	TowerBuilder.BuildBarrier(cx, cz, hp, scale)
end

return TowerBuilder
