-- Походка жука: ноги переступают, корпус следует за ними.
--
-- Правило из дизайна поз (alchemy_td_enemies_visual_design_v1, раздел 5): «перебирание ног —
-- без инерции и скольжения: ноги шагают, корпус следует, никакого качения», плюс отдельным
-- слоем — «наклон конечностей от поверхности». До этой задачи ноги были приварены к телу
-- статичными CFrame (см. EnemySpawner.buildEnemyModel), и жук ехал по полу как санки.
--
-- Как устроено. У каждой ноги есть бедро на теле и стойка — место, куда ей полагается
-- встать при текущем положении тела. Ступня ЛЕЖИТ В МИРЕ и не двигается, пока тело не
-- уедет от неё дальше STRIDE — тогда нога переносится по дуге за STEP_TIME. Отсюда и «без
-- скольжения»: между шагами ступня стоит на месте, а не ползёт вместе с корпусом.
--
-- Куда именно она встанет, решает луч ВНИЗ ПО ТЕЛУ (против его собственного UpVector),
-- а не вниз по миру. Одно правило закрывает все поверхности из ТЗ разом — ровная клетка,
-- плита Бура, зона Землетрясения, стена и гора: жук, вставший на стену пузом, светит
-- лучами в стену и ставит ноги на неё. Отдельной «позы лазанья» для этого не нужно.
--
-- Ноги — обычные части модели, и двигает их сервер в том же цикле, что и саму модель
-- (см. EnemySpawner): модель анкорнута и едет через PivotTo, то есть CFrame всех её частей
-- и так переписывается каждый кадр — на репликацию ноги не добавляют ничего сверх того,
-- что уже шло.
local Workspace = game:GetService("Workspace")

local EnemyGait = {}

-- Насколько тело должно уехать от ступни, чтобы нога переступила, studs. Меньше —
-- семенит, больше — вышагивает и начинает тянуть ногу за собой.
local STRIDE = 1.3

-- Секунд на перенос ноги. Коротко нарочно: жук идёт 15 studs/сек, и при длинном
-- переносе тело уезжает быстрее, чем нога успевает встать — тогда она всегда в воздухе,
-- и вся походка превращается обратно в скольжение.
local STEP_TIME = 0.08

-- Высота дуги переноса, studs: без неё нога едет сквозь пол, а не переступает.
local STEP_LIFT = 0.4

-- Каденция ног-моделей (сегментные лапы шаблона). Толстые лапы с размахом примитивов
-- (шаг 1.3, дуга 0.4) на спринте 15 ст/с переносятся 90% времени и машут на полступи
-- вверх — читается как барахтанье, а не бег (замерено живым прогоном). Поэтому шаг
-- длиннее, дуга ниже, перенос чуть дольше: лапы стелются, фаза опоры сохраняется.
-- Примитивов не касается.
-- Каденция ног-моделей (сегментные лапы шаблона) — короткая: шагает, а не вышагивает.
-- Шаг длиннее анатомического предела лапы (бедро + голень: 1.5-1.7 studs у Стандарта)
-- поднимал бы ступню над опорой: planted-точка уезжала за досягаемость, placeLeg срезал
-- её к бедру, и лапа висела в воздухе с инвертированным коленом (замерено стендом
-- и подбором: stride 2.0 → tarsus 0.35 над полом и колено ниже бедра; stride 0.6 →
-- ступня на полу, колено строго вверх). Свой шаг так же короток, дуга ниже, перенос
-- короче: лапы стелются и успевают встать до того, как тело унесёт бедро от ступни.
-- Примитивов не касается.
local MODEL_STRIDE = 3.0 -- шаг под гиганта ×3.0 (цикл 3.0/15 = 0.2с): тяжёлые редкие шаги, а не семенение
local MODEL_STEP_LIFT = 0.45 -- дуга пропорциональна шагу
local MODEL_STEP_TIME = 0.03 -- перенос короче цикла (3.0/15 = 0.2с): фаза опоры ~85%

