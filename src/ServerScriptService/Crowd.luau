-- Толкучка жуков: столкновения врагов между собой и то, на чём жук стоит.
--
-- Модель врага анкорнута и двигается через PivotTo (см. EnemySpawner), физики у неё нет —
-- а значит, не было и столкновений: волна шла одной кучей, жуки стояли внутри друг друга и
-- сливались в одно пятно. Включить вместо этого настоящую физику нельзя: снять якорь значит
-- отдать движение физическому движку, а ходят жуки по маршруту из A*.
--
-- Поэтому коллизия здесь позиционная. Жук раз в кадр отдаёт точку, куда его ведёт маршрут,
-- и получает исправленную — с учётом соседей, края пола и построек. Про маршруты, волны и
-- бой модуль не знает ничего: он только разводит тела и ставит лапы.
--
-- По горизонтали тела непроницаемы: перекрытие снимается вбок, и группа сама расползается
-- по площади. Тело объёмное: от ступней (пивот минус lift) до верха спины (пивот плюс
-- полувысота), спина — купол над следом-капсулой.
--
-- Высота тела — только из лап. У жука столько лап, сколько у модели (FeetLayout), каждая
-- стоит в своей точке мира. Лапа, ушедшая от своего места под телом дальше шага, шагает:
-- встаёт на то, что под новой точкой, — пол или чужую спину, если до неё дотянуться. Лапа
-- не приклеена: сосед ушёл из-под неё — она срывается и ищет опору заново. Тело держится
-- на самом высоком уровне, лапы которого стоят вокруг его центра. Поэтому лапы на одном
-- соседе (сбоку, спереди) тело не поднимают, а на двух соседях с разных сторон —
-- поднимают: жук залезает на спины. Лап вокруг центра нет — жук падает.
--
-- Лапу не ставят на того, чьи лапы стоят на нас: пара «я на тебе, ты на мне» невозможна.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Arena = require(ReplicatedStorage:WaitForChild("Arena"))
local Grid = require(ServerScriptService:WaitForChild("Grid"))
-- Рельеф пола: жук едет по бетону, а тот умеет подниматься и опускаться
-- (ямка Строителя, ландшафт Литосферы). Высотой жука распоряжается толкучка
-- (он может стоять на спине соседа), поэтому и уровень земли читается здесь же.
local ConcreteFloor = require(ServerScriptService:WaitForChild("ConcreteFloor"))
local TowerDebris = require(ServerScriptService:WaitForChild("TowerDebris"))
-- Габариты тела: капсула по ширине корпуса вдоль хода (см. EnemyBody.Footprint).
local EnemyBody = require(ReplicatedStorage:WaitForChild("EnemyBody"))
-- Скорость разворота тела: капсула доворачивает ровно так же, как видимый корпус.
local EnemyGait = require(ReplicatedStorage:WaitForChild("EnemyGait"))

-- Каждый снимает свою половину перекрытия: вторую снимет сосед на своём же кадре. Единица
-- вместо половины — это двойное исправление одной и той же пары, от него куча дрожит.
local SEPARATION_SHARE = 0.5

-- Потолок расталкивания, studs/сек. Снимать глубокое перекрытие целиком за кадр —
-- это рывок-телепорт; с потолком (чуть меньше скорости жука, 15) видно именно толчок.
local PUSH_SPEED = 12

-- Лапы. Шаг — доля высоты пивота (крупный жук шагает шире), лапа шагает, уйдя от своего
-- места под телом дальше шага, и срывается, растянувшись больше чем на OVERREACH шагов.
-- Новую точку лапа берёт с выносом вперёд по ходу (LEAD шага).
local STRIDE = 0.6
local OVERREACH = 1.8
local LEAD = 0.5
-- Лапы шагают двумя группами по очереди (треногами), группа — раз в STEP_INTERVAL секунд.
local STEP_INTERVAL = 0.12
-- Вниз лапа достаёт на LEG_REACH высот пивота, вверх — до верха своей спины.
local LEG_REACH = 1.4
-- Толщина ступни, доля высоты пивота: в щель между телами уже неё лапа до пола не пролезает
-- и ложится на борт соседа. Поэтому в плотной давке лапы встают на соседей, а в просвете — на пол.
local FOOT_RADIUS = 0.2

-- Лапы ниже уровня тела не больше чем на это тоже его держат.
local FOOT_SLACK = 0.25

-- Объёмы двух тел должны пересекаться по высоте хотя бы на столько, чтобы толкаться:
-- ступни стоящего сверху касаются спины нижнего, и это не столкновение.
local VERTICAL_TOLERANCE = 0.1

local CLIMB_SPEED = 4 -- studs/сек вверх: тело поднимается за лапами
local FALL_SPEED = 10 -- studs/сек вниз: опора ушла — жук падает заметно быстрее, чем лез

local DEFAULT_RADIUS = 1.3 -- если у модели нет PrimaryPart и мерить нечего

