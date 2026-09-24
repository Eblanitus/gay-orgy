-- Изменение ландшафта Литосферой (design: alchemy_td_effects_v4.md).
--
-- «При убийстве — ландшафт карты поднимается/опускается. Без HP, изменяет рельеф.
-- При определённом количестве врагов в изменённом ландшафте — если была яма, то
-- появляется плита сверху и давит всех жуков, нанося урон. Если была возвышенность —
-- медленно опускается до нормального уровня.»
--
-- Сам рельеф двигает ConcreteFloor — он общий и про Литосферу не знает; здесь только
-- то, что отличает именно этот элемент: жребий яма/возвышенность, счёт жуков в яме
-- и падающая плита.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")

local ConcreteFloor = require(ServerScriptService:WaitForChild("ConcreteFloor"))
local Impulse = require(ServerScriptService:WaitForChild("Impulse"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local DamageDealtRemote = Remotes:WaitForChild("DamageDealt")
local ExplosionRemote = Remotes:WaitForChild("Explosion")

local enemiesFolder = Workspace:WaitForChild("Enemies")

local Lithosphere = {}

-- Сколько участков Литосферы держим одновременно. Без потолка залитая Литосферой
-- турель за волну превращает пол в решето, и ни пройти, ни разглядеть его уже нельзя.
-- Самый старый участок затягивается, когда появляется лишний.
local MAX_ZONES = 4

-- Как часто яма считает, сколько в ней жуков, и сколько живёт, если так и не наполнилась.
local WATCH_STEP = 0.5
local PIT_LIFETIME = 30

-- Скорость оседания возвышенности, studs/сек. Втрое медленнее обычного движения
-- пола — документ говорит именно «медленно опускается».
local SETTLE_SPEED = 0.5

-- Сколько падает плита и сколько лежит, прежде чем раствориться.
local SLAB_FALL = 0.35
local SLAB_REST = 1.2

local live = {} -- активные участки

local function enemiesIn(position, radius)
	local found = {}
	for _, enemy in enemiesFolder:GetChildren() do
		if enemy:IsA("Model") and (enemy:GetAttribute("HP") or 0) > 0 then
			local at = enemy:GetPivot().Position
			if (Vector3.new(at.X, 0, at.Z) - Vector3.new(position.X, 0, position.Z)).Magnitude <= radius
				-- Летающие в яме не считаются и под плиту не попадают: они над ней.
				and not enemy:GetAttribute("Flying") then
				table.insert(found, enemy)
			end
		end
	end
	return found
end

-- Убрать из списка активных, но не трогать пол. Нужно яме, которая уже сработала:
-- пока плита падает, яма должна оставаться ямой, но в счёт MAX_ZONES больше не идти.
local function unlist(zone)
	local index = table.find(live, zone)
	if index then
		table.remove(live, index)
	end
end

-- Затянуть участок обратно в ровный пол.
local function close(zone)
	if zone.closed then
		return
	end
	zone.closed = true
	unlist(zone)
	ConcreteFloor.Restore(zone.position, zone.radius, { speed = zone.settleSpeed })
end

-- Плита сверху. Появляется над ямой, падает и давит всех, кто в ней стоит.
local function crush(zone, plan)
	local caught = enemiesIn(zone.position, zone.radius)

	local slab = Instance.new("Part")
	slab.Name = "Плита Литосферы"
	slab.Anchored = true
	slab.Size = Vector3.new(zone.radius * 2, 1.6, zone.radius * 2)
	slab.Position = zone.position + Vector3.new(0, 14, 0)
	slab.Material = Enum.Material.Concrete
	slab.Color = Color3.fromRGB(96, 92, 86)
	-- Без коллизии: она убивает уроном, а не физикой, и запереть игрока под собой не должна.
	slab.CanCollide = false
	slab.CanQuery = false
	slab.Parent = Workspace

	TweenService:Create(slab, TweenInfo.new(SLAB_FALL, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Position = zone.position + Vector3.new(0, 0.8, 0),
	}):Play()

	task.delay(SLAB_FALL, function()
		ExplosionRemote:FireAllClients(zone.position, zone.radius)
		Impulse.Blast(zone.position, zone.radius)

		local hits = 0
		for _, enemy in caught do
			if enemy.Parent and (enemy:GetAttribute("HP") or 0) > 0 then
				local hp = enemy:GetAttribute("HP")
				enemy:SetAttribute("HP", math.max(0, hp - plan.crushDamage))
				DamageDealtRemote:FireAllClients(enemy:GetPivot().Position,
					math.min(hp, plan.crushDamage), true)
				hits += 1
			end
		end
		print(("[Литосфера] плита упала в яму: %d урона по %d жукам")
			:format(plan.crushDamage, hits))

		task.delay(SLAB_REST, function()
			slab:Destroy()
			close(zone)
		end)
	end)
end

-- Жук умер от Литосферы — меняем рельеф на месте его смерти.
function Lithosphere.Erupt(position, plan)
	-- Жребий яма/возвышенность: документ называет оба исхода рядом и не говорит,
	-- что выбирает между ними.
	local pit = math.random() < 0.5

	while #live >= MAX_ZONES do
		close(live[1])
	end

	local zone = {
		position = Vector3.new(position.X, position.Y, position.Z),
		radius = plan.radius,
		pit = pit,
		born = os.clock(),
	}
	table.insert(live, zone)

	if pit then
		ConcreteFloor.Shape(zone.position, plan.radius, -plan.depth, { tag = "lithosphere" })
		print(("[Литосфера] пол провалился: яма радиусом %.0f глубиной %.1f")
			:format(plan.radius, plan.depth))

		-- Ждём, пока в яме наберётся достаточно жуков. Не набралось за PIT_LIFETIME —
		-- яма затягивается сама: вечная дыра посреди арены никому не нужна.
		task.spawn(function()
			while not zone.closed do
				task.wait(WATCH_STEP)
				if zone.closed then
					return
				end
				if #enemiesIn(zone.position, zone.radius) >= plan.crushAt then
					-- Яма остаётся ямой, пока плита падает — затянет её сам crush после удара.
					-- Из списка активных убирается сразу: второй раз она сработать не должна.
					unlist(zone)
					crush(zone, plan)
					return
				end
				if os.clock() - zone.born >= PIT_LIFETIME then
					close(zone)
					return
				end
			end
		end)
	else
		ConcreteFloor.Shape(zone.position, plan.radius, plan.rise, { tag = "lithosphere" })
		zone.settleSpeed = SETTLE_SPEED
		print(("[Литосфера] пол вспучился: возвышенность радиусом %.0f высотой %.1f")
			:format(plan.radius, plan.rise))

		task.delay(plan.settleAfter, function()
			if not zone.closed then
				print("[Литосфера] возвышенность медленно оседает")
				close(zone)
			end
		end)
	end

	return zone
end

-- Новый забег — все участки забываются. Сам пол выравнивает ConcreteFloor.Reset.
function Lithosphere.Clear()
	for _, zone in live do
		zone.closed = true
	end
	table.clear(live)
end

return Lithosphere
