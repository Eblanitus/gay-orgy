-- Связь конструктора волн с клиентом. Сама логика и вся проверка — в WaveEditor;
-- здесь только ремоуты, как у CraftInteraction со столом.
--
-- Клиенту отдаётся три вещи: открыт ли конструктор, список видов и текущий заказ.
-- Список видов идёт с сервера, а не читается клиентом из Enemies напрямую, по двум
-- причинам: порядок сортировки должен быть один и тот же, и сервер — единственный,
-- кто решает, какого жука вообще можно заказать.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local WaveEditor = require(ServerScriptService:WaitForChild("WaveEditor"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local WaveEditorState = Remotes:WaitForChild("WaveEditorState")
local RequestSetWave = Remotes:WaitForChild("RequestSetWave")
local Notify = Remotes:WaitForChild("Notify")

local function stateFor()
	return {
		unlocked = WaveEditor.IsUnlocked(),
		roster = WaveEditor.Roster(),
		current = WaveEditor.Current(),
		maxPerType = WaveEditor.MAX_PER_TYPE,
		maxTotal = WaveEditor.MAX_TOTAL,
	}
end

local function push(player)
	if player then
		WaveEditorState:FireClient(player, stateFor())
	else
		WaveEditorState:FireAllClients(stateFor())
	end
end

-- Любая смена состояния уезжает всем: конструктор открывается на весь забег, а не
-- на одного игрока, и заказ у волны общий.
WaveEditor.Changed.Event:Connect(function()
	push()
end)

Players.PlayerAdded:Connect(function(player)
	-- Та же досылка, что и у инвентаря в CraftInteraction: клиент подключился позже
	-- всех рассылок и без неё увидел бы пустоту.
	task.wait(1)
	push(player)
end)

RequestSetWave.OnServerEvent:Connect(function(player, groups)
	local ok, result = WaveEditor.Set(groups)
	if not ok then
		Notify:FireClient(player, result)
		return
	end

	if result == 0 then
		Notify:FireClient(player, "Состав сброшен: волны пойдут как обычно")
	else
		Notify:FireClient(player, ("Состав принят: %d жуков в следующей волне"):format(result))
	end
end)
