-- Валюта забега. Один игрок на сервере (по ТЗ), поэтому просто общий счётчик,
-- без привязки к игроку.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local MatterChangedRemote = Remotes:WaitForChild("MatterChanged")

-- Стартовый запас на начало забега. Было 20 (ровно на одну Колбу) ещё до того, как стены
-- и элементы стали отдельными тратами из того же кошелька (задачи #19, #23) — на лабиринт из
-- четырёх стен и хотя бы одного элемента уже не хватало. Поднято до 50: хватает и на
-- небольшой лабиринт из стен, и на первый элемент для заливки — остальное по-прежнему
-- добирается убийствами.
local STARTING_AMOUNT = 50

local Matter = {
	amount = STARTING_AMOUNT,
	-- Материя за прохождение волны (все жуки волны погибли или прорвались). Раньше жила
	-- константой в WaveRunner; число баланса — поэтому таблицей здесь.
	WAVE_CLEAR_BONUS = 20,
}

function Matter.Add(value)
	Matter.amount += value
	MatterChangedRemote:FireAllClients(Matter.amount)
	print(("[Материя] +%d, всего: %d"):format(value, Matter.amount))
end

function Matter.Get()
	return Matter.amount
end

-- Досылает текущее значение одному игроку. Обычные рассылки идут FireAllClients в момент
-- изменения, а игрок, зашедший позже (или чей клиентский скрипт ещё не подписался), их не видит.
function Matter.SyncTo(player)
	MatterChangedRemote:FireClient(player, Matter.amount)
end

-- Возвращает счётчик к стартовому запасу — это часть начального состояния забега,
-- поэтому нужен рестарту (см. WaveRunner).
function Matter.Reset()
	Matter.amount = STARTING_AMOUNT
	MatterChangedRemote:FireAllClients(Matter.amount)
	print(("[Материя] сброшена до %d"):format(Matter.amount))
end

-- Списывает value, если хватает; иначе ничего не делает и возвращает false.
function Matter.Spend(value)
	if Matter.amount < value then
		return false
	end
	Matter.amount -= value
	MatterChangedRemote:FireAllClients(Matter.amount)
	print(("[Материя] -%d, всего: %d"):format(value, Matter.amount))
	return true
end

return Matter
