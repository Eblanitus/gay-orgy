-- Splash — заставка во весь экран: начало уровня, начало волны, победа, поражение
-- (просьба автора). Экран темнеет, по центру надпись, через пару секунд она уходит сама
-- и экран светлеет. Нажатий не держит: волна уже идёт, строить можно и под заставкой.
--
-- Своих remote'ов нет — те же события, по которым живёт Hud: WaveReady (первый в забеге —
-- начало уровня), WaveChanged (волна вышла), RunEnded (итог). Баннер итога в Hud остаётся
-- как был: заставка гаснет, а он висит над лобби до следующего забега.
--
-- При снятой настройке «Движение интерфейса» (uiMotion) затемнение и надпись появляются
-- и пропадают сразу, без плавности, но показываются всё равно.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local MobileUI = require(script.Parent:WaitForChild("MobileUI"))
local Theme = require(script.Parent:WaitForChild("UITheme"))
local Settings = require(script.Parent:WaitForChild("Settings"))
local Levels = require(ReplicatedStorage:WaitForChild("Levels"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

local SPLASH = {
	shade = 0.25, -- прозрачность затемнения: 75% чёрного, бирюза и белый на нём читаются
	fadeIn = 0.35, -- секунды
	hold = 1.6, -- секунды надпись стоит
	fadeOut = 0.6,
	title = MobileUI.isMobile and 44 or 72,
	caption = MobileUI.isMobile and 18 or 22,
	note = MobileUI.isMobile and 16 or 20,
}

local gui = Instance.new("ScreenGui")
gui.Name = "Splash"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true -- темнеет и полоса Roblox сверху: «весь экран»
gui.DisplayOrder = MobileUI.Layer.Splash
gui.Enabled = false
gui.Parent = playerGui

local shade = Instance.new("Frame")
shade.Name = "Shade"
shade.Size = UDim2.fromScale(1, 1)
shade.BackgroundColor3 = Color3.new(0, 0, 0)
shade.BackgroundTransparency = 1
shade.BorderSizePixel = 0
shade.Active = false
shade.Interactable = false
shade.Parent = gui

local column = Instance.new("Frame")
column.Name = "Column"
column.AnchorPoint = Vector2.new(0.5, 0.5)
column.Position = UDim2.fromScale(0.5, 0.5)
column.Size = UDim2.new(0.9, 0, 0, 0)
column.AutomaticSize = Enum.AutomaticSize.Y
column.BackgroundTransparency = 1
column.Parent = shade

local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Vertical
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Padding = UDim.new(0, 8)
layout.Parent = column

local function makeLabel(order, size, font)
	local label = Instance.new("TextLabel")
	label.LayoutOrder = order
	label.Size = UDim2.fromScale(1, 0)
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.BackgroundTransparency = 1
	label.TextWrapped = true
	label.TextSize = math.max(size, Theme.MIN_TEXT)
	label.FontFace = font
	label.TextTransparency = 1
	label.TextStrokeColor3 = Theme.color.ink
	label.TextStrokeTransparency = 1
	label.Text = ""
	label.Parent = column
	return label
end

-- Подпись сверху — что это (раздел), слово — само событие, строка ниже — подробность.
local caption = makeLabel(1, SPLASH.caption, Theme.font.strong)
local title = makeLabel(2, SPLASH.title, Theme.font.strong)
Theme.Display(title)
local note = makeLabel(3, SPLASH.note, Theme.font.body)

-- Черта под словом — тот же цвет, что у подписи.
local rule = Instance.new("Frame")
rule.LayoutOrder = 4
rule.Size = UDim2.fromOffset(MobileUI.isMobile and 120 or 180, 2)
rule.BorderSizePixel = 0
rule.BackgroundTransparency = 1
rule.Parent = column

-- Сколько заставок показано: новая обрывает прежнюю, и её таймер ничего уже не прячет.
local generation = 0
local tweens = {}

local function stopTweens()
	for _, tween in tweens do
		tween:Cancel()
	end
	tweens = {}
end

-- Прозрачность всего разом: alpha 0 — заставки нет, 1 — видна целиком.
local function targets(alpha)
	local text = 1 - alpha
	return {
		[shade] = { BackgroundTransparency = 1 - alpha * (1 - SPLASH.shade) },
		[caption] = { TextTransparency = text },
		[title] = { TextTransparency = text, TextStrokeTransparency = 1 - alpha * 0.5 },
		[note] = { TextTransparency = text },
		[rule] = { BackgroundTransparency = text },
	}
end

local function apply(alpha, seconds)
	stopTweens()
	local motion = Settings.Get("uiMotion")
	for inst, props in targets(alpha) do
		if motion and seconds > 0 then
			local tween = TweenService:Create(inst, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props)
			table.insert(tweens, tween)
			tween:Play()
		else
			for key, value in props do
				inst[key] = value
			end
		end
	end
end

-- tone — цвет подписи и черты (бирюза для начала, зелёный/красный для итога).
local function show(captionText, titleText, noteText, tone, titleColor)
	generation += 1
	local mine = generation

	caption.Text = captionText
	caption.TextColor3 = tone
	title.Text = titleText
	title.TextColor3 = titleColor or Theme.color.text
	note.Text = noteText or ""
	note.Visible = noteText ~= nil
	note.TextColor3 = Theme.color.textDim
	rule.BackgroundColor3 = tone

	gui.Enabled = true
	apply(1, SPLASH.fadeIn)

	task.delay(SPLASH.fadeIn + SPLASH.hold, function()
		if generation ~= mine then
			return
		end
		local motion = Settings.Get("uiMotion")
		apply(0, SPLASH.fadeOut)
		task.delay(motion and SPLASH.fadeOut or 0, function()
			if generation == mine then
				gui.Enabled = false
			end
		end)
	end)
end

-- Идёт ли забег на этом клиенте: первый WaveReady вне забега — начало уровня, а повторные
-- (досылка серверу после отказа обучения, ожидание следующей волны) — нет.
local inRun = false

local function wavesWord(count)
	local tail = count % 100
	if tail >= 11 and tail <= 14 then
		return "волн"
	end
	tail = count % 10
	if tail == 1 then
		return "волна"
	elseif tail >= 2 and tail <= 4 then
		return "волны"
	end
	return "волн"
end

Remotes:WaitForChild("WaveReady").OnClientEvent:Connect(function(_waveNumber, totalWaves)
	if inRun then
		return
	end
	inRun = true
	local levelNumber = ReplicatedStorage:GetAttribute("RunLevel")
	local level = typeof(levelNumber) == "number" and Levels[levelNumber]
	local titleText = level and ("УРОВЕНЬ %d"):format(levelNumber) or "УРОВЕНЬ"
	local parts = {}
	if level and level.name then
		table.insert(parts, ("«%s»"):format(level.name))
	end
	if typeof(totalWaves) == "number" then
		table.insert(parts, ("%d %s"):format(totalWaves, wavesWord(totalWaves)))
	end
	show("НАЧАЛО УРОВНЯ", titleText, #parts > 0 and table.concat(parts, " · ") or nil, Theme.color.accent)
end)

Remotes:WaitForChild("WaveChanged").OnClientEvent:Connect(function(waveNumber, totalWaves)
	inRun = true
	local titleText = typeof(totalWaves) == "number" and ("ВОЛНА %d/%d"):format(waveNumber, totalWaves)
		or ("ВОЛНА %d"):format(waveNumber)
	local last = typeof(totalWaves) == "number" and waveNumber == totalWaves
	show("НАЧАЛО ВОЛНЫ", titleText, last and "последняя волна" or nil, Theme.color.accent)
end)

Remotes:WaitForChild("RunEnded").OnClientEvent:Connect(function(won)
	inRun = false
	local tone = won and Theme.color.action or Theme.color.danger
	show(
		"ЗАБЕГ ОКОНЧЕН",
		won and "ПОБЕДА" or "ПОРАЖЕНИЕ",
		won and "лаборатория выстояла" or "лаборатория прорвана",
		tone,
		Theme.Legible(tone)
	)
end)
