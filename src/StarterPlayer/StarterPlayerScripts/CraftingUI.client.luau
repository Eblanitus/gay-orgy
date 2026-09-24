-- Интерфейс стола крафта (задача #23, v3). До этой задачи Crafting/Inventory работали только
-- через прямые вызовы remote-ов — окна с двумя слотами, подтверждением и справочником не было,
-- и скрестить руками в игре было нельзя.
--
-- Клиент только просит и отображает: решения (хватает ли элементов, есть ли такой рецепт)
-- всегда принимает сервер (Crafting/Inventory на ServerScriptService).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ProximityPromptService = game:GetService("ProximityPromptService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")
local TextService = game:GetService("TextService")

local MobileUI = require(script.Parent:WaitForChild("MobileUI"))
local Theme = require(script.Parent:WaitForChild("UITheme"))
local Graph = require(script.Parent:WaitForChild("RecipeGraph"))
local Settings = require(script.Parent:WaitForChild("Settings"))
-- Подписи свойств элемента для плитки покупки — те же, что в справочниках журнала.
local EntityInfo = require(script.Parent:WaitForChild("EntityInfo"))

local Elements = require(ReplicatedStorage:WaitForChild("Elements"))
local Recipes = require(ReplicatedStorage:WaitForChild("Recipes"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RequestCraft = Remotes:WaitForChild("RequestCraft")
local RequestBuyElement = Remotes:WaitForChild("RequestBuyElement")
local RecipeLearned = Remotes:WaitForChild("RecipeLearned")
local InventoryChanged = Remotes:WaitForChild("InventoryChanged")
local MatterChanged = Remotes:WaitForChild("MatterChanged")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local BASE_ORDER = { "Fire", "Water", "Earth", "Air" }

local inventory = {} -- elementKey -> count, приходит целиком по InventoryChanged
local knownRecipes = {} -- resultKey -> true, копится по RecipeLearned + досылке при входе

-- ============ Каркас окна ============

local gui = Instance.new("ScreenGui")
gui.Name = "CraftingUI"
gui.ResetOnSpawn = false
gui.DisplayOrder = MobileUI.Layer.Window
-- Окно во весь экран обязано закрывать и полосу Roblox сверху, иначе над ним остаётся
-- щель с ареной в 58 пикселей — окном во весь экран это не выглядит (замечание автора,
-- задача #105). Сама полоса прозрачная и занята только слева, так что шапка
-- окна садится прямо в неё, справа от кнопок Roblox: см. applyChrome.
gui.IgnoreGuiInset = true
gui.Enabled = false
gui.Parent = playerGui

local root = Instance.new("Frame")
-- Окно во весь экран (решение автора, задача #104). Вместе с этим ушёл весь счёт
-- высоты по содержимому вкладки (applyHeight/tabContentHeight): размер теперь задаёт
-- экран, а внутренние списки и так скроллятся. Заодно пропала целая семья граблей
-- с потолком высоты и поворотом телефона.
root.AnchorPoint = Vector2.new(0, 0)
root.Size = UDim2.new(1, 0, 1, 0)
root.Position = UDim2.new(0, 0, 0, 0)
root.Parent = gui

local MARGIN = 16
-- Полоса заголовка: название окна слева, счётчик материи и крестик справа.
local TITLE_H = 46
-- Низ окна: статусная строка. Подсказки раньше стояли внутри самих вкладок
-- и отъедали высоту у списков — в сумме окно ничего не потеряло.
local FOOTER_H = 26
-- На телефоне вкладки выше: 30px — половина пальца.
local TAB_H = MobileUI.isMobile and 36 or 30
local TAB_W = 148 -- на телефоне вкладки делят ширину поровну, там это число не нужно
-- Ширина содержимого. Потолок в 760 (задача #105) решал верную беду — строку
-- в полтора метра с двумя словами по краям — неверным способом: окно стало колонкой
-- по центру и чёрными полями по бокам. Ширину занимает само содержимое: списки
-- идут сеткой в несколько колонок (Theme.Grid), а ячейка остаётся читаемой ширины.
--
-- Было 1400, и на экране 1920 тот же потолок оставлял по 244 пикселя чёрного
-- с каждой стороны (замечание автора со скриншотом). 2400 на обычном мониторе
-- не срабатывает вовсе — окно занимает всю ширину, — а на сверхшироком всё ещё не даёт
-- строке растянуться на весь стол.
local CONTENT_MAX = 2400

-- Самое дальнее окно в стопке: внутри лежит журнал, и поверх него открывается всё
-- остальное — поэтому решётка здесь самая редкая, тёмная и медленная (см. Theme.depth).
Theme.Panel(root, { scene = "lab" })

-- Кнопки шапки и карты висят теперь не над глухим полем окна, а над самой картой,
-- и сплошная заливка вырезала бы из неё прямоугольные дыры. Сборщик тот же, что
-- у всех кнопок игры (углы, кант, наведение — из Theme.Button), но заливка и кант
-- чуть разбавлены: сквозь плашку видно, что под ней продолжается рисунок.
-- Выбранная вкладка остаётся почти сплошной — это единственный цвет в полную силу
-- во всём окне, и прозрачность съела бы ровно то, ради чего он там стоит.
local function chromeButton(button, kind)
	Theme.Button(button, kind)
	button.BackgroundTransparency = kind == "active" and 0.06 or 0.18
	local edge = button:FindFirstChildOfClass("UIStroke")
	if edge then
		edge.Transparency = 0.15
	end
	return button
end

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, MobileUI.isMobile and -76 or -50, 0, 36)
title.BackgroundTransparency = 1
title.TextSize = 22
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = "Лаборатория"
title.Parent = root

Theme.Title(title)

local matterLabel = Instance.new("TextLabel")
-- Показание висит над картой, а не над глухим полем окна, и без своей плашки
-- цифры ложатся прямо на связи графа. Ширина — по тексту (AutomaticSize),
-- поэтому плашка не тянется пустой полосой влево и не наезжает на крестик,
-- как прежние фиксированные 160 пикселей.
matterLabel.AnchorPoint = Vector2.new(1, 0)
matterLabel.Size = UDim2.new(0, 0, 0, 24)
matterLabel.AutomaticSize = Enum.AutomaticSize.X
matterLabel.BackgroundColor3 = Theme.color.panel
matterLabel.BackgroundTransparency = 0.25
matterLabel.TextSize = 16
matterLabel.RichText = true
matterLabel.TextXAlignment = Enum.TextXAlignment.Right
matterLabel.Text = Theme.Readout("МАТЕРИЯ", "0", Theme.color.energy)
matterLabel.Parent = root

Theme.Corner(matterLabel, Theme.radius.mark)
Theme.Hairline(matterLabel, 0.5)

local matterPad = Instance.new("UIPadding")
matterPad.PaddingLeft = UDim.new(0, 10)
matterPad.PaddingRight = UDim.new(0, 10)
matterPad.Parent = matterLabel

-- Тот же вид показания, что и на панели забега: одна и та же материя в двух местах
-- интерфейса должна выглядеть одинаково.
Theme.Display(matterLabel)

local closeButton = Instance.new("TextButton")
-- Крестик — единственный выход из окна на телефоне, а 28x28 там меньше пальца.
-- 44, а не MIN_TAP = 48: выше не пускает полоса заголовка (TITLE_H = 46).
local CLOSE_SIZE = MobileUI.isMobile and 44 or 28
closeButton.Size = UDim2.new(0, CLOSE_SIZE, 0, CLOSE_SIZE)
closeButton.Parent = root

-- Знак, а не буква, и цвет отказа: на телефоне крестик — единственный выход из окна
-- (клавиши там нет), и тихая кнопка на тёмной шапке читалась бы как буква в воздухе.
-- Сборка — Theme.CloseButton.
Theme.CloseButton(closeButton)

closeButton.MouseButton1Click:Connect(function()
	gui.Enabled = false
end)

-- ============ Вкладки ============

local TAB_NAMES = { "Купить", "Крафт", "Справочник" }
-- Имя инстанса у кнопки вкладки. Без него все три зовутся TextButton, и путь
-- до нужной из проверки не записать вовсе — та же причина, по которой имена есть
-- у вкладок журнала и пунктов главного меню.
local TAB_ID = {
	["Купить"] = "TabBuy",
	["Крафт"] = "TabCraft",
	["Справочник"] = "TabBook",
}
local tabButtons = {}
local tabFrames = {}

-- Вкладки стоят полосой под заголовком — и на телефоне, и на ПК (решение автора,
-- задача #105). Вертикальная панель слева, поставленная в #103, была разумной,
-- пока окно было шириной 900; на весь экран она растянулась в пустую колонку
-- в 132 пикселя, от которой содержимое уехало вправо.
local tabBar = Instance.new("Frame")
tabBar.Name = "TabBar"
tabBar.AnchorPoint = Vector2.new(0.5, 0)
tabBar.Size = UDim2.new(1, -MARGIN * 2, 0, TAB_H)
tabBar.BackgroundTransparency = 1
tabBar.Parent = root
-- Стол, справочник и производитель — три отдельных предмета мебели (alchemy_td_location_v1.6.md):
-- каждый открывает только свой раздел (см. PromptTriggered внизу), и переключаться из окна
-- на чужой нельзя: купить элемент можно только у производителя. Полоса вкладок скрыта.
tabBar.Visible = false

-- Полоса вкладок держится той же колонки, что и содержимое: вкладка над своим списком,
-- а не над пустым полем справа от него.
local tabLimit = Instance.new("UISizeConstraint")
tabLimit.MaxSize = Vector2.new(CONTENT_MAX, math.huge)
tabLimit.Parent = tabBar

local tabLayout = Instance.new("UIListLayout")
tabLayout.FillDirection = Enum.FillDirection.Horizontal
tabLayout.Padding = UDim.new(0, 8)
tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
tabLayout.Parent = tabBar

-- Две линии делят окно на три полосы, как в референсе: заголовок — вкладки
-- и содержимое — статус. Верхняя идёт под заголовком, а не под вкладками:
-- вплотную к первой строке списка линия читалась как часть этой строки.
local headerRule = Instance.new("Frame")
headerRule.Size = UDim2.new(1, -MARGIN * 2, 0, 1)
headerRule.Parent = root

Theme.Rule(headerRule)

-- Линия шапки идёт теперь поверх карты и через весь экран резала бы рисунок пополам.
-- Слева, под самим интерфейсом, она в полную силу; вправо, где под ней только
-- карта, сходит на нет.
local ruleFade = Instance.new("UIGradient")
ruleFade.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0),
	NumberSequenceKeypoint.new(0.45, 0.3),
	NumberSequenceKeypoint.new(1, 1),
})
ruleFade.Parent = headerRule

local footerRule = Instance.new("Frame")
footerRule.AnchorPoint = Vector2.new(0, 1)
footerRule.Size = UDim2.new(1, -MARGIN * 2, 0, 1)
footerRule.Position = UDim2.new(0, MARGIN, 1, -(FOOTER_H - 4))
footerRule.Parent = root

Theme.Rule(footerRule)

local body = Instance.new("Frame")
-- Имя — как у тела главного меню: рядом с ним ещё две безымянных полоски-черты,
-- и путь вида CraftingUI.Frame.Frame.BuyTab был бы неоднозначным.
body.Name = "Body"
body.AnchorPoint = Vector2.new(0.5, 0)
body.BackgroundTransparency = 1
body.Parent = root

local bodyLimit = Instance.new("UISizeConstraint")
bodyLimit.MaxSize = Vector2.new(CONTENT_MAX, math.huge)
bodyLimit.Parent = body

-- Шапка рисуется поверх содержимого: body создан позже и без этого лёг бы на неё.
for _, above in { title, matterLabel, closeButton, headerRule, tabBar } do
	above.ZIndex = 5
end

-- Высота шапки нужна справочнику, чтобы вывести карту под неё ровно на столько.
local headerHeight = 0
local onChrome -- справочник вешает сюда пересчёт своей разметки

-- Всё, что считается от верхней полосы Roblox, собрано в одном месте и пересчитывается
-- на смену экрана: полоса выше на телефоне, а в полноэкранном режиме её нет вовсе,
-- и заголовок, посаженный на постоянное число, то лез бы под кнопки Roblox, то висел
-- бы под пустотой.
--
-- Сама полоса занята только слева — меню, чат, микрофон, — и Roblox сам говорит,
-- где его кнопки кончаются: GuiService.TopbarInset. Строка заголовка садится в полосу
-- справа от них, и 58 пикселей сверху перестают быть пустой лентой над окном
-- (замечание автора: «интерфейс не перенёс, чёрную полосу не убрал»).
local function applyChrome()
	local bar = GuiService.TopbarInset
	local strip = math.max(MobileUI.TopInset, bar.Height)
	-- Справа кнопок Roblox сейчас нет, но края полосы движутся — на то она и inset.
	local right = math.max(0, MobileUI.viewportX - (bar.Min.X + bar.Width))
	-- Влезет ли строка заголовка рядом с кнопками Roblox. На узком телефоне
	-- от полосы остаётся огрызок — там заголовок идёт под ней, как раньше.
	local inStrip = strip >= 40 and bar.Width >= 520
	local left = inStrip and math.max(MARGIN, bar.Min.X + MARGIN) or MARGIN
	local rowY = inStrip and math.floor((strip - 36) / 2) or (strip + 8)

	-- Заголовок шириной в экран нужен был, пока за ним было пустое поле окна.
	-- Теперь за ним вкладки, и метка считается по тексту — тем же замером через
	-- Enum.Font.RobotoMono, что и подписи разделов (Theme.Section).
	local titleW = math.ceil(TextService:GetTextSize(title.ContentText, title.TextSize,
		Enum.Font.RobotoMono, Vector2.new(4000, 60)).X)
	local titleEnd = left + titleW + 24
	-- Три этажа над картой — полоса Roblox, заголовок, вкладки — сами складывались
	-- в ту же ленту сверху, только из интерфейса. Если строка держит и заголовок,
	-- и вкладки, и показание справа — этаж остаётся один. На телефоне нет: там вкладки
	-- делят всю ширину поровну и в полосу не влезают ни по ширине, ни по высоте.
	local tabsW = TAB_W * #TAB_NAMES + 8 * (#TAB_NAMES - 1)
	local oneRow = inStrip and not MobileUI.isMobile and strip >= TAB_H + 8
		and (MobileUI.viewportX - right - titleEnd - tabsW) >= 280
	local tabsY = oneRow and math.floor((strip - TAB_H) / 2)
		or (inStrip and strip or (strip + TITLE_H))

	title.Position = UDim2.new(0, left, 0, rowY)
	title.Size = UDim2.new(0, titleW + 8, 0, 36)
	matterLabel.Position = UDim2.new(1, -(CLOSE_SIZE + 16 + right), 0, rowY + 6)
	closeButton.Position = UDim2.new(1, -(CLOSE_SIZE + 8 + right), 0, rowY + math.floor((36 - CLOSE_SIZE) / 2))

	if oneRow then
		tabBar.AnchorPoint = Vector2.new(0, 0)
		tabBar.Position = UDim2.new(0, titleEnd, 0, tabsY)
		tabBar.Size = UDim2.new(0, tabsW, 0, TAB_H)
	else
		tabBar.AnchorPoint = Vector2.new(0.5, 0)
		tabBar.Position = UDim2.new(0.5, 0, 0, tabsY)
		tabBar.Size = UDim2.new(1, -MARGIN * 2, 0, TAB_H)
	end

	if not tabBar.Visible then
		-- Вкладок нет — шапка кончается строкой заголовка, линия идёт под ней.
		headerHeight = math.max(strip, rowY + 36) + 10
		headerRule.Position = UDim2.new(0, MARGIN, 0, headerHeight - 6)
	else
		headerHeight = (oneRow and strip or (tabsY + TAB_H)) + 10
		-- В одну строку линия идёт под всей шапкой, в две — между заголовком и вкладками,
		-- как было: вплотную к первой строке списка она читалась как часть этой строки.
		headerRule.Position = UDim2.new(0, MARGIN, 0, oneRow and (headerHeight - 6) or (tabsY - 5))
	end
	body.Position = UDim2.new(0.5, 0, 0, headerHeight)
	body.Size = UDim2.new(1, -MARGIN * 2, 1, -(headerHeight + FOOTER_H))
	if onChrome then
		onChrome()
	end
end

-- Кнопки в полосе Roblox появляются и исчезают на ходу (чат, микрофон, значки),
-- а вместе с ними ездит и свободный кусок полосы — заголовок переезжает следом.
GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(applyChrome)

-- Статусная строка: что за раздел открыт и что в нём можно сделать. Одно место
-- на все три вкладки вместо трёх разных подсказок внутри каждой.
local TAB_STATUS = {
	["Купить"] = "цветная кнопка — купить элемент, экран — рулетка и апгрейдер",
	["Крафт"] = "клик по инвентарю — в слот, клик по слоту — очистить его",
	["Справочник"] = "нажмите элемент — покажу его цепочку; карта тянется рукой, «+», «−» и «[]» — масштаб",
}

local statusLabel = Instance.new("TextLabel")
statusLabel.AnchorPoint = Vector2.new(0, 1)
statusLabel.Size = UDim2.new(1, -MARGIN * 2, 0, 16)
statusLabel.Position = UDim2.new(0, MARGIN, 1, -6)
statusLabel.TextSize = 12
statusLabel.Parent = root

-- Своя обстановка у каждой вкладки (Theme.scene): покупка, скрещивание и карта
-- рецептов — три разных занятия, и фон меняется вместе с ними.
local TAB_SCENE = {
	["Купить"] = "shop",
	["Крафт"] = "craft",
	["Справочник"] = "lab",
}

local function selectTab(name)
	for tabName, frame in tabFrames do
		frame.Visible = (tabName == name)
		-- Список покупки — сам ScrollingFrame, и открываться он должен сверху, а не там,
		-- где его оставили в прошлый раз (тот же приём, что в InventoryUI.setOpen
		-- и TowerInteraction.openPicker).
		if frame.Visible and frame:IsA("ScrollingFrame") then
			frame.CanvasPosition = Vector2.new(0, 0)
		end
	end
	for tabName, btn in tabButtons do
		chromeButton(btn, tabName == name and "active" or "ghost")
	end
	Theme.Status(statusLabel, name, TAB_STATUS[name] or "")
	Theme.SetScene(root, TAB_SCENE[name] or "lab")
	-- У производителя своя шапка во всю ширину (вкладка «Купить»): общая шапка окна
	-- и строка статуса под ней не нужны.
	for _, inst in { title, matterLabel, closeButton, headerRule, footerRule, statusLabel } do
		inst.Visible = name ~= "Купить"
	end
	-- Помеха — только на глазах у игрока: первую вкладку выбирают ещё при сборке окна.
	-- У производителя общей помехи нет: его экран въезжает сбоку сам, а своя помеха —
	-- только по сменившейся ячейке апгрейдера (ProducerShow, Show.Noise).
	if gui.Enabled and name ~= "Купить" then
		Theme.Static()
	end
end

for i, name in TAB_NAMES do
	local btn = Instance.new("TextButton")
	btn.Name = TAB_ID[name] or name
	-- На телефоне вкладки делят ширину поровну: треть минус две трети промежутка,
	-- иначе три штуки по 0.33 плюс два промежутка по 8 не влезали в полосу и третья
	-- вылезала за край.
	btn.Size = MobileUI.isMobile and UDim2.new(1 / 3, -6, 1, 0) or UDim2.new(0, TAB_W, 1, 0)
	btn.LayoutOrder = i
	btn.FontFace = Theme.font.strong
	btn.TextSize = 15
	-- Заглавными, как и заголовок окна: вкладка — название раздела, а не фраза.
	-- Ключи tabFrames/tabButtons при этом остаются прежними (name) — меняется только надпись.
	btn.Text = Theme.Caps(name)
	btn.Parent = tabBar

	chromeButton(btn, "ghost")

	btn.MouseButton1Click:Connect(function()
		selectTab(name)
	end)
	tabButtons[name] = btn
end

MobileUI.OnViewportChanged(applyChrome)

-- Вкладка «Купить»: окно производителя поверх root — в модуле CraftingBuyTab.
local CraftingBuyTabExports = require(script.Parent:WaitForChild("CraftingBuyTab"))({Theme = Theme, root = root, tabFrames = tabFrames, ReplicatedStorage = ReplicatedStorage, Remotes = Remotes, BASE_ORDER = BASE_ORDER, Elements = Elements, RequestBuyElement = RequestBuyElement, inventory = inventory, gui = gui, InventoryChanged = InventoryChanged})
local buyFrame = CraftingBuyTabExports.buyFrame
local buyCountLabels = CraftingBuyTabExports.buyCountLabels
-- Экран производителя: режимы «Купить», «Рулетка», «Апгрейдер» (buildProducer) — в модуле CraftingProducer.
local CraftingProducerExports = require(script.Parent:WaitForChild("CraftingProducer"))({ReplicatedStorage = ReplicatedStorage, Remotes = Remotes, inventory = inventory, Theme = Theme, Elements = Elements, TextService = TextService, buyFrame = buyFrame, gui = gui, BASE_ORDER = BASE_ORDER, RequestBuyElement = RequestBuyElement, Settings = Settings, MobileUI = MobileUI, GuiService = GuiService, InventoryChanged = InventoryChanged})
-- Вкладка «Крафт»: слоты, кнопка, список инвентаря, подтверждение крафта — в модуле CraftingCraftTab.
local CraftingCraftTabExports = require(script.Parent:WaitForChild("CraftingCraftTab"))({body = body, tabFrames = tabFrames, MobileUI = MobileUI, Theme = Theme, Elements = Elements, Recipes = Recipes, knownRecipes = knownRecipes, inventory = inventory, root = root, RequestCraft = RequestCraft})
local refreshInventoryList = CraftingCraftTabExports.refreshInventoryList
-- Вкладка «Справочник»: граф рецептов — рисование, кривые, перемещение и масштаб карты — в модуле CraftingReference.
local CraftingReferenceExports = require(script.Parent:WaitForChild("CraftingReference"))({Theme = Theme, body = body, tabFrames = tabFrames, MobileUI = MobileUI, chromeButton = chromeButton, Elements = Elements, knownRecipes = knownRecipes, Graph = Graph, TweenService = TweenService, Recipes = Recipes, gui = gui, UserInputService = UserInputService, RunService = RunService})
local getGraph = CraftingReferenceExports.getGraph
local drawGraph = CraftingReferenceExports.drawGraph
local refreshBook = CraftingReferenceExports.refreshBook
-- Высота шапки меняется вместе с полосой Roblox (поворот телефона, полный экран),
-- и карта справочника должна выводиться наверх ровно на новую высоту.
onChrome = CraftingReferenceExports.applyBookLayout
-- ============ Подключение к серверу ============

InventoryChanged.OnClientEvent:Connect(function(counts)
	inventory = counts
	CraftingBuyTabExports.setInventory(counts)
	CraftingProducerExports.setInventory(counts)
	CraftingCraftTabExports.setInventory(counts)
	for key, label in buyCountLabels do
		label.Text = tostring(inventory[key] or 0)
	end
	refreshInventoryList()
end)

MatterChanged.OnClientEvent:Connect(function(amount)
	matterLabel.Text = Theme.Readout("МАТЕРИЯ", tostring(amount), Theme.color.energy)
	-- Экран производителя читает материю из атрибута окна (buildProducer).
	gui:SetAttribute("Matter", amount)
	-- Вспышка — не у производителя: там показание без анимации.
	if not (gui.Enabled and buyFrame.Visible) then
		Theme.Blink(matterLabel)
	end
end)

RecipeLearned.OnClientEvent:Connect(function(resultKey)
	knownRecipes[resultKey] = true
	-- Карта перерисовывается только здесь и при первом открытии: у нового рецепта
	-- появляется вторая стрелка и имя вместо «???». Наведение и выбор обходятся repaint.
	if getGraph() then
		drawGraph()
	end
	refreshBook()
end)

-- Стол привязан к ProximityPrompt (CraftPrompt в CraftInteraction) — окно открывается только после срабатывания
-- подсказки (то есть игрок уже рядом с столом). Сама возможность действия всё равно
-- перепроверяет сервер на каждый запрос.
-- Каждая мебель открывает свой раздел: имя подсказки → раздел и заголовок окна.
-- Подсказки ставит CraftInteraction. Таблица — внутри обработчика, а не на верхнем
-- уровне файла: там уже упёрлись в предел Luau — 200 локальных на одну функцию.
ProximityPromptService.PromptTriggered:Connect(function(prompt)
	local section = ({
		CraftPrompt = { tab = "Крафт", title = "Стол крафта" },
		BookPrompt = { tab = "Справочник", title = "Справочник" },
		ElementPrompt = { tab = "Купить", title = "Производитель" },
	})[prompt.Name]
	if section then
		title.Text = section.title
		selectTab(section.tab)
		-- Шапка пересчитывается на каждом открытии: на первых кадрах клиента высота
		-- полосы Roblox ещё нулевая, и окно, собранное в этот момент, осталось бы с заголовком
		-- под кнопками Roblox навсегда. К столу игрок подходит гораздо позже.
		applyChrome()
		gui.Enabled = true
		-- Производитель — без раскрытия окна и без помехи: его монитор раскрывается сам
		-- (open в buildProducer, см. «Вкладка "Купить"»).
		if section.tab ~= "Купить" then
			Theme.Open(root)
			Theme.Static()
		end
	end
end)

-- Подгонки графа под ширину окна больше нет: у дерева можно было растянуть шаг
-- колонок, у графа растягивается вся картинка сразу — это масштаб (setZoom/fitZoom).

applyChrome()
selectTab("Купить")
refreshInventoryList()
refreshBook()
