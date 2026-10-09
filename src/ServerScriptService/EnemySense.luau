-- Чувства и общая память жуков: то, что видят и знают ВСЕ виды сразу.
--
-- Поведение каст (EnemyBehavior), особые механики видов (EnemyTraits) и летуны
-- (EnemyFlight) спрашивают мир одинаково: кто жив, где ближняя турель, кто вокруг,
-- куда отойти из-под огня. Раньше всё это жило внутри EnemyBehavior, и разрезать его
-- на модули без общего места значило бы завести три копии одних и тех же функций.
--
-- Здесь же — общие таблицы состояния, которые читают несколько модулей:
--   states   — state каждого жука (его заводит EnemyBehavior.Attach): по нему один жук
--              видит, чем занят другой (прячется ли, несут ли его, идёт ли за вожаком);
--   focus    — приказы Координатора: кого на какую турель он навёл и до какого срока;
--   carried  — кого держит другой жук (несёт Медик, заворачивает Кукольник);
--   chewing  — что грызёт жук прямо сейчас: по нему Кислотник выбирает стену, а
--              Строитель — к чему прислонить Пандус;
--   colony   — память колонии за забег: нашли ли разведчики лабораторию.
--
-- Все таблицы со слабыми ключами: убитый жук не должен держаться в памяти ради того,
-- что о нём кто-то когда-то знал. Атрибутами их не заменить: атрибуты Roblox не держат
-- ссылки на Instance (найдено живым прогоном ещё при первом Координаторе).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Enemies = require(ReplicatedStorage:WaitForChild("Enemies"))
local Towers = require(ReplicatedStorage:WaitForChild("Towers"))
local Grid = require(ServerScriptService:WaitForChild("Grid"))
local EnemyStructures = require(ServerScriptService:WaitForChild("EnemyStructures"))

local Sense = {}

Sense.enemiesFolder = Workspace:WaitForChild("Enemies")
Sense.towersFolder = Workspace:WaitForChild("Towers")

local enemiesFolder = Sense.enemiesFolder
local towersFolder = Sense.towersFolder

local weak = { __mode = "k" }
Sense.states = setmetatable({}, weak)
Sense.focus = setmetatable({}, weak)
Sense.carried = setmetatable({}, weak)
Sense.chewing = setmetatable({}, weak)

-- Спавн жука из поведения (личинка вылупляется, Носитель высыпается, Матка кладёт).
-- Назначает EnemySpawner — прямой require спавнера зациклил бы модули.
-- Сигнатура: Spawn(тип, точка, setup) — setup(enemy) зовётся, когда жук уже на поле.
Sense.Spawn = nil

-- ============================ Общее ============================

-- Очищенный Мылом (атрибут Ally) для механик всё равно что мёртв: копать, строить,
-- лечить и звать своих он больше не будет — он теперь на стороне игрока.
function Sense.alive(enemy)
	return enemy ~= nil and enemy.Parent ~= nil and (enemy:GetAttribute("HP") or 0) > 0
		and not enemy:GetAttribute("Ally")
end

function Sense.flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

local alive, flat = Sense.alive, Sense.flat

-- Засыпает на t секунд и возвращает false, если жук за это время погиб. Все механики
-- ждут через неё, чтобы ни одна не продолжала работать на убитом.
function Sense.naps(enemy, t)
	task.wait(t)
	return alive(enemy)
end

function Sense.dataOf(enemy)
	return Enemies[enemy:GetAttribute("Type")]
end

-- Общие правила касты (Enemies.Castes): «каждая каста реагирует по-разному».
local NO_RULES = {}
function Sense.rules(caste)
	return Enemies.Castes and Enemies.Castes[caste or -1] or NO_RULES
end

-- Настоящая турель — та, у чьего типа есть fireRate. Стена и Гора — преграды,
-- и ни паника, ни Координатор, ни Моль их турелями не считают.
function Sense.isTurret(tower)
	local data = Towers[tower:GetAttribute("Type")]
	return data ~= nil and data.fireRate ~= nil
end

-- Стена игрока — постройка с высотой, но без выстрела (мешки, Гора, статуя Глины).
-- К ней прислоняют Пандус и её покрывает хитином Архитектор («пол и стены»).
function Sense.isWall(tower)
	return tower:GetAttribute("Height") ~= nil and not Sense.isTurret(tower)
end

-- Радиус огня турели. Нет в таблице (преграда) — ноль.
function Sense.turretRange(tower)
	local data = Towers[tower:GetAttribute("Type")]
	return data and data.range or 0
end

