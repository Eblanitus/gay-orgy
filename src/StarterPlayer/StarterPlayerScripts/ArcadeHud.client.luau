-- Табло аркады: очки, сколько раздавлено, рекорд, серия-комбо с полоской до её конца,
-- подсказка при входе, объявления (рекорд, золотой жук) и итог заезда после выхода.
-- Обычный HUD забега (Hud.lua) тут ни при чём — у режима свои показания, видные только
-- пока игрок в аркаде (ArcadeEntered/ArcadeExited). Тут же тряска камеры при давке и
-- поле зрения по скорости машины. Всплывающие очки, звук и золотой цвет — ArcadeFX.
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
local arcadeFolder = Workspace:WaitForChild("Arcade")

local mobile = MobileUI.isMobile
local BIG = mobile and 20 or 26 -- кегль очков и комбо
local LINE = mobile and 16 or 18

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "ArcadeHud"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = MobileUI.Layer.Hud
screenGui.Enabled = false
screenGui.Parent = playerGui

-- Цвет ступени комбо: чем длиннее серия, тем горячее.
local TIER_COLORS = {
	Theme.color.accent,
	Theme.color.action,
	Theme.color.energy,
	Theme.color.warn,
	Theme.color.danger,
}
local function tierColor(tier)
	return TIER_COLORS[math.clamp(tier or 1, 1, #TIER_COLORS)]
end

local function newLabel(parent, size, order)
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.RichText = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextSize = math.max(Theme.MIN_TEXT, size)
	label.Size = UDim2.new(1, 0, 0, size + 6)
	label.LayoutOrder = order or 0
	label.TextColor3 = Theme.color.text
	Theme.Display(label)
	label.Parent = parent
	return label
end

-- ---- табло: очки, раздавлено, рекорд ----
-- Плашка языком рамки главного меню, а не голый текст поверх поля.
local board = Instance.new("Frame")
board.AnchorPoint = Vector2.new(0, 0)
board.Size = UDim2.fromOffset(mobile and 210 or 250, 0)
board.AutomaticSize = Enum.AutomaticSize.Y
board.Parent = screenGui
Theme.Plate(board, { brackets = false, dots = false })
local boardPad = Instance.new("UIPadding")
boardPad.PaddingLeft = UDim.new(0, 12)
boardPad.PaddingRight = UDim.new(0, 12)
boardPad.PaddingTop = UDim.new(0, 6)
boardPad.PaddingBottom = UDim.new(0, 6)
boardPad.Parent = board
local boardList = Instance.new("UIListLayout")
boardList.SortOrder = Enum.SortOrder.LayoutOrder
boardList.Parent = board

local scoreLabel = newLabel(board, BIG, 1)
local countLabel = newLabel(board, LINE, 2)
local bestLabel = newLabel(board, LINE, 3)

local scoreScale = Instance.new("UIScale")
scoreScale.Parent = scoreLabel

local function placeBoard()
	board.Position = UDim2.fromOffset(MobileUI.EDGE, MobileUI.TopInset + MobileUI.EDGE)
end
placeBoard()

-- ---- комбо: по центру сверху, с полоской до конца серии ----
local comboBox = Instance.new("Frame")
comboBox.AnchorPoint = Vector2.new(0.5, 0)
comboBox.Size = UDim2.fromOffset(mobile and 200 or 260, 0)
comboBox.AutomaticSize = Enum.AutomaticSize.Y
comboBox.Visible = false
comboBox.Parent = screenGui
Theme.Plate(comboBox, { brackets = false, dots = false })
local comboPad = Instance.new("UIPadding")
comboPad.PaddingLeft = UDim.new(0, 12)
comboPad.PaddingRight = UDim.new(0, 12)
comboPad.PaddingTop = UDim.new(0, 4)
comboPad.PaddingBottom = UDim.new(0, 8)
comboPad.Parent = comboBox
local comboList = Instance.new("UIListLayout")
comboList.SortOrder = Enum.SortOrder.LayoutOrder
comboList.HorizontalAlignment = Enum.HorizontalAlignment.Center
comboList.Padding = UDim.new(0, 4)
comboList.Parent = comboBox

local comboLabel = newLabel(comboBox, BIG, 1)
comboLabel.TextXAlignment = Enum.TextXAlignment.Center
local comboScale = Instance.new("UIScale")
comboScale.Parent = comboLabel

local comboTrack = Instance.new("Frame")
comboTrack.Size = UDim2.new(1, 0, 0, 6)
comboTrack.BackgroundColor3 = Theme.color.hpBack
comboTrack.BorderSizePixel = 0
comboTrack.LayoutOrder = 2
comboTrack.Parent = comboBox
Theme.Corner(comboTrack, 3)
local comboFill = Instance.new("Frame")
comboFill.Size = UDim2.fromScale(1, 1)
comboFill.BorderSizePixel = 0
comboFill.BackgroundColor3 = Theme.color.accent
comboFill.Parent = comboTrack
Theme.Corner(comboFill, 3)

-- ---- объявление посреди экрана: подсказка, рекорд, золотой жук ----
local banner = Instance.new("TextLabel")
banner.AnchorPoint = Vector2.new(0.5, 0.5)
banner.Position = UDim2.fromScale(0.5, 0.3)
banner.Size = UDim2.fromOffset(0, 0)
banner.AutomaticSize = Enum.AutomaticSize.XY
banner.TextSize = BIG
banner.RichText = true
banner.TextWrapped = false
banner.Visible = false
banner.Parent = screenGui
Theme.Display(banner)
Theme.ArenaBacking(banner)
local bannerPad = Instance.new("UIPadding")
bannerPad.PaddingLeft = UDim.new(0, 16)
bannerPad.PaddingRight = UDim.new(0, 16)
bannerPad.PaddingTop = UDim.new(0, 8)
bannerPad.PaddingBottom = UDim.new(0, 8)
bannerPad.Parent = banner
local bannerScale = Instance.new("UIScale")
bannerScale.Parent = banner

local bannerToken = 0
local function announce(text, color, seconds)
	bannerToken += 1
	local token = bannerToken
	banner.Text = text
	banner.TextColor3 = color or Theme.color.text
	banner.TextTransparency = 0
	banner.BackgroundTransparency = 0.3
	banner.Visible = true
	bannerScale.Scale = 1.25
	TweenService:Create(bannerScale, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	task.delay(seconds or 2, function()
		if token ~= bannerToken then
			return
		end
		local fade = TweenInfo.new(0.4)
		TweenService:Create(banner, fade, { TextTransparency = 1, BackgroundTransparency = 1 }):Play()
		task.delay(0.4, function()
			if token == bannerToken then
				banner.Visible = false
			end
		end)
	end)
end

-- ---- итог заезда: поверх главного меню, пока оно открывается после выхода ----
local summaryGui = Instance.new("ScreenGui")
summaryGui.Name = "ArcadeSummary"
summaryGui.ResetOnSpawn = false
summaryGui.IgnoreGuiInset = true
summaryGui.DisplayOrder = MobileUI.Layer.Notify
summaryGui.Enabled = false
summaryGui.Parent = playerGui

local summary = Instance.new("Frame")
summary.AnchorPoint = Vector2.new(0.5, 0)
summary.Size = UDim2.fromOffset(mobile and 260 or 320, 0)
summary.AutomaticSize = Enum.AutomaticSize.Y
summary.Parent = summaryGui
Theme.Plate(summary, { dots = false })
local summaryPad = Instance.new("UIPadding")
summaryPad.PaddingLeft = UDim.new(0, 16)
summaryPad.PaddingRight = UDim.new(0, 16)
summaryPad.PaddingTop = UDim.new(0, 12)
summaryPad.PaddingBottom = UDim.new(0, 12)
summaryPad.Parent = summary
local summaryList = Instance.new("UIListLayout")
summaryList.SortOrder = Enum.SortOrder.LayoutOrder
summaryList.Padding = UDim.new(0, 2)
summaryList.Parent = summary
local summaryTitle = newLabel(summary, LINE, 1)
local summaryScore = newLabel(summary, BIG, 2)
local summaryCount = newLabel(summary, LINE, 3)
local summaryCombo = newLabel(summary, LINE, 4)
local summaryBest = newLabel(summary, LINE, 5)

local function placeSummary()
	summary.Position = UDim2.new(0.5, 0, 0, MobileUI.TopInset + MobileUI.EDGE)
end
placeSummary()

MobileUI.OnViewportChanged(function()
	placeBoard()
	placeSummary()
	comboBox.Position = UDim2.new(0.5, 0, 0, MobileUI.TopInset + MobileUI.EDGE)
end)
comboBox.Position = UDim2.new(0.5, 0, 0, MobileUI.TopInset + MobileUI.EDGE)

-- ============ Состояние заезда ============

local score, count, best = 0, 0, 0
local recordShown = false
local comboUntil, comboWindow = 0, 1

local function paintBoard()
	scoreLabel.Text = Theme.Readout("очки", tostring(score), Theme.color.accent)
	countLabel.Text = Theme.Readout("раздавлено", tostring(count), Theme.color.text)
	local beaten = score > best and best > 0
	bestLabel.Text = Theme.Readout("рекорд", tostring(math.max(best, score)),
		beaten and Theme.color.energy or Theme.color.textDim)
end

local function bump(scale, size)
	scale.Scale = size
	TweenService:Create(scale, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

-- ---- Тряска камеры и поле зрения ----
-- Чисто вид: сервер уже раздавил жука и прислал счёт. Сдвиг накладывается поверх
-- кадра штатной камеры (она сама выставляет CFrame каждый кадр), поэтому не копится.
local SHAKE = Balance.shake
local CAR = Balance.car
local trauma = 0
local fov = CAR.fovBase
local savedFov = nil

local function carSpeed()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local seat = humanoid and humanoid.SeatPart
	local car = seat and seat.Parent
	if car and car:GetAttribute("ArcadeCar") and car.PrimaryPart then
		local v = car.PrimaryPart.AssemblyLinearVelocity
		return Vector3.new(v.X, 0, v.Z).Magnitude
	end
	return 0
end

RunService:BindToRenderStep("ArcadeShake", Enum.RenderPriority.Camera.Value + 1, function(dt)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	if screenGui.Enabled then
		-- Комбо гаснет у всех на глазах: полоска тает до конца окна серии.
		local left = comboUntil - os.clock()
		if comboBox.Visible then
			if left <= 0 then
				comboBox.Visible = false
			else
				comboFill.Size = UDim2.fromScale(math.clamp(left / comboWindow, 0, 1), 1)
			end
		end

		-- Поле зрения шире на скорости, плюс толчок от каждой давки.
		if not savedFov then
			savedFov = camera.FieldOfView
		end
		local speed01 = math.clamp(carSpeed() / CAR.maxSpeed, 0, 1)
		local target = CAR.fovBase + (CAR.fovFast - CAR.fovBase) * speed01 + CAR.fovKick * trauma
		fov += (target - fov) * math.clamp(CAR.fovResponse * dt, 0, 1)
		camera.FieldOfView = fov
	elseif savedFov then
		camera.FieldOfView = savedFov
		savedFov = nil
		fov = CAR.fovBase
	end

	if trauma <= 0 then
		return
	end
	trauma = math.max(0, trauma - SHAKE.decay * dt)
	-- math.noise отдаёт примерно -0.5..0.5 — ×2, чтобы offset/roll из баланса были настоящим размахом.
	local power = trauma * trauma * 2
	local t = os.clock() * SHAKE.frequency
	local ox = math.noise(t, 0.3) * SHAKE.offset * power
	local oy = math.noise(t, 7.1) * SHAKE.offset * power
	local roll = math.noise(t, 13.7) * SHAKE.roll * power
	camera.CFrame = camera.CFrame * CFrame.new(ox, oy, 0) * CFrame.Angles(0, 0, roll)
end)

-- ============ События ============

ArcadeEnteredRemote.OnClientEvent:Connect(function(info)
	score, count = 0, 0
	best = type(info) == "table" and tonumber(info.best) or 0
	recordShown = false
	comboUntil = 0
	comboBox.Visible = false
	trauma = 0
	paintBoard()
	summaryGui.Enabled = false
	screenGui.Enabled = true
	announce(Theme.StatusText("аркада", "дави жуков, серия подряд умножает очки"), Theme.color.text, 3.5)
end)

local summaryToken = 0
ArcadeExitedRemote.OnClientEvent:Connect(function(result)
	screenGui.Enabled = false
	trauma = 0
	if type(result) ~= "table" or (tonumber(result.squashed) or 0) <= 0 then
		return
	end
	summaryTitle.Text = Theme.Readout("итог заезда", result.record and "НОВЫЙ РЕКОРД" or "",
		Theme.color.energy)
	summaryScore.Text = Theme.Readout("очки", tostring(result.score or 0), Theme.color.accent)
	summaryCount.Text = Theme.Readout("раздавлено", tostring(result.squashed or 0), Theme.color.text)
	summaryCombo.Text = Theme.Readout("лучшая серия", tostring(result.bestCombo or 0), Theme.color.text)
	summaryBest.Text = Theme.Readout("рекорд", tostring(result.best or 0), Theme.color.textDim)
	summaryGui.Enabled = true
	summaryToken += 1
	local token = summaryToken
	task.delay(6, function()
		if token == summaryToken then
			summaryGui.Enabled = false
		end
	end)
end)

ArcadeSquashCountRemote.OnClientEvent:Connect(function(newCount, info)
	local squashed = newCount - count
	count = newCount
	if type(info) == "table" then
		score = tonumber(info.score) or score
		local combo = tonumber(info.combo) or 1
		comboWindow = tonumber(info.window) or 1
		comboUntil = os.clock() + comboWindow
		if combo >= 2 then
			local color = tierColor(info.tier)
			comboLabel.Text = ('<font color="%s">КОМБО ×%d</font>  <font size="%d" color="%s">%d ПОДРЯД</font>'):format(
				Theme.Hex(color), info.mult or 1, math.max(Theme.MIN_TEXT, LINE), Theme.Hex(Theme.color.textDim), combo)
			comboFill.BackgroundColor3 = color
			comboBox.Visible = true
			bump(comboScale, 1.3)
		end
		if info.golden then
			announce(Theme.StatusText("золотой жук", "+" .. tostring(info.points or 0)), Theme.color.energy, 2)
		end
	end
	if not recordShown and best > 0 and score > best then
		recordShown = true
		announce("НОВЫЙ РЕКОРД", Theme.color.energy, 2)
	end
	paintBoard()
	if squashed > 0 then
		trauma = math.min(1, trauma + SHAKE.perSquash * squashed)
		bump(scoreScale, Balance.counterPop.scale)
	end
end)

-- Золотой жук вышел на поле — сказать об этом, пока он не убежал.
task.spawn(function()
	local bugs = arcadeFolder:WaitForChild("ArcadeBugs", 30)
	if not bugs then
		return
	end
	bugs.ChildAdded:Connect(function(model)
		if screenGui.Enabled and model:GetAttribute("Golden") then
			announce(Theme.StatusText("на поле", "золотой жук"), Theme.color.energy, 2.5)
		end
	end)
end)
