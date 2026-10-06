-- Звуки главного меню и его страниц (журнал, настройки, промокод). Своих звуков у меню
-- нет: каждое событие звучит готовым звуком интерфейса из SoundService.UISounds — теми же
-- щелчками, что у производителя и лаборатории. Какое событие каким звуком —
-- ReplicatedStorage.SoundBank.Menu, выключатель — SoundBank.MENU_SFX_ENABLED.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SoundBank = require(ReplicatedStorage:WaitForChild("SoundBank"))
local UISound = require(script.Parent:WaitForChild("UISound"))

local MenuSound = {}

-- Проиграть звук события меню event (ключ SoundBank.Menu).
function MenuSound.Play(event)
	if not SoundBank.MENU_SFX_ENABLED then
		return
	end
	local def = SoundBank.Menu[event]
	if def then
		UISound.Play(def.sound, def.cut)
	end
end

return MenuSound
