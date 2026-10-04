-- Видимое тело каждого жука — на клиенте.
--
-- Сервер держит у жука одну невидимую деталь (EnemyModel.Strip) и двигает её PivotTo:
-- маршрут, толкучка, HP, прицел и попадания решает он. Раньше он же двигал все детали тела
-- и ноги — сотни CFrame на жука в секунду шли каждому игроку (замер: 110 тыс. изменений/с на
-- 39 жуков, 20 Мбит/с). Теперь по сети идёт только кадр якоря и редкие атрибуты
-- Gait (поза ног) и Look (куда смотрит голова), а тело, ноги, вздрагивание и трупы собирает
-- и анимирует этот скрипт.
--
-- Тело — модель "Visual" внутри серверной модели жука: всё, что ищет жуков по папке
-- (обводка EnemyVisuals, машина Аркады, лучи с фильтром по папке), видит его на старом месте.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Enemies = require(ReplicatedStorage:WaitForChild("Enemies"))
local EnemyModel = require(ReplicatedStorage:WaitForChild("EnemyModel"))
local EnemyGait = require(ReplicatedStorage:WaitForChild("EnemyGait"))
local CorpseFX = require(ReplicatedStorage:WaitForChild("CorpseFX"))
local ImpulseFX = require(ReplicatedStorage:WaitForChild("ImpulseFX"))

local EnemyFX = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("EnemyFX")

-- Сглаживание: за 1/FOLLOW секунды тело проходит ~63% пути до кадра сервера. Кадр сервера
-- приходит рывками (частота репликации ниже кадра), и без сглаживания тело дёргается.
local FOLLOW = 18
-- Дальше — не догонять, а переставить сразу (телепорт, первый кадр, возврат из стриминга).
local SNAP_DISTANCE = 8
-- Метка Пороха: материал и доля пути цвета к чёрному (раньше это делал сервер, Effects.applyPrimer).
local PRIMED_MATERIAL = Enum.Material.Basalt
local PRIMED_DARKEN = 0.5

local tracked = {} -- [server model] = { visual, smooth, hp, gaitless, primed, colors, disguise }

-- ============ Маскировка Мимика ============
-- «Маскируется под мешок, обломок или даже турель». Сервер ставит атрибут Disguise
-- ("sack" / "debris" / "turret", для турели ещё DisguiseTower — её вид), а облик собирается
-- здесь: тело жука прячется, на его месте лежит подделка. Подделка обязана быть неотличима от
-- настоящего, поэтому повторяет то, что уже есть на карте: мешок — из кладки Стены
-- (TowerBuilder: SANDBAG_COLOR, размер мешка), обломок — куча-руина (EnemyStructures.KINDS.ruin
-- и rubble), турель — копия ближайшей настоящей того же вида.
local SANDBAG_COLOR = Color3.fromRGB(191, 172, 126)
local SANDBAG_SIZE = Vector3.new(2.0, 1.02, 1.35)
local RUIN_SIZE = Vector3.new(2.73, 1.24, 2.73) -- руина с двумя единицами материала
local RUIN_COLOR = Color3.fromRGB(122, 110, 92)
local RUBBLE_COLOR = Color3.fromRGB(110, 100, 84)
-- Раскрылся — подделка тает за это время, чтобы смена облика читалась, а не мигала.
local REVEAL_FADE = 0.3

local TweenService = game:GetService("TweenService")
local towersFolder = Workspace:WaitForChild("Towers")

-- Обожжённая глина статуи (Глина + огонь): тёплая терракота, почти без следа цвета жука.
local CERAMIC_COLOR = Color3.fromRGB(196, 128, 92)

-- Подделка — только картинка: ни лучи, ни касания, ни игрок её не чувствуют.
local function inert(part)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
end

local function newPart(parent, size, cframe, color, material)
	local part = Instance.new("Part")
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material
	inert(part)
	part.Parent = parent
	return part
end