-- Ближняя турель и расстояние до неё — до края её следа (Grid.DistanceTo), а не до пивота.
-- У Мортиры от пивота до края ~13 студов: по пивоту солдат с engage 16 «видел» её только
-- вплотную, а Бур — за 14 студов, и ближней считалась мелкая дальняя, а не крупная рядом.
function Sense.nearestTurret(position, filter)
	local best, bestDistance = nil, math.huge
	for _, tower in towersFolder:GetChildren() do
		if Sense.isTurret(tower) and (not filter or filter(tower)) then
			local distance = Grid.DistanceTo(tower, position) or flat(tower:GetPivot().Position - position).Magnitude
			if distance < bestDistance then
				best, bestDistance = tower, distance
			end
		end
	end
	return best, bestDistance
end

-- Жуки вокруг точки. except — кого не считать (обычно себя самого).
function Sense.enemiesAround(position, radius, except)
	local found = {}
	for _, other in enemiesFolder:GetChildren() do
		if other ~= except and alive(other)
			and (other:GetPivot().Position - position).Magnitude <= radius then
			table.insert(found, other)
		end
	end
	return found
end

-- Сколько турелей держат точку в своём радиусе. Так жук оценивает место: чем меньше,
-- тем безопаснее (Матка ищет гнездо, работяга — укрытие).
function Sense.coverage(point)
	local count = 0
	for _, tower in towersFolder:GetChildren() do
		if Sense.isTurret(tower) then
			if flat(tower:GetPivot().Position - point).Magnitude <= Sense.turretRange(tower) then
				count += 1
			end
		end
	end
	return count
end

-- Можно ли жуку встать в эту точку: на поле и не внутри постройки.
function Sense.standable(point)
	local cx, cz = Grid.ToCell(point)
	if not Grid.InBounds(cx, cz) then
		return false
	end
	return Grid.GetBlocker(cx, cz) == nil
end

-- Точку на поле: ось Y — пол арены (её всё равно выставит толкучка).
function Sense.onFloor(point)
	local cx, cz = Grid.ToCell(point)
	local world = Grid.ToWorld(cx, cz)
	return Vector3.new(point.X, world.Y, point.Z)
end

-- ============================ Цель-точка ============================
--
-- Почти все новые повадки — «пойти туда-то»: в укрытие, к Строителю с ношей, за спину
-- Щитоносцу, к раненому, в засаду. Общий маршрут волны ведёт к столу полем волн, а
-- точка у каждого своя — её ведёт разовый A* в EnemySpawner (режим "point").
--
-- Заявок может быть несколько сразу, поэтому у каждой приоритет: укрытие от огня
-- важнее, чем идти за вожаком. Заявку меньшего приоритета чужая не перебивает.
-- tag — кто поставил: снимает заявку только тот, кто её ставил.
-- stay — дойдя, стоять (по умолчанию). expires — заявка сама гаснет к сроку.
local REPATH_MOVE = 3 -- studs: цель сдвинулась меньше — маршрут не пересчитываем
-- Недостижимую точку не просим снова каждые полсекунды: каждый такой запрос — A* до потолка.
local RETRY_FAILED = 3 -- сек

function Sense.GoTo(state, position, radius, tag, priority, expires)
	priority = priority or 1
	local current = state.goTo
	if current and current.tag == tag and current.failed
		and flat(current.position - position).Magnitude < REPATH_MOVE
		and os.clock() - (current.failedAt or 0) < RETRY_FAILED then
		return false
	end
	if current and current.tag ~= tag and not current.failed
		and (current.priority or 1) > priority then
		return false
	end
	if current and current.tag == tag and not current.failed
		and flat(current.position - position).Magnitude < REPATH_MOVE then
		current.expires = expires
		current.radius = radius
		return true
	end
	state.goTo = {
		position = position,
		radius = radius or 2,
		tag = tag,
		priority = priority,
		expires = expires,
		reached = false,
	}
	state.repath = true
	return true
end

function Sense.ClearGoTo(state, tag)
	local current = state.goTo
	if current and (tag == nil or current.tag == tag) then
		state.goTo = nil
		state.repath = true
	end
end

function Sense.GoToReached(state, tag)
	local current = state.goTo
	return current ~= nil and current.tag == tag and current.reached
end

-- Заявка этого тега не удалась (точка недостижима): механика решает сама, что дальше.
function Sense.GoToFailed(state, tag)
	local current = state.goTo
	return current ~= nil and current.tag == tag and current.failed == true
end

