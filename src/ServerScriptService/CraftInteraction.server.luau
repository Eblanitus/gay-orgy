-- Связывает игрока со столом крафта. Сами Crafting и Inventory про интерфейс не знают.
-- Решение всегда за сервером: клиент только просит.
--
-- К столу надо подойти — это требование дизайн-дока, а не украшение: крафт работает и во время
-- волны, поэтому отход к столу — это выбор между наблюдением за полем и смешиванием.
-- Расстояние проверяется заново на каждый запрос: само по себе открытое окно ничего
-- не доказывает, клиент мог отойти или вообще не открывать его.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Elements = require(ReplicatedStorage:WaitForChild("Elements"))
local Inventory = require(ServerScriptService:WaitForChild("Inventory"))
local Crafting = require(ServerScriptService:WaitForChild("Crafting"))
-- Прочность стола (design: alchemy_td_enemies.md): «Если стол уничтожен — комбинирование
-- невозможно или ограничено.» Проверка здесь, а не в Crafting: само смешивание
-- про мебель не знает и знать не должно — это тот же вопрос доступа, что и nearTable.
local LabTable = require(ServerScriptService:WaitForChild("LabTable"))
-- Справочник и производитель базовых элементов — отдельная мебель (alchemy_td_location_v1.6.md):
-- стол только для крафта, покупка — у производителя, дерево крафта — на доске.
local LabStations = require(ServerScriptService:WaitForChild("LabStations"))
-- Второй режим того же производителя (alchemy_td_location_v1.6.md): случайный элемент
-- вместо выбора. Розыгрыш и деньги живут в Roulette, здесь — только доступ к автомату.
local Roulette = require(ServerScriptService:WaitForChild("Roulette"))
-- Третий режим того же автомата: элемент двигается вперёд по своей ветке.
-- Проверки веток и розыгрыш живут в Upgrader, здесь — только доступ к автомату.
local Upgrader = require(ServerScriptService:WaitForChild("Upgrader"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RequestCraft = Remotes:WaitForChild("RequestCraft")
local RequestBuyElement = Remotes:WaitForChild("RequestBuyElement")
local RequestRouletteSpin = Remotes:WaitForChild("RequestRouletteSpin")
local RequestUpgrade = Remotes:WaitForChild("RequestUpgrade")
local Notify = Remotes:WaitForChild("Notify")
-- Показ розыгрыша: барабаны рулетки и стрелка апгрейдера. Клиент только рисует
-- то, что сервер уже разыграл.
local RouletteShow = Remotes:WaitForChild("RouletteShow")
local UpgradeShow = Remotes:WaitForChild("UpgradeShow")


local MAX_DISTANCE = 14 -- studs от стола; чуть больше радиуса подсказки, чтобы шаг в сторону не рвал окно

local prompt = Instance.new("ProximityPrompt")
prompt.Name = "CraftPrompt"
prompt.ActionText = "Стол крафта"
prompt.ObjectText = "Лаборатория"
prompt.HoldDuration = 0
prompt.MaxActivationDistance = 12
-- Стол берётся из LabTable: при смене локации подсказка переезжает на её стол.
local function attachPrompt(craftTable)
	prompt.Parent = craftTable:FindFirstChild("Top") or craftTable.PrimaryPart
end
attachPrompt(LabTable.Model())
LabTable.OnChanged(attachPrompt)

-- Стол разгрызен — сказать об этом вслух один раз, а не ждать, пока игрок сам придёт
-- к столу и получит отказ. Полоска HP над столом показывает ход грызни (BuildingVisuals),
-- а это сообщение — её итог.
LabTable.OnDestroyed(function()
	for _, player in Players:GetPlayers() do
		Notify:FireClient(player, "лабораторный стол разгрызен — комбинировать негде")
	end
end)

-- Подсказки станций. Имя подсказки — ключ для клиента: по нему CraftingUI открывает свой раздел.
local stationPrompts = {}
local function makeStationPrompt(stationName, promptName, actionText)
	local p = Instance.new("ProximityPrompt")
	p.Name = promptName
	p.ActionText = actionText
	p.ObjectText = "Лаборатория"
	p.HoldDuration = 0
	p.MaxActivationDistance = 12
	p.RequiresLineOfSight = false
	stationPrompts[stationName] = p
end
makeStationPrompt("ReferenceBoard", "BookPrompt", "Справочник")
makeStationPrompt("ElementProducer", "ElementPrompt", "Производитель")

-- Подсказка стоит на целой станции и снимается с разбитой: окно разбитой станции открывать нечем.
-- Вкл/выкл следит за самим атрибутом HP, а не только за событиями LabStations: так подсказка
-- совпадает с прочностью, кто бы и как бы её ни менял.
local hpWatchers = {}
local function attachStationPrompts()
	for stationName, p in stationPrompts do
		p.Parent = LabStations.Anchor(stationName)
		p.Enabled = LabStations.IsAlive(stationName)

		if hpWatchers[stationName] then
			hpWatchers[stationName]:Disconnect()
			hpWatchers[stationName] = nil
		end
		local model = LabStations.Model(stationName)
		if model then
			hpWatchers[stationName] = model:GetAttributeChangedSignal("HP"):Connect(function()
				p.Enabled = LabStations.IsAlive(stationName)
			end)
		end
	end
end
attachStationPrompts()
LabStations.OnChanged(attachStationPrompts)

local STATION_LOST = {
	ReferenceBoard = "справочник разбит",
	ElementProducer = "производитель элементов разбит — элементы получать негде",
}
LabStations.OnDestroyed(function(stationName)
	local p = stationPrompts[stationName]
	if p then
		p.Enabled = false
	end
	for _, player in Players:GetPlayers() do
		Notify:FireClient(player, STATION_LOST[stationName])
	end
end)

local PRODUCER_DISTANCE = 14 -- как MAX_DISTANCE у стола

local function nearProducer(player)
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	local anchor = LabStations.Anchor("ElementProducer")
	if not rootPart or not anchor then
		return false
	end
	return (rootPart.Position - anchor.Position).Magnitude <= PRODUCER_DISTANCE
end

local function nearTable(player)
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		return false
	end
	return (rootPart.Position - LabTable.Position()).Magnitude <= MAX_DISTANCE
end

RequestBuyElement.OnServerEvent:Connect(function(player, elementKey)
	if typeof(elementKey) ~= "string" or not Elements[elementKey] then
		return
	end
	if not LabStations.IsAlive("ElementProducer") then
		Notify:FireClient(player, "производитель разбит — элементы получать негде")
		return
	end
	if not nearProducer(player) then
		Notify:FireClient(player, "надо подойти к производителю")
		return
	end

	local ok, reason = Inventory.Buy(elementKey)
	if not ok then
		Notify:FireClient(player, reason)
	end
end)

-- Пока прокрутка не завершена, новый запуск не принимается (требование вики). Флаг на сервере,
-- а не блокировка кнопки на клиенте: клиент может прислать десять запросов подряд.
-- Прокрутка завершена, когда остановились барабаны: флаг держится всё время показа.
local spinning = false

-- Серия прокруток (RouletteConfig.ShowTime): когда игрок дождался прошлой и какая по счёту
-- эта. Первый запуск показывают медленно, запуски сразу друг за другом — быстрее.
local lastSpinEnd, spinStreak = {}, {}
Players.PlayerRemoving:Connect(function(player)
	lastSpinEnd[player], spinStreak[player] = nil, nil
end)

RequestRouletteSpin.OnServerEvent:Connect(function(player, spins)
	if typeof(spins) ~= "number" then
		return
	end
	if not LabStations.IsAlive("ElementProducer") then
		Notify:FireClient(player, "производитель разбит — элементы получать негде")
		return
	end
	if not nearProducer(player) then
		Notify:FireClient(player, "надо подойти к производителю")
		return
	end
	if spinning then
		return
	end

	spinning = true
	local ok, result, bonus = Roulette.Spin(spins)

	if not ok then
		spinning = false
		Notify:FireClient(player, result)
		return
	end

	-- Материя уже списана, элементы приходят, когда барабаны встанут. Сбросился забег
	-- за эти секунды — выпавшее принадлежит старому забегу и в новую сумку не идёт.
	local epoch = Inventory.Epoch()
	local last = lastSpinEnd[player]
	local streak = 0
	if last and os.clock() - last <= Roulette.Config.SERIES_GAP then
		streak = (spinStreak[player] or 0) + 1
	end
	spinStreak[player] = streak
	-- Сколько крутятся барабаны, решает сервер и шлёт вместе с итогом: замок и выдача
	-- ждут ровно столько же, сколько идёт показ.
	local time = Roulette.Config.ShowTime(streak)
	RouletteShow:FireClient(player, result, time, bonus)
	-- Джекпот показывают после барабанов: подарок приходит, когда кончится и этот показ.
	task.wait(time + (bonus and Roulette.Config.JACKPOT_TIME or 0))
	if Inventory.Epoch() == epoch then
		Roulette.Grant(result, bonus)
	end
	spinning = false
	if player.Parent then
		lastSpinEnd[player] = os.clock()
	end

	-- Итог ещё и списком: счётчики инвентаря при повторах не показывают, что выпало.
	local names = {}
	for i, key in result do
		names[i] = Elements[key].name
	end
	local text = ("рулетка: %s"):format(table.concat(names, ", "))
	if bonus then
		text ..= ("; джекпот: ещё %d %s в подарок"):format(Roulette.Config.JACKPOT_BONUS, Elements[bonus].name)
	end
	Notify:FireClient(player, text)
end)

-- Пока попытка не завершена, новая не принимается (требование вики). Флаг на сервере,
-- а не блокировка кнопки на клиенте: клиент может прислать десять запросов подряд.
-- Попытка завершена, когда остановилась стрелка: флаг держится всё время показа.
local upgrading = false

RequestUpgrade.OnServerEvent:Connect(function(player, fromKey, toKey)
	if type(fromKey) ~= "string" or type(toKey) ~= "string" then
		return
	end
	if not LabStations.IsAlive("ElementProducer") then
		Notify:FireClient(player, "производитель разбит — апгрейдить негде")
		return
	end
	if not nearProducer(player) then
		Notify:FireClient(player, "надо подойти к производителю")
		return
	end
	if upgrading then
		return
	end

	upgrading = true
	local ok, result = Upgrader.Try(fromKey, toKey)

	if not ok then
		upgrading = false
		Notify:FireClient(player, result)
		return
	end

	-- Вложенное уже снято, итог приходит, когда встанет стрелка. Сбросился забег
	-- за эти секунды — итог принадлежит старому забегу и в новую сумку не идёт.
	local epoch = Inventory.Epoch()
	UpgradeShow:FireClient(player, result)
	task.wait(Upgrader.Config.SHOW_TIME)
	if Inventory.Epoch() == epoch then
		Upgrader.Grant(result)
	end
	upgrading = false

	-- Итог ещё и словами: по одним счётчикам инвентаря не видно, сгорел элемент
	-- или превратился — особенно когда такой элемент в сумке был не один.
	local fromName = Elements[result.from].name
	local toName = Elements[result.to].name
	if result.won then
		Notify:FireClient(player, ("апгрейдер: %s → %s, получилось"):format(fromName, toName))
	else
		Notify:FireClient(player, ("апгрейдер: %s сгорел, %s не вышел"):format(fromName, toName))
	end
end)

RequestCraft.OnServerEvent:Connect(function(player, a, b)
	if typeof(a) ~= "string" or typeof(b) ~= "string" then
		return
	end
	if not Elements[a] or not Elements[b] then
		return
	end
	if not nearTable(player) then
		Notify:FireClient(player, "надо подойти к столу")
		return
	end
	if not LabTable.IsAlive() then
		Notify:FireClient(player, "стол разгрызен — комбинировать негде")
		return
	end

	local ok, result = Crafting.Craft(a, b)
	if not ok then
		Notify:FireClient(player, result)
	end
end)

-- Новому игроку надо отдать текущее состояние: его клиент подключился позже всех рассылок.
-- Знание рецептов живёт в Crafting дольше, чем один забег (рестарт его не сбрасывает), а RecipeLearned
-- раньше был только одноразовым событием открытия — без досылки справочник у зашедшего позже выглядел
-- бы пустым, хотя сервер помнит всё. Переиспользуем тот же ремоут, просто пошлем его по разу
-- на каждый уже открытый ключ — новый RemoteEvent для этого не нужен.
local RecipeLearnedRemote = Remotes:WaitForChild("RecipeLearned")

Players.PlayerAdded:Connect(function(player)
	task.wait(1)
	Remotes.InventoryChanged:FireClient(player, Inventory.GetAll())
	for resultKey in Crafting.GetKnown() do
		RecipeLearnedRemote:FireClient(player, resultKey)
	end
end)
