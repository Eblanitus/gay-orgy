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

local tracked = {} -- [server model] = { visual, smooth, hp, gaitless, primed, colors }

local function applyPrimed(entry)
	if entry.primed or not entry.visual then
		return
	end
	entry.primed = true
	for _, part in entry.visual:GetDescendants() do
		if part:IsA("BasePart") and part.Transparency < 1 then
			part.Material = PRIMED_MATERIAL
			part.Color = part.Color:Lerp(Color3.new(0, 0, 0), PRIMED_DARKEN)
		end
	end
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
		end
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
				EnemyGait.Step(entry.visual, dt, gait, entry.smooth, model:GetAttribute("Look"))
			else
				-- Летуны и жуки со своим циклом (Лицехват, Моль, Пеликан в воздухе): ног не
				-- переставляют, тело просто идёт за якорем.
				entry.visual:PivotTo(entry.smooth)
			end
		end
	end
end)

-- ============ События сервера (Corpses, Impulse) ============

EnemyFX.OnClientEvent:Connect(function(kind, a, b, c, d)
	if kind == "death" then
		-- Серверная модель ещё на месте: событие уходит до её Destroy.
		local visual = a and a:FindFirstChild("Visual")
		if visual then
			local ok, err = pcall(CorpseFX.Leave, visual, c, b)
			if not ok then
				warn("[EnemyRender] труп:", err)
			end
			untrack(a)
		end
	elseif kind == "splat" then
		CorpseFX.Splat(a, b, c, d)
	elseif kind == "absorb" then
		CorpseFX.Absorb(a, b)
	elseif kind == "clear" then
		CorpseFX.Clear()
	elseif kind == "eat" then
		CorpseFX.Eat(a)
	elseif kind == "blast" then
		ImpulseFX.Blast(a, b, c)
	elseif kind == "push" then
		ImpulseFX.Push(a, b)
	end
end)
