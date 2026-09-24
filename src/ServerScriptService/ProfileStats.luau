-- Статистика профиля: счёт убийств для ступеней справочника (ReplicatedStorage.Mastery) и
-- счётчики журнала главного меню (JournalUI). Как killedTypes, засчитывается всем игрокам
-- на сервере — забег общий. До клиента идёт событием ProfileStats: сразу после загрузки
-- профиля и потом пачкой раз в SEND_INTERVAL, а не на каждое событие.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Elements = require(ReplicatedStorage:WaitForChild("Elements"))
local PlayerData = require(ServerScriptService:WaitForChild("PlayerData"))

local ProfileStatsRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("ProfileStats")

local SEND_INTERVAL = 2 -- сек
local TIME_SEND_INTERVAL = 30 -- сек: время в игре досылается само по себе не чаще этого

local ProfileStats = {}

-- Счётчики журнала (data.stats). Список — чтобы опечатка в имени поля падала сразу.
local FIELDS = {
	runs = true, -- забегов начато
	wins = true, -- уровней пройдено (победа)
	defeats = true, -- поражений (стол уничтожен)
	waves = true, -- волн пройдено
	playTime = true, -- секунд на сервере
	crafts = true, -- скрещиваний
	towers = true, -- построек
	matterEarned = true, -- материи получено
	matterSpent = true, -- материи потрачено
}

local dirty = {} -- player -> true: счёт менялся с последней отправки
local joined = {} -- player -> os.clock() последнего учёта времени в игре
local timeSent = 0

-- Профиль до этих счётчиков их не знал: убитый тип жука (killedTypes) — это хотя бы одно убийство.
local function prepare(data)
	data.elementKills = data.elementKills or {}
	data.enemyKills = data.enemyKills or {}
	data.stats = data.stats or {}
	data.enemySeen = data.enemySeen or {}
	data.elementCrafted = data.elementCrafted or {}
	for key, value in data.killedTypes do
		if value and not data.enemyKills[key] then
			data.enemyKills[key] = 1
		end
	end
end

local function send(player, data)
	dirty[player] = nil
	ProfileStatsRemote:FireClient(player, data.elementKills, data.enemyKills, data.stats,
		data.enemySeen, data.elementCrafted)
end

local function forEach(fn)
	for _, player in Players:GetPlayers() do
		local data = PlayerData.Get(player)
		if data then
			prepare(data)
			fn(data)
			dirty[player] = true
		end
	end
end

-- elementKey — элемент последнего попадания (атрибут LastElement), может быть nil:
-- жука убило не турелью (взорвался сам у стены и т. п.) — тогда счёт только у жука.
function ProfileStats.Kill(enemyType, elementKey)
	if type(elementKey) == "string" and not Elements[elementKey] then
		elementKey = nil
	end
	forEach(function(data)
		data.enemyKills[enemyType] = (data.enemyKills[enemyType] or 0) + 1
		if elementKey then
			data.elementKills[elementKey] = (data.elementKills[elementKey] or 0) + 1
		end
	end)
end

-- Жук появился на арене — «встречено» во вкладке «Жуки» журнала.
function ProfileStats.Seen(enemyType)
	forEach(function(data)
		data.enemySeen[enemyType] = (data.enemySeen[enemyType] or 0) + 1
	end)
end

-- Скрещивание дало элемент — «создано» во вкладке «Элементы» журнала и общий счётчик crafts.
function ProfileStats.Crafted(elementKey)
	forEach(function(data)
		data.elementCrafted[elementKey] = (data.elementCrafted[elementKey] or 0) + 1
		data.stats.crafts = (data.stats.crafts or 0) + 1
	end)
end

-- Прибавить к счётчику журнала (FIELDS) всем игрокам на сервере.
function ProfileStats.Add(field, amount)
	assert(FIELDS[field], ("ProfileStats: нет счётчика %s"):format(tostring(field)))
	amount = amount or 1
	if amount == 0 then
		return
	end
	forEach(function(data)
		data.stats[field] = (data.stats[field] or 0) + amount
	end)
end

local function onLoaded(player, data)
	prepare(data)
	joined[player] = os.clock()
	send(player, data)
end

PlayerData.Loaded.Event:Connect(onLoaded)
for _, player in Players:GetPlayers() do
	local data = PlayerData.Get(player)
	if data then
		onLoaded(player, data)
	end
end

-- Время в игре дописывается в профиль по ходу, а не только при выходе: профиль
-- сохраняется сам (ProfileStore), и на выходе он может закрыться раньше этого обработчика.
local function countTime(player)
	local since = joined[player]
	local data = PlayerData.Get(player)
	if since and data then
		local now = os.clock()
		prepare(data)
		data.stats.playTime = (data.stats.playTime or 0) + (now - since)
		joined[player] = now
	end
end

Players.PlayerRemoving:Connect(function(player)
	countTime(player)
	dirty[player] = nil
	joined[player] = nil
end)

task.spawn(function()
	while true do
		task.wait(SEND_INTERVAL)
		local now = os.clock()
		local sendTime = now - timeSent >= TIME_SEND_INTERVAL
		if sendTime then
			timeSent = now
		end
		for player in joined do
			countTime(player)
			if sendTime then
				dirty[player] = true
			end
		end
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

return ProfileStats
