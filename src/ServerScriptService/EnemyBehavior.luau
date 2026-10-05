-- Поведение жуков по кастам: куда идти, что делать этот кадр, как отвечать на урон.
--
-- Движение по маршруту, грызня и перелезание остались в EnemySpawner — они общие
-- для всех. Остальное разложено по модулям:
--
--   EnemySense   — общие чувства и память: кто жив, где турель, куда спрятаться,
--                  заявки «пойти в точку», что знает колония;
--   EnemyTraits  — особые механики видов: одно поле в Enemies = одна функция там;
--   EnemyFlight  — летуны со своим циклом движения (Моль, Матка, Личинка, Пеликан);
--   здесь        — касты: цель маршрута, паника, сбор группы, приказы Координатора.
--
-- Новый жук без новой механики добавляется СТРОКОЙ в Enemies и сюда не лезет вовсе —
-- это требование RULES.md, а не удобство. Общие правила касты — Enemies.Castes.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Enemies = require(ReplicatedStorage:WaitForChild("Enemies"))
local Grid = require(ServerScriptService:WaitForChild("Grid"))
local LabTable = require(ServerScriptService:WaitForChild("LabTable"))
local EnemyStructures = require(ServerScriptService:WaitForChild("EnemyStructures"))
-- Рельеф бетонного пола: окоп спрашивается у самого пола.
local ConcreteFloor = require(ServerScriptService:WaitForChild("ConcreteFloor"))
local Sense = require(ServerScriptService:WaitForChild("EnemySense"))
local EnemyTraits = require(ServerScriptService:WaitForChild("EnemyTraits"))
local EnemyFlight = require(ServerScriptService:WaitForChild("EnemyFlight"))

local alive, flat = Sense.alive, Sense.flat
local enemiesFolder = Sense.enemiesFolder

local EnemyBehavior = {}

-- Особые механики и летуны — наружу тем же именем, что и раньше: EnemySpawner
-- зовёт их через EnemyBehavior и про раскладку по модулям знать не обязан.
EnemyBehavior.CarriedBy = EnemyTraits.CarriedBy
EnemyBehavior.Detonate = EnemyTraits.Detonate
EnemyBehavior.Burst = EnemyTraits.Burst
EnemyBehavior.Spill = EnemyTraits.Spill
EnemyBehavior.Absorb = EnemyTraits.Absorb
EnemyBehavior.ElementHit = EnemyTraits.ElementHit
EnemyBehavior.OwnLoop = EnemyFlight.OwnLoop
EnemyBehavior.FlyStep = EnemyFlight.FlyStep
EnemyBehavior.AboveTower = EnemyFlight.AboveTower

-- Бонус хитина к скорости — из таблицы Архитектора, а не числом в коде: он один на всех,
-- кто по хитину идёт, и живёт там же, где сам хитин.
local CHITIN_SCALE = 1
for _, data in Enemies do
	if type(data) == "table" and data.chitin and data.chitin.speedBonus then
		CHITIN_SCALE = 1 + data.chitin.speedBonus
	end
end

-- ============================ Цель ============================

-- Периметр арены для Хмурого брона: четыре угла с отступом от стены. «Идёт вдоль
-- стен. Разрушает всё что попадается» — разрушение само собой выходит из того, что
-- общая грызня в EnemySpawner останавливает его перед любой постройкой на пути.
local PERIMETER_INSET = 8 -- studs от края поля

local function perimeterCells()
	local inset = math.max(2, math.floor(PERIMETER_INSET / Grid.CellSize))
	local minX, maxX = inset, Grid.Cols - inset
	local minZ, maxZ = inset, Grid.Rows - inset
	return {
		{ x = minX, z = minZ },
		{ x = maxX, z = minZ },
		{ x = maxX, z = maxZ },
		{ x = minX, z = maxZ },
	}
end

-- Блуждание маршрута (Grid.GetRouteTo, параметр wander): маршрут всё так же ведёт к цели
-- по полю волн, но на части шагов сворачивает в сторону. Разведчик, не знающий, где стол,
-- петляет из стороны в сторону («блуждает по полу»); солдат держит свою сторону,
-- и «десять солдат идут десятью разными путями». Знающий разведчик идёт прямо.
local function tableWander(enemyData, state)
	local caste = enemyData.caste
	if enemyData.explores then
		local explore = Sense.rules(caste).explore
		if explore and not (state.found or Sense.LabKnown()) then
			return { budget = explore.meander, chance = 1, side = state.side,
				flip = explore.flip, seed = state.wanderSeed }
		end
		return nil
	end
	local spread = enemyData.spread or Sense.rules(caste).spread
	if spread then
		return { budget = Sense.rules(2).budget or 1, chance = spread, side = state.side,
			seed = state.wanderSeed }
	end
	return nil
