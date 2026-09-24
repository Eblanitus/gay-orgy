-- Апгрейдер производителя (alchemy_td_location_v1.6.md, «Производитель: режимы работы»).
-- Игрок вкладывает свой элемент и двигает его вперёд по собственной ветке.
--
-- Здесь только проверки и розыгрыш. Ветки, шанс и правило неудачи живут в
-- ReplicatedStorage.UpgraderConfig — по ним же магазин рисует проценты.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage:WaitForChild("UpgraderConfig"))
local Elements = require(ReplicatedStorage:WaitForChild("Elements"))
local Inventory = require(ServerScriptService:WaitForChild("Inventory"))

local Upgrader = {}
Upgrader.Config = Config

local rng = Random.new()

-- Сам бросок отделён от кассы: по нему же гоняется проверка частот, и проверять
-- приходится ровно то, что играет в забеге, а не похожую копию из теста.
function Upgrader.Roll(steps)
	return rng:NextNumber() < Config.Chance(steps)
end

-- Ключи приходят с клиента, поэтому проверяется всё: что это строки, что такие элементы
-- есть, что оба на одной спине, что цель впереди, и что вложенное вообще есть в сумке.
function Upgrader.Try(fromKey, toKey)
	if type(fromKey) ~= "string" or type(toKey) ~= "string" then
		return false, "апгрейдер: непонятный запрос"
	end
	if not Elements[fromKey] or not Elements[toKey] then
		return false, "апгрейдер: такого элемента нет"
	end

	local steps = Config.StepsBetween(fromKey, toKey)
	if not steps then
		return false, ("%s нельзя довести до %s: это не шаг вперёд по его ветке")
			:format(Elements[fromKey].name, Elements[toKey].name)
	end

	if (Inventory.Get(fromKey) or 0) < 1 then
		return false, ("нет элемента %s"):format(Elements[fromKey].name)
	end

	-- Вложенное уходит из сумки до броска: при неудаче оно сгорает (вики), при удаче
	-- на его место приходит цель. Так элемент не может оказаться в сумке дважды.
	if not Inventory.Remove(fromKey, 1) then
		return false, ("нет элемента %s"):format(Elements[fromKey].name)
	end

	-- Итог в сумку кладёт Grant — после того как стрелка остановится.
	local won = Upgrader.Roll(steps)
	return true, { won = won, steps = steps, chance = Config.Chance(steps), from = fromKey, to = toKey }
end

-- Выдача итога. Отдельно от Try: вложенное уходит сразу, а цель приходит, когда
-- попытка завершена — иначе счётчик в сумке раскрыл бы итог раньше стрелки.
function Upgrader.Grant(result)
	if result.won then
		Inventory.Add(result.to, 1)
	elseif not Config.BURN_ON_FAIL then
		Inventory.Add(result.from, 1)
	end
end

return Upgrader