-- Два мешка с песком, как выпавшие из кладки: нижний лежит, верхний наискось поперёк.
local function buildSack(look, base)
	for i = 0, 1 do
		local shade = (math.random() - 0.5) * 0.09
		local color = Color3.new(
			math.clamp(SANDBAG_COLOR.R + shade, 0, 1),
			math.clamp(SANDBAG_COLOR.G + shade, 0, 1),
			math.clamp(SANDBAG_COLOR.B + shade * 1.4, 0, 1))
		local at = base * CFrame.new(0, SANDBAG_SIZE.Y * (0.5 + i * 0.8), i * 0.2)
			* CFrame.Angles(0, i * (math.pi / 2 + (math.random() - 0.5) * 0.5), 0)
			* CFrame.Angles((math.random() - 0.5) * 0.12, 0, (math.random() - 0.5) * 0.12)
		local bag = newPart(look, SANDBAG_SIZE, at, color, Enum.Material.Sand)
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = bag
	end
end

-- Куча-руина: тот же блок и те же обломки вокруг, что оставляет снесённая постройка.
local function buildDebris(look, base)
	local centre = base * CFrame.new(0, RUIN_SIZE.Y / 2, 0)
	newPart(look, RUIN_SIZE, centre, RUIN_COLOR, Enum.Material.Slate)
	for _ = 1, 2 do
		local size = Vector3.new(0.8 + math.random() * 0.9, 0.5 + math.random() * 0.5,
			0.8 + math.random() * 0.9)
		local at = CFrame.new(centre.Position + Vector3.new(
			(math.random() - 0.5) * 3.4, -0.2, (math.random() - 0.5) * 3.4))
			* CFrame.Angles(0, math.random() * math.pi, 0)
		newPart(look, size, at, RUBBLE_COLOR, Enum.Material.Slate)
	end
end

-- Что из настоящей турели оставить в копии: геометрию и её облик. Полоски HP, подсветка
-- выбора, свет, частицы и звук выдали бы подделку или жили бы своей жизнью.
local KEEP_IN_COPY = { "BasePart", "Model", "Folder", "DataModelMesh", "FaceInstance",
	"SurfaceAppearance", "Attachment", "JointInstance", "WeldConstraint" }

local function keepInCopy(item)
	for _, class in KEEP_IN_COPY do
		if item:IsA(class) then
			return true
		end
	end
	return false
end

-- Копия ближайшей настоящей турели того же вида. Не вращается и не целится — это и
-- выдаёт её внимательному игроку. Нет такой турели (её уже снесли) — мешок.
local function buildTurret(look, base, towerType)
	local source, best = nil, math.huge
	for _, tower in towersFolder:GetChildren() do
		if tower:IsA("Model") and tower:GetAttribute("Type") == towerType then
			local distance = (tower:GetPivot().Position - base.Position).Magnitude
			if distance < best then
				source, best = tower, distance
			end
		end
	end
	local ok, copy = pcall(function()
		return source and source:Clone()
	end)
	if not ok or not copy then
		buildSack(look, base)
		return
	end

	for _, item in copy:GetDescendants() do
		if not keepInCopy(item) then
			item:Destroy()
		end
	end
	for _, item in copy:GetDescendants() do
		if item:IsA("BasePart") then
			inert(item)
		end
	end
	-- Пивот турели стоит над её подошвой на свою высоту — та же высота и над полом под Мимиком.
	local pivot = source:GetPivot()
	local box, size = source:GetBoundingBox()
	local above = pivot.Position.Y - (box.Position.Y - size.Y / 2)
	copy:PivotTo(CFrame.new(base.Position + Vector3.new(0, above, 0)) * pivot.Rotation)
	for _, item in copy:GetChildren() do
		item.Parent = look
	end
	copy:Destroy()
end

local function setHidden(visual, hidden)
	for _, part in visual:GetDescendants() do
		if part:IsA("BasePart") then
			part.LocalTransparencyModifier = hidden and 1 or 0
		end
	end
end

local function dropDisguise(entry, fade)
	local look = entry.disguise
	if not look then
		return
	end
	entry.disguise = nil
	setHidden(entry.visual, false)
	if not fade then
		look:Destroy()
		return
	end
	local info = TweenInfo.new(REVEAL_FADE)
	for _, part in look:GetDescendants() do
		if part:IsA("BasePart") then
			TweenService:Create(part, info, { Transparency = 1 }):Play()
		end
	end
	task.delay(REVEAL_FADE, function()
		look:Destroy()
	end)
end

