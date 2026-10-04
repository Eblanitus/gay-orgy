-- Обучение на уровне 1 (задача #298): ограничения уровня и шаги подсказки.
-- Данные — в ReplicatedStorage.TutorialConfig. Здесь только состояние забега:
-- идёт ли обучение и сколько раз игрок уже сделал каждое действие.
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
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("TutorialConfig"))

local Tutorial = {}

local active = false -- идёт забег уровня с обучением
local unlocked = false -- введён промокод test
local counts = {}

local function restricted()
	return active and not unlocked
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
	if restricted() then
		for key in Config.towers do
			table.insert(towers, key)
		end
	end
	ReplicatedStorage:SetAttribute("TutorialTowers", table.concat(towers, ","))
	ReplicatedStorage:SetAttribute("TutorialRestricted", restricted())
end

-- Начало забега. levelInfo — запись из Levels.
function Tutorial.Start(levelInfo)
	active = levelInfo ~= nil and levelInfo.tutorial == true
	table.clear(counts)
	publish()
end

-- Конец забега: арена пуста, ограничения больше не к чему применять.
function Tutorial.Stop()
	active = false
	table.clear(counts)
	publish()
end

-- Идёт ли обучение с ограничениями прямо сейчас.
function Tutorial.IsRestricted()
	return restricted()
end

-- Стартовый элемент, если обучение идёт: его кладут в сумку вместо заливки в стартовую Колбу.
function Tutorial.StarterElement()
	return restricted() and Config.starterElement or nil
end

function Tutorial.TowerAllowed(towerType)
	return not restricted() or Config.towers[towerType] == true
end

function Tutorial.ElementAllowed(elementKey)
	return not restricted() or Config.elements[elementKey] == true
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

publish()

return Tutorial
