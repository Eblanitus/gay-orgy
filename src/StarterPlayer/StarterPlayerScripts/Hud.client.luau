-- Экранный HUD забега: рамка по краю экрана с шапкой (волна, материя, прочность стола),
-- журнал сообщений сервера и кнопка вызова волны. Состояние только на сервере,
-- этот скрипт лишь отображает то, что пришло через RemoteEvent.
--
-- ВИД (переработка по макету, согласованному с автором): тот же язык, что у рамки
-- главного меню, — кант в пиксель с отступом от края экрана, уголки-скобки, шапка
-- и подвал под чертой. Но без чёрных плашек: показания и подсказки лежат прямо на арене,
-- а читаемость держит тень от края экрана (тёмный градиент сверху и снизу). Рамка —
-- только у того, что нажимается (кнопки меню и волны): у показаний её нет, чтобы их
-- не принимали за кнопки (замечание автора). Текст на арене белый, бирюза — только
-- у кнопок и полосок: на светлой арене бирюзовый текст не читался.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local MobileUI = require(script.Parent:WaitForChild("MobileUI"))
local Theme = require(script.Parent:WaitForChild("UITheme"))
local Levels = require(ReplicatedStorage:WaitForChild("Levels"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local mobile = MobileUI.isMobile

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "GameHud"
screenGui.ResetOnSpawn = false
screenGui.DisplayOrder = MobileUI.Layer.Hud
screenGui.Parent = playerGui

-- Итог забега живёт отдельным ScreenGui поверх окон, а не вместе с остальным HUD:
-- победу и поражение надо видеть, даже если в этот момент открыта Лаборатория.
local resultGui = Instance.new("ScreenGui")
resultGui.Name = "GameResult"
resultGui.ResetOnSpawn = false
resultGui.DisplayOrder = MobileUI.Layer.Notify
resultGui.Parent = playerGui

-- ============ Рамка забега ============

local INSET = MobileUI.FRAME_INSET

-- Линий по экрану нет (просьба автора): ни канта рамки, ни уголков, ни черт.
-- Читаемость держит плавная тень от верхнего и нижнего края экрана, а сами надписи
-- лежат на своих подложках. frame — пустой контейнер забега: по нему считаются
-- отступы журнала и кнопки волны.
local frame = Instance.new("Frame")
frame.Name = "RunFrame"
frame.Position = UDim2.fromOffset(INSET, INSET)
frame.Size = UDim2.new(1, -2 * INSET, 1, -2 * INSET)
frame.BackgroundTransparency = 1
frame.BorderSizePixel = 0
frame.Visible = false
frame.Parent = screenGui

-- Тени — в своём ScreenGui во весь экран, ВКЛЮЧАЯ полосу Roblox сверху (IgnoreGuiInset):
-- кнопки Roblox и шапка забега лежат в одной темноте, без светлой щели между ними.
-- Слой на единицу ниже HUD.
local shadeGui = Instance.new("ScreenGui")
shadeGui.Name = "GameHudShade"
shadeGui.ResetOnSpawn = false
shadeGui.IgnoreGuiInset = true
shadeGui.DisplayOrder = MobileUI.Layer.Hud - 1
shadeGui.Enabled = false
shadeGui.Parent = playerGui

local function edgeShade(top)
	local shade = Instance.new("Frame")
	shade.Name = top and "ShadeTop" or "ShadeBottom"
	shade.AnchorPoint = Vector2.new(0, top and 0 or 1)
	shade.Position = UDim2.fromScale(0, top and 0 or 1)
	shade.BackgroundColor3 = Theme.color.ink
	shade.BackgroundTransparency = 0
	shade.BorderSizePixel = 0
	shade.Parent = shadeGui

	local fade = Instance.new("UIGradient")
	fade.Rotation = top and 90 or -90
	-- Плавный спад без ступеньки: плотная полоса с видимым краем резала светлую арену.
	fade.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.25),
		NumberSequenceKeypoint.new(0.3, 0.45),
		NumberSequenceKeypoint.new(0.65, 0.8),
		NumberSequenceKeypoint.new(1, 1),
	})
	fade.Parent = shade
	return shade
end

local shadeTop = edgeShade(true)
-- Подвал: строки подсказок, кнопка волны на ПК и запас под спад.
local shadeBottom = edgeShade(false)
shadeBottom.Size = UDim2.new(1, 0, 0, MobileUI.FOOTER_BOTTOM + 3 * MobileUI.FOOTER_LINE + (mobile and 50 or 90))

