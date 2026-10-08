-- Почерк движения вида: во сколько раз его походка и оживление отличаются от Стандарта.
--
-- Зачем. Походка (EnemyGait) одна на всех: трипод, ровный корпус, вздрагивание,
-- голова раньше тела. Числа в ней подобраны под Стандарта — и до
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
-- прохода по деталям. Шаг, дыхание и озирание — это арифметика над ОДНИМ кадром тела,
-- который и так считается каждый кадр; усики, жвала и голова и так двигаются; крылья на
-- земле обмахивают только у стоящего жука и только у видов, у которых wingIdle задан.
local EnemyGaitStyles = {}

-- Умолчания — ровно поведение Стандарта до этой таблицы: все множители 1, добавок нет.
local DEFAULT = {
	-- Каденция ног: длина шага, время переноса, высота дуги.
	stride = 1,
	stepTime = 1,
	stepLift = 1,
	-- Качки корпуса на ходу (подскок, валкость, крен) у вида нет и быть не должно: как у
	-- живого жука, тело идущего ровное (см. «Тело ровное» в EnemyGait).
	-- Дыхание стоящего: amp — доля распорки вверх-вниз, rate — вдохов в секунду.
	-- На ходу его нет.
	breath = { amp = 0, rate = 0.8 },
	-- Озирание стоящего: голова ведёт из стороны в сторону, amp — рад, rate — Гц.
	sniff = { amp = 0, rate = 0.5 },
	-- Усики и жвала: множители собственного покачивания (ANTENNA_*, MANDIBLE_*).
	antenna = { sway = 1, freq = 1 },
	mandible = { open = 1, freq = 1 },
	-- Грызня (удар по цели, см. «Грызня» в EnemyGait): chew — сила рывка головой, когда
	-- жвалы сомкнулись на цели; lunge — длина броска корпуса к цели. Раскрытие жвал
	-- в замахе — mandible.open, отскок после укуса — flinch (броню не качнуть).
	chew = 1,
	lunge = 1,
	-- Вздрагивание от попадания: во сколько раз сильнее отскок корпуса.
	flinch = 1,
	-- Крылья в полёте: множители взмаха шаблона.
	wing = { freq = 1, angle = 1 },
	-- Крылья на земле у СТОЯЩЕГО жука: amp — доля полного размаха, freq — Гц.
	-- nil — на земле крылья просто сложены (так у всех, кому махать нечем или незачем).
	wingIdle = nil,
	-- Поза смерти: множители разъезда лап и просадки (EnemyGait.DEATH_*).
	death = { splay = 1, drop = 1 },
}

