-- Снаряды турелей: летящий шар со своей скоростью и своим хитбоксом.
--
-- Раньше выстрел был мгновенным: TowerBuilder сам отнимал HP у выбранной цели, а клиент
-- рисовал луч уже по факту. Теперь попадание — отдельное событие, а не следствие выстрела:
-- турель выпускает снаряд, он летит и наносит урон только когда действительно догоняет
-- врага. Промах врагу ничего не стоит.
--
-- Снаряд — обычная деталь в Workspace.Projectiles, которую двигает и проверяет сервер:
-- видимый шар и хитбокс — один и тот же объект, поэтому картинка не может разойтись
-- с попаданием. Клиент по снаряду ничего не решает и ничего не досчитывает.
--
-- Летит по прямой: точка прицеливания считается один раз при выстреле, с упреждением по
-- скорости цели, и в полёте больше не меняется. Поэтому враг, который свернул, остановился
-- (упёрся в постройку) или был замедлен уже после выстрела, снаряд пропускает — наведения
-- в полёте нет намеренно, иначе попадание снова стало бы автоматическим, просто с задержкой.
--
-- Задача #53 добавила второй вид полёта — навес (shot.arc, Мортира). Навесной снаряд
-- никого не задевает в полёте нарочно: он идёт НАД толпой по дуге и срабатывает в точке
-- падения — там и считается и прямое попадание, и урон по площади (см. burst).
--
-- Задача #75 — третий вид полёта: дрон (shot.drone, Станция FPV-дронов). Считает он ровно то
-- же, что и навес, теми же числами и тем же burst — меняется только ФОРМА пути. Навес уходил
-- свечкой вверх и падал сверху; дрон выходит из люка, выравнивается и идёт к цели низко,
-- заваливаясь в поворотах, а в конце пикирует и подрывается. Навесная ветка оставлена рядом
-- нетронутой: вернуть мортирную дугу — это одна строка в TowerBuilder.fireDrone (arc вместо drone).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local Arena = require(ReplicatedStorage:WaitForChild("Arena"))
local Effects = require(ReplicatedStorage:WaitForChild("Effects"))
-- Только за EnemiesInRange для взрыва навесного снаряда: фильтр земля/воздух должен быть
-- тот же, что у прицеливания. Цикла нет: Targeting никого не требует.
local Targeting = require(ServerScriptService:WaitForChild("Targeting"))
-- Габариты тела жука: по ним считается хитбокс (см. enemyRadius ниже).
local EnemyBody = require(ReplicatedStorage:WaitForChild("EnemyBody"))
-- Модель самого дрона (задача #75). Только сборка картинки: чем дрон бьёт и куда летит,
-- решается здесь, а не там.
local DroneRig = require(ServerScriptService:WaitForChild("DroneRig"))
-- Модель иглы Инжектора — тот же принцип, что у дрона: только сборка картинки,
-- чем бьёт и куда летит — решается здесь.
local NeedleRig = require(ServerScriptService:WaitForChild("NeedleRig"))
-- Конструкции жуков под разрывом навесного снаряда (см. burst).
local EnemyStructures = require(ServerScriptService:WaitForChild("EnemyStructures"))
-- Отдача: живой вздрагивает от попадания, разрыв расбрасывает всё незакреплённое.
local Impulse = require(ServerScriptService:WaitForChild("Impulse"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local DamageDealtRemote = Remotes:WaitForChild("DamageDealt")
-- Разрыв миномётного снаряда — настоящий взрыв, тот самый случай, ради которого заведён
-- этот Remote (задача #39): CombatFX рисует по нему вспышку с волной, а не по любой смерти.
local ExplosionRemote = Remotes:WaitForChild("Explosion")

local enemiesFolder = Workspace:WaitForChild("Enemies")

local DEFAULT_SPEED = 60 -- studs/сек, если стреляющий не задал свою
local DEFAULT_RADIUS = 0.7 -- радиус хитбокса снаряда, он же половина видимого шара
-- Цвет на случай, если стреляющий не задал свой. Задача #69: тот же нейтральный белый, что
-- и у пустой турели (TowerBuilder.SHOT_COLOR), а не тёплый жёлтый от прежнего луча.
local DEFAULT_COLOR = Color3.fromRGB(255, 255, 255)

-- Игла (shot.shape == "needle", Инжектор) — не шар и даже не одна деталь, а модель
-- (см. NeedleRig): ампула с элементом, кольцо, жало, кончик и оперение. До этого
-- тут был один тонкий цилиндр, и на скорости он читался как разогнавшийся шарик.
--
-- ХИТБОКС от формы не зависит вовсе: попадание как считалось шаром радиуса
-- shot.radius (findHit ниже) вокруг точки снаряда, так и считается.

-- ===== Форма полёта дрона (задача #75) =====
-- Ни одно из этих чисел не балансное: время полёта, урон, радиусы и темп стрельбы остались
-- ровно теми же, что были у навеса (см. Towers.Mortar). Здесь — только траектория и посадка
-- корпуса в ней, то есть картинка. Поэтому числа тут, а не в таблице Towers.

-- Выход из шахты: дрон уходит от люка вверх-вперёд, а не свечкой. Угол пологий нарочно —
-- по прямому требованию автора вертикального подлёта у дрона быть не должно, но и уйти
-- из люка строго горизонтально он не может: под ним крыша собственного модуля.
local DRONE_EXIT_PITCH = math.rad(34)
-- Длина разгонного участка в студах — ФИКСИРОВАННАЯ, а не доля дистанции: иначе дальний
-- выстрел задирал бы дрона тем выше, чем дальше цель, и снова получился бы навес.
local DRONE_EXIT_RUN = 10
-- Terminal: последние студы дрон идёт в пикировании на цель, а не подлетает к ней ровно.
local DRONE_DIVE_PITCH = math.rad(44)
local DRONE_DIVE_RUN = 11
-- Потолок на оба участка от длины всего полёта: у цели на краю слепой зоны (12 studs)
-- десятистудовый разгон занял бы весь путь, и выход из люка съел бы пикирование.
local DRONE_RUN_LIMIT = 0.34

-- Боковой увод. Без него все четыре точки кривой лежат в одной вертикальной плоскости,
-- курс за весь полёт не меняется ни на градус — и крена не бывает вовсе (замерено: ±2°
-- одной дрожи). Разгонная и пикирующая точки разводятся в РАЗНЫЕ стороны: выходит пологая
-- еска, на которой дрон ложится сначала на один борт, потом на другой. Точка подрыва
-- не трогается: увод на точность не влияет вовсе.
local DRONE_WEAVE = 0.12 -- доля длины полёта
local DRONE_WEAVE_MAX = 6 -- studs: на предельной дальности еска не должна читаться как объезд

-- Высота, ниже которой дрон не должен идти над своей же станцией (shot.clearance, абсолютный Y).
-- Без неё низкая трасса прошивала собственную градирню станции на глубину до 3.9 studs
-- на трети курсов (замерено по 72 направлениям). Подъём до своей крыши — это не навес:
-- дрон выходит из шахты, выравнивается на высоте крыш и дальше идёт ровно, а не падает сверху.
--
-- Коэффициент: кубическая кривая проходит заметно НИЖЕ своей верхней точки, поэтому точка
-- разгона задирается выше нужной высоты, а не ровно на неё. Число подобрано замером по кривой.
local DRONE_CLIMB_OVERSHOOT = 1.75

-- Отход от створки люка (shot.exit — точка в мире, куда дрон выходит ПЕРЕД тем, как лечь
-- на курс). Откинутая створка Станции стоит стеной вплотную к точке пуска, и одной кубической
-- кривой её не обойти: замерено — смещение разгонной точки даже на 12 studs вбок убирает
-- задевание только с 30 курсов из 72 до 21, потому что контрольная точка только наклоняет
-- касательную, а кривая всё равно срезает угол. Поэтому путь разбит на две кривые:
-- отход (поднялся из шахты и ушёл вбок вдоль оси петли) и дальше обычный полёт к цели.
--
-- Доля времени на отход берётся ПО ДЛИНЕ, а не константой: тогда скорость на отходе
-- и на курсе одна и та же, а общее время полёта остаётся тем, на которое бралось упреждение.
local DRONE_EXIT_SHARE_MAX = 0.32 -- потолок доли: у ближней цели отход не должен съесть весь полёт
local DRONE_LIFTOUT = 0.55 -- доля отхода на «вверх из шахты» до того, как уйти вбок
local DRONE_ONCOURSE = 0.5 -- доля, на которой отход уже разворачивается на курс (стык без излома)

-- Постоянный завал носом вперёд: квадрокоптер едет, наклоняясь в сторону хода, и ровно
-- висящий в горизонте корпус читается как деталь на верёвочке, а не как летящая машина.
local DRONE_NOSE_DOWN = math.rad(12)
-- Крен в повороте. Считается от угловой скорости курса: чем круче дрон заворачивает,
-- тем сильнее ложится на борт — это и есть то, по чему полёт читается как настоящий.
local DRONE_BANK_GAIN = 0.55
local DRONE_BANK_MAX = math.rad(40)
local DRONE_BANK_SMOOTH = 9 -- 1/сек: с какой скоростью крен догоняет желаемый
-- Микроподработка: живой коптер всё время подруливает и никогда не стоит идеально ровно.
-- Амплитуда нарочно на грани заметности — это дрожь, а не болтанка.
local DRONE_WOBBLE = math.rad(2.4)
local DRONE_WOBBLE_RATE = 17 -- рад/сек

local Projectile = {}

-- Все снаряды в полёте. Один общий Heartbeat на всех, а не поток на каждый: снарядов в
-- воздухе бывает десятки, и каждому свой task.spawn — лишние переключения на ровном месте.
local active = {}
local connection = nil

-- Папка заводится на лету, а не руками в плейсе: снаряд живёт доли секунды, и хранить
-- под него пустой контейнер в сохранённом плейсе незачем.
local function projectilesFolder()
	local folder = Workspace:FindFirstChild("Projectiles")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Projectiles"
		folder.Parent = Workspace
	end
	return folder
end

-- Хитбокс врага — шар по габаритам его тела: жук 2.6 x 1.2 x 3.4 даёт радиус 1.5.
--
-- Формула та же, что была, но переехала в общий EnemyBody: ровно теми же габаритами
-- теперь меряет радиус и площадь прицеливание (Targeting), и две копии разошлись бы
-- при первой же правке размера модели.
local function enemyRadius(enemy)
	return EnemyBody.Radius(enemy)
end

-- Доля отрезка [from, to], в которой он ближе всего к точке point (0 — начало, 1 — конец).
local function closestOnSegment(from, to, point)
	local segment = to - from
	local lengthSquared = segment:Dot(segment)
	if lengthSquared < 1e-6 then
		return 0
	end
	return math.clamp((point - from):Dot(segment) / lengthSquared, 0, 1)
end

-- Первый враг, которого задевает путь снаряда за этот кадр. Проверяется весь отрезок пути,
-- а не одна конечная точка: за кадр снаряд пролетает около студа, и проверка «по точкам»
-- прошивала бы жука насквозь между кадрами тем чаще, чем быстрее снаряд.
--
-- Ищется по всем врагам, а не по той цели, в которую целились: у снаряда свой хитбокс, и
-- получает тот, кто первым под него попал. Чужой жук, влезший на линию огня, ловит выстрел.
local function findHit(shot, from, to)
	local best, bestAlong = nil, math.huge

	for _, enemy in enemiesFolder:GetChildren() do
		if enemy:IsA("Model") and enemy.PrimaryPart and (enemy:GetAttribute("HP") or 0) > 0 then
			local center = enemy:GetPivot().Position
			local along = closestOnSegment(from, to, center)
			local nearest = from:Lerp(to, along)
			if along < bestAlong and (center - nearest).Magnitude <= shot.radius + enemyRadius(enemy) then
				best, bestAlong = enemy, along
			end
		end
	end

	return best
end

-- Урон считается в момент попадания, а не выстрела: броня и разгон Кирпича берутся у того,
-- в кого снаряд реально попал, а это может быть не та цель, в которую целилась турель.
-- Своей арифметики у снаряда нет — всё число считает Effects.HitDamage.
--
-- Элемент снаряд несёт свой — тот, что был залит в турель на момент выстрела. Вынуть элемент
-- из колбы, пока снаряд летит, значит изменить следующие выстрелы, а не уже сделанный.
--
-- Возвращает true, если цель от этого попадания умерла — по этому решается, прошьёт
-- ли снаряд её насквозь (shot.pierce, см. step).
local function dealDamage(shot, enemy)
	local hp = enemy:GetAttribute("HP") or 0
	if hp <= 0 then
		return false
	end

	-- Откуда прилетело. Нужно только лобовому щиту Щитоносца (см. Effects.ApplyArmor):
	-- без направления щит закрывал бы со всех сторон, и «перекрёстный огонь обходит
	-- щит» перестало бы работать вовсе. Атрибутом, а не аргументом — чтобы не тянуть
	-- точку выстрела сквозь всю цепочку Effects, которой она нигде больше не нужна.
	enemy:SetAttribute("HitFrom", shot.origin)

	local armored = enemy:GetAttribute("Armor")
	local damage = Effects.HitDamage(enemy, shot.element, shot.damage)

	-- Нулевой урон — это Плазма: попадание есть, удара нет. HP трогать нечем,
	-- и цифра «0» над жуком читалась бы как промах.
	if damage > 0 then
		hp = math.max(0, hp - damage)
		enemy:SetAttribute("HP", hp)
		DamageDealtRemote:FireAllClients(enemy:GetPivot().Position, damage, true)
		Impulse.Hit(enemy, shot.origin, damage / math.max(enemy:GetAttribute("MaxHP") or damage, 1))
	end

	print(("[%s] снаряд попал в %s: %d урона%s, осталось %d HP")
		:format(shot.ownerName, enemy.Name, damage, armored and " (броня)" or "", hp))

	-- Эффекты вешаются всегда, а не только по выжившей цели: что ложится на саму цель,
	-- а что бьёт вокруг неё (взрыв, цепочка, детонация Пороха), решает Effects.Apply.
	-- Снятый урон ему нужен: от него считаются доли взрыва и цепочки.
	if shot.element then
		-- Четвёртым — точка пуска: притяжение тянет жука к стрелявшей турели, а снаряд —
		-- единственный, кто ещё помнит, откуда он вылетел. Отдача и подброс её не спрашивают:
		-- их направление считается по самой цели.
		Effects.Apply(enemy, shot.element, damage, shot.origin)
	end

	return hp <= 0
end

-- Разрыв навесного снаряда в точке падения (Мортира). Уронов два: прямой — тому, кого
-- накрыло самой воронкой, и доля по площади — всем остальным в радиусе. Разделение то же,
-- что у взрыва-элемента в Effects.applyExplosion: получивший прямой удар второй раз не бьётся.
--
-- Броня и эффекты считаются каждому отдельно теми же Effects, что и при обычном
-- попадании: взрыв — это удар, а не отравление. Цели берутся через Targeting с тем же
-- фильтром земля/воздух, что у выпустившей турели: навес не должен задевать площадью
-- того, в кого не может целиться.
local function burst(shot)
	local center = shot.position
	local list = Targeting.EnemiesInRange(center, shot.splash.radius, enemiesFolder, { targets = shot.targets })

	-- Конструкции жуков: «все уничтожаются тяжёлым снарядом и горят»
	-- (alchemy_td_enemies.md, Строитель). Тяжёлый — это именно навесной и дрон,
	-- то есть всё, что доходит до burst; прямой снаряд их не берёт и не должен.
	EnemyStructures.Blast(center, shot.splash.radius, shot.splash.damage, shot.element)

	-- Прямое попадание — тот, чей хитбокс накрыла сама воронка. Цель вполне может
	-- успеть уйти за время полёта — тогда прямого нет вовсе, а площадь остаётся.
	local direct, directDistance = nil, math.huge
	for _, enemy in list do
		local distance = (enemy:GetPivot().Position - center).Magnitude
		if distance <= shot.radius + enemyRadius(enemy) and distance < directDistance then
			direct, directDistance = enemy, distance
		end
	end

	if direct then
		dealDamage(shot, direct)
	end

	for _, enemy in list do
		-- Проверка жив ли — не лишняя: прямое попадание выше могло убить не только
		-- свою цель (цепочка Электричества, детонация Пороха), а список снят до этого.
		if enemy ~= direct and enemy.Parent and (enemy:GetAttribute("HP") or 0) > 0 then
			local damage = Effects.HitDamage(enemy, shot.element, shot.splash.damage)
			if damage > 0 then
				local hp = math.max(0, (enemy:GetAttribute("HP") or 0) - damage)
				enemy:SetAttribute("HP", hp)
				DamageDealtRemote:FireAllClients(enemy:GetPivot().Position, damage, true)
			end
			if shot.element then
				Effects.Apply(enemy, shot.element, damage, shot.origin)
			end
		end
	end

	-- Третьим аргументом уходит цвет — и он же переключатель картинки: есть цвет — клиент
	-- рисует подрыв микрозаряда дрона (без огня и дыма, в цвет элемента), нет — прежний
	-- пиротехнический взрыв Пороха/Взрыва (см. Effects.applyExplosion и CombatFX.onExplosion).
	-- Отдельного Remote под это заводить незачем: событие одно и то же — «здесь рвануло».
	ExplosionRemote:FireAllClients(center, shot.splash.radius, shot.drone and shot.color or nil)
	Impulse.Blast(center, shot.splash.radius)
	print(("[%s] заряд сработал: целей в радиусе %d — %d%s")
		:format(shot.ownerName, shot.splash.radius, #list, direct and " (есть прямое попадание)" or ""))
end

-- Путь дрона — кубическая кривая по четырём точкам, а не поиск рулёжкой каждый кадр.
-- Причина не в простоте: время полёта задано сразу (дистанция / projectileSpeed) и обязано
-- совпадать с тем, по которому бралось упреждение (PredictAim). Самонаводящийся дрон
-- пришёл бы когда придётся и попадал бы всегда — а промах должен остаться реальным
-- ровно в той же мере, в какой был у навеса: свернувший или вставший жук уходит из-под удара.
local function bezier(a, b, c, d, t)
	local u = 1 - t
	return a * (u * u * u) + b * (3 * u * u * t) + c * (3 * u * t * t) + d * (t * t * t)
end

-- Производная той же кривой — куда дрон сейчас движется. Берётся аналитически, а не разностью
-- соседних кадров: разность на малом dt шумит, а от неё считается и курс, и крен.
local function bezierTangent(a, b, c, d, t)
	local u = 1 - t
	return (b - a) * (3 * u * u) + (c - b) * (6 * u * t) + (d - c) * (3 * t * t)
end

-- Посадка корпуса в этом кадре: нос по курсу, завал вперёд по наклону траектории,
-- крен — по тому, насколько круто дрон сейчас заворачивает. Всё три — следствие пути,
-- а не отдельная анимация поверх него: разошлись бы — дрон летел бы боком.
local function droneFrame(shot, position, velocity, dt)
	local flat = Vector3.new(velocity.X, 0, velocity.Z)
	local heading = flat.Magnitude > 1e-3 and flat.Unit or shot.heading

	-- Знаковая угловая скорость курса: влево — положительная, вправо — отрицательная.
	local turn = math.atan2(shot.heading:Cross(heading).Y, shot.heading:Dot(heading)) / math.max(dt, 1e-3)
	shot.heading = heading

	local wanted = math.clamp(turn * DRONE_BANK_GAIN, -DRONE_BANK_MAX, DRONE_BANK_MAX)
	shot.roll += (wanted - shot.roll) * math.min(dt * DRONE_BANK_SMOOTH, 1)

	-- Угол места траектории плюс постоянный завал: на выходе из люка дрон задран,
	-- на крейсерском участке стоит носом вниз, в пике — смотрит прямо в цель.
	local pitch = math.atan2(-velocity.Y, math.max(flat.Magnitude, 1e-3)) + DRONE_NOSE_DOWN

	local now = os.clock()
	return CFrame.lookAt(position, position + heading)
		* CFrame.Angles(
			-pitch + math.sin(now * DRONE_WOBBLE_RATE) * DRONE_WOBBLE,
			0,
			shot.roll + math.sin(now * DRONE_WOBBLE_RATE * 0.7 + 1.3) * DRONE_WOBBLE)
end

local function destroyShot(index)
	local shot = active[index]
	table.remove(active, index)
	-- У дрона сносится вся модель, а не один корпус: остальные три десятка деталей —
	-- его дети, и без этого они остались бы висеть в точке подрыва.
	local body = shot.rig or shot.part
	body:Destroy()
end

local function step(dt)
	for index = #active, 1, -1 do
		local shot = active[index]

		if not shot.part.Parent then
			table.remove(active, index) -- снаряд снесли снаружи (рестарт забега)
		elseif shot.drone then
			-- Дрон (задача #75). Путь, как и у навеса, задан целиком в момент пуска, и по дороге
			-- дрон ни в кого не врезается: он идёт над толпой и срабатывает там, куда целился.
			-- До exitShare идёт отход от створки люка, дальше — та же кривая к цели, что и без него.
			shot.elapsed += dt
			local t = math.min(shot.elapsed / shot.duration, 1)
			local position, tangent
			if shot.exitShare and t < shot.exitShare then
				local s = t / shot.exitShare
				position = bezier(shot.a0, shot.a1, shot.a2, shot.a3, s)
				tangent = bezierTangent(shot.a0, shot.a1, shot.a2, shot.a3, s)
			else
				local s = shot.exitShare and (t - shot.exitShare) / (1 - shot.exitShare) or t
				position = bezier(shot.p0, shot.p1, shot.p2, shot.p3, s)
				tangent = bezierTangent(shot.p0, shot.p1, shot.p2, shot.p3, s)
			end
			shot.position = position
			shot.part.CFrame = droneFrame(shot, position, tangent, dt)

			if t >= 1 then
				burst(shot)
				destroyShot(index)
			end
		elseif shot.arc then
			-- Навес: путь задан целиком в момент выстрела — откуда, куда и за сколько.
			-- Снаряд ни в кого по дороге не врезается: в том и смысл навеса, что он идёт
			-- над толпой и срабатывает там, куда целился.
			shot.elapsed += dt
			local t = math.min(shot.elapsed / shot.duration, 1)
			local position = shot.origin:Lerp(shot.landing, t)
				+ Vector3.new(0, shot.apex * 4 * t * (1 - t), 0)
			shot.position = position
			shot.part.CFrame = CFrame.new(position)

			if t >= 1 then
				burst(shot)
				destroyShot(index)
			end
		else
			local from = shot.position
			local to = from + shot.direction * shot.speed * dt
			local enemy = findHit(shot, from, to)
			local spent = false

			-- Пробитие (shot.pierce, Инжектор): игла гаснет на попадании, ЕСЛИ цель
			-- выжила, и идёт дальше, если убила — теряя свою долю урона за каждый труп.
			--
			-- Следующая цель ищется на ТОМ ЖЕ отрезке пути, а не в следующем кадре:
			-- игла Инжектора идёт 250 studs/сек, за кадр это добрый десяток студов,
			-- и второго жука в той же колонне она бы просто перепрыгнула.
			--
			-- Цикл конечен: каждый заход либо гасит снаряд, либо кладёт ещё одного
			-- врага, а мёртвых findHit не возвращает.
			while enemy do
				local killed = dealDamage(shot, enemy)
				if killed and shot.pierce then
					shot.damage *= (1 - shot.pierce)
					shot.pierced += 1
					print(("[%s] игла прошла насквозь (трупов на счету: %d), дальше бьёт на %.1f")
						:format(shot.ownerName, shot.pierced, shot.damage))
					enemy = findHit(shot, from, to)
				else
					spent = true
					enemy = nil
				end
			end

			if spent then
				destroyShot(index)
			else
				shot.position = to
				shot.traveled += (to - from).Magnitude
				-- У иглы есть направление, и оно не меняется в полёте — поворот посчитан
				-- один раз при выстреле. У шара orientation нет вовсе: ему всё равно.
				shot.part.CFrame = shot.orientation and (CFrame.new(to) * shot.orientation) or CFrame.new(to)

				-- Промахнувшийся снаряд не летит вечно и не уходит под пол: он целился в точку у
				-- земли, поэтому всегда снижается и рано или поздно втыкается в неё.
				if to.Y - shot.radius <= Arena.floorY then
					print(("[%s] снаряд ушёл в землю — промах"):format(shot.ownerName))
					destroyShot(index)
				elseif shot.traveled >= shot.maxDistance then
					print(("[%s] снаряд выдохся, пролетев %.0f studs — промах"):format(shot.ownerName, shot.traveled))
					destroyShot(index)
				end
			end
		end
	end

	-- В воздухе пусто — цикл не крутится вхолостую между волнами.
	if #active == 0 and connection then
		connection:Disconnect()
		connection = nil
	end
end

-- Точка прицеливания с упреждением: пока снаряд летит, враг успевает уйти, поэтому целиться
-- надо туда, где он окажется к прилёту. Время полёта зависит от точки прилёта, а точка — от
-- времени, поэтому уравнение решается двумя итерациями: первая прикидка по текущей дистанции,
-- вторая уточняет её уже по упреждённой. Третья на наших скоростях (снаряд вчетверо быстрее
-- жука) не даёт разницы, которую видно.
--
-- Скорость цели берётся из атрибута Velocity, который пишет EnemySpawner: модель врага
-- анкорнута и двигается через PivotTo, физической скорости у неё нет и спросить её не у кого.
--
-- Целимся в центр модели (пивот на высоте 1.5), а не в точку под ней: снаряд стартует с дула
-- на высоте ~3.9 и должен снижаться к жуку, иначе он пролетал бы над ним и не задевал вовсе.
function Projectile.PredictAim(origin, target, speed)
	local flightSpeed = (speed and speed > 0) and speed or DEFAULT_SPEED
	local position = target:GetPivot().Position
	local velocity = target:GetAttribute("Velocity") or Vector3.zero
	local aim = position

	for _ = 1, 2 do
		aim = position + velocity * ((aim - origin).Magnitude / flightSpeed)
	end

	return aim
end

-- Внешний вид снаряда (задача #69, под новый меш Колбы). Тело снаряда не трогается
-- вовсе: это тот же шар ровно по хитбоксу, что и раньше — размер, скорость, урон и радиус
-- попадания остаются без изменений. Всё, что здесь добавлено, — свечение вокруг этого шара,
-- сквозь которое сам шар видно: обмануться в том, чем снаряд бьёт, по-прежнему негде.
--
-- Цвет один на всё и приходит снаружи: у залитой турели это цвет элемента, у пустой —
-- нейтральный белый Колбы. Своих цветов здесь нет ни одного, кроме белого накала в голове
-- искры: горячая точка, выцветающая в цвет самого снаряда, читается как жар, а не как другой элемент.
local function dressShot(part, radius, color)
	-- Хвост: на скорости в десятки studs/сек шарик без следа читается как мигание, а по
	-- следу видно и направление, и саму скорость — ради этого выстрел и стал снарядом.
	-- Ширина хвоста ровно в диаметр шара и сходит на нет к хвосту (WidthScale): ровная
	-- лента постоянной ширины читалась как палка, а клин — как движение.
	local top = Instance.new("Attachment")
	top.Position = Vector3.new(0, radius, 0)
	top.Parent = part
	local bottom = Instance.new("Attachment")
	bottom.Position = Vector3.new(0, -radius, 0)
	bottom.Parent = part

	local trail = Instance.new("Trail")
	trail.Attachment0 = top
	trail.Attachment1 = bottom
	trail.Lifetime = 0.25
	trail.MinLength = 0
	trail.Color = ColorSequence.new(color)
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.WidthScale = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(1, 0),
	})
	trail.LightEmission = 1
	trail.FaceCamera = true
	trail.Parent = part

	-- Ореол: мягкое свечение вплотную вокруг ядра. LockedToPart — чтобы он ехал вместе
	-- со снарядом, а не оставался вторым хвостом позади. Прозрачный насквозь и всего на
	-- треть шире самого шара (2.6 радиуса против диаметра в 2) — это свет, а не тело:
	-- за размер снаряда его не примешь, и хитбокс он не врёт.
	local halo = Instance.new("ParticleEmitter")
	halo.Name = "Halo"
	halo.Color = ColorSequence.new(color)
	halo.LightEmission = 1
	halo.LightInfluence = 0
	halo.Size = NumberSequence.new(radius * 2.6)
	halo.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.55),
		NumberSequenceKeypoint.new(1, 1),
	})
	halo.Lifetime = NumberRange.new(0.12)
	halo.Rate = 30
	halo.Speed = NumberRange.new(0)
	halo.Rotation = NumberRange.new(0, 360)
	halo.LockedToPart = true
	halo.Parent = part

	-- Искры: отрываются от снаряда и гаснут на месте (Drag гасит их собственную
	-- скорость) — от этого снаряд читается как раскалённый, а не как летящий шарик.
	local embers = Instance.new("ParticleEmitter")
	embers.Name = "Embers"
	embers.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
		ColorSequenceKeypoint.new(0.35, color),
		ColorSequenceKeypoint.new(1, color),
	})
	embers.LightEmission = 1
	embers.LightInfluence = 0
	embers.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, radius * 0.5),
		NumberSequenceKeypoint.new(1, 0),
	})
	embers.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	embers.Lifetime = NumberRange.new(0.16, 0.3)
	embers.Rate = 90
	embers.Speed = NumberRange.new(1, 3)
	embers.SpreadAngle = Vector2.new(180, 180)
	embers.Drag = 4
	embers.Rotation = NumberRange.new(0, 360)
	embers.RotSpeed = NumberRange.new(-120, 120)
	embers.Parent = part

	-- Свет: снаряд подсвечивает пол и жуков, над которыми проходит. Радиус маленький
	-- нарочно: в воздухе бывают десятки снарядов разом, а одновременных источников света
	-- движок держит ограниченное число (та же беда, что у Highlight на метках).
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 9
	light.Brightness = 2.5
	light.Shadows = false
	light.Parent = part
