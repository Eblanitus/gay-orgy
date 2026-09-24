-- Главное меню: экран, с которого начинается игра. Три пункта — Играть, Журнал, Настройки.
--
-- ВИД. Собрано на том же языке, что и весь остальной интерфейс (UITheme, задача #90):
-- почти чёрный фон, кант в пиксель, моноширинный шрифт, заглавные, скобка «>»
-- в начале строки. Своего вида у меню нет намеренно: экран, нарисованный по-своему,
-- читался бы как чужая игра перед той, в которую играют.
--
-- Терминального здесь три вещи, которых нет в остальном интерфейсе: строки запуска,
-- которые печатаются по букве; мигающий курсор; и медленная светлая полоса сверху вниз —
-- развёртка кинескопа. Сплошных скан-линий по всему экрану нет: в Roblox это сотни
-- отдельных кадров на каждый кадр отрисовки, а фон у панелей уже есть свой — соты
-- (Theme.Backdrop), и два разных рисунка один поверх другого спорили бы за внимание.
--
-- КОГДА ВИДНО. Пока игрок в лобби — то же разделение состояний, что у LobbyUI:
-- прячется по WaveReady/WaveChanged, возвращается по RunEnded. В лобби меню не сворачивается
-- вовсе (просьба автора): в игру заходят только через «Играть» (или «Аркаду»), по острову
-- лобби не ходят. Свернуть можно только во время забега или аркады — и вызвать заново
-- клавишей M или кнопкой в углу. Кнопка нужна потому, что клавиши на телефоне нет вовсе.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local MobileUI = require(script.Parent:WaitForChild("MobileUI"))
local Theme = require(script.Parent:WaitForChild("UITheme"))
local Settings = require(script.Parent:WaitForChild("Settings"))
local JournalUI = require(script.Parent:WaitForChild("JournalUI"))
local SettingsUI = require(script.Parent:WaitForChild("SettingsUI"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RequestEnterLevelRemote = Remotes:WaitForChild("RequestEnterLevel")
local ProfileSyncedRemote = Remotes:WaitForChild("ProfileSynced")
local RequestEnterArcadeRemote = Remotes:WaitForChild("RequestEnterArcade")
local RequestExitArcadeRemote = Remotes:WaitForChild("RequestExitArcade")
local ArcadeEnteredRemote = Remotes:WaitForChild("ArcadeEntered")
local ArcadeExitedRemote = Remotes:WaitForChild("ArcadeExited")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local mobile = MobileUI.isMobile

local MARGIN = mobile and 14 or 26
-- Шапка на телефоне на четыре пикселя теснее прежнего: игра только альбомная,
-- высоты там около трёхсот пикселей на всё, и каждый пиксель шапки и подвала —
-- это пиксель колонки пунктов, которой и так впритык.
local HEADER_H = mobile and 60 or 86
-- Подвал — одна строка ПОД чертой: слева подсказка, справа кнопка действия.
-- Раньше высоты подвала хватало только на подсказку, и кнопка, прижатая к низу
-- рамки, ложилась и на черту, и на саму подсказку (замерено на 1914x793: кнопка
-- 677..709 против черты на 682 и строки 691..709).
local ACTION_W = mobile and 128 or 150
local ACTION_H = mobile and 30 or 32
local FOOTER_H = ACTION_H + (mobile and 10 or 22)
local BTN_H = mobile and 50 or 54
local BTN_GAP = 10
local COLUMN_W = 460
-- Потолок ширины самой рамки. Терминал во всю ширину монитора — это четыре вкладки
-- журнала по полметра каждая и строка статистики, у которой подпись и число разнесены
-- по разным концам экрана и читаются как два несвязанных списка. На телефоне потолок
-- ни на что не влияет: там экран и так уже этого числа.
local FRAME_MAX_W = 1100

-- ============ Каркас ============

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "MainMenu"
screenGui.ResetOnSpawn = false
-- Меню закрывает экран целиком, включая полосу Roblox сверху: щель с игрой над меню
-- выдала бы его за окошко поверх игры. Содержимое при этом начинается НИЖЕ полосы
-- (MobileUI.TopInset) — заголовок под кнопками Roblox не прочесть.
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = MobileUI.Layer.Menu
screenGui.Enabled = false
screenGui.Parent = playerGui

local screen = Instance.new("Frame")
screen.Name = "Screen"
screen.Size = UDim2.new(1, 0, 1, 0)
screen.BackgroundColor3 = Theme.color.panel
screen.BackgroundTransparency = 0
screen.BorderSizePixel = 0
screen.ClipsDescendants = true
screen.Parent = screenGui

-- Фон экрана меню — обстановка страницы (Theme.scene): у главной, журнала и настроек
-- своя, и меняется она вместе со страницей (showPage). Решётка лежит на всём экране,
-- но видна только вокруг рамки терминала: у рамки своя заливка и сетка точек.
Theme.Backdrop(screen, "menu")

-- Развёртка: одна широкая полоса, почти невидимая, едет сверху вниз.
local sweep = Instance.new("Frame")
sweep.Name = "Sweep"
sweep.BackgroundColor3 = Theme.color.accent
sweep.BackgroundTransparency = 0.955
sweep.BorderSizePixel = 0
sweep.Size = UDim2.new(1, 0, 0, mobile and 60 or 90)
sweep.Position = UDim2.new(0, 0, 0, -200)
-- Поверх всего прочего: развёртка проходит по стеклу, а не под текстом.
-- Active остаётся false (значение по умолчанию у Frame) — такой кадр нажатие не забирает,
-- и полоса, проезжая поверх кнопки, не съедает по ней клик.
sweep.Active = false
sweep.ZIndex = 20
sweep.Parent = screen

-- Края полосы растворяются: ровный прямоугольник с чёткой верхней и нижней границей
-- читается как плашка, которую забыли убрать, а не как ход развёртки.
local sweepFade = Instance.new("UIGradient")
sweepFade.Rotation = 90
sweepFade.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1),
	NumberSequenceKeypoint.new(0.5, 0),
	NumberSequenceKeypoint.new(1, 1),
})
sweepFade.Parent = sweep

