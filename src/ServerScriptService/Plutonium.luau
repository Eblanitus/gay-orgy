-- Начисление плутония (alchemy_td_currencies.md). Плутоний даётся за достижение нового,
-- а не за время: иначе игрок находит лёгкий забег и гриндит его повторением. Факт
-- «уже получено» живёт в профиле игрока (PlayerData) и проверяется здесь, на сервере;
-- отдельного RemoteEvent на приём нет — начисление вызывают только WaveRunner и
-- EnemySpawner по реальным игровым событиям, подделанный клиент попросить награду не может.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local PlutoniumRewards = require(ReplicatedStorage:WaitForChild("PlutoniumRewards"))
local XPRewards = require(ReplicatedStorage:WaitForChild("XPRewards"))
local Enemies = require(ReplicatedStorage:WaitForChild("Enemies"))
local PlayerData = require(ServerScriptService:WaitForChild("PlayerData"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local NotifyRemote = Remotes:WaitForChild("Notify")
local ProfileSyncedRemote = Remotes:WaitForChild("ProfileSynced")

local Plutonium = {}

-- Единая точка, через которую растёт data.plutonium — лог, уведомление и досылка профиля
-- в лобби не могут разойтись с фактическим начислением, потому что это одна и та же строчка.
local function grant(player, data, value, reason)
	data.plutonium += value
	print(("[Плутоний] %s: +%d (%s), всего %d"):format(player.Name, value, reason, data.plutonium))
	NotifyRemote:FireClient(player, ("+%d плутония: %s"):format(value, reason))
	-- Журналу в главном меню нужны открытые рецепты и убитые типы жуков — то есть ровно то,
	-- за что здесь и начисляется плутоний. Досылается тем же событием, что и само число:
	-- отдельное событие разошлось бы с этим по времени, и журнал показывал бы новый
	-- плутоний рядом со старым списком того, за что его дали.
	ProfileSyncedRemote:FireClient(player, data.plutonium, data.levels, data.recipes, data.killedTypes, data.settings, data.xp)
end

-- Опыт за первое прохождение этажа (alchemy_td_location_v1.6.md). Тот же флаг completed, что
-- и у плутония за уровень: повторное прохождение не даёт ни того, ни другого. Уведомление
-- своё, а досылку профиля делает grant плутония, который идёт следом.
local function grantXP(player, data, value, reason)
	data.xp = (data.xp or 0) + value
	print(("[Опыт] %s: +%d (%s), всего %d"):format(player.Name, value, reason, data.xp))
	NotifyRemote:FireClient(player, ("+%d опыта: %s"):format(value, reason))
end

-- Первое прохождение волны — оно же новый рекорд на уровне: забег всегда идёт по волнам
-- подряд от первой, поэтому в этом дизайне «волна N пройдена впервые» и «зашёл дальше
-- прежнего рекорда» — одно и то же условие (waveNumber > bestWave), а не два отдельных
-- начисления за одно и то же достижение.
function Plutonium.AwardWaveClear(level, waveNumber)
	for _, player in Players:GetPlayers() do
		local data = PlayerData.Get(player)
		if data then
			local levelData = data.levels[level]
			if waveNumber > levelData.bestWave then
				levelData.bestWave = waveNumber
				grant(player, data, PlutoniumRewards.waveClear, ("волна %d пройдена впервые"):format(waveNumber))
			end
		end
	end
end

-- Первое прохождение уровня целиком — разовая награда, начисляется поверх обычной
-- награды за последнюю волну, не вместо неё.
function Plutonium.AwardLevelClear(level)
	for _, player in Players:GetPlayers() do
		local data = PlayerData.Get(player)
		if data then
			local levelData = data.levels[level]
			if not levelData.completed then
				levelData.completed = true
				-- Пройденный уровень открывает следующий (alchemy_td_lobby.md, шаг 4).
				PlayerData.UnlockNext(data, level)
				grantXP(player, data, XPRewards.levelClear, "этаж пройден впервые")
				grant(player, data, PlutoniumRewards.levelClear, "уровень пройден впервые")
			end
		end
	end
end

-- Первое убийство нового типа жука. Общее на весь профиль, а не на уровень: тип жука —
-- это факт, который игрок либо уже видел мёртвым, либо нет, вне зависимости от того, где.
function Plutonium.AwardEnemyKill(enemyType)
	for _, player in Players:GetPlayers() do
		local data = PlayerData.Get(player)
		if data and not data.killedTypes[enemyType] then
			data.killedTypes[enemyType] = true
			local name = Enemies[enemyType] and Enemies[enemyType].name or enemyType
			grant(player, data, PlutoniumRewards.enemyFirstKill, ("новый тип жука: %s"):format(name))
		end
	end
end

return Plutonium
