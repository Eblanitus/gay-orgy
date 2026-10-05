-- Почерк движения вида: во сколько раз его походка и оживление отличаются от Стандарта.
--
-- Зачем. Походка (EnemyGait) одна на всех: трипод, качка по стоящим ступням, крен в
-- повороте, вздрагивание, голова раньше тела. Числа в ней подобраны под Стандарта — и до
-- этой таблицы ВСЕ 26 видов двигались с точностью до масштаба одинаково: Гигант семенил
-- тем же шагом, что Мини, Спринтер шёл как Личинка, Мимик крался как Таран. Разницу видно
-- только по цвету и размеру, а не по движению, и толпа читается как один жук в 26 размерах.
--
-- Что здесь. Только МНОЖИТЕЛИ и амплитуды поверх общей походки, по виду (ключ — имя
-- шаблона из Enemies.model). Своей логики движения ни у одного вида нет: новый вид —
-- строка в этой таблице, а не ветка в EnemyGait (правило проекта: данные в таблицах).
-- Чего здесь нет: скорость хода, разворот и дебаффы. Скорость — у вида в Enemies
-- (походка сама считает по ней каденцию), разворот общий с толкучкой (Crowd ведёт по нему
-- капсулу, и расхождение въехало бы жуком в соседа), состояние рисует индикация,
-- а не движение (правило v2).
--
-- Телефон держит до ~39 жуков: ни одно поле ниже не добавляет ни детали, ни кадрового
-- прохода по деталям. Шаг, качка, дыхание и крен — это арифметика над ОДНИМ кадром тела,
-- который и так считается каждый кадр; усики, жвала и голова и так двигаются; крылья на
-- земле обмахивают только у стоящего жука и только у видов, у которых wingIdle задан.
local EnemyGaitStyles = {}

-- Умолчания — ровно поведение Стандарта до этой таблицы: все множители 1, добавок нет.
local DEFAULT = {
	-- Каденция ног: длина шага, время переноса, высота дуги.
	stride = 1,
	stepTime = 1,
	stepLift = 1,
	-- Потолки качки тела от ног (BODY_SWAY/LIFT/ROLL/PITCH в EnemyGait).
	sway = 1,
	lift = 1,
	roll = 1,
	pitch = 1,
	-- Собственный подскок корпуса на ходу: amp — доля длины ноги-распорки, freq — во
	-- сколько раз чаще шагового цикла (1 = раз на шаг, 2 = на каждую полуфазу трипода).
	bob = { amp = 0, freq = 1 },
	-- Валкость: крен вокруг оси носа на ходу, рад, с частотой freq от шагового цикла.
	-- Нечётная частота (0.5) даёт перевалку с борта на борт через два шага — хромота,
	-- переваливание, рывки марионетки.
	lurch = { amp = 0, freq = 0.5 },
	-- Дыхание стоящего: amp — доля распорки вверх-вниз, rate — вдохов в секунду.
	-- На ходу гасится (его там не видно за качкой от ног).
	breath = { amp = 0, rate = 0.8 },
	-- Озирание стоящего: голова ведёт из стороны в сторону, amp — рад, rate — Гц.
	sniff = { amp = 0, rate = 0.5 },
	-- Усики и жвала: множители собственного покачивания (ANTENNA_*, MANDIBLE_*).
	antenna = { sway = 1, freq = 1 },
	mandible = { open = 1, freq = 1 },
	-- Грызня: во сколько раз быстрее работают передние лапы.
	chew = 1,
	-- Вздрагивание от попадания: во сколько раз сильнее отскок корпуса.
	flinch = 1,
	-- Крылья в полёте: множители взмаха шаблона.
	wing = { freq = 1, angle = 1 },
	-- Крылья на земле у СТОЯЩЕГО жука: amp — доля полного размаха, freq — Гц.
	-- nil — на земле крылья просто сложены (так у всех, кому махать нечем или незачем).
	wingIdle = nil,
	-- Поза смерти: множители разъезда лап и просадки (EnemyGait.DEATH_*).
	death = { splay = 1, drop = 1 },
	-- Ход, при котором подскок и валкость в полную силу, ст/сек в единицах Стандарта.
	-- У быстрого вида он выше, иначе на своей рабочей скорости он трясётся в потолок.
	refSpeed = 10,
}

