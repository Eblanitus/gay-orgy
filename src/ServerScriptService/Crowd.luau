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
-- Наверх не лезут на того, кто сам (через любое число ярусов) стоит на нас — см. standsOn:
-- пара «я на тебе, ты на мне» невозможна. Башня выше MAX_TIERS разбирается сверху.
-- Поднимаясь или спускаясь, жук не входит в ярус там, где на нём уже кто-то стоит.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Arena = require(ReplicatedStorage:WaitForChild("Arena"))
local Grid = require(ServerScriptService:WaitForChild("Grid"))
-- Рельеф пола: жук едет по бетону, а тот умеет подниматься и опускаться
-- (окоп Окопщика, ландшафт Литосферы). Высотой жука распоряжается толкучка
-- (он может стоять на спине соседа), поэтому и уровень земли читается здесь же.
local ConcreteFloor = require(ServerScriptService:WaitForChild("ConcreteFloor"))
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

-- С какой скоростью давление забывается, когда прожим отпустил. Сбрасывать его в ноль нельзя:
-- в живой давке перекрытие дрожит и на кадр-другой проваливается ниже порога у кого угодно,
-- и с жёстким сбросом счётчик не доживал до STACK_DELAY почти ни у кого (замер в проходе:
-- 22 пары внахлёст, а наверх полез один жук из двадцати).
local PRESSURE_RELIEF = 1.5

-- Высота яруса: на столько поднимается залезший. Тело жука 1.2 в высоту, ноги свисают до
-- -1.5 от пивота — на 1.4 ступни приходятся на бока нижнего, и верхний сидит на спине,
-- а не парит над ней на ходулях.
local TIER_HEIGHT = 1.4 -- минимум: ярус крупного жука — по сумме полувысот тел (см. Resolve)

-- Ярусов, считая землю. Без потолка узкий проход собирает башню до неба.
local MAX_TIERS = 3

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

-- Сосед всё ещё под ногами, пока следы тел перекрываются или почти касаются.
local SUPPORT_MARGIN = 0.3

local Crowd = {}

-- Номер забега толкучки: растёт на каждом Clear. Спавн, который ждёт места у пролома,
-- сверяет его, чтобы не досыпать жука в уже следующий забег.
Crowd.epoch = 0

-- Поиск свободного места для появления (см. Crowd.FindFree): кольца с шагом в радиус тела.
local FREE_SEARCH_RINGS = 4

-- Живые жуки. Массив — для перебора соседей, словарь — чтобы найти свою запись по модели.
-- Врагов на арене десятки, поэтому сосед ищется полным перебором: на волне в 20 жуков это
-- 400 проверок расстояния за кадр, дешевле, чем поддерживать сетку-хеш и её перестройку.
local records = {}
local byModel = {}

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
local function occupied(x, z)
	local cx, cz = Arena.ToCell(Vector3.new(x, 0, z))
	return Grid.GetBlocker(cx, cz) ~= nil
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

	table.insert(records, record)
	byModel[model] = record
	return record
end

function Crowd.Remove(model)
	local record = byModel[model]
	if not record then
		return
	end

	byModel[model] = nil
	local index = table.find(records, record)
	if index then
		table.remove(records, index)
	end

	-- Стоявшие на нём — падают. Ссылку надо снять сразу: иначе верхний ещё кадр висел бы
	-- на высоте застреленного под ним.
	for _, other in records do
		if other.support == record then
			other.support = nil
			other.level = 0
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
-- вовсе — разные ярусы не толкаются (см. Resolve).
function Crowd.Park(model, position, facing)
	local record = byModel[model]
	if not record then
		return
	end

	record.x, record.y, record.z = position.X, position.Y, position.Z
	local fx, fz = flatUnit(facing)
	if fx then
		record.fx, record.fz = fx, fz
	end
	-- С чужой спины жук сошёл в тот же момент, когда полез на преграду.
	record.support = nil
	record.level = 0
	record.pressed = 0
end

-- Забывает всех разом — для рестарта забега (WaveRunner.clearArena сносит врагов пачкой,
-- и снимать их по одному значило бы полагаться на то, что ни один не потерян).
function Crowd.Clear()
	table.clear(records)
	table.clear(byModel)
	Crowd.epoch += 1
end

-- Разные ярусы не толкаются: тот, кто стоит сверху, иначе тут же спихнул бы сам себя
-- с того, на кого залез. Ярус меряется по телам: крупный жук выше мелкого.
local function tierGap(me, other)
	return math.max(TIER_HEIGHT, me.halfHeight + other.halfHeight)
end

-- Ярус считается по высоте над своей землёй, а не по абсолютной Y пивота: пивот
-- Стандарта стоит на 3.1, Работяги — на 1.6, и по абсолютной высоте два жука на одном
-- полу выходили «на разных ярусах» и спокойно проходили друг сквозь друга.
local function elevation(record)
	return record.y - record.groundY
end

local function sameTier(me, other)
	return math.abs(elevation(me) - elevation(other)) < tierGap(me, other) * 0.5
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
		y = position.Y,
		groundY = position.Y, -- появляются на земле
		fx = fx or 0,
		fz = fz or 1,
	}
