-- Уровень 1 — обучающий: волны 1-3 знакомят с видами тира 0 по одному-два за раз (#41), считая
-- сложность растущей толпой HP (#42). Задача #43: каждая волна теперь может нести несколько
-- групп разных видов одновременно — WaveRunner.runWaves спавнит все group этой записи через
-- отдельные task.spawn, ждёт полного опустения enemiesFolder по всем группам сразу, и только
-- потом переходит к следующей волне. hp у каждой группы переопределяет базовое HP типа из
-- Enemies — здесь везде равно базовому значению самого типа, явно указано для читаемости.
--
-- Числа — существовавший состав (#42) плюс то, что попросили добавить сверху (#43), число Лицехватов
-- в волнах 4-5 снижено до 10 каждой (#45); hp у Armored всюду 42 (#48, было 30) — следом
-- за базовым значением типа в Enemies, как и везде здесь:
--   волна 1: Normal x5 (было) + Mini x5
--   волна 2: Normal x9 (было) + Mini x5 + Armored x2
--   волна 3: Armored x7 (было) + Facehugger x1 + Mini x2 + Normal x2
--   волна 4: Mini x30 (было) + Facehugger x10 (было 15) + Normal x5
--   волна 5: Facehugger x10 (было 14) + Armored x15 + Mini x30 + Normal x20
--
-- С задачи #45 турели бронируются под каждого летящего Лицехвата до вылета (Claimed) —
-- два Жука больше не садятся на одну и ту же турель (баг, найденный живым прогоном после #43 —
-- см. CHANGELOG #45), так что с двумя+ турелями на арене залипание больше не грозит. С ровно
-- одной турелью на арене остальные Лицехваты просто ждут (findFreeTurret возвращает nil), а не летят
-- к занятой — каждый по-очереди через освобождающиеся погибших Жуков.
-- ПОРЯДОК ВОЛН — ЭТО ПОРЯДОК КАСТ (design: alchemy_td_enemies.md).
--
-- Каста — не уровень силы, а роль в колонии, но документ выкладывает их как лестницу
-- обучения: разведчики учат стрелять, работяги — держать периметр, солдаты — останавливать
-- прорыв к лаборатории, особые — ломают по одной привычке каждый. Поэтому виды
-- вводятся каста за кастой, по одному-два новых за волну, а не все сразу.
--
-- hp везде равно базовому значению типа из Enemies — выписано явно для читаемости,
-- как и было до этой задачи.
--
-- Личинки здесь нет нарочно: её кладёт Матка, а не волна.
local Waves = {
	-- ===== Каста 0 — Разведчики =====

	-- «Турель работает. Стрелять — жук уничтожен. Но одного выстрела мало.»
	{ number = 1, groups = {
		{ enemyType = "Normal", count = 5, hp = 30 },
		{ enemyType = "Mini",   count = 3, hp = 14 },
	} },
	-- Хмурый брон: «периметр тоже нужен. Броня существует.»
	{ number = 2, groups = {
		{ enemyType = "Normal",  count = 7, hp = 30 },
		{ enemyType = "Mini",    count = 5, hp = 14 },
		{ enemyType = "Armored", count = 2, hp = 42 },
	} },
	-- Моль: «не только пол. Юниты умеют летать.»
	{ number = 3, groups = {
		{ enemyType = "Armored", count = 5, hp = 42 },
		{ enemyType = "Moth",    count = 3, hp = 10 },
		{ enemyType = "Mini",    count = 4, hp = 14 },
		{ enemyType = "Normal",  count = 4, hp = 30 },
	} },
	-- Лицехват (каста 3, но был в игре до каст и остался на своём месте).
	{ number = 4, groups = {
		{ enemyType = "Mini",       count = 25, hp = 14 },
		{ enemyType = "Facehugger", count = 4,  hp = 12 },
		{ enemyType = "Normal",     count = 5,  hp = 30 },
	} },
	{ number = 5, groups = {
		{ enemyType = "Facehugger", count = 7,  hp = 12 },
		{ enemyType = "Armored",    count = 10, hp = 42 },
		{ enemyType = "Mini",       count = 30, hp = 14 },
		{ enemyType = "Normal",     count = 10, hp = 30 },
		{ enemyType = "Moth",       count = 4,  hp = 10 },
	} },

	-- ===== Каста 1 — Работяги =====

	-- «Сам по себе — не опаснее разведчика. Группой — проблема.» Сразу восемь:
	-- меньше пяти они просто не соберутся в группу, и механика не покажется вовсе.
	{ number = 6, groups = {
		{ enemyType = "Worker", count = 8, hp = 45 },
		{ enemyType = "Normal", count = 6, hp = 30 },
	} },
	-- Кислотник и Окопщик: оба по-отдельности бесполезны, вместе с работягами — нет.
	{ number = 7, groups = {
		{ enemyType = "Worker",      count = 10, hp = 45 },
		{ enemyType = "AcidSpitter", count = 2,  hp = 35 },
		{ enemyType = "Digger",      count = 2,  hp = 50 },
	} },
	-- Строитель и Медик: связка «окопщик копает — работяга несёт — строитель строит»
	-- замыкается только здесь, когда на поле есть все трое сразу.
	{ number = 8, groups = {
		{ enemyType = "Worker",  count = 8, hp = 45 },
		{ enemyType = "Builder", count = 2, hp = 70 },
		{ enemyType = "Digger",  count = 3, hp = 50 },
		{ enemyType = "Medic",   count = 2, hp = 40 },
	} },
	-- Пеликан и Матка. К этой волне на поле уже лежат трупы — есть что есть.
	{ number = 9, groups = {
		{ enemyType = "Worker",  count = 6, hp = 45 },
		{ enemyType = "Pelican", count = 3, hp = 55 },
		{ enemyType = "Queen",   count = 1, hp = 90 },
		{ enemyType = "Builder", count = 2, hp = 70 },
	} },

	-- ===== Каста 2 — Солдаты =====

	-- «Десять солдат идут десятью разными путями.» Спринтер и Подрывник —
	-- два самых простых урока: скорость и взрыв.
	{ number = 10, groups = {
		{ enemyType = "Sprinter", count = 8, hp = 18 },
		{ enemyType = "Bomber",   count = 3, hp = 40 },
		{ enemyType = "Normal",   count = 6, hp = 30 },
	} },
	-- Щитоносец, Координатор, Таран: все трое про геометрию обороны —
	-- перекрёстный огонь, единый фокус и смещённые стены.
	{ number = 11, groups = {
		{ enemyType = "ShieldBearer", count = 4, hp = 60 },
		{ enemyType = "Coordinator",  count = 1, hp = 45 },
		{ enemyType = "Worker",       count = 8, hp = 45 },
		{ enemyType = "Ram",          count = 2, hp = 80 },
	} },
	-- Гигант и Заживалка: оба про то, что постоянного слабого огня может не хватить.
	{ number = 12, groups = {
		{ enemyType = "Giant",    count = 2,  hp = 320 },
		{ enemyType = "Knitter",  count = 4,  hp = 60 },
		{ enemyType = "Sprinter", count = 10, hp = 18 },
		{ enemyType = "Bomber",   count = 4,  hp = 40 },
	} },

	-- ===== Каста 3 — Особые =====

	-- Мимик, Тень и Разносчик: три разных способа сломать привычку «турель видит цель
	-- и бьёт её».
	{ number = 13, groups = {
		{ enemyType = "Mimic",    count = 3, hp = 50 },
		{ enemyType = "Shadow",   count = 6, hp = 25 },
		{ enemyType = "Absorber", count = 3, hp = 50 },
	} },
	-- Роевик с летающим координатором — только вместе: без координатора он
	-- вообще не копает, и урока не выйдет.
	{ number = 14, groups = {
		{ enemyType = "Burrower", count = 4, hp = 45 },
		{ enemyType = "SwarmEye", count = 1, hp = 35 },
		{ enemyType = "Evolver",  count = 2, hp = 70 },
		{ enemyType = "Carrier",  count = 2, hp = 90 },
	} },
	-- Финал: Кукольник и Архитектор работают по тому, что на поле уже есть —
	-- раненые и пол, — поэтому идут вместе с большой толпой.
	{ number = 15, groups = {
		{ enemyType = "Puppeteer",     count = 2,  hp = 55 },
		{ enemyType = "HiveArchitect", count = 2,  hp = 80 },
		{ enemyType = "Facehugger",    count = 6,  hp = 12 },
		{ enemyType = "Giant",         count = 2,  hp = 320 },
		{ enemyType = "Worker",        count = 10, hp = 45 },
		{ enemyType = "Sprinter",      count = 8,  hp = 18 },
	} },
}

-- БОЛЬШЕ НЕ ИСПОЛЬЗУЕТСЯ: с задачи #22 каждую волну зовёт игрок кнопкой, а не таймер.
-- Поле оставлено: если вернёмся к автоматическим волнам или добавим таймер-подсказку, число уже есть.
Waves.pauseBetweenWaves = 15 -- сек

return Waves
