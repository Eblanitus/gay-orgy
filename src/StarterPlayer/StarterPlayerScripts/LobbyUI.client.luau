-- Панель лобби: только плутоний в левом верхнем углу (alchemy_td_lobby.md, шаг 3).
-- Выбор уровня из этой панели убран — сейчас в игре всего один уровень ("Обучение"),
-- и прибор входа в лобби (WaveRunner.levelEntrancePrompt) сам берёт его по умолчанию,
-- когда ничего не выбрано явно. Полный список уровней и выбор кликом по строке
-- остаются в истории задачи, но сейчас не нужны и только загромождают угол экрана.
--
-- Видима, пока игрок в лобби (по умолчанию, при загрузке скрипта) — прячется, как только
-- забег реально начинается (WaveReady/WaveChanged), появляется снова, когда сервер возвращает
-- в лобби (RunEnded) — то же самое разделение состояний, что у основного HUD (см. Hud), только
-- наоборот.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MobileUI = require(script.Parent:WaitForChild("MobileUI"))
local Theme = require(script.Parent:WaitForChild("UITheme"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "LobbyHud"
screenGui.ResetOnSpawn = false
screenGui.DisplayOrder = MobileUI.Layer.Hud
screenGui.Parent = playerGui

-- Панель размером ровно под иконку плутония — списка уровней под ней больше нет.
local PLUTONIUM_ICON_SIZE = 56
local PANEL_PAD = 10
local PANEL_SIZE = PLUTONIUM_ICON_SIZE + PANEL_PAD * 2

-- Без фона и без канта — только контейнер для позиционирования иконки и её бейджей: чёрный квадрат вокруг плутония был лишним.
local frame = Instance.new("Frame")
frame.Size = UDim2.new(0, PANEL_SIZE, 0, PANEL_SIZE)
frame.Position = UDim2.new(0, 20, 0, 20)
frame.BackgroundTransparency = 1
frame.BorderSizePixel = 0
frame.Parent = screenGui

local padding = Instance.new("UIPadding")
padding.PaddingTop = UDim.new(0, PANEL_PAD)
padding.PaddingLeft = UDim.new(0, PANEL_PAD)
padding.Parent = frame

local plutoniumIcon = Instance.new("ImageLabel")
plutoniumIcon.Size = UDim2.new(0, PLUTONIUM_ICON_SIZE, 0, PLUTONIUM_ICON_SIZE)
plutoniumIcon.BackgroundTransparency = 1
plutoniumIcon.Image = "rbxassetid://106012105470378"
plutoniumIcon.Parent = frame

-- Кнопка-вопрос над иконкой: без подписи непонятно, что за валюта и откуда она берётся — клик
-- открывает карточку с объяснением ниже.
local plutoniumInfoButton = Instance.new("TextButton")
plutoniumInfoButton.Size = UDim2.new(0, 18, 0, 18)
plutoniumInfoButton.AnchorPoint = Vector2.new(0.5, 0.5)
plutoniumInfoButton.Position = UDim2.new(1, 0, 0, 0)
plutoniumInfoButton.FontFace = Theme.font.strong
plutoniumInfoButton.TextSize = 12
plutoniumInfoButton.Text = "?"
plutoniumInfoButton.ZIndex = 2
plutoniumInfoButton.Parent = plutoniumIcon

Theme.Button(plutoniumInfoButton, "ghost")

-- Количество плутония — бейдж в нижнем правом углу иконки, зеркально кнопке-вопросу
-- в верхнем. Ширина автоматическая (AutomaticSize.X) — число растёт со временем, и фиксированная
-- ширина обрезала бы трёхзначные числа.
local plutoniumCountLabel = Instance.new("TextLabel")
plutoniumCountLabel.AutomaticSize = Enum.AutomaticSize.X
plutoniumCountLabel.Size = UDim2.new(0, 0, 0, 20)
plutoniumCountLabel.AnchorPoint = Vector2.new(1, 1)
plutoniumCountLabel.Position = UDim2.new(1, 4, 1, 4)
-- Бейдж валюты собран теми же цветами, что и показания забега в Hud: янтарь в палитре
-- закреплён за считаемым ресурсом — и материей, и плутонием.
plutoniumCountLabel.BackgroundColor3 = Theme.color.panel
plutoniumCountLabel.BackgroundTransparency = 0.05
plutoniumCountLabel.FontFace = Theme.font.strong
plutoniumCountLabel.TextSize = 14
plutoniumCountLabel.TextColor3 = Theme.color.energy
plutoniumCountLabel.Text = "0"
plutoniumCountLabel.ZIndex = 2
plutoniumCountLabel.Parent = plutoniumIcon

local plutoniumCountPadding = Instance.new("UIPadding")
plutoniumCountPadding.PaddingLeft = UDim.new(0, 6)
plutoniumCountPadding.PaddingRight = UDim.new(0, 6)
plutoniumCountPadding.Parent = plutoniumCountLabel

-- Кант в пиксель — как у любой другой плашки нового языка. Здесь он ещё и нужнее,
-- чем где-либо: бейдж висит поверх иконки, а не на фоне панели, и без границы его
-- тёмная заливка сливается с тёмными участками самой иконки.
Theme.Corner(plutoniumCountLabel, Theme.radius.mark)
Theme.Stroke(plutoniumCountLabel, Theme.Shadowed(Theme.color.energy, 0.55), 1, 0)

-- Опыт — бейджем справа от иконки плутония, по её середине: своей иконки у XP нет,
-- поэтому подпись прямо в тексте. Число — data.xp из профиля (ProfileSynced, шестой аргумент).
-- Под иконкой места нет: там с y = 104 стоит кнопка промокода (Hud.promoButton).
-- Отступ 14 — чтобы не задеть кнопку-вопрос и бейдж числа, выступающие за край иконки.
local XP_GAP = 14
local XP_ROW_HEIGHT = 20

local xpLabel = Instance.new("TextLabel")
xpLabel.Name = "XpLabel"
xpLabel.AutomaticSize = Enum.AutomaticSize.X
xpLabel.Size = UDim2.new(0, 0, 0, XP_ROW_HEIGHT)
xpLabel.Position = UDim2.new(0, PLUTONIUM_ICON_SIZE + XP_GAP, 0, (PLUTONIUM_ICON_SIZE - XP_ROW_HEIGHT) / 2)
xpLabel.BackgroundColor3 = Theme.color.panel
xpLabel.BackgroundTransparency = 0.05
xpLabel.FontFace = Theme.font.strong
xpLabel.TextSize = 14
xpLabel.TextColor3 = Theme.color.text
xpLabel.Text = "XP 0"
xpLabel.Parent = frame

local xpPadding = Instance.new("UIPadding")
xpPadding.PaddingLeft = UDim.new(0, 6)
xpPadding.PaddingRight = UDim.new(0, 6)
xpPadding.Parent = xpLabel

Theme.Corner(xpLabel, Theme.radius.mark)
Theme.Stroke(xpLabel, Theme.Shadowed(Theme.color.text, 0.55), 1, 0)

-- Карточка описания: сначала игровое назначение валюты, потом научная справка по элементу.
-- Свой ScreenGui на слое Notify (200), а не внутри screenGui (Hud, 10): на телефоне панель стройки
-- (BuildControls, слой Controls = 20) иначе легла бы поверх карточки, как любой слой старше Hud.
local plutoniumInfoGui = Instance.new("ScreenGui")
plutoniumInfoGui.Name = "PlutoniumInfo"
plutoniumInfoGui.ResetOnSpawn = false
plutoniumInfoGui.DisplayOrder = MobileUI.Layer.Notify
plutoniumInfoGui.Parent = playerGui

local plutoniumInfoFrame = Instance.new("Frame")
plutoniumInfoFrame.Size = UDim2.new(0, 280, 0, 0)
plutoniumInfoFrame.AutomaticSize = Enum.AutomaticSize.Y
plutoniumInfoFrame.BorderSizePixel = 0
plutoniumInfoFrame.Visible = false
plutoniumInfoFrame.Parent = plutoniumInfoGui

local plutoniumInfoPadding = Instance.new("UIPadding")
plutoniumInfoPadding.PaddingTop = UDim.new(0, 12)
plutoniumInfoPadding.PaddingBottom = UDim.new(0, 12)
plutoniumInfoPadding.PaddingLeft = UDim.new(0, 14)
plutoniumInfoPadding.PaddingRight = UDim.new(0, 14)
plutoniumInfoPadding.Parent = plutoniumInfoFrame

Theme.Panel(plutoniumInfoFrame, { scene = "dialog" })

local plutoniumInfoLabel = Instance.new("TextLabel")
plutoniumInfoLabel.Size = UDim2.new(1, 0, 0, 0)
plutoniumInfoLabel.AutomaticSize = Enum.AutomaticSize.Y
plutoniumInfoLabel.BackgroundTransparency = 1
plutoniumInfoLabel.FontFace = Theme.font.body
plutoniumInfoLabel.TextSize = 14
plutoniumInfoLabel.TextWrapped = true
plutoniumInfoLabel.TextXAlignment = Enum.TextXAlignment.Left
plutoniumInfoLabel.TextYAlignment = Enum.TextYAlignment.Top
plutoniumInfoLabel.TextColor3 = Theme.color.text
plutoniumInfoLabel.Text = "Плутоний — валюта, предназначенная для косметики. Выдаётся после матчей.\n\nПлутоний (Pu, атомный номер 94) — трансурановый радиоактивный металл. В чистом виде серебристо-белый, но на воздухе быстро темнеет и покрывается серо-жёлтой оксидной плёнкой. В природе в значимых количествах не встречается — нарабатывается в ядерных реакторах из урана-238. Изотоп плутоний-239 способен к цепной реакции деления и применяется в ядерном оружии и реакторах, а плутоний-238 служит источником тепла для радиоизотопных генераторов, например на космических зондах."
plutoniumInfoLabel.Parent = plutoniumInfoFrame

plutoniumInfoButton.MouseButton1Click:Connect(function()
	-- Позиция считается на каждый клик, а не один раз при создании: панель могла
	-- сдвинуться (например, на телефоне после поворота экрана).
	plutoniumInfoFrame.Position = UDim2.new(
		0, frame.AbsolutePosition.X,
		0, frame.AbsolutePosition.Y + frame.AbsoluteSize.Y + 10
	)
	plutoniumInfoFrame.Visible = not plutoniumInfoFrame.Visible
	if plutoniumInfoFrame.Visible then
		Theme.Open(plutoniumInfoFrame)
	end
end)

Remotes.ProfileSynced.OnClientEvent:Connect(function(plutonium, _levels, _recipes, _killedTypes, _settings, xp)
	plutoniumCountLabel.Text = tostring(plutonium)
	xpLabel.Text = ("XP %d"):format(xp or 0)
end)

local function hide()
	screenGui.Enabled = false
	plutoniumInfoFrame.Visible = false
end

local function show()
	screenGui.Enabled = true
end

Remotes.WaveReady.OnClientEvent:Connect(hide)
Remotes.WaveChanged.OnClientEvent:Connect(hide)
Remotes.RunEnded.OnClientEvent:Connect(show)
