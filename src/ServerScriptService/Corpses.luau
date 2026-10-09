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
local Workspace = game:GetService("Workspace")

local PhysicsFX = require(ReplicatedStorage:WaitForChild("PhysicsFX"))
local Loose = require(ReplicatedStorage:WaitForChild("Loose"))
local Effects = require(ReplicatedStorage:WaitForChild("Effects"))
local Elements = require(ReplicatedStorage:WaitForChild("Elements"))

local EnemyFX = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("EnemyFX")

-- Тот же потолок, что у туш на клиенте (CorpseFX MAX_CORPSES): съесть можно только то, что видно.
local MAX_CORPSES = 60

local Corpses = {}

-- Группы столкновений заводит общий физический слой (Loose): тут только вызов при загрузке
-- и имена для старых обращений.
Loose.SetupGroups()
Corpses.EnemyCollisionGroup = Loose.Groups.Enemies
Corpses.CorpseCollisionGroup = Loose.Groups.Corpses

local records = {} -- по порядку смерти, самый старый первый
local nextId = 0

local function remember(record)
	table.insert(records, record)
	while #records > MAX_CORPSES do
		table.remove(records, 1).alive = false
	end
end

local function forget(record)
	local index = table.find(records, record)
	if index then
		table.remove(records, index)
	end
	record.alive = false
end

-- Обугленный осыпается за это время (клиент — CorpseRemains.crumble): дальше есть нечего.
local char = PhysicsFX.char
local CRUMBLE_TIME = char.smokeTime + char.limbsTime + char.sinkTime + char.crackTime

-- Виды останков, после которых тела нет (по вики): давит, плавит, растворяет, рвёт,
-- уничтожает. Записи у них не заводится — Пеликану нечего есть.
local BODYLESS = { crush = true, melt = true, dissolve = true, gib = true, destroy = true }

-- Жук умер. Зовётся ДО enemy:Destroy(): клиент по этому событию забирает видимое тело жука
-- и делает из него тушу. hit — как в CorpseFX.Leave: { fraction, from, floorY, carry, remains }.
-- remains — вид останков (Effects.RemainsOf); без него — тело.
function Corpses.Leave(enemy, hit)
	local root = enemy.PrimaryPart
	if not root then
		return nil
	end
	hit = table.clone(hit or {})
	hit.remains = hit.remains or "body"
	-- Обугленный труп — только вид «char» (горел или добит огнём, по вики). Потушенный
	-- Мокрым или оплавленный без огня жук оставляет обычное тело.
	hit.scorched = hit.remains == "char"
	hit.scale = enemy:GetAttribute("Scale") or 3

	if BODYLESS[hit.remains] then
		EnemyFX:FireAllClients("death", enemy, nil, hit)
		return nil
	end

	nextId += 1
	local record = {
		id = nextId,
		position = root.Position,
		alive = true,
		remains = hit.remains,
		scale = hit.scale / 3,
		bornAt = os.clock(),
		swampy = hit.swampy == true,
	}
	remember(record)
	EnemyFX:FireAllClients("death", enemy, nextId, hit)
	if hit.remains == "char" then
		task.delay(CRUMBLE_TIME, forget, record)
	end
	return record
end

-- Касание хрупких трупов (холодная ветка, по вики): что тронуло круг center/radius —
-- шаг жука, попадание снаряда, взрыв — то и лопнуло. Клиенты рисуют осколки.
local brittle = PhysicsFX.brittle

function Corpses.Touch(center, radius)
	local now = os.clock()
	for index = #records, 1, -1 do
		local record = records[index]
		if record.remains == "brittle" and now - record.bornAt >= brittle.grace then
			local delta = record.position - center
			local reach = radius + brittle.size * record.scale
			if delta.X * delta.X + delta.Z * delta.Z <= reach * reach then
				table.remove(records, index)
				record.alive = false
				EnemyFX:FireAllClients("shatter", record.id)
			end
		end
	end
end

-- Болотный труп заражает жука, прошедшего по нему, тем же Болотным, что живой (по вики).
local swamp = Elements.Swamp.contagion

-- swamp.radius — касание жука и трупа обычного размера (масштаб 3). Крупнее тот или другой —
-- касаются дальше центрами: Гигант, прошедший брюхом по трупу, раньше не заражался, потому что
-- его центр не подходил к центру трупа на 4 студа. Мельче — ближе. record.scale — доля от 3.
local function infectAround(enemy, position)
	local walker = (enemy:GetAttribute("Scale") or 3) / 3
	for _, record in records do
		if record.swampy then
			local delta = record.position - position
			local reach = swamp.radius * (walker + (record.scale or 1)) / 2
			if delta.X * delta.X + delta.Z * delta.Z <= reach * reach then
				Effects.InfectFrom(enemy, swamp, Elements.Swamp.name .. " (труп)")
				return
			end
		end
	end
end

-- Шаги: наземный живой жук рядом с хрупким трупом лопает его, рядом с болотным — заражается.
-- Проверка идёт, только пока такие трупы есть.
task.spawn(function()
	local enemies = Workspace:WaitForChild("Enemies")
	while true do
		task.wait(brittle.check)
		local anyBrittle, anySwampy = false, false
		for _, record in records do
			anyBrittle = anyBrittle or record.remains == "brittle"
			anySwampy = anySwampy or record.swampy
		end
		if anyBrittle or anySwampy then
			for _, enemy in enemies:GetChildren() do
				if enemy:IsA("Model") and not enemy:GetAttribute("Flying") and (enemy:GetAttribute("HP") or 0) > 0 then
					local position = enemy:GetPivot().Position
					if anySwampy then
						infectAround(enemy, position)
					end
					if anyBrittle then
						Corpses.Touch(position, brittle.step * (enemy:GetAttribute("Scale") or 3) / 3)
					end
				end
			end
		end
	end
end)

-- Жук застыл керамической статуей (Глина + огонь). Тоже ДО Destroy: клиент забирает
-- видимое тело и ставит его копию в керамике внутрь статуи.
function Corpses.Statue(enemy, statue)
	EnemyFX:FireAllClients("statue", enemy, statue)
end

-- Кровь на полу (строит клиент, BloodFX). floorY — только если поле не на арене (Аркада):
-- иначе каждая капля ложится на свою опору — в яму, на плиту, на обломок (Loose.FloorAt).
-- Раньше сюда всегда подставлялся плоский пол арены, и кровь висела над ямами.
-- direction — куда летит кровь, длина вектора — вытяжка пятна (PhysicsFX.blood).
function Corpses.Splat(position, size, drops, floorY, direction)
	EnemyFX:FireAllClients("splat", position, size, drops or 0, floorY, direction)
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
