-- Режимы прицеливания. Каждый — function(towerPosition, range, enemiesFolder, filter) -> враг или nil.
-- Добавить новый режим = добавить запись в Targeting.Modes; TowerBuilder трогать не надо.
-- Враг теперь Model (жук из примитивов), позиция — через GetPivot(), а не .Position.
--
-- filter (задача #53) — ограничения самой турели, одинаковые для всех режимов, чтобы
-- каждый режим не переписывал их у себя:
--   minRange     — слепая зона вблизи себя (Мортира): ближе неё целей для турели нет;
--   targets      — "ground" / "air" / "both" (или nil = все). Летающий виден по атрибуту
--                  Flying, который ставит EnemySpawner по флагу из Enemies;
--   groupRadius  — радиус кучи для strongestGroup (у Мортиры это радиус взрыва);
--   facing / turnSpeed / turnAccel / projectileSpeed / current (задача #70) — куда сейчас
--                  смотрит ствол, как быстро он доворачивается, как быстро летит снаряд и кого
--                  турель ведёт сейчас. Нужно только closestReachable.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local Aiming = require(ReplicatedStorage:WaitForChild("Aiming"))
-- Габариты тела: радиус считается до поверхности жука, а не до его пивота.
local EnemyBody = require(ReplicatedStorage:WaitForChild("EnemyBody"))
-- Остаток пути до выхода — серверная таблица EnemyProgress (раньше атрибут DistanceToExit).
local EnemyProgress = require(ServerScriptService:WaitForChild("EnemyProgress"))
-- Стены Строителя закрывают линию огня (design: alchemy_td_enemies.md, каста 1).
local EnemyStructures = require(ServerScriptService:WaitForChild("EnemyStructures"))

local Targeting = {}

-- ======================== Линия огня ========================
--
-- Турель не стреляет сквозь то, у чего есть коллизия: стены бункера, постройки
-- игрока, Горы, вспученный литосферой пол. Луч идёт от точки выстрела до жука.
--
-- Что луч НЕ считает преградой и почему:
--   — сама стреляющая постройка: луч начинается внутри неё и ткнулся бы в себя же;
--   — сами жуки и трупы: иначе передний жук закрывал бы собой всю колонну, а это
--     отдельная механика Щитоносца, а не свойство любого тела;
--   — снаряды и сам игрок: пробегающий мимо игрок не должен глушить свою же турель.
--
-- Стены Строителя лучом не ловятся вовсе: они без коллизии (сквозь них должен
-- проходить игрок), и их закрывание линии огня считается отдельно (EnemyStructures.BlocksLine).
local sightParams = RaycastParams.new()
sightParams.FilterType = Enum.RaycastFilterType.Exclude
-- Главное слово задачи: преграда — это то, у чего есть коллизия. Заодно это само
-- выкидывает невидимый ArenaFloor: он без коллизии с задачи про бетонный пол.
sightParams.RespectCanCollide = true

-- Список исключений собирается редко и переиспользуется: лучей тысячи в секунду,
-- и новая таблица на каждый из них — мусор для сборщика на ровном месте.
-- Стреляющая постройка подкладывается в конец на время одного луча и тут же снимается.
local sightExclude = {}

local function rebuildExclude()
	table.clear(sightExclude)
	for _, name in { "Enemies", "Corpses", "Projectiles", "EnemyStructures" } do
		local folder = Workspace:FindFirstChild(name)
		if folder then
			table.insert(sightExclude, folder)
		end
	end
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(sightExclude, player.Character)
		end
	end
end

rebuildExclude()
Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(rebuildExclude)
	rebuildExclude()
end)
Players.PlayerRemoving:Connect(rebuildExclude)
for _, player in Players:GetPlayers() do
	player.CharacterAdded:Connect(rebuildExclude)
end
-- Папки трупов и снарядов заводятся лениво, уже после загрузки этого модуля.
Workspace.ChildAdded:Connect(function(child)
	if child.Name == "Corpses" or child.Name == "Projectiles" or child.Name == "EnemyStructures" then
		rebuildExclude()
	end
end)

-- Видна ли точка из точки. shooter — стреляющая постройка (исключается из луча).
function Targeting.HasLineOfSight(from, to, shooter)
	local delta = to - from
	if delta.Magnitude < 1e-3 then
		return true
	end
	if shooter then
		table.insert(sightExclude, shooter)
	end
	sightParams.FilterDescendantsInstances = sightExclude
	local hit = Workspace:Raycast(from, delta, sightParams)
	if shooter then
		table.remove(sightExclude)
	end
	return hit == nil
end

-- Окоп Окопщика: «жук в окопе ниже линии огня турелей, радиус поражения резко
-- падает». Резко — это втрое: достать его может только тот, кто стоит совсем рядом.
-- Это НЕ иммунитет: ближняя турель по-прежнему бьёт его как всех.
local TRENCH_RANGE_SCALE = 0.35

-- Живой ли враг и того ли он типа, по которому турель вообще работает.
local function suitable(enemy, targets)
	if not (enemy:IsA("Model") and enemy.PrimaryPart) then
		return false
	end
	if (enemy:GetAttribute("HP") or 0) <= 0 then
		return false
	end
	-- Мимик замаскирован, Роевик под полом: «турели не распознают как цель».
	-- Один атрибут на обоих: с точки зрения турели разницы между ними нет.
	if enemy:GetAttribute("Hidden") then
		return false
	end
	if targets == "ground" then
		return not enemy:GetAttribute("Flying")
	elseif targets == "air" then
		return enemy:GetAttribute("Flying") == true
	end
	return true
end

local function enemiesInRange(towerPosition, range, enemiesFolder, filter)
	local targets = filter and filter.targets
	local minRange = filter and filter.minRange
	-- Сектор обстрела (Инжектор): arc — ПОЛОВИНА сектора в радианах, arcCenter —
	-- мировой угол фронта постройки. Считается здесь, а не в каждом режиме по отдельности:
	-- турель, которая не может довернуться на врага, не должна выбирать его целью
	-- ни в одном режиме и не должна задевать его площадью.
	local arc = filter and filter.arc
	local arcCenter = filter and filter.arcCenter
	local list = {}
	for _, enemy in enemiesFolder:GetChildren() do
		if suitable(enemy, targets) then
			local position = enemy:GetPivot().Position
			-- Габариты, а не точка (правило физики из дизайна, раздел 2.3): в радиус
			-- попадает тот, чьё ТЕЛО его задело. Толстого жука задеть легче, Мини — труднее;
			-- это осознанная плата АОЕ против мелочи.
			--
			-- Слепая зона — по-прежнему по центру: она про то, куда турель физически не может
			-- опустить ствол, и жук, заехавший в неё краем корпуса, целью быть не перестаёт.
			local surface, distance = EnemyBody.SurfaceDistance(towerPosition, enemy)

			-- Жук в окопе виден втрое ближе, чем обычный. Атрибут ставит сам жук по полу
			-- под ногами (см. EnemyBehavior.Ground), а не турель поиском окопов на каждой цели.
			local reach = enemy:GetAttribute("InTrench") and range * TRENCH_RANGE_SCALE or range

			if surface <= reach and not (minRange and distance < minRange) then
				local inArc = true
				if arc and arcCenter then
					local angle = Aiming.AngleTo(towerPosition, position)
					-- Цель ровно над башней (angle — nil) в сектор не попадает:
					-- горизонтального направления на неё нет вовсе.
					inArc = angle ~= nil and math.abs(Aiming.Delta(arcCenter, angle)) <= arc
				end
				-- Тень: «турели реагируют с задержкой. Не иммунитет. Не маскировка.»
				-- Счёт идёт от первого момента, когда его вообще увидели: держать свой
				-- таймер на каждую пару «турель-жук» значило бы таблицу на сотни записей
				-- ради того же самого ощущения — он проскакивает первую секунду любого огня.
				local shadowDelay = enemy:GetAttribute("ShadowDelay")
				if shadowDelay and inArc then
					local seen = enemy:GetAttribute("SeenAt")
					if not seen then
						enemy:SetAttribute("SeenAt", os.clock())
						inArc = false
					elseif os.clock() - seen < shadowDelay then
						inArc = false
					end
				end

				-- Стена Строителя между турелью и жуком: «жуки за ней группируются
				-- безопасно». Проверка последней: она самая дорогая из всех, и делать её
				-- для того, кто и так отсеян, незачем.
				if inArc and EnemyStructures.BlocksLine(towerPosition, position) then
					inArc = false
				end

				-- Линия огня по всему, у чего есть коллизия. Самая дорогая проверка из всех,
				-- поэтому самой последней — для тех, кто прошёл всё остальное.
				-- Включается только тем, кто её просит (filter.lineOfSight): взрыв навесного
				-- снаряда бьёт по площади вокруг воронки, а не «видит» цель откуда-то.
				if inArc and filter and filter.lineOfSight
					and not Targeting.HasLineOfSight(towerPosition, position, filter.shooter) then
					inArc = false
				end

				if inArc then
					table.insert(list, enemy)
				end
			end
		end
	end
	return list
end

-- Все цели в радиусе сразу, а не одна выбранная. Нужно тем, кто не целится вовсе:
-- площадным турелям (Испаритель, Бур, Центрифуга) и взрыву миномётного снаряда.
-- Тот же фильтр земля/воздух, что и у прицеливания: турель не может задеть площадью того,
-- в кого не может целиться.
function Targeting.EnemiesInRange(center, radius, enemiesFolder, filter)
	return enemiesInRange(center, radius, enemiesFolder, filter)
end

Targeting.Modes = {}

-- Ближайший к башне.
Targeting.Modes.closest = function(towerPosition, range, enemiesFolder)
	local best, bestValue = nil, math.huge
	for _, enemy in ipairs(enemiesInRange(towerPosition, range, enemiesFolder)) do
		local distance = (enemy:GetPivot().Position - towerPosition).Magnitude
		if distance < bestValue then
			best, bestValue = enemy, distance
		end
	end
	return best
end

-- Ближайший из тех, на кого турель успеет довернуться (задача #70).
--
-- Обычный closest берёт того, кто ближе геометрически, и не спрашивает, куда сейчас смотрит
-- ствол. У медленно поворачивающейся башни это выливается в метания: пока ствол едет
-- к «ближайшему» за спиной, ближайшим успевает стать другой, и турель не стреляет вовсе.
--
-- Поэтому цель сначала проверяется на достижимость: за то время, что уйдёт на доворот,
-- жук не должен успеть выйти из радиуса. Куда он уйдёт, считается по атрибуту Velocity —
-- тем же способом, что и упреждение снаряда (Projectile.PredictAim), и с той же оговоркой:
-- жук, который свернёт за угол, посчитан прямолинейно.
--
-- Если недостижимы все, цель всё равно нужна — берётся та, до которой доворачиваться
-- меньше всего: пусть башня едет к ней, а не стоит столбом.
--
-- Нет facing — режим неотличим от closest, и это не ошибка: так он ведёт себя у турели
-- без доворота (нет turnSpeed в Towers).
-- Насколько новая цель должна быть лучше ведомой, чтобы турель переключилась, в секундах.
-- Ноль означал бы пересмотр выбора каждую проверку — именно от этого башня и мечется.
local SWITCH_MARGIN = 0.75

-- Штраф тому, кто успеет уйти из радиуса раньше, чем ствол до него доедет. Не выброс из
-- списка, а штраф: если все цели такие, крутиться всё равно надо к лучшей из них.
local UNREACHABLE_PENALTY = 10

-- Не просто ближайший, а тот, по кому турель раньше всего сможет попасть (задача #70).
--
-- Обычный closest не спрашивает, куда смотрит ствол. У башни, которая доворачивается
-- секундами, это выливается в метания: в толпе «ближайший» меняется быстрее, чем ствол
-- успевает доехать хоть до кого-то. Замерено на живой волне: 3 выстрела за 12 секунд
-- при темпе выстрел/сек и 11 перескоков цели больше чем на 45°.
--
-- Оценка цели — это ВРЕМЯ до попадания: доворот плюс полёт снаряда. Обе половины в
-- секундах, складывать их можно. Отсюда и «не просто ближе»: жук прямо по курсу вдвое
-- дальше выгоднее ближнего за спиной, если на того ещё полторы секунды крутиться.
--
-- Сверх этого турель ВЕДЁТ выбранную цель, а не пересматривает выбор каждую проверку:
-- смена — только когда прежняя цель пропала (мертва, вышла из радиуса) или когда новая
-- лучше её больше чем на SWITCH_MARGIN секунд. Одна оценка без этого от метаний не спасает:
-- цели движутся, и лучшая меняется по десять раз в секунду.
--
-- Нет facing — режим неотличим от closest, и это не ошибка: так он ведёт себя у турели
-- без доворота (нет turnSpeed в Towers).
Targeting.Modes.closestReachable = function(towerPosition, range, enemiesFolder, filter)
	local facing = filter and filter.facing
	if not facing then
		return Targeting.Modes.closest(towerPosition, range, enemiesFolder, filter)
	end

	local flightSpeed = filter.projectileSpeed or 60
	local best, bestScore = nil, math.huge
	local current, currentScore = nil, math.huge

	for _, enemy in ipairs(enemiesInRange(towerPosition, range, enemiesFolder, filter)) do
		local position = enemy:GetPivot().Position
		local angle = Aiming.AngleTo(towerPosition, position)
		if angle then
			local distance = (position - towerPosition).Magnitude
			local turn = Aiming.TurnTime(Aiming.Delta(facing, angle), filter.turnSpeed, filter.turnAccel)

			-- Успеет ли турель довернуться, пока цель ещё в радиусе. Куда жук уйдёт,
			-- считается по атрибуту Velocity — так же, как упреждение снаряда
			-- (Projectile.PredictAim), и с той же оговоркой: свернувший за угол посчитан
			-- прямолинейно.
			local velocity = enemy:GetAttribute("Velocity") or Vector3.zero
			local reachable = ((position + velocity * turn) - towerPosition).Magnitude <= range

			local score = turn + distance / flightSpeed + (reachable and 0 or UNREACHABLE_PENALTY)
			if score < bestScore then
				best, bestScore = enemy, score
			end
			if enemy == filter.current then
				current, currentScore = enemy, score
			end
		end
	end

	if current and currentScore <= bestScore + SWITCH_MARGIN then
		return current
	end
	return best
end

-- Ближе всех к выходу — головной враг колонны, то есть наименьший остаток пути (EnemyProgress).
-- Его пишет EnemySpawner.moveThroughArena — это остаток пути по маршруту, а не геометрическая
-- близость к выходу. Раньше здесь была пройденная дистанция (Progress); в лабиринте она лжёт —
-- жук, которого увели длинным крюком, прошёл больше всех, а до выхода ему дальше всех.
Targeting.Modes.first = function(towerPosition, range, enemiesFolder)
	local best, bestValue = nil, math.huge
	for _, enemy in ipairs(enemiesInRange(towerPosition, range, enemiesFolder)) do
		local toExit = enemy:GetAttribute("DistanceToExit") or math.huge
		if toExit < bestValue then
			best, bestValue = enemy, toExit
		end
	end
	return best
end

-- Дальше всех от выхода (наибольший остаток пути, EnemyProgress).
Targeting.Modes.last = function(towerPosition, range, enemiesFolder)
	local best, bestValue = nil, -math.huge
	for _, enemy in ipairs(enemiesInRange(towerPosition, range, enemiesFolder)) do
		local toExit = enemy:GetAttribute("DistanceToExit") or math.huge
		if toExit > bestValue then
			best, bestValue = enemy, toExit
		end
	end
	return best
end

-- С наибольшим HP.
--
-- Фильтр передаётся дальше, в отличие от соседних простых режимов: по этому режиму
-- целится Инжектор, а у него есть сектор обстрела (Towers.Injector.arc), и без фильтра
-- он выбирал бы целью того, кого физически не может достать.
Targeting.Modes.strongest = function(towerPosition, range, enemiesFolder, filter)
	local best, bestValue = nil, -math.huge
	for _, enemy in ipairs(enemiesInRange(towerPosition, range, enemiesFolder, filter)) do
		local hp = enemy:GetAttribute("HP") or 0
		if hp > bestValue then
			best, bestValue = enemy, hp
		end
	end
	return best
end

-- Самая крепкая куча, а не самый крепкий жук (Мортира, задача #53): целью становится
-- тот, вокруг кого в радиусе взрыва суммарно больше всего HP. Снаряд накрывает площадь,
-- и одиночный толстяк в чистом поле ему хуже, чем плотная группа помельче.
--
-- Куча считается по всем подходящим жукам в радиусе range + groupRadius, а не только
-- по тем, кто сам годится в цели: взрыв не спрашивает, в радиусе ли сосед у турели и не в
-- слепой ли он зоне — он просто бьёт по кругу вокруг воронки.
Targeting.Modes.strongestGroup = function(towerPosition, range, enemiesFolder, filter)
	local groupRadius = (filter and filter.groupRadius) or 0
	local candidates = enemiesInRange(towerPosition, range, enemiesFolder, filter)
	if #candidates == 0 then
		return nil
	end

	-- Соседи берутся без minRange (слепая зона — ограничение прицела, а не взрыва),
	-- но с тем же фильтром земля/воздух.
	local crowd = enemiesInRange(towerPosition, range + groupRadius, enemiesFolder, {
		targets = filter and filter.targets,
	})

	local best, bestValue = nil, -math.huge
	for _, enemy in ipairs(candidates) do
		local center = enemy:GetPivot().Position
		local total = 0
		for _, other in ipairs(crowd) do
			if (other:GetPivot().Position - center).Magnitude <= groupRadius then
				total += other:GetAttribute("HP") or 0
			end
		end
		if total > bestValue then
			best, bestValue = enemy, total
		end
	end

	return best
end

-- Находит цель по режиму, заданному в таблице башни (Towers[тип].targeting).
-- Неизвестный режим — тихий фолбэк на closest.
function Targeting.FindTarget(towerPosition, range, enemiesFolder, mode, filter)
	local fn = Targeting.Modes[mode] or Targeting.Modes.closest
	local target = fn(towerPosition, range, enemiesFolder, filter)
	local distance = target and (target:GetPivot().Position - towerPosition).Magnitude
	return target, distance
end

return Targeting
