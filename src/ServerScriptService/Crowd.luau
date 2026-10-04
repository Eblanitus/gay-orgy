-- Толкучка жуков: столкновения врагов между собой — расталкивание в стороны, а когда
-- расталкиваться некуда, залезание друг другу на спину.
--
-- Модель врага анкорнута и двигается через PivotTo (см. EnemySpawner), физики у неё нет —
-- а значит, не было и столкновений: волна шла одной кучей, жуки стояли внутри друг друга и
-- сливались в одно пятно. Включить вместо этого настоящую физику нельзя: снять якорь значит
-- отдать движение физическому движку, а ходят жуки по маршруту из A*.
--
-- Поэтому коллизия здесь позиционная. Жук раз в кадр отдаёт точку, куда его ведёт маршрут,
-- и получает исправленную — с учётом соседей, края пола и построек. Про маршруты, волны и
-- бой модуль не знает ничего: он только разводит тела.
--
-- Оба нужных поведения растут из одного правила. Пока вокруг есть место, перекрытие
-- снимается вбок — группа сама расползается по площади. Тела непроницаемы, поэтому когда
-- снимать его некуда (упёрлись в постройку, в очередь к столу, сошлись в узком проходе),
-- жук стоит, упёршись в соседа впереди, и спустя STACK_DELAY лезет ему на спину.
--
-- Высота — не ярусы, а форма тела. Тело жука в толкучке объёмное: от ступней (пивот минус
-- lift) до верха спины (пивот плюс полувысота), а спина — купол над следом-капсулой.
-- Каждый кадр жук ищет опору под пятью точками брюха (CONTACTS): пол (тогда он стоит на
-- лапах на своей высоте) или чужую спину. Тело держится на спине, только если опора под
-- серединой брюха или с двух сторон от неё; иначе жук сползает с края и падает. Висеть
-- в воздухе рядом с соседом или «внутри» его яруса больше нечем: тела сталкиваются, пока
-- их объёмы пересекаются по высоте, и не сталкиваются, только если один целиком над другим.
--
-- Наверх не лезут на того, кто сам (через любое число ярусов) стоит на нас — см. standsOn:
-- пара «я на тебе, ты на мне» невозможна. Башня выше MAX_TIERS не растёт.
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

-- Когда жук считает, что места нет: он упёрся в соседа и за кадр продвинулся к цели меньше
-- этой доли того, что хотел. Глубину перекрытия мерить больше нельзя — тела непроницаемы,
-- и глубоко продавить жука теперь не выходит никогда (с порогом по глубине на спину не
-- лез никто, и очередь к столу стояла по 20 секунд).
local STACK_PROGRESS = 0.35

-- ...и как долго это должно длиться. Без задержки жуки лезли бы наверх от любой пробки на
-- полсекунды — а расталкивание такую пробку разбирает само за несколько кадров.
local STACK_DELAY = 0.35

-- Лезут только на того, кто сам стоит: идёт медленнее этого (studs/сек) — значит упёрся.
-- Идущего впереди догоняют и ждут за ним, а не лезут ему на спину: пара в пустом коридоре
-- (задний чуть быстрее переднего) иначе складывалась в стопку (плейтест).
local STUCK_SPEED = 1

-- С какой скоростью давление забывается, когда прожим отпустил. Сбрасывать его в ноль нельзя:
-- в живой давке перекрытие дрожит и на кадр-другой проваливается ниже порога у кого угодно,
-- и с жёстким сбросом счётчик не доживал до STACK_DELAY почти ни у кого (замер в проходе:
-- 22 пары внахлёст, а наверх полез один жук из двадцати).
local PRESSURE_RELIEF = 1.5

-- Ярусов, считая землю. Без потолка узкий проход собирает башню до неба.
local MAX_TIERS = 3