-- Высота верхней тени — от верха экрана: полоса Roblox с шапкой и запас на спад.
local function fitShade()
	shadeTop.Size = UDim2.new(1, 0, 0, MobileUI.Topbar.height + (mobile and 60 or 100))
end
MobileUI.OnViewportChanged(fitShade)

-- ============ Шапка в полосе Roblox ============

-- Шапка стоит на самом верху экрана, на одной линии с кнопками Roblox, а не под ними
-- (просьба автора): своя ScreenGui с IgnoreGuiInset, место — свободная часть полосы
-- Roblox (MobileUI.Topbar). Слева «> ЗАБЕГ» сразу за кнопками Roblox, по центру
-- показания. На телефоне полоса узкая — там только показания.
local headerGui = Instance.new("ScreenGui")
headerGui.Name = "GameHudHeader"
headerGui.ResetOnSpawn = false
headerGui.IgnoreGuiInset = true
headerGui.DisplayOrder = MobileUI.Layer.Hud
headerGui.Enabled = false
headerGui.Parent = playerGui

local PILL_H = 44
local PILL_GAP = 12

local function pill(name)
	local plate = Instance.new("Frame")
	plate.Name = name
	plate.Parent = headerGui
	Theme.ArenaBacking(plate)
	return plate
end

-- ---- Где игрок ----

local titlePill = pill("Title")
titlePill.Size = UDim2.fromOffset(0, PILL_H)
titlePill.AutomaticSize = Enum.AutomaticSize.X
titlePill.Visible = not mobile

local titlePad = Instance.new("UIPadding")
titlePad.PaddingLeft = UDim.new(0, 12)
titlePad.PaddingRight = UDim.new(0, 12)
titlePad.Parent = titlePill

local titleList = Instance.new("UIListLayout")
titleList.SortOrder = Enum.SortOrder.LayoutOrder
titleList.VerticalAlignment = Enum.VerticalAlignment.Center
titleList.Parent = titlePill

local titleLabel = Instance.new("TextLabel")
titleLabel.LayoutOrder = 1
titleLabel.Size = UDim2.fromOffset(0, 20)
titleLabel.AutomaticSize = Enum.AutomaticSize.X
titleLabel.TextSize = 18
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.Text = Theme.Caps("забег")
titleLabel.BackgroundTransparency = 1
titleLabel.Parent = titlePill
Theme.Title(titleLabel)

local levelLabel = Instance.new("TextLabel")
levelLabel.LayoutOrder = 2
levelLabel.Size = UDim2.fromOffset(0, 18)
levelLabel.AutomaticSize = Enum.AutomaticSize.X
levelLabel.BackgroundTransparency = 1
levelLabel.FontFace = Theme.font.body
levelLabel.TextSize = 15
levelLabel.TextXAlignment = Enum.TextXAlignment.Left
levelLabel.TextColor3 = Theme.color.textDim
levelLabel.Text = ""
levelLabel.Parent = titlePill

-- Номер уровня кладёт сервер атрибутом RunLevel (WaveRunner.startRun).
local function updateLevel()
	local number = ReplicatedStorage:GetAttribute("RunLevel")
	local level = typeof(number) == "number" and Levels[number]
	levelLabel.Text = level and ("УРОВЕНЬ %d · %s"):format(number, Theme.Caps(level.name)) or ""
	levelLabel.Visible = level ~= nil and level ~= false
end
ReplicatedStorage:GetAttributeChangedSignal("RunLevel"):Connect(updateLevel)
updateLevel()

-- ---- Показания ----

-- Три показания одной плашкой: волна посередине, материя слева от неё (прижата
-- вправо), прочность справа (прижата влево). Подпись сверху, число под ней.
-- Плашка не нажимается — у неё нет канта, как у кнопок.
local GROUP_W = mobile and 300 or 420
local WAVE_W = mobile and 110 or 140
local SIDE_W = mobile and 80 or 110
local SIDE_GAP = mobile and 65 or 80 -- от центра до ближнего края бокового показания

local readouts = pill("Readouts")
readouts.AnchorPoint = Vector2.new(0.5, 0)
readouts.Size = UDim2.fromOffset(GROUP_W, PILL_H)

local CAPTION_Y = 2
local VALUE_Y = 18

