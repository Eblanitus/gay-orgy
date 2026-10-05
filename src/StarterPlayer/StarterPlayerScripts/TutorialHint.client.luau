-- Подсказка обучения (задача #298): текущий шаг строкой в подвале рамки забега, над
-- строкой стройки (MobileUI.FooterLine). Плашки нет: в рамке забега текст лежит прямо
-- на арене под тенью от края экрана (Hud), как субтитры.
-- Номер шага решает сервер (Tutorial) и кладёт атрибутом TutorialStep на ReplicatedStorage;
-- 0 — строки нет (не обучение, шаги пройдены или введён промокод test). Текст шага —
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

-- Строка как подвал меню: «ОБУЧЕНИЕ  //  шаг», по центру. Длинный шаг переносится
-- и растёт вверх — низ строки стоит на своём месте подвала.
local label = Instance.new("TextLabel")
MobileUI.FooterLine(label, 1)
label.FontFace = Theme.font.body
label.TextSize = MobileUI.isMobile and Theme.MIN_TEXT or 16
label.TextWrapped = true
label.RichText = true
label.TextXAlignment = Enum.TextXAlignment.Center
label.TextColor3 = Theme.color.text
label.Visible = false
label.Parent = gui
Theme.ArenaLabel(label)

local function refresh()
	local step = TutorialConfig.steps[ReplicatedStorage:GetAttribute("TutorialStep") or 0]
	local text = step and (MobileUI.isMobile and step.mobile or step.text) or ""
	label.Visible = text ~= ""
	local shown = Theme.ArenaText("обучение", Theme.Escape(text))
	if text ~= "" and label.Text ~= shown then
		label.Text = shown
		Theme.Blink(label)
	end
end

ReplicatedStorage:GetAttributeChangedSignal("TutorialStep"):Connect(refresh)
refresh()
