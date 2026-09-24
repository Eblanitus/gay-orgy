-- Наведение и стрельба турелей: дуло, сектор, снаряд, дрон, облако, TowerBuilder.StartFiring
-- Вынесено из TowerBuilder.luau без изменений кода (задача #203): файл был слишком
-- велик, чтобы агент читал его целиком. deps — локальные основного файла, которые нужны
-- этому куску; возвращается то, что основной файл использует дальше.
return function(deps)
	local MUZZLE_LEAD = deps.MUZZLE_LEAD
	local Aiming = deps.Aiming
	local BARRELS = deps.BARRELS
	local TowerBuilder = deps.TowerBuilder
	local Targeting = deps.Targeting
	local enemiesFolder = deps.enemiesFolder
	local Projectile = deps.Projectile
	local SHOT_COLOR = deps.SHOT_COLOR
	local RANGE_OVERSHOOT = deps.RANGE_OVERSHOOT
	local Effects = deps.Effects
	local ShotFiredRemote = deps.ShotFiredRemote
	local EnemyProgress = deps.EnemyProgress
	local Arena = deps.Arena
	local DamageDealtRemote = deps.DamageDealtRemote
	local Towers = deps.Towers
	local Elements = deps.Elements

	local function meshMuzzle(tower, gun, aimAngle, aimPitch)
		local nose = tower:FindFirstChild("MiniBarrelC", true)
		local breech = tower:FindFirstChild("BreechNew", true)
		if not (nose and breech and nose:IsA("BasePart") and breech:IsA("BasePart")) then
			return nil -- у турели нет такого меша — пускай считает aimBarrel по числам
		end

		local axis = nose.Position - breech.Position
		if axis.Magnitude < 1e-3 then
			return nil
		end

		local pivot = tower:GetPivot()
		-- Смещение среза в координатах модели — от ПОЛНОГО пивота (с поворотом постройки),
		-- а наведение прикладывается от пивота БЕЗ поворота: ровно та же арифметика, что
		-- у клиента в BuildingVisuals.trackStep — иначе у повёрнутой при стройке турели (задача #76)
		-- поворот считался бы дважды.
		local offset = pivot:PointToObjectSpace(nose.Position + axis.Unit * MUZZLE_LEAD)
		local frame = CFrame.new(pivot.Position) * CFrame.Angles(0, aimAngle, 0)

		if gun and aimPitch then
			-- Ствол качается на цапфах — той же формулой и теми же числами, что рисует клиент.
			local trunnion = CFrame.new(gun.trunnion)
			local pitch = math.clamp(aimPitch - math.rad(gun.restPitch),
				math.rad(gun.pitchMin), math.rad(gun.pitchMax))
			frame = frame * trunnion * CFrame.Angles(pitch, 0, 0) * trunnion:Inverse()
		end

		return (frame * CFrame.new(offset)).Position
	end

	-- Доворот турели, у которой ствол — не одна деталь, а целый узел импортированного
	-- меша (Инжектор). Путь ниже переставляет одну деталь Barrel; здесь целиком
	-- поворачиваются два АВТОРСКИХ узла рига: Pivot_Yaw по горизонтали и вложенный
	-- в него Pivot_Pitch — по вертикали, вокруг своей цапфы. Имена узлов не выдуманы:
	-- они так названы в самом .glb и ровно для этого там стоят.
	--
	-- Как и у Колбы на клиенте, берётся только ПОЛОЖЕНИЕ пивота, без его собственного
	-- поворота: угол наведения мировой, а поворот постройки при стройке (задача #76)
	-- уже сидит в запомненной позе детали. Умножай мы на полный пивот — поворот
	-- считался бы дважды.
	--
	-- Исходные позы запоминаются один раз на башню: поворот считается ОТ них, иначе
	-- каждый выстрел докручивал бы модель от предыдущего положения. Ключи слабые —
	-- снесённая турель уходит из таблицы сама.
	-- Наведение турели, у которой ствол — не одна деталь, а узел импортированного меша
	-- (Инжектор). Сервер здесь НЕ трогает CFrame ни одной детали: он только говорит
	-- атрибутами AimAngle/AimPitch, куда смотреть, а пушку ставит клиент (BuildingVisuals) —
	-- тот же приём, что у Колбы с задачи #70. До этого сервер переставлял детали сам,
	-- и анимация выстрела на клиенте дралась бы с ним за один и тот же CFrame.
	--
	-- Возвращает мировую точку дульного среза, посчитанную тем же углом, который уехал
	-- клиенту: разойдись они — снаряд вылетал бы из воздуха рядом со стволом, ровно
	-- как было у Колбы до задачи #77.
	--
	-- Порога на публикацию угла (AIM_PUBLISH_STEP у publishAim) здесь не нужно: эта
	-- функция зовётся ровно в момент выстрела, а не двадцать раз в секунду.
	-- Сектор обстрела (Towers[тип].arc): ствол не выходит за половину сектора от фронта
	-- ПОСТРОЙКИ, а не от мира: повернуть турель при стройке можно (задача #76).
	-- Страховка к тому же сектору в Targeting: туда цель вне сектора вообще не попадает,
	-- но упреждение уводит точку прицела дальше самой цели и может вынести её за край.
	local function clampArc(tower, yaw, arc)
		if not arc then
			return yaw
		end
		local look = tower:GetPivot().LookVector
		local facing = math.atan2(-look.X, -look.Z)
		local half = math.rad(arc) / 2
		return facing + math.clamp(Aiming.Delta(facing, yaw), -half, half)
	end

	-- Мировая точка дульного среза турели на риге по УЖЕ посчитанным углам наведения.
	-- Та же арифметика, по которой клиент ставит ствол (BuildingVisuals): разойдись они —
	-- снаряд вылетал бы из воздуха рядом со стволом, ровно как было у Колбы до задачи #77.
	-- Отдача тут не учитывается нарочно: она начинается ПОСЛЕ выстрела и живёт только
	-- на клиенте (так же устроен meshMuzzle у Колбы).
	local function rigMuzzle(tower, rig, yaw, pitch)
		local base = CFrame.new(tower:GetPivot().Position) * CFrame.Angles(0, yaw, 0)
		local trunnion = CFrame.new(rig.trunnion)
		local gun = base * trunnion * CFrame.Angles(pitch or 0, 0, 0) * trunnion:Inverse()
		return (gun * CFrame.new(rig.muzzle)).Position
	end

	-- Запасной путь для турели с ригом, но БЕЗ доворота (нет turnSpeed в Towers, то есть
	-- нет и aimState): углы считаются тут же и сразу уезжают клиенту. С доворотом углы
	-- публикует fireProjectile (publishAim/publishPitch), и сюда управление не доходит.
	local function aimRig(tower, rig, direction, arc)
		local flat = Vector3.new(direction.X, 0, direction.Z)
		if flat.Magnitude < 1e-3 then
			return nil -- цель ровно над башней: доворачиваться не на что
		end

		-- Ноль угла — это -Z модели, та же система, что у Aiming.AngleTo.
		local yaw = clampArc(tower, math.atan2(-direction.X, -direction.Z), arc)
		local pitch = math.asin(math.clamp(direction.Y, -1, 1))

		tower:SetAttribute("AimAngle", yaw)
		tower:SetAttribute("AimPitch", pitch)
		return rigMuzzle(tower, rig, yaw, pitch)
	end

	local function aimBarrel(tower, aimPosition, geometry, towerData)
		geometry = geometry or BARRELS.Ballista
		-- Откуда вылетает снаряд. Обычно это точка на оси башни на высоте height, но у Станции
		-- FPV-дронов люк стоит сбоку, на крыше своего модуля: такой геометрии одной высоты мало,
		-- и она задаёт mount — точку целиком, в координатах модели.
		local center = (tower:GetPivot() * CFrame.new(geometry.mount or Vector3.new(0, geometry.height, 0))).Position

		local delta = aimPosition - center
		if delta.Magnitude < 1e-3 then
			return center -- цель внутри самой башни: стреляем из центра сферы
		end

		local direction
		if geometry.pitch then
			local flat = Vector3.new(delta.X, 0, delta.Z)
			if flat.Magnitude < 1e-3 then
				return center
			end
			local pitch = math.rad(geometry.pitch)
			direction = (flat.Unit * math.cos(pitch) + Vector3.new(0, math.sin(pitch), 0)).Unit
		else
			direction = delta.Unit
		end

		-- У турели с ригом (Инжектор) доворот и дульный срез считаются по самой модели.
		-- Не вышло (откат на процедурную модель — рига в ней нет) — считаем по числам ниже.
		if geometry.rig then
			local muzzle = aimRig(tower, geometry.rig, direction, towerData and towerData.arc)
			if muzzle then
				return muzzle
			end
		end

		if not geometry.clientTracked then
			local barrel = tower:FindFirstChild("Barrel")
			if barrel then
				local barrelCenter = center + direction * geometry.reach
				barrel.CFrame = CFrame.lookAt(barrelCenter, barrelCenter + direction) * CFrame.Angles(0, math.rad(90), 0)
			end
		end

		return center + direction * (geometry.reach + geometry.length / 2)
	end

	-- Желаемый угол ствола уезжает клиенту атрибутом AimAngle (задача #70): сам поворот
	-- рисует BuildingVisuals по той же формуле Aiming, а сервер шлёт только «куда смотреть».
	-- Так картинка не может разойтись с тем, куда уходит выстрел: до этого клиент искал ближайшего
	-- врага сам и вполне мог выбрать не того, в кого стреляет сервер.
	--
	-- Атрибут пишется, лишь когда угол заметно изменился: иначе это была бы репликация числа
	-- по двадцать раз в секунду на каждую турель ради разницы в сотые доли градуса.
	local AIM_PUBLISH_STEP = math.rad(1)

	-- Как часто турель пересматривает цель и доворачивается, пока не стреляет. С темпом
	-- стрельбы не связано вовсе: выстрелившая турель всё равно ждёт свой 1/fireRate.
	local AIM_TICK = 0.05

	-- Полуширина «пятна», которое ствол должен накрывать, чтобы выстрел читался как прицельный:
	-- радиус жука (1.5) плюс радиус снаряда (0.7), округлённо. По нему считается допуск на
	-- доворот: важно не «сколько градусов», а накрывает ли ствол цель. Вблизи те же восемь
	-- градусов — это полстуда мимо, вдали — три; без этой поправки турель переставала бы стрелять
	-- по жукам, проходящим вплотную: их угловая скорость выше, чем у самой башни.
	local AIM_SPAN = 2.2

	local function publishAim(tower, desired)
		local previous = tower:GetAttribute("AimAngle")
		if previous == nil or math.abs(Aiming.Delta(previous, desired)) >= AIM_PUBLISH_STEP then
			tower:SetAttribute("AimAngle", desired)
		end
	end

	-- Вертикальный аналог publishAim (задача #71): тот же порог публикации, но без цикличности
	-- Aiming.Delta — угол места не оборачивается через ±180°, обычной разности достаточно.
	local function publishPitch(tower, desired)
		local previous = tower:GetAttribute("AimPitch")
		if previous == nil or math.abs(desired - previous) >= AIM_PUBLISH_STEP then
			tower:SetAttribute("AimPitch", desired)
		end
	end

	-- Ограничения самой турели для Targeting — слепая зона, земля/воздух и радиус кучи.
	-- Одно место на все три режима стрельбы, чтобы они не разошлись в том, по кому турель бьёт.
	local function aimFilter(towerData, tower)
		local filter = {
			minRange = towerData.minRange,
			targets = towerData.targets,
			groupRadius = towerData.splash and towerData.splash.radius,

			-- Линия огня: сквозь стены, постройки и поднятый пол турель не стреляет.
			--
			-- Исключение — Станция FPV-дронов (fireMode = "drone"): дрон не летит по прямой
			-- из ствола, а выходит из люка и облетает препятствия — ему преграда не помеха.
			-- Признак берётся из режима стрельбы, а не отдельным флагом в таблице: любая
			-- будущая турель на дронах получит то же свойство сама, без правки здесь.
			lineOfSight = towerData.fireMode ~= "drone",
			shooter = tower,
		}

		-- Сектор обстрела (Towers[тип].arc, Инжектор): цель вне сектора турель не выбирает
		-- вовсе. Без этого она «стреляла бы» по врагу за спиной, а ствол, упёртый в край
		-- сектора, смотрел бы в другую сторону — то же расхождение картинки и выстрела,
		-- ради которого доворот вообще считается одной формулой на обеих сторонах.
		--
		-- Центр сектора — фронт САМОЙ ПОСТРОЙКИ, а не мира: повернуть её при стройке
		-- можно (задача #76), и сектор обязан ехать вместе с ней. Нет arc в таблице —
		-- турель бьёт кругом, как и била: поля фильтра просто не появляются.
		if tower and towerData.arc then
			local look = tower:GetPivot().LookVector
			filter.arcCenter = math.atan2(-look.X, -look.Z)
			filter.arc = math.rad(towerData.arc) / 2
		end

		return filter
	end

	-- Снаряд по прямой (Колба, Инжектор) — ровно то, что делала StartFiring до задачи #53.
	--
	-- Башня решает только «в кого целиться и чем зарядить»: цель выбирает Targeting по режиму
	-- towerData.targeting, а в снаряд кладутся залитый элемент и уже посчитанный урон
	-- (Effects.ShotDamage). Самого урона здесь нет: HP цели меняется в момент попадания
	-- (см. Projectile), а по дороге снаряд может промазать или задеть вовсе не того, в кого целились.
	local function fireProjectile(tower, towerData, elementData, aimState)
		local geometry = BARRELS[tower:GetAttribute("Type")] or BARRELS.Ballista
		local towerPosition = tower:GetPivot().Position

		-- Куда смотрит ствол — часть условий поиска цели (задача #70): у турели с доворотом
		-- цель выбирается ещё и по тому, успеет ли башня на неё повернуться (closestReachable).
		local filter = aimFilter(towerData, tower)
		if aimState then
			filter.facing = aimState.angle
			filter.turnSpeed = towerData.turnSpeed
			filter.turnAccel = towerData.turnAccel
			filter.projectileSpeed = towerData.projectileSpeed
			filter.current = aimState.target -- кого турель ведёт: без этого она мечется по толпе
		end

		local target, distance = Targeting.FindTarget(towerPosition, towerData.range,
			enemiesFolder, towerData.targeting, filter)

		if not (target and target.Parent and (target:GetAttribute("HP") or 0) > 0) then
			if aimState then
				aimState.target = nil

				-- Пред-наводка: даже без цели в радиусе турель заранее поворачивается к ближайшему
				-- жуку на всей арене, чтобы к моменту его входа в радиус ствол уже смотрел в его
				-- сторону, а не начинал доворот с нуля. Радиус не ограничен нарочно — «ближайший»
				-- сам по себе всегда самый актуальный кандидат: не тот, кто дальше, а тот, кто раньше
				-- войдёт в радиус. Не трогает aimState.target — это поле только про цель в
				-- радиусе, по которой гистерезис closestReachable ведёт цель.
				-- Пред-наводка линию огня не спрашивает. Две причины. По сути: ствол ворочается
				-- заранее к тому, кто вот-вот войдёт в радиус, а тот вполне может сейчас идти
				-- за стеной и выйти из-за неё уже открытым. По цене: радиус здесь не ограничен,
				-- и луч на каждого жука арены с каждой молчащей турели — тысячи лучей в секунду
				-- ради одного поворота ствола.
				local aiming = filter.lineOfSight
				filter.lineOfSight = false

				local nearest, nearestDistance = nil, math.huge
				for _, enemy in Targeting.EnemiesInRange(towerPosition, math.huge, enemiesFolder, filter) do
					local enemyDistance = (enemy:GetPivot().Position - towerPosition).Magnitude
					if enemyDistance < nearestDistance then
						nearest, nearestDistance = enemy, enemyDistance
					end
				end

				filter.lineOfSight = aiming

				if nearest then
					local angle = Aiming.AngleTo(towerPosition, nearest:GetPivot().Position)
					if angle then
						-- Пред-наводка тоже сидит в секторе: кандидатов вне него и так отсеивает
						-- фильтр выше, но подрезка здесь стоит дёшево и держит инвариант
						-- «в AimAngle всегда угол из сектора» в одном месте.
						angle = clampArc(tower, angle, towerData.arc)
						aimState.desired = angle
						publishAim(tower, angle)
					end
				end
			end
			return false
		end

		if aimState then
			aimState.target = target
		end

		-- Упреждение считается от центра сферы, а ствол доворачивается уже на готовую точку:
		-- дуло сдвинуто от центра на пару студов, и уточнять прицел по нему — гоняться за
		-- собственным хвостом ради поправки меньше размера самого снаряда.
		local center = (tower:GetPivot() * CFrame.new(0, geometry.height, 0)).Position
		local aim = Projectile.PredictAim(center, target, towerData.projectileSpeed)

		-- Доворот (задача #70). Башня стреляет не в тот миг, когда увидела цель, а когда
		-- ствол на неё смотрит. Целимся в упреждённую точку, а не в самого жука: туда же
		-- уйдёт и снаряд, и ствол должен смотреть туда же, куда уйдёт выстрел.
		--
		-- Угол места запоминается: по нему не только качается картинка на клиенте, но и считается
		-- точка пуска снаряда ниже (meshMuzzle).
		local aimPitch = nil
		if aimState then
			local desired = Aiming.AngleTo(towerPosition, aim)
			if desired then
				-- Сектор обстрела (Инжектор): за край сектора ствол не выходит даже
				-- к упреждённой точке. Заодно это чинит и допуск ниже: требовать от ствола
				-- доехать туда, куда он по сектору доехать не может, значило бы запереть
				-- её стрельбу навсегда.
				desired = clampArc(tower, desired, towerData.arc)
				aimState.desired = desired
				publishAim(tower, desired)

				-- Допуск шире у близкой цели и уже у далёкой — это угловой размер самого жука
				-- (см. AIM_SPAN), а не постоянное число градусов.
				local tolerance = math.max(Aiming.TOLERANCE, math.atan(AIM_SPAN / math.max(distance, 1)))
				if math.abs(Aiming.Delta(aimState.angle, desired)) > tolerance then
					return false -- ещё доворачивается
				end
			end

			-- Вертикаль (задача #71): угол места на ту же упреждённую точку aim, что и по
			-- горизонтали: ствол должен смотреть туда же, куда уйдёт снаряд, а не в тело жука.
			-- Сам снаряд летит по aim независимо от того, довернулся ли меш по вертикали
			-- (Projectile.Fire берёт полностью трёхмерное направление), поэтому задержки выстрела
			-- на этот угол нет — только публикация для картинки.
			aimPitch = Aiming.PitchTo(center, aim)
			-- Пределы хода ствола по вертикали (rig.pitchMin/pitchMax, Инжектор). Подрезается
			-- ОДИН раз и здесь, до публикации: по этому же числу клиент ставит ствол, а ниже
			-- считается точка пуска — две подрезки в разных местах разошлись бы.
			--
			-- Сам снаряд летит по aim, а не по углу ствола (так же, как у Колбы с её
			-- подрезанными цапфами): подрезка — это предел картинки, а не правило стрельбы.
			local rig = geometry.rig
			if rig and rig.pitchMin and rig.pitchMax then
				aimPitch = math.clamp(aimPitch, math.rad(rig.pitchMin), math.rad(rig.pitchMax))
			end
			publishPitch(tower, aimPitch)
		end

		-- Снаряд стартует из НАСТОЯЩЕГО дула меша, а не с оси турели: у Колбы ствол
		-- сдвинут вбок, и точка на оси лежала между колбой и пушкой. У турелей без такого меша
		-- (Инжектор) meshMuzzle отдаёт nil, и всё считается по-старому — aimBarrel им ещё и ствол
		-- доворачивает, этого терять нельзя.
		-- У турели на риге с доворотом (Инжектор) снаряд стартует из дула в ТЕКУЩЕМ его
		-- положении (aimState.angle), а не в желаемом: стрелять она начинает, когда довернулась
		-- в пределах допуска, и этот остаток допуска точка пуска обязана учитывать.
		local muzzle = (aimState and geometry.rig and rigMuzzle(tower, geometry.rig, aimState.angle, aimPitch))
			or (aimState and meshMuzzle(tower, towerData.gun, aimState.angle, aimPitch))
			or aimBarrel(tower, aim, geometry, towerData)
		local color = elementData and elementData.color or SHOT_COLOR

		Projectile.Fire({
			origin = muzzle,
			aim = aim,
			speed = towerData.projectileSpeed,
			radius = towerData.projectileRadius,
			maxDistance = towerData.range + RANGE_OVERSHOOT,
			damage = Effects.ShotDamage(towerData.damage, elementData),
			element = elementData,
			color = color,
			ownerName = tower.Name,
			-- Форма снаряда и пробитие — свойства турели, а не снаряда: лежат в таблице
			-- (Towers[тип].projectileShape / .pierce) и просто передаются дальше. Нет полей —
			-- шар без пробития, то есть ровно то, что было у всех до этого.
			shape = towerData.projectileShape,
			pierce = towerData.pierce,
		})

		-- Третьим аргументом — сама турель (задача #69). По ней клиент находит настоящий дульный
		-- срез меша (CombatFX) и играет отдачу именно той башне, которая выстрелила
		-- (BuildingVisuals). Позиция muzzle остаётся первым аргументом и по-прежнему единственным
		-- источником для турелей без такого меша: сервер не знает, что клиент умеет с моделью.
		ShotFiredRemote:FireAllClients(muzzle, color, tower)

		print(("[%s] выстрел по %s (до выхода %.1f, дистанция %.1f)")
			:format(tower.Name, target.Name, EnemyProgress.Get(target) or 0, distance))

		return true
	end

	-- Пуск дрона (Станция FPV-дронов). Отличий от обычного выстрела два. Первое: целится не в тело
	-- жука, а в точку на полу под ним — дрон подрывается у земли, а не в теле цели. Второе:
	-- уронов два, и оба считаются от базовых чисел башни через тот же ShotDamage: элемент множит
	-- и прямой удар, и долю по площади — площадь здесь принадлежит турели, а не тому, чем она залита.
	--
	-- До задачи #75 это называлось навесом и ставило снаряду arc = true. Считается всё то же
	-- и теми же числами; поменялась одна строка — траектория (см. Projectile). Откат к мортирной
	-- дуге — вернуть там же arc = true вместо drone = true.
	local function fireDrone(tower, towerData, elementData)
		local geometry = BARRELS.Mortar
		-- Пивот берётся один раз: по нему считаются и поиск цели, и точка пуска, и обход
		-- створки — всё в одних координатах модели.
		local pivot = tower:GetPivot()
		local target, distance = Targeting.FindTarget(pivot.Position, towerData.range,
			enemiesFolder, towerData.targeting, aimFilter(towerData, tower))

		local hasTarget = target ~= nil and target.Parent ~= nil and (target:GetAttribute("HP") or 0) > 0

		-- Люк Станции FPV-дронов открыт ровно тогда, когда у станции есть цель в радиусе
		-- атаки — то есть тот же поиск, которым она выбирает, куда стрелять: со своей слепой
		-- зоной и со своим «только наземные». Второго поиска ради картинки заводить нельзя:
		-- разойдись они — и люк бы стоял открытым у станции, которая ни по кому не бьёт.
		-- Сама створка едет на клиенте (BuildingVisuals), сервер шлёт только «открыт/закрыт» —
		-- тот же довод, что у Spin и у наведения: каждый кадр гонять CFrame крышки с сервера
		-- значит реплицировать его ради одной картинки.
		if tower:GetAttribute("HatchOpen") ~= hasTarget then
			tower:SetAttribute("HatchOpen", hasTarget)
		end

		if not hasTarget then
			-- Пред-наводка (по образцу Колбы выше, fireProjectile): даже без цели в радиусе атаки
			-- антенна заранее разворачивается к ближайшему жуку на всей арене, чтобы к моменту
			-- его входа в радиус тарелка уже смотрела в его сторону, а не начинала доворот
			-- с нуля. Радиус не ограничен нарочно — тот же довод, что и у Колбы.
			local nearest, nearestDistance = nil, math.huge
			for _, enemy in Targeting.EnemiesInRange(pivot.Position, math.huge, enemiesFolder, aimFilter(towerData, tower)) do
				local enemyDistance = (enemy:GetPivot().Position - pivot.Position).Magnitude
				if enemyDistance < nearestDistance then
					nearest, nearestDistance = enemy, enemyDistance
				end
			end

			if nearest then
				local angle = Aiming.AngleTo(pivot.Position, nearest:GetPivot().Position)
				if angle then
					publishAim(tower, angle)
				end
			end

			return false
		end

		-- Антенна станции смотрит на ту же цель, по которой станция бьёт. Угол — тот же
		-- мировой AimAngle, что и у Колбы, а саму тарелку ведёт клиент (BuildingVisuals) —
		-- тот же довод, что у створки люка: гонять её CFrame с сервера значило бы реплицировать
		-- его каждый кадр ради одной картинки. Второго поиска цели ради антенны нет по той же
		-- причине, что и у люка — разойдись они, и тарелка смотрела бы не на того, кого бьёт.
		-- Обновляется ровно так же часто, как HatchOpen: цикл стрельбы переспрашивает цель каждые
		-- AIM_TICK, а после выстрела спит свой темп — в это время антенна держит прошлый пеленг.
		local bearing = Aiming.AngleTo(pivot.Position, target:GetPivot().Position)
		if bearing then
			publishAim(tower, bearing)
		end

		local center = (pivot * CFrame.new(0, geometry.height, 0)).Position
		local aim = Projectile.PredictAim(center, target, towerData.projectileSpeed)
		local landing = Vector3.new(aim.X, Arena.floorY, aim.Z)
		local muzzle = aimBarrel(tower, landing, geometry)
		local color = elementData and elementData.color or SHOT_COLOR

		-- Отход от откинутой створки: дрон поднимается из шахты и уходит вбок вдоль оси петли,
		-- а не прошивает крышку насквозь. Сторона выбирается та, куда и цель: отход тогда
		-- сразу идёт в счёт пути, а не отматывается назад. Вся геометрия — в координатах модели,
		-- поэтому повёрнутая при стройке станция облетает свою створку так же верно.
		local exit = nil
		local lid = geometry.lid
		if lid then
			local course = pivot:VectorToObjectSpace(landing - muzzle)
			local flatCourse = Vector3.new(course.X, 0, course.Z)
			if flatCourse.Magnitude > 1e-3 and flatCourse.Unit:Dot(lid.facing) > lid.cone then
				local side = course:Dot(lid.axis) >= 0 and 1 or -1
				exit = (pivot * CFrame.new(geometry.mount
					+ lid.axis * (side * lid.side)
					+ Vector3.new(0, lid.lift, 0))).Position
			end
		end

		Projectile.Fire({
			origin = muzzle,
			aim = landing,
			drone = true,
			-- Высота собственных крыш: дрон выходит из шахты над них, а не сквозь градирню.
			clearance = (pivot * CFrame.new(0, geometry.clearance, 0)).Position.Y,
			exit = exit,
			speed = towerData.projectileSpeed,
			radius = towerData.projectileRadius,
			damage = Effects.ShotDamage(towerData.damage, elementData),
			splash = {
				radius = towerData.splash.radius,
				damage = Effects.ShotDamage(towerData.splash.damage, elementData),
			},
			targets = towerData.targets,
			element = elementData,
			color = color,
			ownerName = tower.Name,
		})

		ShotFiredRemote:FireAllClients(muzzle, color, tower)

		print(("[%s] дрон пошёл на %s (дистанция %.1f)"):format(tower.Name, target.Name, distance))
		return true
	end

	-- Площадь вокруг себя (Испаритель, Бур, Центрифуга). Турель ни в кого не целится
	-- и ничего не выпускает: раз в тик она бьёт СРАЗУ по всем подходящим целям в радиусе.
	-- Снаряда нет, поэтому урон, броня и эффекты считаются здесь теми же Effects, что и при
	-- попадании снаряда — модель урона одна на всех.
	--
	-- Центр зоны не всегда совпадает с турелью: areaHeight поднимает его над ней (облако
	-- Испарителя — на 6 studs). От облака до земли при этом ближе, чем его радиус (6.2 против 8),
	-- поэтому наземных под собой облако не трогает именно из-за фильтра targets = "air",
	-- а не из-за высоты: убери фильтр — и начнёт трогать.
	--
	-- Лога на тик нет нарочно: пять тиков в секунду у Испарителя превратили бы вывод в поток,
	-- в котором не видно ничего остального. Цифры урона над жуками показывает DamageDealt.
	local function fireArea(tower, towerData, elementData)
		local center = tower:GetPivot().Position
		if towerData.areaHeight then
			center += Vector3.new(0, towerData.areaHeight, 0)
		end

		local targets = Targeting.EnemiesInRange(center, towerData.range, enemiesFolder, aimFilter(towerData, tower))
		if #targets == 0 then
			return false
		end

		local damage = Effects.ShotDamage(towerData.damage, elementData)
		for _, enemy in targets do
			-- Проверка повторяется внутри цикла: список снят один раз, а эффекты предыдущей
			-- цели (цепочка, детонация) вполне могли убить следующую ещё до того, как до неё дошла очередь.
			if enemy.Parent and (enemy:GetAttribute("HP") or 0) > 0 then
				-- Откуда ударили — для лобового щита Щитоносца, точно так же, как это
				-- делает снаряд (см. Projectile.dealDamage). У площадной это центр её зоны.
				enemy:SetAttribute("HitFrom", center)
				local dealt = Effects.HitDamage(enemy, elementData, damage)
				if dealt > 0 then
					local hp = math.max(0, (enemy:GetAttribute("HP") or 0) - dealt)
					enemy:SetAttribute("HP", hp)
					DamageDealtRemote:FireAllClients(enemy:GetPivot().Position, dealt, true)
				end
				if elementData then
					-- Четвёртым — откуда ударили: притяжение (Воздух и вся его ветка) тянет
					-- к стрелявшей турели, а у площадной это центр её зоны, а не сам пивот:
					-- облако Испарителя висит над ней.
					Effects.Apply(enemy, elementData, dealt, center)
				end
			end
		end

		return true
	end

	local FIRE_MODES = {
		projectile = fireProjectile,
		drone = fireDrone, -- до задачи #75 ключ звался mortar, а функция — fireMortar
		area = fireArea,
	}

	-- Запускает боевой цикл башни. Работает для любой построенной башни независимо —
	-- каждая вызывает это отдельно при постройке.
	--
	-- Здесь осталось только общее для всех турелей: залитый элемент, разгон Воздуха и темп.
	-- Сам удар — за fireMode (FIRE_MODES выше): он возвращает, состоялся ли выстрел, и больше
	-- цикл о нём ничего не знает.
	function TowerBuilder.StartFiring(tower, towerType)
		local towerData = Towers[towerType]
		assert(towerData, ("[TowerBuilder] неизвестный тип башни: %s"):format(tostring(towerType)))

		local fire = FIRE_MODES[towerData.fireMode or "projectile"]
		assert(fire, ("[TowerBuilder] неизвестный режим стрельбы: %s"):format(tostring(towerData.fireMode)))

		task.spawn(function()
			-- Темп бывает дробным (0.2 у Инжектора, 1.5 у Центрифуги), поэтому %.2f, а не %d:
			-- целочисленный формат на дроби в Luau падает с ошибкой, а не округляет.
			print(("[%s] готова: радиус %s, темп %.2f/сек, базовый урон %d, режим %s")
				:format(
					tower.Name,
					towerData.minRange and ("%d–%d"):format(towerData.minRange, towerData.range) or tostring(towerData.range),
					towerData.fireRate,
					towerData.damage,
					towerData.fireMode or "projectile"
				))

			-- Разгон воздуха (fireRateRamp): выстрелы подряд и момент последнего выстрела. Живёт
			-- здесь, а не в Effects — это тайминг стрельбы конкретной башни, а не эффект на цели.
			local rampStreak = 0
			local lastFireClock = os.clock()

			-- Состояние доворота ствола (задача #70) живёт здесь, а не в общей таблице по башням:
			-- оно нужно ровно на время жизни турели, а этот цикл и есть её жизнь — снесли постройку,
			-- кончился цикл, и убирать за собой нечего. Заводится только у турели с turnSpeed в Towers;
			-- у остальных aimState — nil, и все ветки доворота просто не включаются.
			--
			-- Стартовый угол — фронт САМОЙ ПОСТРОЙКИ, а не мировой ноль: повёрнутая при
			-- стройке турель (задача #76) считала бы, что ствол смотрит в мировой ноль,
			-- и на первой же цели прокручивалась бы к ней от чужого направления. Клиент
			-- стартует именно оттуда (BuildingVisuals, restYaw), и две стороны обязаны совпадать.
			local aimState = nil
			if towerData.turnSpeed then
				local look = tower:GetPivot().LookVector
				aimState = { angle = math.atan2(-look.X, -look.Z), velocity = 0, clock = os.clock() }
			end

			while tower.Parent do
				-- Ствол едет к прошлой выбранной точке независимо от того, стреляли мы или нет:
				-- пока он в пути, выстрелов не будет, а угол меняться обязан.
				if aimState then
					local now = os.clock()
					aimState.angle, aimState.velocity = Aiming.Step(aimState.angle, aimState.velocity,
						aimState.desired or aimState.angle, now - aimState.clock,
						towerData.turnSpeed, towerData.turnAccel)
					aimState.clock = now
				end

				local elementKey = tower:GetAttribute("Element")
				local elementData = elementKey and Elements[elementKey]
				local ramp = elementData and elementData.fireRateRamp

				-- Лицехват присосался (Enemies.Facehugger, см. EnemySpawner.flyToTurret): турель вообще не ищет
				-- и не бьёт цель, пока висит атрибут Suppressed — его ставит и снимает сам Лицехват.
				-- Площадных это касается так же: глушится любая турель, а не только стреляющая снарядом.
				local fired = false
				if not tower:GetAttribute("Suppressed") then
					fired = fire(tower, towerData, elementData, aimState)
				elseif tower:GetAttribute("HatchOpen") then
					-- Заглушённая Лицехватом станция никого не выпускает — значит и люк закрыт.
					-- Формально это общий цикл, но атрибут есть только у неё: без этой ветки люк
					-- застывал бы открытым на всё время, пока висит Suppressed: fireMortar,
					-- который его закрывает, в этот момент вообще не вызывается.
					tower:SetAttribute("HatchOpen", false)
				end

				if not ramp then
					-- Разгон осмыслен только пока залит элемент с fireRateRamp: вынули Воздух — следующая
					-- заливка начинает раскрутку с нуля, а не с прежнего темпа.
					rampStreak = 0
				elseif not fired and (os.clock() - lastFireClock) > ramp.resetAfter then
					rampStreak = 0
				end

				if fired then
					lastFireClock = os.clock()
					if ramp then
						rampStreak += 1
					end
				end

				-- Скорострельность пересчитывается каждый выстрел: элемент можно залить или вынуть
				-- на лету, бонус должен подхватываться сразу, а не со следующей башни. У Воздуха
				-- вместо плоского множителя — разгон: темп растёт на ramp.step за каждый выстрел
				-- подряд, до потолка ramp.max.
				local fireRate = towerData.fireRate
				if elementData and elementData.fireRateBonus then
					-- Бонус бывает отрицательным (Гора: −0.6, то есть выстрел раз в 2.5 сек) —
					-- это «цена в темпе стрельбы» из документа, отдельного поля под неё не нужно.
					fireRate *= (1 + elementData.fireRateBonus)
				elseif ramp then
					-- exponent > 1 делает разгон нелинейным (Торнадо): первые выстрелы прибавляют
					-- меньше, чем у Ветра, зато к пятому подряд темп уже у потолка. ramp.base
					-- переопределяет точку отсчёта вместо towerData.fireRate (Извержение: старт выше,
					-- шаг почти незаметный, не как у Воздуха) — без него все четыре разгонных
					-- элемента стартуют с одной и той же точки.
					fireRate = math.min((ramp.base or towerData.fireRate) + ramp.step * rampStreak ^ (ramp.exponent or 1), ramp.max)
				end
				-- Нижняя граница — страховка от опечатки в таблице: fireRateBonus <= −1 дал бы
				-- ноль или минус, а task.wait от этого завис башню навсегда.
				-- Отстрелявшаяся турель ждёт свой полный темп — скорострельность от этой задачи
				-- не меняется. А вот НЕ отстрелявшаяся (нет цели, ствол ещё в пути или висит
				-- Лицехват) переспрашивает часто: иначе доворот стоил бы ей целого выстрела —
				-- ствол доезжает через полсекунды после проверки, а ждать её пришлось бы секунду.
				task.wait(fired and (1 / math.max(fireRate, 0.05)) or AIM_TICK)
			end
		end)
	end

	-- Общая часть постройки: ставит модель в клетку сетки, занимает клетку, запускает
	-- автонаведение. Материю не трогает — этим отдельно занимаются Build/BuildFree.
	--
	-- Клетка запоминается атрибутами CellX/CellZ, чтобы освобождать её по самой постройке,
	-- без обратного поиска по всей сетке. Атрибут Type хранит ключ из Towers: по нему видно,
	-- что это за постройка, без разбора её имени или содержимого.
	--
	-- Стреляет ли постройка, решает всё тот же один признак — есть ли у типа fireRate (см. Towers);
	-- модель берётся из MODELS по типу.
	-- Радиус следа постройки в клетках — по её ФАКТИЧЕСКОМУ размеру (footprint в Towers),
	-- а не по общему шагу сетки. Одно место на всех, кто занимает и проверяет клетки:
	-- разойдись проверка «свободно» с записью занятости — и постройка встала бы туда,
	-- куда сама себя не пустила.
end
