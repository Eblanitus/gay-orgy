-- Список уровней игры: номер, название, состав волн, карта.
-- Ключ таблицы — сам номер уровня, как и profile.levels в PlayerData: новый уровень —
-- новая запись здесь по своему номеру, WaveRunner/PlayerData/LobbyUI её не требуют трогать.
--
-- tutorial = true — на уровне идёт обучение и закрыто всё, кроме открытого в TutorialConfig
-- (задача #298). Прежние 15 волн по кастам переехали на уровень 2.
--
-- rules — что закрыто на обычном уровне (проверяет Tutorial, промокод test снимает):
--   towers   — какие постройки можно ставить (нет поля — все);
--   maxTier  — элементы выше этого тира (Elements.tier) не купить и не скрафтить;
--   roulette, upgrader = false — закрыть Рулетку и Апгрейдер (они выдают элементы любого тира).
--
-- betweenWaves — секунд между волнами: кнопка «Начать» только перед первой волной, дальше
--   следующая стартует сама по таймеру (WaveRunner). Нет поля — каждую волну зовёт кнопка.
-- moths — Моль прилетает сама по одной, вне состава волн: с волны fromWave (с момента,
--   когда та ждёт старта), паузы между Молями — случайные от gap[1] до gap[2] секунд,
--   life — через сколько секунд недобитая улетает (исчезает), чтобы не копились.
-- buildDuringWave = true — строить можно и пока волна идёт (по умолчанию только между волнами).
local Waves = require(script.Parent:WaitForChild("Waves"))
local TutorialWaves = require(script.Parent:WaitForChild("TutorialWaves"))

local Levels = {
	[1] = { number = 1, name = "Обучение", waves = TutorialWaves, map = "Arena", tutorial = true },
	[2] = { number = 2, name = "Бункер", waves = Waves, map = "Arena",
		rules = { towers = { Ballista = true }, maxTier = 1, roulette = false, upgrader = false },
		betweenWaves = 25,
		buildDuringWave = true,
		moths = { fromWave = 3, gap = { 15, 40 }, life = 90 } },
}

return Levels
