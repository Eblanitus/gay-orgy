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

-- ДПС снаряда относительно урона его цены: damageMultiplier (нет поля — 1) × темп стрельбы.
EntityInfo.DAMAGE_WORDS = {
	{ upTo = 0, word = "нет" },
	{ upTo = 0.45, word = "очень слабый" },
	{ upTo = 0.8, word = "слабый" },
	{ upTo = 1.2, word = "нормальный" },
	{ upTo = 2, word = "сильный" },
	{ upTo = 3, word = "очень сильный" },
	{ upTo = 5, word = "огромный" },
	-- Выше — только снаряд с эффектом на полных стеках: у горения и кислоты урон копится.
	{ upTo = 10, word = "колоссальный" },
	{ upTo = math.huge, word = "запредельный" },
}

-- Доля брони, которую элемент игнорирует (armorPierce).
EntityInfo.PIERCE_WORDS = {
	{ upTo = 0.55, word = "частичное" },
	{ upTo = 0.99, word = "почти полное" },
	{ upTo = math.huge, word = "максимальное" },
}

-- Отбрасывание и притяжение — на сколько studs (knockback.distance, pull.distance).
EntityInfo.PUSH_WORDS = {
	{ upTo = 1.75, word = "слабое" },
	{ upTo = 3, word = "среднее" },
	{ upTo = 5, word = "сильное" },
	{ upTo = math.huge, word = "очень сильное" },
}

-- Сила притяжения — те же пороги, что у отбрасывания, но «сила» женского рода.
EntityInfo.PULL_FORCE_WORDS = {
	{ upTo = 1.75, word = "слабая" },
	{ upTo = 3, word = "средняя" },
	{ upTo = 5, word = "сильная" },
	{ upTo = math.huge, word = "очень сильная" },
}

-- Частота притяжения — сколько раз элемент тянет одного и того же жука (pull.shots).
EntityInfo.PULL_WORDS = {
	{ upTo = 1, word = "однократная" },
	{ upTo = 3, word = "редкая" },
	{ upTo = 4, word = "частая" },
	{ upTo = math.huge, word = "очень частая" },
}

-- Замедление хода — доля (slowPercent).
EntityInfo.SLOW_WORDS = {
	{ upTo = 0.3, word = "слабое" },
	{ upTo = 0.55, word = "среднее" },
	{ upTo = 0.75, word = "сильное" },
	{ upTo = math.huge, word = "очень сильное" },
}

-- Длительность оглушения — секунды (stun.duration).
EntityInfo.STUN_WORDS = {
	{ upTo = 0.15, word = "мгновенная" },
	{ upTo = 0.35, word = "короткая" },
	{ upTo = math.huge, word = "долгая" },
}

-- Длительность замедления и урона по времени — секунды (slowDuration, duration).
EntityInfo.DURATION_WORDS = {
	{ upTo = 2, word = "короткая" },
	{ upTo = 4, word = "средняя" },
	{ upTo = 6, word = "долгая" },
	{ upTo = 1e9, word = "очень долгая" },
	{ upTo = math.huge, word = "до смерти жука" },
}

