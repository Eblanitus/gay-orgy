local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local Enemies = require(ReplicatedStorage:WaitForChild("Enemies"))
local Towers = require(ReplicatedStorage:WaitForChild("Towers")) -- только для flyToTurret: отличить турели от Стены/Горы по fireRate
local Matter = require(ServerScriptService:WaitForChild("Matter"))
local Plutonium = require(ServerScriptService:WaitForChild("Plutonium"))
local ProfileStats = require(ServerScriptService:WaitForChild("ProfileStats"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local EnemyDiedRemote = Remotes:WaitForChild("EnemyDied")
local DamageDealtRemote = Remotes:WaitForChild("DamageDealt")

local Grid = require(ServerScriptService:WaitForChild("Grid"))
local Crowd = require(ServerScriptService:WaitForChild("Crowd"))
local EnemyModel = require(ReplicatedStorage:WaitForChild("EnemyModel"))
local EnemyProgress = require(ServerScriptService:WaitForChild("EnemyProgress"))
local EnemyBody = require(ReplicatedStorage:WaitForChild("EnemyBody"))
local Corpses = require(ServerScriptService:WaitForChild("Corpses"))
local PhysicsFX = require(ReplicatedStorage:WaitForChild("PhysicsFX"))
-- Касты и особые механики (design: alchemy_td_enemies.md) — всё, что различает виды.
-- Здесь осталось только общее: ходьба по маршруту, грызня, перелезание, смерть.
local EnemyBehavior = require(ServerScriptService:WaitForChild("EnemyBehavior"))
local LabTable = require(ServerScriptService:WaitForChild("LabTable"))
local EnemyStructures = require(ServerScriptService:WaitForChild("EnemyStructures"))

local enemiesFolder = Workspace:WaitForChild("Enemies")
local towersFolder = Workspace:WaitForChild("Towers")

local SPAWN_INTERVAL = 0.3 -- сек между спавном соседних юнитов в группе
local SCATTER = 1.2 -- studs, разброс от точек маршрута (проход 4 studs — больше не влезает)
-- Тела непроницаемы (см. Crowd), поэтому появиться в проломе, где ещё стоит предыдущий,
-- нельзя: новый ждёт, пока место освободится (опрос раз в SPAWN_POLL), а не дольше
-- SPAWN_WAIT_MAX — потом ищет ближайшее свободное рядом (Crowd.FindFree).
local SPAWN_POLL = 0.1
local SPAWN_WAIT_MAX = 4
-- Точка маршрута засчитана, когда центр жука ближе этой доли радиуса его тела,
-- а промежуточная — ещё и когда он уже за линией точки (поперёк следующего отрезка), но не дальше WAYPOINT_PASS_BODIES
-- радиусов от неё. Точно встать в точку центром несжимаемое тело в толпе не может:
-- её занимает сосед, и вся волна сходилась к одному месту и стояла.
local WAYPOINT_REACH_SHARE = 1
local WAYPOINT_PASS_BODIES = 4
local ENEMY_Y = 1.5 -- studs над полом: на этой высоте пивота ноги жука касаются земли
local REPATH_INTERVAL = 0.25 -- сек; чаще пересчитывать маршрут незачем даже при активной стройке
local VELOCITY_EPSILON = 0.5 -- studs/сек: насколько должна измениться скорость, чтобы переписать атрибут
local FACEHUGGER_HEIGHT = 3.6 -- studs над пивотом турели — над стеклянной сферой Колбы, не внутри неё
-- Кровь на карте. Раненый жук капает не чаще BLEED_INTERVAL: без паузы тиковые
-- турели (Испаритель — 5 тиков/сек) заливали бы пол целиком за одну волну. Смерть даёт
-- отдельное большое пятно с брызгами — именно оно читается как «здесь кого-то убили».
local BLEED_INTERVAL = 0.5
local BLEED_SIZE = 0.7 -- studs, диаметр капли от попадания
local DEATH_SPLAT_SIZE = 2.2 -- studs, диаметр пятна на месте смерти
local DEATH_SPLAT_DROPS = 4 -- брызг вокруг него

-- Атрибут Look переписывается, когда желаемый взгляд ушёл больше чем на ~3°: мельче голова
-- жука не показывает, а писать его каждый кадр значит слать его всем клиентам каждый кадр.
local LOOK_RESEND_COS = math.cos(math.rad(3))

local FACEHUGGER_ATTACH_RANGE = 2 -- studs: на этом расстоянии до турели Лицехват считается «долетел и присосался»

-- Плоская часть вектора: маршрут, повороты и дистанции считаются только по XZ. Высотой
-- жука распоряжается толкучка (Crowd) — в тесноте он едет на спине соседа, и если мерить
-- вместе с высотой, залезший наверх поехал бы по диагонали вниз, к точке маршрута
-- у самой земли.
local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

local EnemySpawner = {}

-- Назначается снаружи (например, из WaveRunner), чтобы считать прорывы. Может оставаться nil.
EnemySpawner.OnBreach = nil

-- Модель врага на сервере — только для замера. Видимое тело (шаблон с лапами или примитив)
-- собирается общим EnemyModel, габариты снимаются в атрибуты (BodyRadius/BodyHalfHeight,
-- FootRadius/FootFront/FootBack), и модель раздевается до невидимого якоря: всё, что решает
-- сервер — маршрут, толкучка, прицел, попадания, зоны, — читает пивот, атрибуты и эти числа.
-- Картинку и походку рисует клиент (StarterPlayerScripts.EnemyRender) по атрибутам Type и Scale.
-- Раньше сервер двигал все детали каждого жука каждый кадр, и их репликация забивала канал.
local function buildEnemyModel(enemyData)
	local model = EnemyModel.Build(enemyData)
	EnemyBody.Footprint(model)
	return EnemyModel.Strip(model)
end

-- Ведёт enemy к выходу по маршруту, который ищет Grid, со скоростью из таблицы врага,
-- урезанной атрибутом SlowPercent (его ставит Effects). offset — постоянное смещение от центров
-- клеток, чтобы группа не шла строго в одну точку.
--
-- Шаг по маршруту — это только заявка: куда жук встанет на самом деле, решает Crowd —
-- рядом стоят другие жуки, и пройти сквозь них нельзя. Оттуда же берётся высота:
-- в давке жук залезает соседу на спину.
--
-- Маршрут пересчитывается, когда меняется занятость клеток (сигнал Grid.Changed), но не чаще
-- REPATH_INTERVAL: пересчёт на каждую поставленную башню сразу для всей волны — заметная нагрузка.
--
-- Грызня: если в следующую точку маршрута жуку мешает встать постройка (Grid.GetBlocker —
-- это не «клетка занята», а «тело жука не влезает»: клетка теперь впятеро мельче его
-- самого), жук останавливается и бьёт её,
-- пока не сломает. Сам он клетку не освобождает — это делает сама постройка при HP <= 0
-- (см. TowerBuilder), после чего Grid.Changed поднимает dirty и маршрут пересчитывается уже сквозь
-- пролом. Поэтому же жук сразу трогается, если постройку снёс кто-то другой.
--
-- Запутывание (Туман): пока не истёк ConfusedUntil, жук идёт не по маршруту, а в сторону
-- из ConfusedDirection (оба атрибута ставит Effects при попадании): клетку маршрута не
-- проходит и постройку не грызёт, но и не стоит на месте — это не стан.
--
-- Стан (Лёд, засыхание Глины) — атрибут StunnedUntil, тоже от Effects: жук не идёт, не грызёт
-- и не поворачивается. Проверяется раньше запутывания: стан сильнее, и станенный жук
-- стоит, а не бродит. Грызню же урезают AttackSlowPercent (Холод) и Weakened (Кислота).
--
-- Пишет в EnemyProgress (серверная таблица, не атрибут — клиенту она не нужна) — сколько ещё
-- идти до выхода по текущему маршруту. По нему
-- целятся режимы first/last в Targeting. Пройденная дистанция (прежний Progress) в лабиринте
-- не годится: жук, которого увели длинным крюком, прошёл больше всех, а до выхода ему дальше всех.
--
-- Пишет атрибут Velocity — текущую скорость со знаком направления. По ней снаряды берут
-- упреждение (см. Projectile.PredictAim): модель врага анкорнута и двигается через PivotTo,
-- своей физической скорости у неё нет, и спросить её больше не у кого.
--
-- Если enemy умирает в пути (Parent становится nil), просто прекращаем движение без вызова onBreach.
-- План перелезания: вверх по преграде, поверху и вниз с другой стороны. Собирается
-- один раз в момент, когда жук упёрся, и дальше просто отыгрывается по таймеру.
--
-- Таймер, а не поиск опоры каждый кадр — это прямое требование дизайна (раздел 1.1):
-- выбранный способ всегда завершается, жук не может застрять на весу или бесконечно
-- пересчитывать. Поэтому же разрушенная по дороге преграда ничего не меняет: жук
-- доводит движение до конца и просто оказывается по ту сторону.
--
-- Точка выхода — первая точка маршрута, где нет НИКАКОЙ постройки, а не просто
-- другая. Следы соседних стен перекрываются, и с проверкой «другая постройка» жук слезал
-- посреди сплошной линии и тут же лез снова — одна стена читалась как две (замечено
-- живым прогоном: два «лезет через» подряд у одного и того же жука).
--
-- По дороге берётся самая высокая из пересекаемых построек: жук ползёт поверх всего,
-- что под ним. Если хоть одна из них ему не по зубам (выше climbHeight или вовсе без
-- высоты) — перелезания нет, остаётся грызть: иначе низкая стенка впритык к турели
-- стала бы пандусом сквозь турель.
local function planClimb(position, points, cells, index, climbHeight, climbSpeed, speed)
	local exitPoint = nil
	local peak = 0

	for i = index, #points do
		local blocker = Grid.GetBlocker(cells[i].x, cells[i].z)
		if not blocker then
			exitPoint = points[i]
			break
		end

		local height = blocker:GetAttribute("Height")
		if not height or height > climbHeight then
			return nil
		end
		peak = math.max(peak, height)
	end

	-- Маршрут кончается внутри преграды — лезть некуда, остаётся грызть.
	if not exitPoint or peak <= 0 then
		return nil
	end

	local flatDelta = flat(exitPoint - position)
	if flatDelta.Magnitude < 1e-3 then
		return nil
	end

	local horizontal = flatDelta.Unit
	local topY = position.Y + peak
	local function overhead(distance)
		local at = position + horizontal * distance
		return Vector3.new(at.X, topY, at.Z)
	end

	-- Подъём почти отвесный, с небольшим наклоном вперёд: жук ползёт по СТЕНКЕ, а не
	-- наискосок сквозь преграду. Первая версия вела его сразу на треть пути к выходу, и тело
	-- полподъёма ехало внутри мешков — видно на плейтесте.
	local span = flatDelta.Magnitude
	local lean = math.min(1, span * 0.35)
	local topEntry, topExit = overhead(lean), overhead(span - lean)
	local vertical = math.max(peak / climbSpeed, 0.05)
	local across = math.max((topExit - topEntry).Magnitude / math.max(speed, 0.1), 0.05)

	return {
		height = peak,
		horizontal = horizontal,
		time = 0,
		leg = 1,
		-- «Верх» жука на подъёме и спуске — это сторона ОТ стены: брюхом он прижат
		-- к поверхности, мордой смотрит вверх. Наверху он просто идёт по крыше.
		legs = {
			{ from = position, to = topEntry, duration = vertical, up = -horizontal },
			{ from = topEntry, to = topExit, duration = across, up = Vector3.yAxis },
			{ from = topExit, to = exitPoint, duration = vertical, up = -horizontal },
		},
	}
end

-- Один кадр перелезания. Возвращает точку, куда встать, направление движения и его
-- «верх» — либо nil, если всё уже кончилось. Отрезок может закончиться и посреди кадра:
-- остаток времени перетекает в следующий, а не теряется — иначе на просадке кадров
-- подъём шёл бы дольше, чем посчитал поиск пути.
local function advanceClimb(climb, dt)
	climb.time += dt

	local leg = climb.legs[climb.leg]
	while leg and climb.time >= leg.duration do
		climb.time -= leg.duration
		climb.leg += 1
		leg = climb.legs[climb.leg]
	end

	if not leg then
		return nil
	end

	local fraction = math.clamp(climb.time / leg.duration, 0, 1)
	local direction = leg.to - leg.from
	if direction.Magnitude < 1e-3 then
		direction = climb.horizontal
	end

	-- Скорость отрезка нужна атрибуту Velocity: по нему снаряды берут упреждение,
	-- а лезущий жук движется со своей скоростью подъёма, а не со скоростью ходьбы.
	return leg.from:Lerp(leg.to, fraction), direction.Unit, leg.up, direction.Magnitude / leg.duration
end

local function moveThroughArena(enemy, enemyData, offset, onBreach, state)
	-- Высота пивота: у шаблонного жука ноги короче примитивных, он едет ниже
	-- (см. RideHeight в EnemySpawner.buildTemplateModel/buildEnemyModel). Атрибут несёт
	-- фактическую высоту для ЭТОГО клона (у Мини — от случайного scaleRange, не общая
	-- для типа), enemyData.rideHeight/ENEMY_Y — только запасной вариант, если атрибут
	-- почему-то не выставлен. Маршруту высота всё равно — он считает только XZ,
	-- высоту каждому подъёму выдаёт толкучка (см. Crowd).
	local lift = Vector3.new(0, enemy:GetAttribute("RideHeight") or enemyData.rideHeight or ENEMY_Y, 0)

	local speed = enemyData.speed
	local chewDamage = enemyData.chewDamage or 0
	local chewRate = enemyData.chewRate or 1
	local chewDps = chewDamage * chewRate

	-- Профиль преодоления: им считается маршрут (Grid.GetRoute) и им же решается, что делать
	-- с преградой, в которую жук упёрся (Grid.Crossing). Один объект на обоих нарочно:
	-- разойдись решение поиска пути и решение на месте — и маршрут был бы посчитан по
	-- перелезанию, а жук вставал бы грызть.
	local profile = {
		chewDps = chewDps,
		climbSpeed = enemyData.climbSpeed or 0,
		climbHeight = enemyData.climbHeight or 0,
	}

	-- Идущее перелезание (см. planClimb). Пока оно не кончилось, жук не идёт по маршруту
	-- и не грызёт — он занят преградой.
	local climb = nil

	-- Куда ведёт текущий маршрут: "table", "exit", "perimeter" или "turret". От этого
	-- зависит, что случится, когда жук дойдёт до конца (см. EnemyBehavior.Arrived).
	local goalMode = "exit"

	-- Половина длины тела: на столько жук не доходит до стола, чтобы грызть его край,
	-- а не стоять в его середине. Гигант берёт стол с большего расстояния, чем Мини.
	local bodyReach = 1.7 * (enemy:GetAttribute("Scale") or enemyData.scale or 1)

	local points -- мировые точки текущего маршрута
	local cells -- те же точки в клетках: по ним видно, во что жук упёрся
	local remaining -- остаток пути от каждой точки до выхода
	local index = 1
	local dirty = true
	local lastRepath = 0
	local lastChew = 0

	-- Куда жук смотрит. Поворот теперь отделён от шага: толкучка двигает жука и в те кадры,
	-- когда сам он стоит (грызёт, упёрся в соседа), а собственного направления шага в такой
	-- кадр нет.
	local heading = Vector3.new(0, 0, 1)

	-- Был ли жук запутан в прошлом кадре: на переходе «запутан → очухался» надо снять
	-- визуальную метку и пересчитать маршрут — и то, и другое ровно один раз, а не каждый кадр.
	local wasConfused = false

	-- То же самое для стана, но без пересчёта маршрута: станенный жук с маршрута
	-- не сходит — он просто по нему не идёт.
	local wasStunned = false

	-- Атрибут переписывается не каждый кадр, а по заметному изменению: он реплицируется всем
	-- клиентам, а упреждению хватает грубой скорости — 60 обновлений в секунду на каждого жука
	-- волны были бы трафиком ни за что.
	local lastVelocity = Vector3.zero

	local function setVelocity(velocity)
		if (velocity - lastVelocity).Magnitude > VELOCITY_EPSILON then
			lastVelocity = velocity
			enemy:SetAttribute("Velocity", velocity)
		end
	end

	local connection = Grid.Changed.Event:Connect(function()
		dirty = true
	end)

	local function rebuild()
		local cx, cz = Grid.ToCell(enemy:GetPivot().Position)

		-- Куда идти, решает каста (design: alchemy_td_enemies.md): разведчики и солдаты —
		-- к лаборатории, Хмурый брон — по периметру, группа работяг — на турель.
		local goalX, goalZ, mode = EnemyBehavior.Goal(enemy, enemyData, state)
		goalMode = mode

		local path
		if mode == "turret" then
			-- Точечная цель ОДНОГО жука — отдельный A*, а не поле волн: поле на 75 тысяч
			-- клеток стоит около 120 мс, и заводить его под каждую турель значило бы вешать
			-- сервер на каждую смену фокуса. Таких жуков единицы, а не вся волна.
			path = Grid.FindPath(cx, cz, goalX, goalZ, profile)
		else
			-- Общая цель (стол, выход, угол периметра) — поле волн: оно считается один раз
			-- на всю волну, и первый спросивший после смены занятости платит за всех.
			path = Grid.GetRouteTo(cx, cz, profile, goalX, goalZ)
		end

		if not path then
			-- Пути к выходу нет совсем — идём к ближайшей постройке (правило из ТЗ).
			local nearest = Grid.FindNearestBuilding(cx, cz)
			path = nearest and Grid.FindPath(cx, cz, nearest.x, nearest.z, profile)
		end

		if not path then
			points, cells, remaining = nil, nil, nil
			return
		end

		-- Маршрут по мелкой сетке — три сотни клеток по 0.8 студа, и почти все они
		-- лежат на прямой. Жуку нужны только точки излома и та, на которой начинается
		-- грызня (см. Grid.Simplify): остальные — это Vector3 на каждую клетку каждого жука
		-- на каждый пересчёт, то есть мусор для сборщика на ровном месте.
		path = Grid.Simplify(path)

		points, cells = {}, path
		for i, cell in path do
			points[i] = Grid.ToWorld(cell.x, cell.z) + lift + offset
		end

		remaining = { [#points] = 0 }
		for i = #points - 1, 1, -1 do
			remaining[i] = remaining[i + 1] + (points[i + 1] - points[i]).Magnitude
		end

		-- Первая точка — центр клетки, в которой жук уже стоит: возвращаться к ней незачем.
		index = math.min(2, #points)
	end

	-- Затухание толчка (доля накопленного смещения в секунду). Не баланс, а ощущение:
	-- сама сила отдачи и притяжения живёт в таблице элементов, а здесь только то, за сколько
	-- кадров жук её отъезжает. Мгновенный перенос читался бы телепортом и ломал бы толкучку.
	local PUSH_DECAY = 8

	while enemy.Parent do
		local dt = RunService.Heartbeat:Wait()
		if not enemy.Parent then
			break
		end

		local now = os.clock()
		-- Цель сменилась не из-за стройки, а по приказу Координатора или потому, что вышла
		-- группа работяг (см. EnemyBehavior). Занятость клеток при этом не меняется, и
		-- Grid.Changed не срабатывает — пометить маршрут устаревшим некому, кроме этого флага.
		if state.repath then
			state.repath = false
			dirty = true
			lastRepath = 0
		end

		if dirty and now - lastRepath >= REPATH_INTERVAL then
			rebuild()
			lastRepath = now
			dirty = points == nil -- маршрута не нашлось — пробуем снова на следующем интервале
		end

		if points then
			-- Маршрутная точка, а НЕ пивот модели. Видимое тело качается вокруг маршрута
			-- (его несут ноги, см. EnemyGait.Step), и читать эту качку обратно в маршрут нельзя:
			-- смещение копилось бы кадр за кадром и уводило жука с дорожки.
			local position = state.pathPosition or enemy:GetPivot().Position
			local blocker = Grid.GetBlocker(cells[index].x, cells[index].z)
			local desired = position

			-- Пол под ногами: хитин ускоряет, окоп прячет от турелей. Спрашивается четыре
			-- раза в секунду, а не каждый кадр: конструкций на поле бывают десятки, и полный
			-- проход по ним на каждого жука шестьдесят раз в секунду ничего не добавляет.
			if now - (state.lastGround or 0) >= 0.25 then
				state.lastGround = now
				state.groundScale = EnemyBehavior.Ground(enemy, state)
			end
			local groundScale = state.groundScale or 1

			-- Дошёл ли до стола. Стол не занимает клеток сетки (см. LabTable) — именно
			-- поэтому «упёрся в него» — это расстояние, а не blocker.
			local atTable = goalMode == "table" and LabTable.IsAlive()
				and (position - LabTable.Position()).Magnitude <= LabTable.REACH + bodyReach

			-- Что жук делает по своей касте и трейтам: идёт, отходит или стоит.
			local behavior = EnemyBehavior.State(enemy, enemyData, state)

			-- Грызущего не сдвигает отдача (см. Effects.applyKnockback): он держится за постройку
			-- жвалами. Признак ставится здесь же, где решается, есть ли перед ним преграда,
			-- и только на смене состояния: атрибут реплицируется, и писать его каждый кадр
			-- значило бы слать его всем клиентам шестьдесят раз в секунду на каждого жука.
			local chewing = blocker ~= nil and not climb
			if chewing ~= (enemy:GetAttribute("Chewing") or false) then
				enemy:SetAttribute("Chewing", chewing)
			end

			-- Поза, которую отыгрывают ноги в этом кадре (см. EnemyGait), и то, куда жук
			-- развёрнут телом. На земле «верх» у него мировой, на стене — сама стена.
			local pose = "walk"
			local facing = heading
			local facingUp = Vector3.yAxis

			-- Стан (Лёд, засыхание Глины): срок ставит Effects, а гасит метку этот цикл —
			-- он и так смотрит на жука каждый кадр, а тик-цикл эффектов для секундных сроков груб.
			local stunned = now < (enemy:GetAttribute("StunnedUntil") or 0)
			if wasStunned and not stunned then
				enemy:SetAttribute("Stunned", false)
			end
			wasStunned = stunned

			-- Запутывание (Туман): срок и сторону ставит Effects, а ведёт жука этот цикл:
			-- окно блуждания короче секунды, а тик-цикл эффектов идёт раз в четверть секунды.
			local confused = now < (enemy:GetAttribute("ConfusedUntil") or 0)
			if wasConfused and not confused then
				enemy:SetAttribute("Confused", false)
				-- Пока жука водило, он сошёл с маршрута: путь считается заново от того места,
				-- где он очухался, а не ведёт его назад к той точке, куда он шёл до тумана.
				dirty = true
			end
			wasConfused = confused

			-- Вертикальный интеллект: жук упёрся в постройку — что дешевле, перелезть или
			-- прогрызть? Считает это Grid.Crossing — тот же расчёт, по которому посчитан сам
			-- маршрут, поэтому решение на месте не может разойтись с решением поиска пути.
			-- Для Мини climb не выпадет никогда (стена выше его climbHeight) — он либо обойдёт
			-- по маршруту, либо встанет грызть, как и до задачи.
			if blocker and not climb and not stunned and not confused then
				local mode = Grid.Crossing(blocker, profile)
				if mode == "climb" then
					climb = planClimb(position, points, cells, index,
						profile.climbHeight, profile.climbSpeed, speed)
					if climb then
						print(("[Преграда] %s лезет через %s (высота %.1f)")
							:format(enemy.Name, blocker.Name, climb.height))
					end
				end
			end

			if stunned then
				-- Стан: ни шага, ни грызни, ни поворота. Толкучка жука всё равно двигает:
				-- соседи продавливают стоящего, и стан не означает, что он стал стеной.
				setVelocity(Vector3.zero)
			elseif state.dash then
				-- Разгон Тарана: идёт строго по зафиксированному направлению и не поворачивает.
				-- Маршрут на это время не спрашивается вовсе — в этом весь смысл прямого разгона.
				local dash = state.dash
				local step = dash.speed * dt
				dash.left -= step
				heading = dash.direction
				desired = position + dash.direction * step
				setVelocity(dash.direction * dash.speed)

				-- Столкновение: проламывает препятствие и сам оглушается.
				local ahead = Grid.GetBlocker(Grid.ToCell(desired))
				if ahead then
					local left = math.max(0, (ahead:GetAttribute("HP") or 0) - dash.damage)
					ahead:SetAttribute("HP", left)
					DamageDealtRemote:FireAllClients(ahead:GetPivot().Position, dash.damage, false)
					enemy:SetAttribute("StunnedUntil", now + dash.stun)
					enemy:SetAttribute("Stunned", true)
					print(("[Таран] проломил %s на %d и оглушён на %.0f сек")
						:format(ahead.Name, dash.damage, dash.stun))
					state.dash = nil
					dirty = true
				elseif dash.left <= 0 then
					-- Разгон ушёл в пустоту: смещённые стены и повороты — это и есть контр.
					state.dash = nil
					dirty = true
				end
			elseif behavior == "hold" then
				-- Копает, маскируется, нацеливается, строит или ждёт группу. Стоит на месте
				-- и от этого уязвим — ровно то, чего требует документ от Окопщика и Тарана.
				setVelocity(Vector3.zero)
			elseif behavior == "flee" then
				-- Паника: отходит от того, кто в него стреляет. Клетку маршрута не проходит
				-- и ничего не грызёт — и возвращается, как только срок выйдет.
				local slowPercent = enemy:GetAttribute("SlowPercent") or 0
				-- Испуг движет быстрее спокойного хода, если у вида есть fleeSpeed (см. Enemies).
				-- Замедление и хитин действуют на него так же, как на обычный ход: ускорение в панике —
				-- другая базовая скорость, а не иммунитет к эффектам.
				local fleeSpeed = (enemyData.fleeSpeed or speed) * (1 - slowPercent) * groundScale
				local move = EnemyBehavior.FleeStep(enemy, state, fleeSpeed * dt)
				if move.Magnitude > 1e-3 then
					heading = move.Unit
				end
				desired = position + move
				setVelocity(heading * fleeSpeed)
				-- Отбежав, он сошёл с маршрута: путь надо будет считать заново.
				dirty = true
			elseif climb then
				-- Перелезание. Жук при этом ОСТАЁТСЯ НАЗЕМНЫМ (подтверждённое правило физики):
				-- атрибут Flying не появляется, все земные турели, зоны Землетрясения и цепь
				-- Электричества по нему работают — меняется только анимация и занимаемое время.
				--
				-- Замедление тянет и его: замороженный жук не может перелезать бодрее, чем ходит.
				local slowPercent = enemy:GetAttribute("SlowPercent") or 0
				local at, direction, upVector, rate = advanceClimb(climb, dt * (1 - slowPercent))

				if at then
					-- Наверху он идёт по крыше обычной походкой — это второй отрезок плана.
					pose = climb.leg == 2 and "walk" or "climb"
					desired = at
					facing, facingUp = direction, upVector
					setVelocity(direction * rate * (1 - slowPercent))

					local flatDirection = flat(direction)
					if flatDirection.Magnitude > 1e-3 then
						heading = flatDirection.Unit
					end
				else
					-- Оказался по ту сторону. Маршрут пересчитывается от нового места: сохрани
					-- мы старый, следующая его точка по-прежнему лежала бы в клетке преграды,
					-- и жук полез бы через неё второй раз — теперь уже обратно.
					climb = nil
					dirty = true
					-- Пересчёт обязан случиться СРАЗУ, а не когда подойдёт REPATH_INTERVAL:
					-- до него cells[index] всё ещё указывает в клетку преграды, и жук, уже стоящий
					-- по ту сторону, тут же начал бы лезть второй раз.
					lastRepath = 0
					setVelocity(Vector3.zero)
				end
			elseif confused then
				-- Не стан: жук идёт с обычной (замедленной) скоростью, просто не туда. Клетку
				-- маршрута он при этом не проходит и постройку не грызёт, а случайно выйти к выходу
				-- блужданием не может: прорыв считается только по маршруту, а он здесь стоит.
				local wander = flat(enemy:GetAttribute("ConfusedDirection") or Vector3.zero)
				if wander.Magnitude > 1e-3 then
					heading = wander.Unit
				end

				local slowPercent = enemy:GetAttribute("SlowPercent") or 0
				local confusedSpeed = speed * (1 - slowPercent)
				desired = position + heading * confusedSpeed * dt
				setVelocity(heading * confusedSpeed)
			elseif blocker then
				-- Упёрлись в постройку: стоим на месте и грызём. Жук останавливается на клетку
				-- раньше, а не влезает внутрь постройки. Остановка сразу видна снарядам: выстрелы,
				-- ушедшие с упреждением до остановки, пролетят впереди него — это цена того, что
				-- попадание больше не выдаётся автоматом.
				setVelocity(Vector3.zero)

				pose = "chew" -- передние лапы упираются в преграду и работают (см. EnemyGait)

				local toBlocker = flat(points[index] - position)
				if toBlocker.Magnitude > 1e-3 then
					heading = toBlocker.Unit
				end

				-- Холод замедляет саму грызню, Кислота ослабляет укус — единственные два эффекта,
				-- которые защищают постройку, а не убивают жука. Оба читаются атрибутами: Effects
				-- про постройки не знает и знать не должен. Цена клетки в поиске пути от этого
				-- не меняется: chewDps считается один раз и описывает жука, а не его текущее состояние.
				local attackSlow = math.clamp(enemy:GetAttribute("AttackSlowPercent") or 0, 0, 0.9)

				if chewDamage > 0 and now - lastChew >= 1 / (chewRate * (1 - attackSlow)) then
					lastChew = now
					local weakened = math.clamp(enemy:GetAttribute("Weakened") or 0, 0, 0.9)
					-- Стойкость самой постройки к грызне (атрибут ChewResist, ставит TowerBuilder
					-- по таблице Towers): у Бура вращающееся сверло срезает укус вдвое. Это свойство
					-- того, кого грызут, а не того, кто грызёт — поэтому читается с blocker, а не с enemy.
					-- Цена клетки в поиске пути учитывает то же число (см. Grid.CellCost).
					local resist = math.clamp(blocker:GetAttribute("ChewResist") or 0, 0, 0.9)
					-- Кислотник размягчил постройку: «Работяги разрушают размягчённую стену
					-- в разы быстрее». Свойство того, кого грызут, как и ChewResist, и читается
					-- оттуда же. Срок истёк — множитель сам перестаёт действовать, снимать нечего.
					local softens = now < (blocker:GetAttribute("SoftenedUntil") or 0)
						and (blocker:GetAttribute("Softens") or 1) or 1
					local bite = math.max(1,
						math.floor(chewDamage * (1 - weakened) * (1 - resist) * softens + 0.5))
					local left = math.max(0, (blocker:GetAttribute("HP") or 0) - bite)
					blocker:SetAttribute("HP", left)
					DamageDealtRemote:FireAllClients(blocker:GetPivot().Position, bite, false)
					print(("[Грызня] %s грызёт %s на %d, осталось %d HP")
						:format(enemy.Name, blocker.Name, bite, left))
				end
			elseif atTable then
				-- «Разведчики ищут лабораторию. Нашли — грызут стол.» Стоит и грызёт,
				-- пока стол цел. Стол разбит — цель сменится на выход на следующем пересчёте.
				setVelocity(Vector3.zero)
				pose = "chew"

				local toTable = flat(LabTable.Position() - position)
				if toTable.Magnitude > 1e-3 then
					heading = toTable.Unit
				end

				if not EnemyBehavior.BiteTable(enemy, enemyData, state) then
					-- Грызть нечем (chewDamage = 0 у Спринтера, Координатора, Тени): для них
					-- сам факт того, что они дошли до лаборатории, и есть прорыв: «Летит к
					-- лаборатории мимо всего. Если не уничтожить в пути — добежит.»
					-- Без этой ветки они встали бы у стола навечно и волна не кончилась бы.
					break
				end
			else
				local slowPercent = enemy:GetAttribute("SlowPercent") or 0
				local step = speed * (1 - slowPercent) * groundScale * dt

				local delta = flat(points[index] - position)
				local distance = delta.Magnitude

				local reached = distance <= math.max(step, 1e-3)
				if not reached then
					local body = enemy:GetAttribute("FootRadius") or 1
					if distance <= body * WAYPOINT_REACH_SHARE then
						reached = true
					elseif index < #points and distance <= body * WAYPOINT_PASS_BODIES then
						local ahead = flat(points[index + 1] - points[index])
						reached = ahead:Dot(-delta) >= 0
					end
				end

				if reached then
					if index >= #points then
						-- Дошёл до конца маршрута. Прорыв — только у того, кто шёл к выходу;
						-- остальные просто продолжают жить (грызут стол, идут к следующему углу).
						if EnemyBehavior.Arrived(enemy, enemyData, state, goalMode) == "breach" then
							break
						end
						-- Маршрут пересчитается по обычному REPATH_INTERVAL, а не немедленно:
						-- обнули мы здесь lastRepath, жук, стоящий в конечной клетке, пересчитывал бы
						-- путь каждый кадр — по четверти миллисекунды на каждого, шестьдесят раз в секунду.
						dirty = true
					else
						index += 1
					end
				else
					heading = delta.Unit
					desired = position + heading * step
					setVelocity(heading * speed * (1 - slowPercent) * groundScale)
				end
			end

			-- Физические силы (v4): отдача, притяжение и подброс копятся в Effects одним
			-- вектором (атрибут Push — та самая «результирующая» из документа), а тратятся здесь:
			-- за кадр жук проезжает долю накопленного, остаток остаётся на следующие.
			-- Смещение идёт через desired, а значит проходит тем же Crowd.Resolve, что и шаг:
			-- отброшенный жук не пролетает сквозь соседей и не проваливается в постройку.
			local push = enemy:GetAttribute("Push")
			if push then
				if push.Magnitude > 0.05 then
					local applied = push * math.min(1, dt * PUSH_DECAY)
					desired += applied
					enemy:SetAttribute("Push", push - applied)
				else
					enemy:SetAttribute("Push", nil)
				end
			end

			-- Маршрут говорит, куда жук хочет; толкучка — куда он помещается на самом деле,
			-- и на какой высоте: в тесноте он лезет соседу на спину (см. Crowd).
			--
			-- На преграде толкучки нет: толкать жука там некуда, и привёл его туда не маршрут,
			-- а таймер перелезания. Но где он на самом деле, соседи знать обязаны (Crowd.Park).
			local resolved = desired
			if climb then
				Crowd.Park(enemy, resolved, facing)
			else
				-- Тела непроницаемы (см. Crowd): толкучка решает не только место, но и разворот —
				-- длинный жук, довернувшись в тесноте, въехал бы головой или брюшком в соседа.
				resolved, facing = Crowd.Resolve(enemy, desired, dt, heading)
			end

			-- Жук смотрит туда, куда идёт. Голова у модели по +Z, а LookVector в Roblox — это -Z,
			-- поэтому кадр доворачивается на 180° — иначе жук шёл бы задом наперёд.
			-- На стене к этому добавляется крен: «верх» жука — это сторона от поверхности,
			-- по которой он ползёт, поэтому мордой он смотрит вверх по стене, а брюхом прижат к ней.
			--
			-- Это МАРШРУТНЫЙ кадр: правда о том, где жук для сетки, толкучки, прицела
			-- башен и дистанции до выхода. Саму модель ставит походка: видимое тело оседает,
			-- кренится и дёргается вокруг этого кадра по стоящим ступням (см. EnemyGait.carryBody).
			-- Два PivotTo за кадр делать нельзя — жук дрожал бы между двумя положениями.
			local pathCF = CFrame.lookAt(resolved, resolved + facing, facingUp) * CFrame.Angles(0, math.pi, 0)
			-- След гемолимфы — ТОЛЬКО под Кровотечением (решение автора): капля через каждые
			-- PhysicsFX.bleed.step пройденных studs (× масштаб вида). Атрибут Bleeding ставит Effects.
			if state.pathPosition and enemy:GetAttribute("Bleeding") then
				local size = (enemy:GetAttribute("Scale") or 3) / 3
				state.bleedTrail = (state.bleedTrail or 0) + (resolved - state.pathPosition).Magnitude
				if state.bleedTrail >= PhysicsFX.bleed.step * size then
					state.bleedTrail = 0
					Corpses.Splat(resolved, PhysicsFX.bleed.size * size, 0)
				end
			end
			state.pathPosition = resolved

			-- Ноги переступают сами и подстраиваются под ту поверхность, на которой стоят
			-- (см. EnemyGait): ровная клетка, плита Бура, стена, гора — всё одним правилом.
			-- Она же и ставит модель — потому что тело теперь следствие ног, а не наоборот.
			--
			-- Сервер ставит только маршрутный кадр (одна деталь-якорь). Ноги, качку, наклон и голову
			-- отыгрывает клиент (EnemyRender → EnemyGait.Step) по этому кадру и двум атрибутам:
			-- Gait — поза ног, Look — куда жук хочет смотреть (голова раньше тела). Оба пишутся
			-- только на смене: атрибут уходит всем клиентам, и каждый кадр — это снова канал.
			enemy:PivotTo(pathCF)
			if state.gaitPose ~= pose then
				state.gaitPose = pose
				enemy:SetAttribute("Gait", pose)
			end
			local want = heading and heading.Magnitude > 1e-3 and -heading or nil
			if want then
				local sent = state.sentLook
				if not sent or sent:Dot(want) < LOOK_RESEND_COS then
					state.sentLook = want
					enemy:SetAttribute("Look", want)
				end
			end

			EnemyProgress.Set(enemy, remaining[index] + flat(points[index] - resolved).Magnitude)
		end
	end

	connection:Disconnect()

	if enemy.Parent then
		onBreach(enemy)
	end
end

-- Ищет ближайшую настоящую турель (у типа есть fireRate) — не Стену и не Гору-преграду,
-- отключать там нечего. towerData берётся по атрибуту Type, который ставит placeTower
-- (см. TowerBuilder).
--
-- Берётся только свободная: без Suppressed (никто ещё не присосался) и без Claimed
-- (никто туда ещё не летит). Обе проверки обязательны: без Claimed два Лицехвата, вылетевшие
-- близко друг к другу, оба выбирают одну и ту же свободную турель — Suppressed она получает только
-- по прибытии, а оба ещё в полёте до того (баг, найден живым прогоном после #43 — см. CHANGELOG #45).
-- Claimed ставит и снимает flyToTurret ниже, в момент выбора цели, до вылета — к моменту, когда
-- она физически долетит и поставит Suppressed сама, бывает уже поздно.
--
-- Если свободных нет вовсе (все турели уже заняты или заняты другими Лицехватами), возвращает nil —
-- лишний Жук просто ждёт (см. flyToTurret), а не летит к занятой — это и есть «1 турель = 1 Лицехват».
local function findFreeTurret(fromPosition)
	local best, bestDistance = nil, math.huge
	for _, tower in towersFolder:GetChildren() do
		local towerData = Towers[tower:GetAttribute("Type")]
		if towerData and towerData.fireRate
			and not tower:GetAttribute("Suppressed")
			and not tower:GetAttribute("Claimed") then
			local distance = (tower:GetPivot().Position - fromPosition).Magnitude
			if distance < bestDistance then
				best, bestDistance = tower, distance
			end
		end
	end
	return best
end

-- Лицехват (design: alchemy_td_enemies_t0.md): летит по прямой к свободной на момент вылета
-- турели, минуя Grid (не ищет путь по сетке) и Crowd (не толкается с другими жуками) —
-- поэтому свой цикл движения, а не moveThroughArena. Если цель разрушена по дороге или
-- свободных больше нет вовсе, просто выбирает новую свободную и летит дальше (или ждёт, если
-- свободных нет вовсе).
--
-- Долетев, ставит турели Suppressed — TowerBuilder.StartFiring перестаёт искать и бить
-- цель, пока флаг висит. Сам Лицехват дальше не движется и урона не наносит.
--
-- Снять его может только урон другой турели: Projectile бьёт по всем моделям в enemiesFolder
-- одинаково, отдельно летающих не выделяет. В момент смерти enemy.Destroying снимает и Claimed,
-- и Suppressed с той, что за ним числилась — «турель немедленно возвращается к работе», как и требует ТЗ,
-- независимо от того, успел он физически долететь или нет.
local function flyToTurret(enemy, enemyData)
	local reserved = nil -- турель, которую жук занял: Claimed на подлёте, Suppressed после присасывания

	enemy.Destroying:Connect(function()
		if reserved and reserved.Parent then
			reserved:SetAttribute("Claimed", false)
			reserved:SetAttribute("Suppressed", false)
		end
	end)

	while enemy.Parent do
		local target = findFreeTurret(enemy:GetPivot().Position)

		if not target then
			-- Свободных турелей нет (все заняты другими Лицехватами, или их нет вовсе) —
			-- зависает и ждёт, не двигаясь, пока какая-нибудь не освободится.
			enemy:SetAttribute("Velocity", Vector3.zero)
			RunService.Heartbeat:Wait()
		else
			-- Бронируем сразу, до вылета: другой Лицехват, выбирающий цель мгновением позже,
			-- уже не увидит её свободной в findFreeTurret — без этого два Жука, вылетевшие близко
			-- друг к другу, выбрали бы одну и ту же ещё свободную турель — именно такой был баг.
			target:SetAttribute("Claimed", true)
			reserved = target
			local targetPosition = target:GetPivot().Position + Vector3.new(0, FACEHUGGER_HEIGHT, 0)

			while enemy.Parent and target.Parent do
				local position = enemy:GetPivot().Position
				local delta = targetPosition - position
				local distance = delta.Magnitude
				if distance <= FACEHUGGER_ATTACH_RANGE then
					break
				end

				local dt = RunService.Heartbeat:Wait()
				if not enemy.Parent then
					return
				end
				local heading = delta.Unit
				local step = math.min(enemyData.speed * dt, distance)
				local nextPosition = position + heading * step
				enemy:PivotTo(CFrame.lookAt(nextPosition, nextPosition + heading) * CFrame.Angles(0, math.pi, 0))
				enemy:SetAttribute("Velocity", heading * enemyData.speed)
			end

			if enemy.Parent and target.Parent then
				target:SetAttribute("Suppressed", true)
				enemy:PivotTo(CFrame.new(targetPosition))
				enemy:SetAttribute("Velocity", Vector3.zero)

				-- «После того как присосался к турели, получает минимальный урон сам по себе»
				-- (alchemy_td_enemies.md, каста 3). Броня появляется именно здесь, а не при спавне:
				-- на подлёте он по-прежнему стеклянный, иначе его не сбить вообще никогда.
				if enemyData.clingArmor then
					enemy:SetAttribute("Armor", enemyData.clingArmor)
				end

				-- Износ на турели (задача #77): присосавшийся Лицехват теряет clingDecay HP
				-- в секунду и рано или поздно отваливается сам. До этого снять его могла только
				-- другая турель, и одиноко стоящая башня молчала до конца забега.
				--
				-- Счёт идёт ЦЕЛЫМИ секундами по часам, а не долями за кадр: HP — целое число,
				-- его показывает полоска и цифра урона, и дробная доля читалась бы мусором.
				-- Отставшие секунды набегают сразу (ticks), а не теряются на просадке кадра.
				--
				-- Смерть отсюда ничем не особенна: HP уходит в ноль, срабатывает тот же листенер
				-- HP в spawnEnemy (материя, плутоний, Destroy), а enemy.Destroying выше снимает
				-- Claimed/Suppressed — турель возвращается к работе сама, без отдельной ветки.
				local decay = enemyData.clingDecay
				if decay then
					print(("[Лицехват] %s присосался к %s и теряет %d HP/сек (осталось %d)")
						:format(enemy.Name, target.Name, decay, enemy:GetAttribute("HP") or 0))
				end
				local lastDecay = os.clock()

				-- Висит, пока жив и пока сама турель не разрушена чем-то другим.
				while enemy.Parent and target.Parent do
					RunService.Heartbeat:Wait()

					if decay and enemy.Parent then
						local ticks = math.floor(os.clock() - lastDecay)
						if ticks >= 1 then
							lastDecay += ticks
							local bite = decay * ticks
							local left = math.max(0, (enemy:GetAttribute("HP") or 0) - bite)
							enemy:SetAttribute("HP", left)
							-- Цифра над жуком — не базовый урон турели, а тик: тот же оранжевый
							-- цвет, что у горения, — без неё игрок не видит вовсе, отчего тот умирает.
							DamageDealtRemote:FireAllClients(enemy:GetPivot().Position, bite, false)
						end
					end
				end

				-- reserved чистим только если вышли из-за гибели турели, а не жука: если умер жук,
				-- снять флаги должен enemy.Destroying выше — а он читает тот же reserved. Очистка
				-- здесь в обоих случаях гонялась бы с ним за одну и ту же переменную — кто успеет
				-- первым, тот и прав, и флаги могли бы застрять навсегда (тот же баг, что был в #43
				-- с одним Suppressed — здесь то же самое для второго флага).
				if not target.Parent and reserved == target then
					reserved = nil
				end
			else
				-- Сюда попадаем, только если таргет разрушен на подлёте, до того как жук долетел: смерть
				-- самого жука в цикле выше уже ловит return. Снимаем reserved, чтобы не держать
				-- ссылку на уже разрушенную турель — следующая итерация внешнего цикла выберет новую цель.
				if not target.Parent and reserved == target then
					reserved = nil
				end
			end
		end
	end
end

-- Создаёт и ведёт одного врага. hpOverride переопределяет HP из Enemies (для волн, где
-- один и тот же тип встречается с разным HP).
-- startPosition — мировая точка старта без учёта offset (по умолчанию вход арены). Используется
-- Осколками Splitter: они появляются там, где погиб родитель, а не у входа.
local function spawnEnemy(enemyType, offset, hpOverride, startPosition)
	offset = offset or Vector3.new(0, 0, 0)
	local enemyData = Enemies[enemyType]
	assert(enemyData, ("[EnemySpawner] неизвестный тип врага: %s"):format(tostring(enemyType)))

	local hp = hpOverride or enemyData.hp
	ProfileStats.Seen(enemyType)

	local enemy = buildEnemyModel(enemyData)

	-- Высота спавна — из RideHeight КОНКРЕТНОГО клона (см. buildTemplateModel/buildEnemyModel),
	-- а не общей enemyData.rideHeight: у Мини она разная от забега к забегу (scaleRange),
	-- и до сборки модели настоящего числа ещё не существует — поэтому построение вынесено
	-- перед расчётом spawnPosition.
	local spawnPosition
	if startPosition then
		-- Личинка Матки, высыпавшиеся из Носителя, вышедший из кокона — все появляются
		-- там, где их выпустили, а не у пролома.
		spawnPosition = startPosition + offset
	else
		local entranceX, entranceZ = Grid.GetEntranceCell()
		spawnPosition = Grid.ToWorld(entranceX, entranceZ) + Vector3.new(0, enemy:GetAttribute("RideHeight") or enemyData.rideHeight or ENEMY_Y, 0) + offset
	end

	-- Тела непроницаемы (см. Crowd): у пролома новый ждёт, пока предыдущий отойдёт, а
	-- выпущенные в точке (личинки, осколки) раскладываются по ближайшим свободным местам.
	if not enemyData.flying then
		enemy:PivotTo(CFrame.new(spawnPosition))
		if not startPosition then
			local epoch = Crowd.epoch
			local waited = 0
			while waited < SPAWN_WAIT_MAX and not Crowd.Fits(enemy, spawnPosition) do
				waited += task.wait(SPAWN_POLL)
				if Crowd.epoch ~= epoch then
					-- Забег перезапустили, пока ждали: этот жук уже из прошлой волны.
					enemy:Destroy()
					return
				end
			end
		end
		-- Места нет даже рядом — ждём дальше: появиться внутри соседа хуже, чем на секунду позже.
		local epoch = Crowd.epoch
		local free = Crowd.FindFree(enemy, spawnPosition)
		while not free do
			task.wait(SPAWN_POLL)
			if Crowd.epoch ~= epoch then
				enemy:Destroy()
				return
			end
			free = Crowd.FindFree(enemy, spawnPosition)
		end
		spawnPosition = free
	end

	enemy:PivotTo(CFrame.new(spawnPosition))
	-- Ключ типа — атрибутом: по нему один жук узнаёт касту другого (группа работяг,
	-- Кукольник, Координатор), не таская за собой ссылку на запись из Enemies.
	enemy:SetAttribute("Type", enemyType)
	enemy:SetAttribute("HP", hp)
	enemy:SetAttribute("MaxHP", hp)
	-- До первого пересчёта маршрута враг не должен выглядеть стоящим у выхода: режим first
	-- берёт минимальное расстояние до выхода, и ноль по умолчанию перетянул бы на себя все башни.
	EnemyProgress.Set(enemy, 1e9)
	-- Скорость есть у врага с первого кадра, ещё до первого шага: снаряд читает её без проверок
	-- на «а вдруг атрибута ещё нет».
	enemy:SetAttribute("Velocity", Vector3.zero)
	if enemyData.armor then
		-- Число, а не флаг: Effects.ApplyArmor вычитает его напрямую из урона (задача #44)
		enemy:SetAttribute("Armor", enemyData.armor)
	end
	if enemyData.swarm then
		enemy:SetAttribute("Swarm", true)
	end
	if enemyData.flying then
		-- Атрибутом, а не только полем в Enemies: по нему турели отличают воздушные цели
		-- от наземных (Towers[тип].targets, задача #53), а Targeting таблицу врагов не требует
		-- и видит только саму модель.
		enemy:SetAttribute("Flying", true)
	end
	enemy.Parent = enemiesFolder

	-- С этой минуты жук — тело в толкучке: его расталкивают соседи, и он расталкивает их.
	-- Регистрируется после PivotTo (уровень земли толкучка берёт из его пивота) и сразу за
	-- проверкой места выше, без уступки потока между ними: иначе двое ждавших у пролома
	-- увидели бы одно и то же свободное место и встали в него оба.
	-- Летающий (Лицехват) в толкучке не участвует вовсе — он не ходит по земле и не может
	-- застрять среди соседей.
	if not enemyData.flying then
		Crowd.Add(enemy)
	end

	-- Каста и особые механики. Запускается ПОСЛЕ Parent: трейты ищут соседей
	-- по enemiesFolder и сами должны в нём числиться.
	local state = EnemyBehavior.Attach(enemy, enemyData)

	-- Смерть от урона (например, от горения) ловится через изменение атрибута HP,
	-- не опросом каждый кадр.
	-- Кровь считается здесь, а не в местах, где наносится урон: их полдюжины (снаряд,
	-- площадь, горение, износ на турели), а падение HP — одно на всех.
	local lastHp = hp
	local lastBleed = 0

	enemy:GetAttributeChangedSignal("HP"):Connect(function()
		local currentHp = enemy:GetAttribute("HP") or 0
		if enemy.Parent and currentHp < lastHp and currentHp > 0 then
			local now = os.clock()
			if now - lastBleed >= BLEED_INTERVAL then
				lastBleed = now
				Corpses.Splat(enemy:GetPivot().Position, BLEED_SIZE * (enemy:GetAttribute("Scale") or enemyData.scale or 1), 1)
			end

			-- «Жуки реагируют на стрельбу. Каждая каста реагирует по-разному.» Падение HP —
			-- единственное место, куда сходится весь урон сразу (снаряд, площадь, горение),
			-- поэтому паника считается здесь же, где и кровь.
			EnemyBehavior.Damaged(enemy, enemyData, state)
		end
		local previousHp = lastHp
		lastHp = currentHp

		if enemy.Parent and currentHp <= 0 then
			print(("[Манекен] %s уничтожен"):format(enemy.Name))
			EnemyDiedRemote:FireAllClients(enemy:GetPivot().Position)
			Matter.Add(enemyData.matter or 0)
			Plutonium.AwardEnemyKill(enemyType)
			ProfileStats.Kill(enemyType, enemy:GetAttribute("LastElement"))

			-- Последействия смерти отдельных видов (design: alchemy_td_enemies.md). Все три —
			-- до трупа и Destroy: модель ещё цела и стоит там, где её убили.
			--
			-- Подрывник: «Попадание в заряд — преждевременная детонация.» Тот же взрыв,
			-- что и у стены, но там, где его сбили — в этом вся выгода раннего выстрела.
			if enemyData.charge then
				EnemyBehavior.Detonate(enemy, enemyData)
			end
			-- Разносчик: «Взрывается впитанными элементами.»
			if enemyData.absorbs then
				EnemyBehavior.Burst(enemy, enemyData)
			end
			-- Носитель: «Уничтожен — жуки высыпаются.»
			if enemyData.carries then
				EnemyBehavior.Spill(enemy, enemyData)
			end

			-- Splitter: смерть не убирает угрозу, а размножает её — на месте гибели появляются
			-- более слабые осколки, каждый идёт к выходу заново своим маршрутом.
			if enemyData.splitsInto then
				local deathPosition = enemy:GetPivot().Position
				for _ = 1, enemyData.splitsInto.count do
					local splitOffset = Vector3.new(
						(math.random() - 0.5) * 2 * SCATTER,
						0,
						(math.random() - 0.5) * 2 * SCATTER
					)
					task.spawn(function()
						spawnEnemy(enemyData.splitsInto.type, splitOffset, nil, deathPosition)
					end)
				end
			end

			-- Останки. Ставятся ДО Destroy: модель ещё цела и стоит там, где её убили, а труп —
			-- её клон в позе смерти (см. Corpses). Кровь — отдельным пятном покрупнее: она
			-- останется на карте, даже когда сам труп растворится по лимиту.
			local deathPoint = enemy:GetPivot().Position
			Corpses.Splat(deathPoint, DEATH_SPLAT_SIZE * (enemy:GetAttribute("Scale") or enemyData.scale or 1), DEATH_SPLAT_DROPS)

			-- Гора вырастает из трупа и поглощает его (Corpses.Absorb в TowerBuilder.BuildBarrier),
			-- но она вполне может встать РАНЬШЕ, чем сюда дойдёт очередь — тогда труп появился бы
			-- уже внутри неё. Поэтому клетка проверяется и здесь: занята постройкой — останков нет.
			local deathX, deathZ = Grid.ToCell(deathPoint)
			if not Grid.GetOccupant(deathX, deathZ) then
				-- Добивающий удар в долях макс. HP (с перебоем) решает, сколько конечностей отлетит,
				-- HitFrom (ставит Projectile) — куда.
				local maxHp = math.max(enemy:GetAttribute("MaxHP") or hp, 1)
				local from = enemy:GetAttribute("HitFrom")
				Corpses.Leave(enemy, {
					fraction = math.max(previousHp - currentHp, 0) / maxHp,
					from = typeof(from) == "Vector3" and from or nil,
				})
			end

			enemy:Destroy()
		end
	end)

	-- Регенерация — свойство самого врага, а не элемента, поэтому живёт здесь, а не в Effects.
	-- Любое уменьшение HP (от чего угодно — горение, удар, тест) сбрасывает паузу.
	if enemyData.regen then
		local lastDamageTime = os.clock()
		local lastHp = hp

		enemy:GetAttributeChangedSignal("HP"):Connect(function()
			local currentHp = enemy:GetAttribute("HP") or 0
			if currentHp < lastHp then
				lastDamageTime = os.clock()
			end
			lastHp = currentHp
		end)

		task.spawn(function()
			while enemy.Parent do
				task.wait(1)
				if not enemy.Parent then
					break
				end
				local currentHp = enemy:GetAttribute("HP") or 0
				-- Анти-реген из документа дебаффов v2 приходит атрибутом от Effects: ноль — реген
				-- выключен совсем (Яд навсегда, Кислота на время), доля — работает, но медленнее
				-- (ветка холода), больше единицы — быстрее обычного (Лёд после разморозки).
				-- Сам Effects про реген не знает, как не знает про грызню (Weakened).
				local amount = math.floor(enemyData.regen.amount * (enemy:GetAttribute("RegenScale") or 1) + 0.5)
				-- Потолок — собственный максимум жука. До этой задачи поля regen не было ни у
				-- одного вида, и отсутствие ограничения никак не проявлялось. Заживалка с её
				-- «очень высокой регенерацией» вылечилась с 60 до 204 за десяток секунд на первом
				-- же прогоне: полоска HP ушла за край, и убить её стало невозможно в принципе.
				local maxHp = enemy:GetAttribute("MaxHP") or currentHp
				if amount > 0 and currentHp > 0 and currentHp < maxHp
					and os.clock() - lastDamageTime >= enemyData.regen.pauseAfterDamage then
					local newHp = math.min(maxHp, currentHp + amount)
					print(("[Реген] %s восстанавливает %d HP: %d -> %d из %d")
						:format(enemy.Name, newHp - currentHp, currentHp, newHp, maxHp))
					enemy:SetAttribute("HP", newHp)
				end
			end
		end)
	end

	print(("[Манекен] %s (%s) появился у пролома (HP = %d)"):format(enemy.Name, enemyType, hp))

	-- Лицехват не идёт к выходу и не участвует в толкучке — свой цикл движения
	-- (flyToTurret), без onBreach и без Crowd.Remove. Отличается от остальных летунов
	-- тем, что цепляется за турель (clingArmor) — это и есть его признак.
	if enemyData.clingArmor then
		flyToTurret(enemy, enemyData)
		return
	end

	-- Свой цикл движения у Моли, Матки, Личинки, летающего координатора и Пеликана.
	-- Первые четверо ведут себя до конца сами; Пеликан наедается, садится и отдаёт
	-- управление общему циклу — «и идёт в бой».
	if EnemyBehavior.OwnLoop(enemy, enemyData, state) then
		Crowd.Remove(enemy)
		return
	end

	-- Пеликан сел на землю — теперь он обычное тело в толкучке, в которую летающим
	-- входа не было. Для всех остальных Crowd.Add уже сработал выше.
	if enemyData.flying and not enemy:GetAttribute("Flying") then
		Crowd.Add(enemy)
	end

	moveThroughArena(enemy, enemyData, offset, function(reachedEnemy)
		-- Прорыв теперь случается не только на выходе: дошёдший до лаборатории жук,
		-- который не умеет грызть стол (Спринтер, Координатор, Тень), считается так же —
		-- «Если не уничтожить в пути — добежит». Поэтому сообщение больше не говорит
		-- про выход: оно солгало бы про половину касты 2.
		print(("[Манекен] %s прошёл оборону"):format(reachedEnemy.Name))
		print("прорыв")
		if EnemySpawner.OnBreach then
			EnemySpawner.OnBreach(reachedEnemy)
		end
		reachedEnemy:Destroy()
	end, state)

	-- Жук дошёл до выхода или умер по дороге — из толкучки его надо убрать, иначе живые
	-- продолжат расталкиваться об его последнюю позицию — и даже стоять на ней.
	Crowd.Remove(enemy)
end

-- Спавнит count врагов типа enemyType. При count > 1 — с интервалом и разбросом по позиции,
-- чтобы не спавились друг на друге. hpOverride — для волн (см. Waves).
--
-- Большая группа спавнится несколько секунд, и за это время забег может кончиться и начаться
-- заново. isCancelled — проверка между спавнами: без неё остаток старой волны досыпался бы
-- уже в новый забег (см. WaveRunner).
function EnemySpawner.SpawnGroup(enemyType, count, hpOverride, isCancelled)
	for i = 1, count do
		if isCancelled and isCancelled() then
			return
		end

		local offset = count > 1 and Vector3.new(
			(math.random() - 0.5) * 2 * SCATTER,
			0,
			(math.random() - 0.5) * 2 * SCATTER
		) or Vector3.new(0, 0, 0)

		task.spawn(function()
			spawnEnemy(enemyType, offset, hpOverride)
		end)

		if i < count then
			task.wait(SPAWN_INTERVAL)
		end
	end
end

-- Колбеки-мосты. Назначаются один раз при загрузке модуля — тот же приём, что и
-- у Effects.OnKillBarrier в TowerBuilder: те, кому надо спавнить жуков, не могут требовать
-- спавнер напрямую — он уже требует их, и require зациклился бы.

local Effects = require(ReplicatedStorage:WaitForChild("Effects"))

-- Личинка Матки, высыпавшиеся из Носителя, вылупившиеся из личинки.
EnemyBehavior.Spawn = function(enemyType, position)
	task.spawn(function()
		spawnEnemy(enemyType, Vector3.zero, nil, position)
	end)
end

-- Жук следующей касты из кокона Кукольника.
EnemyStructures.OnHatch = function(enemyType, position)
	task.spawn(function()
		spawnEnemy(enemyType, Vector3.zero, nil, position)
	end)
end

-- Взрыв элемента сносит и конструкции жуков, а огонь их поджигает.
Effects.OnAreaBlast = function(position, radius, amount, elementData)
	EnemyStructures.Blast(position, radius, amount, elementData)
end

-- Разносчик впитывает элемент, которым в него попали.
Effects.OnAbsorb = function(enemy, elementName, damage)
	EnemyBehavior.Absorb(enemy, elementName, damage)
end

-- Литосфера меняет рельеф на месте смерти. Тот же мост, что и у Горы: элемент
-- считает числа, а бетон двигает серверный модуль.
local Lithosphere = require(ServerScriptService:WaitForChild("Lithosphere"))
Effects.OnTerrain = function(position, plan)
	Lithosphere.Erupt(position, plan)
end

return EnemySpawner