local function makeStat(caption, x, width, align, valueSize)
	local cap = Instance.new("TextLabel")
	cap.Position = UDim2.fromOffset(x, CAPTION_Y)
	cap.Size = UDim2.fromOffset(width, 16)
	cap.TextSize = Theme.MIN_TEXT
	cap.Text = Theme.Caps(caption)
	cap.Parent = readouts
	Theme.StatCaption(cap)
	cap.TextColor3 = Theme.color.textDim
	cap.TextXAlignment = align

	local value = Instance.new("TextLabel")
	value.Position = UDim2.fromOffset(x, VALUE_Y)
	value.Size = UDim2.fromOffset(width, valueSize + 2)
	value.BackgroundTransparency = 1
	value.TextSize = valueSize
	value.TextColor3 = Theme.color.text
	value.TextXAlignment = align
	value.TextTruncate = Enum.TextTruncate.AtEnd
	value.Parent = readouts
	-- Приборный шрифт только у числа: подпись живёт обычным начертанием (Theme.StatCaption).
	Theme.Display(value)
	return value, cap
end

local center = GROUP_W / 2
local valueSize = mobile and 18 or 20

local matterLabel = makeStat("материя", center - SIDE_GAP - SIDE_W, SIDE_W, Enum.TextXAlignment.Right, valueSize)
matterLabel.Text = "0"
matterLabel.TextColor3 = Theme.color.energy

local waveLabel = makeStat("волна", center - WAVE_W / 2, WAVE_W, Enum.TextXAlignment.Center, valueSize)
waveLabel.Text = "- / -"

local hpLabel, hpCaption = makeStat("прочность", center + SIDE_GAP, SIDE_W, Enum.TextXAlignment.Left, valueSize)
hpLabel.Text = "-"

-- Подпись «ПРОЧНОСТЬ» красится слева направо как шкала: левая доля по проценту
-- прочности — цветом состояния (тот же hpColor, что у числа), остальное — тусклым.
-- UIGradient умножает на TextColor3, поэтому у подписи он белый.
hpCaption.TextColor3 = Color3.new(1, 1, 1)
local hpCaptionGradient = Instance.new("UIGradient")
hpCaptionGradient.Parent = hpCaption

-- Ход забега под числом волны — черточками, по одной на каждую волну уровня (просьба
-- автора): дошедшие до текущей бирюзовые, остальные тусклые. Бирюза на арене —
-- только у полосок и кнопок.
local WAVE_TICK_GAP = 3

local waveTrack = Instance.new("Frame")
waveTrack.Name = "WaveTrack"
waveTrack.Position = UDim2.fromOffset(center - WAVE_W / 2, PILL_H - 5)
waveTrack.Size = UDim2.fromOffset(WAVE_W, 3)
waveTrack.BackgroundTransparency = 1
waveTrack.Parent = readouts

local waveTickList = Instance.new("UIListLayout")
waveTickList.FillDirection = Enum.FillDirection.Horizontal
waveTickList.SortOrder = Enum.SortOrder.LayoutOrder
waveTickList.Padding = UDim.new(0, WAVE_TICK_GAP)
waveTickList.Parent = waveTrack

local waveTicks = {}

local function paintWaveTicks(waveNumber, totalWaves)
	if #waveTicks ~= totalWaves then
		for _, tick in waveTicks do
			tick:Destroy()
		end
		table.clear(waveTicks)
		for index = 1, totalWaves do
			local tick = Instance.new("Frame")
			tick.LayoutOrder = index
			-- Доля ширины за вычетом своей части зазоров: черточки ровно заполняют дорожку.
			tick.Size = UDim2.new(1 / totalWaves, -WAVE_TICK_GAP * (totalWaves - 1) / totalWaves, 1, 0)
			tick.BorderSizePixel = 0
			tick.Parent = waveTrack
			waveTicks[index] = tick
		end
	end
	for index, tick in waveTicks do
		local lit = index <= waveNumber
		tick.BackgroundColor3 = lit and Theme.color.accent or Theme.color.textMute
		tick.BackgroundTransparency = lit and 0 or 0.45
	end
end

-- Раскладка по полосе Roblox: плашки по её высоте, «ЗАБЕГ» сразу за кнопками Roblox,
-- показания по центру экрана — но не налезая на «ЗАБЕГ» (на узком окне сдвигаются вправо).
local function layoutHeader()
	local bar = MobileUI.Topbar
	local y = math.max(0, math.floor((bar.height - PILL_H) / 2))
	titlePill.Position = UDim2.fromOffset(bar.left + PILL_GAP, y)
	local leftEdge = titlePill.Visible and (bar.left + PILL_GAP + titlePill.AbsoluteSize.X) or bar.left
	local x = math.max(MobileUI.viewportX / 2, leftEdge + PILL_GAP + GROUP_W / 2)
	readouts.Position = UDim2.fromOffset(math.floor(x), y)
