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
--   * логические записи трупов { id, position, alive } — их ест Пеликан (EnemyBehavior);
--   * ценность трупа в материи (экономика по вики: материя только из трупов) — её увозят
--     носильщики в Биореактор (Carriers, Bioreactor). Числа — ReplicatedStorage.Economy.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local PhysicsFX = require(ReplicatedStorage:WaitForChild("PhysicsFX"))
local Loose = require(ReplicatedStorage:WaitForChild("Loose"))
local Effects = require(ReplicatedStorage:WaitForChild("Effects"))
local Elements = require(ReplicatedStorage:WaitForChild("Elements"))
local Economy = require(ReplicatedStorage:WaitForChild("Economy"))

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

-- Обугленный осыпался: есть Пеликану больше нечего, а носильщики ещё могут собрать угли
-- (Economy.integrity.ash). Без ценности — запись снимается, как раньше.
local function crumble(record)
	if not record.alive then
		return
	end
	local ash = Economy.integrity.ash or 0
	if ash <= 0 or (record.value or 0) <= 0 then
		forget(record)
		return
	end
	record.value *= ash / math.max(record.integrity, 1e-6)
	record.integrity = ash
	record.remains = "ash"
	record.edible = false
	record.crew = 1
end

-- Виды останков, после которых тела нет (по вики): давит, плавит, растворяет, рвёт,
-- уничтожает. Пеликану есть нечего — запись у них «несъедобная» (edible = false) и заводится,
-- только если носильщикам есть что увезти (Economy.integrity: лепёшка, клочья, лужица).
local BODYLESS = { crush = true, melt = true, dissolve = true, gib = true, destroy = true }

-- Сколько носильщиков нужно на тушу (Economy.crewArea): по площади тела, лёгким останкам — один.
local function crewFor(remains, scale)
	if Economy.lightRemains[remains] then
		return 1
	end
	local crew = math.floor(scale * scale + 0.5)
	return math.clamp(crew, 1, Economy.crewMax)
end

-- Жук умер. Зовётся ДО enemy:Destroy(): клиент по этому событию забирает видимое тело жука
-- и делает из него тушу. hit — как в CorpseFX.Leave: { fraction, from, floorY, carry, remains }.
-- remains — вид останков (Effects.RemainsOf); без него — тело. hit.value — материя целого
-- трупа (Enemies[вид].matter); без неё труп ничего не стоит (Аркада, очищенные).
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

	local edible = not BODYLESS[hit.remains]
	local integrity = Economy.integrity[hit.remains] or 0
	local value = (hit.value or 0) * integrity * Economy.valueScale
	hit.value = nil -- клиенту не нужна

	if not edible and value <= 0 then
		EnemyFX:FireAllClients("death", enemy, nil, hit)
		return nil
	end

	nextId += 1
	local scale = hit.scale / 3
	local record = {
		id = nextId,
		position = root.Position,
		alive = true,
		remains = hit.remains,
		scale = scale,
		bornAt = os.clock(),
		swampy = hit.swampy == true,
		edible = edible,
		-- Экономика: сколько материи выйдет из трупа в Биореакторе и сколько носильщиков
		-- нужно, чтобы его увезти. claimed — кто из носильщиков за ним уже едет (Carriers).
		value = value,
		integrity = integrity,
		crew = crewFor(hit.remains, scale),
		enemyType = enemy:GetAttribute("Type"),
	}
	remember(record)
	EnemyFX:FireAllClients("death", enemy, nextId, hit)
	if hit.remains == "char" then
		task.delay(CRUMBLE_TIME, crumble, record)
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

-- Ближайший лежащий труп с телом (для Пеликана) или nil.
function Corpses.Nearest(at)
	local best, bestDistance = nil, math.huge
	for _, record in records do
		local distance = record.edible and (record.position - at).Magnitude or math.huge
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

-- ===== Экономика: сбор трупов (носильщики, Carriers) =====

-- Живые записи, у которых есть ценность, — в порядке смерти. Копия списка: носильщик
-- может забрать запись, пока по нему идут.
function Corpses.Valuable()
	local list = {}
	for _, record in records do
		if record.alive and (record.value or 0) > 0 then
			table.insert(list, record)
		end
	end
	return list
end

-- Труп подобран и увезён: записи больше нет, клиенты убирают тушу (или лежащие останки
-- без туши — по точке и радиусу). Возвращает материю, которую он даст в Биореакторе, или 0,
-- если его уже нет (съел Пеликан, осыпался, лопнул, вытеснен по лимиту).
function Corpses.Take(record)
	if not record.alive then
		return 0
	end
	forget(record)
	local radius = Economy.scrapRadius * (record.scale or 1)
	EnemyFX:FireAllClients("collect", record.id, record.position, radius)
	return record.value or 0
end

-- Груз погибшего носильщика упал на поле (Carriers): та же материя снова лежит и ждёт, кто
-- её увезёт. Тела уже нет (тушу забрали при погрузке) — запись «несъедобная», как клочья,
-- и возит её один дрон. Видимый ком груза ставит сам Carriers.
function Corpses.Drop(position, value)
	if value <= 0 then
		return nil
	end
	nextId += 1
	local record = {
		id = nextId,
		position = position,
		alive = true,
		remains = "gib",
		scale = 1,
		bornAt = os.clock(),
		swampy = false,
		edible = false,
		value = value,
		integrity = Economy.integrity.gib or 0,
		crew = 1,
	}
	remember(record)
	return record
end

return Corpses
