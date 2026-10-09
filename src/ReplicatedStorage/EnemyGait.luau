-- Походка жука: ноги переступают, корпус следует за ними.
--
-- Правило поз: «перебирание ног —
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
-- Спина соседа под лапой — по общей с толкучкой формуле (EnemyBody.BackHeight).
local EnemyBody = require(script.Parent:WaitForChild("EnemyBody"))
-- Почерк вида: множители и амплитуды поверх этой походки (EnemyGaitStyles). Все числа
-- ниже остаются числами СТАНДАРТА, а вид отличается от него множителем из таблицы —
-- так ни один вид не требует своей ветки в коде.
local EnemyGaitStyles = require(script.Parent:WaitForChild("EnemyGaitStyles"))

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

-- MODEL_STRIDE/MODEL_STEP_LIFT и абсолютные расстояния похода ниже (PROBE_*,
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

-- Крылья летунов (Моль, Пеликан): группы wing_L / wing_R шаблона машут вокруг своего
-- внутреннего края, пока жук в воздухе. Частота — взмахов в секунду, угол — в радианах
-- от покоя вверх и вниз. Шаблон может задать свои атрибутами WingFlapFreq / WingFlapAngle.
local WING_FLAP_FREQ = 3
local WING_FLAP_ANGLE = math.rad(35)
-- Как быстро крыло складывается в покой после посадки, 1/сек.
local WING_FOLD = 6

-- ======================= Тело ровное =======================
--
-- Референс — живой жук: корпус у него на ходу НЕ качается. Шесть ног держат его тройками,
-- и тело плывёт ровно, без подскока, валкости и крена; двигаются только ноги (решение
-- автора: «у реальных жуков тело не качается при ходьбе»). Раньше здесь была качка по
-- стоящим ступням (carryBody: просадка, крен, тангаж, рывки скорости), поверх неё почерк
-- вида (подскок, валкость) и крен в повороте — всё это убрано.
--
-- Видимое тело стоит ровно в маршрутном кадре спавнера. Поверх него остаются только
-- реакции, не связанные с ходьбой: вздрагивание от попадания (react) и дыхание стоящего
-- (flourish).
-- Поворот. Маршрут меняет направление мгновенно (угол пути, испуг, отскок от стены),
-- а тело доворачивается к нему с ограниченной угловой скоростью: быстрее при большом
-- рассогласовании, мягко «доезжает» у цели. Ступни стоят, пока тело крутится, поэтому
-- поворот сам вызывает перешагивание — как у живого жука. Разворот на 180° ≈ 0.8 сек.
local TURN_EASE = 8 -- 1/сек: угловая скорость = рассогласование × TURN_EASE
local TURN_RATE_MIN = 1.5 -- рад/сек: чтобы последние градусы не тянулись вечно
local TURN_RATE_MAX = 4 -- рад/сек: потолок, ~230°/сек
local headings = setmetatable({}, { __mode = "k" })

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
-- Жвалы: медленно шевелятся на ходу. В грызне их ведёт цикл укуса (BITE_GAPE_*).
local MANDIBLE_OPEN = 0.12 -- рад
local MANDIBLE_FREQ = 3 -- рад/сек

-- Луч опоры: откуда и насколько далеко светить вниз по телу, studs. Запас вверх нужен
-- для ступенек (плита Бура, крошка Горы): её верх выше номинальной ступни, и луч из-под
-- самой ступни её бы не заметил.
local PROBE_UP = 1.4
local PROBE_LENGTH = 3.2
-- Спины соседей для лап (см. neighbourBack) перечитываются не чаще, чем раз в столько
-- секунд: шагов за кадр десятки, а жуков сотня.
local BACKS_REFRESH = 0.05
-- Толщина ступни, доля высоты пивота: задевшая борт соседа ступня ложится на него.
-- То же число, что FOOT_RADIUS в Crowd.
local FOOT_RADIUS = 0.2

-- На сколько шире ставятся ноги, когда жук лезет: на вертикали он распластывается
-- по поверхности, а не стоит на ней столбиком.
local CLIMB_SPREAD = 1.15

-- Насколько нога вообще может вытянуться сверх собственной длины. Без потолка жук,
-- которого уносит от вставшей ступни (толкучка, рывок перелезания, просадка кадров),
-- отращивает за собой чёрные палки — именно это видно на плейтесте в первую очередь.
local MAX_STRETCH = 1.25

-- ======================= Грызня: удар по цели =======================
--
-- Раньше грызущий жук задирал передние лапы и тряс ими синусом, а жвалы трепетали —
-- до цели не дотягивалось ничего (жалоба автора: «просто трясут лапами и даже не
-- взаимодействуют жалами с целью»). Теперь грызня — это УДАР: ноги стоят на земле,
-- а работает корпус с головой.
--
-- Цикл одного укуса, по времени от его пика (момента, когда сервер снял HP):
--   замах   — корпус отходит назад, нос приподнят, жвалы раскрываются во всю ширь;
--   бросок  — корпус подаётся вперёд, морда с концами жвал доходит до цели;
--   хватка  — жвалы сомкнуты на цели, голова рвёт в стороны («вгрызся»);
--   отдача  — корпус отскакивает назад чуть дальше покоя и возвращается.
-- Между укусами жук стоит, потянувшись к цели, и медленно жуёт.
--
-- Пик удара совпадает с уроном: сервер на каждом укусе прибавляет атрибут Bite
-- (EnemyRender → EnemyGait.Bite), а период клиент меряет сам по промежуткам между ними —
-- следующий замах начинается заранее, чтобы бросок дошёл до цели ровно к укусу.
-- Куда бить — атрибут ChewAt (точка на поверхности цели, ставит сервер на смене цели).
--
-- Ноги при этом не шагают: шаг решается по маршрутному кадру, а не по кадру удара,
-- поэтому бросок не срывает ступни с места — бёдра уезжают вперёд вместе с корпусом,
-- и лапы сгибаются, упираясь в пол.
-- Длительности фаз, сек. При частом укусе (Холод снят, быстрый вид) все фазы
-- ужимаются пропорционально, чтобы цикл влезал в период (см. biteTimes).
local BITE_WINDUP = 0.26
local BITE_STRIKE = 0.07
local BITE_HOLD = 0.16
local BITE_RECOIL = 0.24
-- Насколько далеко корпус подаётся к цели, доля распорки ноги: потолок броска и минимум,
-- который виден даже у жука, уже упёршегося мордой в цель.
-- Потолок — запас задней лапы до полной вытяжки (у меш-лапы он мал, см. MODEL_STEP_REACH):
-- бросок дальше сорвал бы задние ступни с места.
local BITE_LUNGE_MAX = 0.35
local BITE_LUNGE_MIN = 0.1
-- На сколько концы жвал заходят в цель, доля распорки: «вгрызся», а не «коснулся».
local BITE_DEPTH = 0.08
-- Замах назад — доля броска.
local BITE_WIND_BACK = 0.3
-- Тянется к цели между укусами: не больше этой доли распорки. Это уже стойка, а не
-- удар: ноги под неё переступают (один раз, когда жук начал грызть).
local BITE_LEAN_MAX = 0.3
-- Отскок после хватки — доля броска за покой назад (× почерк flinch: броню не качнуть).
local BITE_KICK = 0.3
-- Наклон корпуса и головы на броске, рад на единицу броска: нос клюёт вниз к цели,
-- в замахе — приподнят. Безжвальный вид (хоботок, жало) бьёт головой сильнее.
local BITE_BODY_PITCH = 0.09
local BITE_HEAD_PITCH = 0.22
local BITE_STAB_PITCH = 1.8
-- Рывок головой в хватке: рад и частота, Гц (× почерк chew).
local BITE_TUG = 0.13
local BITE_TUG_FREQ = 9
-- Жвалы: раскрыты в замахе, сомкнуты (кончики чуть заходят друг за друга) в хватке,
-- приоткрыты и медленно жуют между укусами. Рад, раскрытие × почерк mandible.open.
local BITE_GAPE_OPEN = 0.55
local BITE_GAPE_SHUT = -0.06
local BITE_GAPE_REST = 0.1
local BITE_GNAW_FREQ = 4 -- рад/сек
-- Как быстро жук входит в грызню и выходит из неё, 1/сек: без этого первый кадр
-- грызни дёргал бы корпус в позу удара.
local BITE_BLEND = 8
-- Подвод головы к цели, рад: голова доворачивает к точке ChewAt, пока тело ещё
-- доворачивается, и чуть кивает вниз/вверх к её высоте.
local BITE_AIM_PITCH = 0.3
-- Крылатые в замахе приподнимают сложенные крылья для равновесия, доля размаха.
local BITE_WING_FLARE = 0.35

-- Поза смерти: насколько лапы разъезжаются наружу и насколько ниже бедра остаётся
-- ступня. Отличаться от любого дебафф-состояния поза обязана по требованию читаемости:
-- поле из трупов не должно читаться как толпа застывших живых — здесь это
-- держится на расползшихся лапах и выцветании (см. Corpses), а не на перевёртыше.
local DEATH_SPLAY = 1.25
local DEATH_DROP = 0.3

-- ======================= Почерк вида (EnemyGaitStyles) =======================
--
-- Поверх общей походки каждый вид получает своё дыхание и озирание — только у стоящего:
-- на ходу корпус ровный (см. «Тело ровное»). Оба слоя считаются над ОДНИМ кадром тела,
-- который и так пересчитывается каждый кадр: ни одной лишней детали и ни одного лишнего
-- прохода по деталям — важно на телефоне, где жуков до ~39.
--
-- Ниже какого хода (в единицах Стандарта, ст/сек) жук считается стоящим: дыхание и
-- озирание бывают только на остановке.
local IDLE_SPEED = 2
-- Как быстро жук переходит между «идёт» и «стоит», 1/сек: без сглаживания дыхание
-- включалось бы рывком на каждой заминке в толкучке.
local IDLE_EASE = 2
-- Потолок тангажа дыхания, рад: вдох чуть приподнимает нос, а не кивает жуком.
local BREATH_PITCH = 0.5

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
-- Два набора: обычный и для жука, ползущего под постройкой (подлаз, атрибут Crawling).
-- Ползущему опора — только пол: луч сверху иначе ловил бы крышу постройки над ним,
-- и лапы тянулись бы сквозь днище наверх.
local surfaceParams = {}
local surfaceParamsClock = {}

local function groundFilter(underTower)
	local slot = underTower and 2 or 1
	local now = os.clock()
	if surfaceParams[slot] and now - surfaceParamsClock[slot] < 1 then
		return surfaceParams[slot]
	end

	local include = {}
	-- Пол и стены — из активной локации (Workspace.Location), постройки — общая папка,
	-- обломки разрушенных турелей (TowerDebris) — по ним жуки ходят, как по полу.
	local location = Workspace:FindFirstChild("Location")
	for _, node in {
		location and location:FindFirstChild("ArenaFloor"),
		-- Видимый бетон с рельефом (холмы Литосферы, ямы Строителя): тело толкучка ставит
		-- по нему (ConcreteFloor.HeightAt), и лапы без него проходили сквозь холм к плоскому полу.
		Workspace:FindFirstChild("ConcreteFloor"),
		not underTower and Workspace:FindFirstChild("Towers") or nil,
		location and location:FindFirstChild("Walls"),
		Workspace:FindFirstChild("TowerDebris"),
		-- Постройки жуков твёрдые, жук перелезает их (Crowd поднимает тело) — лапы встают сверху.
		Workspace:FindFirstChild("EnemyStructures"),
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

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = include
	params.IgnoreWater = true
	surfaceParams[slot] = params
	surfaceParamsClock[slot] = now
	return params
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
	local femurBone = boneFrame(hip, knee, pole)
	local tibiaBone = boneFrame(knee, target, pole)
	local rest = leg.rest0
	placeSegment(leg.femur, femurBone, rest and rest.femur)
	placeSegment(leg.knee, femurBone, rest and rest.knee)
	-- Голень, лодыжка и лапка — одно жёсткое звено от колена до кончика: инверсия и так
	-- считает его одной длиной l2t. Раньше лапка ставилась своим кадром от лодыжки,
	-- пересчитанной на прямую колено–кончик, а в покое лодыжка лежит не на этой прямой
	-- (голень идёт круто вниз, лапка — по полу). Кадр лапки на ходу расходился с кадром
	-- покоя, и она отрывалась от голени и торчала отдельной палочкой (жалоба автора).
	placeSegment(leg.tibia, tibiaBone, rest and rest.tibia)
	placeSegment(leg.ankle, tibiaBone, rest and rest.ankle)
	placeSegment(leg.tarsus1, tibiaBone, rest and rest.tarsus1)
	placeSegment(leg.tarsus, tibiaBone, rest and rest.tarsus)
	if not rest then
		-- Лапа из примитивов: суставы — шарики, им кадр кости не нужен.
		leg.knee.CFrame = CFrame.new(knee)
		leg.ankle.CFrame = CFrame.new(knee + (target - knee) * (leg.l2 / leg.l2t))
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
	-- Кончик морды в кадре тела: самая передняя точка головы и жвал (у безжвальных —
	-- хоботка и прочего на голове). Им грызня меряет, сколько осталось до цели.
	local snout = -math.huge
	for _, list in { { rig.head }, rig.mandibles } do
		for _, g in list do
			for _, entry in g.parts do
				local half = entry.part.Size * 0.5
				-- Передний край детали по +Z тела: проекция её полуразмеров на ось Z.
				local reach = math.abs(entry.rest.RightVector.Z) * half.X
					+ math.abs(entry.rest.UpVector.Z) * half.Y
					+ math.abs(entry.rest.LookVector.Z) * half.Z
				snout = math.max(snout, entry.rest.Position.Z + reach)
			end
		end
	end
	rig.snout = snout > -math.huge and snout or nil
	return rig
end

-- Поворот вокруг точки в кадре тела.
local function around(point, rotation)
	return CFrame.new(point) * rotation * CFrame.new(-point)
end

local function poseHead(state, body, dt, turnRate, headLead)
	local rig = state.head
	local t = state.clock + rig.phase
	local scale = state.gaitScale or 1

	local style = state.style or EnemyGaitStyles.Default
	local idle = state.idle or 0

	-- Озирание: стоящий жук ведёт головой из стороны в сторону и чуть опускает её —
	-- именно это отличает «замер, ожидая» от «выключен». На ходу гасится: там голова
	-- занята доворотом раньше тела (см. NECK_*).
	local sniff = style.sniff
	local sniffYaw, sniffPitch = 0, 0
	if sniff.amp > 0 and idle > 0.01 then
		local wave = (state.clock + rig.phase) * sniff.rate * math.pi * 2
		sniffYaw = math.sin(wave) * sniff.amp * idle
		sniffPitch = math.sin(wave * 0.5) * sniff.amp * 0.4 * idle
	end

	-- Грызня (см. biteStep): голова наведена на цель, клюёт к ней на броске и рвёт
	-- в стороны в хватке. Наведение идёт через ту же пружину шеи, рывок — поверх неё:
	-- он быстрее, чем шея успевает за ним.
	local bite = state.bite
	local blend = bite and bite.blend or 0
	local aimYaw, aimPitch, tugYaw, strikePitch = 0, 0, 0, 0
	if blend > 0.001 then
		aimYaw, aimPitch = bite.aimYaw * blend, bite.aimPitch * blend
		tugYaw, strikePitch = bite.tug * blend, bite.headPitch * blend
	end

	local lead = math.clamp(headLead + sniffYaw + aimYaw, -NECK_MAX, NECK_MAX)
	state.neckYaw = (state.neckYaw or 0) + (lead - (state.neckYaw or 0)) * math.clamp(dt * NECK_FOLLOW, 0, 1)
	local neck = around(rig.neck, CFrame.Angles(sniffPitch + aimPitch + strikePitch,
		math.clamp(state.neckYaw + tugYaw, -NECK_MAX, NECK_MAX), 0))

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
	-- Усики вида: Моль ведёт ими широко и мягко, Спринтер прижимает, Мимик почти не шевелит.
	local antSway = ANTENNA_SWAY * style.antenna.sway
	local antFreq = ANTENNA_FREQ * style.antenna.freq
	for index, antenna in rig.antennae do
		if antenna.joint then
			local wave = t * antFreq + index * 1.7
			local rotation = CFrame.Angles(
				antSway * 0.6 * math.sin(wave * 1.3) + lagPitch,
				antSway * math.sin(wave) + lagYaw,
				0
			)
			local joint = neck * around(antenna.joint, rotation)
			for _, entry in antenna.parts do
				place(entry, joint)
			end
		end
	end

	local gape = MANDIBLE_OPEN * style.mandible.open * (0.5 + 0.5 * math.sin(t * MANDIBLE_FREQ * style.mandible.freq))
	if blend > 0.001 then
		-- Жвалы грызни ведёт цикл укуса, а не синус: раскрыты в замахе, сомкнуты на цели.
		gape += (bite.gape - gape) * blend
	end
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

-- Крылья: детали групп wing_L / wing_R в кадре тела и шарнир — точка у внутреннего края
-- (ближе всего к оси тела). Нет крыльев — nil.
local function captureWings(model, style)
	local pivot = model:GetPivot()
	local wings = {}
	for _, name in { "wing_L", "wing_R" } do
		local wing = model:FindFirstChild(name)
		if wing then
			local parts, inner, sumX, sumY, sumZ, count = {}, math.huge, 0, 0, 0, 0
			for _, part in wing:GetDescendants() do
				if part:IsA("BasePart") then
					local rest = pivot:ToObjectSpace(part.CFrame)
					table.insert(parts, { part = part, rest = rest })
					local half = part.Size * 0.5
					for _, sx in { -1, 1 } do
						for _, sz in { -1, 1 } do
							local corner = rest * Vector3.new(half.X * sx, 0, half.Z * sz)
							inner = math.min(inner, math.abs(corner.X))
						end
					end
					sumX += rest.X
					sumY += rest.Y
					sumZ += rest.Z
					count += 1
				end
			end
			if count > 0 then
				local side = sumX >= 0 and 1 or -1
				table.insert(wings, {
					parts = parts,
					hinge = Vector3.new(inner * side, sumY / count, sumZ / count),
					side = side,
				})
			end
		end
	end
	if #wings == 0 then
		return nil
	end
	-- Взмах шаблона, помноженный на почерк вида: Матка машет реже и шире, Лицехват — чаще.
	local wing = style and style.wing or nil
	return {
		wings = wings,
		freq = (model:GetAttribute("WingFlapFreq") or WING_FLAP_FREQ) * (wing and wing.freq or 1),
		angle = (model:GetAttribute("WingFlapAngle") or WING_FLAP_ANGLE) * (wing and wing.angle or 1),
		idle = style and style.wingIdle or nil,
		phase = math.random() * math.pi * 2,
		open = 0, -- текущий размах: 1 — машет в полную силу, 0 — сложены
		clock = 0,
	}
end

-- openOverride/freqMul — обмахивание стоящего жука на земле (см. rig.idle): размах не
-- тот, с которым он летит, и частота своя. lift — крылья просто приподняты на эту долю
-- размаха, без взмаха (замах грызни, см. BITE_WING_FLARE).
local function poseWings(rig, body, openOverride, freqMul, lift)
	local open = openOverride or rig.open
	local amount = open * rig.angle * math.sin(rig.clock * rig.freq * (freqMul or 1) * math.pi * 2 + rig.phase)
		+ (lift or 0) * rig.angle
	local parts, frames = {}, {}
	for _, wing in rig.wings do
		-- Поворот вокруг оси нос–хвост: крыло слева и справа поднимаются вместе.
		local joint = around(wing.hinge, CFrame.Angles(0, 0, amount * wing.side))
		for _, entry in wing.parts do
			table.insert(parts, entry.part)
			table.insert(frames, body * joint * entry.rest)
		end
	end
	workspace:BulkMoveTo(parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
end

-- Вздрагивание от попадания поверх ровного тела. Крена в повороте нет: живой жук
-- поворачивает на ногах, корпус не заваливается (см. «Тело ровное»).
local function react(state, body, dt)
	local up = body.UpVector
	local rotation = CFrame.identity

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

-- Насколько жук сейчас «стоит»: 1 — замер, 0 — идёт. Сглажено (см. IDLE_EASE), чтобы
-- заминка в толкучке не включала дыхание рывком.
local function idleAmount(state, dt)
	local speed = (state.velocity or Vector3.zero).Magnitude / (state.gaitScale or 1)
	local want = math.clamp(1 - speed / IDLE_SPEED, 0, 1)
	state.idle = (state.idle or want) + (want - (state.idle or want)) * math.clamp(dt * IDLE_EASE, 0, 1)
	return state.idle
end

-- Дыхание стоящего поверх ровного тела. Числа — EnemyGaitStyles. На ходу его нет:
-- корпус идущего жука не качается (см. «Тело ровное»).
local function flourish(state, body)
	local style = state.style or EnemyGaitStyles.Default
	local strut = state.strut or 1
	local rise, pitch = 0, 0
	local idle = state.idle or 0
	if style.breath.amp > 0 and idle > 0.01 then
		local wave = math.sin((state.clock + state.phase) * style.breath.rate * math.pi * 2)
		rise += wave * style.breath.amp * idle * strut
		pitch += wave * style.breath.amp * idle * BREATH_PITCH
	end

	if math.abs(rise) < 1e-4 and math.abs(pitch) < 1e-4 then
		return body
	end
	-- Смещение В КАДРЕ ТЕЛА, а не по миру: на стене «вверх» — это от поверхности.
	return body * CFrame.new(0, rise, 0) * CFrame.Angles(pitch, 0, 0)
end

-- Фазы укуса, ужатые под период: при частом укусе цикл обязан влезать в промежуток
-- между укусами, иначе следующий замах начинался бы посреди отдачи.
local function biteTimes(period)
	local k = math.min(1, period * 0.9 / (BITE_WINDUP + BITE_STRIKE + BITE_HOLD + BITE_RECOIL))
	return BITE_WINDUP * k, BITE_STRIKE * k, BITE_HOLD * k, BITE_RECOIL * k
end

local function smooth(x)
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

-- Удар грызни поверх тела (см. «Грызня: удар по цели»). Считает позу укуса в state.bite
-- (её же читает голова в poseHead) и возвращает два кадра: стойку (жук потянулся к цели —
-- по ней ставят ноги) и тело в ударе (стойка плюс бросок — его видно). Ничего не
-- двигает сам — ни одной лишней детали: корпус и так ставится одним PivotTo, голова
-- и жвалы и так ставятся каждый кадр.
--
-- chewAt — точка на поверхности цели (атрибут ChewAt), может не прийти — тогда жук бьёт
-- перед собой на среднюю длину броска.
local function biteStep(state, body, dt, chewing, chewAt, now)
	local bite = state.bite
	if not bite then
		if not chewing then
			return body, body
		end
		bite = { blend = 0, period = 1, gape = BITE_GAPE_REST, tug = 0, headPitch = 0,
			aimYaw = 0, aimPitch = 0, reach = 0, lean = 0, lunge = 0 }
		state.bite = bite
	end
	bite.blend += ((chewing and 1 or 0) - bite.blend) * math.clamp(dt * BITE_BLEND, 0, 1)
	if not chewing then
		bite.peak, bite.next = nil, nil
		if bite.blend < 0.001 then
			bite.blend = 0
			return body, body
		end
	end

	local style = state.style or EnemyGaitStyles.Default
	local strut = state.strut or 1
	local rig = state.head

	-- Сколько осталось от морды до цели вдоль носа и куда она от головы. Нет точки —
	-- бьёт перед собой: бросок средний, наведения нет.
	if chewing then
		local gap = nil
		local aimYaw, aimPitch = 0, 0
		if chewAt then
			local snout = rig and rig.snout or strut
			local toTarget = body:PointToObjectSpace(chewAt) - Vector3.new(0, 0, snout)
			gap = toTarget.Z
			if toTarget.Magnitude > 1e-3 then
				-- Голова смотрит по +Z тела: рысканье — к +X, тангаж — вниз при цели ниже морды.
				local flat = math.sqrt(toTarget.X * toTarget.X + toTarget.Z * toTarget.Z)
				aimYaw = math.clamp(math.atan2(toTarget.X, math.max(toTarget.Z, strut * 0.5)), -NECK_MAX, NECK_MAX)
				aimPitch = math.clamp(math.atan2(-toTarget.Y, math.max(flat, strut * 0.5)), -BITE_AIM_PITCH, BITE_AIM_PITCH)
			end
		end
		bite.aimYaw, bite.aimPitch = aimYaw, aimPitch
		local depth = BITE_DEPTH * strut
		if gap then
			-- Тянется к цели на всё, что не дотягивает бросок, — но не дальше BITE_LEAN_MAX.
			bite.lean = math.clamp(gap - BITE_LUNGE_MAX * strut, 0, BITE_LEAN_MAX * strut)
			bite.lunge = math.clamp(gap - bite.lean + depth, BITE_LUNGE_MIN * strut, BITE_LUNGE_MAX * strut)
		else
			bite.lean = 0
			bite.lunge = (BITE_LUNGE_MIN + BITE_LUNGE_MAX) * 0.5 * strut
		end
		bite.lunge *= style.lunge
	end

	-- Предсказание: пока укусы приходят, следующий пик (bite.next) — через период после
	-- прошлого укуса, и замах начинается заранее. Укусы перестали приходить (грызть нечем,
	-- Холод заморозил темп) — жук не бьёт впустую, а стоит, потянувшись к цели, и жуёт.
	local windup, strike, hold, recoil = biteTimes(bite.period)
	local biting = chewing and bite.confirmed ~= nil and now - bite.confirmed < bite.period * 2 + 0.5
	if biting and bite.next and now >= bite.next then
		bite.peak = bite.next
		bite.next += bite.period
		if now >= bite.next then
			bite.next = now + bite.period -- кадр провалился на целый период — не догонять пачкой
		end
	end

	-- reach — где корпус по оси удара: 1 — бросок дошёл до цели, отрицательный — замах.
	-- Между укусами жвалы приоткрыты и медленно жуют; от этой же позы идёт замах
	-- и в неё же возвращается отдача — без скачка на стыке фаз.
	local gnaw = 0.6 + 0.4 * math.sin((state.clock + state.phase) * BITE_GNAW_FREQ * style.mandible.freq)
	local reach, gape, tug = 0, BITE_GAPE_REST * style.mandible.open * gnaw, 0
	local since = bite.peak and now - bite.peak or math.huge
	local untilNext = nil
	if since < 0 then
		untilNext = -since -- первый укус: пик назначен на будущее (см. EnemyGait.Bite)
	elseif biting and bite.next then
		untilNext = bite.next - now
	end
	local openGape = BITE_GAPE_OPEN * style.mandible.open
	if since >= 0 and since < hold then
		-- Хватка: жвалы сомкнуты на цели, голова рвёт затухающими рывками.
		local x = since / hold
		reach = 1
		gape = BITE_GAPE_SHUT
		tug = math.sin(since * BITE_TUG_FREQ * math.pi * 2) * (1 - x) * BITE_TUG * style.chew
	elseif since >= hold and since < hold + recoil then
		-- Отдача: корпус отскакивает за покой назад и возвращается.
		local x = (since - hold) / recoil
		reach = (1 - x) * (1 - x) - BITE_KICK * style.flinch * math.sin(x * math.pi)
		gape = BITE_GAPE_SHUT + (gape - BITE_GAPE_SHUT) * smooth(x)
	elseif untilNext and untilNext < strike then
		-- Бросок: из замаха к цели, жвалы схлопываются к самому концу.
		local x = 1 - untilNext / strike
		reach = -BITE_WIND_BACK + (1 + BITE_WIND_BACK) * x * x
		gape = openGape + (BITE_GAPE_SHUT - openGape) * x * x
	elseif untilNext and untilNext < strike + windup then
		-- Замах: корпус назад, нос вверх, жвалы раскрываются.
		local x = smooth(1 - (untilNext - strike) / windup)
		reach = -BITE_WIND_BACK * x
		gape += (openGape - gape) * x
	end
	bite.reach = reach
	bite.gape = gape
	bite.tug = tug
	-- Безжвальный (хоботок, жало) бьёт головой: клюёт сильнее того, у кого есть жвалы.
	local stab = (rig and #rig.mandibles == 0) and BITE_STAB_PITCH or 1
	bite.headPitch = reach * BITE_HEAD_PITCH * stab

	local blend = bite.blend
	local pitch = reach * BITE_BODY_PITCH * blend
	local stance = body * CFrame.new(0, 0, bite.lean * blend)
	-- Корпус клюёт вокруг задних бёдер, а не вокруг середины: зад стоит, перёд подаётся.
	return stance, stance * CFrame.new(0, 0, reach * bite.lunge * blend)
		* around(Vector3.new(0, 0, -strut * 0.5), CFrame.Angles(pitch, 0, 0))
end

-- Где опора под номинальной стуйкой. Нет опоры (жук над краем, висит над проломом) —
-- нога остаётся там, где ей полагается быть по строению тела: пусть висит, но не тянется
-- к бесконечности.
--
-- Лапа встаёт на то, что под ней: на пол или на спину соседа, если тот закрывает пол под
-- точкой. Так же ставит лапы толкучка (Crowd: лапы и опора тела), и ступни стоят там,
-- где их держит сервер. Тела жуков лучом не ловятся (CanQuery = false), поэтому спина
-- соседа — купол над его следом-капсулой (атрибуты FootRadius/FootFront/FootBack,
-- BodyHalfHeight серверной модели): ступня ближе к хребту встаёт выше, у борта — ниже.
local backs, backsTime = {}, -math.huge
local function refreshBacks()
	local now = os.clock()
	if now - backsTime < BACKS_REFRESH then
		return
	end
	backsTime = now
	table.clear(backs)
	local enemies = Workspace:FindFirstChild("Enemies")
	if not enemies then
		return
	end
	for _, enemy in enemies:GetChildren() do
		local radius = enemy:GetAttribute("FootRadius")
		if radius and enemy:IsA("Model") then
			local front = enemy:GetAttribute("FootFront") or 0
			local back = enemy:GetAttribute("FootBack") or 0
			table.insert(backs, {
				model = enemy,
				pivot = enemy:GetPivot(),
				radius = radius,
				front = front,
				back = back,
				top = enemy:GetAttribute("ShellTop") or enemy:GetAttribute("BodyHalfHeight") or 0.6,
				reach = radius + math.max(math.abs(front), math.abs(back)),
			})
		end
	end
end

local function neighbourBack(point, selfModel)
	refreshBacks()
	local own = selfModel and selfModel.Parent
	-- Выше своей спины лапа не тянется. Толщина ступни — как у толкучки (Crowd.FOOT_RADIUS).
	local limit, margin = math.huge, 0
	if own then
		limit = selfModel:GetPivot().Position.Y
			+ (selfModel:GetAttribute("ShellTop") or selfModel:GetAttribute("BodyHalfHeight") or 0.6)
		margin = (selfModel:GetAttribute("RideHeight") or 1.5) * FOOT_RADIUS
	end
	local best
	for _, entry in backs do
		local position = entry.pivot.Position
		local dx, dz = point.X - position.X, point.Z - position.Z
		local reach = entry.reach + margin
		if entry.model ~= own and dx * dx + dz * dz < reach * reach then
			-- Голова модели по +Z, а пивот развёрнут на 180°: ход — минус LookVector.
			local look = -entry.pivot.LookVector
			local height = EnemyBody.BackHeight(dx, dz, look.X, look.Z, entry.radius,
				entry.front, entry.back, entry.top, margin)
			if height then
				local top = position.Y + height
				if top < limit and top < point.Y + PROBE_UP and (not best or top > best) then
					best = top
				end
			end
		end
	end
	return best
end

local function findSupport(nominal, up, gaitScale, underTower, selfModel)
	local scale = gaitScale or 1
	local result = Workspace:Raycast(nominal + up * (PROBE_UP * scale), -up * (PROBE_LENGTH * scale), groundFilter(underTower))
	local foot = result and result.Position or nominal
	-- Спина соседа над полом в этой точке закрывает пол: лапа встаёт на неё.
	if selfModel then
		local back = neighbourBack(nominal, selfModel)
		if back and back > foot.Y then
			foot = Vector3.new(nominal.X, back, nominal.Z)
		end
	end
	return foot
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
-- styleKey — имя шаблона вида (Enemies.model): по нему берётся почерк из EnemyGaitStyles.
-- Нет ключа (жук Аркады, примитив без шаблона) — почерк Стандарта, как было до таблицы.
function EnemyGait.Attach(model, legs, styleKey)
	-- Свой масштаб похода: во сколько раз этот экземпляр крупнее/мельче Стандарта, под
	-- которого подобраны MODEL_STRIDE и остальные абсолютные величины (см. GAIT_TUNED_SCALE).
	local gaitScale = (model:GetAttribute("Scale") or GAIT_TUNED_SCALE) / GAIT_TUNED_SCALE
	local state = {
		legs = {},
		clock = 0,
		turn = nil,
		gaitScale = gaitScale,
		style = EnemyGaitStyles.For(styleKey),
		-- Своя фаза дыхания и подскока: иначе вся волна одного вида дышит в унисон,
		-- и поле читается как механизм, а не как толпа.
		phase = math.random() * math.pi * 2,
	}

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

		-- Нога как распорка: её рабочая длина в позе покоя. Из неё — мерка экземпляра
		-- (state.strut ниже). Берётся покой, а не анатомический предел: на пределе лапа
		-- выпрямлена в палку, а держит тело она полусогнутой.
		local restFlat = Vector3.new(leg.foot.X - leg.hip.X, 0, leg.foot.Z - leg.hip.Z).Magnitude
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
			if femurBone and tibiaBone then
				entry.rest0 = {
					femur = femurBone:Inverse() * entry.femur.CFrame,
					knee = femurBone:Inverse() * entry.knee.CFrame,
					tibia = tibiaBone:Inverse() * entry.tibia.CFrame,
					ankle = tibiaBone:Inverse() * entry.ankle.CFrame,
					-- Лапка — от кадра голени (см. placeModelLeg): звено колено–кончик жёсткое.
					tarsus1 = tibiaBone:Inverse() * entry.tarsus1.CFrame,
					tarsus = tibiaBone:Inverse() * entry.tarsus.CFrame,
				}
			end
		end
		table.insert(state.legs, entry)
	end

	-- Средняя распорка — единственная физическая мерка этого экземпляра. От неё берутся
	-- вздрагивание и дыхание: у мелкого Мини мелкие, у гиганта крупные, и ни одной
	-- величины в studs подбирать под каждый вид не приходится.
	local strutSum = 0
	for _, entry in state.legs do
		strutSum += entry.strut or 0
	end
	state.strut = #state.legs > 0 and strutSum / #state.legs or 1

	state.head = captureHead(model)
	state.wings = captureWings(model, state.style)

	states[model] = state
	return state
end

-- Летун в воздухе: ноги не переставляет (их ведёт EnemyRender простым PivotTo), а крылья
-- машут. Зовётся каждый кадр после PivotTo. Без крыльев — ничего.
function EnemyGait.Flap(model, dt)
	local state = states[model]
	local wings = state and state.wings
	if not wings then
		return
	end
	wings.open = math.min(1, wings.open + dt * WING_FOLD)
	wings.clock += dt
	poseWings(wings, model:GetPivot())
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
	local style = state.style or EnemyGaitStyles.Default
	-- Броню качнуть труднее, Личинку — легче: сила вздрагивания у вида своя.
	local power = math.clamp(FLINCH_FLOOR + (strength or 0) * FLINCH_GAIN, 0, 1) * style.flinch
	-- Пик критически демпфированной пружины с начальной скоростью v — v / (ω·e).
	local speed = (state.strut or 1) * FLINCH_SHIFT * power * FLINCH_OMEGA * math.exp(1)
	state.flinchVelocity = (state.flinchVelocity or Vector3.zero) + away.Unit * speed
end

-- Укус грызни случился на сервере (атрибут Bite прибавился, см. EnemyRender). Здесь —
-- только время: пик удара подтягивается к укусу, а период укусов меряется по промежуткам
-- между ними (темп у вида свой, Холод его режет — отдельный атрибут для этого не нужен).
function EnemyGait.Bite(model)
	local state = states[model]
	if not state then
		return
	end
	local now = os.clock()
	local bite = state.bite
	if not bite then
		bite = { blend = 0, period = 1, gape = BITE_GAPE_REST, tug = 0, headPitch = 0,
			aimYaw = 0, aimPitch = 0, reach = 0, lean = 0, lunge = 0 }
		state.bite = bite
	end
	if bite.confirmed then
		local interval = now - bite.confirmed
		if interval > 0.15 and interval < 4 then
			bite.period += (interval - bite.period) * 0.5
		end
	end
	bite.confirmed = now

	local windup, strike = biteTimes(bite.period)
	local next = bite.next
	if next and math.abs(now - next) < strike + 0.15 then
		-- Укус рядом с предсказанным пиком: бросок уже идёт. Пришёл раньше — пик подтягивается
		-- к нему (бросок чуть ускоряется), позже — пик уже был, прогноз сдвигается от укуса.
		if now < next then
			bite.next = now
		else
			if not bite.peak or bite.peak < next then
				bite.peak = next -- кадр походки ещё не успел сам перевести прогноз в пик
			end
			bite.next = now + bite.period
		end
		return
	end
	if bite.peak and now < bite.peak then
		return -- первый бросок ещё летит
	end
	bite.next = now + bite.period
	if not next then
		-- Первый укус: пика ещё не было. Полный замах и бросок прямо сейчас — на долю
		-- секунды позже урона, зато без рывка корпуса в позу замаха; дальше укусы уже
		-- предсказаны и бьют ровно в такт.
		bite.peak = now + strike + windup
	end
	-- Прогноз разошёлся с укусом (сеть, Холод сменил темп): этот удар пропускается,
	-- следующий пойдёт уже от него.
end

-- Один кадр походки. mode: "walk" — идёт или стоит, "chew" — грызёт преграду,
-- "climb" — лезет через неё.
--
-- Стан отдельным режимом НЕ выделяется нарочно (правило v2: движение не имитирует
-- дебаффы, состояние рисует индикация): стоящий жук и так не переступает — тело не
-- уезжает от ступней, и порог шага не берётся сам собой.
--
-- pathCF — МАРШРУТНЫЙ кадр от спавнера: где жук находится для сетки, толкучки и прицела.
-- Передан — походка сама ставит модель (PivotTo): тело ровно в нём, плюс доворот,
-- вздрагивание и дыхание. Не передан — тело ведёт вызывающий.
-- На какой угол тело успевает довернуть за кадр при рассогласовании angle (рад).
-- Этим же доворотом пользуется толкучка (Crowd.Resolve): капсула, сквозь которую жуки
-- не проходят, обязана смотреть туда же, куда видимое тело, — иначе на повороте тело
-- отстаёт от капсулы и въезжает брюшком в соседа.
function EnemyGait.TurnStep(angle, dt)
	return math.clamp(math.abs(angle) * TURN_EASE, TURN_RATE_MIN, TURN_RATE_MAX) * dt
end

-- wantLook — куда смотрел бы жук без ограничения разворота (LookVector маршрутного кадра).
-- Нужен, когда разворот уже ограничила толкучка: голова по-прежнему идёт раньше тела.
-- underTower — жук ползёт под постройкой (атрибут Crawling серверной модели): опора только на полу.
-- chewAt — точка на поверхности того, что жук грызёт (атрибут ChewAt), только в режиме "chew".
function EnemyGait.Step(model, dt, mode, pathCF, wantLook, underTower, chewAt)
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
	-- «Стоит или идёт» нужно и голове (озирание), и телу (дыхание) — считается один раз.
	idleAmount(state, dt)
	local body = path
	-- Кадр, по которому решают ноги: без удара грызни. Бросок подаёт корпус к цели,
	-- но ступни остаются на месте — лапы сгибаются, а не переступают вслед за броском.
	local stance = path
	if pathCF then
		stance, body = biteStep(state, flourish(state, react(state, body, dt)), dt, mode == "chew", chewAt, now)
		model:PivotTo(body)
	end
	if state.head then
		poseHead(state, body, dt, turnRate, headLead)
	end
	-- На земле крылья складываются (Пеликан сел, наевшись). А у видов с wingIdle
	-- сложенные крылья ещё и обмахивают — но только пока жук стоит: на марше это
	-- и не видно, и стоило бы прохода по деталям крыльев у каждого жука в волне.
	local wings = state.wings
	if wings then
		local idleFlap = (wings.idle and (state.idle or 0) > 0.5)
			and wings.idle.amp * ((state.idle or 0) - 0.5) * 2 or 0
		-- Замах грызни: сложенные крылья приподнимаются для равновесия и опадают на броске.
		local bite = state.bite
		local flare = bite and bite.blend > 0.001 and math.max(0, -bite.reach) / BITE_WIND_BACK
			* BITE_WING_FLARE * bite.blend or 0
		if wings.open > 0 then
			wings.open = math.max(0, wings.open - dt * WING_FOLD)
			wings.clock += dt
			poseWings(wings, body, math.max(wings.open, idleFlap))
		elseif idleFlap > 0.001 then
			wings.clock += dt
			poseWings(wings, body, idleFlap, wings.idle.freq / math.max(wings.freq, 0.1), flare)
		elseif bite and bite.blend > 0.001 then
			-- Грызёт (крылья сложены, обмахивания нет): позу крыльев держит корпус удара,
			-- даже когда приподнимать нечего — иначе они остались бы в кадре прошлого броска.
			poseWings(wings, body, 0, 0, flare)
		end
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
		-- Поверх масштаба — почерк вида: Гигант вышагивает (шаг длиннее, перенос дольше),
		-- Мини семенит, Кукольник перебрасывает лапу рывком.
		local style = state.style or EnemyGaitStyles.Default
		local modelScale = leg.isModel and state.gaitScale or 1
		local stride = (leg.isModel and (MODEL_STRIDE * modelScale) or STRIDE) * style.stride
		local stepTime = (leg.isModel and MODEL_STEP_TIME or STEP_TIME) * style.stepTime
		local stepLift = (leg.isModel and (MODEL_STEP_LIFT * modelScale) or STEP_LIFT) * style.stepLift

		if mode == "climb" then
			-- На вертикали жук распластывается: стойка шире и немного ближе к поверхности.
			rest = Vector3.new(rest.X * CLIMB_SPREAD, rest.Y + 0.35 * modelScale, rest.Z * CLIMB_SPREAD)
		end

		-- Бедро — на теле как оно есть (с броском грызни), а стойка и порог шага —
		-- по кадру без броска (stance): в грызне лапы стоят на земле и гнутся, а не
		-- переступают за каждым ударом и не машут в воздухе.
		local hipWorld = body * leg.hip
		local nominal = stance * rest
		local stanceHip = stance * leg.hip

		if now < leg.stepUntil then
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
				or (leg.stepReach ~= nil and (stanceHip - planted).Magnitude > leg.stepReach)

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
					and plantAhead(stanceHip, nominal, velocity, leg.length * MODEL_STEP_PLANT, stride * 0.5)
					or nominal
				leg.stepTo = findSupport(aim, up, modelScale, underTower, model)
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
-- splay, drop — насколько далеко и низко ступня (по умолчанию поза трупа); меньше — лапы поджаты.
function EnemyGait.DeathPose(corpse, original, splay, drop)
	local state = states[original]
	-- Поза смерти вида: броня оседает поджато, Моль раскидывает лапы шире. Множитель
	-- ложится и на поджатую позу останков (curlSplay/curlDrop из PhysicsFX).
	local style = (state and state.style) or EnemyGaitStyles.Default
	splay = (splay or DEATH_SPLAY) * style.death.splay
	drop = (drop or DEATH_DROP) * style.death.drop
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
				leg.rest.X * splay,
				leg.hip.Y - drop * modelScale,
				leg.rest.Z * splay
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