-- Рамка терминала: кант в пиксель, отступивший от края экрана. Отдельный кадр,
-- а не обводка самого экрана: обводка по самому краю на телефоне частично уезжает
-- за скруглённые углы экрана и выглядит обрезанной.
local frame = Instance.new("Frame")
frame.Name = "Frame"
-- Фон окна не такой, как фон экрана (просьба автора): сплошная заливка ink и сетка
-- точек, как в окне производителя, но тусклее и с пропусками — часть позиций пустует.
frame.BackgroundColor3 = Theme.color.ink
frame.BackgroundTransparency = 0
frame.BorderSizePixel = 0
frame.Parent = screen
Theme.Corner(frame, Theme.radius.panel)
Theme.Stroke(frame, Theme.color.frame, 1, 0)
Theme.Brackets(frame)
-- Слои у меню общие (ZIndexBehavior Global): сетка берёт ZIndex рамки и, заведённая
-- первым ребёнком, ложится над заливкой, но под всем остальным содержимым.
local paintDots = Theme.Dots(frame, { transparency = 0.65, keep = 0.6 })

-- Геометрия рамки считается заново при каждом изменении экрана: полоса Roblox сверху
-- меняется и без смены размера (полноэкранный режим), а замороженный отступ уехал бы.
local function layoutFrame()
	local top = MobileUI.TopInset + (mobile and 8 or 12)
	local width = math.min(MobileUI.viewportX - MARGIN * 2, FRAME_MAX_W)
	frame.AnchorPoint = Vector2.new(0.5, 0)
	frame.Position = UDim2.new(0.5, 0, 0, top)
	frame.Size = UDim2.new(0, width, 1, -(top + (mobile and 10 or 14)))
end

MobileUI.OnViewportChanged(layoutFrame)

-- Сетка точек меряется по самой рамке: высоту из размера экрана в миг раскладки
-- брать нельзя — экран к этому времени бывает ещё не той высоты, и низ рамки
-- оставался без точек. Пока окно открывается (OpenScale меньше единицы), рамка
-- меряется меньше настоящей — такой замер пропускается, конец анимации даст верный.
frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
	local open = frame:FindFirstChild("OpenScale")
	if open and open.Scale < 1 then
		return
	end
	paintDots(frame.AbsoluteSize.X, frame.AbsoluteSize.Y)
end)

local pad = Instance.new("UIPadding")
pad.PaddingTop = UDim.new(0, mobile and 10 or 14)
pad.PaddingBottom = UDim.new(0, mobile and 8 or 12)
pad.PaddingLeft = UDim.new(0, mobile and 12 or 20)
pad.PaddingRight = UDim.new(0, mobile and 12 or 20)
pad.Parent = frame

-- ============ Шапка ============

local titleLabel = Instance.new("TextLabel")
titleLabel.Size = UDim2.new(1, -(ACTION_W + 136 + 24), 0, mobile and 26 or 40)
titleLabel.BackgroundTransparency = 1
titleLabel.TextSize = mobile and 20 or 32
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.TextTruncate = Enum.TextTruncate.AtEnd
titleLabel.Text = "ALCHEMY LAB DEFENSE"
titleLabel.Parent = frame
Theme.Display(titleLabel)
titleLabel.TextColor3 = Theme.color.accent

-- Подзаголовок — это название текущего экрана, а не постоянная подпись: в журнале
-- и настройках он говорит, где игрок находится.
local pathLabel = Instance.new("TextLabel")
pathLabel.Position = UDim2.new(0, 0, 0, mobile and 28 or 44)
pathLabel.Size = UDim2.new(1, -(ACTION_W + 16), 0, mobile and 16 or 18)
pathLabel.BackgroundTransparency = 1
pathLabel.TextSize = mobile and 11 or 13
pathLabel.TextXAlignment = Enum.TextXAlignment.Left
pathLabel.TextTruncate = Enum.TextTruncate.AtEnd
pathLabel.Text = ""
pathLabel.Parent = frame
pathLabel.FontFace = Theme.font.body
pathLabel.TextColor3 = Theme.color.textDim