end

-- Куда вести маршрут. Возвращает клетку, режим (что ждёт по прибытии) и блуждание.
function EnemyBehavior.Goal(enemy, enemyData, state)
	local goal = enemyData.goal

	-- Очищенный (Мыло) идёт к ближайшему наземному врагу — драться. Врагов нет —
	-- стоит, где стоял, и ждёт следующей волны.
	if state.ally then
		local position = enemy:GetPivot().Position
		local best, bestDistance = enemy, math.huge
		for _, other in enemiesFolder:GetChildren() do
			if alive(other) and not other:GetAttribute("Flying") then
				local distance = flat(other:GetPivot().Position - position).Magnitude
				if distance < bestDistance then
					best, bestDistance = other, distance
				end
			end
		end
		local cx, cz = Grid.ToCell(best:GetPivot().Position)
		return cx, cz, "ally"
	end

	-- Заявка «пойти в точку» от механики (укрытие, вожак, засада, раненый). Сильнее
	-- любой своей цели: жук идёт туда, куда его зовёт дело, а не к столу.
	local goTo = state.goTo
	if goTo and goTo.expires and os.clock() >= goTo.expires then
		state.goTo = nil
		goTo = nil
	end
	if goTo and not goTo.failed then
		local cx, cz = Grid.ToCell(goTo.position)
		return cx, cz, "point"
	end

	-- Группа работяг вышла и встретила турель, солдат вышел на ближнюю или её указал
	-- Координатор — турель перебивает любую свою цель. Сносят её той же общей грызнёй:
	-- подошли вплотную — постройка встала преградой на пути, и грызня сама её ломает.
	local focus = state.focusTurret
	if focus and focus.Parent then
		local cx, cz = Grid.ToCell(focus:GetPivot().Position)
		return cx, cz, "turret"
	end

	if goal == "table" then
		-- Стол разбит — грызть больше нечего, и жук идёт к выходу. Без этой ветки
		-- вся волна вставала бы вокруг обломков стола и никогда не кончалась.
		if LabTable.IsAlive() then
			local cx, cz = LabTable.Cell()
			return cx, cz, "table", tableWander(enemyData, state)
		end
		local cx, cz = Grid.GetExitCell()
		return cx, cz, "exit"
	end

	if goal == "perimeter" then
		local ring = state.ring
		if not ring then
			ring = perimeterCells()
			state.ring = ring
			-- Начинает с ближайшего угла, а не всегда с первого: иначе все броны
			-- идут одной колонной в один и тот же угол. И обходит круг в свою сторону:
			-- половина по часовой, половина против — периметр держат с обеих сторон.
			local cx, cz = Grid.ToCell(enemy:GetPivot().Position)
			local best, bestDistance = 1, math.huge
			for i, cell in ring do
				local distance = math.abs(cell.x - cx) + math.abs(cell.z - cz)
				if distance < bestDistance then
					best, bestDistance = i, distance
				end
			end
			state.ringIndex = best
			state.ringStep = state.side or 1
		end
		local cell = ring[state.ringIndex]
		return cell.x, cell.z, "perimeter"
	end

	local cx, cz = Grid.GetExitCell()
	return cx, cz, "exit"
end

-- Жук дошёл до конца маршрута. Возвращает "breach", если это прорыв, и nil, если
-- жук просто продолжает жить на месте (грызёт стол, идёт по периметру дальше).
function EnemyBehavior.Arrived(enemy, enemyData, state, mode)
	if mode == "perimeter" then
		-- Следующий угол. Круг замкнут: «пока не уничтожен» — то есть бесконечно.
		local count = #state.ring
		state.ringIndex = (state.ringIndex - 1 + (state.ringStep or 1)) % count + 1
		return nil
	end

	if mode == "point" then
		if state.goTo then
			state.goTo.reached = true
		end
		return nil
	end

	if mode == "table" or mode == "turret" or mode == "ally" then
		return nil -- грызёт стол / турель стоит преградой / очищенный кусает врага
	end

	return "breach"
end

-- Каждый кадр из EnemySpawner: дошёл ли жук до точки заявки и не истекла ли она.
-- Точку считаем достигнутой по радиусу, а не по концу маршрута: в толкучке
-- центр клетки обычно занят соседом.
function EnemyBehavior.Track(enemy, state, position)
	local goTo = state.goTo
	if not goTo then
		return
	end
	if goTo.expires and os.clock() >= goTo.expires then
		state.goTo = nil
		state.repath = true
		return
	end
	if not goTo.reached and not goTo.failed
		and flat(goTo.position - position).Magnitude <= goTo.radius then
		goTo.reached = true
	end
