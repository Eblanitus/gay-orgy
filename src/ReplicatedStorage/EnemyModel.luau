-- Видимая модель жука: сегментный шаблон с лапами-моделями или примитив из шара и четырёх
-- палок. Лежит в ReplicatedStorage, потому что собирают её ДВЕ стороны:
--   * сервер — один раз при появлении, чтобы снять габариты (EnemyBody.Measure/Footprint)
--     и сразу раздеть до невидимого якоря (EnemyModel.Strip): решает сервер по пивоту,
--     атрибутам и числам габарита, а не по деталям;
--   * клиент (StarterPlayerScripts.EnemyRender) — то, что видно на экране, и походку к нему.
-- Раньше сервер двигал все 83 детали каждого жука каждый кадр, и репликация этих CFrame
-- съедала весь канал (замер: 110 тыс. изменений в секунду на 39 жуках).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EnemyGait = require(ReplicatedStorage:WaitForChild("EnemyGait"))
local EnemyBody = require(ReplicatedStorage:WaitForChild("EnemyBody"))

local EnemyModel = {}

-- Группа столкновений тела жука (заводит её сервер в Corpses). Тело толкает трупы — теперь
-- клиентские, поэтому и толкает их клиентская модель.
EnemyModel.CollisionGroup = "Enemies"

local ENEMY_Y = 1.5 -- studs над полом: на этой высоте пивота ноги примитива касаются земли

local LEG_NAMES = {
	"leg_front_left", "leg_front_right",
	"leg_mid_left", "leg_mid_right",
	"leg_rear_left", "leg_rear_right",
}
-- Чередующийся трипод: левая передняя + правая средняя + левая задняя — и наоборот.
local TRIPOD = {
	leg_front_left = 1, leg_mid_right = 1, leg_rear_left = 1,
	leg_front_right = 2, leg_mid_left = 2, leg_rear_right = 2,
}

-- Масштаб экземпляра: у Мини он случайный по scaleRange. Выбирает его сервер и кладёт
-- в атрибут Scale — клиент строит ровно того же жука, а не бросает кубик заново.
function EnemyModel.PickScale(enemyData)
	if enemyData.model and enemyData.scaleRange then
		local range = enemyData.scaleRange
		return math.random() * (range[2] - range[1]) + range[1]
	end
	return enemyData.scale or 1
end

-- Шаблонный жук: клон, масштаб, перекраска, лапы в походку. recolor — таблица врага
-- (enemyData) или nil, если красить не надо (Аркада берёт шаблон как есть).
-- Ноги — жёсткие рычаги вокруг CoxaJoint (см. EnemyGait): бедро и стойка снимаются с клона
-- от пивота, поэтому шаблон можно править, не трогая код.
function EnemyModel.FromTemplate(templateName, scale, recolor)
	local template = ReplicatedStorage:WaitForChild(templateName)
	local model = template:Clone()
	-- Масштаб ДО снятия анатомии ног: hip/foot и длины звеньев считаются от
	-- масштабированной позы, иначе походка не сойдётся с телом.
	if scale ~= 1 then
		model:ScaleTo(scale)
	end
	model:SetAttribute("Scale", scale)

	local chitin = template:GetAttribute("ColorChitin")
	local joints = template:GetAttribute("ColorJoints")
	local elytra = template:GetAttribute("ColorElytra")
	local head = template:GetAttribute("ColorHead")
	local color, legColor, elytraColor, headColor
	if recolor then
		color = recolor.color or Color3.fromRGB(55, 80, 45)
		legColor = recolor.legColor or Color3.fromRGB(30, 25, 20)
		elytraColor = recolor.elytraColor or color
		headColor = recolor.headColor or color
	end

	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
			part.CanTouch = false
			if recolor then
				if chitin and part.Color == chitin then
					part.Color = color
				elseif joints and part.Color == joints then
					part.Color = legColor
				elseif elytra and part.Color == elytra then
					part.Color = elytraColor
				elseif head and part.Color == head then
					part.Color = headColor
				end
			end
		end
	end
	-- Единственный коллайдер — грудь и брюшко: толкают трупы, в остальном жук анкорнут
	-- и ходит маршрутом. Друг сквозь друга живые не проходят по капсуле толкучки (Crowd).
	for _, coreName in { "ThoraxCore", "AbdomenCore" } do
		local core = model:FindFirstChild(coreName, true)
		if core and core:IsA("BasePart") then
			core.CanCollide = true
			core.CollisionGroup = EnemyModel.CollisionGroup
		end
	end

	assert(model.PrimaryPart, ("[EnemyModel] у шаблона %s нет PrimaryPart"):format(templateName))
	local pivot = model:GetPivot()
	local legs = {}
	for _, name in LEG_NAMES do
		local legModel = model:FindFirstChild(name, true)
		assert(legModel and legModel:IsA("Model"),
			("[EnemyModel] в шаблоне %s нет ноги %s"):format(templateName, name))
		local coxa = legModel.PrimaryPart
		local tarsus = legModel:FindFirstChild("Tarsus2", true)
		assert(coxa and tarsus, ("[EnemyModel] сломана нога %s"):format(name))
		table.insert(legs, {
			part = legModel,
			hip = pivot:PointToObjectSpace(coxa.Position),
			foot = pivot:PointToObjectSpace(tarsus.Position),
			group = TRIPOD[name],
			-- Грызут только передние лапы.
			front = name == "leg_front_left" or name == "leg_front_right",
		})
	end
	EnemyGait.Attach(model, legs)
	EnemyBody.Measure(model)
	return model
