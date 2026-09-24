-- Жизненный цикл забега: очередь волн, прочность лабораторного стола, победа/поражение,
-- лобби и переход в уровень (alchemy_td_lobby.md, шаг 3).
--
-- Начальное состояние забега собирается здесь целиком (пустая арена, стартовая материя,
-- стартовая башня) в startRun — её вызывает каждый вход в уровень через прибор в лобби,
-- а не отдельная ветка логики.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Levels = require(ReplicatedStorage:WaitForChild("Levels"))
local Arena = require(ReplicatedStorage:WaitForChild("Arena"))
-- Карта уровня (Levels[n].map) и проверка описания уровня при старте сервера.
local LocationService = require(ServerScriptService:WaitForChild("LocationService"))
local LevelSchema = require(ServerScriptService:WaitForChild("LevelSchema"))
local EnemySpawner = require(ServerScriptService:WaitForChild("EnemySpawner"))
local TowerBootstrap = require(ServerScriptService:WaitForChild("TowerBootstrap"))
local Matter = require(ServerScriptService:WaitForChild("Matter"))
local Inventory = require(ServerScriptService:WaitForChild("Inventory"))
local Projectile = require(ServerScriptService:WaitForChild("Projectile"))
local Grid = require(ServerScriptService:WaitForChild("Grid"))
local Crowd = require(ServerScriptService:WaitForChild("Crowd"))
local Corpses = require(ServerScriptService:WaitForChild("Corpses"))
local WaveState = require(ServerScriptService:WaitForChild("WaveState"))
local Plutonium = require(ServerScriptService:WaitForChild("Plutonium"))
-- Профиль игрока: проверка открытости уровня при входе в него (прибор лобби ниже)
-- и досылка плутония/уровней в лобби по PlayerData.Loaded.
local PlayerData = require(ServerScriptService:WaitForChild("PlayerData"))
-- Лабораторный стол и конструкции жуков — такая же часть арены, как трупы и башни:
-- разбираются вместе со всей ареной (design: alchemy_td_enemies.md).
local LabTable = require(ServerScriptService:WaitForChild("LabTable"))
-- Справочник и производитель элементов — та же мебель арены, что и стол.
local LabStations = require(ServerScriptService:WaitForChild("LabStations"))
-- Конструктор волн (открывается промокодом): если игрок задал свой состав,
-- волна идёт им, а не тем, что выписан в Waves.
local WaveEditor = require(ServerScriptService:WaitForChild("WaveEditor"))
local EnemyStructures = require(ServerScriptService:WaitForChild("EnemyStructures"))
-- Рельеф бетонного пола — такая же часть арены, как постройки и трупы: новый
-- забег начинается с ровного пола, а не с ям прошлого.
local ConcreteFloor = require(ServerScriptService:WaitForChild("ConcreteFloor"))
local Lithosphere = require(ServerScriptService:WaitForChild("Lithosphere"))
local Effects = require(ReplicatedStorage:WaitForChild("Effects"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local WaveChangedRemote = Remotes:WaitForChild("WaveChanged")
local RunEndedRemote = Remotes:WaitForChild("RunEnded")
local RequestStartWaveRemote = Remotes:WaitForChild("RequestStartWave")
local WaveReadyRemote = Remotes:WaitForChild("WaveReady")
local ProfileSyncedRemote = Remotes:WaitForChild("ProfileSynced")
local RequestSelectLevelRemote = Remotes:WaitForChild("RequestSelectLevel")
-- Кнопка «Играть» главного меню (MainMenu). Второй вход в ту же дверь, что и прибор
-- в лобби: оба зовут enterLevel и проходят те же проверки.
local RequestEnterLevelRemote = Remotes:WaitForChild("RequestEnterLevel")

local enemiesFolder = Workspace:WaitForChild("Enemies")
local towersFolder = Workspace:WaitForChild("Towers")
local lobbySpawn = Workspace:WaitForChild("SpawnLocation")

-- Уровни с ошибкой в описании (см. LevelSchema). В них нельзя войти; причина — в выводе.
local invalidLevels = {}
for number, level in Levels do
	local ok, reason = LevelSchema.CheckLevel(number, level, LocationService.Exists)
	if not ok then
		invalidLevels[number] = true
		warn(("[Уровни] уровень %s недоступен: %s"):format(tostring(number), reason))
	end
end

local function levelPlayable(levelNumber)
	local levelInfo = Levels[levelNumber]
	return levelInfo ~= nil and levelInfo.waves ~= nil and not invalidLevels[levelNumber]
end

-- Номер текущего забега. Цикл волн узнаёт по нему, что его забег уже сменился, и молча
-- выходит: без этого повторный вход в уровень запускал бы вторую очередь волн параллельно первой.
local generation = 0
-- true — забег сейчас не идёт (сервер только стартовал, либо предыдущий уже кончился и игрок
-- вернулся в лобби). Прибор входа в уровень принимает нажатие только в этом состоянии —
-- иначе прибор в лобби мог бы запустить вторую волну поверх идущей.
local runEnded = true

-- Волны идущего забега — ставит startRun по выбранному уровню (Levels[n].waves). Нужна
-- отдельным module-level полем, а не только параметром runWaves: PlayerAdded ниже досылает
-- общее число волн догнавшему игроку и не имеет доступа к локалям runWaves.
local activeLevelWaves = nil

-- Уровень, который откроет прибор входа игроку (alchemy_td_lobby.md, шаг 4) — выбирается
-- в лобби кликом по строке (RequestSelectLevel), по умолчанию первый. Клиенту здесь ничего
-- не доверяется: выбор перепроверяется заново в момент входа, см. Triggered ниже.
local selectedLevel = {}

-- Волны не начинаются сами: каждую зовёт игрок кнопкой. Без этого первая волна шла
-- сразу после старта сервера, и времени на постройку лабиринта не оставалось вообще.
-- Флаг снимается в момент старта волны, чтобы повторное нажатие не прокручивало очередь вперёд.
local startRequested = false

-- Номер волны, которую сейчас ждём (nil, пока волна идёт). Нужен, чтобы дослать состояние
-- игроку, чей клиент подписался позже рассылки: без этого кнопка волны не появлялась вовсе,
-- и забег вставал насмерть.
local pendingWave = nil

-- Прямое объявление вперёд: LabTable.OnDestroyed ниже вызывает returnToLobby, а определена
-- она только дальше по файлу — без этой строки имя внутри колбэка ушло бы в глобальную (nil),
-- потому что local виден local только с точки своего объявления и ниже.
local returnToLobby

-- Уничтожение лабораторного стола — поражение (design: alchemy_td_enemies_v1.1.md,
-- «Лабораторный стол»: «Если стол уничтожен — комбинирование невозможно»).
LabTable.OnDestroyed(function()
	if runEnded then
		return
	end

	runEnded = true
	print("[Забег] лабораторный стол уничтожен — забег окончен")
	print("поражение")
	RunEndedRemote:FireAllClients(false)
	returnToLobby()
end)

-- Возвращает арену к пустому виду.
--
-- Занятость сбрасывается одним Grid.Reset, а не по Free на каждую сносимую постройку:
-- арена разбирается целиком, и поклеточная бухгалтерия здесь — только лишний способ разойтись
-- с тем, что реально стоит на поле.
local function clearArena()
	for _, enemy in enemiesFolder:GetChildren() do
		enemy:Destroy()
	end

	for _, tower in towersFolder:GetChildren() do
		tower:Destroy()
	end

	-- Снаряды живут отдельно от выпустившей их башни и пережили бы её снос: выстрел,
	-- ушедший за миг до конца забега, долетел бы уже в новый и ударил первого же врага.
	Projectile.ClearAll()

	-- Толкучка забывает всех разом — по той же причине, по которой занятость сбрасывается
	-- одним Grid.Reset: враги сносятся пачкой, и поштучная бухгалтерия здесь — только лишний
	-- способ оставить в новом забеге призрака, об которого расталкиваются живые.
	Crowd.Clear()

	-- Трупы и кровь живут до конца ЗАБЕГА (дизайн, раздел 3): поле зарастает останками
	-- всю его длину и чистится ровно здесь, вместе со всей остальной ареной.
	Corpses.Clear()

	-- Стены, пандусы, кормушки, окопы, коконы и хитин. Именно здесь снимается хитин
	-- Архитектора, который «меняет карту навсегда»: навсегда — это до конца забега,
	-- ремонту он не подлежит.
	EnemyStructures.Clear()

	-- Сначала забываются участки Литосферы, потом выравнивается пол: наоборот
	-- живой сторож ямы успел бы заказать её обратно уже после выравнивания.
	Lithosphere.Clear()
	ConcreteFloor.Reset()

	-- Стол возвращается целым, а привычка колонии к оружию (Эволюционер) — обнуляется:
	-- ни то, ни другое не должно переезжать из прошлой попытки в следующую.
	LabTable.Reset()
	LabStations.Reset()
	Effects.ResetElementUsage()

	Grid.Reset()
end

-- Лобби и арена — одна комната в том же плейсе (alchemy_td_lobby.md, шаг 3): переход
-- между ними — перемещение персонажа, а не загрузка или межсерверный телепорт.
local function teleportToLobby(player)
	local character = player.Character
	if not character then
		return
	end
	character:PivotTo(lobbySpawn.CFrame + Vector3.new(0, 3, 0))
end

local function teleportToArena(player)
	local character = player.Character
	if not character then
		return
	end
	-- Точка появления — из активной локации на момент телепорта: у каждой карты своя.
	local arenaSpawn = Arena.Location().Markers.PlayerSpawn
	character:PivotTo(arenaSpawn.CFrame + Vector3.new(0, 3, 0))
end

-- Состояние забега уничтожается здесь, в момент возврата в лобби (а не только откладывается
-- до следующего входа) — ровно так, как требует ТЗ. Без local — присваивает заранее
-- объявленной переменной (см. комментарий у её объявления выше), а не создаёт новую.
function returnToLobby()
	clearArena()
	for _, player in Players:GetPlayers() do
		teleportToLobby(player)
	end
end

local function runWaves(myGeneration, levelNumber)
	local function cancelled()
		return generation ~= myGeneration
	end

	for i, wave in ipairs(activeLevelWaves) do
		if runEnded or cancelled() then
			return
		end

		-- Ждём кнопки. Пауза между волнами теперь не по таймеру, а по готовности игрока:
		-- в maze строить надо до волны, а сколько на это нужно времени, таймер знать не может.
		startRequested = false
		pendingWave = wave.number
		WaveState.SetActive(false)
		WaveReadyRemote:FireAllClients(wave.number, #activeLevelWaves)
		while not startRequested do
			if runEnded or cancelled() then
				pendingWave = nil
				return
			end
			task.wait(0.1)
		end
		startRequested = false
		pendingWave = nil

		-- Состав волны спрашивается один раз и дальше используется везде: спроси мы его
		-- дважды, игрок мог бы поменять заказ между логом и спавном, и в логе было бы
		-- написано одно, а пришло бы другое.
		local groups, byPlayer = WaveEditor.Groups(wave)

		local parts = {}
		for _, group in groups do
			table.insert(parts, ("%d x %s"):format(group.count, group.enemyType))
		end
		print(("[Волна] волна %d%s: %s")
			:format(wave.number, byPlayer and " (состав задан игроком)" or "", table.concat(parts, ", ")))
		WaveChangedRemote:FireAllClients(wave.number, #activeLevelWaves)
		WaveState.SetActive(true)

		-- Каждая группа — свой вызов SpawnGroup в отдельном task.spawn: SpawnGroup сам блокируется
		-- на task.wait(SPAWN_INTERVAL) между юнитами внутри группы — без этого вторая группа ждала бы
		-- первую целиком, и волна была бы не смешанной, а последовательной внутри одной кнопки.
		for _, group in groups do
			task.spawn(function()
				EnemySpawner.SpawnGroup(group.enemyType, group.count, group.hp, cancelled)
			end)
		end

		while #enemiesFolder:GetChildren() > 0 do
			if runEnded or cancelled() then
				return
			end
			task.wait(0.2)
		end

		if runEnded or cancelled() then
			return
		end

		Matter.Add(Matter.WAVE_CLEAR_BONUS)
		Plutonium.AwardWaveClear(levelNumber, wave.number)

		if i < #activeLevelWaves then
			print(("[Волна] волна %d зачищена, ждём кнопки"):format(wave.number))
		end
	end

	if not runEnded and not cancelled() then
		runEnded = true
		Plutonium.AwardLevelClear(levelNumber)
		print("победа")
		RunEndedRemote:FireAllClients(true)
		returnToLobby()
	end
end

local function startRun(levelNumber)
	generation += 1
	local myGeneration = generation

	-- Разбираем арену до того, как снять runEnded — см. комментарий у LabTable.OnDestroyed.
	clearArena()

	-- Карта уровня — на уже пустой арене: сносить останки прошлого забега по новой
	-- геометрии нельзя. Та же карта, что уже стоит, ничего не делает.
	local loaded, reason = LocationService.Load(Levels[levelNumber].map)
	if not loaded then
		warn(("[Забег] уровень %d не запущен: %s"):format(levelNumber, reason))
		return
	end

	runEnded = false
	activeLevelWaves = Levels[levelNumber].waves
	WaveState.SetActive(false)
	Matter.Reset()
	-- Элементы живут ровно один забег (дизайн-док: «знание сохраняется, имущество — нет»).
	-- Открытые рецепты лежат в Crafting и здесь намеренно не трогаются.
	Inventory.Reset()
	TowerBootstrap.PlaceStartingTower()

	for _, player in Players:GetPlayers() do
		teleportToArena(player)
	end

	task.spawn(runWaves, myGeneration, levelNumber)
end

RequestStartWaveRemote.OnServerEvent:Connect(function()
	startRequested = true
end)

-- Зашедшему игроку отдаём текущее состояние. Обычные рассылки уходят в момент события,
-- а клиентские скрипты запускаются позже старта сервера — без досылки игрок видит пустой HUD
-- и нет кнопки, чтобы начать.
Players.PlayerAdded:Connect(function(player)
	-- Смерть посреди волны не должна выкидывать игрока в лобби мимо забега: штатный респаун
	-- Roblox всегда ставит персонажа на Workspace.SpawnLocation (лобби), а забег в этот момент
	-- может ещё идти. Без этого игрок застревал в лобби с идущим runEnded == false и не мог
	-- вернуться — портал ниже как раз отказывает входить, пока предыдущий забег не кончился.
	player.CharacterAdded:Connect(function(character)
		if not runEnded then
			character:WaitForChild("HumanoidRootPart", 5)
			teleportToArena(player)
		end
	end)

	task.wait(1)
	Matter.SyncTo(player)
	if pendingWave then
		WaveReadyRemote:FireClient(player, pendingWave, #activeLevelWaves)
	end

	-- Профиль досылается ещё раз, вместе с остальным состоянием. Рассылка по
	-- PlayerData.Loaded (ниже) уходит в момент загрузки профиля, а он загружается быстрее,
	-- чем клиент успевает подключить свои обработчики: замерено в Studio — сервер держит
	-- уровень 1 открытым, а журнал на клиенте показывает «закрыт», потому что первое
	-- ProfileSynced до него не дошло вовсе. Второй раз — по тому же таймауту, что и
	-- остальная досылка выше.
	local data = PlayerData.WaitFor(player)
	if data then
		ProfileSyncedRemote:FireClient(player, data.plutonium, data.levels, data.recipes, data.killedTypes, data.settings)
	end
end)

-- Вышел посреди забега — арену нельзя оставлять досыпаться впустую (alchemy_td_lobby.md, шаг 3:
-- «забег не восстанавливается») — без этого тот же сервер без перезахода держал бы чужую
-- волну живой до самого конца, хотя игрок её уже не видит.
Players.PlayerRemoving:Connect(function(player)
	selectedLevel[player] = nil
	if not runEnded then
		runEnded = true
		print("[Забег] игрок вышел посреди забега — арена сбрасывается")
		returnToLobby()
	end
end)

-- Плутоний и прогресс по уровням показывает лобби, пока забег не идёт. Досылка на PlayerData.Loaded,
-- а не на PlayerAdded с таймаутом — там профиль уже точно загружен, а не просто «прошла секунда».
PlayerData.Loaded.Event:Connect(function(player, data)
	ProfileSyncedRemote:FireClient(player, data.plutonium, data.levels, data.recipes, data.killedTypes, data.settings)
end)

-- Выбор уровня (alchemy_td_lobby.md, шаг 4): лобби-панель шлёт номер кликом по строке,
-- сервер запоминает его как намерение игрока и ничего больше — какой уровень реально
-- откроется, решает Triggered ниже в момент входа, тем же набором проверок заново.
RequestSelectLevelRemote.OnServerEvent:Connect(function(player, levelNumber)
	if type(levelNumber) ~= "number" or levelNumber ~= math.floor(levelNumber) then
		return
	end

	if not levelPlayable(levelNumber) then
		return -- содержимого ещё нет (например, разблокированный, но ещё не сделанный уровень 2)
	end

	local data = PlayerData.Get(player)
	local levelData = data and data.levels[levelNumber]
	if not levelData or not levelData.unlocked then
		return
	end

	selectedLevel[player] = levelNumber
end)

-- Вход в уровень. Два вызывающих — прибор в лобби и кнопка «Играть» в главном меню, —
-- поэтому проверки живут здесь, а не в обработчике одного из них. Разойдись они — игрок
-- попадал бы с кнопки туда, куда прибор его не пускает.
local function enterLevel(player)
	if not runEnded then
		-- забег уже идёт: второй поверх первого не начинаем, но если игрока унесло в лобби
		-- (например, респаун после смерти на арене), портал возвращает его в текущий забег,
		-- а не молча отказывает
		teleportToArena(player)
		return
	end

	-- По умолчанию первый уровень — так прибор работает и без единого клика по списку,
	-- как и до шага 4. Дальше всё перепроверяется заново, а не берётся на веру из selectedLevel.
	local levelNumber = selectedLevel[player] or 1
	local data = PlayerData.Get(player)
	local levelData = data and data.levels[levelNumber]
	if not levelPlayable(levelNumber) or not levelData or not levelData.unlocked then
		return
	end

	print(("[Лобби] %s входит в уровень %d"):format(player.Name, levelNumber))
	startRun(levelNumber)
end

-- Точка входа в уровень — прибор в лобби (alchemy_td_lobby.md, шаг 3). Triggered реплицируется
-- движком только после проверки дистанции/удержания на настоящем ProximityPrompt — это такой
-- же надёжный источник, как OnServerEvent, отдельный RemoteEvent для него не нужен.
local levelEntrancePrompt = Instance.new("ProximityPrompt")
levelEntrancePrompt.Name = "LevelEntrancePrompt"
levelEntrancePrompt.ActionText = "Войти"
levelEntrancePrompt.ObjectText = "Выбранный уровень"
levelEntrancePrompt.HoldDuration = 0
levelEntrancePrompt.MaxActivationDistance = 10
levelEntrancePrompt.Parent = Workspace:WaitForChild("Lobby"):WaitForChild("LevelEntrance")

levelEntrancePrompt.Triggered:Connect(enterLevel)

-- Кнопка «Играть» главного меню: тот же вход, но без требования дойти до прибора.
-- Ничего из сообщённого клиентом здесь не берётся вовсе — какой уровень откроется,
-- решает selectedLevel на сервере (его ставит RequestSelectLevel со своими проверками),
-- поэтому лишних аргументов у этого события нет и проверять в нём нечего.
RequestEnterLevelRemote.OnServerEvent:Connect(enterLevel)