end

-- Грызня стола. Жук стоит у стола и бьёт его со своим темпом — тем же, что и постройки.
-- tableBite — укус стола у того, кто стены грызть не может (Мини: «даже стены грызть не
-- может», но разведчики «нашли — грызут стол»).
function EnemyBehavior.BiteTable(enemy, enemyData, state)
	local chewDamage = enemyData.tableBite or enemyData.chewDamage or 0
	if chewDamage <= 0 or not LabTable.IsAlive() then
		return false
	end

	local now = os.clock()
	local attackSlow = math.clamp(enemy:GetAttribute("AttackSlowPercent") or 0, 0, 0.9)
	local rate = (enemyData.chewRate or 1) * (1 - attackSlow)
	if now - (state.lastTableBite or 0) < 1 / math.max(rate, 0.05) then
		return true
	end
	state.lastTableBite = now

	local weakened = math.clamp(enemy:GetAttribute("Weakened") or 0, 0, 0.9)
	local bite = math.max(1, math.floor(chewDamage * (1 - weakened) + 0.5))
	LabTable.Bite(bite)
	return true
end

-- Дошёл до стола, а грызть его нечем. Что дальше — решает вид:
--   Подрывник — рвёт заряд прямо у стола: стол для него такая же преграда, как стена;
--   Спринтер и Тень — «добежал»: один удар по столу с разбега (breachBite) и прорыв;
--   остальные (Координатор, Медик, Кислотник, Кукольник) — прорыв, как и раньше:
--   стоять у стола вечно они не могут, иначе волна не кончится.
-- Возвращает "breach" или nil (жук остаётся на поле).
function EnemyBehavior.TableReached(enemy, enemyData, state)
	if enemyData.charge then
		EnemyTraits.Detonate(enemy, enemyData)
		return nil
	end
	if enemyData.breachBite and LabTable.IsAlive() then
		print(("[Прорыв] %s добежал до лаборатории и бьёт стол на %d"):format(enemy.Name, enemyData.breachBite))
		LabTable.Bite(enemyData.breachBite)
	end
	return "breach"
end

-- ============================ Паника ============================

-- Урон по жуку. Зовётся из EnemySpawner по падению HP — там же, где считается кровь.
--
-- Откуда стреляли, жуку никто не говорит (урон приходит из полудюжины мест),
-- поэтому отходит он ОТ БЛИЖАЙШЕЙ ТУРЕЛИ — в девяти случаях из десяти это она
-- и есть. Турелей нет вовсе — паниковать не от чего.
function EnemyBehavior.Damaged(enemy, enemyData, state, amount)
	if state.ally then
		return
	end

	-- «Попадание в заряд — преждевременная детонация»: заряд взводится у стены, и
	-- любое попадание в это окно рвёт его сразу — там, где Подрывник стоит.
	if enemyData.charge and state.arming then
		EnemyTraits.Detonate(enemy, enemyData)
		return
	end

	if enemyData.mimics then
		EnemyTraits.MimicHit(enemy, enemyData, state)
	end

	local panic = enemyData.panic
	if not panic then
		return -- Хмурый брон слеп: не видит турели и не пугается; солдаты не паникуют
	end

	local position = enemy:GetPivot().Position
	local turret = Sense.nearestTurret(position)
	if not turret then
		return
	end

	local now = os.clock()
	local rules = Sense.rules(enemyData.caste)

	if panic == "scout" then
		-- «Пугаются — отходят, через 3 секунды возвращаются.» Каждое новое попадание
		-- продлевает срок: под непрерывным огнём жук так и не возвращается, и это верно.
		-- Разбегаются веером, а не одной колонной строго от турели: у каждого свой
		-- угол отхода в пределах scatter, выбранный в момент испуга.
		if not (state.panicUntil and now < state.panicUntil) then
			local scatter = math.rad(rules.scatter or 0)
			state.fleeAngle = (math.random() * 2 - 1) * scatter
		end
		state.fleeFrom = turret:GetPivot().Position
		state.panicUntil = now + (enemyData.panicReturn or 3)
	elseif panic == "worker" then
		-- «Получает урон — отходит в безопасное место. Ждёт пока рядом соберётся 5 работяг.»
		if state.regrouping then
			return
		end
		local plan = rules.retreat
		if not plan then
			return
		end
		local spot = Sense.SafeSpot(enemy, turret, plan)
		state.regrouping = true
		state.regroupUntil = now + plan.patience
		state.hiding = false
		if spot then
			Sense.GoTo(state, spot, 3, "retreat", 3)
		else
			-- Укрыться негде (зажат у стены поля): ждёт группу там, где стоит.
			state.hiding = true
		end
		print(("[Работяги] %s ранен и отходит в укрытие"):format(enemy.Name))
	end
