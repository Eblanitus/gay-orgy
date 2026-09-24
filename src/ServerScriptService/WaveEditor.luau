-- Конструктор волн: игрок сам решает, какие жуки пойдут в волне и сколько их.
-- Открывается промокодом (см. PromoCode) — в обычном забеге его нет.
--
-- Вся проверка — ЗДЕСЬ, на сервере (правило проекта: клиент присылает намерение,
-- решает сервер). Клиенту не верим ни в виде жука, ни в числе: иначе через консоль
-- можно было бы заказать десять тысяч Гигантов и положить сервер.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Enemies = require(ReplicatedStorage:WaitForChild("Enemies"))

local WaveEditor = {}

-- Состояние сменилось (открыли конструктор или задали состав). Рассылкой клиентам
-- занимается WaveEditorService — сам модуль про ремоуты не знает и остаётся чистой
-- логикой, которую можно дёргать из теста без единого клиента.
WaveEditor.Changed = Instance.new("BindableEvent")

-- Потолки. Не баланс, а страховка от того, чтобы игрок не положил себе сервер
-- одной строкой: волна на полторы сотни жуков и так кладёт толкучку на лопатки.
WaveEditor.MAX_PER_TYPE = 50
WaveEditor.MAX_TOTAL = 150

local unlocked = false

-- Состав, заданный игроком. nil — волны идут как в Waves.
--
-- Действует со следующей волны и дальше, пока игрок не поменяет или не сбросит.
-- Одноразовым его делать не стал: это инструмент для проверки видов, и перенабирать
-- состав перед каждой волной было бы мучением.
local custom = nil

-- Список видов для панели. Собирается из самой таблицы врагов, а не выписывается
-- вторым списком: новый жук появляется в панели сам, без правок здесь.
local roster = nil

local function buildRoster()
	local list = {}
	for key, data in Enemies do
		if type(data) == "table" and data.name then
			table.insert(list, { key = key, name = data.name, caste = data.caste or 0, hp = data.hp or 0 })
		end
	end
	-- По кастам, внутри касты по имени: так же, как виды выложены в вики,
	-- и так же, как игрок их встречает по ходу уровня.
	table.sort(list, function(a, b)
		if a.caste ~= b.caste then
			return a.caste < b.caste
		end
		return a.name < b.name
	end)
	return list
end

function WaveEditor.Roster()
	if not roster then
		roster = buildRoster()
	end
	return roster
end

function WaveEditor.IsUnlocked()
	return unlocked
end

-- Возвращает true, если открыли именно сейчас (чтобы промокод мог отличить
-- первый ввод от повторного).
function WaveEditor.Unlock()
	if unlocked then
		return false
	end
	unlocked = true
	WaveEditor.Changed:Fire()
	return true
end

-- Что сейчас заказано. Копия, а не сама таблица: отдавать наружу своё состояние
-- значит разрешить править его мимо проверки.
function WaveEditor.Current()
	if not custom then
		return nil
	end
	local copy = {}
	for _, g in ipairs(custom) do
		table.insert(copy, { enemyType = g.enemyType, count = g.count })
	end
	return copy
end

function WaveEditor.Clear()
	custom = nil
	WaveEditor.Changed:Fire()
end

-- Принимает состав от игрока. Возвращает (true, сколько всего жуков) либо (false, причина).
--
-- Состав приходит с клиента, поэтому проверяется каждое поле каждой записи,
-- а не только тип самой таблицы.
function WaveEditor.Set(groups)
	if not unlocked then
		return false, "конструктор волн не открыт"
	end
	if typeof(groups) ~= "table" then
		return false, "состав не передан"
	end

	local clean, total, seen = {}, 0, {}
	for _, entry in ipairs(groups) do
		if typeof(entry) ~= "table" then
			return false, "состав испорчен"
		end

		local key = entry.enemyType
		local count = entry.count
		if typeof(key) ~= "string" or not Enemies[key] or not Enemies[key].name then
			return false, ("нет такого жука: %s"):format(tostring(key))
		end
		if seen[key] then
			return false, ("жук %s указан дважды"):format(Enemies[key].name)
		end
		if typeof(count) ~= "number" or count ~= count or count < 0 then
			return false, "количество должно быть числом от нуля"
		end

		seen[key] = true
		count = math.clamp(math.floor(count), 0, WaveEditor.MAX_PER_TYPE)
		if count > 0 then
			total += count
			table.insert(clean, { enemyType = key, count = count })
		end
	end

	if #clean == 0 then
		-- Пустой состав — это не ошибка, а «верни как было»: иначе выключить
		-- конструктор было бы нечем.
		custom = nil
		WaveEditor.Changed:Fire()
		return true, 0
	end
	if total > WaveEditor.MAX_TOTAL then
		return false, ("слишком много жуков: %d, предел %d"):format(total, WaveEditor.MAX_TOTAL)
	end

	custom = clean
	WaveEditor.Changed:Fire()
	return true, total
end

-- Что реально спавнить в этой волне. Зовёт WaveRunner вместо wave.groups.
--
-- hp у заказанных групп не указывается вовсе — спавнер возьмёт базовое из Enemies.
-- Пускать сюда число с клиента значило бы дать ему ставить жукам любое HP.
function WaveEditor.Groups(wave)
	if custom then
		return custom, true
	end
	return wave.groups, false
end

return WaveEditor
