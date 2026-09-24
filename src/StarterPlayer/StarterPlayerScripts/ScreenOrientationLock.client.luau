-- Игра рассчитана только на альбомную ориентацию (см. MobileUI, Hud, TowerInteraction),
-- поэтому вертикальный режим запрещён. LandscapeSensor разрешает поворот между двумя
-- альбомными положениями (телефон можно держать любой стороной), но не даёт уйти в portrait.
--
-- Основная настройка — свойство StarterGui.ScreenOrientation, оно сохранено в самом плейсе
-- и действует с первого кадра, до того как вообще запустятся клиентские скрипты. Этот скрипт —
-- сторож поверх неё: повторяет значение и возвращает его, если кто-то сменит ориентацию во время
-- игры. Без свойства плейса одного скрипта мало: StarterGui стоял на Sensor, и между входом
-- в игру и строчкой ниже телефон успевал встать вертикально.
local ALLOWED = Enum.ScreenOrientation.LandscapeSensor

local player = game:GetService("Players").LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

playerGui.ScreenOrientation = ALLOWED

playerGui:GetPropertyChangedSignal("ScreenOrientation"):Connect(function()
	if playerGui.ScreenOrientation ~= ALLOWED then
		playerGui.ScreenOrientation = ALLOWED
	end
end)
