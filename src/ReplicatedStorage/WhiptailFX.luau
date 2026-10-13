-- Приёмы Бичехвоста на КЛИЕНТЕ (Remotes.EnemyFX "lob" / "lash", шлёт EnemyTraits).
-- Сервер считает урон и ставит атрибуты турели; здесь только то, что видно: комок кислоты
-- по дуге, лужа на турели и бич по прямой. Отброс игрока — тоже здесь: персонажем владеет
-- его клиент, и толчок с сервера дошёл бы до него рывком с задержкой.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local WhiptailFX = {}

local ACID = Color3.fromRGB(150, 215, 30)
local ACID_DARK = Color3.fromRGB(80, 120, 20)
local LASH = Color3.fromRGB(70, 32, 18)

local function folder()
	local found = Workspace:FindFirstChild("WhiptailFX")
	if not found then
		found = Instance.new("Folder")
		found.Name = "WhiptailFX"
		found.Parent = Workspace
	end
	return found
end

local function part(shape, size, color, material)
	local p = Instance.new("Part")
	p.Shape = shape
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.Neon
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.Parent = folder()
	return p
end

local function fadeOut(p, time)
	local tween = TweenService:Create(p, TweenInfo.new(time), { Transparency = 1 })
	tween.Completed:Once(function()
		p:Destroy()
	end)
	tween:Play()
end

-- Брызги в точке: несколько капель разлетаются и гаснут.
local function splash(at)
	for _ = 1, 6 do
		local drop = part(Enum.PartType.Ball, Vector3.one * (0.3 + math.random() * 0.3), ACID)
		drop.Position = at
		local angle = math.random() * math.pi * 2
		local goal = at + Vector3.new(math.cos(angle) * 2, 0.6 + math.random(), math.sin(angle) * 2)
		TweenService:Create(drop, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Position = goal, Transparency = 1 }):Play()
		task.delay(0.4, drop.Destroy, drop)
	end
end

-- Комок кислоты из from в to за flight секунд по дуге высотой arc; на месте — лужа,
-- которая стекает duration секунд (столько турель и стреляет реже).
function WhiptailFX.Lob(from, to, flight, arc, duration)
	if typeof(from) ~= "Vector3" or typeof(to) ~= "Vector3" then
		return
	end
	flight = math.max(flight or 1, 0.1)
	local blob = part(Enum.PartType.Ball, Vector3.one * 1.1, ACID)
	local start = os.clock()
	local connection
	connection = RunService.RenderStepped:Connect(function()
		local t = math.min((os.clock() - start) / flight, 1)
		blob.Position = from:Lerp(to, t) + Vector3.new(0, (arc or 6) * 4 * t * (1 - t), 0)
		if t >= 1 then
			connection:Disconnect()
			blob:Destroy()
			splash(to)
			local puddle = part(Enum.PartType.Cylinder, Vector3.new(0.15, 3.2, 3.2), ACID_DARK, Enum.Material.Glass)
			puddle.CFrame = CFrame.new(to) * CFrame.Angles(0, 0, math.rad(90))
			puddle.Transparency = 0.2
			fadeOut(puddle, duration or 5)
		end
	end)
end

-- Бич от from до to шириной width. Свой персонаж на полосе отбрасывает вдоль удара.
function WhiptailFX.Lash(from, to, width, push, lift)
	if typeof(from) ~= "Vector3" or typeof(to) ~= "Vector3" then
		return
	end
	local delta = to - Vector3.new(0, to.Y - from.Y, 0) - from
	local length = delta.Magnitude
	if length < 1e-3 then
		return
	end
	local direction = delta.Unit
	local floorY = to.Y
	-- Хлыст опускается от спины к полу: длинная тонкая полоса, вспыхнула и погасла.
	local finish = Vector3.new(to.X, floorY + 0.4, to.Z)
	local middle = (from + finish) / 2
	local whip = part(Enum.PartType.Block, Vector3.new(0.35, 0.35, (finish - from).Magnitude), LASH,
		Enum.Material.SmoothPlastic)
	whip.CFrame = CFrame.lookAt(middle, finish)
	fadeOut(whip, 0.3)
	local trail = part(Enum.PartType.Block, Vector3.new(width or 3, 0.1, length), ACID_DARK)
	trail.CFrame = CFrame.lookAt(Vector3.new(middle.X, floorY + 0.1, middle.Z),
		Vector3.new(finish.X, floorY + 0.1, finish.Z))
	trail.Transparency = 0.5
	fadeOut(trail, 0.4)

	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 then
		return
	end
	local offset = Vector3.new(root.Position.X - from.X, 0, root.Position.Z - from.Z)
	local along = offset:Dot(direction)
	local side = (offset - direction * along).Magnitude
	if along >= 0 and along <= length and side <= (width or 3) / 2 + 1 then
		local speed = push or 50
		root.AssemblyLinearVelocity = direction * speed + Vector3.new(0, speed * (lift or 0.3), 0)
		humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
	end
end

return WhiptailFX
