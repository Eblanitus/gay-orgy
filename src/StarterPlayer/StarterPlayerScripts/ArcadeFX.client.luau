-- Ощущение от давки в аркаде, чисто вид: всплывающие очки над раздавленным, звук давки
-- (выше с каждой ступенью комбо) и золотой цвет с блеском у золотого жука. Счёт и
-- комбо решает сервер (ArcadeMode) и присылает в ArcadeSquashCount; табло — ArcadeHud.
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Balance = require(ReplicatedStorage:WaitForChild("Arcade"))
local Theme = require(script.Parent:WaitForChild("UITheme"))
local MobileUI = require(script.Parent:WaitForChild("MobileUI"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local ArcadeSquashCountRemote = Remotes:WaitForChild("ArcadeSquashCount")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local arcadeFolder = Workspace:WaitForChild("Arcade")

local SOUNDS = Balance.sounds
local POPUP = Balance.popup
local GOLD = Color3.fromRGB(255, 196, 64)

local TIER_COLORS = {
	Theme.color.accent,
	Theme.color.action,
	Theme.color.energy,
	Theme.color.warn,
	Theme.color.danger,
}

-- ---- звук ----
-- Копия звука интерфейса (SoundService.UISounds) со своей высотой: свой SoundGroup
-- копия сохраняет, так что ползунки громкости из настроек действуют и здесь.
local uiSounds = SoundService:WaitForChild("UISounds", 10)
local lastPlayed = {}

local function play(row, tier)
	local source = row and uiSounds and uiSounds:FindFirstChild(row.name)
	if not source then
		return
	end
	-- Пачка жуков за один кадр — один звук, а не гул.
	local now = os.clock()
	if lastPlayed[row] and now - lastPlayed[row] < 0.04 then
		return
	end
	lastPlayed[row] = now
	local sound = source:Clone()
	sound.Volume = source.Volume * (row.volume or 1)
	sound.PlaybackSpeed = (row.pitch or 1) + (row.pitchPerCombo or 0) * ((tier or 1) - 1)
	sound.Parent = SoundService
	sound.Ended:Once(function()
		sound:Destroy()
	end)
	sound:Play()
	Debris:AddItem(sound, row.cut or 5)
end

-- ---- всплывающие очки ----
local popupSize = math.max(Theme.MIN_TEXT, MobileUI.isMobile and 22 or 28)

local function popup(at, points, tier, golden)
	local anchor = Instance.new("Attachment")
	anchor.WorldPosition = at
	anchor.Parent = Workspace.Terrain

	local gui = Instance.new("BillboardGui")
	gui.Adornee = anchor
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Size = UDim2.fromOffset(160, popupSize + 10)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 3, 0)
	gui.Parent = playerGui

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.TextSize = popupSize
	label.Text = "+" .. tostring(points)
	label.TextColor3 = golden and GOLD or TIER_COLORS[math.clamp(tier or 1, 1, #TIER_COLORS)]
	label.TextStrokeColor3 = Theme.color.ink
	label.TextStrokeTransparency = 0.3
	Theme.Display(label)
	label.Parent = gui
	local scale = Instance.new("UIScale")
	scale.Scale = 1.4 + 0.1 * ((tier or 1) - 1)
	scale.Parent = label

	local rise = TweenInfo.new(POPUP.time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(gui, rise, { StudsOffsetWorldSpace = Vector3.new(0, 3 + POPUP.rise, 0) }):Play()
	TweenService:Create(scale, TweenInfo.new(0.15, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	TweenService:Create(label, TweenInfo.new(POPUP.time * 0.5, Enum.EasingStyle.Linear, Enum.EasingDirection.In, 0, false, POPUP.time * 0.5),
		{ TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	Debris:AddItem(gui, POPUP.time + 0.1)
	Debris:AddItem(anchor, POPUP.time + 0.1)
end

local lastTier = 1
ArcadeSquashCountRemote.OnClientEvent:Connect(function(_, info)
	if type(info) ~= "table" then
		return
	end
	local tier = tonumber(info.tier) or 1
	if typeof(info.at) == "Vector3" then
		popup(info.at, info.points or 0, tier, info.golden)
	end
	play(SOUNDS.squash, tier)
	if info.golden then
		play(SOUNDS.golden)
	elseif tier > lastTier then
		play(SOUNDS.comboUp, tier)
	end
	lastTier = tier
end)

-- ---- золотой жук ----
-- Тело строит EnemyRender (дочерний Visual) — красим его, когда оно появилось.
local function gild(visual)
	for _, part in visual:GetDescendants() do
		if part:IsA("BasePart") and part.Transparency < 1 then
			part.Color = GOLD
			part.Material = Enum.Material.Foil
			part.Reflectance = 0.25
		end
	end
	local root = visual.PrimaryPart or visual:FindFirstChildWhichIsA("BasePart", true)
	if root then
		local light = Instance.new("PointLight")
		light.Color = GOLD
		light.Range = 14
		light.Brightness = 2
		light.Parent = root
		local sparkle = Instance.new("ParticleEmitter")
		sparkle.Color = ColorSequence.new(GOLD)
		sparkle.LightEmission = 1
		sparkle.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0) })
		sparkle.Lifetime = NumberRange.new(0.4, 0.8)
		sparkle.Rate = 18
		sparkle.Speed = NumberRange.new(2, 5)
		sparkle.SpreadAngle = Vector2.new(180, 180)
		sparkle.Parent = root
	end
end

local function watchBug(model)
	if not model:GetAttribute("Golden") then
		return
	end
	local visual = model:FindFirstChild("Visual")
	if visual then
		gild(visual)
	end
	model.ChildAdded:Connect(function(child)
		if child.Name == "Visual" and child:IsA("Model") then
			gild(child)
		end
	end)
end

task.spawn(function()
	local bugs = arcadeFolder:WaitForChild("ArcadeBugs", 30)
	if not bugs then
		return
	end
	for _, model in bugs:GetChildren() do
		watchBug(model)
	end
	bugs.ChildAdded:Connect(watchBug)
end)

-- Рекорд — свой звук. Табло (ArcadeHud) сравнивает с рекордом само; здесь хватает
-- того же правила: очки впервые за заезд перевалили за рекорд при входе.
local best, recordPlayed, score = 0, false, 0
Remotes:WaitForChild("ArcadeEntered").OnClientEvent:Connect(function(info)
	best = type(info) == "table" and tonumber(info.best) or 0
	recordPlayed, score, lastTier = false, 0, 1
end)
ArcadeSquashCountRemote.OnClientEvent:Connect(function(_, info)
	score = type(info) == "table" and tonumber(info.score) or score
	if not recordPlayed and best > 0 and score > best then
		recordPlayed = true
		play(SOUNDS.record)
	end
end)
