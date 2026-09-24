-- Конструктор волн: игрок выбирает, какие жуки пойдут в следующей волне и сколько их.
-- Открывается промокодом WAVE — до этого кнопки нет вовсе.
--
-- Клиент здесь только собирает намерение и шлёт его серверу: ни список видов, ни
-- потолки он не выдумывает — всё приходит в WaveEditorState с сервера, и он же перепроверяет
-- всё заново в момент применения (см. WaveEditor.Set).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MobileUI = require(script.Parent:WaitForChild("MobileUI"))
local Theme = require(script.Parent:WaitForChild("UITheme"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local WaveEditorState = Remotes:WaitForChild("WaveEditorState")
local RequestSetWave = Remotes:WaitForChild("RequestSetWave")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local CASTE_NAMES = {
	[0] = "Каста 0 — Разведчики",
	[1] = "Каста 1 — Работяги",
	[2] = "Каста 2 — Солдаты",
	[3] = "Каста 3 — Особые",
}

local ROW_H = 30
local HEADER_H = 24

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "WaveEditorHud"
screenGui.ResetOnSpawn = false
screenGui.DisplayOrder = MobileUI.Layer.Window
screenGui.Enabled = false -- пока конструктор не открыт промокодом, его нет совсем
screenGui.Parent = playerGui

-- Кнопка-переключатель — третьей в правом столбце, под инвентарём и меню. В одну
-- строку с кнопкой инвентаря конструктор её накрывал (видно на скриншоте:
-- «ИНВЕ» обрезалось кнопкой «Волна»), а прежние y = 60 легли бы на кнопку меню.
local toggle = Instance.new("TextButton")
toggle.Name = "WaveEditorToggle"
MobileUI.TopRight(toggle, MobileUI.CornerSlot.WaveEditor)
toggle.FontFace = Theme.font.strong
toggle.TextSize = 14
toggle.Text = "Волна"
toggle.Parent = screenGui
Theme.Button(toggle, "ghost")

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.new(0.5, 0, 0.5, 0)
panel.Size = UDim2.new(0, 420, 0, 460)
panel.Visible = false
panel.Parent = screenGui
Theme.Panel(panel, { scene = "editor" })

local pad = Instance.new("UIPadding")
pad.PaddingTop = UDim.new(0, 12)
pad.PaddingBottom = UDim.new(0, 12)
pad.PaddingLeft = UDim.new(0, 12)
pad.PaddingRight = UDim.new(0, 12)
pad.Parent = panel

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -70, 0, 22)
title.BackgroundTransparency = 1
title.FontFace = Theme.font.strong
title.TextSize = 16
title.TextColor3 = Theme.color.text
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = "Конструктор волны"
title.Parent = panel

local closeButton = Instance.new("TextButton")
closeButton.Size = UDim2.new(0, 26, 0, 22)
closeButton.AnchorPoint = Vector2.new(1, 0)
closeButton.Position = UDim2.new(1, 0, 0, 0)
closeButton.Parent = panel
-- Крестик нарисован двумя линиями (Theme.CloseButton): знака ✕ в наборе шрифта темы
-- нет, он рисовался пустым прямоугольником, а латинская X выбивалась из терминала.
Theme.CloseButton(closeButton)

local hint = Instance.new("TextLabel")
hint.Position = UDim2.new(0, 0, 0, 26)
hint.Size = UDim2.new(1, 0, 0, 16)
hint.BackgroundTransparency = 1
hint.FontFace = Theme.font.body
hint.TextSize = 12
hint.TextColor3 = Theme.color.textDim
hint.TextXAlignment = Enum.TextXAlignment.Left
hint.Text = "Наберите состав и нажмите «Применить»"
hint.Parent = panel

local scroll = Instance.new("ScrollingFrame")
scroll.Position = UDim2.new(0, 0, 0, 48)
scroll.Size = UDim2.new(1, 0, 1, -92)
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel = 0
scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.ScrollBarThickness = 4
scroll.Parent = panel
Theme.Scroller(scroll)
Theme.DragScroll(scroll)

local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 3)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = scroll

local footer = Instance.new("Frame")
footer.AnchorPoint = Vector2.new(0, 1)
footer.Position = UDim2.new(0, 0, 1, 0)
footer.Size = UDim2.new(1, 0, 0, 36)
footer.BackgroundTransparency = 1
footer.Parent = panel

local totalLabel = Instance.new("TextLabel")
totalLabel.Size = UDim2.new(0.36, 0, 1, 0)
totalLabel.BackgroundTransparency = 1
totalLabel.FontFace = Theme.font.strong
totalLabel.TextSize = 13
totalLabel.TextColor3 = Theme.color.textDim
totalLabel.TextXAlignment = Enum.TextXAlignment.Left
totalLabel.Text = ""
totalLabel.Parent = footer

local resetButton = Instance.new("TextButton")
resetButton.Size = UDim2.new(0.28, -4, 1, 0)
resetButton.Position = UDim2.new(0.36, 0, 0, 0)
resetButton.FontFace = Theme.font.strong
resetButton.TextSize = 13
resetButton.Text = "Сбросить"
resetButton.Parent = footer
Theme.Button(resetButton, "quiet")

local applyButton = Instance.new("TextButton")
applyButton.Size = UDim2.new(0.36, 0, 1, 0)
applyButton.Position = UDim2.new(0.64, 0, 0, 0)
applyButton.FontFace = Theme.font.strong
applyButton.TextSize = 13
applyButton.Text = "Применить"
applyButton.Parent = footer
Theme.Button(applyButton, "action")

