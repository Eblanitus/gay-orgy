-- Плашка подсказки обучения (задача #298): текущий шаг сверху по центру экрана.
-- Номер шага решает сервер (Tutorial) и кладёт атрибутом TutorialStep на ReplicatedStorage;
-- 0 — плашки нет (не обучение, шаги пройдены или введён промокод test). Текст шага —
-- из TutorialConfig: на телефоне свой, там нет клавиш.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MobileUI = require(script.Parent:WaitForChild("MobileUI"))
local Theme = require(script.Parent:WaitForChild("UITheme"))
local TutorialConfig = require(ReplicatedStorage:WaitForChild("TutorialConfig"))

local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

local gui = Instance.new("ScreenGui")
gui.Name = "TutorialHint"
gui.ResetOnSpawn = false
gui.DisplayOrder = MobileUI.Layer.Controls
gui.Parent = playerGui

local frame = Instance.new("Frame")
frame.AnchorPoint = Vector2.new(0.5, 0)
frame.Position = UDim2.new(0.5, 0, 0, MobileUI.EDGE)
-- Высота растёт под текст: строке шага добавилась метка раздела, и в фиксированные
-- 52 пикселя длинный шаг на три строки уже не встал бы.
frame.Size = UDim2.new(0.5, 0, 0, 0)
frame.AutomaticSize = Enum.AutomaticSize.Y
frame.BorderSizePixel = 0
frame.Visible = false
frame.Parent = gui
-- Плашка языком рамки главного меню (до этого — соты забега, чужие меню).
Theme.Plate(frame)

local constraint = Instance.new("UISizeConstraint")
constraint.MinSize = Vector2.new(280, 52)
constraint.MaxSize = Vector2.new(560, math.huge)
constraint.Parent = frame

local pad = Instance.new("UIPadding")
pad.PaddingTop = UDim.new(0, 14)
pad.PaddingBottom = UDim.new(0, 14)
pad.PaddingLeft = UDim.new(0, 16)
pad.PaddingRight = UDim.new(0, 16)
pad.Parent = frame

-- Строка как подвал меню: «ОБУЧЕНИЕ  //  шаг», по левому краю.
local label = Instance.new("TextLabel")
label.BackgroundTransparency = 1
label.Size = UDim2.new(1, 0, 0, 0)
label.AutomaticSize = Enum.AutomaticSize.Y
label.FontFace = Theme.font.body
label.TextSize = MobileUI.isMobile and 14 or 16
label.TextWrapped = true
label.RichText = true
label.TextXAlignment = Enum.TextXAlignment.Left
label.TextColor3 = Theme.color.text
label.Parent = frame

local function refresh()
	local step = TutorialConfig.steps[ReplicatedStorage:GetAttribute("TutorialStep") or 0]
	local text = step and (MobileUI.isMobile and step.mobile or step.text) or ""
	frame.Visible = text ~= ""
	local shown = Theme.StatusText("обучение", text)
	if text ~= "" and label.Text ~= shown then
		label.Text = shown
		Theme.Blink(label)
	end
end

ReplicatedStorage:GetAttributeChangedSignal("TutorialStep"):Connect(refresh)
refresh()