end
MobileUI.OnViewportChanged(layoutHeader)
titlePill:GetPropertyChangedSignal("AbsoluteSize"):Connect(layoutHeader)

local function showWave(waveNumber, totalWaves)
	waveLabel.Text = ("%d / %d"):format(waveNumber, totalWaves)
	paintWaveTicks(waveNumber, math.max(0, math.floor(totalWaves)))
	Theme.Blink(waveLabel)
end

-- Цвет Прочности считается от ДОЛИ оставшегося, а не от числа: максимум у стола
-- свой (LabTable.MAX_HP). Пока стол цел — белым, как прочие показания; тревога
-- цветом только когда её пора замечать.
local function hpColor(hp, limit)
	local share = limit > 0 and hp / limit or 0
	if share > 0.6 then
		return Theme.color.text
	elseif share > 0.3 then
		return Theme.color.warn
	end
	return Theme.color.danger
end

local function paintHpCaption(hp, limit)
	local share = limit > 0 and math.clamp(hp / limit, 0, 1) or 0
	local filled = hpColor(hp, limit)
	local rest = Theme.color.textDim
	if share >= 1 then
		hpCaptionGradient.Color = ColorSequence.new(filled)
	elseif share <= 0 then
		hpCaptionGradient.Color = ColorSequence.new(rest)
	else
		-- Жёсткая граница на доле прочности (два ключа с почти одним положением).
		share = math.clamp(share, 0.002, 0.998)
		hpCaptionGradient.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, filled),
			ColorSequenceKeypoint.new(share, filled),
			ColorSequenceKeypoint.new(share + 0.001, rest),
			ColorSequenceKeypoint.new(1, rest),
		})
	end
end
paintHpCaption(0, 0)

-- ============ Журнал ============

-- Сообщения сервера (Notify: «не хватает материи», «надо подойти к столу», ответ на
-- промокод) — столбиком последних строк, а не одной плашкой посреди экрана, которую
-- следующее сообщение тут же затирало. В забеге — слева под шапкой рамки; пока открыто
-- главное меню — в правом нижнем углу над его подвалом, где у меню пусто.
-- Свой ScreenGui на слое Notify: сообщение должно быть видно и поверх открытого окна.
local JOURNAL_LINES = mobile and 2 or 3
local JOURNAL_LIFE = 8 -- секунд строка висит, потом гаснет
local JOURNAL_FADE = 1.5

local journalGui = Instance.new("ScreenGui")
journalGui.Name = "Journal"
journalGui.ResetOnSpawn = false
journalGui.DisplayOrder = MobileUI.Layer.Notify
journalGui.Parent = playerGui

local journal = Instance.new("Frame")
journal.Name = "Journal"
journal.Size = mobile and UDim2.new(0.42, 0, 0, 0) or UDim2.fromOffset(440, 0)
journal.AutomaticSize = Enum.AutomaticSize.Y
journal.BackgroundColor3 = Theme.color.ink
journal.BackgroundTransparency = 0.35
journal.BorderSizePixel = 0
journal.Visible = false
journal.Parent = journalGui

-- Подложка гаснет вправо: тень под строками, а не плашка с краем.
local journalFade = Instance.new("UIGradient")
journalFade.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0),
	NumberSequenceKeypoint.new(0.6, 0.5),
	NumberSequenceKeypoint.new(1, 1),
})
journalFade.Parent = journal

local journalPad = Instance.new("UIPadding")
journalPad.PaddingTop = UDim.new(0, 6)
journalPad.PaddingBottom = UDim.new(0, 6)
journalPad.PaddingLeft = UDim.new(0, mobile and 10 or 14)
journalPad.PaddingRight = UDim.new(0, 10)
journalPad.Parent = journal

local journalList = Instance.new("UIListLayout")
journalList.SortOrder = Enum.SortOrder.LayoutOrder
journalList.Padding = UDim.new(0, 2)
journalList.Parent = journal

