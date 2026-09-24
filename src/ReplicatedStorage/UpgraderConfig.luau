-- Числа апгрейдера производителя (alchemy_td_location_v1.6.md, «Производитель: режимы работы»).
-- Игрок вкладывает свой элемент и двигает его вперёд по собственной ветке: получилось —
-- забирает цель, не получилось — вложенное сгорает.
--
-- Таблица лежит в ReplicatedStorage, а не рядом с розыгрышем: по этим же числам магазин
-- рисует проценты. Если шанс считать в двух местах, витрина однажды пообещает одно,
-- а сервер разыграет другое.

local Config = {
	-- Ветки — четыре чистокровные спины из дерева рецептов (alchemy_td_recipes_v3.1.md).
	-- Боковые рецепты (Болото из Лужи, Остров из Океана, Засуха из Суши) веток не образуют
	-- и апгрейдеру не видны: он ходит только по этим цепочкам.
	SPINES = {
		{ "Fire", "Energy", "Flare", "Lightning", "Star" },
		{ "Earth", "Soil", "Land", "Continent", "Lithosphere" },
		{ "Water", "Puddle", "Pond", "Ocean", "Hydrosphere" },
		{ "Air", "Pressure", "Wind", "Hurricane", "Atmosphere" },
	},
	-- Шанс на одну ступень вперёд. На каждую следующую делится пополам — не отдельными
	-- числами в таблице, а правилом ниже: список процентов для пяти ступеней пришлось бы
	-- править при каждом удлинении ветки.
	STEP_CHANCE = 0.5,
	-- Попытка бесплатная: платой служит риск потерять вложенный элемент.
	COST = 0,
	-- Неудача сжигает вложенное. Если правило смягчат, менять надо здесь, а не в коде.
	BURN_ON_FAIL = true,
	-- Сколько секунд крутится стрелка. Пока она крутится, попытка не завершена,
	-- и новая не принимается (вики): сервер держит замок ровно столько же.
	SHOW_TIME = 2,
}

-- Где стоит элемент: номер ветки и номер ступени в ней. Элемент вне спин — nil.
function Config.Locate(key)
	for spineIndex, chain in Config.SPINES do
		for step, member in chain do
			if member == key then
				return spineIndex, step
			end
		end
	end
	return nil
end

-- Шанс на прыжок в steps ступеней: половина, четверть, восьмая и так далее.
function Config.Chance(steps)
	if type(steps) ~= "number" or steps < 1 then
		return 0
	end
	return Config.STEP_CHANCE ^ steps
end

-- Куда можно двинуть элемент: только вперёд и только по своей ветке.
-- Возвращает список { key, steps, chance } от ближней цели к дальней.
function Config.Targets(key)
	local spineIndex, step = Config.Locate(key)
	if not spineIndex then
		return {}
	end
	local chain = Config.SPINES[spineIndex]
	local list = {}
	for i = step + 1, #chain do
		list[#list + 1] = {
			key = chain[i],
			steps = i - step,
			chance = Config.Chance(i - step),
		}
	end
	return list
end

-- Сколько ступеней от одного элемента до другого. nil — если это не «вперёд по своей
-- ветке»: чужая ветка, шаг назад, тот же самый элемент, элемент вне спин.
function Config.StepsBetween(fromKey, toKey)
	local fromSpine, fromStep = Config.Locate(fromKey)
	local toSpine, toStep = Config.Locate(toKey)
	if not fromSpine or not toSpine then
		return nil
	end
	if fromSpine ~= toSpine then
		return nil
	end
	if toStep <= fromStep then
		return nil
	end
	return toStep - fromStep
end

return Config
