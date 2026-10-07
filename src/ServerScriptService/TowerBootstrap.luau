-- Стартовая Колба забега: строится тем же путём, что и игрок-построенные — просто
-- бесплатно (TowerBuilder.BuildFree) и сразу с залитым Огнём.
--
-- Клетка задана здесь, а не площадкой в плейсе: площадок с ТЗ v2.1 больше нет. Центр
-- арены — примерно на прямой от пролома к выходу, чтобы стартовая башня доставала
-- до врагов на пустой, ещё не застроенной арене.
--
-- Считается от размера сетки, а не вписан числами: раньше здесь стояло (13, 8),
-- и после измельчения клетки эта же пара чисел стала углом арены, а не её центром.
--
-- Это модуль, а не разовый Script: стартовая башня — часть начального состояния забега,
-- и её надо ставить заново на каждом рестарте (см. WaveRunner).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Arena = require(ReplicatedStorage:WaitForChild("Arena"))
local TowerBuilder = require(ServerScriptService:WaitForChild("TowerBuilder"))
local Tutorial = require(ServerScriptService:WaitForChild("Tutorial"))
local PourPrompt = require(ServerScriptService:WaitForChild("PourPrompt"))
local LabTable = require(ServerScriptService:WaitForChild("LabTable"))

local TowerBootstrap = {}

function TowerBootstrap.PlaceStartingTower()
	-- Центр считается на каждый вызов, а не при загрузке: у разных локаций разный размер сетки.
	local startX = math.floor((Arena.cols + 1) / 2)
	local startZ = math.floor((Arena.rows + 1) / 2)

	-- Обучение (#432): Колба стоит у стола, чтобы доставать жуков, которые его грызут
	-- (на волнах 1–2 стол не ломается, и недостающая турель держала бы волну вечно).
	local offset = Tutorial.StarterOffset()
	if offset then
		startX, startZ = Arena.ToCell(LabTable.Position() + offset)
	end

	local ok, tower = TowerBuilder.BuildFree(startX, startZ, "Ballista")
	if not ok and offset then
		warn(("[TowerBootstrap] у стола стартовая башня не встала (%s) — ставим в центр"):format(tostring(tower)))
		ok, tower = TowerBuilder.BuildFree(math.floor((Arena.cols + 1) / 2), math.floor((Arena.rows + 1) / 2), "Ballista")
	end
	if not ok then
		warn(("[TowerBootstrap] не удалось построить стартовую башню: %s"):format(tostring(tower)))
		return nil
	end

	-- Обучение: Колба стоит пустая, сумка пуста — элемент игрок покупает сам на стартовые
	-- 10 материи, и первые шаги обучения — купить его и залить.
	if Tutorial.IsActive() then
		PourPrompt.Add(tower)
		return tower
	end

	TowerBuilder.PourElement(tower, "Fire")
	return tower
end

return TowerBootstrap