-- Плутоний в шапке: его бейдж в лобби (LobbyUI) меню закрывает собой, а число
-- нужно видеть именно здесь — из меню идут и в забег, и в журнал.
-- Оформлен как материя у производителя (просьба автора, #232): тёмная плашка с ровной
-- кромкой, подпись и число крупнее и разделены полоской. Размытых пятен точек под
-- плашкой нет — они живут в CraftingUI (glass/frost), а не в UITheme.
local PLUTONIUM_H = mobile and 34 or 44
local plutoniumBox = Instance.new("Frame")
plutoniumBox.Name = "Plutonium"
plutoniumBox.AnchorPoint = Vector2.new(1, 0)
-- Слева от кнопки «Назад»/«Свернуть» (см. actionButton), по середине её высоты.
plutoniumBox.Position = UDim2.new(1, -(ACTION_W + 16), 0, (mobile and 0 or 4) + math.floor((ACTION_H - PLUTONIUM_H) / 2))
plutoniumBox.Size = UDim2.new(0, 0, 0, PLUTONIUM_H)
plutoniumBox.AutomaticSize = Enum.AutomaticSize.X
plutoniumBox.BackgroundColor3 = Theme.color.ink
plutoniumBox.BackgroundTransparency = 0.1
plutoniumBox.BorderSizePixel = 0
plutoniumBox.Parent = frame
Theme.Corner(plutoniumBox, Theme.radius.mark)
Theme.Stroke(plutoniumBox, Theme.color.text, 1, 0.85)
local plutoniumList = Instance.new("UIListLayout")
plutoniumList.FillDirection = Enum.FillDirection.Horizontal
plutoniumList.VerticalAlignment = Enum.VerticalAlignment.Center
plutoniumList.SortOrder = Enum.SortOrder.LayoutOrder
plutoniumList.Parent = plutoniumBox
local function plutoniumPart(name, order, left, right, size)
	local l = Instance.new("TextLabel")
	l.Name = name
	l.LayoutOrder = order
	l.Size = UDim2.fromScale(0, 1)
	l.AutomaticSize = Enum.AutomaticSize.X
	l.BackgroundTransparency = 1
	l.TextWrapped = false
	l.TextSize = size
	l.Parent = plutoniumBox
	Theme.Display(l)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, left)
	pad.PaddingRight = UDim.new(0, right)
	pad.Parent = l
	return l
end
local plutoniumCaption = plutoniumPart("Caption", 1, 14, 12, mobile and 17 or 20)
plutoniumCaption.Text = Theme.Caps("плутоний")
plutoniumCaption.TextColor3 = Theme.color.textMute
local plutoniumRule = Instance.new("Frame")
plutoniumRule.Name = "Rule"
plutoniumRule.LayoutOrder = 2
plutoniumRule.BackgroundColor3 = Theme.color.text
plutoniumRule.BackgroundTransparency = 0.85
plutoniumRule.BorderSizePixel = 0
plutoniumRule.Size = UDim2.new(0, 1, 0.5, 0)
plutoniumRule.Parent = plutoniumBox
local plutoniumLabel = plutoniumPart("Value", 3, 12, 14, mobile and 24 or 30)
plutoniumLabel.Text = "0"
plutoniumLabel.TextColor3 = Theme.color.energy

local headerRule = Instance.new("Frame")
headerRule.Position = UDim2.new(0, 0, 0, HEADER_H - (mobile and 12 or 16))
headerRule.Size = UDim2.new(1, 0, 0, 1)
headerRule.Parent = frame
Theme.Rule(headerRule)

-- ============ Подвал ============

local footerRule = Instance.new("Frame")
footerRule.AnchorPoint = Vector2.new(0, 1)
footerRule.Position = UDim2.new(0, 0, 1, -(ACTION_H + (mobile and 5 or 10)))
footerRule.Size = UDim2.new(1, 0, 0, 1)
footerRule.Parent = frame
Theme.Rule(footerRule)

-- Ширина — всё, что осталось от кнопки справа; высота — в рост кнопки, чтобы
-- подсказка встала с ней на одну середину, а не по нижнему краю.
local statusLabel = Instance.new("TextLabel")
statusLabel.AnchorPoint = Vector2.new(0, 1)
statusLabel.Position = UDim2.new(0, 0, 1, 0)
statusLabel.Size = UDim2.new(1, 0, 0, ACTION_H)
statusLabel.TextSize = mobile and 10 or 12
statusLabel.TextYAlignment = Enum.TextYAlignment.Center
statusLabel.Parent = frame

-- ============ Тело ============

local body = Instance.new("Frame")
body.Name = "Body"
body.Position = UDim2.new(0, 0, 0, HEADER_H)
body.Size = UDim2.new(1, 0, 1, -(HEADER_H + FOOTER_H))
body.BackgroundTransparency = 1
body.BorderSizePixel = 0
body.Parent = frame

-- ---- Главная страница ----

local rootPage = Instance.new("Frame")
rootPage.Name = "RootPage"
rootPage.Size = UDim2.new(1, 0, 1, 0)
rootPage.BackgroundTransparency = 1
rootPage.BorderSizePixel = 0
rootPage.Parent = body

