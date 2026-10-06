-- Звуки игры (не интерфейса — тот в SoundService.UISounds, см. UISound): что звучит
-- и как. Играет их клиент, GameAudio, по событиям, которые сервер и так шлёт для
-- эффектов (ShotFired, Explosion, EnemyFX, WaveReady, WaveChanged, RunEnded). Сервер про звук
-- ничего не знает.
--
-- Сами файлы — папка «Звуки/» в репозитории, id ассетов — ReplicatedStorage.SoundIds
-- (пишет tools/upload_sounds.py). Звук без id молча не играет.
--
-- Поля звука:
--   group   — группа громкости в SoundService.Master: Combat («Бой»), Ambient («Атмосфера»),
--             Music («Музыка»). Ползунки — UISettings.
--   volume  — громкость самого звука, 1 — как записан.
--   pitch   — {min, max}: высота выбирается случайно на каждый запуск, чтобы двадцать
--             одинаковых выстрелов подряд не звучали пулемётом одной ноты.
--   near, far — RollOffMinDistance / RollOffMaxDistance в студах: ближе near звук на
--             полной громкости, к far стихает. Нет полей — звук не в мире, а «в ушах».
--   gap     — один и тот же звук не чаще, чем раз в gap секунд.
--   voices  — сколько копий звука может играть одновременно; лишние пропускаются.
--   looped  — петля (эмбиент, музыка, гул турели, крылья).
local SoundBank = {}

-- Звуки игры, кроме музыки (бой, жуки, забег, фон). Автор послушал черновой набор и
-- попросил пока убрать: false — молчат все, кроме группы Music. Вернуть — true.
-- Звуки интерфейса (SoundService.UISounds) это не трогает.
SoundBank.SFX_ENABLED = false

SoundBank.Sounds = {
	-- Выстрелы
	ShotFlask = { group = "Combat", volume = 0.5, pitch = { 0.92, 1.08 }, near = 10, far = 140, gap = 0.04, voices = 6 },
	ShotInjector = { group = "Combat", volume = 0.45, pitch = { 0.94, 1.06 }, near = 10, far = 140, gap = 0.04, voices = 6 },
	DroneLaunch = { group = "Combat", volume = 0.55, pitch = { 0.95, 1.05 }, near = 10, far = 160, gap = 0.1, voices = 3 },

	-- Взрывы
	Boom = { group = "Combat", volume = 0.8, pitch = { 0.85, 1.05 }, near = 16, far = 260, gap = 0.08, voices = 4 },
	DroneBoom = { group = "Combat", volume = 0.7, pitch = { 0.9, 1.1 }, near = 14, far = 220, gap = 0.08, voices = 4 },
	Quake = { group = "Combat", volume = 0.85, pitch = { 0.85, 1.0 }, near = 18, far = 300, gap = 0.15, voices = 2 },
	Splash = { group = "Combat", volume = 0.6, pitch = { 0.9, 1.1 }, near = 14, far = 220, gap = 0.08, voices = 3 },

	-- Жуки
	DeathSmall = { group = "Combat", volume = 0.45, pitch = { 0.9, 1.2 }, near = 8, far = 110, gap = 0.03, voices = 6 },
	DeathMedium = { group = "Combat", volume = 0.55, pitch = { 0.9, 1.1 }, near = 9, far = 130, gap = 0.04, voices = 5 },
	DeathBig = { group = "Combat", volume = 0.7, pitch = { 0.85, 1.0 }, near = 12, far = 180, gap = 0.08, voices = 3 },
	Sizzle = { group = "Combat", volume = 0.35, pitch = { 0.9, 1.1 }, near = 8, far = 100, gap = 0.06, voices = 3 },
	Splat = { group = "Combat", volume = 0.35, pitch = { 0.85, 1.15 }, near = 8, far = 100, gap = 0.05, voices = 4 },
	Shatter = { group = "Combat", volume = 0.6, pitch = { 0.9, 1.1 }, near = 10, far = 150, gap = 0.08, voices = 3 },

	-- Петли на моделях
	WingBuzz = { group = "Combat", volume = 0.18, pitch = { 0.85, 1.25 }, near = 6, far = 70, looped = true },
	HumArea = { group = "Combat", volume = 0.22, pitch = { 1, 1 }, near = 8, far = 80, looped = true },

	-- Забег
	WaveStart = { group = "Combat", volume = 0.6, pitch = { 1, 1 }, gap = 1, voices = 1 },
	-- Стинги исхода — в «Бою», а не в «Музыке»: звучат и при выключенной музыке.
	RunWin = { group = "Combat", volume = 0.7, pitch = { 1, 1 }, gap = 1, voices = 1 },
	RunLose = { group = "Combat", volume = 0.7, pitch = { 1, 1 }, gap = 1, voices = 1 },

	-- Фон
	AmbientBunker = { group = "Ambient", volume = 0.5, pitch = { 1, 1 }, looped = true },
	MusicBunker = { group = "Music", volume = 0.35, pitch = { 1, 1 }, looped = true },

	-- Музыка (вся в группе Music: молчит, пока не включено «Экспериментальное: музыка»)
	MusicMenu = { group = "Music", volume = 0.4, pitch = { 1, 1 }, looped = true },
	MusicBattleCalm = { group = "Music", volume = 0.4, pitch = { 1, 1 }, looped = true },
	-- Интро и бой — одна запись, разрезанная на две: громкость у них одна, иначе на стыке
	-- прыгнет. Calm в самом файле тише (около -22 LUFS против -14), поэтому ей не убавлено.
	MusicBattleIntro = { group = "Music", volume = 0.45, pitch = { 1, 1 } },
	MusicBattle = { group = "Music", volume = 0.45, pitch = { 1, 1 }, looped = true },
}