-- ============================ Укрытие ============================
--
-- «Работяга... получает урон — отходит в безопасное место». Безопасное — по порядку:
--   1. за Стеной Строителя: «жуки за ней группируются безопасно» — турель через неё не видит;
--   2. к тем своим, кто уже прячется: так группа и собирается в одном месте;
--   3. прочь от турели за край её радиуса, но не дальше travel — через всю карту не бежит.
function Sense.SafeSpot(enemy, turret, plan)
	local position = enemy:GetPivot().Position
	local from = turret:GetPivot().Position

	local bestWall, wallDistance = nil, plan.search
	for _, wall in EnemyStructures.Near(position, plan.search, "wall") do
		local distance = flat(wall:GetPivot().Position - position).Magnitude
		if distance < wallDistance then
			bestWall, wallDistance = wall, distance
		end
	end
	if bestWall then
		local at = bestWall:GetPivot().Position
		local behind = flat(at - from)
		if behind.Magnitude > 1e-3 then
			local spot = at + behind.Unit * plan.behindWall
			if Sense.standable(spot) then
				return Sense.onFloor(spot), "wall"
			end
		end
	end

	local myCaste = (Sense.dataOf(enemy) or NO_RULES).caste
	local bestMate, mateDistance = nil, plan.search
	for other, otherState in Sense.states do
		if other ~= enemy and otherState.hiding and alive(other) then
			local data = Sense.dataOf(other)
			if data and data.caste == myCaste then
				local distance = flat(other:GetPivot().Position - position).Magnitude
				if distance < mateDistance then
					bestMate, mateDistance = other, distance
				end
			end
		end
	end
	if bestMate then
		return Sense.onFloor(bestMate:GetPivot().Position), "mates"
	end

	local away = flat(position - from)
	if away.Magnitude < 1e-3 then
		return nil
	end
	local gap = Sense.turretRange(turret) + plan.beyond - away.Magnitude
	local travel = math.clamp(gap, plan.minTravel, plan.travel)
	local spot = position + away.Unit * travel
	if Sense.standable(spot) then
		return Sense.onFloor(spot), "away"
	end
	return nil
end

-- ============================ Бегство ============================
--
-- Повторный испуг разведчика (Enemies.Castes[0].rehit): куда бежать, чтобы по нему не били.
-- Перебирает направления и дальности вокруг жука, берёт точку без турелей над ней, подальше
-- от стреляющего и не в ту сторону, куда он уже бежал. Путь до точки должен быть свободен
-- до края поля плюс edge: испуг ни сетки, ни стен не знает (см. fleeConfine в EnemySpawner).
function Sense.FleeSpot(enemy, from, avoidDirection, plan)
	local position = enemy:GetPivot().Position
	local best, bestScore
	local offset = math.random() * math.pi * 2 / plan.directions
	for i = 0, plan.directions - 1 do
		local angle = offset + i * math.pi * 2 / plan.directions
		local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))

		-- Свободный путь считается один раз на направление: самая дальняя точка плюс запас.
		local free = 0
		local reach = plan.distances[#plan.distances] + plan.edge
		while free + plan.step <= reach and Sense.standable(position + direction * (free + plan.step)) do
			free += plan.step
		end

		for _, distance in plan.distances do
			if distance + plan.edge <= free then
				local spot = position + direction * distance
				local score = Sense.coverage(spot) * plan.coverPenalty
					- flat(spot - from).Magnitude
					+ math.random() * plan.jitter
				if avoidDirection and direction:Dot(avoidDirection) > plan.sameDot then
					score += plan.samePenalty
				end
				if not bestScore or score < bestScore then
					best, bestScore = spot, score
				end
			end
		end
	end
	return best and Sense.onFloor(best) or nil
end

-- ============================ Колония ============================
--
-- «Разведчики ищут лабораторию. Нашли — грызут стол.» Пока лабораторию не нашли, они
-- бродят; нашедший докладывает остальным, и через доклад о столе знает вся колония —
-- до конца забега. Хмурый брон «не докладывает данные»: у него нет поля explores.
Sense.colony = { labKnown = false, reportAt = nil, knownAt = nil }

function Sense.ResetColony()
	Sense.colony.labKnown = false
	Sense.colony.reportAt = nil
	Sense.colony.knownAt = nil
end

-- Нашедший разведчик. Доклад доходит до колонии не сразу: report секунд.
function Sense.ReportLab(report)
	local colony = Sense.colony
	if colony.labKnown or colony.reportAt then
		return
	end
	colony.reportAt = os.clock() + report
	print("[Разведчики] лаборатория найдена — докладывают колонии")
end

function Sense.LabKnown()
	local colony = Sense.colony
	if not colony.labKnown and colony.reportAt and os.clock() >= colony.reportAt then
		colony.labKnown = true
		colony.knownAt = os.clock()
		print("[Разведчики] колония знает, где лаборатория")
	end
	return colony.labKnown
end

return Sense