local BOOT_LINE_H = mobile and 16 or 18
local BOOT_H = BOOT_LINE_H * 3

-- Строки запуска стоят СПРАВА от колонки пунктов, а не над ней. Игра только альбомная
-- (ScreenOrientationLock), и на телефоне это около трёхсот пикселей высоты на всё: три блока
-- друг под другом (шапка, запуск, пункты) туда не влезают, а ширины в альбоме всегда
-- в избытке. На ПК та же раскладка заодно занимает правую половину рамки, которая
-- иначе пустует.
local bootLabel = Instance.new("TextLabel")
bootLabel.Name = "Boot"
bootLabel.Position = UDim2.new(0.52, mobile and 10 or 20, 0, 0)
bootLabel.Size = UDim2.new(0.48, -(mobile and 10 or 20), 0, BOOT_H)
bootLabel.BackgroundTransparency = 1
bootLabel.FontFace = Theme.font.body
bootLabel.TextSize = mobile and 11 or 13
bootLabel.TextXAlignment = Enum.TextXAlignment.Left
bootLabel.TextYAlignment = Enum.TextYAlignment.Top
bootLabel.TextColor3 = Theme.color.accentDim
bootLabel.Text = ""
bootLabel.Parent = rootPage

-- Ниже строк запуска правая колонка пустовала на всю оставшуюся высоту рамки
-- (замерено на 1914x793: тело 1060x559, занято верхних сто с небольшим). Здесь
-- стоят те же числа, что и на вкладке «Статистика» журнала, и берутся они оттуда
-- же (JournalUI.Progress) — своего счётчика у меню нет.
local SUM_ROW_H = mobile and 20 or 25
local SUM_CAP_H = 26

-- Плутоний в этом списке не стоит: он уже показан числом в шапке (plutoniumLabel)
-- в паре сотен пикселей выше — второе число рядом было бы тавтологией, а не вторым показанием.
local SUM_ROWS = {
	{ key = "recipes", caption = "Рецепты", total = "recipesTotal" },
	{ key = "elements", caption = "Элементы", total = "elementsTotal" },
	{ key = "enemies", caption = "Жуки встречены", total = "enemiesTotal" },
	{ key = "levelsCleared", caption = "Уровни пройдены", total = "levelsTotal" },
}

local SUMMARY_Y = BOOT_H + (mobile and 10 or 18)
local SUMMARY_H = SUM_CAP_H + #SUM_ROWS * SUM_ROW_H

local summary = Instance.new("Frame")
summary.Name = "Summary"
summary.Position = UDim2.new(0.52, mobile and 10 or 20, 0, SUMMARY_Y)
summary.Size = UDim2.new(0.48, -(mobile and 10 or 20), 0, SUMMARY_H)
summary.BackgroundTransparency = 1
summary.BorderSizePixel = 0
summary.Parent = rootPage

local summaryCaption = Instance.new("TextLabel")
summaryCaption.Size = UDim2.new(1, 0, 0, SUM_CAP_H)
summaryCaption.TextSize = mobile and 11 or 12
summaryCaption.Parent = summary
Theme.Section(summaryCaption, "сводка")

-- Подпись и число — два отдельных ярлыка, а не одна строка с RichText: числа должны
-- стоять в колонку, а при склейке место числа зависело бы от длины подписи
-- (тот же приём, что в JournalUI.statsRow).
local summaryValues = {}

for index, row in SUM_ROWS do
	local holder = Instance.new("Frame")
	holder.Position = UDim2.new(0, 0, 0, SUM_CAP_H + (index - 1) * SUM_ROW_H)
	holder.Size = UDim2.new(1, 0, 0, SUM_ROW_H)
	holder.BackgroundTransparency = 1
	holder.BorderSizePixel = 0
	holder.Parent = summary

	local caption = Instance.new("TextLabel")
	caption.Size = UDim2.new(1, -110, 1, 0)
	caption.BackgroundTransparency = 1
	caption.FontFace = Theme.font.body
	caption.TextSize = mobile and 11 or 13
	caption.TextXAlignment = Enum.TextXAlignment.Left
	caption.TextTruncate = Enum.TextTruncate.AtEnd
	caption.TextColor3 = Theme.color.textDim
	caption.Text = Theme.Caps(row.caption)
	caption.Parent = holder

	local value = Instance.new("TextLabel")
	value.AnchorPoint = Vector2.new(1, 0)
	value.Position = UDim2.new(1, 0, 0, 0)
	value.Size = UDim2.new(0, 106, 1, 0)
	value.BackgroundTransparency = 1
	value.FontFace = Theme.font.strong
	value.TextSize = mobile and 12 or 14
	value.TextXAlignment = Enum.TextXAlignment.Right
	value.TextColor3 = row.energy and Theme.color.energy or Theme.color.accent
	value.Text = "—"
	value.Parent = holder

	summaryValues[index] = value
end

