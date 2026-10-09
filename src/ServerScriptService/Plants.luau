-- Растение (вики effects v4): при убийстве Растением или Деревом из трупа вырастает
-- растение. Оно даёт плоды — те летят к самой побитой постройке и лечат её, — а пока
-- живо, бьёт шипами жуков рядом. Метка Грунта на убитом усиливает шипы, метка Пепла —
-- и шипы, и плоды. Effects считает только числа и зовёт Effects.OnKillPlant; модели,
-- полёт плода и сам удар живут здесь, на сервере.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Effects = require(ReplicatedStorage:WaitForChild("Effects"))
local Arena = require(ReplicatedStorage:WaitForChild("Arena"))
local EnemyBody = require(ReplicatedStorage:WaitForChild("EnemyBody"))

local DamageDealtRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("DamageDealt")
local enemiesFolder = Workspace:WaitForChild("Enemies")
local towersFolder = Workspace:WaitForChild("Towers")

-- Своя папка: растение — не постройка (жуки его не грызут и путь не обходят) и не жук.
-- WaveRunner чистит её вместе с ареной.
local plantsFolder = Workspace:FindFirstChild("Plants")
if not plantsFolder then
	plantsFolder = Instance.new("Folder")
	plantsFolder.Name = "Plants"
	plantsFolder.Parent = Workspace
end

local GROW_TIME = 0.8 -- росток поднимается из трупа, потом сразу отдаёт плоды
local WITHER_TIME = 0.6
local FRUIT_SPEED = 30 -- studs/сек полёта плода
local FRUIT_ARC = 6 -- высота дуги над прямой
local FRUIT_GAP = 0.35 -- между плодами одного растения
local STEM_COLOR = Color3.fromRGB(60, 95, 45)

local Plants = {}

local function part(model, size, cframe, color, material)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Parent = model
	return p
end

-- Низкополигональный росток: стебель, три листа веером и бутон цвета элемента.
-- Шипастый (метка Грунта) — с венцом колючек вокруг бутона: разница видна с камеры.
local function buildModel(position, color, spiked)
	local model = Instance.new("Model")
	model.Name = "Plant"
	local base = CFrame.new(position)
	local stem = part(model, Vector3.new(0.5, 3, 0.5), base * CFrame.new(0, 1.5, 0), STEM_COLOR)
	model.PrimaryPart = stem
	for i = 0, 2 do
		local yaw = math.rad(i * 120)
		local leaf = base * CFrame.Angles(0, yaw, 0) * CFrame.new(0, 1.2, -0.9) * CFrame.Angles(math.rad(-35), 0, 0)
		part(model, Vector3.new(0.15, 0.9, 1.8), leaf, color)
	end
	part(model, Vector3.new(1.2, 1.2, 1.2), base * CFrame.new(0, 3.3, 0), color, Enum.Material.Neon).Shape = Enum.PartType.Ball
	if spiked then
		for i = 0, 5 do
			local yaw = math.rad(i * 60)
			part(model, Vector3.new(0.2, 0.2, 1.4),
				base * CFrame.new(0, 3.3, 0) * CFrame.Angles(0, yaw, 0) * CFrame.new(0, 0, -0.9),
				Color3.fromRGB(230, 220, 170))
		end
	end
	-- Пивот — у земли: ScaleTo тянет модель от него, и росток растёт из пола, а не висит.
	model.WorldPivot = base
	model:ScaleTo(0.05)
	model.Parent = plantsFolder
	return model
end

local function scaleOver(model, from, to, duration)
	local start = os.clock()
	while model.Parent do
		local t = math.min((os.clock() - start) / duration, 1)
		model:ScaleTo(from + (to - from) * t)
		if t >= 1 then
			break
		end
		task.wait()
	end
end

-- Цель плода: самая побитая по доле HP постройка, при равенстве — ближайшая к растению.
-- Перехил (Дерево) лечит и целые постройки, иначе плоду там делать нечего.
local function pickBuilding(origin, overheal)
	local best, bestRatio, bestDistance
	for _, building in towersFolder:GetChildren() do
		local hp = building:GetAttribute("HP")
		local maxHp = building:GetAttribute("MaxHP")
		if hp and maxHp and maxHp > 0 and hp > 0 and (hp < maxHp or overheal) then
			local ratio = hp / maxHp
			local distance = (building:GetPivot().Position - origin).Magnitude
			if not bestRatio or ratio < bestRatio or (ratio == bestRatio and distance < bestDistance) then
				best, bestRatio, bestDistance = building, ratio, distance
			end
		end
	end
	return best
end

