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
-- Сборка моделей турелей, стены и горного барьера (процедурные и из мешей-шаблонов) — в модуле TowerModels.
local TowerModelsExports = require(script.Parent:WaitForChild("TowerModels"))({Elements = Elements, SPHERE_HEIGHT = SPHERE_HEIGHT, STAND_UP = STAND_UP, BARREL_LENGTH = BARREL_LENGTH, BARREL_REACH = BARREL_REACH, colbaMeshTemplate = colbaMeshTemplate, ACCENT_NEUTRAL_COLOR = ACCENT_NEUTRAL_COLOR, Grid = Grid, WALL_HEIGHT = WALL_HEIGHT, WALL_ROWS = WALL_ROWS, SANDBAG_COLOR = SANDBAG_COLOR, MOUNTAIN_HEIGHT = MOUNTAIN_HEIGHT, TOWER_Y = TOWER_Y, BARRELS = BARRELS, droneStationTemplate = droneStationTemplate, injectorTemplate = injectorTemplate})
local MUZZLE_LEAD = TowerModelsExports.MUZZLE_LEAD
local MODELS = TowerModelsExports.MODELS
local buildTowerModel = TowerModelsExports.buildTowerModel
local buildWallModel = TowerModelsExports.buildWallModel
local buildMountainBarrierModel = TowerModelsExports.buildMountainBarrierModel
-- Наведение и стрельба турелей: дуло, сектор, снаряд, дрон, облако, TowerBuilder.StartFiring — в модуле TowerFiring.
require(script.Parent:WaitForChild("TowerFiring"))({MUZZLE_LEAD = MUZZLE_LEAD, Aiming = Aiming, BARRELS = BARRELS, TowerBuilder = TowerBuilder, Targeting = Targeting, enemiesFolder = enemiesFolder, Projectile = Projectile, SHOT_COLOR = SHOT_COLOR, RANGE_OVERSHOOT = RANGE_OVERSHOOT, Effects = Effects, ShotFiredRemote = ShotFiredRemote, EnemyProgress = EnemyProgress, Arena = Arena, DamageDealtRemote = DamageDealtRemote, Towers = Towers, Elements = Elements})
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