-- Подпись «ЖУРНАЛ» — только на ПК: на телефоне она съела бы строку из двух.
if not mobile then
	local journalCaption = Instance.new("TextLabel")
	journalCaption.LayoutOrder = 0
	journalCaption.Size = UDim2.new(1, 0, 0, 18)
	journalCaption.TextSize = Theme.MIN_TEXT
	journalCaption.TextXAlignment = Enum.TextXAlignment.Left
	journalCaption.Text = Theme.Caps("журнал")
	journalCaption.Parent = journal
	Theme.StatCaption(journalCaption)
end

local journalEntries = {} -- новые первыми: { label = TextLabel, text = string }
local journalOrder = 0
local inRun = false

-- Новая строка — белым, старые тише: глаз сразу находит последнее. Скобки «>»
-- в начале строк нет: декоративные «>» и «//» убраны из всех интерфейсов (решение автора).
local function paintJournal()
	for index, entry in journalEntries do
		entry.label.LayoutOrder = index
		local newest = index == 1
		entry.label.TextColor3 = newest and Theme.color.text or (index == 2 and Theme.color.textDim or Theme.color.textMute)
		entry.label.Text = entry.text
	end
	journal.Visible = #journalEntries > 0
end

local function removeEntry(entry)
	local index = table.find(journalEntries, entry)
	if index then
		table.remove(journalEntries, index)
		entry.label:Destroy()
		paintJournal()
	end
end