end

-- Примитив: приплюснутое тело (шар с неравномерным Size), голова, 4 ноги. PrimaryPart = Body.
local function buildPrimitive(enemyData)
	local model = Instance.new("Model")
	local scale = enemyData.scale or 1
	local color = enemyData.color or (enemyData.armor and Color3.fromRGB(120, 120, 130) or Color3.fromRGB(55, 80, 45))
	local material = enemyData.material or (enemyData.armor and Enum.Material.Metal or Enum.Material.SmoothPlastic)
	local legColor = enemyData.legColor or (enemyData.armor and Color3.fromRGB(60, 60, 66) or Color3.fromRGB(30, 25, 20))

	-- Shape = Ball игнорирует неравномерный Size — нужен SpecialMesh(Sphere).
	local body = Instance.new("Part")
	body.Name = "Body"
	body.Size = Vector3.new(2.6, 1.2, 3.4) * scale
	body.Anchored = true
	body.CanCollide = true
	body.CanTouch = false
	body.CollisionGroup = EnemyModel.CollisionGroup
	body.Color = color
	body.Material = material
	body.CFrame = CFrame.new(0, 0, 0)
	body.Parent = model
	local bodyMesh = Instance.new("SpecialMesh")
	bodyMesh.MeshType = Enum.MeshType.Sphere
	bodyMesh.Parent = body

	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(0.95, 0.75, 0.85) * scale
	head.Anchored = true
	head.CanCollide = false
	head.CanTouch = false
	head.Color = color
	head.Material = material
	head.CFrame = CFrame.new(0, -0.1 * scale, 1.72 * scale)
	head.Parent = model
	local headMesh = Instance.new("SpecialMesh")
	headMesh.MeshType = Enum.MeshType.Sphere
	headMesh.Parent = head

	-- Нога от «бедра» на боку тела к «ступне» на земле. GROUND_Y не масштабируется:
	-- пивот любого жука едет на высоте точки пути (ENEMY_Y).
	local GROUND_Y = -ENEMY_Y
	local legPairs = {
		{ hip = Vector3.new(0.9, -0.25, 1.0) * scale, foot = Vector3.new(1.5 * scale, GROUND_Y, 1.25 * scale) },
		{ hip = Vector3.new(-0.9, -0.25, 1.0) * scale, foot = Vector3.new(-1.5 * scale, GROUND_Y, 1.25 * scale) },
		{ hip = Vector3.new(0.9, -0.25, -1.0) * scale, foot = Vector3.new(1.5 * scale, GROUND_Y, -1.25 * scale) },
		{ hip = Vector3.new(-0.9, -0.25, -1.0) * scale, foot = Vector3.new(-1.5 * scale, GROUND_Y, -1.25 * scale) },
	}
	local legs = {}
	for i, pair in legPairs do
		local leg = Instance.new("Part")
		leg.Name = "Leg" .. i
		leg.Shape = Enum.PartType.Cylinder
		leg.Size = Vector3.new((pair.foot - pair.hip).Magnitude, 0.26 * scale, 0.26 * scale)
		leg.Anchored = true
		leg.CanCollide = false
		leg.CanTouch = false
		leg.Color = legColor
		leg.Material = material
		leg.CFrame = CFrame.lookAt(pair.hip:Lerp(pair.foot, 0.5), pair.foot) * CFrame.Angles(0, math.rad(90), 0)
		leg.Parent = model
		table.insert(legs, { part = leg, hip = pair.hip, foot = pair.foot })
	end

	model.PrimaryPart = body
	model:SetAttribute("Scale", scale)
	EnemyGait.Attach(model, legs)
	return model
end

-- Полная видимая модель врага. scale — масштаб экземпляра (атрибут Scale серверной модели);
-- nil — выбрать (так делает сервер при появлении).
function EnemyModel.Build(enemyData, scale)
	local model
	if enemyData.model then
		scale = scale or EnemyModel.PickScale(enemyData)
		model = EnemyModel.FromTemplate(enemyData.model, scale, enemyData)
		-- Высота пивота при ходьбе: явный rideHeight вида или прямо масштаб клона.
		model:SetAttribute("RideHeight", enemyData.rideHeight or scale)
	else
		model = buildPrimitive(enemyData)
		model:SetAttribute("RideHeight", enemyData.rideHeight or ENEMY_Y)
	end
	model.Name = enemyData.name
	return model
end

-- Серверная модель после замера: всё, кроме PrimaryPart, снимается. Остаётся невидимый
-- якорь с тем же Size (по нему считают запасные габариты EnemyBody), пивотом и атрибутами —
-- этого хватает всей логике: прицелу, попаданиям, зонам, толкучке. Картинку рисует клиент.
function EnemyModel.Strip(model)
	local root = model.PrimaryPart
	assert(root, "[EnemyModel] нечего оставить: нет PrimaryPart")
	for _, child in model:GetChildren() do
		if child ~= root then
			child:Destroy()
		end
	end
	root:ClearAllChildren()
	root.Transparency = 1
	root.CanCollide = false
	root.CanTouch = false
	root.CastShadow = false
	root.Anchored = true
	-- Модель из одной детали приходит клиенту целиком, вместе с PrimaryPart.
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	return model
end

return EnemyModel