-- MODEL_STRIDE/MODEL_STEP_LIFT и абсолютные расстояния похода ниже (PROBE_*, CHEW_*,
-- DEATH_DROP, офсет 0.35 в climb) подобраны стендом под Стандарта — модель на Scale = 3.0
-- (см. #137). Нога-модель у Мини — тот же шаблон, но его Scale гуляет в scaleRange
-- 0.55-1.80, а физическая длина лапы (бедро+голень, entry.length) уезжает вместе со Scale,
-- эти же константы — нет: MODEL_STRIDE=3.0 у Мини на маленьком Scale в разы больше всей его
-- вытянутой лапы, «переступить по-настоящему» она не успевает — тело утаскивает уже
-- вросшую в предел растяжения стойку, и лапа не шагает, а скользит/дёргается на пределе
-- (жалоба «у маленьких жуков лапы двигаются странно», см. #155). Приводится к масштабу
-- экземпляра через его Scale-атрибут (см. EnemySpawner) — на Scale = 3.0 коэффициент 1,
-- поведение Стандарта не меняется.

-- НО: масштаб — не вся правда. Шаг ограничен не размером жука, а ЗАПАСОМ КОНКРЕТНОЙ
-- ЛАПЫ: разницей между её вытянутой длиной (бедро + голень) и стойкой покоя. У меш-модели
-- из Blender лапа в покое уже почти выпрямлена (замерено по шаблону: стойка = 73-82% от
-- вытянутой длины), и у Стандарта на Scale = 3.0 этот запас всего 0.8-0.9 studs — втрое
-- меньше MODEL_STRIDE. То есть ступня упиралась в анатомический предел задолго до того,
-- как брался порог шага: placeModelLeg срезал цель к бедру, и кончик ехал вместе с телом
-- вместо того, чтобы стоять на месте. Жалоба автора «лапы не успевают за торсом» — именно это:
-- замерено на живом прогоне — задние лапы стояли на месте всего 35% кадров против 89%
-- у передних, и скорость тут ни при чём — на медленном ходу та же картина.
--
-- Решается не укорочением шага (пробовалось: шаг по запасу даёт 0.74 studs и 13 шагов
-- в секунду — семенение), а ВТОРЫМ ПОВОДОМ переступить: нога шагает, когда либо
-- тело ушло от ступни на MODEL_STRIDE, либо лапа вот-вот вытянется до предела — смотря
-- что раньше. Порог ниже — доля вытянутой длины (бедро + голень), по достижении
-- которой ногу пора переносить. С запасом до единицы: ровно на пределе лапа уже
-- выпрямлена в палку, а во время переноса тело уедет ещё немного.
-- Примитивов не касается: у них нога резиновая (меняется Size), тянуться ей не больно.
local MODEL_STEP_REACH = 0.9

-- Куда СТАВИТСЯ ступня в конце переноса — тоже доля вытянутой длины, но ВПЕРЁД ПО ХОДУ.
--
-- До этой задачи нога вставала ровно в свою номинальную стойку — то есть туда, где ей полагается
-- быть у стоячего жука. Но тело в этот момент едет, и сразу после постановки ступня начинала
-- отставать: весь шаг целиком уходил НАЗАД от нейтрали, и каждый перенос был догоняющим.
-- Оттуда жалоба автора: «лапы не тащат торс, а пытаются за ним убежать».
--
-- Теперь ступня выносится вперёд до этой доли вытяжки, а переступает нога по MODEL_STEP_REACH
-- сзади. То есть опорная фаза идёт ОТ точки впереди тела до точки позади него, через нейтраль
-- посередине — именно так лапа читается как толкающая тело, а не догоняющая его.
-- Строго меньше MODEL_STEP_REACH: ступня обязана вставать с запасом до порога перешагивания,
-- иначе она будет требовать следующий шаг в тот же кадр, как только встала.
local MODEL_STEP_PLANT = 0.84

-- Сглаживание скорости тела, 1/сек: именно по ней решается, где «впереди». Сырая
-- покадровая разница не годится: рывки толкучки и просадки кадров швыряли бы ступню
-- в случайную сторону на каждом шаге.
local VELOCITY_SMOOTH = 10
local GAIT_TUNED_SCALE = 3.0

-- ======================= Тело несут ноги =======================
--
-- Референс — живой жук (автор так и сформулировал: «у нас есть референс из самой лучшей
-- игры в мире — Real life»). Что там происходит и чего у нас не было:
--
-- 1. Тело НЕ едет с постоянной скоростью. Ступня, вставшая впереди, сначала тормозит
--    корпус, а к концу опоры толкает его вперёд. Скорость корпуса дёргается дважды за
--    цикл — это и читается как «ноги несут тело».
-- 2. Тело НЕ едет на постоянной высоте. Нога работает как распорка постоянной длины:
--    ступня под бедром — тело в верхней точке, ступня уехала вперёд или назад — тело
--    просело. Вертикальная качка идёт вдвое чаще шага.
-- 3. Тело переваливается. Трипод меняется — опора смещается вбок, и корпус кренится
--    к той стороне, которая его держит.
--
-- До этой задачи всё было наоборот: спавнер вёл тело по маршруту с постоянной скоростью
-- и постоянной высотой, а ноги пририсовывались к нему. Сколько ни чини ноги, тело
-- оставалось независимым объектом — отсюда жалоба «торс просто плавно плывёт, а лапы
-- пытаются его догнать».
--
-- Теперь маршрут и тело — РАЗНЫЕ вещи. Маршрут остаётся у спавнера (по нему считаются
-- сетка, толкучка, прицел башен, дистанция до выхода — их качка трогать не должна),
-- а видимое тело каждый кадр собирается из СТОЯЩИХ ступней: где они стоят, туда корпус
-- и смещается. Ступни задают и подъём, и крен, и рывки скорости — см. carryBody.
--
-- Из смещения вычитается его же среднее (BODY_MEAN): нужна именно КАЧКА вокруг маршрута,
-- а постоянная составляющая означала бы, что жук едет мимо своей маршрутной точки —
-- и копилась бы, потому что стойки ног отсчитываются от тела.
-- Поворот. Маршрут меняет направление мгновенно (угол пути, испуг, отскок от стены),
-- а тело доворачивается к нему с ограниченной угловой скоростью: быстрее при большом
-- рассогласовании, мягко «доезжает» у цели. Ступни стоят, пока тело крутится, поэтому
-- поворот сам вызывает перешагивание — как у живого жука. Разворот на 180° ≈ 0.8 сек.
local TURN_EASE = 8 -- 1/сек: угловая скорость = рассогласование × TURN_EASE
local TURN_RATE_MIN = 1.5 -- рад/сек: чтобы последние градусы не тянулись вечно
local TURN_RATE_MAX = 4 -- рад/сек: потолок, ~230°/сек
local headings = setmetatable({}, { __mode = "k" })

-- Наклон в повороте: крен внутрь дуги пропорционален «центробежному» угловая скорость × ход.
-- Скорость берётся в единицах Стандарта (÷ gaitScale), чтобы гигант не заваливался на бок.
local LEAN_GAIN = 0.012 -- рад крена на (рад/сек × ст/сек)
local LEAN_MAX = 0.16 -- рад, ~9°
local LEAN_FOLLOW = 7 -- 1/сек: как быстро крен догоняет цель

-- Вздрагивание от попадания: тело отскакивает от точки удара и возвращается критически
-- демпфированной пружиной (без колебаний). Размер — в долях распорки ноги (см. state.strut).
local FLINCH_SHIFT = 0.18 -- пик смещения при полной силе, доля распорки
local FLINCH_FLOOR = 0.35 -- сила самого слабого попадания (иначе мелкий урон не виден)
local FLINCH_GAIN = 3 -- сила = FLOOR + доля урона × GAIN, потолок 1
local FLINCH_OMEGA = 18 -- 1/сек: жёсткость пружины, пик через 1/OMEGA ≈ 0.06 сек
local FLINCH_TILT = 1.2 -- рад крена на одну распорку смещения: верх уходит от удара

-- Голова раньше тела: на повороте голова (с усиками и жвалами) уже смотрит туда, куда
-- тело только доворачивает (см. TURN_*). Только у жуков с моделью head.
local NECK_MAX = 0.45 -- рад, ~26° в каждую сторону
local NECK_FOLLOW = 14 -- 1/сек
-- Усики: слабое покачивание + инерция (отстают при разгоне и повороте).
local ANTENNA_SWAY = 0.12 -- рад
local ANTENNA_FREQ = 2.6 -- рад/сек
local ANTENNA_TURN_LAG = 0.08 -- рад отставания на рад/сек поворота
local ANTENNA_ACCEL_LAG = 0.02 -- рад на ст/сек² ускорения (в единицах Стандарта)
local ANTENNA_MAX = 0.35 -- рад, потолок отставания
-- Жвалы: медленно шевелятся на ходу, часто и широко — когда жук грызёт.
local MANDIBLE_OPEN = 0.12 -- рад
local MANDIBLE_FREQ = 3 -- рад/сек
local MANDIBLE_CHEW_OPEN = 0.35 -- рад
local MANDIBLE_CHEW_FREQ = 16 -- рад/сек

local BODY_FOLLOW = 0.6 -- какую долю расхождения «где тело по ногам» отыгрывать
local BODY_MEAN = 1.5 -- 1/сек, скорость забывания постоянной составляющей (τ ≈ 0.7с)
local BODY_SETTLE = 12 -- 1/сек, подтягивание к цели: сглаживает пересменку трипода

-- Потолки качки в долях длины ноги. Вдоль хода потолок вдвое ниже, чем по высоте,
-- и это не вкусовщина: продольное смещение ПРИБАВЛЯЕТСЯ к скорости хода, и качок
-- амплитудой A на частоте f даёт прибавку 2πfA. На наших ~3.3 шагах в секунду
-- амплитуда 0.35 стоила ±10-16 studs/сек при ходе 10 (замерено стендом) — жук
-- не толкался, а дёргался и на мгновение ехал назад. У живого насекомого продольный
-- рывок тоже малый — единицы процентов длины тела за шаг; походка читается
-- вертикалью и креном, а не рывками взад-вперёд.
local BODY_SWAY = 0.05
local BODY_LIFT = 0.08

-- Крен и тангаж, радиан на единицу перекоса (перекос — в долях длины ноги).
--
-- Крен нарочно МЕНЬШЕ геометрически честного. Замеренный перекос бортов — ±1.2 studs
-- на колее шириной ~3.5, то есть «честный» крен был бы около 9°. Живое насекомое так
-- не болтается — оно активно держит корпус мышцами, и переваливание у него в градусах
-- единицы. С полным креном жук упирался в потолок каждый кадр (замерено: средний 4.8°
-- при потолке 5.2°) — то есть качался квадратной волной, что читается как дефект.
local BODY_ROLL = 0.15
local BODY_ROLL_MAX = 0.07 -- потолок крена, рад (~4°): страховка на резкие случаи, а не рабочий режим
local BODY_PITCH = 0.6

-- Луч опоры: откуда и насколько далеко светить вниз по телу, studs. Запас вверх нужен
-- для ступенек (плита Бура, крошка Горы): её верх выше номинальной ступни, и луч из-под
-- самой ступни её бы не заметил.
local PROBE_UP = 1.4
local PROBE_LENGTH = 3.2

-- На сколько шире ставятся ноги, когда жук лезет: на вертикали он распластывается
-- по поверхности, а не стоит на ней столбиком.
local CLIMB_SPREAD = 1.15

-- Насколько нога вообще может вытянуться сверх собственной длины. Без потолка жук,
-- которого уносит от вставшей ступни (толкучка, рывок перелезания, просадка кадров),
-- отращивает за собой чёрные палки — именно это видно на плейтесте в первую очередь.
local MAX_STRETCH = 1.25

-- Грызня: насколько передние ноги поднимаются на преграду и как быстро они работают.
-- Поза обязана читаться как «занят делом» (визуальный документ, раздел 5), а не как
-- «встал и ждёт».
local CHEW_RAISE = 0.85 -- studs вверх по телу
local CHEW_REACH = 0.7 -- studs вперёд, к преграде
local CHEW_RATE = 6 -- качков в секунду
local CHEW_SWING = 0.16 -- studs амплитуды

-- Поза смерти: насколько лапы разъезжаются наружу и насколько ниже бедра остаётся
-- ступня. Отличаться от любого дебафф-состояния поза обязана по требованию читаемости
-- (v2, раздел 4): поле из трупов не должно читаться как толпа застывших живых — здесь это
-- держится на расползшихся лапах и выцветании (см. Corpses), а не на перевёртыше.
local DEATH_SPLAY = 1.25
local DEATH_DROP = 0.3

-- Состояние ног по моделям. Слабые ключи: жук умирает в десятках мест кода (снаряд,
-- горение, рестарт забега), и обязывать каждое из них сообщить об этом походке значит
-- завести ещё один способ протечь памятью.
local states = setmetatable({}, { __mode = "k" })

-- Опоры, на которые жук вообще может встать ногой. Список разрешительный (Include),
-- а не запретительный: перечислить то, на что МОЖНО (пол, постройки, стены загона),
-- короче и надёжнее, чем перечислять всё, за что нога цепляться не должна (другие жуки,
-- трупы, снаряды, сам игрок, кровь на полу).
--
-- Собирается заново не чаще раза в секунду: папки появляются на лету, а лучей
-- тут тысячи в секунду, и пересобирать список на каждый — чистый мусор.
local surfaceParams = nil
local surfaceParamsClock = 0

local function groundFilter()
	local now = os.clock()
	if surfaceParams and now - surfaceParamsClock < 1 then
		return surfaceParams
	end

	local include = {}
	-- Пол и стены — из активной локации (Workspace.Location), постройки — общая папка.
	local location = Workspace:FindFirstChild("Location")
	for _, node in {
		location and location:FindFirstChild("ArenaFloor"),
		Workspace:FindFirstChild("Towers"),
		location and location:FindFirstChild("Walls"),
	} do
		table.insert(include, node)
	end
	-- Поле Аркады — именно поле, а не папка целиком: в ней же машина и сами жуки. Без него
	-- луч там ни во что не попадал, ступня вставала в плоскость тела, и на крене лапы одного
	-- борта висели в воздухе (до 1.5 studs), а другого уходили в пол — замерено.
	local arcade = Workspace:FindFirstChild("Arcade")
	local arcadeField = arcade and arcade:FindFirstChild("Field")
	if arcadeField then
		table.insert(include, arcadeField)
	end

	surfaceParams = RaycastParams.new()
	surfaceParams.FilterType = Enum.RaycastFilterType.Include
	surfaceParams.FilterDescendantsInstances = include
	surfaceParams.IgnoreWater = true
	surfaceParamsClock = now
	return surfaceParams
end

-- Ставит ногу-модель (сегментированная лапа процедурного жука) от бедра к ступне
-- двухсуставной инверсией: бедро дотягивается до колена, голень — до кончика.
-- Поворот ноги целиком жёстким рычагом здесь был и убран: на ходу ступня уходит далеко
-- позади, и выпрямленная лапа-палка торчит в небо (замерено стендом). Со сгибом ступня
-- встаёт точно в цель, колено складывается само, а нахлёсты сегментов сохраняются как
-- в покое: длины бедра и голени не меняются, меняется только их угол.
-- l1 — бедро (бедро→колено), l2 — голень до лодыжки, l2t — голень до кончика.
-- poleLocal — направление сгиба в кадре тела (снято в Attach): колени смотрят так же,
-- как слепил генератор (вверх-наружу), а не куда попало.
--
-- Ориентация самих сегментов снимается с ПОЗЫ ПОКОЯ, а не подразумевается: у лапы
-- из примитивов длинная ось — локальный X (цилиндр), а у лапы из мешей геометрия
-- запечена в мировых осях Blender и локальные оси меша не значат ничего. Поэтому
-- каждому сегменту в Attach считается его собственный сдвиг относительно кости
-- (boneFrame ниже), и на ходу сегмент ставится как «кость × сдвиг покоя». Цилиндру
-- сдвиг выходит почти единичным — поворот вокруг собственной оси у него не виден.
--
-- Кадр кости: начало — середина отрезка, X — вдоль кости (та же ось, что у цилиндра),
-- Y — по направлению сгиба колена. Опора на сгиб, а не на мировой верх: кость на ходу
-- уходит и в вертикаль тоже, и кадр от мирового верха там переворачивался бы, закручивая
-- меш вокруг своей оси.
local function boneFrame(a, b, pole)
	local axis = b - a
	local len = axis.Magnitude
	if len < 1e-4 then
		return nil
	end
	axis = axis / len
	local up = pole - axis * pole:Dot(axis)
	if up.Magnitude < 1e-4 then
		up = math.abs(axis.Y) < 0.9 and Vector3.yAxis:Cross(axis) or Vector3.xAxis:Cross(axis)
	end
	up = up.Unit
	return CFrame.fromMatrix((a + b) * 0.5, axis, up)
end

-- Ставит сегмент по его кости: сохранённый сдвиг покоя переносит меш ровно туда, где
-- он стоял у скульптора, но уже относительно новой позы кости.
local function placeSegment(part, frame, offset)
	if part and frame then
		part.CFrame = offset and (frame * offset) or frame
	end
end

local function placeModelLeg(leg, hip, foot, bodyCF)
	local toFoot = foot - hip
	local dist = toFoot.Magnitude
	if dist < 1e-3 then
		return
	end
	local dir = toFoot / dist
	-- Анатомический предел: дальше вытянутой лапы (бедро + голень) кончик не уедет.
	-- Цилиндру тут дотягивает Size, а шарниру нечем — недостижимая цель превращается
	-- в полностью выпрямленную лапу в её сторону.
	local reach = leg.l1 + leg.l2t
	local clamped = math.min(dist, reach - 1e-3)
	local target = hip + dir * clamped
	-- Полюс сгиба в мировых координатах, строго перпендикулярно оси ноги.
	local pole = bodyCF:VectorToWorldSpace(leg.poleLocal)
	pole = pole - dir * pole:Dot(dir)
	if pole.Magnitude < 1e-3 then
		pole = math.abs(dir.Y) < 0.9 and Vector3.yAxis:Cross(dir) or Vector3.xAxis:Cross(dir)
	else
		pole = pole.Unit
	end
	local cosA = math.clamp((leg.l1 * leg.l1 + clamped * clamped - leg.l2t * leg.l2t) / (2 * leg.l1 * clamped), -1, 1)
	local sinA = math.sqrt(math.max(0, 1 - cosA * cosA))
	local knee = hip + dir * (leg.l1 * cosA) + pole * (leg.l1 * sinA)
	-- Лодыжка — в той же доле голени, что в покое; лапка — между ней и кончиком.
	local ankle = knee + (target - knee) * (leg.l2 / leg.l2t)
	local femurBone = boneFrame(hip, knee, pole)
	local tibiaBone = boneFrame(knee, target, pole)
	local tarsusBone = boneFrame(ankle, target, pole)
	local rest = leg.rest0
	placeSegment(leg.femur, femurBone, rest and rest.femur)
	placeSegment(leg.knee, femurBone, rest and rest.knee)
	placeSegment(leg.tibia, tibiaBone, rest and rest.tibia)
	placeSegment(leg.ankle, tibiaBone, rest and rest.ankle)
	placeSegment(leg.tarsus1, tarsusBone, rest and rest.tarsus1)
	placeSegment(leg.tarsus, tarsusBone, rest and rest.tarsus)
	if not rest then
		-- Лапа из примитивов: суставы — шарики, им кадр кости не нужен.
		leg.knee.CFrame = CFrame.new(knee)
		leg.ankle.CFrame = CFrame.new(ankle)
		leg.tarsus.CFrame = CFrame.new(target)
	end
end

-- Ставит часть-ногу от бедра к ступне. Цилиндр вытянут вдоль локальной X, поэтому
-- lookAt доворачивается на 90° по Y — тот же приём, что был при сборке модели.
--
-- Длина меняется вместе с расстоянием: нога тянется к опоре, которая ниже или выше
-- номинальной — иначе на ступеньке ступня висела бы в воздухе. Переписывается только
-- по заметному изменению: Size — реплицируемое свойство, и дёргать его на сотые доли
-- каждый кадр — трафик ни за что.
local function placeLeg(leg, hip, foot, bodyCF)
	local delta = foot - hip
	local length = delta.Magnitude
	if length < 1e-3 then
		return
	end

	-- Нога не резиновая: дальше своей длины с небольшим запасом она не тянется,
	-- а просто не достаёт до опоры — так же, как у настоящего жука. У ноги-модели
	-- length — это бедро + голень (см. Attach): недостижимая цель выпрямляет лапу.
	local limit = leg.length * MAX_STRETCH
	if length > limit then
		foot = hip + delta / length * limit
		length = limit
	end

	-- Нога-модель не ресайзится (у Model нет Size): работает инверсия суставов.
	if leg.isModel then
		placeModelLeg(leg, hip, foot, bodyCF)
		return
	end

	leg.part.CFrame = CFrame.lookAt(hip:Lerp(foot, 0.5), foot) * CFrame.Angles(0, math.rad(90), 0)
	if math.abs(leg.part.Size.X - length) > 0.05 then
		leg.part.Size = Vector3.new(length, leg.thickness, leg.thickness)
	end
end

-- Точка постановки ступни впереди по ходу (см. MODEL_STEP_PLANT). От номинальной стойки
-- отходим по направлению движения ровно настолько, чтобы лапа оказалась вытянута на reach.
-- Это пересечение луча с сферой вокруг бедра — квадратное уравнение, а не подбор: шаг
-- сам выходит таким, какой лапа физически может сделать, на любом размере жука.
--
-- Нейтраль уже дальше reach (лапа распластана на лазанье) — выносить некуда, ставим
-- в нейтраль: сужать стойку ради выноса хуже, чем отказаться от выноса.
local function plantAhead(hip, nominal, travel, reach, limit)
	if not reach or travel.Magnitude < 1e-3 then
		return nominal
	end

	local dir = travel.Unit
	local h = nominal - hip
	local b = h:Dot(dir)
	local disc = b * b - h:Dot(h) + reach * reach
	if disc <= 0 then
		return nominal
	end

	local s = math.clamp(-b + math.sqrt(disc), 0, limit)
	return nominal + dir * s
end


-- Где стоит тело, если его несут ноги (см. блок BODY_* выше). Ответ собирается по тем
-- ступням, что СЕЙЧАС на земле; нога в переносе не считается — она ничего не держит.
--
-- Горизонталь. Стоящая ступня говорит: «тело полагается вот здесь» — там, где стойка
-- этой ноги совпала бы с её ступнёй. Пока ступня стоит, а маршрут уезжает, эта точка
-- отстаёт и тянет корпус назад (торможение). На пересменке трипода свежие ступни встают
-- впереди, точка прыгает вперёд — корпус толкается. Дважды за цикл, как у живого.
--
-- Вертикаль считается отдельно и по-другому — как перевёрнутый маятник. Нога держит свою
-- длину, значит бедро может быть выше ступни ровно на sqrt(распорка² − вынос²): ступня
-- под бедром — тело в верхней точке, ступня уехала — тело просело. Через «где была бы
-- стойка» это не выразить: на ровном полу все ступни на одной высоте, и подъём вышел бы
-- постоянным.
-- Голова, усики и жвалы шаблонного жука: детали в кадре тела в покое и точки шарниров.
-- У примитивов модели head нет — nil, и оживление головы просто не запускается.
local function captureHead(model)
	local head = model:FindFirstChild("head")
	local headBase = head and head:FindFirstChild("HeadBase", true)
	if not headBase then
		return nil
	end
	local pivot = model:GetPivot()

	local function group(instance, jointName, side)
		local parts = {}
		for _, part in instance:GetDescendants() do
			if part:IsA("BasePart") then
				table.insert(parts, { part = part, rest = pivot:ToObjectSpace(part.CFrame) })
			end
		end
		local joint = jointName and instance:FindFirstChild(jointName, true)
		local at = joint and pivot:PointToObjectSpace(joint.Position)
		return { parts = parts, joint = at, side = side or (at and (at.X >= 0 and 1 or -1)) or 1 }
	end

	-- Шея — задний край головы (голова смотрит по +Z тела).
	local base = pivot:PointToObjectSpace(headBase.Position)
	local depth = math.min(headBase.Size.X, headBase.Size.Z) * 0.5
	local rig = {
		neck = base - Vector3.new(0, 0, depth),
		head = group(head),
		antennae = {},
		mandibles = {},
		phase = math.random() * math.pi * 2,
	}
	for _, name in { "antenna_left", "antenna_right" } do
		local antenna = model:FindFirstChild(name)
		if antenna then
			table.insert(rig.antennae, group(antenna, "AntSeg1"))
		end
	end
	for _, name in { "mandible_left", "mandible_right" } do
		local mandible = model:FindFirstChild(name)
		if mandible then
			table.insert(rig.mandibles, group(mandible, "MandibleJoint"))
		end
	end
	return rig
end

-- Поворот вокруг точки в кадре тела.
local function around(point, rotation)
	return CFrame.new(point) * rotation * CFrame.new(-point)
end

local function poseHead(state, body, dt, mode, turnRate, headLead)
	local rig = state.head
	local t = state.clock + rig.phase
	local scale = state.gaitScale or 1

	local lead = math.clamp(headLead, -NECK_MAX, NECK_MAX)
	state.neckYaw = (state.neckYaw or 0) + (lead - (state.neckYaw or 0)) * math.clamp(dt * NECK_FOLLOW, 0, 1)
	local neck = around(rig.neck, CFrame.Angles(0, state.neckYaw, 0))

	-- Ускорение вдоль носа — из сглаженной скорости хода (state.velocity считает Step).
	local forward = body:VectorToObjectSpace(state.velocity or Vector3.zero).Z / scale
	local accel = dt > 1e-4 and (forward - (state.lastForward or forward)) / dt or 0
	state.lastForward = forward
	state.antennaAccel = (state.antennaAccel or 0) + (accel - (state.antennaAccel or 0)) * math.clamp(dt * 6, 0, 1)

	local parts, frames = {}, {}
	local function place(entry, local_)
		table.insert(parts, entry.part)
		table.insert(frames, body * local_ * entry.rest)
	end

	for _, entry in rig.head.parts do
		place(entry, neck)
	end

	local lagYaw = math.clamp(-turnRate * ANTENNA_TURN_LAG, -ANTENNA_MAX, ANTENNA_MAX)
	local lagPitch = math.clamp(state.antennaAccel * ANTENNA_ACCEL_LAG, -ANTENNA_MAX, ANTENNA_MAX)
	for index, antenna in rig.antennae do
		if antenna.joint then
			local wave = t * ANTENNA_FREQ + index * 1.7
			local rotation = CFrame.Angles(
				ANTENNA_SWAY * 0.6 * math.sin(wave * 1.3) + lagPitch,
				ANTENNA_SWAY * math.sin(wave) + lagYaw,
				0
			)
			local joint = neck * around(antenna.joint, rotation)
			for _, entry in antenna.parts do
				place(entry, joint)
			end
		end
	end

	local chewing = mode == "chew"
	local open = chewing and MANDIBLE_CHEW_OPEN or MANDIBLE_OPEN
	local freq = chewing and MANDIBLE_CHEW_FREQ or MANDIBLE_FREQ
	local gape = open * (0.5 + 0.5 * math.sin(t * freq))
	for _, mandible in rig.mandibles do
		if mandible.joint then
			-- +угол вокруг Y уводит кончик (+Z) к +X: жвала справа раскрывается наружу с плюсом.
			local joint = neck * around(mandible.joint, CFrame.Angles(0, gape * mandible.side, 0))
			for _, entry in mandible.parts do
				place(entry, joint)
			end
		end
	end

	workspace:BulkMoveTo(parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
end

-- Крен в повороте и вздрагивание — поверх качки от ног (см. carryBody).
local function react(state, body, dt, turnRate)
	local up = body.UpVector
	local speed = (state.velocity or Vector3.zero).Magnitude / (state.gaitScale or 1)
	local leanTarget = math.clamp(turnRate * speed * LEAN_GAIN, -LEAN_MAX, LEAN_MAX)
	state.lean = (state.lean or 0) + (leanTarget - (state.lean or 0)) * math.clamp(dt * LEAN_FOLLOW, 0, 1)

	local rotation = CFrame.identity
	if math.abs(state.lean) > 1e-4 then
		-- Положительный угол доворота — поворот налево; поворот вокруг хвоста на +φ валит
		-- верх туда же, внутрь дуги. Хвост — это LookVector: голова модели по +Z.
		rotation = CFrame.fromAxisAngle(body.LookVector, state.lean)
	end

	local offset = state.flinchOffset or Vector3.zero
	local velocity = state.flinchVelocity
	if velocity then
		-- Критически демпфированная пружина; шаг дробится, чтобы просадка кадра не раскачала её.
		local steps = math.clamp(math.ceil(dt / 0.01), 1, 10)
		local h = dt / steps
		for _ = 1, steps do
			velocity += (-offset * FLINCH_OMEGA * FLINCH_OMEGA - velocity * 2 * FLINCH_OMEGA) * h
			offset += velocity * h
		end
		if offset.Magnitude < 1e-3 and velocity.Magnitude < 1e-2 then
			offset, velocity = Vector3.zero, nil
		end
		state.flinchOffset, state.flinchVelocity = offset, velocity
	end
	if offset.Magnitude > 1e-4 then
		local tilt = offset.Magnitude / (state.strut or 1) * FLINCH_TILT
		local axis = up:Cross(offset.Unit)
		if axis.Magnitude > 1e-3 then
			rotation = CFrame.fromAxisAngle(axis.Unit, tilt) * rotation
		end
	end

	return CFrame.new(body.Position + offset) * rotation * body.Rotation
end

local function carryBody(state, path, dt, now)
	local up = path.UpVector
	local sum, lift, stance = Vector3.zero, 0, 0
	local sinkPlus, sinkMinus, nPlus, nMinus = 0, 0, 0, 0

	for _, leg in state.legs do
		local planted = leg.planted
		if planted and now >= leg.stepUntil then
			sum += planted - path:VectorToWorldSpace(leg.rest)

			local strut = leg.strut
			if strut and strut > 1e-3 then
				local fromHip = planted - path * leg.hip
				local alongUp = fromHip:Dot(up) -- отрицателен: ступня ниже бедра
				local flat = (fromHip - up * alongUp).Magnitude
				local hold = math.sqrt(math.max(strut * strut - flat * flat, 0))
				local sink = hold + alongUp -- в покое ровно 0, дальше — только вниз
				lift += sink

				-- Просадка по бортам копится отдельно — отсюда переваливание (см. BODY_ROLL).
				-- Среднее положение ступней для этого не годится: по боку оно тождественный ноль
				-- (замерено стендом: 0.000) — шесть ног симметричны и гасят друг друга.
				-- А вот НАГРУЗКА несимметрична: в триподе две лапы одного борта и одна
				-- другого, поэтому борта проседают в противофазе, и тело валится то туда, то сюда.
				if leg.rest.X > 0 then
					sinkPlus += sink
					nPlus += 1
				else
					sinkMinus += sink
					nMinus += 1
				end
			end
			stance += 1
		end
	end

	if stance == 0 then
		-- Все ноги в воздухе (кадр пересменки) — держим прошлое смещение, а не
		-- обнуляем: иначе на каждый такой кадр тело дёргалось бы к маршруту.
		return path * CFrame.new(state.carry or Vector3.zero)
	end

	local flatRaw = path:VectorToObjectSpace(sum / stance - path.Position)
	local raw = Vector3.new(flatRaw.X, lift / stance, flatRaw.Z)

	-- Постоянную составляющую забываем (см. BODY_MEAN): маршрут — правда о том, где жук,
	-- качка — только рябь вокруг него.
	state.carryMean = state.carryMean and state.carryMean:Lerp(raw, math.clamp(dt * BODY_MEAN, 0, 1)) or raw

	local strutRef = state.strut or 1
	local sway = strutRef * BODY_SWAY
	local rise = strutRef * BODY_LIFT
	local wobble = (raw - state.carryMean) * BODY_FOLLOW
	wobble = Vector3.new(
		math.clamp(wobble.X, -sway, sway),
		math.clamp(wobble.Y, -rise, rise),
		math.clamp(wobble.Z, -sway, sway)
	)
	local settle = math.clamp(dt * BODY_SETTLE, 0, 1)
	state.carry = state.carry and state.carry:Lerp(wobble, settle) or wobble

	-- Крен — из разницы просадки бортов: тело валится на тот борт, чьи лапы сейчас
	-- вытянуты сильнее (он ниже держит). Тангаж — из продольного смещения: опора
	-- ушла назад — значит жука толкают сзади, и нос идёт кверху.
	local tilt = 0
	if nPlus > 0 and nMinus > 0 then
		tilt = sinkPlus / nPlus - sinkMinus / nMinus
	end
	-- Из перекоса тоже вычитается среднее: борта шаблона не совсем зеркальны, и без
	-- этого жук ехал с постоянным креном в 5° на один бок (замерено стендом) — это
	-- читалось как криво собранная модель, а не как походка. Нужно переваливание, а не наклон.
	state.tiltMean = state.tiltMean and state.tiltMean + (tilt - state.tiltMean) * math.clamp(dt * BODY_MEAN, 0, 1) or tilt
	local swing = tilt - state.tiltMean
	state.carryRoll = state.carryRoll and state.carryRoll + (swing - state.carryRoll) * settle or swing

	local offset = state.carry
	-- tilt < 0 — борт +X просел сильнее; поворот вокруг оси носа опускает его туда же.
	local roll = math.clamp(state.carryRoll / strutRef * BODY_ROLL, -BODY_ROLL_MAX, BODY_ROLL_MAX)
	local pitch = (offset.Z / strutRef) * BODY_PITCH
	return path * CFrame.new(offset) * CFrame.Angles(pitch, 0, roll)
end

-- Где опора под номинальной стуйкой. Нет опоры (жук над краем, висит над проломом) —
-- нога остаётся там, где ей полагается быть по строению тела: пусть висит, но не тянется
-- к бесконечности.
local function findSupport(nominal, up, gaitScale)
	local scale = gaitScale or 1
	local result = Workspace:Raycast(nominal + up * (PROBE_UP * scale), -up * (PROBE_LENGTH * scale), groundFilter())
	return result and result.Position or nominal
end

-- Заводит походку для модели. legs — тот же список, по которому собрана модель
-- (см. EnemySpawner.buildEnemyModel): анатомия остаётся там, где строится тело, а не
-- восстанавливается здесь обратным счётом по CFrame готовых частей.
--
-- Ноги делятся на две группы по диагонали (передняя левая с задней правой и наоборот):
-- одновременно переступает только одна группа, вторая в это время держит тело.
-- Без этого все четыре ноги переступают в один и тот же кадр — это читается как прыжок,
-- а не как ходьба.
--
-- Шестиногу диагональное правило не покрывает (даёт иноходь тройками вместо трипода),
-- поэтому сборщик модели может передать group и front явно — для примитивов работают
-- те же умолчания, что раньше. Нога-модель (Model вместо BasePart) не имеет Size:
-- толщину ей хранить негде и не нужно. Вместо этого снимаются длины звеньев
-- и направление сгиба — по ним placeModelLeg гнёт лапу инверсией (см. выше).
-- length у модели — бедро + голень (анатомический предел, не стойка покоя).
function EnemyGait.Attach(model, legs)
	-- Свой масштаб похода: во сколько раз этот экземпляр крупнее/мельче Стандарта, под
	-- которого подобраны MODEL_STRIDE и остальные абсолютные величины (см. GAIT_TUNED_SCALE).
	local gaitScale = (model:GetAttribute("Scale") or GAIT_TUNED_SCALE) / GAIT_TUNED_SCALE
	local state = { legs = {}, clock = 0, turn = nil, gaitScale = gaitScale }

	for index, leg in legs do
		local isModel = leg.part:IsA("Model")
		local entry = {
			part = leg.part,
			hip = leg.hip,
			rest = leg.foot,
			isModel = isModel or nil,
			thickness = not isModel and leg.part.Size.Y or nil,
			length = (leg.foot - leg.hip).Magnitude, -- собственная длина ноги, потолок растяжения
			front = leg.front ~= nil and leg.front or leg.foot.Z > 0,
			-- Группа по диагонали: знаки X и Z совпали — одна группа, разошлись — другая.
			group = leg.group or (((leg.foot.X > 0) == (leg.foot.Z > 0)) and 1 or 2),
			planted = nil, -- мировая точка ступни; nil — ещё не вставал
			stepFrom = nil,
			stepTo = nil,
			stepUntil = 0,
			index = index,
		}

		-- Нога как распорка: её рабочая длина в позе покоя (см. carryBody). По ней считается,
		-- насколько тело оседает, когда ступня уходит от стойки вперёд или назад. Берётся
		-- именно покой, а не анатомический предел: на пределе лапа выпрямлена в палку,
		-- а держит тело она полусогнутой.
		local restFlat = Vector3.new(leg.foot.X - leg.hip.X, 0, leg.foot.Z - leg.hip.Z).Magnitude
		entry.restFlat = restFlat
		entry.strut = math.sqrt(restFlat * restFlat + (leg.hip.Y - leg.foot.Y) ^ 2)

		if isModel then
			local function needPart(name)
				local p = leg.part:FindFirstChild(name, true)
				assert(p and p:IsA("BasePart"),
					("[EnemyGait] у ноги-модели %s нет %s"):format(leg.part:GetFullName(), name))
				return p
			end
			entry.femur = needPart("Femur")
			entry.knee = needPart("KneeJoint")
			entry.tibia = needPart("Tibia")
			entry.ankle = needPart("AnkleJoint")
			entry.tarsus = needPart("Tarsus2")
			entry.tarsus1 = needPart("Tarsus1")
			-- Анатомия в кадре тела (модель при сборке стоит в покое, пивот выставлен):
			-- все длины и сгиб — инварианты жёсткого тела, переживут любой PivotTo.
			local bodyCF = model:GetPivot()
			local kneeLocal = bodyCF:PointToObjectSpace(entry.knee.Position)
			local ankleLocal = bodyCF:PointToObjectSpace(entry.ankle.Position)
			local axis = (leg.foot - leg.hip).Unit
			local bend = (kneeLocal - leg.hip) - axis * (kneeLocal - leg.hip):Dot(axis)
			if bend.Magnitude < 1e-3 then
				bend = Vector3.yAxis
			else
				bend = bend.Unit
			end
			entry.l1 = (kneeLocal - leg.hip).Magnitude
			entry.l2 = (ankleLocal - kneeLocal).Magnitude
			entry.l2t = (leg.foot - kneeLocal).Magnitude
			entry.poleLocal = bend
			entry.length = entry.l1 + entry.l2t

			-- Порог перетягивания именно этой лапы, в мировых studs (см. MODEL_STEP_REACH).
			-- Длины уже в масштабе экземпляра, поэтому gaitScale здесь не нужен.
			entry.stepReach = entry.length * MODEL_STEP_REACH

			-- Сдвиг каждого сегмента относительно своей кости — снят с позы покоя
			-- шаблона (см. boneFrame). Он и держит ориентацию мешей, у которых геометрия
			-- запечена в мировых осях экспорта, а не вдоль собственной оси части.
			-- У старой лапы-цилиндра сдвиг выходит поворотом вокруг собственной оси — не виден.
			local hipWorld = bodyCF * leg.hip
			local footWorld = bodyCF * leg.foot
			-- Полюс готовится точно так же, как на ходу (см. placeModelLeg): иначе кадры покоя
			-- и движения разойдутся на постоянный закрут, и лапа встанет боком сразу же.
			local restDir = (footWorld - hipWorld).Unit
			local poleWorld = bodyCF:VectorToWorldSpace(bend)
			poleWorld = poleWorld - restDir * poleWorld:Dot(restDir)
			poleWorld = poleWorld.Magnitude > 1e-3 and poleWorld.Unit or bodyCF:VectorToWorldSpace(bend)
			local femurBone = boneFrame(hipWorld, entry.knee.Position, poleWorld)
			local tibiaBone = boneFrame(entry.knee.Position, footWorld, poleWorld)
			local tarsusBone = boneFrame(entry.ankle.Position, footWorld, poleWorld)
			if femurBone and tibiaBone and tarsusBone then
				entry.rest0 = {
					femur = femurBone:Inverse() * entry.femur.CFrame,
					knee = femurBone:Inverse() * entry.knee.CFrame,
					tibia = tibiaBone:Inverse() * entry.tibia.CFrame,
					ankle = tibiaBone:Inverse() * entry.ankle.CFrame,
					tarsus1 = tarsusBone:Inverse() * entry.tarsus1.CFrame,
					tarsus = tarsusBone:Inverse() * entry.tarsus.CFrame,
				}
			end
		end
		table.insert(state.legs, entry)
	end

	-- Средняя распорка — единственная физическая мерка этого экземпляра. От неё берутся
	-- потолки качки тела (см. BODY_SWAY/BODY_LIFT): мелкий Мини качается мелко, гигант —
	-- размашисто, и ни одной величины в studs подбирать под каждый вид не приходится.
	local strutSum = 0
	for _, entry in state.legs do
		strutSum += entry.strut or 0
	end
	state.strut = #state.legs > 0 and strutSum / #state.legs or 1

	state.head = captureHead(model)

	states[model] = state
	return state
end

-- Отскок живого жука от попадания. from — откуда прилетело, strength — доля макс. HP
-- (или близость к центру взрыва). Зовёт Impulse; маршрут и позиция жука не меняются —
-- только тело над ногами (см. react).
function EnemyGait.Flinch(model, from, strength)
	local state = states[model]
	if not state or not from then
		return
	end
	local pivot = model:GetPivot()
	local up = pivot.UpVector
	local away = pivot.Position - from
	away -= up * away:Dot(up)
	if away.Magnitude < 1e-3 then
		return
	end
	local power = math.clamp(FLINCH_FLOOR + (strength or 0) * FLINCH_GAIN, 0, 1)
	-- Пик критически демпфированной пружины с начальной скоростью v — v / (ω·e).
	local speed = (state.strut or 1) * FLINCH_SHIFT * power * FLINCH_OMEGA * math.exp(1)
	state.flinchVelocity = (state.flinchVelocity or Vector3.zero) + away.Unit * speed
end

-- Один кадр походки. mode: "walk" — идёт или стоит, "chew" — грызёт преграду,
-- "climb" — лезет через неё.
--
-- Стан отдельным режимом НЕ выделяется нарочно (правило v2: движение не имитирует
-- дебаффы, состояние рисует индикация): стоящий жук и так не переступает — тело не
-- уезжает от ступней, и порог шага не берётся сам собой.
--
-- pathCF — МАРШРУТНЫЙ кадр от спавнера: где жук находится для сетки, толкучки и прицела.
-- Передан — походка сама ставит модель (PivotTo), смещая видимое тело по ногам
-- (см. carryBody). Не передан — тело ведёт вызывающий, качки не будет.
-- На какой угол тело успевает довернуть за кадр при рассогласовании angle (рад).
-- Этим же доворотом пользуется толкучка (Crowd.Resolve): капсула, сквозь которую жуки
-- не проходят, обязана смотреть туда же, куда видимое тело, — иначе на повороте тело
-- отстаёт от капсулы и въезжает брюшком в соседа.
function EnemyGait.TurnStep(angle, dt)
	return math.clamp(math.abs(angle) * TURN_EASE, TURN_RATE_MIN, TURN_RATE_MAX) * dt
end

-- wantLook — куда смотрел бы жук без ограничения разворота (LookVector маршрутного кадра).
-- Нужен, когда разворот уже ограничила толкучка: голова по-прежнему идёт раньше тела.
function EnemyGait.Step(model, dt, mode, pathCF, wantLook)
	local turnRate, headLead = 0, 0
	if pathCF then
		-- Доворот тела к направлению маршрута вокруг его «верха» (не Slerp целиком:
		-- на развороте ровно в 180° тот выбирает ось наугад и может перевернуть жука).
		local up = pathCF.UpVector
		local look = pathCF.LookVector
		local previous = headings[model]
		if previous then
			previous -= up * previous:Dot(up)
		end
		if previous and previous.Magnitude > 1e-3 then
			previous = previous.Unit
			local angle = math.atan2(up:Dot(previous:Cross(look)), previous:Dot(look))
			local rate = EnemyGait.TurnStep(angle, dt)
			if math.abs(angle) > rate then
				look = CFrame.fromAxisAngle(up, math.sign(angle) * rate):VectorToWorldSpace(previous)
				headLead = angle - math.sign(angle) * rate
				turnRate = dt > 1e-4 and math.sign(angle) * rate / dt or 0
			else
				turnRate = dt > 1e-4 and angle / dt or 0
			end
		end
		headings[model] = look
		if wantLook then
			local want = wantLook - up * wantLook:Dot(up)
			if want.Magnitude > 1e-3 then
				want = want.Unit
				local lead = math.atan2(up:Dot(look:Cross(want)), look:Dot(want))
				if math.abs(lead) > math.abs(headLead) then
					headLead = lead
				end
			end
		end
		pathCF = CFrame.lookAt(pathCF.Position, pathCF.Position + look, up)
	end

	local state = states[model]
	if not state then
		-- Походки нет (жук без списка ног) — вести тело всё равно надо, иначе замрёт.
		if pathCF then
			model:PivotTo(pathCF)
		end
		return
	end

	local now = os.clock()
	local path = pathCF or model:GetPivot()
	local body = pathCF and carryBody(state, path, dt, now) or path
	if pathCF then
		body = react(state, body, dt, turnRate)
		model:PivotTo(body)
	end
	if state.head then
		poseHead(state, body, dt, mode, turnRate, headLead)
	end
	local up = body.UpVector
	local nose = body:VectorToWorldSpace(Vector3.new(0, 0, 1)) -- голова модели смотрит по +Z
	state.clock += dt

	-- Куда едет тело: по этому вектору ступня выносится вперёд (см. MODEL_STEP_PLANT).
	-- Считается по фактическому смещению пивота, а не по задуманной скорости вида:
	-- в толкучке, на повороте и на замедлении нога шагает туда, куда жук едет НА САМОМ ДЕЛЕ.
	local previous = state.lastPosition
	state.lastPosition = path.Position
	if previous and dt > 1e-4 then
		local sample = (path.Position - previous) / dt
		state.velocity = state.velocity
			and state.velocity:Lerp(sample, math.clamp(dt * VELOCITY_SMOOTH, 0, 1))
			or sample
	end
	local velocity = state.velocity or Vector3.zero

	-- Кто сейчас в воздухе: пока шагает одна группа, вторая ждёт.
	local stepping = nil
	for _, leg in state.legs do
		if now < leg.stepUntil then
			stepping = leg.group
			break
		end
	end

	-- Кто имеет право НАЧАТЬ перенос. Группы чередуются строго: после того, как одна
	-- троица переступила, следующая инициатива принадлежит другой. Без этого флаг-очередь
	-- брала бы группа, которой всегда есть куда шагать (короткий шаг при скорости 15 ст/с
	-- переступает каждые пару кадров), и вторая троица замирала бы на номинальных стойках
	-- навсегда — видно было, как пол-жука стоит, пол-жука скачет (замерено живым прогоном).

	for _, leg in state.legs do
		local rest = leg.rest

		-- Своя каденция ног-моделей (см. MODEL_* выше) — приведена к масштабу экземпляра:
		-- у Мини (Scale меньше Стандартовых 3.0) шаг и дуга короче во столько же раз, иначе
		-- они превышают анатомический предел собственной лапы (см. GAIT_TUNED_SCALE).
		local modelScale = leg.isModel and state.gaitScale or 1
		local stride = leg.isModel and (MODEL_STRIDE * modelScale) or STRIDE
		local stepTime = leg.isModel and MODEL_STEP_TIME or STEP_TIME
		local stepLift = leg.isModel and (MODEL_STEP_LIFT * modelScale) or STEP_LIFT

		if mode == "climb" then
			-- На вертикали жук распластывается: стойка шире и немного ближе к поверхности.
			rest = Vector3.new(rest.X * CLIMB_SPREAD, rest.Y + 0.35 * modelScale, rest.Z * CLIMB_SPREAD)
		elseif mode == "chew" and leg.front then
			-- Передние лапы упёрлись в преграду и работают: подняты, вынесены вперёд
			-- и качаются. Это то, что отличает «вгрызся» от «встал и ждёт».
			local swing = math.sin(state.clock * CHEW_RATE * math.pi * 2 + leg.index) * CHEW_SWING * modelScale
			rest = rest + Vector3.new(0, CHEW_RAISE * modelScale + swing, CHEW_REACH * modelScale + swing)
		end

		local hipWorld = body * leg.hip
		local nominal = body * rest

		if mode == "chew" and leg.front then
			-- Передняя лапа при грызне не шагает и не ищет опору под собой: она висит
			-- на преграде перед мордой. Связь со ступнёй-на-земле рвётся, чтобы после
			-- грызни она встала заново, а не тянулась к точке, где стояла до упора.
			leg.planted = nil
			leg.stepUntil = 0
			placeLeg(leg, hipWorld, nominal, body)
		elseif now < leg.stepUntil then
			-- Нога в переносе: дуга от старой точки к новой.
			local t = math.clamp(1 - (leg.stepUntil - now) / stepTime, 0, 1)
			local foot = leg.stepFrom:Lerp(leg.stepTo, t) + up * math.sin(t * math.pi) * stepLift
			placeLeg(leg, hipWorld, foot, body)
		else
			local planted = leg.planted
			-- Второй повод переступить — лапа вот-вот вытянется до предела (см. MODEL_STEP_REACH).
			-- Без него шаг брался только по отходу тела от ступни, а у меш-лапы запаса меньше
			-- этого порога втрое: ступня упиралась в предел и ехала за телом, вместо того
			-- чтобы стоять («лапы не успевают за торсом»).
			local needsStep = planted == nil or (nominal - planted).Magnitude > stride
				or (leg.stepReach ~= nil and (hipWorld - planted).Magnitude > leg.stepReach)

			-- Ход переноса у трипода: либо группа уже в движении (все лапы троицы
			-- переступают вместе), либо очередь свободна и подошла эта группа — но не
			-- сейчас же после собственного же переноса: иначе короткий шаг зажимал бы
			-- очередь в одной группе.
			if needsStep and (stepping == leg.group or (stepping == nil and (state.turn == nil or state.turn == leg.group))) then
				leg.stepFrom = planted or nominal
				-- Ступня идёт НЕ в нейтраль, а вперёд по ходу (см. plantAhead): иначе каждый
				-- шаг — догоняющий, и лапа всю опорную фазу только отстаёт от тела.
				local aim = leg.stepReach
					-- Вынос не больше половины шага: иначе ступня встаёт сразу за порогом отхода
					-- тела от ступни и требует следующий перенос в тот же кадр, как только встала.
					and plantAhead(hipWorld, nominal, velocity, leg.length * MODEL_STEP_PLANT, stride * 0.5)
					or nominal
				leg.stepTo = findSupport(aim, up, modelScale)
				leg.stepUntil = now + stepTime
				leg.planted = leg.stepTo
				if stepping == nil then
					state.turn = 3 - leg.group
				end
				stepping = leg.group
				placeLeg(leg, hipWorld, leg.stepFrom, body)
			else
				placeLeg(leg, hipWorld, planted or nominal, body)
			end
		end
	end
end

-- Поза смерти: ноги подламываются наружу и вверх, к брюху — жук оседает на брюхо,
-- а не валится на спину (решение автора: «после смерти не переворачивался, а падал»).
-- Ставится один раз при превращении в труп (см. Corpses) и больше не обновляется: дальше
-- трупом распоряжается физика.
--
-- Анатомия берётся у ЖИВОГО жука (original), а не восстанавливается обратным счётом
-- по готовым частям клона: бёдра и стойки уже записаны в состоянии походки, и второй
-- способ их узнать — лишний.
function EnemyGait.DeathPose(corpse, original)
	local state = states[original]
	local body = corpse.PrimaryPart
	if not state or not body then
		return
	end

	for _, leg in state.legs do
		-- Рекурсивно: ноги-модели шаблона лежат не только в корне (средние и задние —
		-- внутри под-модели тела), а имена у них уникальны. Примитивам это не мешает:
		-- Leg1..Leg4 тоже находятся, как раньше.
		local part = corpse:FindFirstChild(leg.part.Name, true)
		if part then
			local hip = body.CFrame * leg.hip
			local modelScale = leg.isModel and (state.gaitScale or 1) or 1
			-- Ступня уезжает наружу и поднимается почти до уровня брюха: лапы лежат
			-- плашмя вокруг тела, и корпус садится на землю, а не стоит на ходулях.
			local foot = body.CFrame * Vector3.new(
				leg.rest.X * DEATH_SPLAY,
				leg.hip.Y - DEATH_DROP * modelScale,
				leg.rest.Z * DEATH_SPLAY
			)
			local length = (foot - hip).Magnitude
			if length > 1e-3 then
				if leg.isModel and part:IsA("Model") then
					-- Лапа клона гнётся той же инверсией; меры берутся у живого жука
					-- (анатомия у клона та же), а части — у трупа.
					local function cpart(name)
						local p = part:FindFirstChild(name, true)
						return (p and p:IsA("BasePart")) and p or nil
					end
					local femur, knee, tibia = cpart("Femur"), cpart("KneeJoint"), cpart("Tibia")
					local ankle, tarsus, tarsus1 = cpart("AnkleJoint"), cpart("Tarsus2"), cpart("Tarsus1")
					if femur and knee and tibia and ankle and tarsus and tarsus1 then
						placeModelLeg({
							part = part,
							femur = femur,
							knee = knee,
							tibia = tibia,
							ankle = ankle,
							tarsus = tarsus,
							tarsus1 = tarsus1,
							l1 = leg.l1,
							l2 = leg.l2,
							l2t = leg.l2t,
							poleLocal = leg.poleLocal,
							rest0 = leg.rest0,
						}, hip, foot, body.CFrame)
					end
				elseif part:IsA("BasePart") then
					part.Size = Vector3.new(length, part.Size.Y, part.Size.Z)
					part.CFrame = CFrame.lookAt(hip:Lerp(foot, 0.5), foot) * CFrame.Angles(0, math.rad(90), 0)
				end
			end
		end
	end
end

return EnemyGait