-- Виды. Ключ — имя шаблона (Enemies.model): оно же приходит клиенту атрибутом Template,
-- и по нему же собирается тело, так что лишнего поля заводить не нужно.
local STYLES = {
	-- Каста 0 ------------------------------------------------------------------
	-- Стандарт — точка отсчёта: шаг и качка ровно базовые, добавлено только то, чего
	-- у базы не было вовсе: разведчик принюхивается на остановке и дышит.
	NormalBeetleTemplate = {
		breath = { amp = 0.03, rate = 0.9 },
		sniff = { amp = 0.14, rate = 0.45 },
		bob = { amp = 0.012, freq = 2 },
	},
	-- Хмурый брон: тяжёлая броня — шаг длиннее и реже, корпус заметно проседает,
	-- усики вялые, жвала работают медленно.
	ArmoredBeetleTemplate = {
		stride = 1.2,
		stepTime = 1.3,
		lift = 1.3,
		roll = 1.2,
		bob = { amp = 0.03, freq = 2 },
		lurch = { amp = 0.021, freq = 0.5 },
		breath = { amp = 0.05, rate = 0.6 },
		antenna = { sway = 0.6, freq = 0.7 },
		mandible = { open = 1.2, freq = 0.6 },
		flinch = 0.6, -- броню качнуть труднее
		death = { splay = 0.85, drop = 0.9 },
	},
	-- Мини: суетливые усики и голова, корпус ровный. Шаг у крошечного жука и так частый
	-- (масштаб), укорачивать его ещё и почерком нельзя: выходила дрожь, а не семенение.
	MiniBeetleTemplate = {
		stride = 0.9,
		stepTime = 1,
		stepLift = 0.85,
		bob = { amp = 0.024, freq = 2 },
		breath = { amp = 0.04, rate = 1.1 },
		sniff = { amp = 0.2, rate = 0.6 },
		antenna = { sway = 1.2, freq = 1.4 },
		mandible = { freq = 1.2 },
		flinch = 1.1,
		refSpeed = 12,
	},
	-- Лицехват в воздухе, но садится: на земле дёрганый, низкий, крылья дрожат.
	FacehuggerTemplate = {
		stride = 0.8,
		stepTime = 0.8,
		lift = 0.7,
		bob = { amp = 0.018, freq = 2 },
		lurch = { amp = 0.035, freq = 1 },
		antenna = { sway = 1.3, freq = 1.4 },
		mandible = { open = 1.4, freq = 1.4 },
		wing = { freq = 1.3 },
		wingIdle = { amp = 0.12, freq = 5 },
		flinch = 1.2,
		refSpeed = 20,
	},
	-- Моль: порхает, на земле мелко дрожит крыльями, усики огромные и мягкие.
	MothTemplate = {
		stride = 0.85,
		stepLift = 1.2,
		lift = 0.8,
		breath = { amp = 0.04, rate = 1.1 },
		antenna = { sway = 1.8, freq = 1.3 },
		wing = { freq = 1.2, angle = 1.15 },
		wingIdle = { amp = 0.18, freq = 5 },
		flinch = 1.2,
		death = { splay = 1.15 },
		refSpeed = 16,
	},

	-- Каста 1 ------------------------------------------------------------------
	-- Работяга: ровная деловая походка, жвала всё время что-то перебирают.
	WorkerBeetleTemplate = {
		stride = 0.95,
		bob = { amp = 0.018, freq = 2 },
		breath = { amp = 0.035, rate = 1 },
		mandible = { open = 1.3, freq = 1.4 },
		chew = 1.3,
		refSpeed = 12,
	},
	-- Строитель: медленный и обстоятельный, широкие медленные жвала.
	BuilderBeetleTemplate = {
		stride = 1.15,
		stepTime = 1.25,
		bob = { amp = 0.024, freq = 2 },
		breath = { amp = 0.06, rate = 0.55 },
		sniff = { amp = 0.1, rate = 0.3 },
		antenna = { sway = 0.8, freq = 0.8 },
		mandible = { open = 1.5, freq = 0.7 },
		chew = 1.2,
		refSpeed = 8,
	},
	-- Пеликан: грузный, идёт вперевалку, на земле обмахивается крыльями.
	PelicanBeetleTemplate = {
		stride = 1.1,
		stepTime = 1.15,
		roll = 1.5,
		lift = 1.2,
		bob = { amp = 0.03, freq = 1 },
		lurch = { amp = 0.042, freq = 0.5 },
		breath = { amp = 0.055, rate = 0.7 },
		mandible = { open = 1.4, freq = 0.8 },
		wing = { angle = 1.2 },
		wingIdle = { amp = 0.25, freq = 2.5 },
		death = { splay = 1.1 },
		refSpeed = 14,
	},
	-- Кислотник: нервный, подрагивает, жвала часто щёлкают.
	AcidSpitterTemplate = {
		stride = 0.9,
		stepTime = 0.85,
		bob = { amp = 0.021, freq = 2 },
		lurch = { amp = 0.021, freq = 1 },
		breath = { amp = 0.05, rate = 1.1 },
		antenna = { sway = 1.3, freq = 1.4 },
		mandible = { open = 1.3, freq = 1.4 },
		refSpeed = 11,
	},
	-- Медик: аккуратный, почти не качается, голова ищет своих.
	MedicTemplate = {
		stride = 0.95,
		stepTime = 0.9,
		roll = 0.7,
		bob = { amp = 0.012, freq = 2 },
		breath = { amp = 0.04, rate = 1.1 },
		sniff = { amp = 0.22, rate = 0.7 },
		antenna = { sway = 1.2, freq = 1.3 },
		refSpeed = 12,
	},
	-- Матка: величавая, высоко несёт корпус, на земле разводит крылья.
	QueenTemplate = {
		stride = 1.15,
		stepTime = 1.1,
		roll = 0.8,
		bob = { amp = 0.018, freq = 1 },
		breath = { amp = 0.07, rate = 0.5 },
		sniff = { amp = 0.12, rate = 0.25 },
		antenna = { sway = 0.9, freq = 0.8 },
		wing = { freq = 0.85, angle = 1.25 },
		wingIdle = { amp = 0.3, freq = 1.8 },
		flinch = 0.8,
		death = { splay = 1.1, drop = 0.9 },
		refSpeed = 18,
	},
	-- Личинка почти не ходит (speed = 0): всё её движение — дыхание. Поэтому оно
	-- большое и медленное: иначе на поле она читается как неживой мешок.
	LarvaTemplate = {
		stride = 0.6,
		stepTime = 1.2,
		stepLift = 0.6,
		lift = 0.6,
		bob = { amp = 0.012, freq = 1 },
		breath = { amp = 0.12, rate = 0.45 },
		antenna = { sway = 0.7, freq = 0.6 },
		mandible = { open = 1.2, freq = 0.8 },
		flinch = 1.2,
		death = { splay = 0.7, drop = 1.1 },
		refSpeed = 6,
	},

	-- Каста 2 ------------------------------------------------------------------
	-- Подрывник: торопится, корпус подпрыгивает, усики дрожат.
	BomberTemplate = {
		stride = 0.85,
		stepTime = 0.8,
		bob = { amp = 0.033, freq = 2 },
		breath = { amp = 0.05, rate = 1.1 },
		antenna = { sway = 1.4, freq = 1.4 },
		mandible = { freq = 1.4 },
		flinch = 1.2,
		refSpeed = 13,
	},
	-- Щитоносец: вышагивает, щит держит ровно — крен подавлен нарочно.
	ShieldBearerTemplate = {
		stride = 1.25,
		stepTime = 1.3,
		roll = 0.4,
		pitch = 0.6,
		bob = { amp = 0.027, freq = 2 },
		breath = { amp = 0.05, rate = 0.6 },
		antenna = { sway = 0.7, freq = 0.8 },
		flinch = 0.5,
		death = { splay = 0.9 },
	},
	-- Координатор: на ходу всё время озирается и машет усиками — он управляет толпой.
	CoordinatorTemplate = {
		stride = 0.95,
		bob = { amp = 0.018, freq = 2 },
		breath = { amp = 0.04, rate = 1 },
		sniff = { amp = 0.3, rate = 0.8 },
		antenna = { sway = 1.6, freq = 1.4 },
		refSpeed = 12,
	},
	-- Таран: валкий и тяжёлый, раскачивается с борта на борт.
	RamTemplate = {
		stride = 1.3,
		stepTime = 1.25,
		stepLift = 1.1,
		lift = 1.4,
		roll = 1.4,
		bob = { amp = 0.036, freq = 1 },
		lurch = { amp = 0.049, freq = 0.5 },
		breath = { amp = 0.06, rate = 0.5 },
		antenna = { sway = 0.6, freq = 0.6 },
		mandible = { open = 1.3, freq = 0.7 },
		flinch = 0.5,
		chew = 1.2,
		death = { splay = 0.9, drop = 0.9 },
	},
	-- Спринтер: частый стелющийся галоп, усики прижаты ходом.
	SprinterTemplate = {
		stride = 0.85,
		stepTime = 0.8,
		stepLift = 0.8,
		sway = 1.3,
		lift = 0.8,
		bob = { amp = 0.03, freq = 2 },
		breath = { amp = 0.05, rate = 1.1 },
		antenna = { sway = 0.5, freq = 1.4 },
		flinch = 1.2,
		refSpeed = 32,
	},
	-- Гигант: редкие тяжёлые шаги, корпус оседает на каждый.
	GiantTemplate = {
		stride = 1.35,
		stepTime = 1.4,
		stepLift = 1.25,
		lift = 1.5,
		roll = 1.3,
		bob = { amp = 0.042, freq = 1 },
		lurch = { amp = 0.035, freq = 0.5 },
		breath = { amp = 0.08, rate = 0.4 },
		antenna = { sway = 0.6, freq = 0.5 },
		mandible = { open = 1.4, freq = 0.6 },
		flinch = 0.35,
		chew = 0.8,
		death = { splay = 0.9, drop = 0.85 },
		refSpeed = 6,
	},
	-- Заживалка: суетливая, мелкий частый шаг, жвала всё время работают.
	KnitterTemplate = {
		stride = 0.8,
		stepTime = 0.8,
		bob = { amp = 0.021, freq = 2 },
		breath = { amp = 0.045, rate = 1.1 },
		sniff = { amp = 0.18, rate = 0.8 },
		antenna = { sway = 1.3, freq = 1.4 },
		mandible = { open = 1.2, freq = 1.4 },
		refSpeed = 12,
	},

	-- Каста 3 ------------------------------------------------------------------
	-- Разносчик: раздутый, переваливается и тяжело дышит.
	AbsorberTemplate = {
		stride = 1.05,
		stepTime = 1.1,
		roll = 1.4,
		lift = 1.2,
		bob = { amp = 0.027, freq = 1 },
		lurch = { amp = 0.038, freq = 0.5 },
		breath = { amp = 0.09, rate = 0.7 },
		antenna = { sway = 0.8, freq = 0.9 },
		death = { splay = 1.1, drop = 1.1 },
		refSpeed = 11,
	},
	-- Эволюционер: его всё время перестраивает — частое крупное дыхание и рывки.
	EvolverTemplate = {
		stride = 0.95,
		stepTime = 0.9,
		bob = { amp = 0.024, freq = 2 },
		lurch = { amp = 0.035, freq = 1 },
		breath = { amp = 0.1, rate = 1.1 },
		antenna = { sway = 1.4, freq = 1.4 },
		mandible = { open = 1.3, freq = 1.4 },
		refSpeed = 11,
	},
	-- Носитель: идёт гружёный — низко, ровно, медленно, с просадкой.
	CarrierTemplate = {
		stride = 1.2,
		stepTime = 1.3,
		roll = 0.6,
		lift = 1.35,
		bob = { amp = 0.03, freq = 1 },
		breath = { amp = 0.065, rate = 0.5 },
		antenna = { sway = 0.7, freq = 0.7 },
		flinch = 0.6,
		death = { splay = 0.95 },
		refSpeed = 9,
	},
	-- Кукольник: марионеточная походка — резкие короткие переносы и рывки корпуса.
	PuppeteerTemplate = {
		stride = 0.9,
		-- Лапа перебрасывается рывком, а не переносится. Ниже 0.8 опускать нельзя:
		-- перенос ноги-модели и так 0.03 сек (MODEL_STEP_TIME), и короче кадра он
		-- превратится в телепорт ступни вместо дуги.
		stepTime = 0.8,
		stepLift = 1.3,
		bob = { amp = 0.027, freq = 2 },
		lurch = { amp = 0.056, freq = 1 },
		breath = { amp = 0.03, rate = 1.1 },
		sniff = { amp = 0.25, rate = 1.1 },
		antenna = { sway = 1.7, freq = 1.2 },
		flinch = 1.2,
		refSpeed = 11,
	},
	-- Архитектор улья: степенный, жвала и усики всё время заняты.
	HiveArchitectTemplate = {
		stride = 1.15,
		stepTime = 1.2,
		bob = { amp = 0.024, freq = 2 },
		breath = { amp = 0.06, rate = 0.6 },
		sniff = { amp = 0.16, rate = 0.4 },
		antenna = { sway = 1.2, freq = 1.1 },
		mandible = { open = 1.5, freq = 1.2 },
		chew = 1.2,
		refSpeed = 8,
	},
	-- Мимик крадётся: подделке нельзя дышать и трясти усиками, иначе его видно
	-- до того, как он раскрылся. Это самый тихий почерк в таблице нарочно.
	MimicTemplate = {
		stride = 0.9,
		stepTime = 0.95,
		sway = 0.7,
		lift = 0.5,
		roll = 0.6,
		bob = { amp = 0.009, freq = 2 },
		breath = { amp = 0.02, rate = 0.6 },
		antenna = { sway = 0.4, freq = 0.6 },
		mandible = { open = 0.7, freq = 0.7 },
		refSpeed = 12,
	},
	-- Тень: стелется, корпус почти не поднимается, усики быстрые.
	ShadowTemplate = {
		stride = 0.9,
		stepTime = 0.8,
		stepLift = 0.7,
		lift = 0.5,
		roll = 0.7,
		bob = { amp = 0.012, freq = 2 },
		breath = { amp = 0.03, rate = 1.1 },
		sniff = { amp = 0.15, rate = 1 },
		antenna = { sway = 1.3, freq = 1.4 },
		flinch = 1.2,
		death = { splay = 1.05 },
		refSpeed = 20,
	},
}

-- Готовые (достроенные умолчаниями) наборы: собираются один раз на вид, а не на жука.
local built = {}

local function fill(style)
	local out = {}
	for key, base in DEFAULT do
		local own = style[key]
		if type(base) == "table" then
			local merged = {}
			for field, value in base do
				local given = own and own[field]
				merged[field] = given ~= nil and given or value
			end
			out[key] = merged
		else
			out[key] = own ~= nil and own or base
		end
	end
	-- Поля, которых в умолчаниях нет (wingIdle = nil), переносятся как есть.
	if style.wingIdle then
		out.wingIdle = { amp = style.wingIdle.amp or 0.15, freq = style.wingIdle.freq or 4 }
	end
	return out
end

EnemyGaitStyles.Default = fill({})

-- Почерк вида по имени шаблона. Вида нет в таблице (примитив без шаблона, жук Аркады,
-- новый вид без строки) — ровно базовое поведение Стандарта, как было до этой таблицы.
function EnemyGaitStyles.For(key)
	if not key then
		return EnemyGaitStyles.Default
	end
	local ready = built[key]
	if not ready then
		local style = STYLES[key]
		ready = style and fill(style) or EnemyGaitStyles.Default
		built[key] = ready
	end
	return ready
end

return EnemyGaitStyles
