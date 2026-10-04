-- Список уровней игры: номер, название, состав волн, карта.
-- Ключ таблицы — сам номер уровня, как и profile.levels в PlayerData: новый уровень —
-- новая запись здесь по своему номеру, WaveRunner/PlayerData/LobbyUI её не требуют трогать.
--
-- tutorial = true — на уровне идёт обучение и закрыто всё, кроме открытого в TutorialConfig
-- (задача #298). Прежние 15 волн по кастам переехали на уровень 2.
local Waves = require(script.Parent:WaitForChild("Waves"))
local TutorialWaves = require(script.Parent:WaitForChild("TutorialWaves"))

local Levels = {
	[1] = { number = 1, name = "Обучение", waves = TutorialWaves, map = "Arena", tutorial = true },
	[2] = { number = 2, name = "Бункер", waves = Waves, map = "Arena" },
}

return Levels
