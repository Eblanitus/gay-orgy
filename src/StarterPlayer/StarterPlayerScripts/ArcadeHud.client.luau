-- Счётчик аркады: сколько жуков раздавлено машиной за текущий заезд. Обычный
-- HUD забега (Hud.lua) тут ни при чём — у режима свои показания, видные
-- только пока игрок в аркаде (ArcadeEntered/ArcadeExited).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Balance = require(ReplicatedStorage:WaitForChild("Arcade"))

local MobileUI = require(script.Parent:WaitForChild("MobileUI"))
local Theme = require(script.Parent:WaitForChild("UITheme"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local ArcadeEnteredRemote = Remotes:WaitForChild("ArcadeEntered")
local ArcadeExitedRemote = Remotes:WaitForChild("ArcadeExited")
local ArcadeSquashCountRemote = Remotes:WaitForChild("ArcadeSquashCount")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "ArcadeHud"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = MobileUI.Layer.Hud
screenGui.Enabled = false
screenGui.Parent = playerGui

local label = Instance.new("TextLabel")
label.AnchorPoint = Vector2.new(0, 0)
label.Position = UDim2.new(0, MobileUI.EDGE, 0, MobileUI.TopInset + MobileUI.EDGE)
label.Size = UDim2.new(0, 240, 0, MobileUI.isMobile and 24 or 28)
label.BackgroundTransparency = 1
label.RichText = true
label.TextXAlignment = Enum.TextXAlignment.Left
label.TextSize = MobileUI.isMobile and 14 or 17
label.Parent = screenGui
Theme.Display(label)
label.Text = Theme.Readout("раздавлено", "0", Theme.color.accent)

local labelScale = Instance.new("UIScale")
labelScale.Parent = label

-- ---- Тряска камеры при давке ----
-- Чисто вид: сервер уже раздавил жука и прислал счёт. Сдвиг накладывается поверх
-- кадра штатной камеры (она сама выставляет CFrame каждый кадр), поэтому не копится.
local SHAKE = Balance.shake
local trauma = 0
local lastCount = 0

RunService:BindToRenderStep("ArcadeShake", Enum.RenderPriority.Camera.Value + 1, function(dt)
	if trauma <= 0 then
		return
	end
	trauma = math.max(0, trauma - SHAKE.decay * dt)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	-- math.noise отдаёт примерно -0.5..0.5 — ×2, чтобы offset/roll из баланса были настоящим размахом.
	local power = trauma * trauma * 2
	local t = os.clock() * SHAKE.frequency
	local ox = math.noise(t, 0.3) * SHAKE.offset * power
	local oy = math.noise(t, 7.1) * SHAKE.offset * power
	local roll = math.noise(t, 13.7) * SHAKE.roll * power
	camera.CFrame = camera.CFrame * CFrame.new(ox, oy, 0) * CFrame.Angles(0, 0, roll)
end)

local POP = Balance.counterPop
local popIn = TweenInfo.new(POP.time * 0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local popOut = TweenInfo.new(POP.time * 0.65, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

local function pop()
	labelScale.Scale = 1
	local grow = TweenService:Create(labelScale, popIn, { Scale = POP.scale })
	grow.Completed:Connect(function(state)
		if state == Enum.PlaybackState.Completed then
			TweenService:Create(labelScale, popOut, { Scale = 1 }):Play()
		end
	end)
	grow:Play()
end

MobileUI.OnViewportChanged(function()
	label.Position = UDim2.new(0, MobileUI.EDGE, 0, MobileUI.TopInset + MobileUI.EDGE)
end)

ArcadeEnteredRemote.OnClientEvent:Connect(function()
	label.Text = Theme.Readout("раздавлено", "0", Theme.color.accent)
	lastCount = 0
	trauma = 0
	screenGui.Enabled = true
end)

ArcadeExitedRemote.OnClientEvent:Connect(function()
	screenGui.Enabled = false
	trauma = 0
end)

ArcadeSquashCountRemote.OnClientEvent:Connect(function(count)
	label.Text = Theme.Readout("раздавлено", tostring(count), Theme.color.accent)
	local squashed = count - lastCount
	lastCount = count
	if squashed > 0 then
		trauma = math.min(1, trauma + SHAKE.perSquash * squashed)
		pop()
	end
end)
