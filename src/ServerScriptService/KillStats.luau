-- Счёт убийств для ступеней справочника (ReplicatedStorage.Mastery): сколько жуков добил
-- каждый элемент и сколько раз убит каждый тип жука. Как killedTypes, засчитывается всем
-- игрокам на сервере — убийство общее. До клиента счёт идёт событием KillStats: сразу
-- после загрузки профиля и потом пачкой раз в SEND_INTERVAL, а не на каждое убийство.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Elements = require(ReplicatedStorage:WaitForChild("Elements"))
local PlayerData = require(ServerScriptService:WaitForChild("PlayerData"))

local KillStatsRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("KillStats")

local SEND_INTERVAL = 2 -- сек

local KillStats = {}

local dirty = {} -- player -> true: счёт менялся с последней отправки

-- Профиль до этой задачи счёта не знал: убитый тип жука (killedTypes) — это хотя бы одно убийство.
local function prepare(data)
	data.elementKills = data.elementKills or {}
	data.enemyKills = data.enemyKills or {}
	for key, value in data.killedTypes do
		if value and not data.enemyKills[key] then
			data.enemyKills[key] = 1
		end
	end
end

local function send(player, data)
	dirty[player] = nil
	KillStatsRemote:FireClient(player, data.elementKills, data.enemyKills)
end

-- elementKey — элемент последнего попадания (атрибут LastElement), может быть nil:
-- жука убило не турелью (взорвался сам у стены и т. п.) — тогда счёт только у жука.
function KillStats.Record(enemyType, elementKey)
	if type(elementKey) == "string" and not Elements[elementKey] then
		elementKey = nil
	end
	for _, player in Players:GetPlayers() do
		local data = PlayerData.Get(player)
		if data then
			prepare(data)
			data.enemyKills[enemyType] = (data.enemyKills[enemyType] or 0) + 1
			if elementKey then
				data.elementKills[elementKey] = (data.elementKills[elementKey] or 0) + 1
			end
			dirty[player] = true
		end
	end
end

local function onLoaded(player, data)
	prepare(data)
	send(player, data)
end

PlayerData.Loaded.Event:Connect(onLoaded)
for _, player in Players:GetPlayers() do
	local data = PlayerData.Get(player)
	if data then
		onLoaded(player, data)
	end
end
Players.PlayerRemoving:Connect(function(player)
	dirty[player] = nil
end)

task.spawn(function()
	while true do
		task.wait(SEND_INTERVAL)
		for player in dirty do
			local data = PlayerData.Get(player)
			if data then
				send(player, data)
			else
				dirty[player] = nil
			end
		end
	end
end)

return KillStats
