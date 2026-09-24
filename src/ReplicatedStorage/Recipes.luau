-- Дерево рецептов. Структура и обоснование своих рецептов — в alchemy_td_recipes_v3.md.
--
-- Дерево v3: 71 элемент (4 базовых + 67 производных) и 67 рецептов. В итоговой строке
-- документа стоит «72 и 68», но перечисленные там таблицы дают ровно 67 строк
-- (10 + 18 + 27 + 12), и именно они названы единственным источником правды — списки
-- перенесены строка в строку, а не добиты до числа из итоговой строки.
--
-- Четыре «спины» — чистокровные ветки по одному паттерну: тир 1 = тир0 + тир0,
-- тир 2 = тир0 + тир1, тир 3 = тир0 + тир2, тир 4 = тир3 + тир3. Из-за них в v3 переехала
-- земляная ветка: Земля + Земля теперь Грунт, Суша стала тиром 2, Континент — тиром 3.
--
-- Ключ — два ключа элементов, отсортированные и склеенные. Порядок ингредиентов поэтому
-- не важен сам собой: Огонь + Вода и Вода + Огонь дают один ключ, а не две записи.
-- Поиск — одно обращение к таблице; перебор списка пар запрещён ТЗ — дерево будет расти.
--
-- Один рецепт на один элемент, множественных путей нет — решение из дизайн-дока.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Elements = require(ReplicatedStorage:WaitForChild("Elements"))

local Recipes = {}

local function key(a, b)
	if a > b then
		a, b = b, a
	end
	return a .. "+" .. b
end

Recipes.Results = {
	-- Шаг 1 — все десять пар базовых, канон целиком кроме Грунта
	[key("Fire", "Fire")] = "Energy",
	[key("Water", "Water")] = "Puddle",
	[key("Earth", "Earth")] = "Soil", -- своё (v3): была Суша, теперь Грунт
	[key("Air", "Air")] = "Pressure",
	[key("Fire", "Water")] = "Steam",
	[key("Fire", "Earth")] = "Lava",
	[key("Fire", "Air")] = "Smoke",
	[key("Water", "Earth")] = "Mud",
	[key("Water", "Air")] = "Mist",
	[key("Earth", "Air")] = "Dust",

	-- Шаг 2
	[key("Fire", "Energy")] = "Flare", -- новый: огненная спина
	[key("Earth", "Soil")] = "Land", -- своё (v3): было Суша + Суша
	[key("Water", "Puddle")] = "Pond",
	[key("Air", "Pressure")] = "Wind",
	[key("Earth", "Pressure")] = "Stone",
	[key("Earth", "Energy")] = "Earthquake",
	[key("Earth", "Lava")] = "Volcano",
	[key("Earth", "Steam")] = "Geyser",
	[key("Air", "Energy")] = "Heat",
	[key("Water", "Lava")] = "Obsidian",
	[key("Water", "Pressure")] = "Cold", -- своё: канонный холод идёт через жизнь
	[key("Water", "Smoke")] = "Acid", -- своё: канонной кислоты нет
	[key("Fire", "Dust")] = "Gunpowder",
	[key("Fire", "Mud")] = "Brick",
	[key("Steam", "Air")] = "Cloud",
	[key("Smoke", "Mist")] = "Smog", -- новый
	[key("Puddle", "Mud")] = "Swamp", -- новый
	[key("Soil", "Water")] = "Plant", -- новый

	-- Шаг 3
	[key("Fire", "Flare")] = "Lightning", -- новый
	[key("Earth", "Land")] = "Continent", -- своё (v3): было Суша + Суша
	[key("Water", "Pond")] = "Ocean", -- новый
	[key("Air", "Wind")] = "Hurricane", -- новый
	[key("Plant", "Earth")] = "Tree", -- новый
	[key("Plant", "Air")] = "Oxygen", -- своё (v3): было Растение + Энергия
	[key("Fire", "Plant")] = "Ash", -- новый
	[key("Tree", "Fire")] = "Coal", -- новый
	[key("Swamp", "Energy")] = "Life",
	[key("Acid", "Plant")] = "Poison", -- новый
	[key("Metal", "Air")] = "Rust",
	[key("Cloud", "Water")] = "Rain",
	[key("Cloud", "Cold")] = "Snow",
	[key("Mist", "Cold")] = "Frost",
	[key("Smog", "Acid")] = "AcidRain", -- новый
	[key("Heat", "Land")] = "Drought", -- новый
	[key("Ice", "Wind")] = "Blizzard",
	[key("Fire", "Stone")] = "Metal",
	[key("Air", "Stone")] = "Sand",
	[key("Fire", "Gunpowder")] = "Explosion",
	[key("Pressure", "Heat")] = "Plasma",
	[key("Wind", "Steam")] = "Tornado", -- своё (v3): было Ветер + Ветер
	[key("Volcano", "Pressure")] = "Eruption",
	[key("Water", "Cold")] = "Ice",
	[key("Mud", "Stone")] = "Clay",
	[key("Earth", "Earthquake")] = "Mountain",
	[key("Brick", "Brick")] = "BrickWall",

	-- Шаг 4
	[key("Lightning", "Lightning")] = "Star", -- новый: вершина огненной спины (из Молний, а не Вспышек — ошибка вики)
	[key("Continent", "Continent")] = "Lithosphere", -- новый: вершина земляной
	[key("Ocean", "Ocean")] = "Hydrosphere", -- новый: вершина водяной
	[key("Hurricane", "Hurricane")] = "Atmosphere", -- новый: вершина воздушной
	[key("Fire", "Sand")] = "Glass",
	[key("Energy", "Metal")] = "Electricity", -- своё: канонное идёт через космос
	[key("Eruption", "Ocean")] = "Island", -- новый
	[key("Explosion", "Air")] = "Sound", -- новый
	[key("Ash", "Water")] = "Soap", -- новый
	[key("Coal", "Coal")] = "Diamond", -- новый
	[key("Coal", "Metal")] = "Steel", -- новый
	[key("Plasma", "Energy")] = "Antimatter", -- новый
}

-- Список всех рецептов в виде { a, b, result } — для справочника. Собирается один
-- раз при загрузке, чтобы справочник не разбирал ключи строками на каждое открытие.
Recipes.List = {}
for pair, result in Recipes.Results do
	local a, b = pair:match("^(.-)%+(.+)$")
	table.insert(Recipes.List, { a = a, b = b, result = result })
end

table.sort(Recipes.List, function(x, y)
	local tx = Elements[x.result].tier or 0
	local ty = Elements[y.result].tier or 0
	if tx ~= ty then
		return tx < ty
	end
	return Elements[x.result].name < Elements[y.result].name
end)

-- Проверка при загрузке: шестьдесят семь строк переписаны руками из документа, и опечатка
-- в ключе иначе всплыла бы только тогда, когда игрок не смог бы что-то скрестить.
for _, recipe in Recipes.List do
	assert(Elements[recipe.a], ("[Recipes] нет такого элемента: %s"):format(tostring(recipe.a)))
	assert(Elements[recipe.b], ("[Recipes] нет такого элемента: %s"):format(tostring(recipe.b)))
	assert(Elements[recipe.result], ("[Recipes] нет такого элемента: %s"):format(tostring(recipe.result)))
end

-- Возвращает ключ элемента-результата либо nil, если такой пары в дереве нет.
function Recipes.Find(a, b)
	return Recipes.Results[key(a, b)]
end

return Recipes