-- Сколько чего набрано: ключ вида -> число. Живёт только на клиенте и ничего
-- не решает: правда — та, что принял сервер.
local counts = {}
local rows = {}
local limits = { perType = 50, total = 150 }

local function total()
	local sum = 0
	for _, n in counts do
		sum += n
	end
	return sum
end

local function refreshTotals()
	local sum = total()
	totalLabel.Text = ("Всего: %d / %d"):format(sum, limits.total)
	totalLabel.TextColor3 = sum > limits.total and Theme.color.danger or Theme.color.textDim
end

local function setCount(key, value)
	value = math.clamp(math.floor(value or 0), 0, limits.perType)
	counts[key] = value
	local row = rows[key]
	if row then
		row.box.Text = tostring(value)
		-- Набранный вид виден сразу: в списке под тридцать строк иначе не найти,
		-- что ты уже заказал.
		row.name.TextColor3 = value > 0 and Theme.color.accent or Theme.color.text
	end
	refreshTotals()
end

local function clearRows()
	for _, child in scroll:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	table.clear(rows)
end

local function addHeader(text, order)
	local label = Instance.new("TextLabel")
	label.LayoutOrder = order
	label.Size = UDim2.new(1, 0, 0, HEADER_H)
	label.BackgroundTransparency = 1
	label.FontFace = Theme.font.strong
	label.TextSize = 12
	label.TextColor3 = Theme.color.accentDim
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Bottom
	label.Text = text
	label.Parent = scroll
end

local function addRow(entry, order)
	local row = Instance.new("Frame")
	row.LayoutOrder = order
	row.Size = UDim2.new(1, 0, 0, ROW_H)
	row.BackgroundColor3 = Theme.color.row
	row.BackgroundTransparency = 0.35
	row.BorderSizePixel = 0
	row.Parent = scroll
	Theme.Corner(row, Theme.radius.control)

	local name = Instance.new("TextLabel")
	name.Size = UDim2.new(1, -132, 1, 0)
	name.Position = UDim2.new(0, 8, 0, 0)
	name.BackgroundTransparency = 1
	name.FontFace = Theme.font.body
	name.TextSize = 13
	name.TextColor3 = Theme.color.text
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.Text = entry.name
	name.Parent = row

	local function stepper(text, dx, delta)
		local b = Instance.new("TextButton")
		b.Size = UDim2.new(0, 26, 0, 22)
		b.AnchorPoint = Vector2.new(1, 0.5)
		b.Position = UDim2.new(1, dx, 0.5, 0)
		b.FontFace = Theme.font.strong
		b.TextSize = 14
		b.Text = text
		b.Parent = row
		Theme.Button(b, "ghost")
		b.Activated:Connect(function()
			setCount(entry.key, (counts[entry.key] or 0) + delta)
		end)
		return b
	end

	stepper("+", -6, 1)

	local box = Instance.new("TextBox")
	box.Size = UDim2.new(0, 40, 0, 22)
	box.AnchorPoint = Vector2.new(1, 0.5)
	box.Position = UDim2.new(1, -36, 0.5, 0)
	box.FontFace = Theme.font.strong
	box.TextSize = 13
	box.TextColor3 = Theme.color.text
	box.BackgroundColor3 = Theme.color.field
	box.BorderSizePixel = 0
	box.ClearTextOnFocus = false
	box.Text = "0"
	box.Parent = row
	Theme.Corner(box, Theme.radius.control)

	-- Число можно ввести руками: дощёлкивать до пятидесяти по одному — мучение,
	-- а на телефоне ещё и промахи.
	box.FocusLost:Connect(function()
		setCount(entry.key, tonumber(box.Text) or 0)
	end)

	stepper("−", -82, -1)

	rows[entry.key] = { name = name, box = box }
end

local function rebuild(state)
	clearRows()
	table.clear(counts)

	local order, lastCaste = 0, nil
	for _, entry in ipairs(state.roster or {}) do
		if entry.caste ~= lastCaste then
			lastCaste = entry.caste
			order += 1
			addHeader(CASTE_NAMES[entry.caste] or ("Каста " .. tostring(entry.caste)), order)
		end
		order += 1
		addRow(entry, order)
		counts[entry.key] = 0
	end

	-- То, что уже заказано на сервере, подставляется в поля: панель открывается
	-- не пустой, а с тем составом, который реально пойдёт.
	for _, g in ipairs(state.current or {}) do
		setCount(g.enemyType, g.count)
	end
	refreshTotals()
end

WaveEditorState.OnClientEvent:Connect(function(state)
	limits.perType = state.maxPerType or limits.perType
	limits.total = state.maxTotal or limits.total
	screenGui.Enabled = state.unlocked == true
	if not state.unlocked then
		panel.Visible = false
		return
	end
	rebuild(state)
end)

toggle.Activated:Connect(function()
	panel.Visible = not panel.Visible
	Theme.Button(toggle, panel.Visible and "active" or "ghost")
end)

closeButton.Activated:Connect(function()
	panel.Visible = false
	Theme.Button(toggle, "ghost")
end)

resetButton.Activated:Connect(function()
	for key in counts do
		setCount(key, 0)
	end
	-- Пустой состав сервер понимает как «верни как было» (см. WaveEditor.Set).
	RequestSetWave:FireServer({})
end)

applyButton.Activated:Connect(function()
	local groups = {}
	for key, n in counts do
		if n > 0 then
			table.insert(groups, { enemyType = key, count = n })
		end
	end
	RequestSetWave:FireServer(groups)
end)

refreshTotals()
