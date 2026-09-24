-- Числа рулетки производителя (alchemy_td_location_v1.6.md, «Производитель: режимы работы»).
-- Таблица лежит в ReplicatedStorage, а не рядом с розыгрышем на сервере: по этим же числам
-- магазин рисует цену. Если цену держать в двух местах, они однажды разойдутся, и витрина
-- начнёт обещать одно, а касса списывать другое.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Elements = require(ReplicatedStorage:WaitForChild("Elements"))

local Config = {
	-- Больше трёх прокруток за раз нельзя (вики).
	MAX_SPINS = 3,
	-- Шансы равные — по 25% на каждый из четырёх базовых (вики).
	WEIGHTS = { Fire = 1, Water = 1, Earth = 1, Air = 1 },
	-- Одна прокрутка стоит столько же, сколько обычная покупка базового элемента (вики).
	-- Поэтому цена не записана числом, а берётся из Elements: поменяют цену элемента —
	-- рулетка поедет за ней сама и не разойдётся с гайдом.
	COST_MULT = 1,
	-- Сколько секунд крутятся барабаны. Пока они крутятся, прокрутка не завершена,
	-- и новый запуск не принимается (вики): сервер держит замок ровно столько же.
	-- Первый запуск медленный — итог разглядывают. Запуск не позже SERIES_GAP секунд
	-- после конца прошлого — серия: каждый следующий в SPEEDUP раз короче, но не короче
	-- SHOW_TIME_MIN, чтобы тот, кто крутит много, не ждал. Время выбирает ShowTime ниже.
	SHOW_TIME = 3.5,
	SHOW_TIME_MIN = 1.5,
	SPEEDUP = 0.7,
	SERIES_GAP = 4,
	-- Джекпот (решение автора, 2026-09-23): все прокрутки одного запуска выпали одним
	-- элементом, а их не меньше JACKPOT_COUNT — сверху даётся ещё JACKPOT_BONUS этого элемента.
	-- Показ джекпота идёт JACKPOT_TIME секунд после барабанов; выдача и замок ждут и его.
	JACKPOT_COUNT = 3,
	JACKPOT_BONUS = 1,
	JACKPOT_TIME = 2.5,
}

-- Сколько идёт показ запуска: streak — какой он по счёту в серии (0 — первый).
function Config.ShowTime(streak)
	return math.max(Config.SHOW_TIME * Config.SPEEDUP ^ streak, Config.SHOW_TIME_MIN)
end

-- Джекпот запуска: выпавший элемент, если все results одинаковые и их не меньше
-- JACKPOT_COUNT, иначе nil. Решает сервер (Roulette.Spin), клиент только показывает.
function Config.Jackpot(results)
	if #results < Config.JACKPOT_COUNT then
		return nil
	end
	for i = 2, #results do
		if results[i] ~= results[1] then
			return nil
		end
	end
	return results[1]
end

function Config.SpinCost()
	local top = 0
	for key in Config.WEIGHTS do
		local data = Elements[key]
		if data and data.cost and data.cost > top then
			top = data.cost
		end
	end
	return math.floor(top * Config.COST_MULT + 0.5)
end

-- Цена складывается: три прокрутки стоят как три покупки (вики).
function Config.TotalCost(spins)
	return Config.SpinCost() * spins
end

return Config
