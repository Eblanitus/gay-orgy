-- Отдельное окно "что у меня есть": в отличие от списков в CraftingUI (стол крафта) и
-- ElementPicker в TowerInteraction (заливка в башню), это окно не привязано ни к какому
-- ProximityPrompt и никуда элемент не выбирает — только показывает инвентарь. Открывается
-- в любой момент клавишей I или кнопкой в углу экрана.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local MobileUI = require(script.Parent:WaitForChild("MobileUI"))
local Theme = require(script.Parent:WaitForChild("UITheme"))

local Elements = require(ReplicatedStorage:WaitForChild("Elements"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local InventoryChanged = Remotes:WaitForChild("InventoryChanged")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local inventory = {} -- elementKey -> count, приходит целиком по InventoryChanged (см. CraftingUI)

-- ============ Каркас окна ============

local gui = Instance.new("ScreenGui")
gui.Name = "InventoryUI"
gui.ResetOnSpawn = false
gui.DisplayOrder = MobileUI.Layer.Window
-- Окно во весь экран обязано закрывать и полосу Roblox сверху (то же самое в CraftingUI):
-- без этого над окном оставалась щель с ареной в 58 пикселей.
gui.IgnoreGuiInset = true
gui.Parent = playerGui

local root = Instance.new("Frame")
-- Ширина долей экрана, центрирование через AnchorPoint: посчитанный один раз отступ
-- -rootW/2 после поворота телефона описывал уже другой экран, и окно уезжало из центра.
-- Высота — по числу строк инвентаря (applyHeight ниже), а не долей экрана: с двумя
-- элементами окно во полэкрана стояло почти пустым.
local ROW_H = MobileUI.isMobile and 48 or 34
local ROW_GAP = 6
-- Шапка выросла на подпись раздела с линией — та же разметка, что и в Лаборатории.
local SECTION_H = 16
local MARGIN = 16
-- Отступ внутри рамки окна: всё содержимое считается от него, а не каждое от своего.
local INNER = MobileUI.isMobile and 12 or 18
-- Шапка и подвал внутри рамки — те же три полосы, что и в главном меню:
-- заголовок, линия, подпись раздела — и строка состояния внизу.
local HEADER_H = INNER + 70
-- Подвал выше угловой засечки окна: та стоит в шести пикселях от края
-- (Theme.BRACKET), и при подвале в 26 строка состояния ложилась ровно на неё —
-- засечка подчёркивала первое слово «ИНВЕНТАРЬ».
local FOOTER_H = 34
-- На телефоне крестик больше: 44x44 — вдвое меньше пальца, а другого способа
-- закрыть окно там нет (клавиши I нет, кнопка-переключатель оказывается под окном).
local CLOSE_SIZE = MobileUI.isMobile and 44 or 28
-- Ширину занимает само содержимое: список идёт сеткой в несколько колонок
-- (Theme.Grid), а ячейка остаётся читаемой ширины. То же число, что в Лаборатории:
-- потолок нужен только ради сверхшироких экранов.
local CONTENT_MAX = 1400

-- Окно во весь экран (решение автора, задача #104): счёт высоты по числу строк
-- (applyHeight) вместе с потолком от рабочей высоты больше не нужен.
root.AnchorPoint = Vector2.new(0, 0)
root.Size = UDim2.new(1, 0, 1, 0)
root.Position = UDim2.new(0, 0, 0, 0)
root.Visible = false
root.Parent = gui

-- Инвентарь открывается поверх игры, но под всеми карточками — решётка чуть ближе
-- журнала Лаборатории и дальше всего остального (см. Theme.depth).
Theme.Panel(root, { scene = "inventory" })

-- Само окно — рамка внутри полноэкранной подложки, а не сама подложка.
--
-- До этого шапка (заголовок и крестик) шла во всю ширину экрана, а список был ограничен
-- CONTENT_MAX и стоял по центру. На мониторе 1914 это заголовок в шестнадцати пикселях
-- от края и первая ячейка под ним в двухстах шестидесяти — две разные левые границы
-- в одном окне. Теперь колонка одна на всё, и шапка стоит ровно над содержимым.
--
-- На телефоне ничего не сдвинулось: там CONTENT_MAX больше экрана, и колонка как была,
-- так и осталась шириной во весь экран за вычетом MARGIN.
local window = Instance.new("Frame")
window.Name = "Window"
window.AnchorPoint = Vector2.new(0.5, 0)
window.BackgroundTransparency = 1
window.BorderSizePixel = 0
window.Parent = root

local windowLimit = Instance.new("UISizeConstraint")
windowLimit.MaxSize = Vector2.new(CONTENT_MAX, math.huge)
windowLimit.Parent = window

Theme.Corner(window, Theme.radius.panel)
Theme.Stroke(window, Theme.color.frame, 1, 0)
Theme.Brackets(window)

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -(CLOSE_SIZE + INNER * 2 + 8), 0, 30)
title.BackgroundTransparency = 1
title.TextSize = 22
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = "Инвентарь"
title.Parent = window

Theme.Title(title)

-- Линия под шапкой и линия над подвалом: без них окно — одно чёрное поле,
-- на котором в разных местах лежит текст.
local headerRule = Instance.new("Frame")
headerRule.Size = UDim2.new(1, -INNER * 2, 0, 1)
headerRule.Parent = window
Theme.Rule(headerRule)

local footerRule = Instance.new("Frame")
footerRule.Size = UDim2.new(1, -INNER * 2, 0, 1)
footerRule.Parent = window
Theme.Rule(footerRule)

local statusLabel = Instance.new("TextLabel")
statusLabel.Size = UDim2.new(1, -INNER * 2, 0, 16)
statusLabel.TextSize = MobileUI.isMobile and 10 or 12
statusLabel.Parent = window
Theme.Status(statusLabel, "инвентарь", "элементы живут один забег и пропадают в конце")

local closeButton = Instance.new("TextButton")
closeButton.Size = UDim2.new(0, CLOSE_SIZE, 0, CLOSE_SIZE)
closeButton.Parent = window

-- Красный, как и в Лаборатории: на телефоне крестик — единственный выход из окна
-- (клавиши I там нет, а кнопка-переключатель оказывается под окном).
Theme.CloseButton(closeButton)

-- ============ Список элементов ============

local sectionLabel = Instance.new("TextLabel")
sectionLabel.Size = UDim2.new(1, -INNER * 2, 0, SECTION_H)
sectionLabel.TextSize = 11
sectionLabel.Parent = window

Theme.Section(sectionLabel, "элементы", 0)

-- Потолка ширины у списка больше нет: его держит само окно. Обёртка осталась
-- ради карточки «пусто»: refreshList зовёт list:ClearAllChildren() на каждый приход
-- инвентаря, и всё, что лежит внутри списка, сносится первым же обновлением.
local listWrap = Instance.new("Frame")
listWrap.BackgroundTransparency = 1
listWrap.BorderSizePixel = 0
listWrap.Parent = window

local list = Instance.new("ScrollingFrame")
list.Size = UDim2.new(1, 0, 1, 0)
list.BackgroundTransparency = 1
list.BorderSizePixel = 0
list.ScrollBarThickness = 6
list.AutomaticCanvasSize = Enum.AutomaticSize.Y
list.CanvasSize = UDim2.new(0, 0, 0, 0)
list.Parent = listWrap

Theme.Scroller(list)
Theme.DragScroll(list)

-- «Пусто» — карточка по центру свободного места, а не строчка в углу списка. Окно
-- теперь во весь экран, и подпись в четырнадцать пикселей где-то слева сверху терялась
-- в нём совершенно — пустой инвентарь читался как не открывшееся окно.
--
-- Лежит рядом со списком, а не внутри него: внутри её сносил бы каждый ClearAllChildren,
-- а собирать её заново на каждый приход инвентаря незачем.
local emptyCard = Instance.new("Frame")
emptyCard.Name = "Empty"
emptyCard.AnchorPoint = Vector2.new(0.5, 0.5)
emptyCard.Position = UDim2.new(0.5, 0, 0.5, 0)
emptyCard.Size = UDim2.new(0, MobileUI.isMobile and 300 or 380, 0, 0)
emptyCard.AutomaticSize = Enum.AutomaticSize.Y
emptyCard.Visible = false
emptyCard.Parent = listWrap

-- Без решётки (depth = false): она не строится на плашках с AutomaticSize вовсе
-- (см. Theme.Backdrop), и просить её здесь — тихий холостой вызов.
Theme.Panel(emptyCard, { color = Theme.color.panelSoft, depth = false })

local emptyPad = Instance.new("UIPadding")
emptyPad.PaddingTop = UDim.new(0, 16)
emptyPad.PaddingBottom = UDim.new(0, 16)
emptyPad.PaddingLeft = UDim.new(0, 18)
emptyPad.PaddingRight = UDim.new(0, 18)
emptyPad.Parent = emptyCard

local emptyList = Instance.new("UIListLayout")
emptyList.SortOrder = Enum.SortOrder.LayoutOrder
emptyList.Padding = UDim.new(0, 6)
emptyList.Parent = emptyCard

local emptyTitle = Instance.new("TextLabel")
emptyTitle.LayoutOrder = 1
emptyTitle.Size = UDim2.new(1, 0, 0, 20)
emptyTitle.BackgroundTransparency = 1
emptyTitle.FontFace = Theme.font.strong
emptyTitle.TextSize = 15
emptyTitle.TextXAlignment = Enum.TextXAlignment.Left
emptyTitle.TextColor3 = Theme.color.textDim
emptyTitle.Text = Theme.Caps("пусто")
emptyTitle.Parent = emptyCard

local emptyText = Instance.new("TextLabel")
emptyText.LayoutOrder = 2
emptyText.Size = UDim2.new(1, 0, 0, 0)
emptyText.AutomaticSize = Enum.AutomaticSize.Y
emptyText.BackgroundTransparency = 1
emptyText.FontFace = Theme.font.body
emptyText.TextSize = 13
emptyText.TextWrapped = true
emptyText.TextXAlignment = Enum.TextXAlignment.Left
emptyText.TextYAlignment = Enum.TextYAlignment.Top
emptyText.TextColor3 = Theme.color.textMute
emptyText.Text = "Купите базовый элемент в Лаборатории за материю или скрестите два уже имеющихся."
emptyText.Parent = emptyCard

-- Окно меняет ширину вместе с экраном, а число колонок считается от неё.
list:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
	local layout = list:FindFirstChildOfClass("UIGridLayout")
	if layout then
		Theme.GridFit(layout)
	end
end)

-- Всё, что считается от верхней полосы Roblox, собрано в одном месте и пересчитывается
-- на смену экрана — тот же applyChrome, что и в Лаборатории.
local function applyChrome()
	local top = MobileUI.TopInset
	local gap = MobileUI.isMobile and 8 or 12

	-- Сама рамка отступает от края экрана и от полосы Roblox сверху; всё остальное
	-- считается уже от неё и про эту полосу ничего не знает.
	window.Position = UDim2.new(0.5, 0, 0, top + gap)
	window.Size = UDim2.new(1, -MARGIN * 2, 1, -(top + gap * 2))

	title.Position = UDim2.new(0, INNER, 0, INNER)
	-- Крестик на телефоне выше самой строки заголовка (44 против 30), поэтому
	-- поднимается на разницу половин, чтобы стоять с ней по одной оси.
	closeButton.Position = UDim2.new(1, -(CLOSE_SIZE + INNER), 0, INNER - (CLOSE_SIZE - 30) / 2)
	headerRule.Position = UDim2.new(0, INNER, 0, INNER + 38)
	sectionLabel.Position = UDim2.new(0, INNER, 0, INNER + 48)

	listWrap.Position = UDim2.new(0, INNER, 0, HEADER_H)
	listWrap.Size = UDim2.new(1, -INNER * 2, 1, -(HEADER_H + FOOTER_H))

	footerRule.Position = UDim2.new(0, INNER, 1, -(FOOTER_H - 2))
	statusLabel.Position = UDim2.new(0, INNER, 1, -(FOOTER_H - 6))
end

MobileUI.OnViewportChanged(applyChrome)

-- Тот же фильтр (count > 0) и та же сортировка (ярус, потом имя), что в
-- CraftingUI.refreshInventoryList и TowerInteraction.refreshElementList — список
-- пересобирается целиком на каждый InventoryChanged.
local function refreshList()
	list:ClearAllChildren() -- вместе со строками сносит и раскладку, поэтому сетка собирается заново
	-- Сетка, а не колонка: окно во весь экран, и сорок элементов одной колонкой —
	-- это двенадцать видимых строк и прокрутка при пустых боках.
	local layout = Theme.Grid(list, ROW_H, 320, ROW_GAP)

	local keys = {}
	for key, count in inventory do
		if count > 0 then
			table.insert(keys, key)
		end
	end
	table.sort(keys, function(a, b)
		local tierA, tierB = Elements[a].tier or 0, Elements[b].tier or 0
		if tierA ~= tierB then
			return tierA < tierB
		end
		return Elements[a].name < Elements[b].name
	end)

	Theme.Section(sectionLabel, "элементы", #keys)

	emptyCard.Visible = #keys == 0
	if #keys == 0 then
		return
	end

	for i, key in keys do
		local data = Elements[key]

		local row = Instance.new("Frame")

		row.LayoutOrder = i
		row.Parent = list

		-- Цветной блок с номером слева, дымка по строке, тёмный корпус и кант — тот же
		-- язык, что в списках Лаборатории и в выборе заливки в башню.
		Theme.ElementFill(row, data.color, { wide = true, element = key })

		-- Имя и счётчик лежат в одной начинке во всю строку, а не каждый на своём клочке:
		-- отступ от канта и от засечки считается один раз.
		local content = Instance.new("Frame")
		content.Parent = row
		Theme.Inner(content)

		local nameLabel = Instance.new("TextLabel")
		nameLabel.Size = UDim2.new(1, -72, 1, 0)
		nameLabel.Position = UDim2.new(0, 0, 0, 0)
		nameLabel.BackgroundTransparency = 1
		nameLabel.FontFace = Theme.font.strong
		nameLabel.TextSize = 15
		nameLabel.TextColor3 = Theme.color.text
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
		nameLabel.Text = Theme.Caps(data.name)
		nameLabel.Parent = content

		local countLabel = Instance.new("TextLabel")
		countLabel.AnchorPoint = Vector2.new(1, 0)
		countLabel.Size = UDim2.new(0, 64, 1, 0)
		countLabel.Position = UDim2.new(1, -4, 0, 0)
		countLabel.BackgroundTransparency = 1
		countLabel.FontFace = Theme.font.strong
		countLabel.TextSize = 15
		countLabel.RichText = true
		countLabel.TextXAlignment = Enum.TextXAlignment.Right
		-- Подпись «шт» вдвое мельче самого числа, число — цветом элемента: заливок
		-- в полную силу больше нет, и цвету нужно второе место в строке помимо засечки.
		countLabel.Text = Theme.Readout("шт", inventory[key], Theme.Legible(data.color), 10)
		countLabel.Parent = content
	end

end

-- ============ Кнопка-переключатель и клавиша I ============

local toggleButton = Instance.new("TextButton")
toggleButton.Name = "InventoryToggle"
-- На мобильном кнопка квадратная с текстом-ярлыком (палец не промахнётся), на ПК
-- остаётся прежней широкой кнопкой с подписью про клавишу I. Угол и высоту считает
-- MobileUI.TopRight: под этой кнопкой стоит кнопка меню из другого скрипта, и оба
-- числа должны браться из одного места.
MobileUI.TopRight(toggleButton, MobileUI.CornerSlot.Inventory)
if MobileUI.isMobile then
	toggleButton.Text = "I"
	toggleButton.TextSize = 20
else
	toggleButton.Text = "ИНВЕНТАРЬ (I)"
	toggleButton.TextSize = 15
end
toggleButton.FontFace = Theme.font.strong
-- Кнопка-переключатель живёт на слое HUD, а не вместе с самим окном: окно теперь
-- во весь экран, и в общем ScreenGui кнопка ложилась поверх него и закрывала крестик.
-- Со слоя Hud её накрывает любое окно — и своё, и Лаборатория.
local toggleGui = Instance.new("ScreenGui")
toggleGui.Name = "InventoryToggle"
toggleGui.ResetOnSpawn = false
toggleGui.DisplayOrder = MobileUI.Layer.Hud
toggleGui.Parent = playerGui

toggleButton.Parent = toggleGui

Theme.Button(toggleButton, "ghost")

-- Открытие сбрасывает прокрутку списка — тот же фикс, что и в TowerInteraction.openPicker,
-- иначе окно может открыться промотанным вниз с прошлого раза.
local function setOpen(open)
	root.Visible = open
	if open then
		-- Шапка пересчитывается на каждом открытии: на первых кадрах клиента
		-- высота полосы Roblox ещё нулевая, и окно, собранное в этот момент, осталось бы
		-- с заголовком под кнопками Roblox навсегда. Открывают окно гораздо позже.
		applyChrome()
		list.CanvasPosition = Vector2.new(0, 0)
		Theme.Open(root)
		Theme.Static()
	end
end

toggleButton.MouseButton1Click:Connect(function()
	setOpen(not root.Visible)
end)

closeButton.MouseButton1Click:Connect(function()
	setOpen(false)
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.KeyCode == Enum.KeyCode.I then
		setOpen(not root.Visible)
	end
end)

-- ============ Подключение к серверу ============

InventoryChanged.OnClientEvent:Connect(function(counts)
	inventory = counts
	refreshList()
end)

refreshList()
