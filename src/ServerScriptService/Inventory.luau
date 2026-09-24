-- Инвентарь элементов: счётчик на каждый ключ из Elements. Один игрок на сервере (по ТЗ),
-- поэтому просто общая таблица, как и у материи.
--
-- По дизайн-доку элементы живут ровно один забег: «знание сохраняется, имущество — нет».
-- Поэтому Reset зовётся из WaveRunner вместе со сбросом материи, а открытые рецепты хранятся
-- отдельно (см. Crafting) и рестартом не сбрасываются.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Elements = require(ReplicatedStorage:WaitForChild("Elements"))
local Matter = require(ServerScriptService:WaitForChild("Matter"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local InventoryChangedRemote = Remotes:WaitForChild("InventoryChanged")

local Inventory = {}

local counts = {}
-- Номер забега: растёт при каждом сбросе. Рулетка и апгрейдер выдают элемент
-- после анимации, и если за эти секунды забег сменился, выдача старому забегу
-- не должна попасть в сумку нового.
local epoch = 0

local function broadcast()
	InventoryChangedRemote:FireAllClients(counts)
end

function Inventory.Get(elementKey)
	return counts[elementKey] or 0
end

-- Отдаёт копию: иначе вызывающий мог бы править счётчики мимо Add/Remove и мимо рассылки.
function Inventory.GetAll()
	local copy = {}
	for elementKey, count in counts do
		copy[elementKey] = count
	end
	return copy
end

function Inventory.Add(elementKey, amount)
	amount = amount or 1
	assert(Elements[elementKey], ("[Инвентарь] нет такого элемента: %s"):format(tostring(elementKey)))

	counts[elementKey] = (counts[elementKey] or 0) + amount
	broadcast()
	print(("[Инвентарь] +%d %s, стало %d")
		:format(amount, Elements[elementKey].name, counts[elementKey]))
end

-- Списывает, если хватает; иначе ничего не делает и возвращает false.
function Inventory.Remove(elementKey, amount)
	amount = amount or 1
	local have = counts[elementKey] or 0
	if have < amount then
		return false
	end

	counts[elementKey] = have - amount
	if counts[elementKey] == 0 then
		counts[elementKey] = nil
	end
	broadcast()
	return true
end

-- Покупает элемент за материю. Продаются только те, у кого в Elements есть cost —
-- сейчас это четыре базовых. Всё остальное только скрещиванием.
function Inventory.Buy(elementKey)
	local data = Elements[elementKey]
	if not data then
		return false, "нет такого элемента"
	end
	if not data.cost then
		return false, ("%s не продаётся — его надо скрестить"):format(data.name)
	end
	if not Matter.Spend(data.cost) then
		return false, ("не хватает материи (нужно %d, есть %d)"):format(data.cost, Matter.Get())
	end

	Inventory.Add(elementKey, 1)
	return true
end

-- Новый забег — пустой инвентарь.
function Inventory.Reset()
	counts = {}
	epoch += 1
	broadcast()
end

function Inventory.Epoch()
	return epoch
end

return Inventory