JournalUI.OnChanged(function()
	local progress = JournalUI.Progress()
	for index, row in SUM_ROWS do
		local value = progress[row.key] or 0
		summaryValues[index].Text = row.total
			and ("%d / %d"):format(value, progress[row.total] or 0)
			or tostring(value)
	end
end)

local menuHolder = Instance.new("Frame")
menuHolder.Name = "Items"
menuHolder.Position = UDim2.new(0, 0, 0, 0)
menuHolder.Size = UDim2.new(0.52, 0, 1, 0)
menuHolder.BackgroundTransparency = 1
menuHolder.BorderSizePixel = 0
menuHolder.Parent = rootPage

-- Колонка пунктов прижата влево и ограничена по ширине: пункт меню во всю ширину
-- широкого монитора — это полтора метра плашки с одним словом слева.
local columnLimit = Instance.new("UISizeConstraint")
columnLimit.MaxSize = Vector2.new(COLUMN_W, math.huge)
columnLimit.Parent = menuHolder

local menuLayout = Instance.new("UIListLayout")
menuLayout.SortOrder = Enum.SortOrder.LayoutOrder
menuLayout.Padding = UDim.new(0, BTN_GAP)
menuLayout.Parent = menuHolder

-- ---- Страницы журнала и настроек ----

-- Журнал сообщает о смене вкладки обратно в меню: подсказка внизу принадлежит рамке
-- меню, а знает, что в ней написать, только сам журнал.
local journal
local setStatus

journal = JournalUI.Mount(body, function(status)
	if setStatus then
		setStatus("Журнал", status)
	end
end)

local settings = SettingsUI.Mount(body)

-- Одна кнопка на два действия, справа вверху рамки — там же, где выход и возврат во всех
-- окнах игры: в журнале и настройках это «назад», в главном меню — «свернуть». Стоит
-- по середине строки названия; на телефоне кнопка выше строки и прижата к верху.
-- Оба действия никогда не нужны одновременно, а вынесенная из колонки
-- кнопка сворачивания освобождает те полсотни пикселей высоты, которых на телефоне
-- в альбоме как раз и не хватало.
--
-- На главной странице во время забега эта кнопка прячется (см. showPage): пункт меню
-- «Играть» тогда уже подписан «Продолжить» и делает ровно то же самое, что и «Свернуть» —
-- две кнопки с разными надписями для одного и того же действия путают игрока.
local actionButton = Instance.new("TextButton")
actionButton.Name = "Action"
actionButton.AnchorPoint = Vector2.new(1, 0)
actionButton.Position = UDim2.new(1, 0, 0, mobile and 0 or 4)
actionButton.Size = UDim2.new(0, ACTION_W, 0, ACTION_H)
actionButton.FontFace = Theme.font.strong
actionButton.TextSize = mobile and 12 or 13
actionButton.Text = ""
actionButton.Parent = frame
Theme.Button(actionButton, "quiet")

-- «Назад» — знак «‹» из двух линий, а не надпись, в пару крестику окон (Theme.CloseButton):
-- угловых скобок и стрелок нужной формы в шрифте темы нет. Кнопка тогда квадратная,
-- на телефоне шире — под палец. «Свернуть» остаётся словом.
local BACK_W = mobile and 44 or ACTION_H
local backIcon = Instance.new("Frame")
backIcon.Name = "BackIcon"
backIcon.BackgroundTransparency = 1
backIcon.Size = UDim2.new(1, 0, 1, 0)
backIcon.ZIndex = actionButton.ZIndex + 1
backIcon.Visible = false
backIcon.Parent = actionButton
local BACK_ARM = mobile and 8 or 7 -- катет плеча в пикселях
local BACK_THICK = mobile and 2 or 1
local backBars = {}
for index, rotation in { -45, 45 } do
	local bar = Instance.new("Frame")
	bar.Name = "Bar" .. index
	bar.BorderSizePixel = 0
	bar.AnchorPoint = Vector2.new(0.5, 0.5)
	-- Центр плеча — на полкатета правее острия и выше (ниже) середины: знак по центру кнопки.
	bar.Position = UDim2.new(0.5, 0, 0.5, (index == 1 and -1 or 1) * BACK_ARM / 2)
	bar.Size = UDim2.fromOffset(math.floor(BACK_ARM * math.sqrt(2) + BACK_THICK + 0.5), BACK_THICK)
	bar.Rotation = rotation
	bar.ZIndex = backIcon.ZIndex
	bar.Parent = backIcon
	backBars[index] = bar
end
-- Знак горит цветом надписи кнопки: наведение осветляет его вместе с ней (Theme.Button).
local function paintBack()
	for _, bar in backBars do
		bar.BackgroundColor3 = actionButton.TextColor3
	end
end
paintBack()
actionButton:GetPropertyChangedSignal("TextColor3"):Connect(paintBack)

-- ============ Пункты меню ============

local inRun = false
local inArcade = false
local page = "root"

local items = {}
local selected = 1

