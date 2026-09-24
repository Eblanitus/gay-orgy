-- Профиль игрока: плутоний, открытые рецепты, прогресс по уровням — то, что должно
-- пережить выход и заход заново (alchemy_td_lobby.md, шаг 1). Хранится через
-- ProfileStore (session-locking): наивный DataStore теряет прогресс при вылете
-- и при заходе с двух устройств одновременно.
--
-- Что здесь НЕ живёт: материя, инвентарь элементов, постройки — это состояние
-- одного забега, оно живёт в Matter/Inventory и сбрасывается в WaveRunner.startRun.
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local ProfileStore = require(ServerScriptService:WaitForChild("ProfileStore"))

-- Профиль по умолчанию для нового игрока: плутоний 0, рецептов не открыто (базовые
-- элементы покупаются за материю сами, это не рецепт), убитых типов жуков нет,
-- открыт только уровень 1.
local DEFAULT_DATA = {
	plutonium = 0,
	-- Опыт (alchemy_td_currencies.md): копится между забегами, даётся за первое прохождение
	-- этажа (alchemy_td_location_v1.6.md), начисляет Plutonium.AwardLevelClear. Тратить его
	-- пока негде — открытие рецептов и турелей за XP отдельное ТЗ.
	xp = 0,
	recipes = {},
	killedTypes = {}, -- тип жука -> true, за что даёт плутоний Plutonium.AwardEnemyKill
	-- Счёт убийств для ступеней справочника (ReplicatedStorage.Mastery), ведёт KillStats.
	elementKills = {}, -- элемент -> сколько жуков добил
	enemyKills = {}, -- тип жука -> сколько раз убит
	levels = {
		[1] = { unlocked = true, completed = false, bestWave = 0 },
	},
	-- Настройки интерфейса из главного меню (ReplicatedStorage.UISettings). Пустая, а не заполненная
	-- умолчаниями: Reconcile досыпает только верхний уровень шаблона и внутрь этой
	-- таблицы не заглядывает, так что у старого профиля настройка, добавленная позже, всё
	-- равно останется незаписанной. Умолчание подставляет UISettings.Read при чтении.
	settings = {},
}

local Store = ProfileStore.New("PlayerSave", DEFAULT_DATA)

local PlayerData = {}

-- Профиль игрока загружен и лежит в profiles[player]. Слушает Crafting, чтобы
-- засеять открытые рецепты после входа, не гадая через task.wait, готовы ли данные.
PlayerData.Loaded = Instance.new("BindableEvent")

local profiles = {}

-- Данные игрока (Profile.Data) либо nil, если профиль ещё грузится, провалился
-- или игрок уже вышел.
function PlayerData.Get(player)
	local profile = profiles[player]
	return profile and profile.Data or nil
end

-- Ждёт готовности профиля (или выхода игрока / провала загрузки — тогда nil).
-- Нужен коду, которому данные требуются сразу при входе, раньше PlayerData.Loaded.
function PlayerData.WaitFor(player)
	while player.Parent == Players and not profiles[player] do
		task.wait(0.1)
	end
	return PlayerData.Get(player)
end

-- Открывает следующий уровень после первого прохождения текущего (alchemy_td_lobby.md,
-- шаг 4: «пройденный открывает следующий»). Next может ещё не существовать в Levels
-- (ReplicatedStorage) — профиль просто помнит, что путь туда открыт, а содержимое
-- появится отдельной задачей, когда уровень действительно сделают.
function PlayerData.UnlockNext(data, level)
	local nextLevel = level + 1
	local nextLevelData = data.levels[nextLevel]
	if not nextLevelData then
		data.levels[nextLevel] = { unlocked = true, completed = false, bestWave = 0 }
	elseif not nextLevelData.unlocked then
		nextLevelData.unlocked = true
	end
end

local function onPlayerAdded(player)
	local profile = Store:StartSessionAsync(("Player_%d"):format(player.UserId), {
		Cancel = function()
			return player.Parent ~= Players
		end,
	})

	if profile == nil then
		-- StartSessionAsync сдаётся сама (см. Cancel) или после долгого конфликта сессий
		-- (второй сервер держит лок). Игрока с пустым профилем в игру не пускаем.
		player:Kick("Не удалось загрузить сохранение. Попробуйте зайти ещё раз.")
		return
	end

	profile:AddUserId(player.UserId)
	profile:Reconcile()

	profile.OnSessionEnd:Connect(function()
		profiles[player] = nil
		player:Kick("Сохранение занято другим сервером. Перезайдите.")
	end)

	if player.Parent ~= Players then
		-- Игрок вышел, пока грузился профиль (см. Cancel) — сессию всё равно нужно
		-- закрыть, иначе она висит занятой до ASSUME_DEAD (630 сек, см. ProfileStore).
		profile:EndSession()
		return
	end

	profiles[player] = profile
	print(("[PlayerData] профиль загружен: %s (плутоний %d)"):format(player.Name, profile.Data.plutonium))
	PlayerData.Loaded:Fire(player, profile.Data)
end

local function onPlayerRemoving(player)
	local profile = profiles[player]
	if profile ~= nil then
		profile:EndSession()
		profiles[player] = nil
	end
end

-- Игроков, зашедших до старта этого скрипта (не бывает в реальной игре, только
-- при перезагрузке кода в Studio), тоже подхватываем — иначе их профиль не грузится вовсе.
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end
Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

return PlayerData