end

local function fitsProbe(me, x, z)
	if x < MIN_X or x > MAX_X or z < MIN_Z or z > MAX_Z or occupied(x, z) then
		return false
	end
	for _, other in records do
		if other.model.Parent and sameTier(me, other)
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
	local deepest = 0 -- самое глубокое перекрытие на своём ярусе: по нему считается давление
	local blockedAhead = false -- упёрся в того, кто впереди (а не задет сбоку или сзади)
	-- Кто-то стоит у нас на спине: тогда наверх не лезем. Иначе башня росла бы снизу, уже
	-- после проверки MAX_TIERS у верхних, и верхние оказывались бы внутри чужих ярусов.
	local carrying = false
	local supportCandidate, supportOverlap = nil, 0
	local supportHolds = false
	-- Кто ярусом ниже оказался под брюхом: на него встаём, если опора уйдёт.
	local landing, landingOverlap = nil, -SUPPORT_MARGIN

	-- Соседи, с которыми тело обязано не пересекаться, и насколько они пересекаются уже.
	local solid, allowed, standing = {}, {}, {}

	for index = #records, 1, -1 do
		local other = records[index]

		if not other.model.Parent then
			-- Жук мог умереть между кадрами (горение, снаряд) — тогда запись снимает его
			-- собственный поток. Эта же проверка закрывает щель в один кадр между смертью
			-- и снятием: расталкиваться об убитого никто не должен.
			byModel[other.model] = nil
			table.remove(records, index)
		elseif other ~= me then
			local cx, cz = desired.X - other.x, desired.Z - other.z
			local near = me.extent + other.extent + SUPPORT_MARGIN
			if cx * cx + cz * cz < near * near then
				local overlap, nx, nz = penetration(me, desired.X, desired.Z, fx, fz, other)

				-- Опора держит, пока она всё ещё под нами. Ушла из-под ног (или мы с неё сошли,
				-- шагая по маршруту) — падаем.
				if other == me.support then
					supportHolds = overlap > -SUPPORT_MARGIN
				end

				local stacked = other == me.support or other.support == me
				if other.support == me then
					carrying = true
				end

				if not stacked and not sameTier(me, other) then
					if elevation(other) < elevation(me) and overlap > landingOverlap
						and other.level + 1 < MAX_TIERS and not standsOn(other, me) then
						landing, landingOverlap = other, overlap
					end
				elseif not stacked then
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
	if not caged and occupied(x, homeZ) then
		x = homeX
	end

	z = math.clamp(z, MIN_Z, MAX_Z)
	if not caged and occupied(x, z) then
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

	if me.support and not supportHolds then
		me.support = nil
	end

	-- Опора ушла (убили, уползла), а под брюхом другой жук — встаём на него. Раньше верхний
	-- падал на землю сквозь нижних: разные ярусы друг для друга прозрачны, и приземлялся он
	-- внутри тех, над кем висел. На землю он спускается, только сойдя с чужих спин.
	if not me.support and landing and not carrying then
		me.support = landing
		me.pressed = 0
	end

	if not me.support and not carrying and me.pressed >= STACK_DELAY and supportCandidate then
		me.support = supportCandidate
		me.pressed = 0
	end

	me.level = me.support and me.support.level + 1 or 0

	-- Земля под жуком — это бетон, а он двигается. Считается по ТОЙ точке, куда жук
	-- реально встал после расталкивания, а не по заявке маршрута: иначе выдавленный
	-- из ямы соседями жук продолжал бы ехать на её глубине.
	local oldElevation = elevation(me)
	me.groundY = ConcreteFloor.HeightAt(x, z) + (me.lift or 0)

	local targetY = me.support and me.groundY + elevation(me.support) + tierGap(me, me.support) or me.groundY
	local y = me.y
	if y < targetY then
		y = math.min(targetY, y + CLIMB_SPEED * dt)
	elseif y > targetY then
		y = math.max(targetY, y - FALL_SPEED * dt)
	end

	-- Поднимаясь на спину или спускаясь с неё, жук проходит через чужие ярусы. Если на
	-- том ярусе в этом месте уже кто-то стоит, высота не меняется: иначе жук возник бы
	-- внутри него, и перекрытие, которое по горизонтали не возникло бы никогда, досталось
	-- бы обоим. Место освободится — подъём или спуск продолжится.
	if y ~= me.y then
		local newElevation = y - me.groundY
		for _, other in records do
			if other ~= me and other ~= me.support and other.support ~= me and other.model.Parent then
				local cx, cz = x - other.x, z - other.z
				local near = me.extent + other.extent
				if cx * cx + cz * cz < near * near then
					local half = tierGap(me, other) * 0.5
					local was = math.abs(oldElevation - elevation(other)) < half
					local will = math.abs(newElevation - elevation(other)) < half
					if will and not was and penetration(me, x, z, fx, fz, other) > TOUCH_TOLERANCE then
						y = me.y
						break
					end
				end
			end
		end
	end

	me.x, me.y, me.z = x, y, z
	me.fx, me.fz = fx, fz
	return Vector3.new(x, y, z), Vector3.new(fx, 0, fz)
end

return Crowd