function EntityInfo.Word(scale, value)
	for _, step in scale do
		if value <= step.upTo then
			return step.word
		end
	end
	return scale[#scale].word
end

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

-- Строки характеристик элемента: { label, value }. Скорострельность и ДПС снаряда — всегда,
-- остальное — только если у элемента это есть. ДПС, а не урон попадания (просьба автора):
-- так видно, быстро ли элемент наносит урон, а не только сколько за раз.
-- Строки, что есть у каждого элемента. В карточке они идут над разделителем «эффект»,
-- всё остальное — под ним, как уникальное.
EntityInfo.STANDARD_STATS = { ["стоимость"] = true, ["скорострельность"] = true, ["дпс снаряда"] = true }

function EntityInfo.ElementStats(elementKey, element)
	local rows = {}
	local function add(label, value)
		table.insert(rows, { label = label, value = value })
	end

	local matter = EntityInfo.MatterCost(elementKey)
	add("стоимость", ("%d %s"):format(matter, plural(matter, "материя", "материи", "материи")))

	if EntityInfo.MYSTERY[elementKey] then
		add("скорострельность", "???")
		add("дпс снаряда", "???")
		return rows
	end

	local ramp = element.fireRateRamp
	local rate = ramp and (ramp.base or 1) or (1 + (element.fireRateBonus or 0))
	add("скорострельность", EntityInfo.Word(EntityInfo.RATE_WORDS, rate))

	local function dps(multiplier)
		return EntityInfo.Word(EntityInfo.DAMAGE_WORDS, multiplier * rate)
	end
	-- Случайный, по скорости и растущий урон — по среднему: как он меняется, пишет строка
	-- «особенности», здесь не дублируем.
	local multiplier = element.damageMultiplier or 1
	if element.damageRandom then
		multiplier = (element.damageRandom.min + element.damageRandom.max) / 2
	elseif element.damageSpeedScale then
		multiplier = (element.damageSpeedScale.min + element.damageSpeedScale.max) / 2
	elseif element.damageRamp then
		multiplier *= 1 + element.damageRamp.step * element.damageRamp.hits / 2
	end
	add("дпс снаряда", dps(multiplier))

	-- Снаряд и эффект одной строкой (просьба автора: игрок сам их не сложит). Урон эффекта
	-- переводится в доли урона снаряда: снаряд бьёт на Towers.Ballista.damage (5) за каждый
	-- базовый элемент в составе. Стеки копятся, пока старый не истёк: при частой стрельбе
	-- на жуке висит duration × rate стеков, но не больше maxStacks.
	if element.damagePerSecond then
		local basics = math.max(1, matter / 10)
		local stacks = math.clamp((element.duration or 1) * rate, 1, element.maxStacks or 1)
		add("дпс снаряда с эффектом", dps(multiplier + element.damagePerSecond * stacks / (5 * basics * rate)))
		if element.duration then
			add("длительность эффекта", EntityInfo.Word(EntityInfo.DURATION_WORDS, element.duration))
		end
	end
	-- Дым и Смог: удар раз в несколько попаданий подряд — в ДПС он входит своей долей.
	local burst = element.breakthrough
	if burst then
		local basics = math.max(1, matter / 10)
		add("дпс снаряда с эффектом", dps(multiplier + burst.damage / burst.hits / (5 * basics)))
		add("удар каждые", ("%d %s"):format(burst.hits, plural(burst.hits, "попадание", "попадания", "попаданий")))
		if burst.zone then
			add("длительность зоны", EntityInfo.Word(EntityInfo.DURATION_WORDS, burst.zone.duration))
		end
	end
	-- Кислота не пробивает броню попаданием, а разъедает её эффектом, пока не снимет совсем —
	-- «неограниченное» (у Кислотного дождя — через кислотную зону); «максимальное» — сразу
	-- и полностью, как у Алмаза.
	local corrodes = (element.debuff and element.debuff.armorShred)
		or (element.killZone and element.killZone.spreadElement == "Acid")
	if corrodes then
		add("пробитие брони", "неограниченное")
	elseif element.armorPierce then
		add("пробитие брони", EntityInfo.Word(EntityInfo.PIERCE_WORDS, element.armorPierce))
	end
	if element.knockback then
		local word = EntityInfo.Word(EntityInfo.PUSH_WORDS, element.knockback.distance)
		add("отбрасывание", element.knockback.radial and (word .. ", по площади") or word)
	end
	if element.pull then
		add("сила притяжения", EntityInfo.Word(EntityInfo.PULL_FORCE_WORDS, element.pull.distance))
		add("частота притяжения", EntityInfo.Word(EntityInfo.PULL_WORDS, element.pull.shots or 1))
	end
	if element.slowPercent and element.slowPercent > 0 then
		add("замедление", EntityInfo.Word(EntityInfo.SLOW_WORDS, element.slowPercent))
		if element.slowDuration then
			add("длительность замедления", EntityInfo.Word(EntityInfo.DURATION_WORDS, element.slowDuration))
		end
	end
	if element.stun then
		-- Название — то же, что в строке «эффект»: у Вспышки ослепление, у Льда заморозка.
		local name = elementKey == "Ice" and "заморозки"
			or (element.stun.duration <= 0.1 and "ослепления" or "оглушения")
		add("длительность " .. name, EntityInfo.Word(EntityInfo.STUN_WORDS, element.stun.duration))
	end
	return rows
end

-- Две строки карточки под характеристиками (задача #250):
-- «особенности» — как стреляет сама турель (разгон, урон от скорости цели, накопление);
-- «эффект» — что остаётся на жуке или на карте (цепь, мокрость, метки, зоны при смерти).
-- Свойства со своей строкой характеристик (урон, темп, замедление, пробитие, отбрасывание,
-- притяжение, оглушение) здесь не повторяются. Порядок значим: главное — первым.
-- label — строка или функция(значение, элемент, ключ) → строка или nil (не показывать).
EntityInfo.ELEMENT_FEATURES = {
	{ field = "fireRateRamp", label = function(ramp)
		return ramp.exponent and "нелинейный разгон" or "разгон"
	end },
	{ field = "damageSpeedScale", label = "сильнее по быстрым" },
	{ field = "damageRamp", label = "набирает урон" },
	{ field = "damageRandom", label = "случайный урон" },
	{ field = "breakthrough", label = "накопительный удар" },
	{ field = "armorPierce", label = "бронепробитие" },
	{ field = "knockback", label = "отталкивающий" },
	{ field = "healer", label = "чинит постройки" },
}

-- Зона, которую элемент оставляет на месте смерти жука, — своим именем.
EntityInfo.ZONE_NAMES = {
	Earthquake = "зона землетрясения",
	AcidRain = "кислотная зона",
	Blizzard = "зона метели",
	Coal = "зона пепла",
	Drought = "зона засухи",
	Hurricane = "зона урагана",
	Hydrosphere = "потоп на всю карту",
	Rain = "дождевая туча",
	Snow = "зона снежной тучи",
	Star = "рождение звезды",
}

-- Горение без поля chars: по вики их урон по времени — тоже Горение.
local BURNS = { Lightning = true, Coal = true, Star = true, Island = true }

local MARK_NAMES = { soil = "метка грунта", ash = "метка пепла", rust = "ржавчина" }

-- *так* — выделение цветом: ReferenceDetail заменяет звёздочки на тег <font>.
EntityInfo.ELEMENT_EFFECTS = {
	-- chars — горящий снаряд; у Лавы и Вулкана это Плавление (conductive), не Горение.
	{ field = "damageType", label = function(kind, element, key)
		if kind == "overtime" and ((element.chars and not element.conductive) or BURNS[key]) then
			return "горение"
		end
		return nil
	end },
	{ field = "conductive", label = "плавление" },
	{ field = "scald", label = "ошпаривание" },
	{ field = "slowSpeedScale", label = "замедляет быстрых" },
	-- Пар: замедление и горение одним эффектом — это и есть Ошпаривание.
	{ field = "name", label = function(_, _, key)
		return key == "Steam" and "ошпаривание" or nil
	end },
	{ field = "chain", label = function(chain)
		return chain.requiresWet and "цепь *по мокрым*" or "цепь"
	end },
	-- Микро-стан Вспышки по вики — ослепление, у Льда — заморозка.
	{ field = "stun", label = function(stun, _, key)
		if key == "Ice" then
			return "заморозка"
		end
		return stun.duration <= 0.1 and "ослепление" or "оглушение"
	end },
	{ field = "chain", label = function(chain)
		return chain.stun and "оглушение" or nil
	end },
	{ field = "explosion", label = "взрыв при попадании" },
	{ field = "wet", label = "мокрый" },
	{ field = "bleeds", label = "кровотечение" },
	{ field = "debuff", label = "разъедает броню" },
	-- Ветка холода: замедляет ход, атаку и регенерацию. Ход — своей строкой характеристик,
	-- здесь — чем элемент отличается от Холода.
	{ field = "attackSlowPercent", label = function(_, element)
		if (element.slowPercent or 0) <= 0 then
			return "охлаждает · не замедляет движение"
		elseif element.slowDuration == math.huge then
			return "охлаждает навсегда"
		end
		return "охлаждает"
	end },
	{ field = "regen", label = function(regen, element)
		if element.attackSlowPercent then
			return nil -- уже в «охлаждает»
		elseif regen.block then
			return "блокирует регенерацию"
		elseif regen.slow then
			return "замедляет регенерацию"
		end
		return nil
	end },
	{ field = "slowGrowth", label = "накапливающееся замедление" },
	{ field = "slowRamp", label = "застывание" },
	{ field = "burnCatalyst", label = "улучшает горение" },
	{ field = "amplifier", label = "усиливает эффекты" },
	{ field = "blind", label = "слепота" },
	{ field = "confusion", label = "сбивает с пути" },
	{ field = "toss", label = "подбрасывает" },
	{ field = "primer", label = "метка взрыва" },
	{ field = "contagion", label = "заразный" },
	{ field = "mark", label = function(mark)
		return MARK_NAMES[mark.kind] or "метка"
	end },
	{ field = "washes", label = function(kind)
		return kind == "rust" and "смывает ржавчину" or nil
	end },
	{ field = "terrain", label = "меняет рельеф" },
	-- Дым — удушье (разовый большой урон), Смог — взрыв с зоной тумана.
	{ field = "breakthrough", label = function(plan)
		return plan.zone and "взрыв · зона тумана" or "удушье"
	end },
	{ field = "killDamage", label = function(plan)
		return plan.spreadElement == "Steam" and "взрыв при смерти с ошпариванием" or "взрыв при смерти"
	end },
	{ field = "killZone", label = function(_, _, key)
		return EntityInfo.ZONE_NAMES[key] or "оставляет зону"
	end },
	-- Жизнь не бьёт врагов, и плодов с убитых у неё не бывает.
	{ field = "killHeal", label = function(_, element)
		return not element.healer and "лечащие плоды" or nil
	end },
	{ field = "killBarrier", label = "преграда при смерти" },
}

-- Элементы, чья механика из вики в коде сделана не целиком и требует большой доработки:
-- карточка показывает яркую пометку «в разработке» и что именно не готово.
EntityInfo.IN_DEVELOPMENT = {
	Soap = "очищение пока не работает — Мыло просто бьёт",
	Life = "лечение построек пока не работает — турель стреляет как обычная",
	Clay = "керамическая статуя пока не появляется",
	Star = "взрыв зоны и белый карлик пока не появляются",
	Plant = "растение из трупа пока не вырастает — плоды лечат сразу",
	Soil = "метка грунта пока ни на что не влияет",
}

-- Загадка для игрока (вики): вместо характеристик — вопросы.
EntityInfo.MYSTERY = { Antimatter = true }

local function collect(list, key, element)
	if EntityInfo.MYSTERY[key] then
		return { "???" }
	end
	local found, seen = {}, {}
	for _, trait in list do
		local value = element[trait.field]
		if value ~= nil and value ~= false and value ~= 0 then
			local label = trait.label
			if type(label) == "function" then
				label = label(value, element, key)
			end
			if label and not seen[label] then
				seen[label] = true
				table.insert(found, label)
			end
		end
	end
	return found
end

function EntityInfo.ElementFeatures(key, element)
	return collect(EntityInfo.ELEMENT_FEATURES, key, element)
end

function EntityInfo.ElementEffects(key, element)
	return collect(EntityInfo.ELEMENT_EFFECTS, key, element)
end

return EntityInfo
