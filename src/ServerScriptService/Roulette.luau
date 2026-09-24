-- Рулетка производителя (alchemy_td_location_v1.6.md, «Производитель: режимы работы»).
-- Игрок не выбирает элемент: платит и получает случайный из четырёх базовых.
--
-- Здесь только розыгрыш и касса. Числа баланса (цена прокрутки, потолок прокруток,
-- веса элементов) живут в ReplicatedStorage.RouletteConfig — по ним же магазин рисует
-- цену на витрине.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage:WaitForChild("RouletteConfig"))
local Matter = require(ServerScriptService:WaitForChild("Matter"))
local Inventory = require(ServerScriptService:WaitForChild("Inventory"))

local Roulette = {}
Roulette.Config = Config

local rng = Random.new()

local function rollOne()
	local total = 0
	for _, weight in Config.WEIGHTS do
		total += weight
	end
	local point = rng:NextNumber() * total
	local running, last = 0, nil
	for key, weight in Config.WEIGHTS do
		running += weight
		last = key
		if point <= running then
			return key
		end
	end
	return last
end

-- Число прокруток приходит с клиента, поэтому проверяется здесь целиком: не число,
-- дробь, ноль, четвёрка подделанным запросом — всё отбивается до списания материи.
function Roulette.Spin(spins)
	if type(spins) ~= "number" or spins ~= math.floor(spins) or spins ~= spins then
		return false, "рулетка: непонятное число прокруток"
	end
	if spins < 1 or spins > Config.MAX_SPINS then
		return false, ("за раз можно крутить от 1 до %d"):format(Config.MAX_SPINS)
	end

	local price = Config.TotalCost(spins)
	if not Matter.Spend(price) then
		return false, ("не хватает материи (нужно %d, есть %d)"):format(price, Matter.Get())
	end

	-- Каждая прокрутка разыгрывается отдельно, элементы могут повториться (вики).
	-- В сумку выпавшее кладёт Grant — после того как барабаны остановятся.
	local results = {}
	for i = 1, spins do
		results[i] = rollOne()
	end
	-- Все прокрутки одинаковые — джекпот: подарок того же элемента (RouletteConfig.Jackpot).
	return true, results, Config.Jackpot(results)
end

-- Выдача выпавшего. Отдельно от Spin: материя списана сразу, а элементы приходят,
-- когда прокрутка завершена — иначе счётчик в сумке раскрыл бы итог раньше барабанов.
-- bonus — элемент джекпота из Spin, если он был: его подарок приходит вместе с выпавшим.
function Roulette.Grant(results, bonus)
	for _, key in results do
		Inventory.Add(key, 1)
	end
	if bonus then
		Inventory.Add(bonus, Config.JACKPOT_BONUS)
	end
end

return Roulette
