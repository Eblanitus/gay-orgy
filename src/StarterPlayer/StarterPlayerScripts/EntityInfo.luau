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
local Elements = require(ReplicatedStorage:WaitForChild("Elements"))

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
	{ field = "fireRateRamp", label = "разгон" },
	{ field = "slowPercent", label = "замедление" },
	{ field = "armorPierce", label = "пробитие брони" },
	{ field = "knockback", label = "отбрасывание" },
	{ field = "stun", label = "оглушение" },
	{ field = "chain", label = "цепной" },
	{ field = "explosion", label = "взрыв" },
	{ field = "killZone", label = "оставляет зону" },
	{ field = "wet", label = "мочит" },
	{ field = "conductive", label = "проводит ток" },
	{ field = "blind", label = "ослепляет" },
	{ field = "confusion", label = "сбивает с пути" },
	{ field = "pull", label = "притягивает" },
	{ field = "toss", label = "подбрасывает" },
	{ field = "healer", label = "чинит" },
	{ field = "terrain", label = "меняет рельеф" },
	{ field = "amplifier", label = "усилитель" },
	{ field = "primer", label = "метка взрыва" },
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

-- ============ Характеристики элемента словами ============
--
-- Справочник показывает не числа, а оценку словом — «медленная», «быстрая», «безумно
-- быстрая» (просьба автора, как в Brawl Stars). Числа живут в Elements; здесь только
-- пороги, по которым число становится словом. Порог — верхняя граница ступени:
-- значение до неё включительно получает это слово.

-- Во сколько раз темп элемента отличается от темпа турели (1 + fireRateBonus). У разгонных
-- (fireRateRamp) — стартовый темп: разгон — способность, он идёт в «особенности».
EntityInfo.RATE_WORDS = {
	{ upTo = 0.3, word = "безумно медленная" },
	{ upTo = 0.6, word = "очень медленная" },
	{ upTo = 0.85, word = "медленная" },
	{ upTo = 1.15, word = "нормальная" },
	{ upTo = 1.6, word = "быстрая" },
	{ upTo = 2.5, word = "очень быстрая" },
	{ upTo = math.huge, word = "безумно быстрая" },
}

-- Множитель урона снаряда к урону его цены (damageMultiplier; нет поля — 1).
EntityInfo.DAMAGE_WORDS = {
	{ upTo = 0, word = "нет" },
	{ upTo = 0.45, word = "очень слабый" },
	{ upTo = 0.8, word = "слабый" },
	{ upTo = 1.2, word = "нормальный" },
	{ upTo = 2, word = "сильный" },
	{ upTo = 3, word = "очень сильный" },
	{ upTo = math.huge, word = "огромный" },
}

-- Урон по времени, в секунду (damagePerSecond).
EntityInfo.DOT_WORDS = {
	{ upTo = 5, word = "слабый" },
	{ upTo = 10, word = "нормальный" },
	{ upTo = 15, word = "сильный" },
	{ upTo = math.huge, word = "очень сильный" },
}

-- Доля брони, которую элемент игнорирует (armorPierce).
EntityInfo.PIERCE_WORDS = {
	{ upTo = 0.55, word = "частичное" },
	{ upTo = 0.99, word = "почти полное" },
	{ upTo = math.huge, word = "неограниченное" },
}

-- Отбрасывание и притяжение — на сколько studs (knockback.distance, pull.distance).
EntityInfo.PUSH_WORDS = {
	{ upTo = 1.75, word = "слабое" },
	{ upTo = 3, word = "среднее" },
	{ upTo = 5, word = "сильное" },
	{ upTo = math.huge, word = "очень сильное" },
}

-- Замедление хода — доля (slowPercent).
EntityInfo.SLOW_WORDS = {
	{ upTo = 0.3, word = "слабое" },
	{ upTo = 0.55, word = "среднее" },
	{ upTo = 0.75, word = "сильное" },
	{ upTo = math.huge, word = "очень сильное" },
}

-- Оглушение — секунды (stun.duration).
EntityInfo.STUN_WORDS = {
	{ upTo = 0.35, word = "короткое" },
	{ upTo = math.huge, word = "долгое" },
}

