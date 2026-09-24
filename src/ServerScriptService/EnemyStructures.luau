-- Всё, что жуки ставят на карте сами (design: alchemy_td_enemies.md, каста 1 и каста 3).
--
-- Семь видов объектов, все одной механикой жизни (HP, горение, снос):
--
--   ruin   — руина. Остаётся от ЛЮБОЙ разрушенной постройки и от Окопщика
--            с Пеликаном. Строитель их ест и строит из них всё остальное.
--   wall   — Стена Строителя: «блокирует линию огня турелей». Жукам она НЕ мешает
--            и клетки сетки не занимает: займи она их — жуки стали бы обгрызать
--            собственную постройку. За ней они «группируются безопасно» — именно
--            потому, что турель их через неё не видит (см. Targeting).
--   ramp   — Пандус, прислонённый к постройке игрока. Помечает её атрибутом Ramped:
--            через такую постройку перелезают все, а не только альпинисты (см. Grid.Crossing).
--   feeder — Кормушка: жуки рядом регенерируют, сама со временем истощается.
--   chitin — Хитин Архитектора: на нём жуки быстрее. Не горит и не сносится вовсе:
--            «Обычный ремонт невозможен. Меняет карту навсегда.» Навсегда — то есть
--            до конца забега: вся арена разбирается целиком (WaveRunner.clearArena).
--   cocoon — Кокон Кукольника: через время выпускает жука следующей касты.
--
-- «Все из обломков, все уничтожаются тяжёлым снарядом и горят» — отсюда ровно два
-- способа их снести, и оба ведут в Blast ниже: разрыв навесного снаряда (Projectile.burst)
-- и взрыв элемента (Effects.applyExplosion). Обычный снаряд их не берёт — так в документе.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local Grid = require(ServerScriptService:WaitForChild("Grid"))
-- Рельеф пола. Всё, что здесь строится, стоит на ФАКТИЧЕСКОМ бетоне и едет вместе
-- с ним: по номинальному уровню объект либо висит над ямой, либо оказывается целиком
-- под поднявшимся полом (найдено замером: руина на холме уходила под землю).
local ConcreteFloor = require(ServerScriptService:WaitForChild("ConcreteFloor"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local DamageDealtRemote = Remotes:WaitForChild("DamageDealt")

local enemiesFolder = Workspace:WaitForChild("Enemies")

local EnemyStructures = {}

-- Колбек на вылупление кокона. Назначает EnemySpawner — точно так же, как Effects
-- отдаёт Гору через OnKillBarrier: прямой require спавнера зациклил бы модули.
EnemyStructures.OnHatch = nil

local folder = Workspace:FindFirstChild("EnemyStructures")
if not folder then
	folder = Instance.new("Folder")
	folder.Name = "EnemyStructures"
	folder.Parent = Workspace
end

-- Живые объекты списком: их спрашивают каждый кадр (пол под каждым жуком,
-- линия огня каждой турели), а GetChildren на каждый такой вопрос — новая таблица
-- в мусор шестьдесят раз в секунду.
local live = {}

-- Сколько из них — Стены. Счётчик рядом со списком, а не подсчёт проходом: весь
-- его смысл в том, чтобы BlocksLine НЕ ходил по списку, когда Стен нет.
local wallCount = 0

local KINDS = {
	ruin = { hp = 20, size = Vector3.new(2.2, 1, 2.2), color = Color3.fromRGB(122, 110, 92) },
	wall = { hp = 260, size = Vector3.new(9, 6, 1.6), color = Color3.fromRGB(104, 92, 74) },
	ramp = { hp = 180, size = Vector3.new(6, 0.8, 9), color = Color3.fromRGB(114, 100, 78) },
	feeder = { hp = 120, size = Vector3.new(4.4, 2.2, 4.4), color = Color3.fromRGB(138, 120, 66) },
	chitin = { hp = 0, size = Vector3.new(9, 0.25, 9), color = Color3.fromRGB(64, 96, 88) },
	cocoon = { hp = 40, size = Vector3.new(2.4, 3, 2.4), color = Color3.fromRGB(198, 190, 214) },
}

-- Горение конструкции: сколько HP в секунду и сколько секунд горит от одного
-- попадания огнём. Числа баланса — здесь, как и всё остальное.
local BURN_DPS = 14
local BURN_TIME = 6

-- Кормушка: сколько лечит, как часто, в каком радиусе и на сколько её хватает.
-- «Не медик лечит — жук ест и сам восстанавливается. Кормушка со временем истощается.»
local FEEDER = { amount = 5, interval = 1, radius = 12, meals = 40 }

local function container()
	return folder
end

-- position — только XZ; высоту решает бетон под ней. lift — на сколько ЦЕНТР детали
-- выше поверхности (обычно половина высоты, чтобы объект лёг на пол, а не врос в него).
local function build(kind, position, lift, facing, size)
	local spec = KINDS[kind]

	local model = Instance.new("Model")
	model.Name = kind

	local part = Instance.new("Part")
	part.Name = "Body"
	part.Size = size or spec.size
	part.Color = spec.color
	part.Material = kind == "chitin" and Enum.Material.Glass or Enum.Material.Slate
	part.Anchored = true
	-- Ни одна из них не толкается физически: жуки ходят по маршруту, а игрок должен
	-- мочь пройти сквозь. Луч линии огня ищет их по белому списку, а не по коллизии.
	part.CanCollide = false
	part.CanTouch = false
	lift = lift or (part.Size.Y / 2)
	local at = Vector3.new(position.X,
		ConcreteFloor.HeightAt(position.X, position.Z) + lift, position.Z)
	part.CFrame = facing
		and CFrame.lookAt(at, at + facing)
		or CFrame.new(at)
	part.Parent = model
	model.PrimaryPart = part

	model:SetAttribute("Kind", kind)
	if spec.hp > 0 then
		model:SetAttribute("MaxHP", spec.hp)
		model:SetAttribute("HP", spec.hp)
	end
	model.Parent = container()

	-- lift хранится: по нему объект держится пола, когда тот едет (см. цикл жизни ниже).
	local record = { model = model, part = part, kind = kind, burnUntil = 0, lift = lift }
	table.insert(live, record)
	if kind == "wall" then
		wallCount += 1
	end
	return model, record
end

local function remove(record)
	local index = table.find(live, record)
	if index then
		table.remove(live, index)
		if record.kind == "wall" then
			wallCount -= 1
		end
	end
	if record.model.Parent then
		record.model:Destroy()
	end
end

-- Общий список живых объектов нужного вида в радиусе.
function EnemyStructures.Near(position, radius, kind)
	local found = {}
	for _, record in live do
		if (not kind or record.kind == kind)
			and (record.part.Position - position).Magnitude <= radius then
			table.insert(found, record.model)
		end
	end
	return found
end

-- ============================ Руины ============================
--
-- «Ест обломки стены или мебели. Из собранного строит на карте» (Строитель).
-- Руина — куча с запасом материала, а не россыпь одинаковых кубиков: из Стены
-- выходит куча побольше, из Испарителя — поменьше, и это видно на поле без счёта.

-- Сколько прочности разрушенного уходит на одну единицу материала, и потолок кучи.
-- При 70 Стена игрока (150 HP) даёт ровно две единицы — то есть ровно одну конструкцию
-- колонии (Enemies.Builder.builds.needMaterial). Снёс стену — подарил жукам стену.
local HP_PER_MATERIAL = 70
local MAX_MATERIAL = 6

-- Куча из нескольких обломков вокруг главного: один ровный кубик читается ящиком,
-- а не развалинами. Части лежат в той же модели и уходят вместе с ней.
local function rubble(model, centre, material)
	for i = 1, math.min(material, 4) do
		local chunk = Instance.new("Part")
		chunk.Name = "Chunk"
		chunk.Anchored = true
		chunk.CanCollide = false
		chunk.CanTouch = false
		chunk.CanQuery = false
		chunk.Size = Vector3.new(0.8 + math.random() * 0.9, 0.5 + math.random() * 0.5,
			0.8 + math.random() * 0.9)
		chunk.Color = Color3.fromRGB(110, 100, 84)
		chunk.Material = Enum.Material.Slate
		chunk.CFrame = CFrame.new(centre + Vector3.new(
			(math.random() - 0.5) * 3.4, -0.2, (math.random() - 0.5) * 3.4))
			* CFrame.Angles(0, math.random() * math.pi, 0)
		chunk.Parent = model
	end
end

-- Руина на месте разрушенного. maxHp — прочность того, что снесли: от неё зависят
-- и размер кучи, и сколько из неё можно вынести.
function EnemyStructures.Ruin(position, maxHp)
	local material = math.clamp(math.round((maxHp or 0) / HP_PER_MATERIAL), 1, MAX_MATERIAL)
	return EnemyStructures.DropMaterial(position, material)
end

-- Оставить кучу с заданным запасом материала — Окопщик выносит его из окопа,
-- Пеликан оставляет наевшись, работяга приносит Строителю.
function EnemyStructures.DropMaterial(position, material)
	material = math.max(1, math.floor(material or 1))
	local spec = KINDS.ruin
	-- Куча растёт с запасом, но не линейно: шесть единиц не должны давать кучу
	-- вшестеро шире Стены, из которой она вышла.
	local scale = 0.8 + 0.22 * material
	local size = spec.size * scale
	-- Лежит НА полу, а не вросши в него: подъём — половина собственной высоты.
	-- Раньше центр ставился на полстуда выше пола, и большая куча тонула в нём на 0.46.
	local model, record = build("ruin", position, size.Y / 2, nil, size)
	record.material = material
	rubble(model, record.part.Position, material)
	return model
end

-- Забрать одну единицу материала из ближайшей руины. Возвращает true, если взял —
-- так работяги и Строитель конкурируют за одну кучу без отдельной брони: кто успел, тот и взял.
--
-- Куча убывает и зрительно: иначе разобранная наполовину руина выглядела бы как целая.
function EnemyStructures.TakeMaterial(position, radius)
	local best, bestDistance = nil, math.huge
	for _, record in live do
		if record.kind == "ruin" and (record.material or 0) > 0 then
			local distance = (record.part.Position - position).Magnitude
			if distance <= radius and distance < bestDistance then
				best, bestDistance = record, distance
			end
		end
	end

	if not best then
		return false
	end

	best.material -= 1
	if best.material <= 0 then
		remove(best)
	else
		local scale = 0.8 + 0.22 * best.material
		best.part.Size = KINDS.ruin.size * scale
		local chunk = best.model:FindFirstChild("Chunk")
		if chunk then
			chunk:Destroy()
		end
	end
	return true
end

-- ======================= Конструкции Строителя =======================

function EnemyStructures.Wall(position, facing)
	local model = build("wall", position, 3, facing)
	print("[Строитель] поставил Стену — турели через неё не видят")
	return model
end

-- Пандус ставится К постройке игрока и помечает её: через помеченную перелезают все,
-- а не только те, кому хватает climbHeight. Снос пандуса снимает метку обратно.
function EnemyStructures.Ramp(building)
	if not building or not building.Parent or building:GetAttribute("Ramped") then
		return nil
	end

	local at = building:GetPivot().Position
	local model, record = build("ramp", at, KINDS.ramp.size.Y / 2)
	record.building = building
	building:SetAttribute("Ramped", true)
	print(("[Строитель] прислонил Пандус к %s — теперь через неё забегают все")
		:format(building.Name))
	return model
end

function EnemyStructures.Feeder(position)
	local model, record = build("feeder", position, 1.1)
	record.meals = FEEDER.meals
	record.lastMeal = 0
	print("[Строитель] навалил Кормушку — жуки рядом восстанавливаются")
	return model
end

-- ===================== Окоп, хитин и кокон =====================

function EnemyStructures.Chitin(position)
	-- Второй хитин поверх первого не нужен: бонус скорости не складывается, а моделей
	-- на поле без этой проверки копились бы сотнями — Архитектор стелит его на ходу.
	if #EnemyStructures.Near(position, 6, "chitin") > 0 then
		return nil
	end
	-- Хитин — покрытие пола, и лежать он обязан на самом полу, какой бы тот ни был:
	-- в яме — на дне ямы. Половина толщины плюс волосок — чтобы не мерцал с плитой.
	return (build("chitin", position, KINDS.chitin.size.Y / 2 + 0.03))
end

-- Кокон: через hatch секунд выпускает enemyType. Расстрелянный до срока не выпускает
-- никого — в этом весь смысл «нельзя оставлять раненых».
function EnemyStructures.Cocoon(position, enemyType, hatchAfter, hp)
	local model, record = build("cocoon", position, 1.5)
	if hp then
		model:SetAttribute("MaxHP", hp)
		model:SetAttribute("HP", hp)
	end
	record.hatchAt = os.clock() + hatchAfter
	record.hatchType = enemyType
	return model
end

-- ===================== Свойства пола под жуком =====================

-- Стоит ли точка на хитине (на нём жуки быстрее).
--
-- Окопа здесь больше нет: он переехал в рельеф бетонного пола (ConcreteFloor) и стал
-- настоящей выемкой, а не плоской картонкой поверх пола — «жук в окопе ниже линии
-- огня турелей» теперь верно буквально.
function EnemyStructures.OnChitin(position)
	for _, record in live do
		if record.kind == "chitin" then
			local size = record.part.Size
			local at = record.part.Position
			if math.abs(position.X - at.X) <= size.X / 2 and math.abs(position.Z - at.Z) <= size.Z / 2 then
				return true
			end
		end
	end
	return false
end

-- Закрывает ли Стена жуков линию между двумя точками. Считается арифметикой, а не
-- лучом: Стены не сталкиваются (игрок должен проходить сквозь), а включать им коллизию
-- ради одного луча значило бы сломать всё остальное.
function EnemyStructures.BlocksLine(from, to)
	-- Быстрый выход: без Стен проверять нечего. Эту функцию зовёт каждая турель на
	-- каждую цель каждый выбор — то есть тысячи раз в секунду, а Строитель есть далеко
	-- не в каждой волне. Без этой строки все остальные волны платили бы полный проход
	-- по списку конструкций за механику, которой на поле нет.
	if wallCount == 0 then
		return false
	end

	for _, record in live do
		if record.kind == "wall" then
			local part = record.part
			-- Отрезок в локальных координатах стены: пересечение с коробкой — это slab-тест,
			-- три пары плоскостей и пересечение интервалов.
			local inverse = part.CFrame:Inverse()
			local a = inverse * from
			local b = inverse * to
			local half = part.Size / 2
			local direction = b - a

			local enter, exit = 0, 1
			local hit = true
			for _, axis in { "X", "Y", "Z" } do
				local origin, delta, limit = a[axis], direction[axis], half[axis]
				if math.abs(delta) < 1e-6 then
					if math.abs(origin) > limit then
						hit = false
						break
					end
				else
					local t1 = (-limit - origin) / delta
					local t2 = (limit - origin) / delta
					if t1 > t2 then
						t1, t2 = t2, t1
					end
					enter = math.max(enter, t1)
					exit = math.min(exit, t2)
					if enter > exit then
						hit = false
						break
					end
				end
			end

			if hit then
				return true
			end
		end
	end
	return false
end

-- ============================ Урон ============================

local function damage(record, amount)
	local hp = record.model:GetAttribute("HP")
	if not hp then
		return -- окоп и хитин прочности не имеют вовсе
	end

	local left = math.max(0, hp - amount)
	record.model:SetAttribute("HP", left)
	DamageDealtRemote:FireAllClients(record.part.Position, math.min(hp, amount), true)

	if left <= 0 then
		if record.building and record.building.Parent then
			record.building:SetAttribute("Ramped", nil)
		end

		-- Конструкции Строителя сами «из обломков» — значит обломками и рассыпаются,
		-- и колония может отстроиться заново. Кокон исключён: это не кладка, а шёлк
		-- с жуком внутри — строить из него нечего. Сама руина тоже: иначе сгоревшая
		-- куча рожала бы новую кучу бесконечно.
		if record.kind ~= "ruin" and record.kind ~= "cocoon" then
			local maxHp = record.model:GetAttribute("MaxHP") or 0
			local at = record.part.Position
			remove(record)
			EnemyStructures.Ruin(at, maxHp)
			return
		end

		remove(record)
	end
end

-- Тяжёлый снаряд или взрыв элемента. Огонь (damageType == "overtime") ещё и поджигает.
function EnemyStructures.Blast(position, radius, amount, elementData)
	local burns = elementData and elementData.damageType == "overtime"
	for index = #live, 1, -1 do
		local record = live[index]
		if (record.part.Position - position).Magnitude <= radius then
			if burns then
				record.burnUntil = os.clock() + BURN_TIME
			end
			damage(record, amount)
		end
	end
end

-- Сносит всё разом — для рестарта забега, как Corpses.Clear и Grid.Reset.
function EnemyStructures.Clear()
	for _, record in live do
		if record.building and record.building.Parent then
			record.building:SetAttribute("Ramped", nil)
		end
		if record.model.Parent then
			record.model:Destroy()
		end
	end
	table.clear(live)
	wallCount = 0
end

-- ======================= Жизнь конструкций =======================
--
-- Один цикл на всех, а не таск на каждый объект: кормушек и окопов на поле бывают
-- десятки, и десятки корутин, каждая со своим task.wait, стоят дороже одного обхода.
local STEP = 0.25
local accumulated = 0

RunService.Heartbeat:Connect(function(dt)
	accumulated += dt
	if accumulated < STEP then
		return
	end
	accumulated = 0

	local now = os.clock()

	for index = #live, 1, -1 do
		local record = live[index]

		if not record.model.Parent then
			table.remove(live, index)
			if record.kind == "wall" then
				wallCount -= 1
			end
		else
			-- Держимся пола: он ездит вверх и вниз под нами — Окопщик копает там, где стоит,
			-- а Литосфера меняет рельеф целыми участками. Без этого руина, под которой вырыли
			-- окоп, оставалась висеть в воздухе, а под поднявшимся полом — уходила под землю целиком.
			--
			-- Двигается модель целиком, а не одна деталь: у руины вокруг лежат обломки,
			-- и они обязаны ехать вместе с ней, а поворот Стены — сохраниться.
			local at = record.part.Position
			local want = ConcreteFloor.HeightAt(at.X, at.Z) + (record.lift or 0)
			if math.abs(want - at.Y) > 0.05 then
				local pivot = record.model:GetPivot()
				record.model:PivotTo(pivot + Vector3.new(0, want - at.Y, 0))
			end

			-- Горение
			if now < record.burnUntil then
				damage(record, BURN_DPS * STEP)
			end

			-- Кормушка: лечит соседей и тратит себя. Истощилась — исчезает.
			if record.kind == "feeder" and record.model.Parent
				and now - record.lastMeal >= FEEDER.interval then
				record.lastMeal = now
				local at = record.part.Position
				for _, enemy in enemiesFolder:GetChildren() do
					if record.meals <= 0 then
						break
					end
					local hp = enemy:GetAttribute("HP")
					local maxHp = enemy:GetAttribute("MaxHP")
					if hp and maxHp and hp > 0 and hp < maxHp
						and (enemy:GetPivot().Position - at).Magnitude <= FEEDER.radius then
						enemy:SetAttribute("HP", math.min(maxHp, hp + FEEDER.amount))
						record.meals -= 1
					end
				end
				if record.meals <= 0 then
					print("[Кормушка] истощилась")
					remove(record)
				end
			end

			-- Кокон: вылупляется по сроку.
			if record.hatchAt and now >= record.hatchAt and record.model.Parent then
				local at = record.part.Position
				local hatchType = record.hatchType
				remove(record)
				if EnemyStructures.OnHatch then
					print(("[Кокон] раскрылся: вышел %s"):format(hatchType))
					EnemyStructures.OnHatch(hatchType, at)
				end
			end
		end
	end
end)

return EnemyStructures