end

-- Смерть жука. Разведчики рядом видят, как погиб свой, и шарахаются от этого места:
-- «отпугивание работает, но жуки возвращаются снова».
function EnemyBehavior.Died(enemy, enemyData, at)
	local alarm = Sense.rules(0).alarm
	if not alarm then
		return
	end
	local now = os.clock()
	for _, other in Sense.enemiesAround(at, alarm.radius, enemy) do
		local otherState = Sense.states[other]
		local data = Sense.dataOf(other)
		if otherState and data and data.panic == "scout" and not otherState.ally then
			if not (otherState.panicUntil and now < otherState.panicUntil) then
				local scatter = math.rad(Sense.rules(data.caste).scatter or 0)
				otherState.fleeAngle = (math.random() * 2 - 1) * scatter
				otherState.fleeFrom = at
				otherState.panicUntil = now + alarm.time
			end
		end
	end
end

-- Сколько своих (та же каста) стоит рядом, считая самого жука.
local function gatheredAround(enemy, enemyData, radius)
	local gathered = 1
	for _, other in Sense.enemiesAround(enemy:GetPivot().Position, radius, enemy) do
		local otherData = Sense.dataOf(other)
		if otherData and otherData.caste == enemyData.caste and not other:GetAttribute("Flying") then
			gathered += 1
		end
	end
	return gathered
end

-- Что жук делает этот кадр: nil — идёт по маршруту, "flee" — отходит, "hold" — стоит.
function EnemyBehavior.State(enemy, enemyData, state)
	local now = os.clock()

	-- Очищенный (Мыло) живёт без касты: ни паники, ни механик — только идёт и дерётся.
	if state.ally then
		return nil
	end

	-- Механика держит жука на месте (копает, маскируется, нацеливается, строит).
	if state.holdUntil and now < state.holdUntil then
		return "hold"
	end

	-- Медик с грузом уносит его прочь от турели (см. EnemyTraits.heals).
	if state.carrying then
		return "flee"
	end

	if state.panicUntil and now < state.panicUntil then
		return "flee"
	end

	if state.regrouping then
		-- Идёт в укрытие: маршрут ведёт заявка "retreat" (Goal → "point").
		local goTo = state.goTo
		local walking = goTo ~= nil and goTo.tag == "retreat" and not goTo.reached and not goTo.failed
		if walking and now < state.regroupUntil then
			return nil
		end
		state.hiding = true

		-- Выходят вместе, когда рядом набралось groupSize своих (считая себя).
		-- Свои — это любые работяги (каста 1), а не только тот же вид: группа в документе
		-- — это каста, а не вид.
		local plan = Sense.rules(enemyData.caste).retreat
		local need = enemyData.groupSize or 5
		local gathered = gatheredAround(enemy, enemyData, plan and plan.gather or 18)

		if gathered >= need or now >= state.regroupUntil then
			state.regrouping = false
			state.hiding = false
			state.fleeFrom = nil
			Sense.ClearGoTo(state, "retreat")
			-- «Группой выходят. Встретили турель — группой атакуют.» Один — никогда:
			-- цель-турель ставится только тому, кто дождался группы, а не вышедшему
			-- по истечении терпения.
			if gathered >= need then
				local turret = Sense.nearestTurret(enemy:GetPivot().Position)
				if turret then
					state.focusTurret = turret
					-- Тот же флаг, что и у приказа Координатора: без него группа «выходит
					-- на турель» только в логе, а ногами идёт по старому маршруту к столу.
					state.repath = true
					print(("[Работяги] группа из %d вышла на %s"):format(gathered, turret.Name))
				end
			end
			state.repath = true
			return nil
		end

		return "hold"
	end

	-- Дошёл до точки заявки и стоит там (укрытие, место за спиной вожака, засада).
	local goTo = state.goTo
	if goTo and goTo.reached then
		return "hold"
	end

	return nil
end

-- Куда отходит испуганный: прочь от того, от чего бежит, под своим углом разброса.
function EnemyBehavior.FleeStep(enemy, state, step)
	local position = enemy:GetPivot().Position
	local away = flat(position - (state.fleeFrom or position))
	if away.Magnitude < 1e-3 then
		away = Vector3.new(math.cos(state.seed or 0), 0, math.sin(state.seed or 0))
	end
	local angle = state.fleeAngle or 0
	if angle ~= 0 and not state.carrying then
		local c, s = math.cos(angle), math.sin(angle)
		away = Vector3.new(away.X * c - away.Z * s, 0, away.X * s + away.Z * c)
	end
	return away.Unit * step