-- Точки брюха: сторона (-1 левый борт, 1 правый) и место вдоль тела (-1 зад, 0 середина,
-- 1 перёд). Борта — на CONTACT_SPREAD ширины корпуса от оси. Первой идёт середина.
local CONTACTS = { { 0, 0 }, { 0, -1 }, { 0, 1 }, { -1, 0 }, { 1, 0 } }
local CONTACT_SPREAD = 0.6

-- На сколько выше своего брюха жук встаёт на чужую спину, просто шагая (по спинам давки
-- с одной на соседнюю). Сосед на полу всегда выше — на него встают, только залезая.
local STEP_UP = 0.35

-- Опоры ниже самой высокой не больше чем на это тоже держат тело.
local CONTACT_SLACK = 0.25

-- Объёмы двух тел должны пересекаться по высоте хотя бы на столько, чтобы толкаться:
-- ступни стоящего сверху касаются спины нижнего, и это не столкновение.
local VERTICAL_TOLERANCE = 0.1

local CLIMB_SPEED = 4 -- studs/сек вверх: ярус берётся примерно за треть секунды
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

-- Залезание: сколько секунд жук влезает на спину (его ведёт к хребту соседа, и лапы на нём
-- держат, хотя стоят ещё не с обеих сторон) и с какой скоростью по горизонтали.
local MOUNT_TIME = 0.8
local MOUNT_SPEED = 5

-- Слезание: давки нет уже столько секунд — верхний сходит со спины в сторону. Наверх лезут
-- только от тесноты, и, когда она кончилась, стопка разбирается сама.
local STEP_OFF_DELAY = 0.6
local STEP_OFF_SPEED = 5

-- Лапы держат только с одной стороны (жук на краю чужой спины) — сползает в сторону
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
		support = nil, -- запись того, на ком стоим (nil — на земле)
		level = 0, -- ярус: 0 — земля
		pressed = 0, -- сколько секунд подряд его прижимают
	}
	-- Дальше этого от центра тело не торчит: грубый отсев соседей до точной проверки.
	record.extent = math.max(math.abs(record.front), math.abs(record.back)) + record.radius

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
		if other.support == record then
			other.support = nil
			other.level = 0
		end
		if other.under then
			other.under[record] = nil
		end
		if other.climbOn == record then
			other.climbOn = nil
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
	record.support = nil
	record.under = nil
	record.climbOn = nil
	record.mount = nil
	record.level = 0
	record.pressed = 0
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

-- Толкаются, только пока объёмы пересекаются по высоте: стоящий сверху целиком над нижним
-- (его ступни на уровне чужой спины) — уже не столкновение. Ноги в объём входят: под
-- брюхом крупного жука мелкий не проходит, там его лапы.
local function overlapsVertically(me, y, other)
	return feetOf(me, y) < topOf(other) - VERTICAL_TOLERANCE
		and feetOf(other) < topOf(me, y) - VERTICAL_TOLERANCE
end

-- Высота спины other над точкой (x, z) или nil, если точка не над ним. Спина — купол над
-- следом-капсулой: над хребтом верх тела, к борту ниже. Тот же купол у лап на клиенте
-- (EnemyGait.neighbourBack), чтобы ступни стояли там, где их держит толкучка.
local function shellTop(other, x, z)
	local dx, dz = x - other.x, z - other.z
	local along = math.clamp(dx * other.fx + dz * other.fz, other.back, other.front)
	local px, pz = dx - other.fx * along, dz - other.fz * along
	local across = math.sqrt(px * px + pz * pz)
	local radius = other.radius - BODY_CLEARANCE
	if across >= radius then
		return nil
	end
	return other.y + other.halfHeight * math.sqrt(1 - (across / radius) ^ 2)
end

-- Под брюхом ли record у него target (по прошлому кадру).
local function restsOn(record, target)
	return record.under ~= nil and record.under[target] == true
end