local function heal(building, amount, overheal, name)
	local hp = building:GetAttribute("HP")
	local maxHp = building:GetAttribute("MaxHP")
	if not (building.Parent and hp and maxHp and hp > 0) then
		return
	end
	local healed = math.min(maxHp - hp, amount)
	local overflow = amount - healed
	if overflow > 0 and overheal then
		-- Дерево: перехил идёт в прочность, и потолка у неё нет — так в документе.
		building:SetAttribute("MaxHP", maxHp + overflow)
		healed += overflow
	end
	if healed <= 0 then
		return
	end
	building:SetAttribute("HP", hp + healed)
	DamageDealtRemote:FireAllClients(building:GetPivot().Position, -healed, true)
	print(("[Растение] %s лечит %s на %d (было %d из %d)"):format(name, building.Name, healed, hp, maxHp))
end

-- Плод летит дугой к постройке и лечит её по прилёту. Постройку снесли в полёте —
-- плод пропал: искать другую он не умеет, это не самонаводящийся снаряд.
local function throwFruit(from, building, amount, overheal, color, name)
	local to = building:GetPivot().Position
	local fruit = Instance.new("Part")
	fruit.Name = "Fruit"
	fruit.Shape = Enum.PartType.Ball
	fruit.Size = Vector3.new(0.9, 0.9, 0.9)
	fruit.Anchored = true
	fruit.CanCollide = false
	fruit.CanQuery = false
	fruit.CanTouch = false
	fruit.Material = Enum.Material.Neon
	fruit.Color = color
	fruit.Position = from
	fruit.Parent = plantsFolder

	local duration = math.max((to - from).Magnitude / FRUIT_SPEED, 0.3)
	local start = os.clock()
	while fruit.Parent do
		local t = math.min((os.clock() - start) / duration, 1)
		fruit.Position = from:Lerp(to, t) + Vector3.new(0, FRUIT_ARC * 4 * t * (1 - t), 0)
		if t >= 1 then
			break
		end
		task.wait()
	end
	if fruit.Parent then
		fruit:Destroy()
		heal(building, amount, overheal, name)
	end
end

-- Шипы: раз в interval бьют ближайшего наземного жука в радиусе. Удар идёт через
-- AfterArmor, как прямое попадание: броня, щит и зоны работают и против растения.
-- В радиусе — тело, а не пивот (EnemyBody): шипы достают и до брюшка крупного жука.
local function lash(origin, thorns, damage, elementData)
	local best, bestDistance
	for _, enemy in enemiesFolder:GetChildren() do
		if enemy:IsA("Model") and not enemy:GetAttribute("Flying") and (enemy:GetAttribute("HP") or 0) > 0 then
			local distance = EnemyBody.SurfaceDistance(origin, enemy, true)
			if distance <= thorns.radius and (not bestDistance or distance < bestDistance) then
				best, bestDistance = enemy, distance
			end
		end
	end
	if not best then
		return
	end
	local dealt = Effects.AfterArmor(best, damage, elementData)
	if dealt <= 0 then
		return
	end
	best:SetAttribute("HitFrom", origin)
	best:SetAttribute("HP", math.max(0, (best:GetAttribute("HP") or 0) - dealt))
	DamageDealtRemote:FireAllClients(best:GetPivot().Position, dealt, true)
end

-- plan — killHeal элемента; healScale — от метки Пепла; thornsScale — метки Грунта и Пепла.
function Plants.Spawn(position, plan, elementData, healScale, thornsScale)
	local ground = Vector3.new(position.X, Arena.floorY or position.Y, position.Z)
	local spiked = thornsScale > 1
	local model = buildModel(ground, elementData.color, spiked)

	task.spawn(function()
		scaleOver(model, 0.05, 1, GROW_TIME)
		if not model.Parent then
			return
		end

		local bud = ground + Vector3.new(0, 3.3, 0)
		local amount = math.floor(plan.amount * healScale + 0.5)
		for i = 1, plan.fruits or 1 do
			-- Каждый плод ищет постройку заново: пока росток бросал, худшей могла стать другая.
			local building = pickBuilding(ground, plan.overheal)
			if building then
				task.spawn(throwFruit, bud, building, amount, plan.overheal, elementData.color, elementData.name)
			end
			if i < (plan.fruits or 1) then
				task.wait(FRUIT_GAP)
			end
		end

		local thorns = plan.thorns
		if thorns then
			local damage = thorns.damage * thornsScale
			local deadline = os.clock() + thorns.life
			while model.Parent and os.clock() < deadline do
				lash(ground, thorns, damage, elementData)
				task.wait(thorns.interval)
			end
		end

		if model.Parent then
			scaleOver(model, 1, 0.05, WITHER_TIME)
			model:Destroy()
		end
	end)
end

Effects.OnKillPlant = Plants.Spawn

return Plants