end

-- Множитель скорости от пола под ногами: на хитине жуки быстрее. Заодно
-- проставляет атрибут InTrench, по которому турели теряют по нему радиус (см. Targeting):
-- пол спрашивается один раз на кадр и сразу на оба вопроса.
function EnemyBehavior.Ground(enemy, state)
	local at = enemy:GetPivot().Position
	local onChitin = EnemyStructures.OnChitin(at)
	-- Укрытие спрашивается у самого пола, а не у списка конструкций: в яме можно
	-- оказаться не только из-за Строителя, но и из-за Литосферы — а прячет одинаково.
	local inTrench = ConcreteFloor.IsCover(at.X, at.Z)

	if inTrench ~= (state.inTrench or false) then
		state.inTrench = inTrench
		enemy:SetAttribute("InTrench", inTrench or nil)
	end

	return onChitin and CHITIN_SCALE or 1
end

-- Новый забег: колония снова не знает, где лаборатория.
function EnemyBehavior.Reset()
	Sense.ResetColony()
end

-- ============================ Фокус солдат ============================
--
-- «Без координатора солдаты идут каждый на ближайшую. С координатором — все на одну.
-- Уничтожить координатора — солдаты теряют фокус.»
--   • приказ Координатора приходит со сроком (Sense.focus) и перебивает всё;
--   • погиб отдавший приказ — солдат на lostFocus секунд теряется (стоит) и бросает цель;
--   • без приказа солдат с полем engage сам выходит на ближнюю турель в этом радиусе.
--     Гигант и Спринтер поля не имеют: первый «просто не останавливается», второй «мимо всего».
local function focusLoop(enemy, enemyData, state)
	local caste = enemyData.caste
	while alive(enemy) do
		if not Sense.naps(enemy, 0.5) then
			return
		end
		if state.ally then
			return
		end

		local before = state.focusTurret
		local now = os.clock()
		local order = Sense.focus[enemy]

		if order then
			if not alive(order.by) and order.turret == state.focusTurret then
				-- Координатор убит: солдаты теряют фокус.
				Sense.focus[enemy] = nil
				state.focusTurret = nil
				state.focusBy = nil
				local lost = Sense.rules(caste).lostFocus
				if lost then
					state.holdUntil = now + lost
					print(("[Солдаты] %s потерял фокус"):format(enemy.Name))
				end
			elseif now < order.expires and order.turret.Parent then
				state.focusTurret = order.turret
				state.focusBy = order.by
			else
				Sense.focus[enemy] = nil
				state.focusBy = nil
			end
		end

		-- Цель снесена — забыть её; кто её снёс, неважно.
		if state.focusTurret and not state.focusTurret.Parent then
			state.focusTurret = nil
			state.focusBy = nil
		end

		-- Своя цель солдата: ближняя турель в радиусе engage, если приказа нет.
		if enemyData.engage and not state.focusTurret and not Sense.focus[enemy]
			and not (state.holdUntil and now < state.holdUntil) then
			local turret, distance = Sense.nearestTurret(enemy:GetPivot().Position)
			if turret and distance <= enemyData.engage then
				state.focusTurret = turret
				print(("[Солдаты] %s вышел на ближнюю турель %s"):format(enemy.Name, turret.Name))
			end
		end

		-- Смена цели САМА ПО СЕБЕ ничего не делает: маршрут пересчитывается только по
		-- смене занятости клеток (Grid.Changed), а приказ занятость не меняет.
		if state.focusTurret ~= before then
			state.repath = true
		end
	end
end

-- ============================ Запуск ============================

-- Заводит состояние жука и запускает все его механики. Механика запускается тем и только
-- тем, что в записи врага есть поле с её именем.
function EnemyBehavior.Attach(enemy, enemyData)
	local state = {
		seed = math.random() * math.pi * 2,
		-- Своя сторона: куда сворачивает на блуждании, в какую сторону обходит периметр,
		-- куда кружит Моль. Половина жуков — в одну, половина — в другую.
		side = math.random() < 0.5 and -1 or 1,
		wanderSeed = math.random(1, 1000000),
	}
	Sense.states[enemy] = state

	for field, start in EnemyTraits.TRAITS do
		if enemyData[field] then
			task.spawn(start, enemy, enemyData, state)
		end
	end

	task.spawn(focusLoop, enemy, enemyData, state)

	return state
end

return EnemyBehavior