local function addItem(key, name, action)
	local button = Instance.new("TextButton")
	button.Name = key
	button.LayoutOrder = #items + 1
	button.Size = UDim2.new(1, 0, 0, BTN_H)
	button.FontFace = Theme.font.strong
	button.TextSize = mobile and 16 or 19
	button.TextXAlignment = Enum.TextXAlignment.Left
	button.Text = ""
	button.Parent = menuHolder
	Theme.Button(button, "ghost")

	local buttonPad = Instance.new("UIPadding")
	buttonPad.PaddingLeft = UDim.new(0, mobile and 12 or 16)
	buttonPad.Parent = button

	local item = { button = button, name = name, action = action, index = #items + 1 }
	table.insert(items, item)
	return item
end

-- Выбранный пункт показан дважды: и скобкой «>» в самой строке, и вывороткой плашки
-- (вид active). Одной скобки мало на телефоне — там палец закрывает левый край кнопки;
-- одной выворотки мало на ПК — там выбор ездит стрелками, и глаз ищет каретку.
local function paintItems()
	for index, item in items do
		local on = index == selected
		Theme.Button(item.button, on and "active" or "ghost")
		item.button.Text = (on and "> " or "  ") .. Theme.Caps(item.name)
	end
end

local function selectItem(index)
	if #items == 0 then
		return
	end
	selected = ((index - 1) % #items) + 1
	paintItems()
end

function setStatus(section, detail)
	Theme.Status(statusLabel, section, detail)
end

-- Свернуть меню можно только поверх забега или аркады: в лобби за ним нечего показывать.
local function canHide()
	return inRun or inArcade
end

local function rootHint()
	if mobile then
		return canHide() and "«Свернуть» — вернуться в игру" or "«Играть» — начать забег"
	end
	return canHide() and "M — свернуть, ↑↓ — выбор, ENTER — открыть" or "↑↓ — выбор, ENTER — открыть"
end

local function showPage(name)
	page = name
	rootPage.Visible = name == "root"
	local back = name ~= "root"
	actionButton.Text = back and "" or Theme.Caps("Свернуть")
	actionButton.Size = UDim2.new(0, back and BACK_W or ACTION_W, 0, ACTION_H)
	backIcon.Visible = back
	-- На корневой странице кнопка — «Свернуть», и есть она только в аркаде. В лобби
	-- сворачивать некуда. Во время забега первый пункт меню — «Продолжить» — уже делает
	-- ровно то же (hideMenu), а две кнопки с разными надписями для одного действия путают.
	actionButton.Visible = name ~= "root" or (inArcade and not inRun)
	-- Без кнопки плутоний встаёт в угол сам, а не висит над пустым местом.
	plutoniumBox.Position = UDim2.new(1, actionButton.Visible and -(actionButton.Size.X.Offset + 16) or 0, 0, plutoniumBox.Position.Y.Offset)

	if name == "journal" then
		journal.Open()
	else
		journal.Close()
	end

	if name == "settings" then
		settings.Open()
	else
		settings.Close()
	end

	if name == "journal" then
		pathLabel.Text = "> " .. Theme.Caps("Журнал")
		setStatus("Журнал", journal.Status())
	elseif name == "settings" then
		pathLabel.Text = "> " .. Theme.Caps("Настройки")
		setStatus("Настройки", settings.status)
	else
		pathLabel.Text = "> " .. Theme.Caps(inRun and "забег идёт" or "лобби")
		setStatus("Главное меню", rootHint())
	end

	Theme.SetScene(screen, name == "root" and "menu" or name)
	-- Помеха при смене страницы — только когда меню на экране: страницу выставляют
	-- и у закрытого меню.
	if screenGui.Enabled then
		Theme.Static()
	end
end

local function hideMenu()
	screenGui.Enabled = false
end

local function showMenu()
	screenGui.Enabled = true
	showPage("root")
	Theme.Open(frame)
end

-- Меню закрывается сразу по нажатию, не дожидаясь ответа сервера. Если сервер
-- откажет (забег или аркада так и не начнутся), игрок остался бы в лобби без меню —
-- а свернуть его там и вызвать обратно нельзя. Поэтому через несколько секунд
-- без забега и аркады меню возвращается само. Забег сообщает о себе за секунду (WaveRunner).
local ENTER_TIMEOUT = 8
local function returnIfNotEntered()
	task.delay(ENTER_TIMEOUT, function()
		if not canHide() and not screenGui.Enabled then
			showMenu()
		end
	end)
end

-- ---- Сами пункты ----

local playItem = addItem("Play", "Играть", function()
	if inRun then
		-- Забег уже идёт: меню открыли посреди игры, и первый пункт — просто выход
		-- обратно. Серверу тут сообщать нечего.
		hideMenu()
		return
	end
	-- Какой уровень и можно ли в него войти — решает сервер (WaveRunner.enterLevel).
	-- Меню закрывается сразу, не дожидаясь ответа, а при отказе вернётся само
	-- (returnIfNotEntered) — это честнее, чем замершее меню на время круга до сервера.
	RequestEnterLevelRemote:FireServer()
	hideMenu()
	returnIfNotEntered()
end)

-- Аркада — отдельный режим, не часть забега: доступна и открыта отдельно от него.
-- Пункт меняет надпись так же, как «Играть» во время забега (setInArcade ниже) —
-- один и тот же приём для двух независимых состояний.
local arcadeItem = addItem("Arcade", "Аркада", function()
	if inRun then
		-- Забег идёт своей ареной и своим персонажем — прыгать в аркаду поверх него не даём.
		return
	end
	if inArcade then
		RequestExitArcadeRemote:FireServer()
	else
		RequestEnterArcadeRemote:FireServer()
	end
	hideMenu()
	returnIfNotEntered()
end)

addItem("Journal", "Журнал", function()
	showPage("journal")
end)

addItem("Settings", "Настройки", function()
	showPage("settings")
end)

for _, item in items do
	item.button.MouseButton1Click:Connect(function()
		selectItem(item.index)
		item.action()
	end)
	-- Наведение передвигает каретку: иначе мышь и стрелки показывали бы разный выбор
	-- одновременно, и непонятно, что сработает по Enter.
	item.button.MouseEnter:Connect(function()
		selectItem(item.index)
	end)
end

actionButton.MouseButton1Click:Connect(function()
	if page == "root" then
		if canHide() then
			hideMenu()
		end
	else
		showPage("root")
	end
end)

-- Высота пункта считается от того, что реально осталось под колонку, а не берётся числом.
-- Игра альбомная: на телефоне высоты всего триста с небольшим пикселей, и вычесть из неё
-- надо ещё и полосу Roblox сверху, высота которой у каждого устройства своя. Ниже MIN_TAP
-- не опускаемся: пункт, в который не попасть пальцем, хуже пункта, уехавшего за край.
local function fitItems()
	if #items == 0 then
		return
	end
	local available = menuHolder.AbsoluteSize.Y
	if available < 40 then
		return -- до первой отрисовки размера ещё нет
	end
	local height = math.floor((available - BTN_GAP * (#items - 1)) / #items)
	height = math.clamp(height, MobileUI.MIN_TAP, BTN_H)
	for _, item in items do
		item.button.Size = UDim2.new(1, 0, 0, height)
	end

	-- Сводка в правой колонке прячется, если ей не хватает высоты: на низком
	-- альбомном экране строки запуска и пять строк сводки друг под друга не встают,
	-- а обрезанная по нижнему краю сводка хуже отсутствующей: число видно наполовину.
	summary.Visible = available - SUMMARY_Y >= SUMMARY_H
end

-- Подписка на размер САМОЙ колонки, а не рамки и не вьюпорта. На ПК окно игры
-- может не менять размер ни разу за сессию, и подгонка только на OnViewportChanged
-- не сработала бы ни разу: единственный вызов приходится на момент с нулевым
-- AbsoluteSize. Но и подписки на рамку мало: в момент её события движок ещё не
-- пересчитал детей, и fitItems читал СТАРУЮ высоту колонки — замерено: рамка
-- сжата до 700x250, тело стало 84 пикселя, а пункты остались по 54 и сводка не убралась.
-- Событие самой колонки приходит уже с новым числом и покрывает все случаи сразу:
-- и первую отрисовку (0 → размер), и поворот, и смену полосы Roblox.
menuHolder:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitItems)

-- ============ Кнопка вызова ============

-- Свой ScreenGui на слое Controls: он должен оставаться видным тогда, когда само меню
-- выключено целиком, а значит внутри screenGui ему места нет.
local openGui = Instance.new("ScreenGui")
openGui.Name = "MainMenuButton"
openGui.ResetOnSpawn = false
openGui.DisplayOrder = MobileUI.Layer.Controls
openGui.Parent = playerGui

local openButton = Instance.new("TextButton")
-- Правый верхний угол под кнопкой инвентаря: левый верхний занят показаниями
-- забега и плутонием, низ — панелью стройки. Место в столбце считает MobileUI:
-- раньше этот скрипт брал угол своим числом и на телефоне накрывал кнопку инвентаря.
MobileUI.TopRight(openButton, MobileUI.CornerSlot.Menu)
openButton.FontFace = Theme.font.strong
openButton.TextSize = mobile and 12 or 13
openButton.Text = Theme.Caps("Меню")
openButton.Parent = openGui
Theme.Button(openButton, "ghost")

openButton.MouseButton1Click:Connect(showMenu)

-- Кнопка вызова прячется, пока меню открыто: иначе она висела бы поверх
-- собственного меню... точнее, под ним — и нажатие ничего бы не давало.
screenGui:GetPropertyChangedSignal("Enabled"):Connect(function()
	openGui.Enabled = not screenGui.Enabled
end)


-- ============ Запуск: строки и курсор ============

-- Обрезка по буквам, а не по байтам: в UTF-8 кириллическая буква занимает два байта,
-- и string.sub по нечётному числу разрезал бы её пополам — вместо текста получился бы
-- мусор на каждом втором кадре печати.
local function utf8Prefix(text, letters)
	local offset = utf8.offset(text, letters + 1)
	if not offset then
		return text
	end
	return text:sub(1, offset - 1)
end

local BOOT_LINES = {
	"ТЕРМИНАЛ ЛАБОРАТОРИИ",
	"ОПЕРАТОР: " .. Theme.Caps(player.DisplayName),
	"СИСТЕМА ГОТОВА",
}

local bootDone = false
local cursorOn = true

local function bootText(lines, cursor)
	local shown = table.concat(lines, "\n")
	if cursor then
		return shown .. "█"
	end
	return shown
end

-- Запуск играется ОДИН раз за сессию, а не на каждом открытии меню: красиво в первый
-- раз и раздражает в десятый, когда игрок просто вернулся из забега. При выключенном
-- движении интерфейса строки появляются сразу целиком.
local function runBoot()
	if bootDone then
		return
	end
	bootDone = true

	if not Settings.Get("uiMotion") then
		bootLabel.Text = bootText(BOOT_LINES, false)
		return
	end

	task.spawn(function()
		local shown = {}
		for _, text in BOOT_LINES do
			table.insert(shown, "")
			local letters = utf8.len(text) or #text
			for i = 1, letters do
				shown[#shown] = utf8Prefix(text, i)
				bootLabel.Text = bootText(shown, true)
				task.wait(0.018)
			end
			task.wait(0.12)
		end
		bootLabel.Text = bootText(shown, cursorOn)
	end)
end

-- Мигающий курсор после последней строки запуска. Отдельный цикл, а не часть печати:
-- печать кончается, а мигать должно всё время, пока меню открыто.
task.spawn(function()
	while true do
		task.wait(0.5)
		cursorOn = not cursorOn
		if screenGui.Enabled and page == "root" and bootLabel.Text ~= "" and Settings.Get("uiMotion") then
			local typed = bootLabel.Text:gsub("█$", "")
			bootLabel.Text = cursorOn and (typed .. "█") or typed
		end
	end
end)

-- Развёртка кинескопа. По высоте экрана, а не по числу в пикселях: на телефоне и на
-- мониторе полоса должна проходить экран за одно и то же время.
local sweepPhase = 0

RunService.Heartbeat:Connect(function(dt)
	if not screenGui.Enabled then
		return
	end
	if not Settings.Get("uiMotion") then
		sweep.Visible = false
		return
	end
	sweep.Visible = true
	sweepPhase = (sweepPhase + dt / 6) % 1.25
	sweep.Position = UDim2.new(0, 0, sweepPhase - 0.15, 0)
end)

-- ============ Управление с клавиатуры ============

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return -- игрок пишет в чат или в поле промокода — это не команда меню
	end

	if input.KeyCode == Enum.KeyCode.M then
		if screenGui.Enabled then
			if canHide() then
				hideMenu()
			end
		else
			showMenu()
		end
		return
	end

	if not screenGui.Enabled then
		return
	end

	if input.KeyCode == Enum.KeyCode.Backspace then
		if page ~= "root" then
			showPage("root")
		end
		return
	end

	if page ~= "root" then
		return -- стрелки внутри журнала и настроек список пунктов не двигают
	end

	if input.KeyCode == Enum.KeyCode.Up or input.KeyCode == Enum.KeyCode.W then
		selectItem(selected - 1)
	elseif input.KeyCode == Enum.KeyCode.Down or input.KeyCode == Enum.KeyCode.S then
		selectItem(selected + 1)
	elseif input.KeyCode == Enum.KeyCode.Return or input.KeyCode == Enum.KeyCode.KeypadEnter then
		local item = items[selected]
		if item then
			item.action()
		end
	end
end)

-- ============ Состояние игры ============

local function setInRun(value)
	inRun = value
	-- Первый пункт меняет смысл вместе с надписью: во время забега он не начинает
	-- новый, а просто возвращает к игре (см. его обработчик).
	playItem.name = value and "Продолжить" or "Играть"
	paintItems()
	if screenGui.Enabled and page == "root" then
		showPage("root")
	end
end

Remotes.WaveReady.OnClientEvent:Connect(function()
	setInRun(true)
	hideMenu()
end)

Remotes.WaveChanged.OnClientEvent:Connect(function()
	setInRun(true)
	hideMenu()
end)

Remotes.RunEnded.OnClientEvent:Connect(function()
	setInRun(false)
	showMenu()
end)

local function setInArcade(value)
	inArcade = value
	arcadeItem.name = value and "Выйти из аркады" or "Аркада"
	paintItems()
	if screenGui.Enabled and page == "root" then
		showPage("root")
	end
end

ArcadeEnteredRemote.OnClientEvent:Connect(function()
	setInArcade(true)
end)

ArcadeExitedRemote.OnClientEvent:Connect(function()
	setInArcade(false)
	showMenu()
end)

ProfileSyncedRemote.OnClientEvent:Connect(function(plutonium)
	plutoniumLabel.Text = tostring(plutonium or 0)
end)

-- ============ Старт ============

selectItem(1)
showMenu()
-- Строки запуска печатаются, когда экран загрузки (ReplicatedFirst.LoadingScreen) уже
-- снят: иначе они допечатались бы за ним, и игрок их не увидел бы.
task.spawn(function()
	local loading = playerGui:FindFirstChild("LoadingScreen")
	if loading then
		while loading.Parent do
			loading.AncestryChanged:Wait()
		end
	end
	runBoot()
end)