local function updateDisguise(model, entry)
	local kind = model:GetAttribute("Disguise")
	if not kind then
		dropDisguise(entry, true)
		return
	end
	if entry.disguise then
		return
	end

	-- Пол — подошва тела жука; поворот подделки — случайный, как легло.
	local box, size = entry.visual:GetBoundingBox()
	local floor = box.Position - Vector3.new(0, size.Y / 2, 0)
	local base = CFrame.new(floor) * CFrame.Angles(0, math.random() * 2 * math.pi, 0)

	local look = Instance.new("Model")
	look.Name = "Disguise"
	if kind == "turret" then
		buildTurret(look, CFrame.new(floor), model:GetAttribute("DisguiseTower"))
	elseif kind == "debris" then
		buildDebris(look, base)
	else
		buildSack(look, base)
	end
	look.Parent = model
	entry.disguise = look
	setHidden(entry.visual, true)
end

local function applyPrimed(entry)
	if entry.primed or not entry.visual then
		return
	end
	entry.primed = true
	-- Исходный облик запоминается: после взрыва метка спадает, и жук возвращает свой цвет.
	entry.colors = {}
	for _, part in entry.visual:GetDescendants() do
		if part:IsA("BasePart") and part.Transparency < 1 then
			entry.colors[part] = { part.Color, part.Material }
			part.Material = PRIMED_MATERIAL
			part.Color = part.Color:Lerp(Color3.new(0, 0, 0), PRIMED_DARKEN)
		end
	end
end

local function clearPrimed(entry)
	if not entry.primed then
		return
	end
	entry.primed = nil
	for part, look in entry.colors or {} do
		part.Color, part.Material = look[1], look[2]
	end
	entry.colors = nil
end

local function buildVisual(model)
	local template = model:GetAttribute("Template")
	local scale = model:GetAttribute("Scale")
	if template then
		return EnemyModel.FromTemplate(template, scale, nil), true
	end
	local enemyData = Enemies[model:GetAttribute("Type")]
	if not enemyData then
		return nil
	end
	return EnemyModel.Build(enemyData, scale), false
end

local function track(model)
	if tracked[model] or not model:IsA("Model") then
		return
	end
	-- Тип и масштаб приходят атрибутами вместе с моделью, но якорь большой модели может
	-- доехать чуть позже самого ChildAdded.
	local t0 = os.clock()
	while model.Parent and not (model.PrimaryPart and (model:GetAttribute("Type") or model:GetAttribute("Template")))
		and os.clock() - t0 < 5 do
		task.wait()
	end
	if not model.Parent or not model.PrimaryPart or tracked[model] then
		return
	end

	local ok, visual, arcade = pcall(buildVisual, model)
	if not ok or not visual then
		warn("[EnemyRender] не собрать тело для", model:GetFullName(), visual)
		return
	end
	visual.Name = "Visual"
	local pivot = model:GetPivot()
	visual:PivotTo(pivot)
	visual.Parent = model

	local entry = {
		visual = visual,
		smooth = pivot,
		hp = model:GetAttribute("HP"),
		arcade = arcade,
	}
	tracked[model] = entry

	if model:GetAttribute("Primed") then
		applyPrimed(entry)
	end
	model:GetAttributeChangedSignal("Primed"):Connect(function()
		if model:GetAttribute("Primed") then
			applyPrimed(entry)
		else
			clearPrimed(entry)
		end
	end)

	updateDisguise(model, entry)
	model:GetAttributeChangedSignal("Disguise"):Connect(function()
		updateDisguise(model, entry)
	end)

	-- Вздрагивание от попадания: сила — доля макс. HP, направление — HitFrom (его ставит
	-- Projectile.dealDamage раньше HP).
	model:GetAttributeChangedSignal("HP"):Connect(function()
		local hp = model:GetAttribute("HP")
		local last = entry.hp
		entry.hp = hp
		if not (hp and last) or hp >= last or hp <= 0 then
			return
		end
		local maxHp = model:GetAttribute("MaxHP") or last
		local from = model:GetAttribute("HitFrom")
		if from and maxHp > 0 then
			EnemyGait.Flinch(visual, from, (last - hp) / maxHp)
		end
	end)
end

local function untrack(model)
	local entry = tracked[model]
	if entry then
		tracked[model] = nil
		dropDisguise(entry, false)
		if entry.visual and entry.visual.Parent then
			entry.visual:Destroy()
		end
	end
end

