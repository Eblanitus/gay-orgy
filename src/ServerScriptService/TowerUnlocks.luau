-- Состояние блокировки турелей вне Колбы (задача #56): они полностью в игре — запись
-- в Towers, модель и режим стрельбы целы, — но строить их нельзя, пока не введён
-- промокод (см. ServerScriptService.PromoCode). Разблокировка одна на весь сервер сразу,
-- а не персонально по игроку: материя и сами постройки тоже общие на всех.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Towers = require(ReplicatedStorage:WaitForChild("Towers"))

local TowerUnlocks = {}

local unlocked = false

-- Реплицируется клиенту атрибутом на ReplicatedStorage, а не отдельным RemoteEvent:
-- TowerInteraction читает его при заходе и подписывается на изменение — значение уже
-- доступно к моменту, когда клиентский скрипт успевает его спросить.
ReplicatedStorage:SetAttribute("TurretsUnlocked", false)

function TowerUnlocks.IsLocked(towerType)
	local data = Towers[towerType]
	return data ~= nil and data.locked == true and not unlocked
end

-- Возвращает true, только если этот вызов действительно что-то разблокировал —
-- по этому флагу PromoCode отличает первый ввод кода от повторного.
function TowerUnlocks.UnlockAll()
	if unlocked then
		return false
	end
	unlocked = true
	ReplicatedStorage:SetAttribute("TurretsUnlocked", true)
	return true
end

return TowerUnlocks
