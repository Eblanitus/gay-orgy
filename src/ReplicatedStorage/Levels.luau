-- Список уровней игры (alchemy_td_lobby.md, шаг 4): номер, название, состав волн, карта.
-- Ключ таблицы — сам номер уровня, как и profile.levels в PlayerData: новый уровень —
-- новая запись здесь по своему номеру, WaveRunner/PlayerData/LobbyUI её не требуют трогать.
-- Сейчас уровень один — обучающий; второй уровень и его содержимое не входят в это ТЗ.
local Waves = require(script.Parent:WaitForChild("Waves"))

local Levels = {
	[1] = { number = 1, name = "Обучение", waves = Waves, map = "Arena" },
}

return Levels