local function watch(folder)
	for _, model in folder:GetChildren() do
		task.spawn(track, model)
	end
	folder.ChildAdded:Connect(function(model)
		task.spawn(track, model)
	end)
	folder.ChildRemoved:Connect(untrack)
end

watch(Workspace:WaitForChild("Enemies"))
-- Очищенные Мылом переезжают в Allies (см. EnemySpawner): тело пересобирается там же,
-- где жук стоял, — ChildRemoved в Enemies снимает старое, ChildAdded здесь строит новое.
task.spawn(function()
	watch(Workspace:WaitForChild("Allies"))
end)
task.spawn(function()
	local arcade = Workspace:WaitForChild("Arcade", 30)
	local bugs = arcade and arcade:WaitForChild("ArcadeBugs", 30)
	if bugs then
		watch(bugs)
	end
end)

RunService.RenderStepped:Connect(function(dt)
	dt = math.min(dt, 0.1)
	local alpha = 1 - math.exp(-FOLLOW * dt)
	for model, entry in tracked do
		local root = model.PrimaryPart
		if not model.Parent or not entry.visual.Parent then
			untrack(model)
		elseif root then
			local target = root.CFrame
			if (target.Position - entry.smooth.Position).Magnitude > SNAP_DISTANCE then
				entry.smooth = target
			else
				entry.smooth = entry.smooth:Lerp(target, alpha)
			end
			local gait = model:GetAttribute("Gait") or (entry.arcade and "walk") or nil
			if gait then
				EnemyGait.Step(entry.visual, dt, gait, entry.smooth, model:GetAttribute("Look"),
					model:GetAttribute("Crawling"))
			else
				-- Летуны и жуки со своим циклом (Лицехват, Моль, Пеликан в воздухе): ног не
				-- переставляют, тело просто идёт за якорем. Крылья в воздухе машут.
				entry.visual:PivotTo(entry.smooth)
				if model:GetAttribute("Flying") then
					EnemyGait.Flap(entry.visual, dt)
				end
			end
		end
	end
end)

-- ============ События сервера (Corpses, Impulse) ============

EnemyFX.OnClientEvent:Connect(function(kind, a, b, c, d)
	if kind == "death" then
		-- Серверная модель ещё на месте: событие уходит до её Destroy.
		local visual = a and a:FindFirstChild("Visual")
		-- Убит под маской (зоной, взрывом) — труп остаётся жучиный, подделка исчезает.
		local entry = a and tracked[a]
		if entry then
			dropDisguise(entry, false)
		end
		if visual then
			local ok, err = pcall(CorpseFX.Leave, visual, c, b)
			if not ok then
				warn("[EnemyRender] труп:", err)
			end
			untrack(a)
		end
	elseif kind == "statue" then
		-- Глина + огонь: тело жука застывает как было, в позе этой секунды, и встаёт
		-- в серверную статую (Corpses.Statue). Снесут статую — уйдёт и копия.
		local visual = a and a:FindFirstChild("Visual")
		local entry = a and tracked[a]
		if entry then
			dropDisguise(entry, false)
		end
		if visual and b then
			local copy = visual:Clone()
			copy.Name = "Ceramic"
			for _, item in copy:GetDescendants() do
				if item:IsA("BasePart") then
					inert(item)
					item.Color = item.Color:Lerp(CERAMIC_COLOR, 0.85)
					item.Material = Enum.Material.SmoothPlastic
					item.Reflectance = 0.08
				elseif not (item:IsA("Model") or item:IsA("Folder") or item:IsA("SpecialMesh")
					or item:IsA("Attachment")) then
					item:Destroy() -- полоска HP, огонь, обводка, суставы
				end
			end
			for name in copy:GetAttributes() do
				if name:sub(1, 4) ~= "RBX_" then
					copy:SetAttribute(name, nil)
				end
			end
			copy.Parent = b
		end
		untrack(a)
	elseif kind == "splat" then
		CorpseFX.Splat(a, b, c, d)
	elseif kind == "absorb" then
		CorpseFX.Absorb(a, b)
	elseif kind == "clear" then
		CorpseFX.Clear()
	elseif kind == "eat" then
		CorpseFX.Eat(a)
	elseif kind == "shatter" then
		CorpseFX.Shatter(a)
	elseif kind == "blast" then
		ImpulseFX.Blast(a, b, c)
	elseif kind == "push" then
		ImpulseFX.Push(a, b)
	end
end)