-- Непроницаемость. Мягкое расталкивание выше разводит толпу красиво, но с потолком
-- скорости: быстрый шаг его пересиливал, и жуки въезжали друг в друга. Поэтому поверх
-- него жёсткое правило — шаг не имеет права сделать перекрытие двух тел глубже, чем
-- оно уже было (и глубже TOUCH_TOLERANCE). Уже существующее перекрытие (спавн в одной
-- точке, падение со спины) не отменяется рывком, а снимается мягким толчком.
local TOUCH_TOLERANCE = 0.02 -- studs: касание, а не перекрытие
local HARD_ITERATIONS = 3
-- Как быстро (stud/сек) жёсткое ограничение съедает уже имеющееся перекрытие: старое
-- перекрытие не консервируется навсегда, а рассасывается, пока есть куда сдвинуться.
local OVERLAP_RELAX_SPEED = 6

-- Запас к радиусу капсулы, studs: видимое тело качается и вздрагивает вокруг маршрутной
-- точки (EnemyGait.carryBody, вздрагивание) — без запаса соседи касались бы с перехлёстом.
local BODY_CLEARANCE = 0.12 -- проходов выталкивания за кадр: сосед, вытолкнувший в третьего

-- Обгон. Упёршись в тело впереди себя, жук не просто встаёт в хвост, а берёт вбок
-- (доля перекрытия, переводимая в боковой шаг) — так волна идёт рядами, а не колонной
-- «нос в хвост». Сторона — та, где он и так чуть левее/правее соседа.
local SIDESTEP_SHARE = 0.6
local AHEAD_DOT = -0.3 -- нормаль перекрытия против хода сильнее этого — сосед впереди

-- Запас к поиску соседей рядом, studs.
local SUPPORT_MARGIN = 0.3

-- Лапы не стоят вокруг центра (жук на краю чужой спины) — тело сползает в сторону
-- лап, которым не на что встать, с этой скоростью.
local SLIDE_SPEED = 6

local Crowd = {}

-- Номер забега толкучки: растёт на каждом Clear. Спавн, который ждёт места у пролома,
-- сверяет его, чтобы не досыпать жука в уже следующий забег.
Crowd.epoch = 0

-- Поиск свободного места для появления (см. Crowd.FindFree): кольца с шагом в радиус тела.
local FREE_SEARCH_RINGS = 4

-- Живые жуки. Массив — для перебора всех, словарь — чтобы найти свою запись по модели.
local records = {}
local byModel = {}

-- Соседи ищутся по корзинам BUCKET x BUCKET studs, а не полным перебором: на 100 жуках
-- перебор — 10 000 проверок за кадр, и с объёмными телами толкучка съедала бы кадр сервера.
-- Запись перекладывается в корзину, только когда её центр перешёл границу.
local BUCKET = 4
local buckets = {}
local maxExtent = 0 -- самое далеко торчащее тело: до него и ищется сосед

local function bucketKey(x, z)
	return (math.floor(x / BUCKET) + 32768) * 65536 + math.floor(z / BUCKET) + 32768
end

