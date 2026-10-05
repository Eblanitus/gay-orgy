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
MobileUI.FooterLine(label, 1)
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

-- Пока обучение держит волну (TutorialWaveLocked), кнопки «Начать» справа внизу нет,
-- и строке шага место не нужно уступать: на всю ширину рамки она не переносится
-- посреди фразы (скрин автора: «…клавиша E у / турели»).
local function fitWidth()
	-- На телефоне по краям низа — джойстик и прыжок Roblox, там отступ остаётся всегда.
	local locked = ReplicatedStorage:GetAttribute("TutorialWaveLocked") == true and not MobileUI.isMobile
	MobileUI.FooterLine(label, 1, locked and (MobileUI.FRAME_INSET + 24) or MobileUI.FOOTER_SIDE)
end

ReplicatedStorage:GetAttributeChangedSignal("TutorialWaveLocked"):Connect(fitWidth)
fitWidth()

ReplicatedStorage:GetAttributeChangedSignal("TutorialStep"):Connect(refresh)
refresh()
