-- Подсказка обучения (задача #298): текущий шаг строкой в подвале рамки забега, над
-- строкой стройки (MobileUI.FooterLine), как субтитры: тёмная подложка только под строкой.
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

-- Строка как подвал меню: «ОБУЧЕНИЕ  //  шаг», по центру, шириной по тексту. Длинный
-- шаг переносится и растёт вверх — низ строки стоит на своём месте подвала.
local label = Instance.new("TextLabel")
label.FontFace = Theme.font.body
label.TextSize = MobileUI.isMobile and Theme.MIN_TEXT or 16
label.TextWrapped = true
label.RichText = true
label.TextXAlignment = Enum.TextXAlignment.Center
label.TextColor3 = Theme.color.text
label.Visible = false
label.Parent = gui
-- Тёмная подложка только под строкой (Theme.ArenaBacking), без полосы во всю ширину.
Theme.ArenaBacking(label)

local labelPad = Instance.new("UIPadding")
labelPad.PaddingTop = UDim.new(0, 4)
labelPad.PaddingBottom = UDim.new(0, 4)
labelPad.PaddingLeft = UDim.new(0, 12)
labelPad.PaddingRight = UDim.new(0, 12)
labelPad.Parent = label

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

-- На ПК строка шага стоит выше кнопки «Начать» (третья строка подвала) и потому
-- занимает всю ширину экрана: в узком месте между отступами она переносилась
-- посреди фразы (скрины автора: «…клавиша E у / турели»). На телефоне по краям
-- низа джойстик и прыжок Roblox — там прежние строка и отступы.
if MobileUI.isMobile then
	MobileUI.FooterLine(label, 1)
else
	MobileUI.FooterLine(label, 2, MobileUI.FRAME_INSET + 24)
end

ReplicatedStorage:GetAttributeChangedSignal("TutorialStep"):Connect(refresh)
refresh()
