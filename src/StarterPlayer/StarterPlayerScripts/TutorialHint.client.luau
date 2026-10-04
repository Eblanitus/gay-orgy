-- Плашка подсказки обучения (задача #298): текущий шаг сверху по центру экрана.
-- Текст решает сервер (Tutorial) и кладёт атрибутом TutorialHint на ReplicatedStorage;
-- пустая строка — плашки нет (не обучение, шаги пройдены или введён промокод test).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MobileUI = require(script.Parent:WaitForChild("MobileUI"))
local Theme = require(script.Parent:WaitForChild("UITheme"))

local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

local gui = Instance.new("ScreenGui")
gui.Name = "TutorialHint"
gui.ResetOnSpawn = false
gui.DisplayOrder = MobileUI.Layer.Controls
gui.Parent = playerGui

local frame = Instance.new("Frame")
frame.AnchorPoint = Vector2.new(0.5, 0)
frame.Position = UDim2.new(0.5, 0, 0, MobileUI.EDGE)
frame.Size = UDim2.new(0.5, 0, 0, 52)
frame.BorderSizePixel = 0
frame.Visible = false
frame.Parent = gui
Theme.Panel(frame, { scene = "run" })

local constraint = Instance.new("UISizeConstraint")
constraint.MinSize = Vector2.new(280, 0)
constraint.MaxSize = Vector2.new(560, math.huge)
constraint.Parent = frame

local label = Instance.new("TextLabel")
label.BackgroundTransparency = 1
label.Position = UDim2.new(0, 14, 0, 0)
label.Size = UDim2.new(1, -28, 1, 0)
label.FontFace = Theme.font.strong
label.TextSize = MobileUI.isMobile and 14 or 16
label.TextWrapped = true
label.TextColor3 = Theme.color.text
label.Parent = frame

local function refresh()
	local text = ReplicatedStorage:GetAttribute("TutorialHint") or ""
	frame.Visible = text ~= ""
	if text ~= "" and label.Text ~= text then
		label.Text = text
		Theme.Blink(label)
	end
end

ReplicatedStorage:GetAttributeChangedSignal("TutorialHint"):Connect(refresh)
refresh()
