-- Чем элемент или жук подписан в интерфейсе: поле таблицы → человеческая подпись.
--
-- Отдельный модуль, а не копия в каждом экране: эти подписи нужны и журналу
-- (справочники), и Лаборатории (плитка покупки). Две копии одной таблицы однажды
-- разойдутся, и один и тот же Огонь окажется разным в двух окнах — то же правило
-- проекта, что и у UITheme: одна вещь — одно место.
--
-- Здесь НЕТ описаний от себя. Каждая строка — имя существующего поля из таблиц
-- ReplicatedStorage.Elements / .Enemies и его название по-русски. Пересказ механики
-- живёт в вики, цифры — в таблицах кода, а выдуманное свойство разошлось бы с тем,
-- что реально делает код, при первой же правке баланса.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Recipes = require(ReplicatedStorage:WaitForChild("Recipes"))

local EntityInfo = {}

-- Названия каст — из вики (alchemy_td_enemies_v1.1.md, раздел «Касты»).
-- Каста — не уровень силы, а роль в колонии; в таблице жуков у них только номера.
EntityInfo.CASTE_NAME = {
	[0] = "Разведчики",
	[1] = "Работяги",
	[2] = "Солдаты",
	[3] = "Особые",
}

-- Порядок значим: в строку влезает не всё, и первыми должны идти те свойства,
-- ради которых элемент вообще берут.
EntityInfo.ELEMENT_TRAITS = {
	{ field = "damageMultiplier", label = "урон" },
	{ field = "damagePerSecond", label = "урон/сек" },
	{ field = "fireRateBonus", label = "темп" },
	{ field = "slowPercent", label = "замедление" },
	{ field = "armorPierce", label = "пробитие брони" },
	{ field = "knockback", label = "отбрасывание" },
	{ field = "stun", label = "оглушение" },
	{ field = "chain", label = "цепной" },
	{ field = "explosion", label = "взрыв" },
	{ field = "killZone", label = "лужа" },
	{ field = "wet", label = "мочит" },
	{ field = "conductive", label = "проводит ток" },
	{ field = "blind", label = "ослепляет" },
	{ field = "confusion", label = "сбивает с пути" },
	{ field = "pull", label = "притягивает" },
	{ field = "toss", label = "подбрасывает" },
	{ field = "healer", label = "чинит" },
	{ field = "terrain", label = "меняет рельеф" },
	{ field = "amplifier", label = "усилитель" },
	{ field = "primer", label = "грунтовка" },
	{ field = "contagion", label = "заразный" },
	{ field = "mark", label = "метка" },
	{ field = "breakthrough", label = "пробой" },
	{ field = "killBarrier", label = "барьер" },
}

-- Признаки жука, которые видны игроку в бою.
EntityInfo.ENEMY_TRAITS = {
	{ field = "flying", label = "летает" },
	{ field = "armor", label = "броня" },
	{ field = "shield", label = "щит" },
	{ field = "chitin", label = "хитин" },
	{ field = "regen", label = "регенерация" },
	{ field = "heals", label = "лечит своих" },
	{ field = "spits", label = "плюётся" },
	{ field = "digs", label = "копает" },
	{ field = "burrows", label = "уходит под землю" },
	{ field = "builds", label = "строит" },
	{ field = "carries", label = "носит других" },
	{ field = "cocoons", label = "плетёт коконы" },
	{ field = "lays", label = "откладывает" },
	{ field = "hatches", label = "вылупляется" },
	{ field = "evolves", label = "эволюционирует" },
	{ field = "mimics", label = "маскируется" },
	{ field = "shadow", label = "тень" },
	{ field = "commands", label = "командует" },
	{ field = "directs", label = "направляет" },
	{ field = "absorbs", label = "поглощает урон" },
	{ field = "scavenges", label = "подбирает" },
	{ field = "rams", label = "таранит" },
	{ field = "charge", label = "разгон" },
	{ field = "climbHeight", label = "лазает" },
	{ field = "panic", label = "паникует" },
}

-- Сколько признаков брать по умолчанию — дальше строка всё равно обрезается
-- краем ячейки, и собирать все двадцать значит тратить время на невидимое.
EntityInfo.MAX_TRAITS = 4

function EntityInfo.Traits(entry, spec, limit)
	limit = limit or EntityInfo.MAX_TRAITS
	local found = {}
	if type(entry) ~= "table" then
		return found
	end
	for _, trait in spec do
		local value = entry[trait.field]
		-- Ноль и false — это «свойства нет», а не «свойство со значением ноль»: в таблицах
		-- игры неиспользуемое поле просто не выписывают, но встречается и явный ноль.
		if value ~= nil and value ~= false and value ~= 0 then
			table.insert(found, trait.label)
			if #found >= limit then
				break
			end
		end
	end
	return found
end

function EntityInfo.ElementTraits(element, limit)
	return EntityInfo.Traits(element, EntityInfo.ELEMENT_TRAITS, limit)
end

function EntityInfo.EnemyTraits(enemy, limit)
	return EntityInfo.Traits(enemy, EntityInfo.ENEMY_TRAITS, limit)
end

-- Число без хвоста из нулей: скорость бывает дробной, HP — всегда целое,
-- а «8.0» рядом с «120» в одной строке читается как опечатка.
function EntityInfo.Number(value)
	if type(value) ~= "number" then
		return "-"
	end
	if value == math.floor(value) then
		return tostring(math.floor(value))
	end
	return ("%.1f"):format(value)
end

-- Каким рецептом получается элемент. Recipes.List лежит как «пара → результат»,
-- а справочнику нужен обратный вопрос — «из чего это». Считается один раз на загрузке.
local recipeOf = {}
for _, recipe in Recipes.List do
	if not recipeOf[recipe.result] then
		recipeOf[recipe.result] = recipe
	end
end

function EntityInfo.RecipeOf(elementKey)
	return recipeOf[elementKey]
end

return EntityInfo