local function unplace(record)
	local list = record.bucket and buckets[record.bucket]
	if list then
		local index = table.find(list, record)
		if index then
			list[index] = list[#list]
			list[#list] = nil
		end
	end
	record.bucket = nil
end

local function place(record)
	local key = bucketKey(record.x, record.z)
	if record.bucket == key then
		return
	end
	unplace(record)
	local list = buckets[key]
	if not list then
		list = {}
		buckets[key] = list
	end
	table.insert(list, record)
	record.bucket = key
end

-- Все, чей центр может оказаться ближе reach к точке (x, z). Выдаёт кандидатов с запасом
-- (корзины целиком), точное расстояние проверяет вызывающий.
local function around(x, z, reach)
	local found = {}
	local x0, x1 = math.floor((x - reach) / BUCKET), math.floor((x + reach) / BUCKET)
	local z0, z1 = math.floor((z - reach) / BUCKET), math.floor((z + reach) / BUCKET)
	for bx = x0, x1 do
		for bz = z0, z1 do
			local list = buckets[(bx + 32768) * 65536 + bz + 32768]
			if list then
				table.move(list, 1, #list, #found + 1, found)
			end
		end
	end
	return found
end

-- Снять запись совсем: из списка, словаря и корзины.
local function forget(record)
	byModel[record.model] = nil
	local index = table.find(records, record)
	if index then
		table.remove(records, index)
	end
	unplace(record)
end

-- Возрастающий номер. Он же порядок «кто на кого может залезть» (см. шапку) и заодно
-- очерёдность прихода: пришедший позже лезет на того, кто уже топчется у стены.
local nextId = 0

-- Границы берутся по самому краю пола, без отступа на радиус жука. Отступ выглядит
-- аккуратнее, но точка маршрута считается от центра клетки со случайным разбросом и может
-- лежать у самой границы: жук тянулся бы к недостижимой точке вечно — а на клетке выхода
-- это ещё и прорыв, который никогда не случится.
local HALF_CELL = Arena.cellSize / 2
local MIN_X, MAX_X, MIN_Z, MAX_Z

-- Пересчитываются при смене локации (Arena.OnChanged).
local function bindBounds()
	local southWest = Arena.ToWorld(1, 1)
	local northEast = Arena.ToWorld(Arena.cols, Arena.rows)
	MIN_X, MAX_X = southWest.X - HALF_CELL, northEast.X + HALF_CELL
	MIN_Z, MAX_Z = southWest.Z - HALF_CELL, northEast.Z + HALF_CELL
end
bindBounds()
Arena.OnChanged(bindBounds)

-- Спрашивается карта проходимости для тела жука (Grid.GetBlocker), а не занятость
-- самой клетки. На крупной сетке разницы не было: клетка была с жука размером,
-- и его центр у самой границы занятой клетки означал тело вплотную к постройке.
-- На мелкой по одной клетке (0.8) жук въезжал бы в стену почти целиком, пока его центр
-- не дойдёт до её клеток.
--
-- Постройка, под которой этот жук пролезает (подлаз, Grid.FitsUnder), ему не стена:
-- иначе толкучка выпихивала бы мелкого из-под Колбы обратно, куда маршрут его не ведёт.
local function occupied(x, z, me)
	local cx, cz = Arena.ToCell(Vector3.new(x, 0, z))
	local blocker = Grid.GetBlocker(cx, cz)
	return blocker ~= nil and not (me and Grid.FitsUnder(blocker, me.bodyHeight))
end

-- А вот «жук ВНУТРИ постройки» — это уже занятость самой клетки, а не карта для тела.
-- Разница важна для caged ниже: по карте тела жук считался бы «запертым» просто потому,
-- что идёт вплотную к стене (разброс SCATTER как раз сдвигает его туда в узком проходе), —
-- и проверка построек снималась бы с него ровно там, где она нужна, и он бы въехал в стену.
local function insideBuilding(x, z)
	local cx, cz = Arena.ToCell(Vector3.new(x, 0, z))
	return Grid.GetOccupant(cx, cz) ~= nil
end

-- Ближайшие точки двух отрезков на плоскости XZ (Ericson, «Real-Time Collision Detection»).
-- Возвращает квадрат расстояния и обе точки: по ним строится нормаль выталкивания.
local function closestSegments(px, pz, qx, qz, rx, rz, sx, sz)
	local d1x, d1z = qx - px, qz - pz
	local d2x, d2z = sx - rx, sz - rz
	local ex, ez = px - rx, pz - rz
	local a = d1x * d1x + d1z * d1z
	local e = d2x * d2x + d2z * d2z
	local f = d2x * ex + d2z * ez
	local s, t

	if a <= 1e-6 and e <= 1e-6 then
		s, t = 0, 0
	elseif a <= 1e-6 then
		s, t = 0, math.clamp(f / e, 0, 1)
	else
		local c = d1x * ex + d1z * ez
		if e <= 1e-6 then
			t, s = 0, math.clamp(-c / a, 0, 1)
		else
			local b = d1x * d2x + d1z * d2z
			local denom = a * e - b * b
			s = denom > 1e-6 and math.clamp((b * f - c * e) / denom, 0, 1) or 0
			t = (b * s + f) / e
			if t < 0 then
				t, s = 0, math.clamp(-c / a, 0, 1)
			elseif t > 1 then
				t, s = 1, math.clamp((b - c) / a, 0, 1)
			end
		end
	end

	local c1x, c1z = px + d1x * s, pz + d1z * s
	local c2x, c2z = rx + d2x * t, rz + d2z * t
	local dx, dz = c1x - c2x, c1z - c2z
	return dx * dx + dz * dz, dx, dz
end

-- Перекрытие тела me (поставленного в x,z лицом fx,fz) с телом other там, где тот стоит.
-- > 0 — тела входят друг в друга. Вторым и третьим значением — единичная нормаль от
-- соседа к нам: вдоль неё и выталкивается.
local function penetration(me, x, z, fx, fz, other)
	local distSq, nx, nz = closestSegments(
		x + fx * me.back, z + fz * me.back, x + fx * me.front, z + fz * me.front,
		other.x + other.fx * other.back, other.z + other.fz * other.back,
		other.x + other.fx * other.front, other.z + other.fz * other.front
	)
	local reach = me.radius + other.radius
	if distSq >= reach * reach then
		return reach - math.sqrt(distSq), 0, 0
	end

	local distance = math.sqrt(distSq)
	if distance < 1e-3 then
		-- Оси тел пересеклись в точке: направление брать неоткуда, берём его из id —
		-- лишь бы у двоих оно было разным и не менялось от кадра к кадру.
		return reach - distance, math.cos(me.id), math.sin(me.id)
	end
	return reach - distance, nx / distance, nz / distance
end

-- Лапы жука: где каждая стоит под телом в покое (ox — вбок, oz — вдоль хода, в осях модели)
-- и её группа шага. Расстановку снимает сборка модели (EnemyModel, атрибут FeetLayout:
-- "x,z,группа;..."); у модели без неё — шесть лап по бокам корпуса.
local function readFeet(model, record)
	local feet = {}
	local layout = model:GetAttribute("FeetLayout")
	if type(layout) == "string" then
		for x, z, group in string.gmatch(layout, "([%-%d%.]+),([%-%d%.]+),(%d)") do
			table.insert(feet, { ox = tonumber(x), oz = tonumber(z), group = tonumber(group) })
		end
	end
	if #feet < 3 then
		table.clear(feet)
		local side = record.radius * 1.2
		for i, along in { record.front, (record.front + record.back) / 2, record.back } do
			table.insert(feet, { ox = side, oz = along, group = i % 2 + 1 })
			table.insert(feet, { ox = -side, oz = along, group = (i + 1) % 2 + 1 })
		end
	end
	return feet
end

-- Ставит жука в толкучку. Уровень земли берётся из его текущего пивота: высота спавна —
-- забота EnemySpawner, дублировать её здесь константой значит завести второе место,
-- где её надо править.
function Crowd.Add(model)
	local pivot = model:GetPivot()
	local position = pivot.Position
	nextId += 1

	-- Габариты меряются один раз по видимому телу, а не по PrimaryPart: у шаблонного
	-- жука это служебный Root 1.4 studs, и толкучка по нему пускала крупных жуков друг в друга.
	local radius, front, back = EnemyBody.Footprint(model)
	-- Голова модели по +Z, а пивот маршрута развёрнут на 180° (см. EnemySpawner) —
	-- поэтому ход жука это -LookVector.
	local facing = -pivot.LookVector
	facing = Vector3.new(facing.X, 0, facing.Z)
	facing = facing.Magnitude > 1e-3 and facing.Unit or Vector3.zAxis

	local record = {
		model = model,
		id = nextId,
		radius = (radius or DEFAULT_RADIUS) + BODY_CLEARANCE,
		front = front or 0,
		back = back or 0,
		halfHeight = EnemyBody.HalfHeight(model),
		bodyHeight = EnemyBody.TopHeight(model), -- высота спины: пролезет ли под постройкой
		groundY = position.Y,
		-- На сколько пивот жука выше поверхности под ним. Запоминается один раз в
		-- момент появления, а не берётся константой из спавнера: так толкучке не надо
		-- знать про ENEMY_Y, а вылупившийся в яме жук сразу считает свой уровень от дна ямы.
		lift = position.Y - ConcreteFloor.HeightAt(position.X, position.Z),
		x = position.X,
		y = position.Y,
		z = position.Z,
		fx = facing.X,
		fz = facing.Z,
		under = {}, -- [запись] = true: на ком стоит хоть одна лапа
		stepClock = 0,
		stepGroup = 1,
	}
	record.stride = math.max(0.3, record.lift * STRIDE)
	record.footRadius = record.lift * FOOT_RADIUS
	record.feet = readFeet(model, record)
	-- Дальше этого от центра не торчат ни тело, ни лапы: грубый отсев соседей до точной проверки.
	record.extent = math.max(math.abs(record.front), math.abs(record.back)) + record.radius
	for _, foot in record.feet do
		record.extent = math.max(record.extent, math.sqrt(foot.ox * foot.ox + foot.oz * foot.oz) + record.stride)
	end

	maxExtent = math.max(maxExtent, record.extent)

	table.insert(records, record)
	byModel[model] = record
	place(record)
	return record
end

function Crowd.Remove(model)
	local record = byModel[model]
	if not record then
		return
	end

	forget(record)

	-- Стоявшие на нём — падают. Ссылку надо снять сразу: иначе верхний ещё кадр висел бы
	-- на высоте застреленного под ним.
	for _, other in records do
		if other.under[record] then
			other.under[record] = nil
			for _, foot in other.feet do
				if foot.by == record then
					foot.planted, foot.by = false, nil
				end
			end
		end
	end
end

-- Горизонтальное направление или nil, если его нет.
local function flatUnit(direction)
	if not direction then
		return nil
	end
	local length = math.sqrt(direction.X * direction.X + direction.Z * direction.Z)
	if length < 1e-3 then
		return nil
	end
	return direction.X / length, direction.Z / length
end

-- Запомнить позицию, не расталкиваясь. Нужно тому, кто на время выпал из толкучки —
-- жуку, который лезет через преграду (см. EnemySpawner). Его самого толкать некуда — он на
-- стене, и туда его привёл не маршрут, а таймер перелезания. Но соседи обязаны видеть,
-- где он на самом деле: без этого они будут расталкиваться об его призрака у подножия
-- всё время, пока он наверху.
--
-- Высота записывается такая же, какая у него есть: тогда стоящие внизу его не замечают
-- вовсе — тела, чьи объёмы не пересекаются по высоте, не толкаются (см. Resolve).
function Crowd.Park(model, position, facing)
	local record = byModel[model]
	if not record then
		return
	end

	record.x, record.y, record.z = position.X, position.Y, position.Z
	place(record)
	local fx, fz = flatUnit(facing)
	if fx then
		record.fx, record.fz = fx, fz
	end
	-- С чужой спины жук сошёл в тот же момент, когда полез на преграду.
	table.clear(record.under)
	for _, foot in record.feet do
		foot.planted, foot.by = false, nil
	end
end

-- Забывает всех разом — для рестарта забега (WaveRunner.clearArena сносит врагов пачкой,
-- и снимать их по одному значило бы полагаться на то, что ни один не потерян).
function Crowd.Clear()
	table.clear(records)
	table.clear(byModel)
	table.clear(buckets)
	Crowd.epoch += 1
end

-- Отменяет жуков, которые ещё ждут места у пролома (EnemySpawner), не трогая стоящих на поле:
-- промокод STOP обрывает волну, и очередь из неё выйти уже не должна.
function Crowd.CancelPending()
	Crowd.epoch += 1
end

-- Объём тела по высоте: от ступней до верха спины. Ступни — пивот минус lift (на сколько
-- пивот стоит над полом), верх — пивот плюс полувысота корпуса.
local function feetOf(record, y)
	return (y or record.y) - record.lift
end

local function topOf(record, y)
	return (y or record.y) + record.halfHeight
end

-- Стоит ли хоть одна лапа record на target (по прошлому кадру).
local function restsOn(record, target)
	return record.under ~= nil and record.under[target] == true
end

-- Толкаются, только пока объёмы пересекаются по высоте. Ноги в объём входят: под брюхом
-- крупного жука мелкий не проходит, там его лапы. Но если лапы одного стоят на другом,
-- считается только корпус: лапы лежат на спине соседа, а не в нём, и тело над соседом
-- (брюхо выше его спины) с ним уже не сталкивается.
local function overlapsVertically(me, y, other)
	if restsOn(me, other) or restsOn(other, me) then
		return topOf(me, y) - me.halfHeight * 2 < topOf(other) - VERTICAL_TOLERANCE
			and topOf(other) - other.halfHeight * 2 < topOf(me, y) - VERTICAL_TOLERANCE
	end
	return feetOf(me, y) < topOf(other) - VERTICAL_TOLERANCE
		and feetOf(other) < topOf(me, y) - VERTICAL_TOLERANCE
end

-- Высота спины other над точкой (x, z) или nil, если точка не над ним. Спина — купол над
-- следом-капсулой: над хребтом верх тела, к борту ниже. Тот же купол у лап на клиенте
-- (EnemyGait.neighbourBack), чтобы ступни стояли там, где их держит толкучка.
--
-- margin — толщина ступни: ступня, задевшая борт, на пол рядом уже не встаёт, а ложится на
-- край спины (на высоте пивота соседа).
local function shellTop(other, x, z, margin)
	local dx, dz = x - other.x, z - other.z
	local along = math.clamp(dx * other.fx + dz * other.fz, other.back, other.front)
	local px, pz = dx - other.fx * along, dz - other.fz * along
	local across = math.sqrt(px * px + pz * pz)
	local radius = other.radius - BODY_CLEARANCE
	if across >= radius + (margin or 0) then
		return nil
	end
	return other.y + other.halfHeight * math.sqrt(math.max(0, 1 - (across / radius) ^ 2))
end

-- Пол под точкой: бетон (он двигается: ямы Строителя, Литосфера) и обломки турелей поверх.
local function groundAt(x, z)
	return ConcreteFloor.HeightAt(x, z) + TowerDebris.HeightAt(x, z)
end

-- Куда встанет лапа в точке (x, z) у тела на высоте bodyY: высота и сосед, на котором
-- она стоит (nil — пол), или nil, если опоры нет. Лапа встаёт на самое верхнее, что под
-- точкой: чужое тело закрывает пол под собой. Выше своей спины лапа не тянется (тогда
-- точка занята телом, до которого не достать), ниже LEG_REACH — не достаёт.
local function footing(me, x, z, bodyY, nearby)
	local top, by = nil, nil
	for _, other in nearby do
		if other.model.Parent and not restsOn(other, me) then
			local shell = shellTop(other, x, z, me.footRadius)
			if shell and (not top or shell > top) then
				top, by = shell, other
			end
		end
	end
	local lowest = bodyY - me.lift * LEG_REACH
	if top then
		if top <= bodyY + me.halfHeight and top >= lowest then
			return top, by
		end
		return nil
	end
	local ground = groundAt(x, z)
	if ground >= lowest then
		return ground, nil
	end
	return nil
end

-- Лапы из первых count стоят на двух разных соседях, и среди них есть лапы по обе стороны
-- от оси тела (rightX, rightZ — вбок). Так жук упирается в две спины перед собой или с
-- боков и лезет на них, хотя ещё не стоит над ними целиком.
local function onTwo(feet, count, cx, cz, rightX, rightZ)
	local first, second = nil, false
	local left, right = false, false
	for i = 1, count do
		local foot = feet[i]
		if foot.by then
			if not first then
				first = foot.by
			elseif foot.by ~= first then
				second = true
			end
			local side = (foot.x - cx) * rightX + (foot.z - cz) * rightZ
			left = left or side < 0
			right = right or side > 0
		end
	end
	return second and left and right
end

-- Стоят ли точки вокруг центра (cx, cz): центр внутри их выпуклой оболочки, то есть
-- между соседними по углу точками нет разрыва в пол-оборота и больше.
local angles = {}
local function surrounds(points, count, cx, cz)
	if count < 3 then
		return false
	end
	table.clear(angles)
	for i = 1, count do
		local point = points[i]
		local dx, dz = point.x - cx, point.z - cz
		if dx * dx + dz * dz < 1e-4 then
			return true -- лапа прямо под центром
		end
		table.insert(angles, math.atan2(dz, dx))
	end
	table.sort(angles)
	local gap = angles[1] + 2 * math.pi - angles[#angles]
	for i = 2, #angles do
		gap = math.max(gap, angles[i] - angles[i - 1])
	end
	return gap < math.pi - 0.05
end

-- Встанет ли ещё не зарегистрированное тело в точку, ни в кого не въехав. Появиться
-- внутри соседа значило бы начать жизнь с перекрытием, которое потом снимается мягким
-- толчком секундами — ровно то, чего быть не должно.
local function probe(model, position)
	local radius, front, back = EnemyBody.Footprint(model)
	local facing = -model:GetPivot().LookVector
	local fx, fz = flatUnit(facing)
	return {
		id = 0,
		radius = (radius or DEFAULT_RADIUS) + BODY_CLEARANCE,
		front = front or 0,
		back = back or 0,
		halfHeight = EnemyBody.HalfHeight(model),
		bodyHeight = EnemyBody.TopHeight(model), -- высота спины: пролезет ли под постройкой
		y = position.Y,
		groundY = position.Y, -- появляются на земле
		lift = position.Y - ConcreteFloor.HeightAt(position.X, position.Z),
		fx = fx or 0,
		fz = fz or 1,
	}
end

local function fitsProbe(me, x, z)
	if x < MIN_X or x > MAX_X or z < MIN_Z or z > MAX_Z or occupied(x, z, me) then
		return false
	end
	local extent = math.max(math.abs(me.front), math.abs(me.back)) + me.radius
	for _, other in around(x, z, extent + maxExtent) do
		-- Сам себе не помеха: проба места для слезающего несёт его id.
		if other.id ~= me.id and other.model.Parent and overlapsVertically(me, me.y, other)
			and penetration(me, x, z, me.fx, me.fz, other) > TOUCH_TOLERANCE then
			return false
		end
	end
	return true
end

function Crowd.Fits(model, position)
	return fitsProbe(probe(model, position), position.X, position.Z)
end

-- Ближайшая к position точка, куда тело помещается, или nil (ищется по кольцам вокруг).
function Crowd.FindFree(model, position)
	local me = probe(model, position)
	if fitsProbe(me, position.X, position.Z) then
		return position
	end
	for ring = 1, FREE_SEARCH_RINGS do
		local distance = ring * me.radius
		local count = math.max(6, math.ceil(2 * math.pi * distance / me.radius))
		for step = 0, count - 1 do
			local angle = step / count * 2 * math.pi
			local x, z = position.X + math.cos(angle) * distance, position.Z + math.sin(angle) * distance
			if fitsProbe(me, x, z) then
				return Vector3.new(x, position.Y, z)
			end
		end
	end
	return nil
end

-- Куда жук на самом деле помещается. desired — точка, куда его ведёт маршрут (только XZ имеют
-- значение), facing — куда он хочет смотреть. Возвращается точка с учётом соседей, границ
-- и построек — вместе с высотой (по Y жуком распоряжается толкучка: стоять он может и на
-- спине соседа), — и направление, которое телу разрешено: если разворот в тесноте вогнал бы
-- его в соседа, жук остаётся как стоял.
--
-- Незарегистрированный жук проходит насквозь, как и раньше: модуль ни на кого не обязателен.
function Crowd.Resolve(model, desired, dt, facing)
	local me = byModel[model]
	if not me then
		return desired, facing
	end

	local fx, fz = flatUnit(facing)
	if not fx then
		fx, fz = me.fx, me.fz
	else
		-- Разворот — с той же скоростью, что у видимого тела (EnemyGait.TurnStep). Мгновенный
		-- разворот капсулы при медленном развороте корпуса пускал брюшко в соседа на повороте.
		local angle = math.atan2(me.fx * fz - me.fz * fx, me.fx * fx + me.fz * fz)
		local turn = EnemyGait.TurnStep(angle, dt)
		if math.abs(angle) > turn then
			local a = math.sign(angle) * turn
			local c, s = math.cos(a), math.sin(a)
			fx, fz = c * me.fx - s * me.fz, s * me.fx + c * me.fz
		end
	end

	local pushX, pushZ = 0, 0

	-- Соседи, с которыми тело обязано не пересекаться, и насколько они пересекаются уже.
	-- nearby — все, кто рядом: лапа может встать на любого из них.
	local solid, allowed, standing, nearby = {}, {}, {}, {}

	for _, other in around(desired.X, desired.Z, me.extent + maxExtent + SUPPORT_MARGIN) do
		if not other.model.Parent then
			-- Жук мог умереть между кадрами (горение, снаряд) — тогда запись снимает его
			-- собственный поток. Эта же проверка закрывает щель в один кадр между смертью
			-- и снятием: расталкиваться об убитого никто не должен.
			forget(other)
		elseif other ~= me then
			local cx, cz = desired.X - other.x, desired.Z - other.z
			local near = me.extent + other.extent + SUPPORT_MARGIN
			if cx * cx + cz * cz < near * near then
				table.insert(nearby, other)

				if overlapsVertically(me, me.y, other) then
					local overlap, nx, nz = penetration(me, desired.X, desired.Z, fx, fz, other)
					table.insert(solid, other)
					-- Нормаль берётся из того, где мы СТОИМ (уже разведённые прошлым кадром),
					-- а не из desired: шаг быстрого соседа бывает крупнее щели, и нормаль от
					-- desired перевернулась бы — толчок достроил бы проскок насквозь.
					local current, cnx, cnz = penetration(me, me.x, me.z, me.fx, me.fz, other)
					standing[other] = math.max(TOUCH_TOLERANCE, current)
					allowed[other] = math.max(TOUCH_TOLERANCE, current - OVERLAP_RELAX_SPEED * dt)

					if overlap > 0 then
						if current > 0 then
							nx, nz = cnx, cnz
						end

						pushX += nx * overlap * SEPARATION_SHARE
						pushZ += nz * overlap * SEPARATION_SHARE

						-- Упёрся в того, кто впереди, — берёт вбок, а не встаёт в хвост.
						if nx * fx + nz * fz < AHEAD_DOT then
							local sideX, sideZ = -fz, fx
							local offset = (desired.X - other.x) * sideX + (desired.Z - other.z) * sideZ
							local side = offset > 0.05 and 1 or offset < -0.05 and -1 or (me.id % 2 == 0 and 1 or -1)
							pushX += sideX * side * overlap * SIDESTEP_SHARE
							pushZ += sideZ * side * overlap * SIDESTEP_SHARE
						end
					end
				end
			end
		end
	end

	local pushLength = math.sqrt(pushX * pushX + pushZ * pushZ)
	local limit = PUSH_SPEED * dt
	if pushLength > limit then
		pushX, pushZ = pushX / pushLength * limit, pushZ / pushLength * limit
	end

	-- Прошлым кадром лапы не стояли вокруг центра — тело сползает с края.
	if me.slideX then
		pushX += me.slideX * SLIDE_SPEED * dt
		pushZ += me.slideZ * SLIDE_SPEED * dt
	end

	-- Жёсткое выталкивание: сколько бы ни пересилил шаг, тело встаёт вплотную к соседу,
	-- а не в него.
	local x, z = desired.X + pushX, desired.Z + pushZ
	for _ = 1, HARD_ITERATIONS do
		local moved = false
		for _, other in solid do
			local overlap, nx, nz = penetration(me, x, z, fx, fz, other)
			local excess = overlap - allowed[other]
			if excess > 0 then
				x += nx * (excess + 1e-3)
				z += nz * (excess + 1e-3)
				moved = true
			end
		end
		if not moved then
			break
		end
	end

	-- В стену и в постройку толкучка не толкает. Оси проверяются по отдельности: прижатый
	-- к стене жук съезжает вдоль неё, а не застревает целиком из-за одной запертой оси.
	--
	-- Если жук уже стоит ВНУТРИ постройки (её возвели вокруг него), проверка
	-- снимается совсем: иначе она бы его там и заперла, вместо того чтобы вытолкнуть.
	-- Именно внутри, а не «вплотную»: второе в узком проходе происходит со всяким вторым.
	local homeX = math.clamp(desired.X, MIN_X, MAX_X)
	local homeZ = math.clamp(desired.Z, MIN_Z, MAX_Z)
	local caged = insideBuilding(homeX, homeZ)

	x = math.clamp(x, MIN_X, MAX_X)
	if not caged and occupied(x, homeZ, me) then
		x = homeX
	end

	z = math.clamp(z, MIN_Z, MAX_Z)
	if not caged and occupied(x, z, me) then
		z = homeZ
	end

	-- Стена могла вернуть тело в соседа. Тогда шаг не делается вовсе: прошлая позиция
	-- заведомо допустима (allowed считан из неё), и жук просто ждёт кадр.
	for _, other in solid do
		if penetration(me, x, z, fx, fz, other) > standing[other] + 1e-3 then
			x, z = me.x, me.z
			fx, fz = me.fx, me.fz
			break
		end
	end

	-- Лапы. Каждая стоит в своей точке мира, пока может: опора под ней на месте, и тело
	-- не утащило её дальше OVERREACH шагов.
	local rightX, rightZ = fz, -fx -- ось X модели в мире (вперёд — ось Z, голова)
	local moveX, moveZ = x - me.x, z - me.z
	local moved = math.sqrt(moveX * moveX + moveZ * moveZ)
	if moved > 1e-4 then
		moveX, moveZ = moveX / moved, moveZ / moved
	else
		moveX, moveZ = 0, 0
	end
	me.stepClock += dt
	local stepGroup = nil
	if me.stepClock >= STEP_INTERVAL then
		me.stepClock = 0
		me.stepGroup = me.stepGroup == 1 and 2 or 1
		stepGroup = me.stepGroup
	end

	local under = me.under
	table.clear(under)
	for _, foot in me.feet do
		local homeX = x + rightX * foot.ox + fx * foot.oz
		local homeZ = z + rightZ * foot.ox + fz * foot.oz
		local away = 0

		if foot.planted then
			if foot.by then
				-- Лапа на соседе: держит, пока он под ней. Ушёл, умер или сам встал на нас —
				-- лапа срывается.
				local shell = foot.by.model.Parent and not restsOn(foot.by, me)
					and shellTop(foot.by, foot.x, foot.z, me.footRadius)
				if shell then
					foot.y = shell
				else
					foot.planted, foot.by = false, nil
				end
			end
			away = math.sqrt((foot.x - homeX) ^ 2 + (foot.z - homeZ) ^ 2)
			if away > me.stride * OVERREACH then
				foot.planted, foot.by = false, nil
			end
		end

		-- Шагает сорванная лапа — сразу, а отставшая — в черёд своей группы.
		if not foot.planted or (away > me.stride and foot.group == stepGroup) then
			local tx = homeX + moveX * me.stride * LEAD
			local tz = homeZ + moveZ * me.stride * LEAD
			local height, by = footing(me, tx, tz, me.y, nearby)
			if not height then
				tx, tz = homeX, homeZ
				height, by = footing(me, tx, tz, me.y, nearby)
			end
			if height then
				foot.planted, foot.x, foot.y, foot.z, foot.by = true, tx, height, tz, by
			else
				foot.planted, foot.by = false, nil
			end
		end

		if foot.planted and foot.by then
			under[foot.by] = true
		end
	end

	-- Тело держится на самом высоком уровне, лапы которого (вместе с теми, что выше) стоят
	-- вокруг центра или стоят на двух соседях по разные борта (onTwo). Лапы выше уровня
	-- поджаты: лапы на одном соседе тело не поднимают, а на двух — поднимают, и жук лезет
	-- им на спины. Таких лап нет — тело падает.
	local planted = {}
	for _, foot in me.feet do
		if foot.planted then
			table.insert(planted, foot)
		end
	end
	table.sort(planted, function(a, b)
		return a.y > b.y
	end)
	local level = nil
	for i, foot in planted do
		local count = i
		while planted[count + 1] and planted[count + 1].y >= foot.y - FOOT_SLACK do
			count += 1
		end
		if surrounds(planted, count, x, z) or onTwo(planted, count, x, z, rightX, rightZ) then
			level = foot.y
			break
		end
	end

	me.slideX, me.slideZ = nil, nil
	local y = me.y
	if level then
		local targetY = level + me.lift
		if y < targetY then
			y = math.min(targetY, y + CLIMB_SPEED * dt)
		elseif y > targetY then
			y = math.max(targetY, y - FALL_SPEED * dt)
		end
	else
		-- Опоры вокруг центра нет: падает и сползает прочь от лап, которые ещё на чём-то стоят.
		y -= FALL_SPEED * dt
		local cx, cz = 0, 0
		for _, foot in planted do
			cx += foot.x - x
			cz += foot.z - z
		end
		local length = math.sqrt(cx * cx + cz * cz)
		if length > 1e-3 then
			me.slideX, me.slideZ = -cx / length, -cz / length
		end
	end
	-- Ниже пола тело не проваливается: брюхом лежит на земле.
	me.groundY = groundAt(x, z) + me.lift
	y = math.max(y, me.groundY - me.lift + me.halfHeight)

	me.x, me.y, me.z = x, y, z
	me.fx, me.fz = fx, fz
	place(me)
	return Vector3.new(x, y, z), Vector3.new(fx, 0, fz)
end

return Crowd
