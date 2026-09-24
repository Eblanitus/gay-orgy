-- Трупы и кровь: СЕРВЕРНАЯ часть.
--
-- Туши, оторванные куски и пятна — чистый визуал: маршрут, HP, прицел и проход жуков от них
-- не зависят (лучи походки трупы не ловят). Раньше всё это строил сервер, и каждая деталь
-- каждого трупа шла по сети — основная доля трафика и кадра сервера (замер: 20 Мбит/с на 39 жуков).
-- Теперь сервер только сообщает клиентам «жук умер вот так» по Remotes.EnemyFX, а тушу
-- строит каждый клиент сам (ReplicatedStorage.CorpseFX, вызывает EnemyRender).
--
-- Здесь остаётся то, что нужно логике:
--   * группы столкновений Enemies/Corpses (их читает и клиент — группы реплицируются);
--   * логические записи трупов { id, position, alive } — их ест Пеликан (EnemyBehavior).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PhysicsService = game:GetService("PhysicsService")

local Arena = require(ReplicatedStorage:WaitForChild("Arena"))

local EnemyFX = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("EnemyFX")

local ENEMY_GROUP = "Enemies"
local CORPSE_GROUP = "Corpses"

-- Тот же потолок, что у туш на клиенте (CorpseFX MAX_CORPSES): съесть можно только то, что видно.
local MAX_CORPSES = 60

local Corpses = {}

-- Группы заводятся один раз при загрузке модуля, а не руками в Studio: иначе работающий
-- код зависит от настройки, которой нет ни в одном файле.
local function registerGroups()
	for _, name in { ENEMY_GROUP, CORPSE_GROUP } do
		if not PhysicsService:IsCollisionGroupRegistered(name) then
			PhysicsService:RegisterCollisionGroup(name)
		end
	end

	-- Жук толкает труп — и больше ничего. С полом, постройками и игроком его тело
	-- не сталкивается.
	PhysicsService:CollisionGroupSetCollidable(ENEMY_GROUP, CORPSE_GROUP, true)
	PhysicsService:CollisionGroupSetCollidable(ENEMY_GROUP, "Default", false)
	PhysicsService:CollisionGroupSetCollidable(ENEMY_GROUP, ENEMY_GROUP, false)
	PhysicsService:CollisionGroupSetCollidable(CORPSE_GROUP, "Default", true)
	PhysicsService:CollisionGroupSetCollidable(CORPSE_GROUP, CORPSE_GROUP, true)
end
registerGroups()

-- Имена групп — отсюда, а не строкой в других скриптах: две копии названия разойдутся
-- при первой же опечатке.
Corpses.EnemyCollisionGroup = ENEMY_GROUP
Corpses.CorpseCollisionGroup = CORPSE_GROUP

local records = {} -- по порядку смерти, самый старый первый
local nextId = 0

local function remember(record)
	table.insert(records, record)
	while #records > MAX_CORPSES do
		table.remove(records, 1).alive = false
	end
end

-- Жук умер. Зовётся ДО enemy:Destroy(): клиент по этому событию забирает видимое тело жука
-- и делает из него тушу. hit — как в CorpseFX.Leave: { fraction, from, floorY, carry }.
function Corpses.Leave(enemy, hit)
	local root = enemy.PrimaryPart
	if not root then
		return nil
	end
	hit = table.clone(hit or {})
	hit.scorched = enemy:GetAttribute("Scorched") == true
	hit.scale = enemy:GetAttribute("Scale") or 3

	nextId += 1
	local record = { id = nextId, position = root.Position, alive = true }
	remember(record)
	EnemyFX:FireAllClients("death", enemy, nextId, hit)
	return record
end

function Corpses.Splat(position, size, drops, floorY)
	EnemyFX:FireAllClients("splat", position, size, drops or 0, floorY or Arena.floorY)
end

-- Гора поглощает трупы в своём следу.
function Corpses.Absorb(position, radius)
	for index = #records, 1, -1 do
		local record = records[index]
		local delta = record.position - position
		if math.abs(delta.X) <= radius and math.abs(delta.Z) <= radius then
			record.alive = false
			table.remove(records, index)
		end
	end
	EnemyFX:FireAllClients("absorb", position, radius)
end

function Corpses.Clear()
	for _, record in records do
		record.alive = false
	end
	table.clear(records)
	EnemyFX:FireAllClients("clear")
end

-- Ближайший лежащий труп (для Пеликана) или nil.
function Corpses.Nearest(at)
	local best, bestDistance = nil, math.huge
	for _, record in records do
		local distance = (record.position - at).Magnitude
		if distance < bestDistance then
			best, bestDistance = record, distance
		end
	end
	return best, bestDistance
end

function Corpses.Eat(record)
	local index = table.find(records, record)
	if index then
		table.remove(records, index)
	end
	record.alive = false
	EnemyFX:FireAllClients("eat", record.id)
end

return Corpses
