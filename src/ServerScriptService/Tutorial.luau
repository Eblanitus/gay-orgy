-- Обучение на уровне 1 (задача #298): ограничения уровня и шаги подсказки.
-- Данные — в ReplicatedStorage.TutorialConfig. Здесь только состояние забега:
-- идёт ли обучение и сколько раз игрок уже сделал каждое действие.
-- Тут же правила обычных уровней (Levels[n].rules: Бункер — только Колбы и элементы
-- до тира 1): Tutorial уже стоит во всех проверках постройки, покупки и станций.
--
-- Клиенту состояние уходит атрибутами на ReplicatedStorage, как TurretsUnlocked у TowerUnlocks:
--   TutorialStep   — номер текущего шага в TutorialConfig.steps (0 — плашку не показывать;
--                    текст по номеру выбирает клиент: на телефоне он другой)
--   TutorialWaveLocked — волну пока запускать нельзя (Hud прячет кнопку)
--   TutorialTowers — открытые постройки через запятую ("" — ограничений нет)
--   TutorialRestricted — идёт обучение с ограничениями (прячет рулетку и апгрейдер)
--
-- Промокод test снимает ограничения на весь сервер до перезапуска (как и прочие коды):
-- это инструмент проверки, перевводить его каждый забег было бы мучением.
-- Промокод tutorial возвращает их и запускает обучение заново (Rearm).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("TutorialConfig"))
local Elements = require(ReplicatedStorage:WaitForChild("Elements"))

local Tutorial = {}

local active = false -- идёт забег уровня с обучением
local unlocked = false -- введён промокод test
local counts = {}
local rules = nil -- Levels[n].rules обычного уровня (Бункер: только Колбы и тир 1)

local function restricted()
	return active and not unlocked
end

-- Правила обычного уровня действуют, пока их не снял промокод test.
local function ruled()
	return rules ~= nil and not unlocked
end

local function currentStep()
	for i, step in Config.steps do
		if (counts[step.action] or 0) < step.need then
			return step, i
		end
	end
	return nil, 0
end

local function waveAllowed()
	if not restricted() then
		return true
	end
	local step = currentStep()
	return step == nil or step.action == "wave"
end

local function publish()
	local _, index = currentStep()
	ReplicatedStorage:SetAttribute("TutorialStep", restricted() and index or 0)
	ReplicatedStorage:SetAttribute("TutorialWaveLocked", not waveAllowed())

	local towers = {}
	local open = (restricted() and Config.towers) or (ruled() and rules.towers) or nil
	if open then
		for key in open do
			table.insert(towers, key)
		end
	end
	ReplicatedStorage:SetAttribute("TutorialTowers", table.concat(towers, ","))
	ReplicatedStorage:SetAttribute("TutorialRestricted", restricted())
end

-- Начало забега. levelInfo — запись из Levels.
function Tutorial.Start(levelInfo)
	active = levelInfo ~= nil and levelInfo.tutorial == true
	rules = levelInfo ~= nil and not active and levelInfo.rules or nil
	table.clear(counts)
	publish()
end

-- Конец забега: арена пуста, ограничения больше не к чему применять.
function Tutorial.Stop()
	active = false
	rules = nil
	table.clear(counts)
	publish()
end

-- Идёт ли обучение с ограничениями прямо сейчас.
function Tutorial.IsRestricted()
	return restricted()
end

-- Идёт ли забег уровня-обучения (независимо от промокода): от этого зависят
-- стартовая материя, место и пустота стартовой Колбы, защита стола и засчёт уровня.
function Tutorial.IsActive()
	return active
end

-- Материя на старте забега обучения; nil — обычный старт (Matter.STARTING_AMOUNT).
function Tutorial.StartMatter()
	return active and Config.startMatter or nil
end

-- Сдвиг стартовой Колбы от центра стола; nil — обычное место (центр арены).
function Tutorial.StarterOffset()
	return active and Config.starterOffset or nil
end

-- Не ломается ли стол на этой волне.
function Tutorial.TableGuarded(waveNumber)
	return active and waveNumber <= Config.guardedWaves
end

-- Засчитывается ли обучение после этой волны.
function Tutorial.CompletesAt(waveNumber)
	return active and waveNumber == Config.completeAfterWave
end

function Tutorial.TowerAllowed(towerType)
	if restricted() then
		return Config.towers[towerType] == true
	end
	if ruled() and rules.towers then
		return rules.towers[towerType] == true
	end
	return true
end

-- Элемент не выше тира, открытого на уровне (rules.maxTier). Нужен и покупке, и крафту:
-- на крафте проверяется результат, до того как ингредиенты уйдут.
function Tutorial.TierAllowed(elementKey)
	local data = Elements[elementKey]
	return not (ruled() and rules.maxTier and data and (data.tier or 0) > rules.maxTier)
end

-- Рулетка и Апгрейдер выдают элементы любого тира: на уровне с rules их можно закрыть.
function Tutorial.StationAllowed(station)
	return not (ruled() and rules[station] == false)
end

-- Текст отказа для правил уровня — один на всех, кто их проверяет.
function Tutorial.RulesText()
	return "на этом уровне закрыто: только Колбы и элементы до тира " .. tostring(rules and rules.maxTier or 0)
end

-- Пока текущий шаг — постройка Колбы, магазин закрыт: деньги на неё (бонус волны 20)
-- не должны уйти на элементы, иначе шаг не пройти и волну не запустить (#432).
function Tutorial.ElementAllowed(elementKey)
	if not restricted() then
		return Tutorial.TierAllowed(elementKey)
	end
	local step = currentStep()
	if step and step.action == "build" then
		return false
	end
	return Config.elements[elementKey] == true
end

-- Действие игрока (pour/build/buy/wave) — двигает подсказку.
function Tutorial.Report(action)
	if not restricted() then
		return
	end
	counts[action] = (counts[action] or 0) + 1
	publish()
end

-- Можно ли запускать волну: все шаги до "wave" пройдены.
function Tutorial.WaveAllowed()
	return waveAllowed()
end

-- Промокод test. Возвращает true, если этот вызов что-то снял.
function Tutorial.UnlockAll()
	if unlocked then
		return false
	end
	unlocked = true
	publish()
	return true
end

-- Промокод tutorial: вернуть ограничения, снятые test, чтобы обучение можно было
-- пройти заново так, как его видит новый игрок. Вызывается до Tutorial.Start нового забега.
function Tutorial.Rearm()
	if not unlocked then
		return false
	end
	unlocked = false
	publish()
	return true
end

publish()

return Tutorial