-- Виды. Ключ — имя шаблона (Enemies.model): оно же приходит клиенту атрибутом Template,
-- и по нему же собирается тело, так что лишнего поля заводить не нужно.
local STYLES = {
	-- Каста 0 ------------------------------------------------------------------
	-- Стандарт — точка отсчёта: шаг ровно базовый, добавлено только то, чего
	-- у базы не было вовсе: разведчик принюхивается на остановке и дышит.
	NormalBeetleTemplate = {
		breath = { amp = 0.03, rate = 0.9 },
		sniff = { amp = 0.14, rate = 0.45 },
	},
	-- Хмурый брон: тяжёлая броня — шаг длиннее и реже,
	-- усики вялые, жвала работают медленно.
	ArmoredBeetleTemplate = {
		stride = 1.2,
		stepTime = 1.3,
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
		breath = { amp = 0.04, rate = 1.1 },
		sniff = { amp = 0.2, rate = 0.6 },
		antenna = { sway = 1.2, freq = 1.4 },
		mandible = { freq = 1.2 },
		flinch = 1.1,
	},
	-- Лицехват в воздухе, но садится: на земле дёрганый, низкий, крылья дрожат.
	FacehuggerTemplate = {
		stride = 0.8,
		stepTime = 0.8,
		antenna = { sway = 1.3, freq = 1.4 },
		mandible = { open = 1.4, freq = 1.4 },
		wing = { freq = 1.3 },
		wingIdle = { amp = 0.12, freq = 5 },
		flinch = 1.2,
	},
	-- Моль: порхает, на земле мелко дрожит крыльями, усики огромные и мягкие.
	MothTemplate = {
		stride = 0.85,
		stepLift = 1.2,
		breath = { amp = 0.04, rate = 1.1 },
		antenna = { sway = 1.8, freq = 1.3 },
		wing = { freq = 1.2, angle = 1.15 },
		wingIdle = { amp = 0.18, freq = 5 },
		flinch = 1.2,
		death = { splay = 1.15 },
	},

	-- Каста 1 ------------------------------------------------------------------
	-- Работяга: ровная деловая походка, жвала всё время что-то перебирают.
	WorkerBeetleTemplate = {
		stride = 0.95,
		breath = { amp = 0.035, rate = 1 },
		mandible = { open = 1.3, freq = 1.4 },
		chew = 1.3,
	},
	-- Строитель: медленный и обстоятельный, широкие медленные жвала.
	BuilderBeetleTemplate = {
		stride = 1.15,
		stepTime = 1.25,
		breath = { amp = 0.06, rate = 0.55 },
		sniff = { amp = 0.1, rate = 0.3 },
		antenna = { sway = 0.8, freq = 0.8 },
		mandible = { open = 1.5, freq = 0.7 },
		chew = 1.2,
	},
	-- Пеликан: грузный, шаг тяжёлый, на земле обмахивается крыльями.
	PelicanBeetleTemplate = {
		stride = 1.1,
		stepTime = 1.15,
		breath = { amp = 0.055, rate = 0.7 },
		mandible = { open = 1.4, freq = 0.8 },
		wing = { angle = 1.2 },
		wingIdle = { amp = 0.25, freq = 2.5 },
		death = { splay = 1.1 },
	},
	-- Кислотник: нервный, подрагивает, жвала часто щёлкают.
	AcidSpitterTemplate = {
		stride = 0.9,
		stepTime = 0.85,
		breath = { amp = 0.05, rate = 1.1 },
		antenna = { sway = 1.3, freq = 1.4 },
		mandible = { open = 1.3, freq = 1.4 },
	},
	-- Медик: аккуратный, почти не качается, голова ищет своих.
	MedicTemplate = {
		stride = 0.95,
		stepTime = 0.9,
		breath = { amp = 0.04, rate = 1.1 },
		sniff = { amp = 0.22, rate = 0.7 },
		antenna = { sway = 1.2, freq = 1.3 },
	},
	-- Матка: величавая, высоко несёт корпус, на земле разводит крылья.
	QueenTemplate = {
		stride = 1.15,
		stepTime = 1.1,
		breath = { amp = 0.07, rate = 0.5 },
		sniff = { amp = 0.12, rate = 0.25 },
		antenna = { sway = 0.9, freq = 0.8 },
		wing = { freq = 0.85, angle = 1.25 },
		wingIdle = { amp = 0.3, freq = 1.8 },
		flinch = 0.8,
		death = { splay = 1.1, drop = 0.9 },
	},
	-- Личинка почти не ходит (speed = 0): всё её движение — дыхание. Поэтому оно
	-- большое и медленное: иначе на поле она читается как неживой мешок.
	LarvaTemplate = {
		stride = 0.6,
		stepTime = 1.2,
		stepLift = 0.6,
		breath = { amp = 0.12, rate = 0.45 },
		antenna = { sway = 0.7, freq = 0.6 },
		mandible = { open = 1.2, freq = 0.8 },
		flinch = 1.2,
		death = { splay = 0.7, drop = 1.1 },
	},

	-- Каста 2 ------------------------------------------------------------------
	-- Подрывник: торопится, корпус подпрыгивает, усики дрожат.
	BomberTemplate = {
		stride = 0.85,
		stepTime = 0.8,
		breath = { amp = 0.05, rate = 1.1 },
		antenna = { sway = 1.4, freq = 1.4 },
		mandible = { freq = 1.4 },
		flinch = 1.2,
	},
	-- Щитоносец: вышагивает, щит держит ровно — крен подавлен нарочно.
	ShieldBearerTemplate = {
		stride = 1.25,
		stepTime = 1.3,
		breath = { amp = 0.05, rate = 0.6 },
		antenna = { sway = 0.7, freq = 0.8 },
		flinch = 0.5,
		death = { splay = 0.9 },
	},
	-- Координатор: на ходу всё время озирается и машет усиками — он управляет толпой.
	CoordinatorTemplate = {
		stride = 0.95,
		breath = { amp = 0.04, rate = 1 },
		sniff = { amp = 0.3, rate = 0.8 },
		antenna = { sway = 1.6, freq = 1.4 },
	},
	-- Таран: тяжёлый, шаг длинный и редкий.
	RamTemplate = {
		stride = 1.3,
		stepTime = 1.25,
		stepLift = 1.1,
		breath = { amp = 0.06, rate = 0.5 },
		antenna = { sway = 0.6, freq = 0.6 },
		mandible = { open = 1.3, freq = 0.7 },
		flinch = 0.5,
		chew = 1.2,
		lunge = 1.15, -- таран: бьёт с подачи всем корпусом
		death = { splay = 0.9, drop = 0.9 },
	},
	-- Спринтер: частый стелющийся галоп, усики прижаты ходом.
	SprinterTemplate = {
		stride = 0.85,
		stepTime = 0.8,
		stepLift = 0.8,
		breath = { amp = 0.05, rate = 1.1 },
		antenna = { sway = 0.5, freq = 1.4 },
		flinch = 1.2,
	},
	-- Гигант: редкие тяжёлые шаги, корпус оседает на каждый.
	GiantTemplate = {
		stride = 1.35,
		stepTime = 1.4,
		stepLift = 1.25,
		breath = { amp = 0.08, rate = 0.4 },
		antenna = { sway = 0.6, freq = 0.5 },
		mandible = { open = 1.4, freq = 0.6 },
		flinch = 0.35,
		chew = 0.8,
		lunge = 0.8, -- гигант: не бросается, а наваливается
		death = { splay = 0.9, drop = 0.85 },
	},
	-- Заживалка: суетливая, мелкий частый шаг, жвала всё время работают.
	KnitterTemplate = {
		stride = 0.8,
		stepTime = 0.8,
		breath = { amp = 0.045, rate = 1.1 },
		sniff = { amp = 0.18, rate = 0.8 },
		antenna = { sway = 1.3, freq = 1.4 },
		mandible = { open = 1.2, freq = 1.4 },
	},

	-- Каста 3 ------------------------------------------------------------------
	-- Разносчик: раздутый, тяжело дышит.
	AbsorberTemplate = {
		stride = 1.05,
		stepTime = 1.1,
		breath = { amp = 0.09, rate = 0.7 },
		antenna = { sway = 0.8, freq = 0.9 },
		death = { splay = 1.1, drop = 1.1 },
	},
	-- Эволюционер: его всё время перестраивает — частое крупное дыхание и рывки.
	EvolverTemplate = {
		stride = 0.95,
		stepTime = 0.9,
		breath = { amp = 0.1, rate = 1.1 },
		antenna = { sway = 1.4, freq = 1.4 },
		mandible = { open = 1.3, freq = 1.4 },
	},
	-- Носитель: идёт гружёный — низко, ровно, медленно, с просадкой.
	CarrierTemplate = {
		stride = 1.2,
		stepTime = 1.3,
		breath = { amp = 0.065, rate = 0.5 },
		antenna = { sway = 0.7, freq = 0.7 },
		flinch = 0.6,
		death = { splay = 0.95 },
	},
	-- Кукольник: марионеточная походка — резкие короткие переносы и рывки корпуса.
	PuppeteerTemplate = {
		stride = 0.9,
		-- Лапа перебрасывается рывком, а не переносится. Ниже 0.8 опускать нельзя:
		-- перенос ноги-модели и так 0.03 сек (MODEL_STEP_TIME), и короче кадра он
		-- превратится в телепорт ступни вместо дуги.
		stepTime = 0.8,
		stepLift = 1.3,
		breath = { amp = 0.03, rate = 1.1 },
		sniff = { amp = 0.25, rate = 1.1 },
		antenna = { sway = 1.7, freq = 1.2 },
		flinch = 1.2,
	},
	-- Архитектор улья: степенный, жвала и усики всё время заняты.
	HiveArchitectTemplate = {
		stride = 1.15,
		stepTime = 1.2,
		breath = { amp = 0.06, rate = 0.6 },
		sniff = { amp = 0.16, rate = 0.4 },
		antenna = { sway = 1.2, freq = 1.1 },
		mandible = { open = 1.5, freq = 1.2 },
		chew = 1.2,
	},
	-- Мимик крадётся: подделке нельзя дышать и трясти усиками, иначе его видно
	-- до того, как он раскрылся. Это самый тихий почерк в таблице нарочно.
	MimicTemplate = {
		stride = 0.9,
		stepTime = 0.95,
		breath = { amp = 0.02, rate = 0.6 },
		antenna = { sway = 0.4, freq = 0.6 },
		mandible = { open = 0.7, freq = 0.7 },
	},
	-- Тень: стелется, корпус почти не поднимается, усики быстрые.
	ShadowTemplate = {
		stride = 0.9,
		stepTime = 0.8,
		stepLift = 0.7,
		breath = { amp = 0.03, rate = 1.1 },
		sniff = { amp = 0.15, rate = 1 },
		antenna = { sway = 1.3, freq = 1.4 },
		flinch = 1.2,
		death = { splay = 1.05 },
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
