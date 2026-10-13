-- Биореактор (по вики): единственный источник материи в забеге, кроме стартового запаса
-- и награды за волну. Принимает останки, которые привезли носильщики (Carriers), и через
-- Economy.processTime выдаёт материю. Здесь только переработка; постройку ставит TowerBuilder
-- (Towers.Bioreactor), дронов водит Carriers.
--
-- Точки подключения для модели и интерфейса (их делают отдельно):
--   * Remotes.EconomyFX:FireAllClients("load", reactor, value) — груз сброшен в приёмный лоток;
--   * Remotes.EconomyFX:FireAllClients("processed", reactor, amount) — переработка кончилась,
--     amount материи ушло в кошелёк (целое, может быть 0 — копится дробная часть);
--   * атрибут Processing (число) на модели реактора — сколько грузов сейчас в переработке.
-- reactor может быть nil (сбор без носильщиков, этап 1, или реактор снесли с грузом в тракте).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Economy = require(ReplicatedStorage:WaitForChild("Economy"))
local Matter = require(ServerScriptService:WaitForChild("Matter"))
local Corpses = require(ServerScriptService:WaitForChild("Corpses"))
local EconomyFX = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("EconomyFX")

local Bioreactor = {}

-- Дробная материя: клочья Мини-жука стоят 0.6, и без накопления такие грузы пропадали бы целиком.
local carry = 0
-- Поколение забега: переработка, начатая до рестарта, в новый забег материю не приносит.
local generation = 0

local function bump(reactor, delta)
	if reactor and reactor.Parent then
		reactor:SetAttribute("Processing", math.max((reactor:GetAttribute("Processing") or 0) + delta, 0))
	end
end

-- Груз сброшен в реактор: через processTime его ценность станет материей.
function Bioreactor.Process(reactor, value)
	if value <= 0 then
		return
	end
	local mine = generation
	bump(reactor, 1)
	EconomyFX:FireAllClients("load", reactor, value)
	task.delay(Economy.processTime, function()
		if mine ~= generation then
			return
		end
		bump(reactor, -1)
		carry += value
		local whole = math.floor(carry + 1e-6)
		carry -= whole
		if whole > 0 then
			Matter.Add(whole)
		end
		EconomyFX:FireAllClients("processed", reactor, whole)
	end)
end

-- Новый забег: недоработанное и дробный остаток сгорают вместе с прежним забегом.
function Bioreactor.Reset()
	generation += 1
	carry = 0
end

-- Сбор без носильщиков (Economy.autoCollectDelay): труп сам уходит в переработку через
-- заданное время после смерти. Включён, только пока носильщиков нет.
task.spawn(function()
	while true do
		task.wait(0.5)
		local delay = Economy.autoCollectDelay
		if delay then
			local now = os.clock()
			for _, record in Corpses.Valuable() do
				if now - record.bornAt >= delay then
					Bioreactor.Process(nil, Corpses.Take(record))
				end
			end
		end
	end
end)

return Bioreactor