-- Стоит ли record (напрямую или через других) на спине target.
local function standsOn(record, target)
	local below = record.support
	for _ = 1, MAX_TIERS do
		if not below then
			return false
		end
		if below == target then
			return true
		end
		below = below.support
	end
	return false
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
	local deepest = 0 -- самое глубокое перекрытие: по нему считается давление
	local blockedAhead = false -- упёрся в того, кто впереди (а не задет сбоку или сзади)
	-- Кто-то стоит у нас на спине: тогда наверх не лезем и со спины не сходим.
	local carrying = false
	local supportCandidate, supportOverlap = nil, 0
	local climbOn = me.mount and me.mount > 0 and me.climbOn or nil
	if climbOn and not climbOn.model.Parent then
		climbOn = nil
	end

	-- Соседи, с которыми тело обязано не пересекаться, и насколько они пересекаются уже.
	-- nearby — все, кто рядом: под лапы годится любой из них.
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
				if restsOn(other, me) then
					carrying = true
				end

				-- На ком стоим лапами, кто стоит на нас и на кого сейчас влезаем — с теми не
				-- толкаемся: это опора, а не столкновение.
				local stacked = restsOn(me, other) or restsOn(other, me) or other == climbOn
				if not stacked and overlapsVertically(me, me.y, other) then
					local overlap, nx, nz = penetration(me, desired.X, desired.Z, fx, fz, other)
					table.insert(solid, other)
					-- Нормаль берётся из того, где мы СТОИМ (уже разведённые прошлым кадром),
					-- а не из desired: шаг быстрого соседа бывает крупнее щели, и нормаль от
					-- desired перевернулась бы — толчок достроил бы проскок насквозь.
					local current, cnx, cnz = penetration(me, me.x, me.z, me.fx, me.fz, other)
					standing[other] = math.max(TOUCH_TOLERANCE, current)
					allowed[other] = math.max(TOUCH_TOLERANCE, current - OVERLAP_RELAX_SPEED * dt)

					if overlap > 0 then
						if overlap > deepest then
							deepest = overlap
						end
						if current > 0 then
							nx, nz = cnx, cnz
						end

						pushX += nx * overlap * SEPARATION_SHARE
						pushZ += nz * overlap * SEPARATION_SHARE

						-- Упёрся в того, кто впереди, — берёт вбок, а не встаёт в хвост.
						if nx * fx + nz * fz < AHEAD_DOT then
							blockedAhead = true
							local sideX, sideZ = -fz, fx
							local offset = (desired.X - other.x) * sideX + (desired.Z - other.z) * sideZ
							local side = offset > 0.05 and 1 or offset < -0.05 and -1 or (me.id % 2 == 0 and 1 or -1)
							pushX += sideX * side * overlap * SIDESTEP_SHARE
							pushZ += sideZ * side * overlap * SIDESTEP_SHARE
						end

						-- Лезем на того, кто впереди и прижимает сильнее прочих. Не на того, кто сам
						-- стоит на нас: иначе двое залезли бы друг другу на спины по кругу.
						if nx * fx + nz * fz < AHEAD_DOT and other.level + 1 < MAX_TIERS
							and overlap > supportOverlap and not standsOn(other, me) then
							supportCandidate, supportOverlap = other, overlap
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

	-- Прошлым кадром лапы держали только с одного края — сползаем с него.
	if me.slideX then
		pushX += me.slideX * SLIDE_SPEED * dt
		pushZ += me.slideZ * SLIDE_SPEED * dt
	end

	-- Влезая, жук перебирается к хребту соседа; сидя без давки — сходит с него вбок.
	local support = me.support
	if climbOn then
		local tx, tz = climbOn.x - desired.X, climbOn.z - desired.Z
		local length = math.sqrt(tx * tx + tz * tz)
		if length > 1e-3 then
			local step = math.min(length, MOUNT_SPEED * dt)
			pushX += tx / length * step
			pushZ += tz / length * step
		end
	elseif support and support.model.Parent and not carrying and (me.calm or 0) >= STEP_OFF_DELAY then
		-- Туда, где рядом на земле есть место: сначала вбок (к краю, к которому мы и так
		-- ближе), потом вперёд по ходу опоры, потом назад — в узком коридоре боков нет.
		-- Места нет нигде — толпа ещё плотная, остаёмся на спине.
		local sideX, sideZ = -support.fz, support.fx
		local side = (desired.X - support.x) * sideX + (desired.Z - support.z) * sideZ
		local first = side > 0.02 and 1 or side < -0.02 and -1 or (me.id % 2 == 0 and 1 or -1)
		local ground = {
			id = me.id, radius = me.radius, front = me.front, back = me.back,
			halfHeight = me.halfHeight, bodyHeight = me.bodyHeight, lift = me.lift,
			y = me.groundY, groundY = me.groundY, fx = me.fx, fz = me.fz,
		}
		local clear = support.radius + me.radius
		local reach = clear + math.max(math.abs(support.front), math.abs(support.back))
			+ math.max(math.abs(me.front), math.abs(me.back))
		for _, way in {
			{ sideX * first, sideZ * first, clear },
			{ -sideX * first, -sideZ * first, clear },
			{ support.fx, support.fz, reach },
			{ -support.fx, -support.fz, reach },
		} do
			local gx, gz = support.x + way[1] * way[3], support.z + way[2] * way[3]
			if fitsProbe(ground, gx, gz) then
				pushX += way[1] * STEP_OFF_SPEED * dt
				pushZ += way[2] * STEP_OFF_SPEED * dt
				break
			end
		end
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

	-- Давление копится, пока перекрытие остаётся глубоким: значит, вбок расходиться некуда.
	-- Отпустило — убывает с PRESSURE_RELIEF, а не обнуляется: дергание на один кадр не должно
	-- стирать память о том, что жука жмут уже полсекунды.
	local wantX, wantZ = desired.X - me.x, desired.Z - me.z
	local want = math.sqrt(wantX * wantX + wantZ * wantZ)
	local progress = want > 1e-3 and ((x - me.x) * wantX + (z - me.z) * wantZ) / want or want
	if blockedAhead and deepest > 0 and progress < want * STACK_PROGRESS then
		me.pressed += dt
	else
		me.pressed = math.max(0, me.pressed - dt * PRESSURE_RELIEF)
	end

	-- Давки нет — копится спокойствие (по нему верхний слезает); прижали — сбрасывается.
	if me.support and me.pressed < 0.05 and not blockedAhead then
		me.calm = (me.calm or 0) + dt
	else
		me.calm = 0
	end
	if me.mount and me.mount > 0 then
		me.mount = math.max(0, me.mount - dt)
		if me.mount == 0 then
			me.climbOn = nil
		end
	end

	-- Наверх лезут только на того, кто сам стоит (упёрся), и только от давки.
	if supportCandidate and (supportCandidate.speed or 0) > STUCK_SPEED then
		supportCandidate = nil
	end
	if not me.support and not climbOn and not carrying and me.pressed >= STACK_DELAY and supportCandidate then
		climbOn = supportCandidate
		me.climbOn = supportCandidate
		me.mount = MOUNT_TIME
		me.pressed = 0
		me.calm = 0
	end

	-- Опора. Земля под жуком — бетон, а он двигается, и обломки турелей (TowerDebris) поверх
	-- него. Считается по ТОЙ точке, куда жук реально встал после расталкивания, а не по
	-- заявке маршрута: иначе выдавленный из ямы соседями жук ехал бы на её глубине.
	me.groundY = ConcreteFloor.HeightAt(x, z) + TowerDebris.HeightAt(x, z) + me.lift
	-- Брюхо, когда жук стоит на полу на лапах, и где оно сейчас.
	local groundBelly = me.groundY - me.halfHeight
	local belly = me.y - me.halfHeight
	-- Залезая, тянемся на свой рост — но только на того, на кого лезем.
	local climbReach = me.lift + me.halfHeight * 2

	-- Под каждой точкой брюха — самое высокое, до чего она достаёт: пол или чужая спина.
	-- Все, над чьей спиной брюхо (а не чья спина в нашем теле), — под нами: с ними
	-- не толкаемся.
	local heights = table.create(#CONTACTS)
	local under = {}
	local best, bestHeight = nil, groundBelly
	local sideX, sideZ = -fz, fx
	local spread = (me.radius - BODY_CLEARANCE) * CONTACT_SPREAD
	local middle = (me.front + me.back) / 2
	for i, point in CONTACTS do
		local along = point[2] == 1 and me.front or point[2] == -1 and me.back or middle
		local px = x + fx * along + sideX * spread * point[1]
		local pz = z + fz * along + sideZ * spread * point[1]
		local height, by = groundBelly, nil
		for _, other in nearby do
			-- На того, кто (через кого угодно) стоит на нас, не встаём.
			if other.model.Parent and not restsOn(other, me) and not standsOn(other, me) then
				local top = shellTop(other, px, pz)
				if top and top <= belly + (other == climbOn and climbReach or STEP_UP) then
					under[other] = true
					if top > height then
						height, by = top, other
					end
				end
			end
		end
		heights[i] = height
		if height > bestHeight then
			best, bestHeight = by, height
		end
	end

	-- Тело держится на самой высокой опоре, если она под серединой брюха или по обе стороны
	-- от неё (спереди и сзади, или слева и справа). На ровном полу держат все пять. На краю
	-- чужой спины опора с одного бока: тело проседает к пустой стороне и сползает туда.
	local highest = bestHeight
	local count, all = 0, 0
	local left, right, fore, aft = false, false, false, false
	local hx, hz = 0, 0
	for i, point in CONTACTS do
		all += heights[i]
		if heights[i] >= highest - CONTACT_SLACK then
			count += 1
			left = left or point[1] < 0
			right = right or point[1] > 0
			fore = fore or point[2] > 0
			aft = aft or point[2] < 0
			hx += sideX * point[1] + fx * point[2]
			hz += sideZ * point[1] + fz * point[2]
		end
	end
	local centred = heights[1] >= highest - CONTACT_SLACK

	local bellyTarget
	me.slideX, me.slideZ = nil, nil
	if climbOn or centred or (left and right) or (fore and aft) then
		bellyTarget = highest
	else
		bellyTarget = all / #CONTACTS
		local length = math.sqrt(hx * hx + hz * hz)
		if length > 1e-3 then
			me.slideX, me.slideZ = -hx / length, -hz / length
		end
	end

	-- Подъём на опору — с CLIMB_SPEED, падение — с FALL_SPEED: опора ушла, и жук падает
	-- заметно быстрее, чем лез. По пути вниз лапы ловят первую спину, до которой достали.
	local targetY = bellyTarget + me.halfHeight
	local y = me.y
	if y < targetY then
		y = math.min(targetY, y + CLIMB_SPEED * dt)
	elseif y > targetY then
		y = math.max(targetY, y - FALL_SPEED * dt)
	end

	me.under = under
	me.support = best
	me.level = best and best.level + 1 or 0

	-- Скорость по полу — по ней соседи решают, стоит ли этот жук (см. STUCK_SPEED).
	if dt > 1e-4 then
		local moved = math.sqrt((x - me.x) ^ 2 + (z - me.z) ^ 2) / dt
		me.speed = me.speed and me.speed + (moved - me.speed) * math.clamp(dt * 8, 0, 1) or moved
	end
	-- Клиенту: стоит ли жук на чужой спине. По нему походка ищет опору лапам на
	-- соседе, а не на полу (EnemyGait.findSupport); на земле лапы соседей не касаются никогда.
	local onBack = next(under) ~= nil
	if me.onBack ~= onBack then
		me.onBack = onBack
		me.model:SetAttribute("OnBack", onBack)
	end

	me.x, me.y, me.z = x, y, z
	me.fx, me.fz = fx, fz
	place(me)
	return Vector3.new(x, y, z), Vector3.new(fx, 0, fz)
end

return Crowd