function EntityInfo.Word(scale, value)
	for _, step in scale do
		if value <= step.upTo then
			return step.word
		end
	end
	return scale[#scale].word
end

-- Свойства, у которых теперь своя строка в справочнике: в перечне «особенностей»
-- они бы повторились.
EntityInfo.RATED_FIELDS = {
	fireRateBonus = true, damageMultiplier = true, damagePerSecond = true,
	slowPercent = true, armorPierce = true, knockback = true, pull = true, stun = true,
}

-- Сколько материи стоит элемент: цена покупки каждого базового в его составе (поле cost),
-- по всему дереву рецептов; пара одинаковых — дважды. Та же рекурсия, что у урона
-- (Effects.Basics): чем дороже элемент, тем тяжелее его снаряд.
local matterOf = {}
local function countMatter(key, seen)
	if matterOf[key] then
		return matterOf[key]
	end
	local recipe = recipeOf[key]
	if not recipe or seen[key] then
		return (Elements[key] and Elements[key].cost) or 0
	end
	seen[key] = true
	local total = countMatter(recipe.a, seen) + countMatter(recipe.b, seen)
	matterOf[key] = total
	return total
end

function EntityInfo.MatterCost(elementKey)
	return countMatter(elementKey, {})
end

local function plural(n, one, few, many)
	local d10, d100 = n % 10, n % 100
	if d10 == 1 and d100 ~= 11 then
		return one
	elseif d10 >= 2 and d10 <= 4 and (d100 < 12 or d100 > 14) then
		return few
	end
	return many
end

-- Строки характеристик элемента: { label, value }. Скорострельность и урон — всегда,
-- остальное — только если у элемента это есть.
function EntityInfo.ElementStats(elementKey, element)
	local rows = {}
	local function add(label, value)
		table.insert(rows, { label = label, value = value })
	end

	local matter = EntityInfo.MatterCost(elementKey)
	add("стоимость", ("%d %s"):format(matter, plural(matter, "материя", "материи", "материи")))

	local ramp = element.fireRateRamp
	add("скорострельность", EntityInfo.Word(EntityInfo.RATE_WORDS,
		ramp and (ramp.base or 1) or (1 + (element.fireRateBonus or 0))))

	if element.damageRandom then
		add("урон снаряда", ("случайный: от «%s» до «%s»"):format(
			EntityInfo.Word(EntityInfo.DAMAGE_WORDS, element.damageRandom.min),
			EntityInfo.Word(EntityInfo.DAMAGE_WORDS, element.damageRandom.max)
		))
	elseif element.damageSpeedScale then
		add("урон снаряда", ("по скорости цели: от «%s» до «%s»"):format(
			EntityInfo.Word(EntityInfo.DAMAGE_WORDS, element.damageSpeedScale.min),
			EntityInfo.Word(EntityInfo.DAMAGE_WORDS, element.damageSpeedScale.max)
		))
	elseif element.damageRamp then
		add("урон снаряда", "растёт с каждым попаданием подряд")
	else
		add("урон снаряда", EntityInfo.Word(EntityInfo.DAMAGE_WORDS, element.damageMultiplier or 1))
	end

	if element.damagePerSecond then
		add("урон по времени", EntityInfo.Word(EntityInfo.DOT_WORDS, element.damagePerSecond))
	end
	if element.armorPierce then
		add("пробитие брони", EntityInfo.Word(EntityInfo.PIERCE_WORDS, element.armorPierce))
	end
	if element.knockback then
		local word = EntityInfo.Word(EntityInfo.PUSH_WORDS, element.knockback.distance)
		add("отбрасывание", element.knockback.radial and (word .. ", по площади") or word)
	end
	if element.pull then
		add("притяжение", EntityInfo.Word(EntityInfo.PUSH_WORDS, element.pull.distance))
	end
	if element.slowPercent and element.slowPercent > 0 then
		add("замедление", EntityInfo.Word(EntityInfo.SLOW_WORDS, element.slowPercent))
	end
	if element.stun then
		add("оглушение", EntityInfo.Word(EntityInfo.STUN_WORDS, element.stun.duration))
	end
	return rows
end

-- Остальные свойства элемента — те, у которых нет своей строки (взрыв, цепь, метки…).
function EntityInfo.ElementFeatures(element)
	local found = {}
	for _, trait in EntityInfo.ELEMENT_TRAITS do
		local value = element[trait.field]
		if not EntityInfo.RATED_FIELDS[trait.field] and value ~= nil and value ~= false and value ~= 0 then
			table.insert(found, trait.label)
		end
	end
	return found
end

return EntityInfo
