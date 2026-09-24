-- Скрещивание элементов. Само дерево — в Recipes, счётчики — в Inventory; здесь только
-- правила обмена и память об открытых рецептах.
--
-- Неверная пара ничего не сжигает. Фраза ТЗ «ошибка стоит двух элементов» прочтена как
-- «скрестил не то, что хотел»: ингредиенты ушли, а результат не тот. Сжигать ещё и за пару,
-- которой в дереве нет, было бы наказанием за исследование дерева, а его игра как раз просит.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Elements = require(ReplicatedStorage:WaitForChild("Elements"))
local Recipes = require(ReplicatedStorage:WaitForChild("Recipes"))
local Inventory = require(ServerScriptService:WaitForChild("Inventory"))
local PlayerData = require(ServerScriptService:WaitForChild("PlayerData"))
local ProfileStats = require(ServerScriptService:WaitForChild("ProfileStats"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RecipeLearnedRemote = Remotes:WaitForChild("RecipeLearned")

local Crafting = {}

-- Открытые рецепты: ключ элемента-результата -> true. По дизайн-доку знание живёт
-- «навсегда», поэтому рестарт забега его не сбрасывает, в отличие от инвентаря.
-- Между сессиями сервера хранится в профиле игрока (PlayerData) — known остаётся
-- быстрым кэшем на чтение, профиль остаётся источником правды на диске.
local known = {}

PlayerData.Loaded.Event:Connect(function(_player, data)
	for resultKey in data.recipes do
		known[resultKey] = true
	end
end)

-- Пишет новое открытие во все загруженные профили на сервере. Серверов с двумя
-- игроками этот проект не предполагает (см. Matter), но так корректно и для них.
local function persistLearned(resultKey)
	for _, player in Players:GetPlayers() do
		local data = PlayerData.Get(player)
		if data then
			data.recipes[resultKey] = true
		end
	end
end

function Crafting.IsKnown(resultKey)
	return known[resultKey] == true
end

function Crafting.GetKnown()
	local copy = {}
	for resultKey in known do
		copy[resultKey] = true
	end
	return copy
end

-- Разом помечает известным весь справочник рецептов — для промокода-читa, не для обычной
-- игры. known общий на весь сервер (как и остальное состояние крафта), поэтому рассылаем
-- всем тем же ремоутом и тем же паттерном, что и обычное первое открытие в Craft.
function Crafting.RevealAll()
	local revealed = {}
	for _, recipe in Recipes.List do
		if not known[recipe.result] then
			known[recipe.result] = true
			table.insert(revealed, recipe.result)
		end
	end

	for _, resultKey in revealed do
		persistLearned(resultKey)
		RecipeLearnedRemote:FireAllClients(resultKey)
	end

	return revealed
end

-- Скрещивает два элемента. Возвращает (true, ключ результата, впервые ли) либо (false, причина).
function Crafting.Craft(a, b)
	if not Elements[a] or not Elements[b] then
		return false, "нет такого элемента"
	end

	-- Одинаковые ингредиенты — это две штуки одного элемента, а не одна дважды засчитанная.
	local needed = {}
	needed[a] = (needed[a] or 0) + 1
	needed[b] = (needed[b] or 0) + 1

	for elementKey, amount in needed do
		if Inventory.Get(elementKey) < amount then
			return false, ("не хватает: %s нужно %d, есть %d")
				:format(Elements[elementKey].name, amount, Inventory.Get(elementKey))
		end
	end

	local resultKey = Recipes.Find(a, b)
	if not resultKey then
		return false, ("%s и %s не смешиваются"):format(Elements[a].name, Elements[b].name)
	end

	for elementKey, amount in needed do
		Inventory.Remove(elementKey, amount)
	end
	Inventory.Add(resultKey, 1)
	ProfileStats.Crafted(resultKey)

	local firstTime = not known[resultKey]
	known[resultKey] = true

	print(("[Крафт] %s + %s = %s%s"):format(
		Elements[a].name, Elements[b].name, Elements[resultKey].name,
		firstTime and " (рецепт открыт)" or ""))

	if firstTime then
		persistLearned(resultKey)
		RecipeLearnedRemote:FireAllClients(resultKey)
	end

	return true, resultKey, firstTime
end

return Crafting