local function addJournal(message)
	journalOrder += 1
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 0, 0)
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.FontFace = Theme.font.body
	label.TextSize = mobile and Theme.MIN_TEXT or 15
	label.TextWrapped = true
	label.RichText = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = journal
	Theme.ArenaLabel(label)

	local entry = { label = label, text = Theme.Escape(message) }
	table.insert(journalEntries, 1, entry)
	while #journalEntries > JOURNAL_LINES do
		removeEntry(journalEntries[#journalEntries])
	end
	paintJournal()
	Theme.Blink(label)

	task.delay(JOURNAL_LIFE, function()
		if not label.Parent then
			return -- строку уже вытеснили новые
		end
		local fade = TweenService:Create(label, TweenInfo.new(JOURNAL_FADE), {
			TextTransparency = 1,
			TextStrokeTransparency = 1,
		})
		fade.Completed:Connect(function()
			removeEntry(entry)
		end)
		fade:Play()
	end)
end

Remotes.Notify.OnClientEvent:Connect(addJournal)

-- Место журнала зависит от того, что на экране: главное меню, рамка забега или ничего.
local mainMenuGui = nil

local function placeJournal()
	if mainMenuGui and mainMenuGui.Enabled then
		-- Над подвалом меню справа: колонка пунктов слева, справа внизу пусто.
		journal.AnchorPoint = Vector2.new(1, 1)
		journal.Position = UDim2.new(1, -(INSET + 24), 1, -(mobile and 56 or 84))
		journalFade.Rotation = 180
	else
		journal.AnchorPoint = Vector2.new(0, 0)
		-- Вне забега (аркада) — ниже бейджа плутония лобби (20 + 76, LobbyUI).
		local top = inRun and (INSET + 10) or 108
		journal.Position = UDim2.fromOffset(INSET + 4, top)
		journalFade.Rotation = 0
	end
end

task.spawn(function()
	mainMenuGui = playerGui:WaitForChild("MainMenu", 30)
	if mainMenuGui then
		mainMenuGui:GetPropertyChangedSignal("Enabled"):Connect(placeJournal)
	end
	placeJournal()
end)
placeJournal()

local function setInRun(value)
	inRun = value
	frame.Visible = value
	headerGui.Enabled = value
	shadeGui.Enabled = value
	placeJournal()
end

-- Итог забега собран той же ячейкой, что и строки списков: тёмный корпус в цвете исхода
-- (зелёный — победа, красный — поражение), кант и засечка. Раньше это была голая
-- надпись с чёрной обводкой поверх арены — единственный элемент интерфейса без своей плашки.
local resultFrame = Instance.new("Frame")
resultFrame.Visible = false
resultFrame.Parent = resultGui

local resultLabel = Instance.new("TextLabel")
-- Ширина долей экрана и центрирование через AnchorPoint. Прежний ручной отступ -resultW/2
-- считался один раз при загрузке: после поворота телефона ширина вьюпорта уже другая,
-- а отступ оставался от старой, и баннер уезжал из центра. AnchorPoint от размера не зависит.
-- На телефоне баннер опущен под панель лобби и стал ниже. Он висит до следующего
-- забега, а на низком альбомном экране 0.25 высоты — это ровно строка уровня
-- в панели лобби (замерено на 750x322: баннер 37,80..712,170 против панели
-- 20,20..485,128 — перекрытие 447x47). Строка уровня — кнопка выбора, её надо и
-- читать, и нажимать сразу после поражения.
resultFrame.AnchorPoint = Vector2.new(0.5, 0)
resultFrame.Size = MobileUI.isMobile and UDim2.new(0.9, 0, 0, 56) or UDim2.new(0, 500, 0, 90)
resultFrame.Position = MobileUI.isMobile and UDim2.new(0.5, 0, 0.59, 0) or UDim2.new(0.5, 0, 0.25, 0)
-- Плашка — до надписей: сетка точек должна лечь под них. Скобки и кант красит исход (RunEnded).
-- На телефоне баннер 56px — скобки там сошлись бы, их нет.
Theme.Plate(resultFrame, { brackets = not MobileUI.isMobile })
resultLabel.Size = UDim2.new(1, 0, 1, 0)
resultLabel.BackgroundTransparency = 1
resultLabel.TextWrapped = true
resultLabel.TextSize = MobileUI.isMobile and 40 or 52
resultLabel.TextStrokeTransparency = 1
resultLabel.Text = ""
resultLabel.Parent = resultFrame

-- Тот же приборный шрифт, что у показаний: итог забега — самая крупная надпись в игре,
-- и Gotham Black рядом с остальным интерфейсом читался как чужая игра.
Theme.Display(resultLabel)

-- Мелкая подпись над словом — тот же строй, что у чисел в списках: сначала что это
-- за показание, потом само значение. Только на ПК: на телефоне баннер всего 56px
-- высотой, и сорокапиксельное слово по центру накрыло бы её целиком.
local resultCaption = nil
if not MobileUI.isMobile then
	resultCaption = Instance.new("TextLabel")
	resultCaption.Size = UDim2.new(1, -28, 0, 16)
	resultCaption.Position = UDim2.new(0, 14, 0, 7)
	resultCaption.TextSize = Theme.MIN_TEXT
	resultCaption.ZIndex = resultLabel.ZIndex + 1
	resultCaption.Parent = resultFrame

	Theme.StatCaption(resultCaption)
	resultCaption.TextXAlignment = Enum.TextXAlignment.Left

	-- Слово центрируется в остатке высоты, а не во всём баннере — иначе оно наезжает
	-- на подпись верхними выносными элементами букв.
	local resultPad = Instance.new("UIPadding")
	resultPad.PaddingTop = UDim.new(0, 16)
	resultPad.Parent = resultLabel
end

-- Кнопка вызова волны. Волны не идут сами: сервер сообщает по WaveReady, что готов следующую,
-- и ждёт нажатия — в maze лабиринт строится до волны, и таймер не знает, сколько на это нужно.
local startWaveButton = Instance.new("TextButton")
-- На мобильном кнопка ушла к правому краю и стала уже: внизу теперь панель стройки
-- (TowerInteraction) и родные кнопки Roblox, а прежние 90% ширины по центру накрывали панель целиком.
-- На ПК кнопка в правом нижнем углу рамки забега, справа от подсказок подвала (по макету,
-- согласованному с автором); подвал оставляет ей место (MobileUI.FOOTER_SIDE).
startWaveButton.AnchorPoint = Vector2.new(1, 1)
startWaveButton.Size = MobileUI.isMobile and UDim2.new(0.32, 0, 0, 56) or UDim2.new(0, 260, 0, 52)
-- Кнопка поднята над зоной родной кнопки прыжка Roblox. Та занимает правый нижний угол
-- (замерено на вьюпорте 750x322: JumpButton 655,232..725,302 — 95px от правого края,
-- 90px от нижнего), и в прежнем положении «1, -12» кнопка волны накрывала её целиком:
-- прыжок на телефоне не работал вовсе, а правая треть самой кнопки волны стояла над
-- чужим элементом. Доля 0.7 по высоте, а не пиксельный отступ снизу: на планшете
-- Roblox рисует кнопку прыжка крупнее (120px против 70), и фиксированный отступ,
-- подобранный по телефону, там снова дал бы пересечение.
startWaveButton.Position = MobileUI.isMobile and UDim2.new(1, -12, 0.7, 0)
	or UDim2.new(1, -(INSET + 12), 1, -(INSET + 12))
startWaveButton.AutoButtonColor = true
startWaveButton.FontFace = Theme.font.strong
startWaveButton.TextSize = MobileUI.isMobile and 18 or 24
startWaveButton.TextColor3 = Theme.buttonKind.action.text
startWaveButton.TextTruncate = Enum.TextTruncate.AtEnd
-- «Начать», а не «Волна»: это действие, а номер волны и так в шапке (просьба автора).
startWaveButton.Text = MobileUI.isMobile and "НАЧАТЬ ▶" or "НАЧАТЬ"
startWaveButton.Visible = false
-- Волна ждёт кнопки (WaveReady пришёл, удержания, WaveChanged и RunEnded ещё не было).
-- Нужно обучению (задача #298): пока шаги не пройдены, кнопки нет, и появляется она
-- по атрибуту TutorialWaveLocked, а не по новому WaveReady.
local waveReady = false
startWaveButton.Parent = screenGui

-- Пульсирующей обводки здесь больше нет: что игра ждёт именно этого нажатия, говорит
-- само появление кнопки — она видна только между волнами, по WaveReady.
Theme.Button(startWaveButton, "action")
-- Уголки-скобки, как у рамки меню: главная кнопка забега — тоже окно терминала.
Theme.Brackets(startWaveButton, Theme.color.accent)

local startSize = Instance.new("UISizeConstraint")
startSize.MaxSize = Vector2.new(240, 56)
startSize.Parent = startWaveButton

-- Волна вызывается не кликом, а удержанием секунду (прямое требование автора). Причина та же,
-- по которой удержанием ставится постройка (TowerInteraction.BUILD_HOLD_TIME): кнопка стоит
-- в той части экрана, где палец и так елозит по камере, и случайный тап запускал волну
-- посреди недостроенного лабиринта — отменить это нечем, волна уже вышла.
local WAVE_HOLD_TIME = 1 -- секунд удержания кнопки перед RequestStartWave

-- Полоска прогресса — узкая планка по низу самой кнопки, а не заливка на всю её площадь:
-- текст кнопки принадлежит самой кнопке и рисуется её ZIndex'ом, любой дочерний кадр того же
-- ZIndex лёг бы поверх надписи и закрыл её.
local holdBar = Instance.new("Frame")
holdBar.Name = "HoldProgress"
holdBar.AnchorPoint = Vector2.new(0, 1)
holdBar.Position = UDim2.new(0, 6, 1, -6)
holdBar.Size = UDim2.new(0, 0, 0, 6)
holdBar.BackgroundColor3 = Theme.color.accent
holdBar.BorderSizePixel = 0
holdBar.Parent = startWaveButton

Theme.Corner(holdBar, 3)

local holdingWave = false
local waveHoldStart = 0
local waveHoldConn = nil

local function cancelWaveHold()
	holdingWave = false
	if waveHoldConn then
		waveHoldConn:Disconnect()
		waveHoldConn = nil
	end
	holdBar.Size = UDim2.new(0, 0, 0, 6)
end

local function startWaveHold()
	if holdingWave or not startWaveButton.Visible then
		return
	end
	holdingWave = true
	waveHoldStart = os.clock()
	-- Heartbeat, а не RenderStepped: на RenderStepped висит вся анимация построек, и в
	-- Play-сессии Studio он не идёт вовсе (STATE.md, «Открытые проблемы», задача #77) —
	-- полоска бы стояла, а волна не начиналась никогда. Heartbeat тикает штатные 60/сек.
	waveHoldConn = RunService.Heartbeat:Connect(function()
		if not holdingWave then
			return
		end
		local progress = math.clamp((os.clock() - waveHoldStart) / WAVE_HOLD_TIME, 0, 1)
		holdBar.Size = UDim2.new(progress, -12, 0, 6)
		if progress >= 1 then
			cancelWaveHold()
			startWaveButton.Visible = false -- чтобы второе удержание не ушло в следующую волну
			waveReady = false
			Remotes.RequestStartWave:FireServer()
		end
	end)
end

-- InputBegan самой кнопки, а не MouseButton1Click: клик приходит уже по отпусканию, то есть
-- ровно тем событием, от которого удержание и должно защищать. Touch здесь тоже нужен явно —
-- на телефоне мыши нет.
startWaveButton.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		startWaveHold()
	end
end)

-- Отпускание ловится и на кнопке, и глобально: палец может уйти с кнопки до отпускания,
-- и тогда её собственный InputEnded не придёт вовсе, а удержание осталось бы висеть.
startWaveButton.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		cancelWaveHold()
	end
end)

startWaveButton.MouseLeave:Connect(cancelWaveHold)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		cancelWaveHold()
	end
end)

ReplicatedStorage:GetAttributeChangedSignal("TutorialWaveLocked"):Connect(function()
	if waveReady then
		startWaveButton.Visible = not ReplicatedStorage:GetAttribute("TutorialWaveLocked")
	end
end)

Remotes.WaveReady.OnClientEvent:Connect(function(waveNumber, totalWaves)
	setInRun(true)
	-- Готовность волны говорит сама кнопка «Начать»: номер — в шапке.
	showWave(waveNumber, totalWaves)
	waveReady = true
	startWaveButton.Visible = not ReplicatedStorage:GetAttribute("TutorialWaveLocked")

	-- Готовность волны 1 приходит и после входа в уровень из лобби. Без сброса здесь баннер
	-- победы/поражения предыдущего забега висел бы поверх новой попытки до первого нажатия волны.
	resultFrame.Visible = false
end)

Remotes.WaveChanged.OnClientEvent:Connect(function(waveNumber, totalWaves)
	waveReady = false
	setInRun(true)
	showWave(waveNumber, totalWaves)

	-- Началась волна — значит забег идёт, и итоговый баннер убирается сам.
	-- Отдельное событие «забег начался» для этого заводить не нужно.
	resultFrame.Visible = false
	startWaveButton.Visible = false
	cancelWaveHold()
end)

Remotes.MatterChanged.OnClientEvent:Connect(function(amount)
	matterLabel.Text = tostring(amount)
	Theme.Blink(matterLabel)
end)

-- Стол активной локации; при смене локации подписка переезжает на новый стол.
local Arena = require(ReplicatedStorage:WaitForChild("Arena"))
local craftTable = Arena.Location():WaitForChild("CraftTable")
local tableConnections = {}

local function updateTableHp()
	local hp = craftTable:GetAttribute("HP") or 0
	local maxHp = craftTable:GetAttribute("MaxHP") or hp
	hpLabel.Text = tostring(math.floor(hp))
	hpLabel.TextColor3 = hpColor(hp, maxHp)
	paintHpCaption(hp, maxHp)
	Theme.Blink(hpLabel)
end

local function watchTable()
	for _, connection in tableConnections do
		connection:Disconnect()
	end
	tableConnections = {
		craftTable:GetAttributeChangedSignal("HP"):Connect(updateTableHp),
		craftTable:GetAttributeChangedSignal("MaxHP"):Connect(updateTableHp),
	}
	updateTableHp()
end
watchTable()

Arena.OnChanged(function()
	craftTable = Arena.Location():WaitForChild("CraftTable")
	watchTable()
end)

Remotes.RunEnded.OnClientEvent:Connect(function(won, levelNumber)
	waveReady = false
	local tone = won and Theme.color.action or Theme.color.danger
	resultLabel.Text = won and "ПОБЕДА" or "ПОРАЖЕНИЕ"
	-- Плашка языком меню, исход — цветом канта, скобок и слова.
	Theme.Stroke(resultFrame, Theme.Shadowed(tone, 0.35), 1, 0)
	if resultFrame:FindFirstChild("Brackets") then
		Theme.Brackets(resultFrame, tone)
	end
	resultLabel.TextColor3 = Theme.Legible(tone)
	if resultCaption then
		resultCaption.Text = won and "ЗАБЕГ ОКОНЧЕН: прочность стола сохранена"
			or "ЗАБЕГ ОКОНЧЕН: лаборатория прорвана"
		-- Обучение пройдено (задача #298): сказать, куда «Играть» поведёт дальше.
		local level = won and typeof(levelNumber) == "number" and Levels[levelNumber]
		if level and level.tutorial then
			local nextLevel = Levels[levelNumber + 1]
			resultCaption.Text = nextLevel
				and ("ОБУЧЕНИЕ ПРОЙДЕНО: открыт уровень %d «%s»"):format(levelNumber + 1, nextLevel.name)
				or "ОБУЧЕНИЕ ПРОЙДЕНО"
		end
	end
	resultFrame.Visible = true
	Theme.Open(resultFrame)
	startWaveButton.Visible = false
	cancelWaveHold()
	-- Сервер тут же возвращает игрока в лобби — рамку забега прячем,
	-- баннер остаётся висеть поверх лобби до следующего WaveReady/WaveChanged.
	setInRun(false)
end)
