-- Приём настроек интерфейса от клиента и хранение их в профиле.
--
-- Настройка тут вся косметическая и применяется на клиенте сразу, не дожидаясь ответа:
-- серверу она нужна только затем, чтобы пережить выход из игры. Проверка всё равно
-- здесь, а не на клиенте: без неё любой клиент пишет в чужой сохранённый профиль
-- любой ключ с любым значением, а это уже не косметика, а чужой DataStore.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local UISettings = require(ReplicatedStorage:WaitForChild("UISettings"))
local PlayerData = require(ServerScriptService:WaitForChild("PlayerData"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RequestSetSettingRemote = Remotes:WaitForChild("RequestSetSetting")

RequestSetSettingRemote.OnServerEvent:Connect(function(player, key, value)
	-- Ключ и тип значения сверяются с той же таблицей, по которой клиент рисует
	-- экран настроек: убрали настройку из списка — сервер перестал её принимать тем
	-- же движением, без второй правки здесь.
	if type(key) ~= "string" or not UISettings.Valid(key, value) then
		return
	end

	local data = PlayerData.Get(player)
	if not data then
		return -- профиль ещё не загрузился или уже закрыт: записывать некуда
	end

	data.settings = data.settings or {}
	data.settings[key] = value
end)