end

-- Выпускает снаряд из origin в точку aim. Кого бить и куда целиться решает стреляющий
-- (см. TowerBuilder.StartFiring), снаряд решает только одно: долетел он до кого-нибудь или нет.
--
-- shot: origin, aim, damage, ownerName (для лога) — обязательны;
--       speed, radius, maxDistance, color, element — по вкусу стреляющего.
--
-- Навес (Мортира, задача #53) — ещё три поля: arc = true, splash = { radius, damage }
-- и targets ("ground"/"air"/"both") для фильтра взрыва. aim для него — не точка прицела
-- в воздухе, а место падения на земле: навес бьёт по полу, а не по телу жука.
--
-- Дрон (Станция FPV-дронов, задача #75) — drone = true вместо arc = true, остальные поля
-- те же и значат то же: тот же splash, тот же targets, aim — точка на полу. Разница только
-- в траектории и в том, что летит модель, а не шар. Необязательное clearance — абсолютная
-- высота крыш выпустившей станции: ниже неё дрон пошёл бы сквозь собственную градирню.
-- Необязательное exit — точка, в которую дрон выходит перед тем, как лечь на курс (облёт
-- откинутой створки люка). Где она и нужна ли вообще — решает выпускающий: про свою
-- створку знает он, а не снаряд (см. TowerBuilder.BARRELS.Mortar.lid).
function Projectile.Fire(shot)
	local origin = shot.origin
	local delta = shot.aim - origin
	if delta.Magnitude < 1e-3 then
		return -- целимся в собственное дуло: стрелять некуда
	end

	local radius = shot.radius or DEFAULT_RADIUS
	local color = shot.color or DEFAULT_COLOR
	local speed = shot.speed or DEFAULT_SPEED
	-- Игла летит носом вперёд, и курс у прямого выстрела в полёте не меняется —
	-- поворот считается раз при выстреле и дальше только переезжает с точкой.
	local needle = shot.shape == "needle"
	local orientation = needle and CFrame.lookAt(origin, shot.aim).Rotation or nil

	-- У дрона (задача #75) тот же самый шар ровно по хитбоксу, только вокруг него собрана
	-- модель (см. DroneRig). Двигает сервер по-прежнему одну деталь — корпус.
	local part, rig
	if shot.drone then
		rig = DroneRig.Build(radius, color)
		part = rig.PrimaryPart
		-- Позиция ставится ПОСЛЕ Parent, а не до: оснастка едет за корпусом на сварке,
		-- а сварка тянет детали только в Workspace — вне его корпус уехал бы один.
		rig.Parent = projectilesFolder()
		part.CFrame = CFrame.new(origin)
	elseif needle then
		-- Игла — тоже модель на сварке, как дрон: сервер двигает один корень,
		-- остальное едет за ним. Позиция ставится ПОСЛЕ Parent, а не до: сварка
		-- тянет детали только в Workspace, вне его корень уехал бы один.
		rig = NeedleRig.Build(radius, color)
		part = rig.PrimaryPart
		rig.Parent = projectilesFolder()
		part.CFrame = CFrame.new(origin) * orientation
	else
		part = Instance.new("Part")
		part.Name = "Projectile"
		part.Shape = Enum.PartType.Ball
		part.Size = Vector3.new(radius * 2, radius * 2, radius * 2) -- шар ровно по хитбоксу
		part.Anchored = true
		part.CanCollide = false
		part.CanTouch = false -- касания не нужны: попадания считает сам модуль по своему радиусу
		part.CanQuery = false -- иначе снаряд ловил бы луч подсветки клетки при постройке
		part.Material = Enum.Material.Neon
		part.Color = color
		part.CFrame = CFrame.new(origin)
		part.Parent = projectilesFolder()

		dressShot(part, radius, color)
	end

	local state = {
		part = part,
		rig = rig, -- nil у обычного снаряда: там сносить нечего, кроме самой детали
		color = color, -- нужен подрыву: картинка взрыва идёт в том же цвете, что и сам дрон
		position = origin,
		direction = delta.Unit,
		speed = speed,
		radius = radius,
		traveled = 0,
		maxDistance = shot.maxDistance or math.huge,
		damage = shot.damage or 0,
		element = shot.element,
		ownerName = shot.ownerName or "Снаряд",
		orientation = orientation,
		-- Доля урона, теряемая за каждый труп при пробитии. nil — пробития нет
		-- вовсе, снаряд гаснет на первом же попадании, как и было.
		pierce = shot.pierce,
		pierced = 0,
	}

	if shot.arc then
		-- Скорость навесного снаряда считается по горизонтали: время полёта — это расстояние
		-- до воронки, делённое на неё, а высота дуги — чисто геометрия поверх этого времени.
		-- Так же его считает и упреждение (PredictAim), иначе турель целилась бы по одному
		-- времени полёта, а снаряд летел бы другое.
		local flat = Vector3.new(delta.X, 0, delta.Z).Magnitude
		state.arc = true
		state.origin = origin
		state.landing = shot.aim
		state.elapsed = 0
		state.duration = math.max(flat / speed, 0.05)
		-- Высота дуги не из ТЗ — это только картинка траектории: чем дальше выстрел,
		-- тем выше навес, но не ниже крыши построек, иначе выстрел вблизи читается как прямой.
		state.apex = math.max(8, flat * 0.35)
		state.splash = shot.splash
		state.targets = shot.targets
	end

	if shot.drone then
		-- Время полёта — по ПРЯМОЙ до цели, той же самой, по которой считал упреждение
		-- PredictAim. Кривая длиннее прямой, и дрон проходит её чуть быстрее номинала — ровно
		-- как до этого навесный снаряд проходил свою дугу. Важно другое: в точке прицела
		-- он оказывается в то же время, на которое бралось упреждение.
		local length = delta.Magnitude
		-- Отход от створки люка: основная кривая начинается не у дула, а там, куда дрон
		-- отошёл. Нет shot.exit — всё как было, от самого люка.
		local start = shot.exit or origin
		local mainDelta = shot.aim - start
		local flat = Vector3.new(mainDelta.X, 0, mainDelta.Z)
		-- Цель ровно под люком — курса нет вовсе; берётся нос туда, куда смотрит модель.
		-- Случай разобран ради него одного: слепая зона (minRange) таких целей не даёт.
		local heading = flat.Magnitude > 1e-3 and flat.Unit or Vector3.new(0, 0, -1)
		local limit = mainDelta.Magnitude * DRONE_RUN_LIMIT
		-- Сторона ески своя на каждый пуск: два дрона подряд, идущие одной и той же
		-- дугой, читаются как одна анимация, а не как два аппарата.
		local side = (math.random() < 0.5) and 1 or -1
		local weave = Vector3.new(-heading.Z, 0, heading.X)
			* (side * math.min(mainDelta.Magnitude * DRONE_WEAVE, DRONE_WEAVE_MAX))

		-- Подъём на высоту крыш своей же станции. Ограничен длиной полёта тем же limit,
		-- что и разгон: по ближней цели дрон не успевает набрать высоту и не должен — иначе
		-- выстрел вблизи снова стал бы навесом: вверх и тут же вниз.
		local climb = shot.clearance
			and math.min(math.max(shot.clearance - start.Y, 0) * DRONE_CLIMB_OVERSHOOT, limit)
			or 0

		state.drone = true
		state.p0 = start
		state.p1 = start
			+ (heading * math.cos(DRONE_EXIT_PITCH) + Vector3.yAxis * math.sin(DRONE_EXIT_PITCH))
			* math.min(DRONE_EXIT_RUN, limit)
			+ Vector3.yAxis * climb
			+ weave
		state.p2 = shot.aim
			- (heading * math.cos(DRONE_DIVE_PITCH) - Vector3.yAxis * math.sin(DRONE_DIVE_PITCH))
			* math.min(DRONE_DIVE_RUN, limit)
			- weave
		state.p3 = shot.aim
		state.elapsed = 0
		state.duration = math.max(length / speed, 0.05)
		state.heading = heading
		state.roll = 0
		state.splash = shot.splash
		state.targets = shot.targets

		-- Сам отход: вверх из шахты (a1 — чистая вертикаль, иначе дрон поехал бы вбок ещё
		-- внутри люка) и дальше в точку отхода уже разворачиваясь на курс (a2 стоит на продолжении
		-- начальной касательной основной кривой — без этого на стыке был бы излом).
		if shot.exit then
			local run = (shot.exit - origin).Magnitude
			local onCourse = state.p1 - start
			onCourse = onCourse.Magnitude > 1e-3 and onCourse.Unit or heading
			state.a0 = origin
			state.a1 = origin + Vector3.yAxis * (run * DRONE_LIFTOUT)
			state.a2 = shot.exit - onCourse * (run * DRONE_ONCOURSE)
			state.a3 = shot.exit
			-- Доля по длине: отход и курс проходятся одной скоростью, и дрон не дёргается на стыке.
			state.exitShare = math.clamp(run / math.max(run + mainDelta.Magnitude, 1e-3),
				0, DRONE_EXIT_SHARE_MAX)
		end
	end

	table.insert(active, state)

	if not connection then
		connection = RunService.Heartbeat:Connect(step)
	end
end

-- Снимает все снаряды в полёте. Нужен рестарту (WaveRunner.clearArena): врагов и постройки
-- он сносит, а снаряд, выпущенный за миг до конца забега, иначе долетел бы уже в новый забег
-- и ударил бы первого врага новой волны.
function Projectile.ClearAll()
	for index = #active, 1, -1 do
		destroyShot(index)
	end
end

return Projectile