-- Выстрел — по типу турели (атрибут Type, Towers). Нет строки — турель стреляет молча.
SoundBank.Shot = {
	Ballista = "ShotFlask",
	Injector = "ShotInjector",
	Mortar = "DroneLaunch",
}

-- Постоянный гул площадных турелей (fireMode = "area"): звук и его высота по типу.
SoundBank.Hum = {
	Vaporizer = { sound = "HumArea", pitch = 1.35 },
	Drill = { sound = "HumArea", pitch = 0.8 },
	Centrifuge = { sound = "HumArea", pitch = 1.1 },
}

-- Взрыв — по виду (поле blast у Explosion). drone — подрыв дрона, default — всё прочее
-- (огонь и взрыв без своего вида).
SoundBank.Blast = {
	drone = "DroneBoom",
	cloud = "Splash",
	rain = "Splash",
	snow = "Splash",
	wave = "Splash",
	quake = "Quake",
	rift = "Quake",
	default = "Boom",
}

-- Смерть жука — по размеру (hit.scale из Corpses.Leave, у Стандарта 3). Берётся первая
-- строка, чей upTo не меньше размера жука.
SoundBank.Death = {
	{ upTo = 2.2, sound = "DeathSmall" },
	{ upTo = 3.6, sound = "DeathMedium" },
	{ upTo = math.huge, sound = "DeathBig" },
}

-- Вид останков, который добавляет к смерти свой звук поверх (Effects.RemainsOf).
SoundBank.Remains = {
	char = "Sizzle",
}

-- Громкость взрыва растёт с радиусом: radius / BLAST_REF_RADIUS, не меньше и не больше
-- пределов.
SoundBank.BLAST_REF_RADIUS = 8
SoundBank.BLAST_GAIN = { 0.7, 1.4 }

-- Фон и музыка
SoundBank.Ambient = "AmbientBunker"
-- Трек по состоянию игры: menu — лобби и главное меню (до забега и после RunEnded),
-- calm — забег, волна ждёт кнопки (WaveReady, и перед первой волной тоже), intro —
-- волна началась (WaveChanged): интро играет один раз с начала, а когда кончится,
-- с начала же идёт battle и крутится до конца волны.
-- MusicBunker загружен, но пока не играет нигде.
SoundBank.Music = {
	menu = "MusicMenu",
	calm = "MusicBattleCalm",
	intro = "MusicBattleIntro",
	battle = "MusicBattle",
}
-- За сколько секунд один трек перетекает в другой.
SoundBank.MUSIC_FADE = 2
-- Волна началась: за сколько секунд гаснет calm (интро вступает сразу, с начала).
SoundBank.MUSIC_INTRO_FADE = 1

return SoundBank
