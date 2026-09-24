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

-- ============ Вкладка "Купить" ============
-- Производитель — окно во весь экран, как планшет с камерами: сверху только название
-- и крестик, ниже монитор в тонкой рамке, а на нём один из трёх режимов
-- (alchemy_td_location_v1.6.md, «Производитель: режимы работы»). Сборка — buildProducer.
-- Прежний вид — автомат спереди (задачи #201–#202, buildMachineFront) — больше
-- не собирается: три режима на одной маленькой панели игроки не понимали.
--
-- Вкладка лежит прямо на root и сама глухая: закрывает фон окна и его шапку. Движение
-- окна — барабаны, стрелка, джекпот и отклики — в ProducerShow; оно слушается «Движения».
local buyFrame = Instance.new("Frame")
buyFrame.Name = "BuyTab"
buyFrame.Size = UDim2.new(1, 0, 1, 0)
buyFrame.BackgroundColor3 = Theme.color.panel
buyFrame.BackgroundTransparency = 0
buyFrame.BorderSizePixel = 0
buyFrame.ClipsDescendants = true
buyFrame.ZIndex = 2
buyFrame.Visible = true
buyFrame.Parent = root
tabFrames["Купить"] = buyFrame

local buyCountLabels = {} -- elementKey -> label, обновляется по InventoryChanged

-- Всё внутри функции: главный кусок скрипта упёрся в потолок Luau — 200 локальных.
local function buildMachineFront()
	local Skin = require(script.Parent:WaitForChild("ProducerSkin"))
	local Show = require(script.Parent:WaitForChild("ProducerShow"))
	local RouletteConfig = require(ReplicatedStorage:WaitForChild("RouletteConfig"))
	local UpgraderConfig = require(ReplicatedStorage:WaitForChild("UpgraderConfig"))
	local RequestRouletteSpin = Remotes:WaitForChild("RequestRouletteSpin")
	local RequestUpgrade = Remotes:WaitForChild("RequestUpgrade")

	local MARGIN = 1.04
	-- По этим деталям автомат вписывается в окно: крышки колб сверху, корпус по бокам.
	-- Снизу рисунок обрезан чуть ниже панели с кнопками (деталь PanelFace): лоток выдачи
	-- и подставка во вкладке не нужны. Короб и кабель на стене сзади в кадр не просятся.
	local FRAME_PARTS = { CanCap = true, Cabinet = true, CornerGuard = true }
	local CUT_BELOW = 0.12 -- стадов корпуса под панелью с кнопками

	-- Рисунок автомата. Все детали на слое 1: из равных по ZIndex позже рисуется тот, кто
	-- позже в дереве, поэтому детали создаются от дальней к ближней.
	local view = Instance.new("Frame")
	view.Name = "Machine"
	view.Size = UDim2.fromScale(1, 1)
	view.BackgroundTransparency = 1
	view.BorderSizePixel = 0
	view.ZIndex = 1
	view.Parent = buyFrame

	-- Всё, что лежит поверх модели. Пока модели нет (локация ещё не построена), слоя нет тоже.
	local front = Instance.new("Frame")
	front.Name = "Front"
	front.Size = UDim2.fromScale(1, 1)
	front.BackgroundTransparency = 1
	front.ZIndex = 2
	front.Visible = false
	front.Parent = buyFrame

	local source, copy -- copy: Frame с рисунком деталей текущего автомата
	local shapes = {} -- { frame, lo, hi, key } — деталь в осях автомата; key у налитого в колбу
	local shapeOf = {} -- деталь модели -> её запись в shapes
	local shares = {} -- elementKey -> доля налитого в колбе, 0..1
	local lo, hi -- рамка автомата по FRAME_PARTS в его осях
	local cut -- высота обрезки рисунка в осях автомата: ниже неё ничего не рисуется

	local function make(className, name, parent, z)
		local inst = Instance.new(className)
		inst.Name = name
		inst.BorderSizePixel = 0
		inst.BackgroundTransparency = 1
		inst.ZIndex = z
		inst.Parent = parent
		return inst
	end

	local function text(parent, name, str, z)
		local l = make("TextLabel", name, parent, z or 3)
		l.FontFace = Theme.font.strong
		l.TextColor3 = Theme.color.ink
		l.TextScaled = true
		l.Text = str
		local limit = Instance.new("UITextSizeConstraint")
		limit.MinTextSize = 6
		limit.Parent = l
		return l
	end

	-- Клавиша экрана: тёмная, как кнопки самого автомата, без твинов наведения.
	local function key(parent, name, str)
		local b = make("TextButton", name, parent, 3)
		b.BackgroundTransparency = 0
		b.AutoButtonColor = true
		b.FontFace = Theme.font.strong
		b.TextScaled = true
		b.TextColor3 = Color3.new(1, 1, 1)
		b.Text = str
		Theme.Corner(b, Theme.radius.mark)
		local limit = Instance.new("UITextSizeConstraint")
		limit.MinTextSize = 6
		limit.Parent = b
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 3)
		pad.PaddingRight = UDim.new(0, 3)
		pad.Parent = b
		return b
	end

	-- Неоновая полоса автомата (деталь LogoPlate) с его именем.
	local logo = text(front, "Logo", "ПРОИЗВОДИТЕЛЬ ЭЛЕМЕНТОВ", 2)

	-- Светлый экран автомата (деталь Panel): на нём рулетка и апгрейдер, на нём же их показ.
	local screen = make("Frame", "Screen", front, 2)
	screen.BackgroundTransparency = 0
	Theme.Corner(screen, Theme.radius.mark)

	-- Цена покупки: одна строка на экране. Числа из Elements — те же, по которым платит сервер.
	local priceLine
	do
		local costs, parts, same = {}, {}, true
		for _, k in BASE_ORDER do
			costs[#costs + 1] = Elements[k].cost
			parts[#parts + 1] = Elements[k].name .. " " .. Elements[k].cost
			same = same and Elements[k].cost == costs[1]
		end
		priceLine = text(screen, "Price", same and ("ЦВЕТНАЯ КНОПКА ВНИЗУ — ЭЛЕМЕНТ ЗА " .. costs[1])
			or Theme.Caps(table.concat(parts, " · ")))
	end

	-- Кнопки покупки лежат на цветных кнопках рисунка (их рисует build по кнопкам модели),
	-- кнопка — только место нажатия поверх.
	local buyButtons = {}
	for _, k in BASE_ORDER do
		local b = make("TextButton", "Buy" .. k, front, 2)
		b.AutoButtonColor = false
		b.Text = ""
		b.BackgroundColor3 = Color3.new(1, 1, 1)
		Theme.Corner(b, Theme.radius.mark)
		b.MouseEnter:Connect(function()
			b.BackgroundTransparency = 0.8
		end)
		b.MouseLeave:Connect(function()
			b.BackgroundTransparency = 1
		end)
		b.MouseButton1Click:Connect(function()
			RequestBuyElement:FireServer(k)
		end)
		buyButtons[k] = b

		-- Запас элемента — число прямо на его колбе.
		local count = text(front, "Count" .. k, tostring(inventory[k] or 0), 2)
		count.TextColor3 = Color3.new(1, 1, 1)
		count.TextStrokeTransparency = 0.2
		buyCountLabels[k] = count
	end

	-- ============ Рулетка ============
	-- Второй режим (alchemy_td_location_v1.6.md, «Производитель: режимы работы»): случайный
	-- элемент из четырёх. Потолок прокруток и цена — из RouletteConfig, по нему платит сервер.
	local roulette = { count = 1, buttons = {} }
	roulette.name = text(screen, "RouletteName", "РУЛЕТКА")
	roulette.name.TextXAlignment = Enum.TextXAlignment.Left
	roulette.price = text(screen, "RoulettePrice", "")
	roulette.spin = key(screen, "Spin", "+")
	for n = 1, RouletteConfig.MAX_SPINS do
		local b = key(screen, "Spins" .. n, tostring(n))
		b.MouseButton1Click:Connect(function()
			roulette.count = n
			roulette.refresh()
		end)
		roulette.buttons[n] = b
	end
	roulette.spin.MouseButton1Click:Connect(function()
		-- Сколько прокруток и хватает ли материи — решает сервер; здесь только просьба.
		RequestRouletteSpin:FireServer(roulette.count)
	end)

	-- ============ Апгрейдер ============
	-- Третий режим: элемент вперёд по своей чистокровной ветке. Ветки и шансы — из
	-- UpgraderConfig, по нему сервер и разыгрывает попытку.
	local up = { moves = {}, index = 1 }
	up.src = key(screen, "Source", "")
	up.arrow = text(screen, "Arrow", "→")
	up.dst = key(screen, "Target", "")
	up.go = key(screen, "Upgrade", "+")

	-- 50, 25, 12.5, 6.25 — без лишних нулей и без округления до вранья.
	local function percent(chance)
		local s = string.format("%.2f", chance * 100)
		s = s:gsub("0+$", ""):gsub("%.$", "")
		return s .. "%"
	end

	function up.rebuild(counts)
		local keep = up.moves[up.index]
		up.moves = {}
		for _, spine in UpgraderConfig.SPINES do
			for _, k in spine do
				if (counts[k] or 0) > 0 then
					for _, target in UpgraderConfig.Targets(k) do
						up.moves[#up.moves + 1] = { from = k, to = target.key, chance = target.chance }
					end
				end
			end
		end
		-- Выбор игрока переживает пополнение сумки: иначе каждая покупка сбрасывала бы его.
		up.index = 1
		if keep then
			for i, move in up.moves do
				if move.from == keep.from and move.to == keep.to then
					up.index = i
					break
				end
			end
		end
	end

	-- Кнопка «откуда» перебирает элементы, «куда» — цели внутри выбранного элемента.
	up.src.MouseButton1Click:Connect(function()
		if #up.moves == 0 then
			return
		end
		local from = up.moves[up.index].from
		for step = 1, #up.moves do
			local i = (up.index + step - 1) % #up.moves + 1
			if up.moves[i].from ~= from then
				up.index = i
				break
			end
		end
		up.refresh()
	end)
	up.dst.MouseButton1Click:Connect(function()
		if #up.moves == 0 then
			return
		end
		local from = up.moves[up.index].from
		local nextIndex = up.index + 1
		if not up.moves[nextIndex] or up.moves[nextIndex].from ~= from then
			nextIndex = up.index
			while up.moves[nextIndex - 1] and up.moves[nextIndex - 1].from == from do
				nextIndex -= 1
			end
		end
		up.index = nextIndex
		up.refresh()
	end)
	up.go.MouseButton1Click:Connect(function()
		local pick = up.moves[up.index]
		if pick then
			-- Ветку, шанс и наличие элемента проверяет сервер; здесь только просьба.
			RequestUpgrade:FireServer(pick.from, pick.to)
		end
	end)

	-- ============ Рисунок автомата ============
	local function findSource()
		local location = workspace:FindFirstChild("Location")
		return (location and location:FindFirstChild("ElementProducer", true))
			or workspace:FindFirstChild("ElementProducer", true)
	end

	-- Коробка детали в осях автомата: лицевая сторона смотрит в −X, верх — +Y, ширина — вдоль Z.
	local function bounds(part, pivot)
		local half = part.Size / 2
		local a = Vector3.new(math.huge, math.huge, math.huge)
		local b = -a
		for _, sx in { -1, 1 } do
			for _, sy in { -1, 1 } do
				for _, sz in { -1, 1 } do
					local p = pivot:PointToObjectSpace(part.CFrame:PointToWorldSpace(half * Vector3.new(sx, sy, sz)))
					a = a:Min(p)
					b = b:Max(p)
				end
			end
		end
		return a, b
	end

	-- Локация строится под забег: рисунок снимается при открытии окна и заново — если
	-- автомат в мире сменился.
	local function build()
		local found = findSource()
		if not found or (found == source and copy) then
			return
		end
		source = found
		if copy then
			copy:Destroy()
			copy = nil
		end
		shapes, shapeOf = {}, {}
		local pivot = found:GetPivot()
		lo = Vector3.new(math.huge, math.huge, math.huge)
		hi = -lo
		for _, part in found:GetDescendants() do
			if part:IsA("BasePart") then
				local a, b = bounds(part, pivot)
				if FRAME_PARTS[part.Name] then
					lo = lo:Min(a)
					hi = hi:Max(b)
				end
				-- Невидимое в модели невидимо и на рисунке.
				if part.Transparency < 1 then
					local rec = { part = part, lo = a, hi = b, key = part.Name:match("^Reagent(%a+)$") }
					shapes[#shapes + 1] = rec
					shapeOf[part] = rec
				end
			end
		end
		if lo.X == math.huge then
			return
		end
		local face = source:FindFirstChild("PanelFace", true)
		cut = face and shapeOf[face] and shapeOf[face].lo.Y - CUT_BELOW or lo.Y
		lo = Vector3.new(lo.X, cut, lo.Z)
		-- Ближняя к игроку грань детали — меньший X: дальние детали рисуются первыми.
		table.sort(shapes, function(a, b)
			return a.lo.X > b.lo.X
		end)
		copy = make("Frame", "Parts", view, 1)
		copy.Size = UDim2.fromScale(1, 1)
		for _, rec in shapes do
			local f = make("Frame", rec.part.Name, copy, 1)
			f.BackgroundColor3 = rec.part.Color
			f.BackgroundTransparency = rec.part.Transparency
			rec.frame = f
		end
	end

	-- Сколько налито в колбе — запас этого элемента: полна при Skin.CANISTER_FULL штуках.
	local function fill(counts)
		for _, k in BASE_ORDER do
			shares[k] = math.clamp((counts[k] or 0) / Skin.CANISTER_FULL, 0, 1)
		end
	end

	-- Вид спереди без перспективы: автомат вписан в окно по FRAME_PARTS.
	local scale, ox, oy -- пикселей на стад; где в окне точка автомата Z = 0, Y = 0
	local function fit()
		local w, h = view.AbsoluteSize.X, view.AbsoluteSize.Y
		scale = math.min(w / (hi.Z - lo.Z), h / (hi.Y - lo.Y)) / MARGIN
		ox = w / 2 - (lo.Z + hi.Z) / 2 * scale
		oy = h / 2 + (lo.Y + hi.Y) / 2 * scale
	end

	-- Место коробки в окне: левый верхний угол и размер.
	local function toScreen(a, b)
		return Vector2.new(ox + a.Z * scale, oy - b.Y * scale), Vector2.new((b.Z - a.Z) * scale, (b.Y - a.Y) * scale)
	end

	local function rect(part)
		local rec = shapeOf[part]
		return toScreen(rec.lo, rec.hi)
	end

	-- Деталь автомата по имени, если она есть и видна.
	local function detail(name)
		local part = source and source:FindFirstChild(name, true)
		return part and shapeOf[part] and part
	end

	local function place(inst, x, y, w, h)
		inst.Position = UDim2.fromOffset(math.floor(x + 0.5), math.floor(y + 0.5))
		inst.Size = UDim2.fromOffset(math.max(0, math.floor(w + 0.5)), math.max(0, math.floor(h + 0.5)))
	end

	local function textMax(inst, size)
		inst:FindFirstChildOfClass("UITextSizeConstraint").MaxTextSize = math.max(6, math.floor(size))
	end

	local function layout()
		local w, h = view.AbsoluteSize.X, view.AbsoluteSize.Y
		if not copy or w < 40 or h < 40 then
			return
		end
		fit()
		for _, rec in shapes do
			local a, b = rec.lo, rec.hi
			local shown = b.Y > cut
			if rec.key then
				-- Налитое укорачивается от дна, а не сжимается к середине.
				local share = shares[rec.key] or 0
				b = Vector3.new(b.X, a.Y + (b.Y - a.Y) * share, b.Z)
				shown = shown and share > 0
			end
			a = Vector3.new(a.X, math.max(a.Y, cut), a.Z)
			rec.frame.Visible = shown
			local p, s = toScreen(a, b)
			place(rec.frame, p.X, p.Y, s.X, s.Y)
		end
		local panel = detail("Panel")
		if not panel then
			return
		end
		local pPos, pSize = rect(panel)
		local pps = scale
		place(screen, pPos.X, pPos.Y, pSize.X, pSize.Y)

		local plate = detail("LogoPlate")
		logo.Visible = plate ~= nil
		if plate then
			local p, s = rect(plate)
			place(logo, p.X, p.Y, s.X, s.Y)
			textMax(logo, s.Y * 0.7)
		end

		for _, k in BASE_ORDER do
			local plus = detail("Button" .. k)
			buyButtons[k].Visible = plus ~= nil
			if plus then
				-- Место нажатия шире самого плюса: палец на телефоне больше плюса на экране.
				local p, s = rect(plus)
				local c = p + s / 2
				local bw, bh = pps * 0.72, pps * 0.5
				place(buyButtons[k], c.X - bw / 2, c.Y - bh / 2, bw, bh)
			end
			local glass = detail("Canister" .. k)
			buyCountLabels[k].Visible = glass ~= nil
			if glass then
				local p, s = rect(glass)
				place(buyCountLabels[k], p.X, p.Y + s.Y / 2 - pps * 0.2, s.X, pps * 0.4)
				textMax(buyCountLabels[k], pps * 0.34)
			end
		end

		-- Экран: строка цены и два режима под ней.
		local W, H = pSize.X, pSize.Y
		local pad = math.max(3, math.floor(H * 0.06))
		local gap = math.max(2, math.floor(H * 0.035))
		local inner = H - pad * 2 - gap * 2
		local h1 = inner * 0.2
		local h2 = (inner - h1) / 2
		local y2 = pad + h1 + gap
		local y3 = y2 + h2 + gap
		local right = W - pad

		place(priceLine, pad, pad, W - pad * 2, h1)
		textMax(priceLine, h1 * 0.85)

		-- Рулетка, справа налево: плюс, цена, кнопки числа прокруток, имя.
		local x = right - h2
		place(roulette.spin, x, y2, h2, h2)
		x -= gap + h2 * 1.2
		place(roulette.price, x, y2, h2 * 1.2, h2)
		for n = RouletteConfig.MAX_SPINS, 1, -1 do
			x -= gap + h2 * 0.9
			place(roulette.buttons[n], x, y2, h2 * 0.9, h2)
		end
		place(roulette.name, pad, y2, x - gap - pad, h2)

		-- Апгрейдер: что вложить → что получить с шансом, плюс.
		place(up.go, right - h2, y3, h2, h2)
		local rest = right - h2 - gap - pad
		if up.moves[up.index] then
			local arrowW = h2 * 0.6
			local srcW = (rest - arrowW - gap * 2) * 0.42
			place(up.src, pad, y3, srcW, h2)
			place(up.arrow, pad + srcW + gap, y3, arrowW, h2)
			place(up.dst, pad + srcW + gap * 2 + arrowW, y3, rest - arrowW - gap * 2 - srcW, h2)
		else
			place(up.src, pad, y3, rest, h2)
		end

		for _, inst in { roulette.name, roulette.price, roulette.spin, up.src, up.arrow, up.dst, up.go } do
			textMax(inst, h2 * 0.55)
		end
		for _, b in roulette.buttons do
			textMax(b, h2 * 0.55)
		end
		textMax(roulette.spin, h2 * 0.8)
		textMax(up.go, h2 * 0.8)
	end

	local skin = Skin.Read()

	function roulette.refresh()
		roulette.price.Text = tostring(RouletteConfig.TotalCost(roulette.count))
		for n, b in roulette.buttons do
			local chosen = n == roulette.count
			b.BackgroundColor3 = chosen and skin.logo or skin.dark
			b.TextColor3 = chosen and Theme.color.ink or Color3.new(1, 1, 1)
		end
	end

	function up.refresh()
		local pick = up.moves[up.index]
		-- Кнопка без действия — декорация: когда апгрейдить нечего, цели и плюса нет.
		up.arrow.Visible = pick ~= nil
		up.dst.Visible = pick ~= nil
		up.go.Visible = pick ~= nil
		if pick then
			up.src.Text = Theme.Caps(Elements[pick.from].name)
			up.dst.Text = Theme.Caps(Elements[pick.to].name) .. " " .. percent(pick.chance)
		else
			up.src.Text = "АПГРЕЙДЕР: НЕТ ЭЛЕМЕНТА"
		end
		layout()
	end

	-- Цвета сняты с деталей самой модели (ProducerSkin), не подобраны на глаз.
	local function paint()
		skin = Skin.Read()
		screen.BackgroundColor3 = skin.screen
		for _, b in { roulette.spin, up.src, up.dst, up.go } do
			b.BackgroundColor3 = skin.dark
		end
		roulette.spin.TextColor3 = Theme.color.action
		up.go.TextColor3 = Theme.color.action
		roulette.refresh()
	end

	local function open()
		if not gui.Enabled or not buyFrame.Visible then
			return
		end
		build()
		front.Visible = copy ~= nil
		if copy then
			paint()
			fill(inventory)
			layout()
		end
	end

	gui:GetPropertyChangedSignal("Enabled"):Connect(open)
	buyFrame:GetPropertyChangedSignal("Visible"):Connect(open)
	buyFrame:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
	-- Обработчик ниже по скрипту обновляет inventory позже этого, поэтому запас берётся
	-- из самого события, а не из таблицы.
	InventoryChanged.OnClientEvent:Connect(function(counts)
		fill(counts)
		up.rebuild(counts)
		up.refresh()
	end)

	-- Показ розыгрыша на светлом экране автомата. Сервер уже разыграл итог и держит замок,
	-- пока идёт показ; элементы придут в инвентарь после него. Код показа — в ProducerShow.
	Remotes:WaitForChild("RouletteShow").OnClientEvent:Connect(function(results, time)
		Show.Roulette(screen, Skin.Read(), results, time or RouletteConfig.SHOW_TIME)
	end)
	Remotes:WaitForChild("UpgradeShow").OnClientEvent:Connect(function(result)
		Show.Upgrade(screen, Skin.Read(), result, UpgraderConfig.SHOW_TIME)
	end)

	up.rebuild(inventory)
	paint()
	up.refresh()
	open()
end
-- ============ Экран производителя ============
-- Всё внутри функции: главный кусок скрипта упёрся в потолок Luau — 200 локальных.
local function buildProducer()
	local Skin = require(script.Parent:WaitForChild("ProducerSkin"))
	local Show = require(script.Parent:WaitForChild("ProducerShow"))
	local UISound = require(script.Parent:WaitForChild("UISound"))
	local RouletteConfig = require(ReplicatedStorage:WaitForChild("RouletteConfig"))
	local UpgraderConfig = require(ReplicatedStorage:WaitForChild("UpgraderConfig"))
	local RequestRouletteSpin = Remotes:WaitForChild("RequestRouletteSpin")
	local RequestUpgrade = Remotes:WaitForChild("RequestUpgrade")

	-- Три режима производителя — в порядке документа. На мониторе всегда ровно один.
	local MODES = {
		{ id = "Buy", name = "Покупка" },
		{ id = "Roulette", name = "Рулетка" },
		{ id = "Upgrade", name = "Апгрейдер" },
	}
	local st = {
		mode = "Buy",
		busy = nil, -- идёт показ розыгрыша: запуск рулетки и попытка апгрейда не нажимаются
		skin = Skin.Read(),
		counts = inventory,
		-- Запас хоть раз пришёл с сервера. До этого «есть 0» было бы выдумкой — показания нет.
		haveCounts = next(inventory) ~= nil,
		spins = 1,
		moves = {}, -- { from, to, chance } — все попытки апгрейда, доступные при текущем запасе
		index = 1,
		follow = nil, -- удачная попытка: на этот элемент перейдёт выбор, когда он придёт в сумку
		cap = 11, -- размер подписи у показаний: меняется вместе с раскладкой
	}
	local refresh, lock -- объявлены ниже: их зовут кнопки, собранные раньше них

	local function make(className, name, parent, z)
		local inst = Instance.new(className)
		inst.Name = name
		inst.BorderSizePixel = 0
		inst.BackgroundTransparency = 1
		inst.ZIndex = z
		inst.Parent = parent
		return inst
	end

	local function text(parent, name, z)
		local l = make("TextLabel", name, parent, z)
		l.FontFace = Theme.font.strong
		l.TextColor3 = Theme.color.text
		l.TextWrapped = true
		l.Text = ""
		return l
	end

	-- Кнопка под общий сборщик: наведение осветляет её, как во всей игре (Theme.Button),
	-- нажатие проседает и пружинит обратно (Show.Press).
	local function button(parent, name, z)
		local b = make("TextButton", name, parent, z)
		Show.Press(b)
		b.FontFace = Theme.font.strong
		b.TextWrapped = true
		b.Text = ""
		return b
	end

	-- Ячейка элемента — как во всей игре (Theme.ElementFill): тёмный корпус его цвета, кант,
	-- засечка, дымка и узор элемента. Цвет снят с кнопок самой модели (ProducerSkin), как и
	-- у барабанов рулетки. dim — невыбранная фишка запаса: корпус глубже, кант и засечка гаснут.
	-- Слои ячейки — её дети и легли бы поверх её собственного текста, поэтому текст
	-- показывает дочерняя подпись Label, созданная после слоёв. Text и TextSize ячейки она
	-- повторяет сама: раскладка и показания пишут в ячейку, как раньше.
	local function paintElement(inst, k, dim)
		local c = (st.skin.button and st.skin.button[k]) or Elements[k].color
		Theme.ElementFill(inst, c, { element = k, dim = dim })
		inst.TextTransparency = 1
		local l = inst:FindFirstChild("Label")
		if not l then
			l = make("TextLabel", "Label", inst, inst.ZIndex)
			l.Size = UDim2.fromScale(1, 1)
			l.FontFace = inst.FontFace
			l.TextWrapped = true
			local function sync()
				l.Text = inst.Text
				l.TextSize = inst.TextSize
			end
			sync()
			inst:GetPropertyChangedSignal("Text"):Connect(sync)
			inst:GetPropertyChangedSignal("TextSize"):Connect(sync)
		end
		l.TextColor3 = dim and Theme.color.textDim or Theme.color.text
		-- Узор (огонь, молнии) шумит под названием: под самим текстом — тёмная плашка,
		-- гаснущая к левому и правому краю. Размер — по TextBounds, узор вокруг виден как был.
		-- Размытая полоса во всю ширину автору понравилась меньше (#219).
		-- Порядок детей держит полосу под надписью: Label создаётся после неё,
		-- а Theme.Pattern переносит остальных детей в конец, не меняя их порядок.
		local shade = inst:FindFirstChild("Shade")
		if not shade then
			shade = make("Frame", "Shade", inst, inst.ZIndex)
			shade.AnchorPoint = Vector2.new(0.5, 0.5)
			shade.Position = UDim2.fromScale(0.5, 0.5)
			shade.BackgroundColor3 = Theme.color.panel
			shade.BackgroundTransparency = 0
			shade.BorderSizePixel = 0
			local fade = Instance.new("UIGradient")
			fade.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.25, 0.45),
				NumberSequenceKeypoint.new(0.75, 0.45),
				NumberSequenceKeypoint.new(1, 1),
			})
			fade.Parent = shade
			local function fit()
				local tb = l.TextBounds
				shade.Size = UDim2.fromOffset(tb.X + tb.Y * 3, tb.Y + 8)
				shade.Visible = l.Text ~= ""
			end
			l:GetPropertyChangedSignal("TextBounds"):Connect(fit)
			fit()
			l.Parent = nil
			l.Parent = inst
		end
	end

	-- 50, 25, 12.5, 6.25 — без лишних нулей и без округления до вранья.
	local function percent(chance)
		local s = string.format("%.2f", chance * 100)
		s = s:gsub("0+$", ""):gsub("%.$", "")
		return s .. "%"
	end

	local function place(inst, x, y, w, h)
		inst.Position = UDim2.fromOffset(math.floor(x + 0.5), math.floor(y + 0.5))
		inst.Size = UDim2.fromOffset(math.max(0, math.floor(w + 0.5)), math.max(0, math.floor(h + 0.5)))
	end

	-- Подписи элементов для подбора размера текста: каждое слово отдельно.
	local function words(keys)
		local list = {}
		for _, k in keys do
			for word in Theme.Caps(Elements[k].name):gmatch("%S+") do
				list[#list + 1] = word
			end
		end
		return list
	end

	-- Самое длинное слово должно влезть в ширину целиком: иначе перенос рвёт его посередине.
	-- Шрифт окна — RobotoMono; у жирного ширина букв та же.
	local function fitSize(list, want, width)
		local size = want
		while size > 10 do
			local widest = 0
			for _, word in list do
				widest = math.max(widest, TextService:GetTextSize(word, size, Enum.Font.RobotoMono, Vector2.new(4000, 1000)).X)
			end
			if widest <= width then
				break
			end
			size -= 1
		end
		return size
	end

	-- ============ Рамка, шапка и подвал — как у главного меню ============
	-- Соты вкладки «Купить» (Theme.scene.shop), едущие по диагонали — вверх и вправо.
	-- Волна опроса и её скорость обнулены: движется только сама решётка.
	local drifting = table.clone(Theme.scene.shop)
	drifting.drift, drifting.driftX = -3, 3
	drifting.pulse, drifting.wave = 0, 0
	Theme.Backdrop(buyFrame, drifting)

	-- Рамка терминала: кант в пиксель и уголки. Фон окна свой, сплошной (просьба автора,
	-- #221): соты меню остаются вокруг окна, а не под карточками.
	local mon = make("Frame", "Monitor", buyFrame, 2)
	mon.BackgroundColor3 = Theme.color.ink
	mon.BackgroundTransparency = 0
	Theme.Corner(mon, Theme.radius.panel)
	Theme.Stroke(mon, Theme.color.frame, 1, 0)
	Theme.Brackets(mon)

	-- Фон окна — ровная сетка точек (выбор автора, #221, Theme.Dots): отличается от сот
	-- меню формой. Первым ребёнком рамки — под всем остальным содержимым; сквозь
	-- стеклянные подложки видна приглушённой.
	local paintDots = Theme.Dots(mon, { zIndex = 2 })

	local head = text(mon, "Title", 3)
	head.TextXAlignment = Enum.TextXAlignment.Left
	head.TextWrapped = false
	head.TextTruncate = Enum.TextTruncate.AtEnd
	head.Text = "ПРОИЗВОДИТЕЛЬ"
	Theme.Display(head)
	head.TextColor3 = Theme.color.accent

	-- Материя справа в шапке, как плутоний в меню. Это то же число, что шлёт сервер
	-- (MatterChanged; обработчик внизу скрипта кладёт его в атрибут окна). Пока числа не было, показания нет.
	-- Своя плашка (просьба автора, #228): без неё показание сливалось с точками окна.
	-- Стекло — как у карточек (#229), и надпись на слой выше: пятна стекла лежат
	-- детьми плашки и иначе прошли бы поверх текста. Плашка по ширине текста — растёт
	-- влево от крестика.
	local matterBox = make("Frame", "MatterBox", mon, 3)
	matterBox.AutomaticSize = Enum.AutomaticSize.X
	matterBox.AnchorPoint = Vector2.new(1, 0)
	-- Подпись и число разделены полоской (просьба автора, #231). Строка — свой Frame
	-- с UIListLayout: прямо в плашке раскладка расставила бы и слой пятен стекла.
	local matterRow = make("Frame", "Row", matterBox, 4)
	matterRow.Size = UDim2.fromScale(0, 1)
	matterRow.AutomaticSize = Enum.AutomaticSize.X
	local matterList = Instance.new("UIListLayout")
	matterList.FillDirection = Enum.FillDirection.Horizontal
	matterList.VerticalAlignment = Enum.VerticalAlignment.Center
	matterList.SortOrder = Enum.SortOrder.LayoutOrder
	matterList.Parent = matterRow
	-- Отступы у надписей, а не у плашки: UIPadding плашки сдвинул бы и слой пятен стекла.
	local function matterPart(name, order, left, right)
		local l = text(matterRow, name, 4)
		l.LayoutOrder = order
		l.Size = UDim2.fromScale(0, 1)
		l.AutomaticSize = Enum.AutomaticSize.X
		l.TextWrapped = false
		Theme.Display(l)
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, left)
		pad.PaddingRight = UDim.new(0, right)
		pad.Parent = l
		return l
	end
	local matterCaption = matterPart("Caption", 1, 14, 12)
	matterCaption.Text = Theme.Caps("Материя")
	matterCaption.TextColor3 = Theme.color.textMute
	local matterRule = make("Frame", "Rule", matterRow, 4)
	matterRule.LayoutOrder = 2
	matterRule.BackgroundColor3 = Theme.color.text
	matterRule.BackgroundTransparency = 0.85
	matterRule.Size = UDim2.new(0, 1, 0.5, 0)
	local matter = matterPart("Matter", 3, 12, 14)
	-- Строки режима под названием и серых линий шапки и подвала больше нет (просьба
	-- автора, #227): выбранный режим и так виден по вкладке внизу.

	-- Подвал: режимы пунктами, как в меню. «Закрыть» — справа вверху, как выход во всех окнах.
	local map = make("Frame", "ModeMap", mon, 3)
	local modeButtons, screens = {}, {}
	for _, m in MODES do
		local b = button(map, "Mode" .. m.id, 4)
		b.TextXAlignment = Enum.TextXAlignment.Left
		local bp = Instance.new("UIPadding")
		bp.Name = "Pad"
		bp.Parent = b
		modeButtons[m.id] = b
		screens[m.id] = make("Frame", m.id .. "Screen", mon, 2)
	end

	-- Выход — крестик, как во всех окнах игры (Theme.CloseButton), а не надпись.
	local close = button(mon, "Close", 3)
	Theme.CloseButton(close)
	close.MouseButton1Click:Connect(function()
		gui.Enabled = false
	end)

	-- Подложка — жидкое стекло (просьба автора, #226): фон под ней размыт, а не засветлён.
	-- Размывать интерфейс под кадром Roblox не умеет, поэтому размытие нарисовано: тёмное
	-- почти непрозрачное стекло закрывает чёткие точки окна, а на их местах слой Frost
	-- кладёт мягкие пятна — так выглядит точка сквозь матовое стекло. Кромка — ровная
	-- тонкая линия.
	-- Пятно вчетверо шире точки и во столько же бледнее: свет точки растёкся по стеклу.
	local FROST_SIZE, FROST_T = 9, 0.9
	local monDots = mon:FindFirstChild("Dots")
	local frosted = {}
	local function frost(plate, layer)
		local open = mon:FindFirstChild("OpenScale")
		local step = monDots:GetAttribute("Step")
		if (open and open.Scale < 1) or not step then
			return -- окно раскрывается и меряется меньше настоящего; конец анимации даст верный замер
		end
		local ox, oy = monDots:GetAttribute("OriginX"), monDots:GetAttribute("OriginY")
		local half = monDots:GetAttribute("Size") / 2
		local rel = plate.AbsolutePosition - monDots.AbsolutePosition
		local rx, ry = math.floor(rel.X + 0.5), math.floor(rel.Y + 0.5)
		local w, h = plate.AbsoluteSize.X, plate.AbsoluteSize.Y
		local key = rx .. ":" .. ry .. ":" .. w .. "x" .. h .. ":" .. ox .. ":" .. oy
		if layer:GetAttribute("For") == key then
			return
		end
		layer:SetAttribute("For", key)
		layer:ClearAllChildren()
		-- Центры точек окна в координатах подложки
		local c0 = math.ceil((rx - ox - half) / step)
		local r0 = math.ceil((ry - oy - half) / step)
		local cx = ox + half + c0 * step - rx
		while cx <= w do
			local cy = oy + half + r0 * step - ry
			while cy <= h do
				local d = Instance.new("Frame")
				d.BorderSizePixel = 0
				d.BackgroundColor3 = Theme.color.grid
				d.BackgroundTransparency = FROST_T
				d.Size = UDim2.fromOffset(FROST_SIZE, FROST_SIZE)
				d.Position = UDim2.fromOffset(cx - FROST_SIZE / 2, cy - FROST_SIZE / 2)
				d.ZIndex = layer.ZIndex
				local round = Instance.new("UICorner")
				round.CornerRadius = UDim.new(0.5, 0)
				round.Parent = d
				d.Parent = layer
				cy += step
			end
			cx += step
		end
	end
	local function refrostAll()
		for plate, layer in frosted do
			frost(plate, layer)
		end
	end
	monDots:GetAttributeChangedSignal("OriginX"):Connect(refrostAll)
	monDots:GetAttributeChangedSignal("OriginY"):Connect(refrostAll)

	local function glass(plate)
		plate.BackgroundColor3 = Theme.color.ink
		plate.BackgroundTransparency = 0.1
		Theme.Corner(plate, Theme.radius.mark)
		-- Кромка ровная, без блика сверху (просьба автора, #230): блик тянул в «Frutiger
		-- Aero» и спорил с неоном интерфейса.
		Theme.Stroke(plate, Theme.color.text, 1, 0.85)

		local layer = Instance.new("Frame")
		layer.Name = "Frost"
		layer.BackgroundTransparency = 1
		layer.BorderSizePixel = 0
		layer.Size = UDim2.fromScale(1, 1)
		layer.ClipsDescendants = true
		layer.ZIndex = plate.ZIndex
		layer.Parent = plate
		frosted[plate] = layer
		local function again()
			frost(plate, layer)
		end
		plate:GetPropertyChangedSignal("AbsolutePosition"):Connect(again)
		plate:GetPropertyChangedSignal("AbsoluteSize"):Connect(again)
	end
	glass(matterBox)

	-- ============ Покупка ============
	-- Карточка на стихию: цвет, запас, кнопка. Цена — из Elements, по ней же платит сервер.
	local cards = {}
	for _, k in BASE_ORDER do
		local card = make("Frame", "Card" .. k, screens.Buy, 3)
		glass(card)
		local swatch = text(card, "Swatch", 4)
		swatch.Text = Theme.Caps(Elements[k].name)
		Theme.Corner(swatch, Theme.radius.mark)
		local count = text(card, "Count", 4)
		count.RichText = true
		count.TextWrapped = false
		Theme.Display(count)
		local buy = button(card, "Buy" .. k, 4)
		buy.Text = "КУПИТЬ ЗА " .. Elements[k].cost
		buy.MouseButton1Click:Connect(function()
			-- Хватает ли материи — решает сервер; здесь только просьба.
			RequestBuyElement:FireServer(k)
		end)
		cards[k] = { card = card, swatch = swatch, count = count, buy = buy }
	end

	-- ============ Рулетка ============
	-- Случайный элемент из четырёх (alchemy_td_location_v1.6.md). Потолок прокруток, веса
	-- и цена — из RouletteConfig: по нему же сервер разыгрывает и берёт плату.
	local roul = { tiles = {}, counts = {} }
	roul.stage = make("Frame", "Stage", screens.Roulette, 3)
	glass(roul.stage)
	-- Пока барабаны стоят, на экране — что вообще может выпасть и с каким шансом.
	local weightSum = 0
	for _, w in RouletteConfig.WEIGHTS do
		weightSum += w
	end
	roul.keys = {}
	for _, k in BASE_ORDER do
		local w = RouletteConfig.WEIGHTS[k] or 0
		if w > 0 and weightSum > 0 then
			local tile = text(roul.stage, "Tile" .. k, 4)
			tile.Text = Theme.Caps(Elements[k].name) .. "\n" .. percent(w / weightSum)
			roul.tiles[k] = tile
			roul.keys[#roul.keys + 1] = k
		end
	end
	roul.words = words(roul.keys)
	for _, k in roul.keys do
		roul.words[#roul.words + 1] = percent(RouletteConfig.WEIGHTS[k] / weightSum)
	end

	roul.caption = text(screens.Roulette, "SpinsCaption", 3)
	Theme.Section(roul.caption, "Прокруток")
	for n = 1, RouletteConfig.MAX_SPINS do
		local b = button(screens.Roulette, "Spins" .. n, 3)
		b.Text = tostring(n)
		b.MouseButton1Click:Connect(function()
			st.spins = n
			refresh()
		end)
		roul.counts[n] = b
	end
	roul.go = button(screens.Roulette, "Spin", 3)
	roul.go.MouseButton1Click:Connect(function()
		if st.busy then
			return
		end
		-- Сколько прокруток и хватает ли материи — решает сервер; здесь только просьба.
		lock(1)
		RequestRouletteSpin:FireServer(st.spins)
	end)

	-- ============ Апгрейдер ============
	-- Раскладка как у апгрейдеров кейс-сайтов: слева то, что отдаёшь, справа то, что получишь,
	-- между ними круг шанса и кнопка. Правила — из документа: один элемент вперёд по своей
	-- чистокровной ветке. Ветки, шансы и цена — из UpgraderConfig, по нему сервер и разыгрывает.
	local up = { stock = {}, steps = {} }
	local spineKeys = {}
	local maxSteps = 0
	for _, spine in UpgraderConfig.SPINES do
		for _, k in spine do
			spineKeys[#spineKeys + 1] = k
			maxSteps = math.max(maxSteps, #UpgraderConfig.Targets(k))
		end
	end
	up.words = words(spineKeys)

	local function side(name, caption)
		local panel = make("Frame", name, screens.Upgrade, 3)
		glass(panel)
		local cap = text(panel, "Caption", 4)
		Theme.Section(cap, caption)
		local block = text(panel, "Element", 4)
		Theme.Corner(block, Theme.radius.mark)
		return panel, cap, block
	end
	up.srcPanel, up.srcCap, up.src = side("Source", "Затраты")
	up.dstPanel, up.dstCap, up.dst = side("Target", "Результат")

	up.burn = text(up.srcPanel, "Burn", 4)
	up.burn.TextXAlignment = Enum.TextXAlignment.Left
	up.burn.TextColor3 = Theme.color.danger
	up.burn.Text = "ПРИ НЕУДАЧЕ ЭЛЕМЕНТ СГОРАЕТ"
	up.burn.Visible = UpgraderConfig.BURN_ON_FAIL == true
	up.empty = text(up.srcPanel, "Empty", 4)
	up.empty.TextColor3 = Theme.color.textDim
	up.empty.Text = "НЕТ ЭЛЕМЕНТОВ ДЛЯ АПГРЕЙДА"

	-- Попытки, доступные при текущем запасе, от одного элемента — в порядке его целей.
	local function movesFrom(k)
		local list = {}
		for i, move in st.moves do
			if move.from == k then
				list[#list + 1] = i
			end
		end
		return list
	end

	local function paintPair(from, to)
		paintElement(up.src, from)
		paintElement(up.dst, to)
		up.src.Text = Theme.Caps(Elements[from].name)
		up.dst.Text = Theme.Caps(Elements[to].name)
	end

	-- Запас внизу слева — выбор того, что отдаёшь. Порядок — как в ветках; конец ветки
	-- апгрейдить некуда, его здесь нет. Смена элемента сохраняет, на сколько шагов идти.
	up.list = make("ScrollingFrame", "Stock", up.srcPanel, 4)
	up.list.ScrollBarThickness = 4
	up.list.ScrollBarImageColor3 = Theme.color.hairline
	up.list.ScrollingDirection = Enum.ScrollingDirection.Y
	up.list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	up.list.CanvasSize = UDim2.new()
	up.grid = Instance.new("UIGridLayout")
	up.grid.SortOrder = Enum.SortOrder.LayoutOrder
	up.grid.Parent = up.list
	for order, k in spineKeys do
		if #UpgraderConfig.Targets(k) > 0 then
			local chip = button(up.list, "Stock" .. k, 5)
			chip.LayoutOrder = order
			chip.MouseButton1Click:Connect(function()
				local list = movesFrom(k)
				if st.busy or #list == 0 then
					return
				end
				local step = 1
				local pick = st.moves[st.index]
				if pick then
					for i, index in movesFrom(pick.from) do
						if index == st.index then
							step = i
						end
					end
				end
				st.index = list[math.min(step, #list)]
				refresh()
			end)
			up.stock[k] = chip
		end
	end

	-- Цели внизу справа: на 1–4 шага вперёд, на кнопке — шанс.
	up.stepRow = make("Frame", "Steps", up.dstPanel, 4)
	for i = 1, maxSteps do
		local b = button(up.stepRow, "Step" .. i, 5)
		b.MouseButton1Click:Connect(function()
			local pick = st.moves[st.index]
			if st.busy or not pick then
				return
			end
			local list = movesFrom(pick.from)
			if list[i] then
				st.index = list[i]
				refresh()
			end
		end)
		up.steps[i] = b
	end

	-- Круг шанса рисует ProducerShow — тот же, что крутится в попытке.
	up.dial = make("Frame", "Dial", screens.Upgrade, 3)
	up.dialSize = 0
	up.go = button(screens.Upgrade, "Upgrade", 3)
	local cost = UpgraderConfig.COST or 0
	up.go.Text = cost > 0 and ("АПГРЕЙД ЗА " .. cost) or "АПГРЕЙД"

	function up.rebuild(counts)
		local keep = st.moves[st.index]
		st.moves = {}
		for _, spine in UpgraderConfig.SPINES do
			for _, k in spine do
				if (counts[k] or 0) > 0 then
					for _, target in UpgraderConfig.Targets(k) do
						st.moves[#st.moves + 1] = { from = k, to = target.key, chance = target.chance }
					end
				end
			end
		end
		-- Выбор игрока переживает пополнение сумки: иначе каждая покупка сбрасывала бы его.
		st.index = 1
		if keep then
			for i, move in st.moves do
				if move.from == keep.from and move.to == keep.to then
					st.index = i
					break
				end
			end
		end
		-- После удачной попытки выбор переходит на полученный элемент: следующий шаг его ветки.
		if st.follow and (counts[st.follow] or 0) > 0 then
			for i, move in st.moves do
				if move.from == st.follow then
					st.index = i
					break
				end
			end
			st.follow = nil
		end
	end

	up.go.MouseButton1Click:Connect(function()
		local pick = st.moves[st.index]
		if st.busy or not pick then
			return
		end
		-- Ветку, шанс и наличие элемента проверяет сервер; здесь только просьба.
		lock(1, "Upgrade")
		RequestUpgrade:FireServer(pick.from, pick.to)
	end)

	-- ============ Показания ============
	refresh = function()
		local cap = st.cap
		for _, k in BASE_ORDER do
			local c = cards[k]
			paintElement(c.swatch, k)
			c.count.Visible = st.haveCounts
			c.count.Text = Theme.Readout("Есть", tostring(st.counts[k] or 0), Theme.color.text, cap)
			Theme.Button(c.buy, "action")
			-- «Стандарт» настройки «Кнопки действий»: кнопка покупки — тёмный тон своего элемента
			-- с его кантом, как карточка над ней. Наведение осветляет этот тон (ThemeBase).
			if Settings.Get("buttonStyle") == "standard" then
				local col = (st.skin.button and st.skin.button[k]) or Elements[k].color
				local body = Theme.Shadowed(col, 0.62)
				c.buy.BackgroundColor3 = body
				c.buy:SetAttribute("ThemeBase", body)
				c.buy.TextColor3 = Theme.color.text
				Theme.Stroke(c.buy, col, 1, 0)
			end
		end

		-- Барабаны в покое — приглушённые (просьба автора): корпус, кант, засечка и узор
		-- гаснут, а надпись со стихией и шансом остаётся яркой.
		for k, tile in roul.tiles do
			paintElement(tile, k, true)
			tile.Label.TextColor3 = Theme.color.text
		end
		for n, b in roul.counts do
			Theme.Button(b, n == st.spins and "active" or "ghost")
		end
		roul.go.Text = "КРУТИТЬ ЗА " .. RouletteConfig.TotalCost(st.spins)
		Theme.Button(roul.go, st.busy and "muted" or "action")

		-- Апгрейдер. Пока идёт попытка, картинка стоит: сервер уже забрал вложенное, и выбор
		-- под ней может смениться, а круг и пара должны показывать разыгранное.
		-- Кнопка без действия — декорация: когда апгрейдить нечего, пары и попытки нет.
		local pick = st.moves[st.index]
		local showing = st.busy ~= nil and st.busy.show == "Upgrade"
		if not showing then
			for k, chip in up.stock do
				local n = st.counts[k] or 0
				chip.Visible = n > 0
				chip.Text = Theme.Caps(Elements[k].name) .. " ×" .. n
				-- Выбранная фишка — в полную силу, остальные приглушены, как кнопки стройки.
				paintElement(chip, k, not (pick and pick.from == k))
			end
			up.src.Visible = pick ~= nil
			up.dst.Visible = pick ~= nil
			up.dial.Visible = pick ~= nil
			up.empty.Visible = pick == nil and st.haveCounts
			local list = pick and movesFrom(pick.from) or {}
			for i, b in up.steps do
				local move = st.moves[list[i]]
				b.Visible = move ~= nil
				if move then
					b.Text = percent(move.chance)
					Theme.Button(b, list[i] == st.index and "active" or "ghost")
				end
			end
			if pick then
				paintPair(pick.from, pick.to)
				-- Сменилась пара — по сменившейся ячейке проходит помеха (просьба автора). Толчок
				-- на ячейке с узором элемента автор отверг: смотрится плохо (2026-09-23).
				local was = up.shown or {}
				if was.from ~= pick.from then
					Show.Noise(up.src)
				end
				if was.to ~= pick.to then
					Show.Noise(up.dst)
				end
				up.shown = { from = pick.from, to = pick.to }
				local key = pick.chance .. "|" .. up.dialSize
				if up.dialKey ~= key then
					up.dialKey = key
					Show.Dial(up.dial, pick.chance, up.dialSize, 4)
				end
			end
		end
		up.go.Visible = pick ~= nil or showing
		Theme.Button(up.go, st.busy and "muted" or "action")

		-- Выбранный режим — как пункт меню: вывороткой плашки и скобкой «>».
		for _, m in MODES do
			local on = m.id == st.mode
			Theme.Button(modeButtons[m.id], on and "active" or "ghost")
			modeButtons[m.id].Text = (on and "> " or "  ") .. Theme.Caps(m.name)
		end
		local amount = gui:GetAttribute("Matter")
		matterBox.Visible = amount ~= nil
		-- Материя не прыгает, а добегает до нового числа: на бегу убыль красная, прибыль
		-- бирюзовая, в конце — обычный цвет.
		if amount ~= nil and amount ~= st.matter then
			local from = st.matterShown or amount
			local tint = amount < from and Theme.color.danger or Theme.color.action
			st.matter = amount
			if st.matterCount then
				st.matterCount:Cancel()
			end
			st.matterCount = Show.Count(from, amount, 0.4, function(x, exact)
				st.matterShown = x
				matter.Text = tostring(math.floor(x + 0.5))
				matter.TextColor3 = exact and Theme.color.energy or tint
			end)
		end
	end

	local function setMode(id)
		local was = st.mode
		st.mode = id
		for sid, s in screens do
			s.Visible = sid == id
		end
		-- Новый экран въезжает с той стороны, где его пункт в подвале.
		if was and was ~= id then
			local from, to = 0, 0
			for i, m in MODES do
				if m.id == was then
					from = i
				elseif m.id == id then
					to = i
				end
			end
			Show.Slide(screens[id], to > from and 1 or -1)
		end
		refresh()
	end

	for _, m in MODES do
		modeButtons[m.id].MouseButton1Click:Connect(function()
			setMode(m.id)
		end)
	end

	-- ============ Раскладка ============
	-- Всё считается от размера вкладки. Телефон, низкое или узкое окно — «компактно»: те же
	-- места, мельче отступы и текст, но кнопки не ниже 44 пикселей — это палец. Узкое — уже
	-- 1024: в крупной раскладке названиям в апгрейдере там не хватило бы места.
	local function layout()
		local W, H = buyFrame.AbsoluteSize.X, buyFrame.AbsoluteSize.Y
		if W < 100 or H < 100 then
			return
		end
		local compact = MobileUI.isMobile or H < 520 or W < 1024
		local function by(phone, pc)
			return compact and phone or pc
		end
		st.cap = by(11, 14)

		-- Рамка — под полосой Roblox, с отступом от краёв экрана.
		-- Внутри: шапка, линия, поле режима, линия, подвал.
		local strip = math.max(MobileUI.TopInset, GuiService.TopbarInset.Height)
		local margin = by(14, 26)
		local top = strip + by(8, 12)
		local AW, AH = W - margin * 2, H - top - by(10, 14)
		local px, pt, pb = by(12, 20), by(10, 14), by(8, 12)
		local g = by(6, 16)
		local titleH = by(34, 44)
		local rowH = by(44, 50)
		local footGap = by(6, 10)

		-- Окно по размеру карточек (просьба автора, #221): поле режима не шире 1600 и
		-- на большом экране не выше 460 — высоты карточки покупки; рамка обнимает поле,
		-- лишнего пустого фона вокруг нет, и окно стоит посередине. Размер общий у трёх
		-- вкладок: при смене режима рамка не прыгает.
		local CY = pt + titleH + g
		local below = g + footGap + rowH + pb
		local CX = px
		local CW = math.min(AW - px * 2, 1600)
		local CH = AH - CY - below
		if not compact then
			CH = math.min(CH, 460)
		end
		local MW, MH = CW + px * 2, CY + CH + below
		place(mon, margin + math.floor((AW - MW) / 2), top + math.floor((AH - MH) / 2), MW, MH)
		paintDots(math.floor(MW), math.floor(MH))

		-- Шапка.
		-- Крестик — справа вверху, как выход во всех окнах и «Назад» главного меню: той же
		-- высоты, по середине строки названия. На телефоне шире, под палец. Материя — слева.
		-- Материя и крестик крупнее прежнего (просьба автора, #227).
		local closeW, closeH = by(52, 44), by(34, 44)
		local closeY = pt + math.max(0, math.floor((titleH - closeH) / 2))
		place(close, MW - px - closeW, closeY, closeW, closeH)
		local matterW, matterH = by(220, 320), closeH
		local headW = MW - px * 2 - closeW - matterW - g * 2
		head.TextSize = by(20, 32)
		place(head, px, pt, headW, titleH)
		matter.TextSize = by(24, 30)
		matterCaption.TextSize = by(17, 20)
		place(matterBox, MW - px - closeW - g, closeY, 0, matterH)

		-- Подвал: режимы пунктами меню.
		local footY = MH - pb - rowH
		local tabGap = by(6, 10)
		local tabW = math.min(by(120, 220), (MW - px * 2 - tabGap * (#MODES - 1)) / #MODES)
		place(map, px, footY, tabW * #MODES + tabGap * (#MODES - 1), rowH)
		for i, m in MODES do
			local b = modeButtons[m.id]
			b.TextSize = by(13, 18)
			b.Pad.PaddingLeft = UDim.new(0, by(10, 16))
			place(b, (i - 1) * (tabW + tabGap), 0, tabW, rowH)
		end

		-- Поле режима — между линиями, размер посчитан выше.
		for _, s in screens do
			place(s, CX, CY, CW, CH)
		end

		-- Покупка: четыре карточки в ряд.
		local cp = by(4, 12)
		local cardW = (CW - g * 3) / 4
		local cardH = CH
		local countH, buyH = by(20, 34), by(44, 64)
		for i, k in BASE_ORDER do
			local c = cards[k]
			local w = cardW - cp * 2
			place(c.card, (i - 1) * (cardW + g), (CH - cardH) / 2, cardW, cardH)
			place(c.swatch, cp, cp, w, cardH - cp * 4 - countH - buyH)
			place(c.count, cp, cardH - cp * 2 - buyH - countH, w, countH)
			place(c.buy, cp, cardH - cp - buyH, w, buyH)
			c.swatch.TextSize = by(16, 30)
			c.count.TextSize = by(16, 26)
			c.buy.TextSize = by(14, 22)
		end

		-- Рулетка и апгрейдер: экран слева, управление столбцом справа.
		local colW = by(250, 440)
		local stageW = CW - colW - g
		local colX = stageW + g
		local btnH = by(44, 72)

		place(roul.stage, 0, 0, stageW, CH)
		local tp, tg = by(8, 16), by(6, 12)
		local tw = (stageW - tp * 2 - tg * (#roul.keys - 1)) / math.max(#roul.keys, 1)
		local tileSize = fitSize(roul.words, by(14, 26), tw - 8)
		for i, k in roul.keys do
			local tile = roul.tiles[k]
			place(tile, tp + (i - 1) * (tw + tg), tp, tw, CH - tp * 2)
			tile.TextSize = tileSize
		end
		local rowY = by(20, 34)
		roul.caption.TextSize = by(11, 14)
		place(roul.caption, colX, 0, colW, rowY - by(4, 8))
		Theme.Section(roul.caption, "Прокруток")
		local nw = (colW - g * (#roul.counts - 1)) / math.max(#roul.counts, 1)
		for n, b in roul.counts do
			place(b, colX + (n - 1) * (nw + g), rowY, nw, btnH)
			b.TextSize = by(18, 30)
		end
		place(roul.go, colX, CH - btnH, colW, btnH)
		roul.go.TextSize = by(16, 26)

		-- Апгрейдер: слева отдаю, в середине круг шанса и кнопка, справа получаю.
		local dialH = CH - btnH - g
		local dialW = math.max(math.min(dialH, math.floor(CW * 0.34)), 60)
		local sideW = (CW - dialW - g * 2) / 2
		place(up.srcPanel, 0, 0, sideW, CH)
		place(up.dstPanel, CW - sideW, 0, sideW, CH)
		place(up.dial, sideW + g, 0, dialW, dialH)
		up.dialSize = math.max(math.min(dialW, dialH), 30)
		place(up.go, sideW + g, CH - btnH, dialW, btnH)
		up.go.TextSize = by(16, 26)

		local pp, capH, gap = by(6, 16), by(16, 26), by(4, 8)
		local chipW, chipH = by(104, 160), by(44, 56)
		local bw = sideW - pp * 2
		for cap, caption in { [up.srcCap] = "Затраты", [up.dstCap] = "Результат" } do
			cap.TextSize = by(11, 14)
			place(cap, pp, pp, bw, capH)
			Theme.Section(cap, caption)
		end
		local burnH = up.burn.Visible and by(14, 22) or 0
		up.burn.TextSize = by(10, 14)
		place(up.burn, pp, pp + capH, bw, burnH)
		-- Запас: строка на телефоне, две на большом экране, остальное — прокруткой.
		local listH = by(chipH, chipH * 2 + gap)
		local listY = CH - pp - listH
		place(up.list, pp, listY, bw, listH)
		up.grid.CellSize = UDim2.fromOffset(chipW, chipH)
		up.grid.CellPadding = UDim2.fromOffset(gap, gap)
		local chipSize = fitSize(up.words, by(12, 16), chipW - 8)
		for _, chip in up.stock do
			chip.TextSize = chipSize
		end
		-- Плашки элементов слева и справа одной высоты; цели — на уровне запаса.
		local top = pp + capH + burnH + gap
		local blockH = listY - gap - top
		place(up.src, pp, top, bw, blockH)
		place(up.empty, pp, top, bw, blockH)
		place(up.dst, pp, top, bw, blockH)
		local nameSize = fitSize(up.words, by(16, 30), bw - 8)
		up.src.TextSize = nameSize
		up.dst.TextSize = nameSize
		up.empty.TextSize = by(12, 20)
		place(up.stepRow, pp, listY, bw, chipH)
		local sw = (bw - gap * (#up.steps - 1)) / math.max(#up.steps, 1)
		for i, b in up.steps do
			place(b, (i - 1) * (sw + gap), 0, sw, chipH)
			b.TextSize = by(14, 22)
		end

		refresh()
	end

	-- Окно открыли — цвета модели и запас перечитываются: локацию строят под забег.
	local function open()
		if not (gui.Enabled and buyFrame.Visible) then
			return
		end
		st.skin = Skin.Read()
		if not st.haveCounts and next(inventory) ~= nil then
			st.counts = inventory
			st.haveCounts = true
			up.rebuild(inventory)
		end
		layout()
		-- Монитор раскрывается, как окна игры (Theme.Open); помехи у производителя нет.
		Theme.Open(mon)
	end

	-- Пока идёт показ, новый запуск всё равно не примут (замок на сервере) — и кнопки
	-- на это время не выглядят рабочими. Замок ставится уже по нажатию: иначе, пока идёт
	-- ответ сервера, успели бы уйти и прокрутка, и попытка. Откажет сервер — замок сам
	-- снимется через секунду.
	lock = function(time, show)
		local token = { show = show }
		st.busy = token
		refresh()
		task.delay(time, function()
			if st.busy == token then
				st.busy = nil
				refresh()
			end
		end)
	end

	gui:GetPropertyChangedSignal("Enabled"):Connect(open)
	buyFrame:GetPropertyChangedSignal("Visible"):Connect(open)
	buyFrame:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
	GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(layout)
	MobileUI.OnViewportChanged(layout)
	gui:GetAttributeChangedSignal("Matter"):Connect(refresh)
	-- Смену «Кнопок действий» перекрашивает UITheme; покупку в цвет элемента («Стандарт»)
	-- докрашивает refresh — после UITheme, поэтому отложенно.
	Settings.Changed.Event:Connect(function(key)
		if key == "buttonStyle" then
			task.defer(refresh)
		end
	end)
	-- Обработчик ниже по скрипту обновляет inventory позже этого, поэтому запас берётся
	-- из самого события, а не из таблицы.
	-- Пришло в запас — «+n» всплывает там, откуда пришло: над карточкой покупки, плиткой
	-- рулетки или целью апгрейда. Сама ячейка не вздрагивает: толчок на узоре элемента
	-- смотрится плохо (замечание автора), а помеха в магазине не к месту.
	local function gained(before, after)
		for k, n in after do
			local plus = n - (before[k] or 0)
			if plus > 0 and Elements[k] then
				local host
				if st.mode == "Buy" and cards[k] then
					host = cards[k].swatch
					Show.Pop(cards[k].count, 0.2, 0.3)
				elseif st.mode == "Roulette" then
					host = roul.tiles[k]
				elseif st.mode == "Upgrade" and up.landing == k then
					host = up.dst
					up.landing = nil
				end
				if host then
					local col = (st.skin.button and st.skin.button[k]) or Elements[k].color
					local size = math.clamp(math.floor(host.AbsoluteSize.Y * 0.4), 16, 32)
					Show.Float(host, "+" .. plus, col:Lerp(Color3.new(1, 1, 1), 0.3), size)
				-- Несколько элементов разом (три барабана) звучат одним откликом: UISound не
				-- повторяет звук чаще раза в 0,045 с.
				UISound.Play("Gain")
				end
			end
		end
	end

	InventoryChanged.OnClientEvent:Connect(function(counts)
		local before = st.haveCounts and st.counts or nil
		st.counts = counts
		st.haveCounts = true
		up.rebuild(counts)
		refresh()
		if before and gui.Enabled and buyFrame.Visible then
			gained(before, counts)
		end
	end)

	-- Итог уже разыграл сервер; барабаны и стрелка только приходят к нему, элементы
	-- придут в инвентарь после показа. Код показа — в ProducerShow.
	-- Выданное сервер шлёт ровно в конце показа: замок держится чуть дольше, на дорогу.
	local GRACE = 0.3
	-- Сколько идёт показ, решает сервер (первый запуск медленный, серия быстрее) и шлёт с итогом.
	-- Джекпот (RouletteConfig.Jackpot): третьим сервер шлёт элемент подарка. Показ и замок
	-- длиннее на JACKPOT_TIME, подарок приходит вместе с выпавшим.
	Remotes:WaitForChild("RouletteShow").OnClientEvent:Connect(function(results, time, bonus)
		time = time or RouletteConfig.SHOW_TIME
		local jackpot = bonus and Elements[bonus] and {
			key = bonus,
			amount = RouletteConfig.JACKPOT_BONUS,
			count = #results,
			time = RouletteConfig.JACKPOT_TIME,
		} or nil
		setMode("Roulette")
		lock(time + (jackpot and jackpot.time or 0) + GRACE, "Roulette")
		Show.Roulette(roul.stage, Skin.Read(), results, time, jackpot)
	end)
	Remotes:WaitForChild("UpgradeShow").OnClientEvent:Connect(function(result)
		st.follow = result.won and result.to or nil
		-- Выигранное придёт в запас после показа — его «+1» всплывёт над целью.
		up.landing = st.follow
		setMode("Upgrade")
		lock(UpgraderConfig.SHOW_TIME + GRACE, "Upgrade")
		-- Пара и круг — ровно то, что разыграл сервер; стрелка крутится прямо на круге.
		paintPair(result.from, result.to)
		up.src.Visible, up.dst.Visible, up.dial.Visible, up.empty.Visible = true, true, true, false
		up.dialKey = nil
		-- Встала стрелка: выигранная цель вспыхивает бирюзой; при неудаче вложенное трясёт,
		-- а если оно сгорает — вспыхивает красным. Звук у каждого из трёх итогов свой.
		Show.SpinDial(up.dial, result, UpgraderConfig.SHOW_TIME, up.dialSize, 4, function(won)
			if won then
				Show.Flash(up.dst, Theme.color.action, 0.5)
				UISound.Play("Win")
			else
				Show.Shake(up.src, 8, 0.45)
				if UpgraderConfig.BURN_ON_FAIL then
					Show.Flash(up.src, Theme.color.danger, 0.6)
					UISound.Play("Burn")
				else
					UISound.Play("Fail")
				end
			end
		end)
	end)

	up.rebuild(st.counts)
	setMode("Buy")
	layout()
end
buildProducer()

-- ============ Вкладка "Крафт" ============

local craftFrame = Instance.new("Frame")
craftFrame.Size = UDim2.new(1, 0, 1, 0)
craftFrame.BackgroundTransparency = 1
craftFrame.Visible = false
craftFrame.Parent = body
craftFrame.Name = "CraftTab"
tabFrames["Крафт"] = craftFrame

-- Верхний блок (слоты + кнопка + подсказка) фиксированной высоты, ниже — список инвентаря.
-- 200px под список — это примерно четыре строки, дальше он скроллится.
--
-- Кнопка «Скрестить» стоит в одной строке со слотами, а не отдельной полосой под ними.
-- Отдельной полосой она забирала на телефоне 86 пикселей высоты, а высота окна там упирается
-- в потолок applyHeight (0.92 рабочей высоты экрана) — вычитались эти пиксели ровно из списка
-- инвентаря снизу: на узком экране ему оставалось около 30px, то есть половина одной строки
-- из 48. Справа кнопке хватает своей ширины, слотам достаётся остальное.
local SLOT_H = MobileUI.isMobile and 56 or 84
local PLUS_W = MobileUI.isMobile and 22 or 40
local CRAFT_W = MobileUI.isMobile and 100 or 200
local ROW_GAP = 8
local TOP_PAD = 6
-- Стол занимает всю ширину вкладки и стал выше: это главное действие вкладки,
-- и полоска в 752 пикселя посреди полного экрана читалась как обрезок старого окна.
-- Потолок остаётся только от сверхшироких экранов, где слот ушёл бы за метр.
local CRAFT_ROW_MAX = 1400
-- Высота верхнего блока: отступ, строка слотов, отступ, подпись раздела, отступ.
-- Подсказка отсюда ушла в статусную строку окна, а её место заняла подпись со счётчиком.
local SECTION_H = 16
local TOP_H = TOP_PAD + SLOT_H + 8 + SECTION_H + 4

local slots = { nil, nil } -- ключи выбранных элементов, порядок значения не имеет (см. Recipes)

-- Кнопки списка инвентаря по ключу элемента — чтобы пометить галочкой ту, что сейчас
-- лежит в слоте крафта. Число «шт N» рядом с ней при этом не меняется: сервер спишет
-- элемент только в момент самого крафта (см. подтверждение ниже), а не при выборе.
-- Без пометки строка в инвентаре выглядела так, будто выбор в слот вообще ни на что
-- не повлиял — количество то же самое, связи со столом не видно.
local invButtons = {}

local function refreshSlotMarks()
	for key, btn in invButtons do
		local inSlot = slots[1] == key or slots[2] == key
		local mark = btn:FindFirstChild("SlotMark")
		if inSlot and not mark then
			mark = Instance.new("TextLabel")
			mark.Name = "SlotMark"
			mark.AnchorPoint = Vector2.new(1, 0)
			mark.Position = UDim2.new(1, -3, 0, 2)
			mark.Size = UDim2.new(0, 16, 0, 16)
			mark.BackgroundTransparency = 1
			mark.FontFace = Theme.font.strong
			mark.TextSize = 14
			mark.TextColor3 = Theme.color.accent
			mark.Text = "✓"
			mark.ZIndex = btn.ZIndex + 1
			mark.Parent = btn
		elseif not inSlot and mark then
			mark:Destroy()
		end
	end
end

-- Слоты лежат в своей строке-контейнере, а не считают доли от ширины вкладки: справа от них
-- теперь стоит кнопка фиксированной ширины, и вычитать её пришлось бы из каждой доли
-- отдельно. Контейнер вычитает её один раз, внутри слоты снова делят ширину пополам,
-- а «+» встаёт по центру строки — то есть ровно между ними при любой ширине окна.
-- (Раньше место «+» задавалось жёсткими 186px от края — верно только для пиксельных слотов
-- ПК, а на телефоне слоты считались долями, и «+» печатался поверх первого слота.)
local craftRow = Instance.new("Frame")
craftRow.Size = UDim2.new(1, 0, 0, SLOT_H)
craftRow.Position = UDim2.new(0, 0, 0, TOP_PAD)
craftRow.BackgroundTransparency = 1
craftRow.Parent = craftFrame

local craftLimit = Instance.new("UISizeConstraint")
craftLimit.MaxSize = Vector2.new(CRAFT_ROW_MAX, math.huge)
craftLimit.Parent = craftRow

local slotRow = Instance.new("Frame")
slotRow.Size = UDim2.new(1, -(CRAFT_W + ROW_GAP), 1, 0)
slotRow.Position = UDim2.new(0, 0, 0, 0)
slotRow.BackgroundTransparency = 1
slotRow.Parent = craftRow

local slotA = Instance.new("TextButton")
slotA.Size = UDim2.new(0.5, -PLUS_W / 2, 1, 0)
slotA.Position = UDim2.new(0, 0, 0, 0)
slotA.FontFace = Theme.font.strong
slotA.TextSize = 16
slotA.Parent = slotRow

local plusLabel = Instance.new("TextLabel")
plusLabel.Size = UDim2.new(0, PLUS_W, 1, 0)
plusLabel.Position = UDim2.new(0.5, -PLUS_W / 2, 0, 0)
plusLabel.BackgroundTransparency = 1
plusLabel.FontFace = Theme.font.strong
plusLabel.TextSize = 22
plusLabel.TextColor3 = Theme.color.textDim
plusLabel.Text = "+"
plusLabel.Parent = slotRow

local slotB = Instance.new("TextButton")
slotB.AnchorPoint = Vector2.new(1, 0)
slotB.Size = UDim2.new(0.5, -PLUS_W / 2, 1, 0)
slotB.Position = UDim2.new(1, 0, 0, 0)
slotB.FontFace = Theme.font.strong
slotB.TextSize = 16
slotB.Parent = slotRow


-- Прижата к правому краю вкладки, а не поставлена по пиксельному отступу: на ПК окно шире
-- слотов, и кнопка, посаженная на 412px, висела посреди пустого места.
local craftButton = Instance.new("TextButton")
craftButton.AnchorPoint = Vector2.new(1, 0)
craftButton.Size = UDim2.new(0, CRAFT_W, 1, 0)
craftButton.Position = UDim2.new(1, 0, 0, 0)
craftButton.FontFace = Theme.font.strong
craftButton.TextSize = 16
craftButton.TextTruncate = Enum.TextTruncate.AtEnd -- «→ ЭЛЕКТРИЧЕСТВО» шире кнопки
craftButton.Text = "СКРЕСТИТЬ"
craftButton.Parent = craftRow


local invSection = Instance.new("TextLabel")
invSection.Size = UDim2.new(1, 0, 0, SECTION_H)
invSection.Position = UDim2.new(0, 0, 0, TOP_PAD + SLOT_H + 8)
invSection.TextSize = 11
invSection.Parent = craftFrame

Theme.Section(invSection, "инвентарь", 0)

local invList = Instance.new("ScrollingFrame")
-- Занимает всё, что осталось от вкладки под верхним блоком: список — единственное здесь,
-- что растёт вместе с окном, и отдавать ему остаток целиком правильнее, чем резервировать
-- пиксели, которых на телефоне и так нет.
invList.Size = UDim2.new(1, 0, 1, -TOP_H)
invList.Position = UDim2.new(0, 0, 0, TOP_H)
invList.BackgroundTransparency = 1
invList.BorderSizePixel = 0
invList.ScrollBarThickness = 6
invList.AutomaticCanvasSize = Enum.AutomaticSize.Y
invList.CanvasSize = UDim2.new(0, 0, 0, 0)
invList.Parent = craftFrame

Theme.Scroller(invList)
Theme.DragScroll(invList)

-- Пустой инвентарь под столом был просто пустотой: подпись «ИНВЕНТАРЬ // 0»
-- и полэкрана ничего — непонятно, вкладка не догрузилась или класть в слоты нечего.
-- Та же карточка, что в окне инвентаря (InventoryUI.emptyCard), и лежит она так же
-- РЯДОМ со списком, а не внутри: refreshInventoryList зовёт invList:ClearAllChildren()
-- на каждый приход инвентаря.
local invEmpty = Instance.new("Frame")
invEmpty.Name = "Empty"
invEmpty.AnchorPoint = Vector2.new(0.5, 0)
invEmpty.Size = UDim2.new(0, MobileUI.isMobile and 300 or 420, 0, 0)
invEmpty.AutomaticSize = Enum.AutomaticSize.Y
invEmpty.Visible = false
invEmpty.Parent = craftFrame

-- Без решётки (depth = false): на плашках с AutomaticSize она не строится вовсе
-- (см. Theme.Backdrop) — тот же разбор, что у карточки в InventoryUI.
Theme.Panel(invEmpty, { color = Theme.color.panelSoft, depth = false })

local invEmptyPad = Instance.new("UIPadding")
invEmptyPad.PaddingTop = UDim.new(0, 16)
invEmptyPad.PaddingBottom = UDim.new(0, 16)
invEmptyPad.PaddingLeft = UDim.new(0, 18)
invEmptyPad.PaddingRight = UDim.new(0, 18)
invEmptyPad.Parent = invEmpty

local invEmptyList = Instance.new("UIListLayout")
invEmptyList.SortOrder = Enum.SortOrder.LayoutOrder
invEmptyList.Padding = UDim.new(0, 6)
invEmptyList.Parent = invEmpty

local invEmptyTitle = Instance.new("TextLabel")
invEmptyTitle.LayoutOrder = 1
invEmptyTitle.Size = UDim2.new(1, 0, 0, 20)
invEmptyTitle.BackgroundTransparency = 1
invEmptyTitle.FontFace = Theme.font.strong
invEmptyTitle.TextSize = 15
invEmptyTitle.TextXAlignment = Enum.TextXAlignment.Left
invEmptyTitle.TextColor3 = Theme.color.textDim
invEmptyTitle.Text = Theme.Caps("пусто")
invEmptyTitle.Parent = invEmpty

local invEmptyText = Instance.new("TextLabel")
invEmptyText.LayoutOrder = 2
invEmptyText.Size = UDim2.new(1, 0, 0, 0)
invEmptyText.AutomaticSize = Enum.AutomaticSize.Y
invEmptyText.BackgroundTransparency = 1
invEmptyText.FontFace = Theme.font.body
invEmptyText.TextSize = 13
invEmptyText.TextWrapped = true
invEmptyText.TextXAlignment = Enum.TextXAlignment.Left
invEmptyText.TextYAlignment = Enum.TextYAlignment.Top
invEmptyText.TextColor3 = Theme.color.textMute
invEmptyText.Text = "Класть в слоты пока нечего. Возьмите базовый элемент на вкладке «Купить» — он появится здесь."
invEmptyText.Parent = invEmpty

-- Окно меняет ширину вместе с экраном, а число колонок считается от неё.
invList:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
	local layout = invList:FindFirstChildOfClass("UIGridLayout")
	if layout then
		Theme.GridFit(layout)
	end
end)

-- Надпись ячейки живёт на дочернем Caption (см. Theme.ElementButton), поэтому кегль
-- меняется в двух местах: на самой кнопке (оттуда его возьмёт следующая пересборка)
-- и на готовой надписи (чтобы видно было сразу).
local function setCellTextSize(button, size)
	button.TextSize = size
	local caption = button:FindFirstChild("Caption")
	if caption then
		caption.TextSize = size
	end
end

-- Стол — главный предмет вкладки, и высота у него долевая, а не постоянная: полоской
-- в пятьдесят пикселей посреди полного экрана он читался обрезком старого окна.
-- На телефоне высоты и так нет — там остаётся пальцевая строка.
local function applyCraftLayout()
	local w, h = craftFrame.AbsoluteSize.X, craftFrame.AbsoluteSize.Y
	if h < 40 or w < 40 then
		return
	end
	local slotH = MobileUI.isMobile and SLOT_H or math.clamp(math.floor(h * 0.26), 84, 220)

	-- Вся вкладка стоит одной колонкой. До этого стол был ограничен CRAFT_ROW_MAX и прижат
	-- влево, а подпись раздела и список под ним шли во всю ширину: на мониторе 1914
	-- стол кончался на 1415, а линия под ним — на 1900, и вкладка читалась как два разных
	-- окна, наложенных друг на друга.
	--
	-- Ширина и отступ считаются здесь, а не задаются UISizeConstraint внутри списка:
	-- refreshInventoryList зовёт invList:ClearAllChildren(), и ограничение, положенное внутрь,
	-- снесло бы первым же обновлением инвентаря — та же грабля, что в InventoryUI.
	local colW = math.min(w, CRAFT_ROW_MAX)
	local colX = math.max(0, math.floor((w - colW) / 2))

	craftRow.Position = UDim2.new(0, colX, 0, TOP_PAD)
	craftRow.Size = UDim2.new(0, colW, 0, slotH)

	local topH = TOP_PAD + slotH + 8 + SECTION_H + 4
	invSection.Position = UDim2.new(0, colX, 0, TOP_PAD + slotH + 8)
	invSection.Size = UDim2.new(0, colW, 0, SECTION_H)
	invList.Position = UDim2.new(0, colX, 0, topH)
	invList.Size = UDim2.new(0, colW, 1, -topH)
	-- Карточка «пусто» — по середине той же колонки, чуть ниже верха списка:
	-- точно по центру остатка она на мониторе уезжала бы к самому низу экрана.
	invEmpty.Position = UDim2.new(0, colX + math.floor(colW / 2), 0, topH + 24)

	-- Кегль внутри стола тоже от его высоты: имя элемента в шестнадцать пунктов
	-- теряется посреди поля в двести.
	local big = slotH >= 120
	setCellTextSize(slotA, big and 26 or 16)
	setCellTextSize(slotB, big and 26 or 16)
	setCellTextSize(craftButton, big and 20 or 16)
	plusLabel.TextSize = big and 34 or 22
end

applyCraftLayout()
craftFrame:GetPropertyChangedSignal("AbsoluteSize"):Connect(applyCraftLayout)

local function renderSlot(button, key)
	button.Text = key and Theme.Caps(Elements[key].name) or "— ПУСТО —"
	-- Цветная полоска смотрит в сторону «+»: у левого слота она у правого края, у правого —
	-- у левого (решение автора, задача #105). Слоты сходятся к плюсу, и цвет, отвёрнутый
	-- от него наружу, показывал не туда, куда идёт действие. Сторона считается по самой
	-- кнопке, а не приходит аргументом: renderSlot зовут из восьми мест, и восьмой раз
	-- этот флаг однажды передали бы неверно.
	Theme.ElementButton(button, key and Elements[key].color or nil, { right = button == slotA, element = key })
end

local function refreshCraftButton()
	local ready = slots[1] ~= nil and slots[2] ~= nil
	-- Готовность кнопки — это целиком её вид, а не два отдельных цвета: в выключенном
	-- состоянии гаснет и кант тоже.
	Theme.Button(craftButton, ready and "action" or "muted")

	-- Уже открытый рецепт показывается прямо на кнопке. Это не новое знание — пара
	-- уже лежит в «Справочнике», — но избавляет от привычки скрещивать и только потом
	-- сверяться с деревом. Неизвестная пара остаётся неизвестной: кнопка не намекает
	-- даже на то, есть ли у неё рецепт вообще.
	local known = nil
	if ready then
		local recipe = Recipes.Find(slots[1], slots[2])
		if recipe and knownRecipes[recipe.result] then
			known = Elements[recipe.result].name
		end
	end
	craftButton.Text = known and ("→ " .. Theme.Caps(known)) or "СКРЕСТИТЬ"
	refreshSlotMarks()
end

renderSlot(slotA, nil)
renderSlot(slotB, nil)
refreshCraftButton()

-- Клик по слоту очищает его — проще, чем перетаскивание, и хватает для двух слотов.
slotA.MouseButton1Click:Connect(function()
	slots[1] = nil
	renderSlot(slotA, nil)
	refreshCraftButton()
end)

slotB.MouseButton1Click:Connect(function()
	slots[2] = nil
	renderSlot(slotB, nil)
	refreshCraftButton()
end)

-- Клик по элементу инвентаря кладёт его ключ в первый свободный слот; если оба заняты —
-- заменяет первый. Одинаковый элемент можно выбрать в оба слота (Recipes.Find("Fire","Fire")
-- существует) — здесь только ключи, реальные счётчики проверяет сервер при крафте.
local function assignToSlot(key)
	if slots[1] == nil then
		slots[1] = key
	elseif slots[2] == nil then
		slots[2] = key
	else
		slots[1] = key
		slots[2] = nil
	end
	renderSlot(slotA, slots[1])
	renderSlot(slotB, slots[2])
	refreshCraftButton()
end

local function refreshInventoryList()
	invList:ClearAllChildren() -- вместе с ячейками сносит и раскладку, поэтому сетка собирается заново
	invButtons = {} -- список пересобран целиком, старые кнопки больше не существуют
	-- Сетка, а не колонка: под столом остаётся половина экрана, и сорок элементов
	-- одной колонкой — это десять видимых строк и прокрутка при пустых боках.
	local layout = Theme.Grid(invList, MobileUI.isMobile and 48 or 40, 300, 6)

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

	Theme.Section(invSection, "инвентарь", #keys)
	invEmpty.Visible = #keys == 0

	for i, key in keys do
		local data = Elements[key]

		local btn = Instance.new("TextButton")
		btn.LayoutOrder = i -- размер ячейки задаёт сетка
		btn.FontFace = Theme.font.strong
		btn.TextSize = MobileUI.isMobile and 16 or 14
		-- Номер, имя и счётчик одной строкой с разным кеглем — второго TextLabel
		-- у ячейки-кнопки нет, её надпись одна на всю строку.
		btn.RichText = true
		btn.TextXAlignment = Enum.TextXAlignment.Left
		btn.Text = ("%s   %s"):format(
			Theme.Caps(data.name),
			Theme.Readout("шт", inventory[key], Theme.Legible(data.color), 10)
		)
		btn.Parent = invList

		Theme.ElementButton(btn, data.color, { wide = true, element = key })
		invButtons[key] = btn

		btn.MouseButton1Click:Connect(function()
			if Theme.WasDragged(invList) then
				return
			end
			assignToSlot(key)
		end)
	end

	refreshSlotMarks()
end

-- ============ Подтверждение крафта ============
-- ТЗ v3: ошибка может стоить два элемента (верная пара, но не та, которую хотел), поэтому
-- крафт уходит на сервер только после явного подтверждения.

local confirmOverlay = Instance.new("Frame")
confirmOverlay.Size = UDim2.new(1, 0, 1, 0)
confirmOverlay.BackgroundColor3 = Theme.color.ink
confirmOverlay.BackgroundTransparency = 0.2
confirmOverlay.Visible = false
confirmOverlay.ZIndex = 10
confirmOverlay.Parent = root

local confirmBox = Instance.new("Frame")
-- Доля ширины окна с потолком: фиксированные 360px шире самого окна на узком телефоне.
-- Кнопки подтверждения на телефоне в MIN_TAP высотой: тут ошибка стоит двух элементов,
-- и промахнуться по 38px между «Скрестить» и «Отмена» дороже, чем где-либо ещё.
local CONFIRM_BTN_H = MobileUI.isMobile and MobileUI.MIN_TAP or 38

confirmBox.AnchorPoint = Vector2.new(0.5, 0.5)
confirmBox.Size = UDim2.new(0.9, 0, 0, 102 + CONFIRM_BTN_H)
confirmBox.Position = UDim2.new(0.5, 0, 0.5, 0)
confirmBox.ZIndex = 11
confirmBox.Parent = confirmOverlay

-- Карточка подтверждения — та же панель, но на тон светлее и без прозрачности: она лежит
-- поверх самого окна, и одинаковый цвет читался бы как дыра в нём.
-- Самое близкое к игроку окно во всём интерфейсе: лежит поверх Лаборатории, которая
-- сама поверх всего. Решётка здесь самая плотная, светлая и быстрая.
Theme.Panel(confirmBox, { color = Theme.color.panelSoft, transparency = 0, scene = "confirm" })

local confirmSize = Instance.new("UISizeConstraint")
confirmSize.MaxSize = Vector2.new(360, 102 + CONFIRM_BTN_H)
confirmSize.Parent = confirmBox

local confirmLabel = Instance.new("TextLabel")
confirmLabel.Size = UDim2.new(1, -24, 0, 64)
confirmLabel.Position = UDim2.new(0, 12, 0, 14)
confirmLabel.BackgroundTransparency = 1
confirmLabel.FontFace = Theme.font.strong
confirmLabel.TextSize = 17
confirmLabel.TextWrapped = true
confirmLabel.TextColor3 = Theme.color.text
confirmLabel.ZIndex = 11
confirmLabel.Parent = confirmBox

local yesButton = Instance.new("TextButton")
yesButton.Size = UDim2.new(0.44, 0, 0, CONFIRM_BTN_H)
yesButton.Position = UDim2.new(0, 16, 1, -(CONFIRM_BTN_H + 12))
yesButton.FontFace = Theme.font.strong
yesButton.TextSize = 15
yesButton.Text = "СКРЕСТИТЬ"
yesButton.ZIndex = 11
yesButton.Parent = confirmBox

Theme.Button(yesButton, "action")

local noButton = Instance.new("TextButton")
noButton.AnchorPoint = Vector2.new(1, 0)
noButton.Size = UDim2.new(0.44, 0, 0, CONFIRM_BTN_H)
noButton.Position = UDim2.new(1, -16, 1, -(CONFIRM_BTN_H + 12))
noButton.FontFace = Theme.font.strong
noButton.TextSize = 15
noButton.Text = "ОТМЕНА"
noButton.ZIndex = 11
noButton.Parent = confirmBox

Theme.Button(noButton, "quiet")

craftButton.MouseButton1Click:Connect(function()
	if not (slots[1] and slots[2]) then
		return
	end
	confirmLabel.Text = ("Скрестить %s + %s?"):format(Elements[slots[1]].name, Elements[slots[2]].name)
	confirmOverlay.Visible = true
	Theme.Open(confirmBox)
end)

noButton.MouseButton1Click:Connect(function()
	confirmOverlay.Visible = false
end)

yesButton.MouseButton1Click:Connect(function()
	RequestCraft:FireServer(slots[1], slots[2])
	confirmOverlay.Visible = false
	slots[1], slots[2] = nil, nil
	renderSlot(slotA, nil)
	renderSlot(slotB, nil)
	refreshCraftButton()
end)

-- ============ Вкладка "Справочник" ============
-- Граф рецептов: узел на каждый элемент, стрелка на каждый ингредиент. Где что стоит
-- и как линии обходят чужие узлы, считает RecipeGraph — здесь только рисование.
--
-- До этой задачи здесь стояло дерево по колонкам: линия одна, от старшего родителя,
-- второй ингредиент подписью «+ Земля» на самом узле. Оно читалось построчно и не имело
-- ни одного пересечения, но рисунка дерева развития не давало: ветки шли параллельными
-- полосами, и того, что четыре стихии расходятся из общего центра, а между ветками
-- натянута сетка перекрёстных рецептов, по нему было не увидеть. Форму задал автор —
-- тот же граф, который он собрал на стороннем сайте.
--
-- Что обещано и проверено на сборке: ни один узел не налезает на другой, и ни одна
-- стрелка не проходит сквозь чужой узел. Пересечения самих стрелок остаются: у каждого
-- элемента два родителя, и такой граф на плоскости без пересечений не рисуется вовсе.
--
-- Неоткрытому узлу по-прежнему видна только стрелка от старшего родителя — из какой ветки
-- он растёт. Вторая стрелка приходит вместе с открытым рецептом: иначе граф выдавал бы
-- пару целиком, и открывать в справочнике было бы нечего.
--
-- Карта отвечает на прикосновение: под курсором узел подрастает, его связи и соседи
-- загораются, остальное гаснет; по нажатию карта оставляет светящейся всю цепочку
-- создания элемента, а список под ней показывает эту же цепочку по шагам.

-- Графу отданы три четверти высоты, а не две трети, как было у дерева: картинка
-- почти квадратная, а полоса в треть экрана высотой показывает её полоской.
local GRAPH_SHARE = 0.74 -- какую долю высоты вкладки занимает граф, остальное — список рецептов
local ARROW = 8 -- длина уса наконечника
-- Карта в окно не влезает вовсе (орбиты расходятся на две с лишним тысячи пикселей) —
-- отсюда и нижняя граница масштаба, и кнопка «вписать целиком».
local ZOOM_MIN, ZOOM_MAX, ZOOM_STEP = 0.15, 1.6, 0.15

-- Связь идёт градиентом от цвета родителя к цвету ребёнка (решение автора;
-- это отменяет прежнее «все стрелки серые»). Градиента вдоль повёрнутого Frame нет,
-- поэтому переход собирается из звеньев самой кривой: каждое своего цвета.
--
-- Цвет смешивается с фоном окна, а не делается прозрачным: звенья кривой заходят друг
-- на друга, и у полупрозрачных нахлёст темнел бы точкой на каждом стыке — линия шла бы
-- бусами. По той же причине связь и гаснет смешиванием, а не прозрачностью.
--
-- Старшая связь (дерево карты) ярче второй (сетка между ветками): при равной яркости
-- сто двадцать четыре линии сливались в одну паутину, и формы дерева было не прочесть.
local LINE_GROUND = Theme.color.panel
-- Бледность колец ярусов: насколько их цвет смешан с фоном (wire.rings).
local BEAD = 0.35
-- Иерархия линий карты. Магистраль —
-- связь со старшим родителем, то есть ствол ветки: вдвое толще и почти без прозрачности.
-- Второй ингредиент — паутина между ветками — остаётся в пиксель и гаснет до четверти
-- непрозрачности (требование автора).
-- Одной таблицей по той же причине, что и spin: предел Luau на местные переменные.
-- Толщина связи — не одно число: у самих стихий (глубина 0)
-- линия толще всего и утоньшается к внешним кольцам — чем рецепт дальше от истока,
-- тем тоньше его связь (просьба автора). NEAR — толщина у центра, FAR — у последнего
-- кольца; wireThick (ниже) считает промежуточную по глубине конкретной связи.
local wire = {
	MAIN_THICK_NEAR = 3,
	MAIN_THICK_FAR = 1,
	MATE_THICK_NEAR = 1.6,
	MATE_THICK_FAR = 0.6,
	MAIN_BEAD = 0.08,
	MATE_BEAD = 0.75,
	MAIN_SHARE = 0.95,
	MATE_SHARE = 0.45,
	-- Кривые карты (Path2D, см. wire.update). BANDS — на сколько полос
	-- делится связь ради градиента (у Path2D один цвет на всю кривую), LAP — нахлёст
	-- соседних полос в пикселях карты, чтобы на стыке не светилась щель, PROBES — сколько
	-- точек кривой пробует обрезка по окну.
	BANDS = 4,
	LAP = 1.5,
	PROBES = 24,
	view = nil, -- рамка кривых поверх окна карты
	items = {}, -- кривые: { c, q, paths, shown, color, thick, z, want, dirty }
	spans = {}, -- участки кривой внутри окна (wire.clip), один на все
	last = nil, -- вид при прошлом пересчёте
	scale = nil,
	dirty = false, -- перекрашена хоть одна кривая
}

-- Неизвестная связь заметно светлее решётки сцены: при равной яркости ствол
-- неоткрытой ветки терялся на обзоре среди прямых линий сетки окна (#130).
local LINE_UNKNOWN = Theme.color.panel:Lerp(Theme.color.steel, 0.24)
-- Кольца ярусов под связями (RecipeGraph, guides): сплошные и еле заметные — подложка,
-- по которой читается глубина, а не ещё одна сетка поверх паутины.
local GUIDE = Theme.color.panel:Lerp(Theme.color.steel, 0.14)
-- Тень под картой (graphShade): прозрачность её середины и доля каждой стороны,
-- на которой тень уходит в окно.
local SHADE, SHADE_EDGE = 0.2, 0.12
local NODE_UNKNOWN = Color3.fromRGB(16, 20, 25)

-- Стеклянная плашка. Настоящего размытия фона (backdrop-filter) в Roblox UI нет —
-- размывать можно только весь экран через DepthOfField, а это трёхмерный эффект,
-- к плоскому интерфейсу он не применяется. Остальное от стекла воспроизводимо:
-- полупрозрачная тёмная заливка, свет сверху градиентом и светящаяся рамка в пиксель.
local GLASS = 0.3

-- Ступени подробности по масштабу: точки — буква — имя — имя с рецептом.
-- На второй ступени вместо иконки — первая буква имени: картинок у элементов
-- нет ни в Elements, ни где-либо ещё, а рисовать семьдесят одну иконку — отдельная задача.
local LOD_GLYPH, LOD_NAME, LOD_DETAIL = 0.4, 0.62, 1.15
-- Точки на полном отдалении — в пикселях экрана, а не холста: при любом масштабе базовая
-- стихия читается ядром с ореолом (HALO), остальные — мелкими точками своего цвета.
local DOT, DOT_BASE, HALO = 4, 10, 26
-- Подпись базовой стихии у её точки на полном отдалении: размер и отступ в пикселях экрана.
local SIDE_TEXT, SIDE_GAP = 10, 4

-- Постороннее не прячется совсем, а гаснет: карта должна остаться на месте, иначе
-- по одной висящей в пустоте цепочке не понять, откуда в дереве она растёт.
local FADE_LINE = 0.78 -- на столько цвет погасшей связи уходит в фон
local FADE_NODE = 0.6
local HOT = Theme.color.accent -- выбранная цепочка
local WARM = Theme.color.steel -- связи узла под курсором

local LIFT = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
-- Поворот карты. Карта медленно вращается вокруг середины ромба, пока ничего не выбрано
-- (SPEED, радиан в секунду). Нажатие на элемент за AIM_TIME поворачивает её так, чтобы
-- элемент встал справа от середины, и приближает вид к нему до AIM_ZOOM (если вид уже
-- ближе, масштаб не трогается). Пока элемент выбран, поворот стоит.
-- Настройки и состояние — одной таблицей: местные переменные главного куска скрипта
-- упираются в предел Luau (двести), и на каждую по отдельности их уже не хватает.
local spin = {
	SPEED = math.rad(2),
	AIM_TIME = 0.9,
	AIM_ZOOM = 1.2,
	angle = 0, -- нынешний поворот, радианы
	aim = nil, -- идущее наведение на элемент (focusOn)
	layer = nil, -- слой колец и связей: его Rotation и есть поворот (drawGraph)
}

local bookFrame = Instance.new("Frame")
bookFrame.Name = "BookTab"
bookFrame.Size = UDim2.new(1, 0, 1, 0)
bookFrame.BackgroundTransparency = 1
bookFrame.Visible = false
bookFrame.Parent = body
tabFrames["Справочник"] = bookFrame

-- Тень под картой. Крупная решётка сцены лаборатории шла под графом прямыми линиями
-- и на обзоре читалась как лишние связи (#130). Тень гасит её только под картой, а к
-- краям уходит в прозрачность по обеим осям, чтобы карта не выглядела вырезанной
-- прямоугольником. Обе оси сразу даёт только CanvasGroup: градиент заливки гасит края
-- по горизонтали, градиент самой группы — по вертикали, и непрозрачности перемножаются.
-- Создаётся раньше карты: из равных по ZIndex позже рисуется тот, кто позже в дереве.
local function shadeRamp(inner)
	return NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(SHADE_EDGE, inner),
		NumberSequenceKeypoint.new(1 - SHADE_EDGE, inner),
		NumberSequenceKeypoint.new(1, 1),
	})
end

local graphShade = Instance.new("CanvasGroup")
graphShade.Name = "Shade"
graphShade.Size = UDim2.new(1, 0, GRAPH_SHARE, 0)
graphShade.BackgroundTransparency = 1
graphShade.BorderSizePixel = 0
graphShade.Parent = bookFrame
local shadeFill = Instance.new("Frame")
shadeFill.Size = UDim2.new(1, 0, 1, 0)
shadeFill.BackgroundColor3 = Theme.color.panel
shadeFill.BorderSizePixel = 0
shadeFill.Parent = graphShade
local shadeAcross = Instance.new("UIGradient")
shadeAcross.Transparency = shadeRamp(SHADE)
shadeAcross.Parent = shadeFill
local shadeDown = Instance.new("UIGradient")
shadeDown.Rotation = 90
shadeDown.Transparency = shadeRamp(0)
shadeDown.Parent = graphShade

-- Рамка кривых карты — поверх тени и под самой картой: из равных по ZIndex
-- позже рисуется тот, кто позже в дереве, и узлы ложатся на линии, а не под них.
wire.view = Instance.new("Frame")
wire.view.Name = "Wires"
wire.view.BackgroundTransparency = 1
wire.view.BorderSizePixel = 0
wire.view.Parent = bookFrame

local graphScroll = Instance.new("ScrollingFrame")
graphScroll.Name = "Graph"
-- Доли, а не фиксированные пиксели: на альбомном телефоне рабочая высота вкладки меньше
-- самого графа, и у списка под ним высота выходила бы отрицательной.
graphScroll.Size = UDim2.new(1, 0, GRAPH_SHARE, 0)
graphScroll.BackgroundTransparency = 1
graphScroll.BorderSizePixel = 0
graphScroll.ClipsDescendants = true
-- Прокрутка своя: полосы двигают холст только по вертикали, а граф шире экрана и по
-- горизонтали, и колесо здесь занято масштабом. Тянуть картинку рукой — как в остальных
-- списках окна (Theme.DragScroll), только в обе стороны.
graphScroll.ScrollingEnabled = false
graphScroll.ScrollBarThickness = 0
graphScroll.Parent = bookFrame

-- Слой, который тянет масштаб. Узлы и линии лежат в нём, а не прямо в списке: UIScale
-- растягивает своих детей, и холст списка ему при этом не подчиняется — размер холста
-- пересчитывается руками (applyZoom).
local graphLayer = Instance.new("Frame")
graphLayer.Name = "Layer"
graphLayer.BackgroundTransparency = 1
graphLayer.Size = UDim2.new(0, 100, 0, 100)
graphLayer.Parent = graphScroll

local graphScale = Instance.new("UIScale")
graphScale.Parent = graphLayer

local graph = nil
local zoom = 1
-- Подробность узлов зависит от масштаба, поэтому applyZoom её дёргает, а определена
-- она ниже, вместе с остальным рисованием.
local applyLod

local function applyZoom()
	if not graph then
		return
	end
	graphScale.Scale = zoom
	if applyLod then
		applyLod()
	end
	local w = math.ceil(graph.width * zoom)
	local h = math.ceil(graph.height * zoom)
	-- Вокруг карты — запас в пол-окна с каждой стороны. Карта вращается, и элемент,
	-- к которому её поворачивают, приезжает направо, к самому краю холста: без запаса
	-- прокрутка упиралась бы в край, и поставить его в середину окна было бы нельзя.
	-- Отдалённая карта от этого не прижимается ни к краю, ни к верху (#130): в середину
	-- её ставят fitZoom и setZoom. Запас ровно в пол-окна держит точку под серединой окна
	-- на месте, когда окно растёт при открытии. Кривые (wire.update) считают от
	-- AbsolutePosition слоя, так что сдвиг слоя их не сбивает.
	local view = graphScroll.AbsoluteSize
	local slackX, slackY = math.floor(view.X / 2), math.floor(view.Y / 2)
	graphLayer.Position = UDim2.new(0, slackX, 0, slackY)
	graphScroll.CanvasSize = UDim2.new(0, w + slackX * 2, 0, h + slackY * 2)
end

-- Сдвиг слоя в холсте — запас вокруг карты (applyZoom). Точка под серединой окна
-- считается за его вычетом: иначе при смене масштаба картинка отпрыгивала бы в сторону.
local function canvasPad()
	return Vector2.new(graphLayer.Position.X.Offset, graphLayer.Position.Y.Offset)
end

local function setZoom(value)
	spin.aim = nil -- масштаб взяли в руки: наведение дальше не тянет вид на себя
	value = math.clamp(value, ZOOM_MIN, ZOOM_MAX)
	if not graph or math.abs(value - zoom) < 0.001 then
		return
	end
	-- Держим ту же точку графа в середине окна: иначе с каждым щелчком масштаба картинка
	-- уезжает к левому верхнему углу, и приближать приходится вслепую.
	local view = graphScroll.AbsoluteSize
	local centre = (graphScroll.CanvasPosition + view / 2 - canvasPad()) / zoom
	zoom = value
	applyZoom()
	local want = centre * zoom + canvasPad() - view / 2
	graphScroll.CanvasPosition = Vector2.new(math.max(0, want.X), math.max(0, want.Y))
end

-- Два рода «вписать».
--
-- При первом открытии — читаемый масштаб и наводка на центр орбит, где стоят четыре
-- базовые стихии: с них карта и читается. По ширине не вписываем: вписанная карта
-- мельчит подпись в двенадцать пунктов до нескольких пикселей. Центр орбит, а не середина
-- холста: сектора веток разной величины, и середина холста съезжает к крупной ветке.
--
-- По кнопке «[]» — целиком: туда жмут именно затем, чтобы увидеть всю карту сразу,
-- и подписи там уже не читают, а служат ориентирами.
local HOME_ZOOM = MobileUI.isMobile and 0.6 or 0.8

local function fitZoom(whole)
	if not graph then
		return
	end
	local view = graphScroll.AbsoluteSize
	if view.X < 50 or view.Y < 50 then
		return
	end

	spin.aim = nil
	local focusX, focusY
	if whole then
		zoom = math.clamp(math.min(view.X / graph.width, view.Y / graph.height), ZOOM_MIN, 1)
		focusX, focusY = graph.width / 2, graph.height / 2
	else
		zoom = HOME_ZOOM
		focusX, focusY = graph.centre[1], graph.centre[2]
	end

	applyZoom()
	local want = Vector2.new(focusX, focusY) * zoom + canvasPad() - view / 2
	graphScroll.CanvasPosition = Vector2.new(math.max(0, want.X), math.max(0, want.Y))
end

local openedLabel = Instance.new("TextLabel")
openedLabel.Size = UDim2.new(1, 0, 0, 18)
openedLabel.Position = UDim2.new(0, 0, GRAPH_SHARE, 6)
openedLabel.BackgroundTransparency = 1
openedLabel.FontFace = Theme.font.strong
openedLabel.TextSize = 11
openedLabel.Parent = bookFrame

local listScroll = Instance.new("ScrollingFrame")
listScroll.Size = UDim2.new(1, 0, 1 - GRAPH_SHARE, -28)
listScroll.Position = UDim2.new(0, 0, GRAPH_SHARE, 28)
listScroll.BackgroundTransparency = 1
listScroll.BorderSizePixel = 0
listScroll.ScrollBarThickness = 6
listScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
listScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
listScroll.Parent = bookFrame

Theme.Scroller(listScroll)
Theme.DragScroll(listScroll)

listScroll:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
	local layout = listScroll:FindFirstChildOfClass("UIGridLayout")
	if layout then
		Theme.GridFit(layout)
	end
end)

-- Кнопки масштаба висят на вкладке, а не на холсте: на холсте они уезжали бы вместе
-- с картинкой. На телефоне это единственный способ приблизить — колеса там нет.
local ZOOM_BTN = MobileUI.isMobile and MobileUI.MIN_TAP or 26

local function zoomButton(caption, right, action)
	local btn = Instance.new("TextButton")
	btn.AnchorPoint = Vector2.new(1, 0)
	btn.Size = UDim2.new(0, ZOOM_BTN, 0, ZOOM_BTN)
	btn.Position = UDim2.new(1, -right, 0, 2)
	btn.FontFace = Theme.font.strong
	btn.TextSize = MobileUI.isMobile and 20 or 16
	btn.Text = caption
	btn.ZIndex = 6
	btn.Parent = bookFrame
	chromeButton(btn, "quiet")
	btn.MouseButton1Click:Connect(action)
	return btn
end

zoomButton("−", ZOOM_BTN * 2 + 14, function()
	setZoom(zoom - ZOOM_STEP)
end)
zoomButton("+", ZOOM_BTN + 8, function()
	setZoom(zoom + ZOOM_STEP)
end)
-- Третья кнопка — «вся карта». От Гидросферы до Атмосферы теперь две с лишним тысячи
-- пикселей, и протащить их рукой дольше, чем отдалиться и ткнуть в нужный угол.
zoomButton("[]", 2, function()
	fitZoom(true)
end)

-- Подпись под курсором: что за элемент и из чего он. Стоит внизу графа, а не у самого
-- узла: всплывающая рядом подсказка закрывала бы соседние узлы — то самое, ради чего
-- вся раскладка и считается.
local hintBar = Instance.new("TextLabel")
hintBar.AnchorPoint = Vector2.new(0, 1)
hintBar.Position = UDim2.new(0, 4, GRAPH_SHARE, -4)
hintBar.Size = UDim2.new(0, 0, 0, 22)
hintBar.AutomaticSize = Enum.AutomaticSize.X
hintBar.BackgroundColor3 = Theme.color.panel
hintBar.BackgroundTransparency = 0.1
hintBar.FontFace = Theme.font.body
hintBar.TextSize = 12
hintBar.TextColor3 = Theme.color.textDim
hintBar.TextXAlignment = Enum.TextXAlignment.Left
hintBar.ZIndex = 6
hintBar.Visible = false
hintBar.Parent = bookFrame

Theme.Corner(hintBar, Theme.radius.mark)
Theme.Hairline(hintBar, 0.5)

local hintPad = Instance.new("UIPadding")
hintPad.PaddingLeft = UDim.new(0, 8)
hintPad.PaddingRight = UDim.new(0, 8)
hintPad.Parent = hintBar

-- Выход из цепочки кнопкой, а не только нажатием на пустое место: на телефоне
-- пустого места на экране может и не оказаться, а любое касание там — ещё и протяжка.
local backButton = Instance.new("TextButton")
-- В правом верхнем углу самой карты, слева от кнопок масштаба: возврат во всех окнах
-- стоит справа вверху. На телефоне кнопка высотой в палец, и в полоске между графом
-- и списком она бы не поместилась.
backButton.Size = UDim2.new(0, 104, 0, MobileUI.isMobile and MobileUI.MIN_TAP or 22)
backButton.AnchorPoint = Vector2.new(1, 0)
backButton.Position = UDim2.new(1, -(ZOOM_BTN * 3 + 28), 0, 2)
backButton.FontFace = Theme.font.strong
backButton.TextSize = 11
backButton.Text = "ВСЕ РЕЦЕПТЫ"
backButton.ZIndex = 6
backButton.Visible = false
backButton.Parent = bookFrame

chromeButton(backButton, "quiet")

-- Список рецептов под картой убирается (просьба автора): вся высота вкладки
-- уходит карте. Кнопка стоит в том же углу, что и возврат из цепочки, — обе про то,
-- что сейчас показано, а не про саму карту.
local listButton = Instance.new("TextButton")
listButton.Size = UDim2.new(0, 150, 0, MobileUI.isMobile and MobileUI.MIN_TAP or 22)
listButton.Position = UDim2.new(0, 2, 0, 2)
listButton.FontFace = Theme.font.strong
listButton.TextSize = 11
listButton.Text = "СКРЫТЬ СПИСОК"
listButton.ZIndex = 6
listButton.Parent = bookFrame

chromeButton(listButton, "quiet")

-- Кнопки карты собраны в один угол — справа, рядом с масштабом. Слева от них теперь
-- нет ничего, кроме самой карты, и одинокая кнопка под вкладками читалась как третий
-- этаж шапки. На телефоне «Скрыть список» остаётся слева: три кнопки масштаба шириной
-- в палец и «Все рецепты» и так занимают там весь правый угол.
if not MobileUI.isMobile then
	local zoomRow = ZOOM_BTN * 3 + 20
	listButton.AnchorPoint = Vector2.new(1, 0)
	listButton.Position = UDim2.new(1, -(zoomRow + 8), 0, 2)
	backButton.Position = UDim2.new(1, -(zoomRow + 166), 0, 2)
end

local listShown = true

-- Пустая полоса между шапкой и картой. Раньше холст выводился вверх на всю высоту
-- шапки, и узлы, проходя под вкладками, торчали из-под них краями (замечание
-- автора со скриншотом). Чёрной ленты из #114 это не возвращает: в полосе видна
-- та же решётка окна, что и под самой картой, а место заняты кнопками карты:
-- высота считается от них, чтобы они умещались целиком и на телефоне.
local GRAPH_TOP = ZOOM_BTN + 8

local function applyBookLayout()
	local share = listShown and GRAPH_SHARE or 1
	graphScroll.Position = UDim2.new(0, 0, 0, GRAPH_TOP)
	graphScroll.Size = UDim2.new(1, 0, share, -GRAPH_TOP)
	graphShade.Position = graphScroll.Position
	graphShade.Size = graphScroll.Size
	wire.view.Position = graphScroll.Position
	wire.view.Size = graphScroll.Size
	hintBar.Position = UDim2.new(0, 4, share, -4)
	openedLabel.Visible = listShown
	listScroll.Visible = listShown
	listButton.Text = listShown and "СКРЫТЬ СПИСОК" or "ПОКАЗАТЬ СПИСОК"
end

listButton.MouseButton1Click:Connect(function()
	listShown = not listShown
	applyBookLayout()
end)

-- Высота шапки меняется вместе с полосой Roblox (поворот телефона, полный экран),
-- и карта должна выводиться наверх ровно на новую высоту.
onChrome = applyBookLayout

applyBookLayout()

-- ---------- рисование ----------
-- Наведение и выбор не пересобирают карту, а перекрашивают уже нарисованное: узлов
-- семьдесят один, отрезков больше четырёхсот, и полная сборка стоит заметной доли кадра —
-- на каждое движение мыши её не хватило бы.

local nodeGui = {} -- key -> { frame, label, stroke, known, color }
local edgeGui = {} -- { parent, child, known, parts = { Frame... } }
local edgesOf = {} -- key -> связи, у которых элемент на одном из концов
local selected = nil -- элемент, чья цепочка создания подсвечена
local hovered = nil
local chainNodes, chainEdges = {}, {}
-- Насколько уехал палец с момента нажатия: на карте, которую тянут рукой, каждая
-- протяжка заканчивается отпусканием над каким-нибудь узлом — иначе он бы выбирался.
local panMoved = 0

-- Обе зовутся из обработчиков, которые вешаются раньше, чем эти функции определены.
local repaint
local selectNode
local focusOn

local function hintFor(key)
	local recipe = graph.producedBy[key]
	if not recipe then
		return ("%s   —   базовый, покупается за материю"):format(Theme.Caps(Elements[key].name))
	end
	if knownRecipes[key] ~= true then
		return "???   —   рецепт ещё не открыт"
	end
	return ("%s   =   %s + %s"):format(
		Theme.Caps(Elements[key].name),
		Theme.Caps(Elements[recipe.a].name),
		Theme.Caps(Elements[recipe.b].name)
	)
end

-- ---------- кривые карты ----------
-- Связь — не цепочка повёрнутых рамок, а Path2D: настоящая кривая
-- Безье из раскладки (RecipeGraph, edge.curve). Цепочка рамок давала засечку на каждом
-- стыке звеньев, а пять тысяч рамок во вращающемся слое перерисовывались каждый кадр
-- и роняли частоту кадров до двадцати (замечание автора).
--
-- Path2D не подчиняется ни UIScale слоя, ни повороту родителя, ни обрезке окна
-- (ClipsDescendants и CanvasGroup — проверено на сборке). Поэтому кривые лежат не в слое,
-- а в своей рамке поверх окна (wire.view), и когда вид сдвинулся, переводятся в её
-- пиксели: поворот вокруг середины ромба, масштаб, сдвиг. Безье при таком переносе
-- остаётся той же кривой — переносятся только четыре её точки. За края окна её режет
-- wire.clip. Неизменную прозрачности у Path2D нет, и бледность линии всюду смешана с фоном в цвет.

-- Кривая c — восемь чисел в координатах карты (см. RecipeGraph, BezierAt).
function wire.add(c, color, thick, z, want)
	local item = {
		c = c,
		q = table.create(8, 0), -- та же кривая в пикселях окна
		paths = {},
		shown = 0, -- сколько из paths сейчас видны
		color = color,
		thick = thick,
		z = z,
		want = want ~= false,
		dirty = true,
	}
	table.insert(wire.items, item)
	wire.dirty = true
	return item
end

-- Прямой отрезок той же записью: точки управления на трети и двух третях.
function wire.segment(x1, y1, x2, y2)
	local dx, dy = (x2 - x1) / 3, (y2 - y1) / 3
	return { x1, y1, x1 + dx, y1 + dy, x2 - dx, y2 - dy, x2, y2 }
end

function wire.reset()
	for _, item in wire.items do
		for _, path in item.paths do
			path:Destroy()
		end
	end
	table.clear(wire.items)
	wire.last = nil
end

-- Кольца ярусов: каждое — четыре четверти окружности, каждая — кубика с усами в ARC
-- радиуса (отклонение от окружности — сотые доли радиуса). Радиус берётся
-- у первой точки кольца: раскладка начинает его с угла ноль, справа от середины.
function wire.rings()
	local ARC = 0.5523
	local ox, oy = graph.centre[1], graph.centre[2]
	local color = LINE_GROUND:Lerp(GUIDE, 1 - BEAD)
	for _, ring in graph.guides do
		local r = ring[1][1] - ox
		for quarter = 0, 3 do
			local a, b = quarter * math.pi / 2, (quarter + 1) * math.pi / 2
			local ca, sa, cb, sb = math.cos(a), math.sin(a), math.cos(b), math.sin(b)
			wire.add({
				ox + ca * r, oy + sa * r,
				ox + (ca - sa * ARC) * r, oy + (sa + ca * ARC) * r,
				ox + (cb + sb * ARC) * r, oy + (sb - cb * ARC) * r,
				ox + cb * r, oy + sb * r,
			}, color, 1, 1)
		end
	end
end

-- Связь: полосы градиента от цвета родителя к цвету ребёнка (одна, если цвет один)
-- и два уса наконечника, по умолчанию скрытые — их зажигает repaint, как и рамки.
function wire.edge(record, curve, fromColor, toColor, thick)
	local bands = fromColor == toColor and 1 or wire.BANDS
	-- Нахлёст в долях параметра — по длине ломаной точек управления: она не короче кривой.
	local len = 0
	for k = 1, 5, 2 do
		len += math.sqrt((curve[k + 2] - curve[k]) ^ 2 + (curve[k + 3] - curve[k + 1]) ^ 2)
	end
	local lap = wire.LAP / math.max(len, 1)
	record.items, record.itemColors, record.headItems = {}, {}, {}
	for k = 1, bands do
		local t0, t1 = math.max((k - 1) / bands - lap, 0), math.min(k / bands + lap, 1)
		local color = fromColor:Lerp(toColor, (k - 0.5) / bands)
		table.insert(record.items, wire.add(Graph.BezierPart(curve, t0, t1), color, thick, 1))
		table.insert(record.itemColors, color)
	end
	-- Усы идут от конца назад вдоль касательной в конце кривой.
	local ex, ey = curve[7], curve[8]
	local hx, hy = curve[5], curve[6]
	if (ex - hx) ^ 2 + (ey - hy) ^ 2 < 1e-6 then
		hx, hy = curve[3], curve[4]
	end
	local ang = math.atan2(ey - hy, ex - hx)
	for _, side in { 0.45, -0.45 } do
		local wing = wire.segment(ex, ey, ex - math.cos(ang + side) * ARROW, ey - math.sin(ang + side) * ARROW)
		table.insert(record.headItems, wire.add(wing, toColor, thick, 1, false))
	end
end

-- Участки кривой q (уже в пикселях окна) внутри окна w×h — пары t0, t1 подряд в out.
-- Кривая пробуется в PROBES точках, граница участка уточняется делением пополам.
function wire.clip(q, w, h, out)
	table.clear(out)
	local function inside(t)
		local x, y = Graph.BezierAt(q, t)
		return x >= 0 and x <= w and y >= 0 and y <= h
	end
	local was = inside(0)
	local from = 0
	for k = 1, wire.PROBES do
		local t = k / wire.PROBES
		local now = inside(t)
		if now ~= was then
			local lo, hi = (k - 1) / wire.PROBES, t
			for _ = 1, 10 do
				local mid = (lo + hi) / 2
				if inside(mid) == was then
					lo = mid
				else
					hi = mid
				end
			end
			if now then
				from = lo
			else
				table.insert(out, from)
				table.insert(out, hi)
			end
			was = now
		end
	end
	if was then
		table.insert(out, from)
		table.insert(out, 1)
	end
	return out
end

-- Перенос кривых в окно. Зовётся каждый кадр из RenderStepped, но считает только тогда,
-- когда сдвинулся слой, окно или поворот, либо кривые перекрасили (wire.dirty).
function wire.update()
	if not graph then
		return
	end
	local view = wire.view
	local layerAt, layerSize = graphLayer.AbsolutePosition, graphLayer.AbsoluteSize
	local viewAt, viewSize = view.AbsolutePosition, view.AbsoluteSize
	if layerSize.X <= 0 or viewSize.X <= 0 then
		return
	end
	local last = wire.last
	if last and not wire.dirty and last[1] == layerAt and last[2] == layerSize and last[3] == viewAt
		and last[4] == viewSize and last[5] == spin.angle then
		return
	end
	wire.last = { layerAt, layerSize, viewAt, viewSize, spin.angle }
	wire.dirty = false

	local scale = layerSize.X / graph.width
	local rescaled = scale ~= wire.scale
	wire.scale = scale
	local ox, oy = graph.centre[1], graph.centre[2]
	local c, s = math.cos(spin.angle) * scale, math.sin(spin.angle) * scale
	-- Точка карты p в пикселях окна: слой − окно + (середина + поворот(p − середина)) · масштаб.
	local bx = layerAt.X - viewAt.X + ox * scale
	local by = layerAt.Y - viewAt.Y + oy * scale
	local w, h = viewSize.X, viewSize.Y
	local spans = wire.spans
	local none = UDim2.new()

	for _, item in wire.items do
		local paths = item.paths
		local count = 0
		-- Толщина тянется с масштабом, как у рамок в слое, но не тоньше пикселя: тоньше
		-- Path2D на отдалении рассыпается на обрывки.
		local thick = math.max(item.thick * scale, 1)
		if item.want then
			local src, q = item.c, item.q
			local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
			for k = 1, 7, 2 do
				local dx, dy = src[k] - ox, src[k + 1] - oy
				local x, y = bx + dx * c - dy * s, by + dx * s + dy * c
				q[k], q[k + 1] = x, y
				x0, x1 = math.min(x0, x), math.max(x1, x)
				y0, y1 = math.min(y0, y), math.max(y1, y)
			end
			-- Кривая лежит внутри оболочки своих точек управления: оболочка за окном —
			-- рисовать нечего, в окне целиком — резать нечего.
			if x1 >= 0 and x0 <= w and y1 >= 0 and y0 <= h then
				if x0 >= 0 and x1 <= w and y0 >= 0 and y1 <= h then
					table.clear(spans)
					spans[1], spans[2] = 0, 1
				else
					wire.clip(q, w, h, spans)
				end
				for k = 1, #spans - 1, 2 do
					local t0, t1 = spans[k], spans[k + 1]
					if t1 > t0 then
						count += 1
						local path = paths[count]
						if not path then
							path = Instance.new("Path2D")
							path.Visible = false
							path.Color3 = item.color
							path.Thickness = thick
							path.ZIndex = item.z
							path.Parent = view
							paths[count] = path
						end
						local p = (t0 == 0 and t1 == 1) and q or Graph.BezierPart(q, t0, t1)
						-- Усы точки Path2D — смещение соседней точки управления Безье от неё самой.
						path:SetControlPoints({
							Path2DControlPoint.new(
								UDim2.fromOffset(p[1], p[2]),
								none,
								UDim2.fromOffset(p[3] - p[1], p[4] - p[2])
							),
							Path2DControlPoint.new(
								UDim2.fromOffset(p[7], p[8]),
								UDim2.fromOffset(p[5] - p[7], p[6] - p[8]),
								none
							),
						})
					end
				end
			end
		end
		-- Видимость и вид пишутся только при перемене: кривых сотни, кадров — шестьдесят в секунду.
		for k = count + 1, item.shown do
			paths[k].Visible = false
		end
		for k = item.shown + 1, count do
			paths[k].Visible = true
		end
		item.shown = count
		if item.dirty or rescaled then
			item.dirty = false
			for _, path in paths do
				path.Color3 = item.color
				path.Thickness = thick
				path.ZIndex = item.z
			end
		end
	end
end

-- Доля глубины связи (0 — от самих стихий, 1 — последнее кольцо) на диапазон [near, far].
-- Глубина берётся у ребёнка: связь всегда идёт из более раннего яруса в более поздний,
-- поэтому именно он определяет, на каком кольце линия заканчивается. Определена здесь,
-- а не выше вместе с wire: там ещё нет локальной graph (объявлена ниже по файлу), и
-- функция бы считала её глобальной — всегда nil (баг #131).
local function wireThick(edge, near, far)
	local maxDepth = math.max(#graph.guides, 1)
	local d = graph.depth[edge.child] or maxDepth
	local t = math.clamp(d / maxDepth, 0, 1)
	return near + (far - near) * t
end

local function drawEdge(edge)
	local known = knownRecipes[edge.child] == true
	-- Вторая связь — это и есть второй ингредиент. Пока рецепт не открыт, её нет.
	if not edge.main and not known then
		return
	end

	-- Магистраль (связь со старшим родителем) идёт толще и ярче,
	-- а связь второго ингредиента — тоньше и прозрачнее (wire).
	local share, thick, bead
	if edge.main then
		share = wire.MAIN_SHARE
		thick = wireThick(edge, wire.MAIN_THICK_NEAR, wire.MAIN_THICK_FAR)
		bead = wire.MAIN_BEAD
	else
		share = wire.MATE_SHARE
		thick = wireThick(edge, wire.MATE_THICK_NEAR, wire.MATE_THICK_FAR)
		bead = wire.MATE_BEAD
	end
	-- Кривые непрозрачны: прозрачность переносится в долю цвета, то есть связь так же
	-- гаснет в фон, но нахлёсты не светятся бусинами.
	share *= 1 - bead

	local record = {
		parent = edge.parent,
		child = edge.child,
		known = known,
		thick = thick,
	}
	local fromColor = known and LINE_GROUND:Lerp(Theme.Legible(Elements[edge.parent].color), share)
		or LINE_UNKNOWN
	local toColor = known and LINE_GROUND:Lerp(Theme.Legible(Elements[edge.child].color), share)
		or LINE_UNKNOWN

	wire.edge(record, edge.curve, fromColor, toColor, thick)
	table.insert(edgeGui, record)
	table.insert(edgesOf[edge.parent], record)
	table.insert(edgesOf[edge.child], record)
end

-- На какой ступени подробности сейчас карта.
local function lodTier()
	if zoom < LOD_GLYPH then
		return 1 -- только светящиеся точки
	elseif zoom < LOD_NAME then
		return 2 -- плашка с одной буквой
	elseif zoom < LOD_DETAIL then
		return 3 -- имя
	end
	return 4 -- имя и рецепт под узлом
end

local function nodeSize(ui, lifted)
	local w, h = ui.w, ui.h
	if lodTier() == 1 then
		w = (ui.base and DOT_BASE or DOT) / zoom
		h = w
	end
	if lifted then
		w, h = w + 8, h + 4
	end
	return UDim2.new(0, w, 0, h)
end

local function drawNode(key)
	local place = graph.nodes[key]
	local data = Elements[key]
	-- Базовые открыты всегда: рецепта, который надо открыть, у них нет — их покупают.
	local known = (graph.producedBy[key] == nil) or knownRecipes[key] == true

	local tint = known and Theme.Legible(data.color) or Theme.color.textMute

	-- Ореол — отдельная плашка под узлом, больше его и почти прозрачная: настоящего
	-- свечения в плоском интерфейсе нет. Ярче всего у базовых и на полном отдалении.
	local glow = Instance.new("Frame")
	glow.AnchorPoint = Vector2.new(0.5, 0.5)
	glow.Position = UDim2.new(0, place.x, 0, place.y)
	glow.Size = UDim2.new(0, place.w + 18, 0, place.h + 18)
	glow.BackgroundColor3 = tint
	glow.BackgroundTransparency = 1
	glow.BorderSizePixel = 0
	glow.ZIndex = 1
	glow.Parent = graphLayer
	Theme.Corner(glow, 999)

	-- Кнопка, а не рамка: узел ловит и наведение, и нажатие. Протяжку карты это не ломает:
	-- она идёт через UserInputService поверх всего интерфейса (см. ниже).
	local node = Instance.new("TextButton")
	node.AnchorPoint = Vector2.new(0.5, 0.5)
	node.Position = UDim2.new(0, place.x, 0, place.y)
	node.Size = UDim2.new(0, place.w, 0, place.h)
	node.Text = ""
	node.AutoButtonColor = false -- своё освещение, см. repaint
	node.BorderSizePixel = 0
	node.ZIndex = 2
	node.Parent = graphLayer

	-- Радиус больше половины высоты Roblox сам ужимает, поэтому 999 — это «таблетка»
	-- при любой высоте, включая точку на полном отдалении (там она становится кругом).
	Theme.Corner(node, 999)
	-- Обводка есть всегда и перекрашивается в repaint: у выбранного узла она горит.
	local stroke = Theme.Stroke(node, tint, 1, 0.2)

	-- Свет сверху: стекло без блика читается как просто полупрозрачная дырка.
	local sheen = Instance.new("UIGradient")
	sheen.Rotation = 90
	sheen.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(120, 128, 140))
	sheen.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 0.35),
	})
	sheen.Parent = node

	-- Узор элемента — только у открытого: у «???» он назвал бы элемент не хуже имени.
	-- Стоит до подписи, чтобы имя лежало поверх узора.
	Theme.Pattern(node, known and key or nil, tint, false)

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, -6, 1, 0)
	nameLabel.Position = UDim2.new(0, 3, 0, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.FontFace = Theme.font.strong
	nameLabel.TextSize = 12
	-- Ширину узла раскладка считала по числу букв в моноширинном шрифте, поэтому имя
	-- влезает целиком; обрезка оставлена на случай, если шрифт когда-нибудь сменят.
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.ZIndex = 2
	local caption = known and Theme.Caps(data.name) or "???"
	nameLabel.Text = caption
	nameLabel.Parent = node

	-- Строка рецепта под узлом — самая подробная ступень. Лежит не внутри узла,
	-- а рядом: в коробку в двадцать два пикселя вторая строка не влезает. Место под неё
	-- раскладка оставляет на орбите (RecipeGraph, DETAIL_H), а тёмная подложка по ширине
	-- текста не даёт ей читаться поверх линии, идущей в соседнем просвете.
	local recipe = graph.producedBy[key]
	local detailText
	if not recipe then
		detailText = Theme.Caps("базовый")
	elseif known then
		detailText = Theme.Caps(("%s + %s"):format(Elements[recipe.a].name, Elements[recipe.b].name))
	end

	local detail = Instance.new("TextLabel")
	detail.AnchorPoint = Vector2.new(0.5, 0)
	detail.Position = UDim2.new(0, place.x, 0, place.y + place.h / 2 + 4)
	detail.AutomaticSize = Enum.AutomaticSize.X
	detail.Size = UDim2.new(0, 0, 0, 14)
	detail.BackgroundColor3 = Theme.color.panel
	detail.BackgroundTransparency = 0.15
	detail.BorderSizePixel = 0
	detail.FontFace = Theme.font.body
	detail.TextSize = 10
	detail.TextColor3 = Theme.color.textMute
	detail.Text = detailText or ""
	detail.ZIndex = 2
	detail.Visible = false
	detail.Parent = graphLayer
	Theme.Corner(detail, Theme.radius.mark)
	local detailPad = Instance.new("UIPadding")
	detailPad.PaddingLeft = UDim.new(0, 4)
	detailPad.PaddingRight = UDim.new(0, 4)
	detailPad.Parent = detail

	-- Имя базовой стихии рядом с точкой — с той стороны, что смотрит от середины ромба.
	-- На полном отдалении подписей нет ни у кого, и четыре ядра иначе не опознать.
	-- Размер и отступ applyLod делит на масштаб, чтобы подпись не мельчала вместе с картой.
	-- Место и сторону ставит spin.place: карта вращается.
	local side
	if not recipe then
		side = Instance.new("TextLabel")
		side.AutomaticSize = Enum.AutomaticSize.XY
		side.Size = UDim2.new(0, 0, 0, 0)
		side.BackgroundTransparency = 1
		side.FontFace = Theme.font.strong
		side.TextColor3 = tint
		side.Text = caption
		side.ZIndex = 4
		side.Visible = false
		side.Parent = graphLayer
	end

	nodeGui[key] = {
		frame = node,
		label = nameLabel,
		detail = detail,
		detailText = detailText,
		glow = glow,
		side = side,
		stroke = stroke,
		known = known,
		base = graph.producedBy[key] == nil,
		color = data.color,
		caption = caption,
		glyph = known and utf8.char(utf8.codepoint(caption)) or "?",
		w = place.w,
		h = place.h,
	}

	-- Под курсором узел подрастает. Просвет до чужой линии раскладка держит не меньше
	-- двенадцати пикселей, поэтому подрост на четыре с каждой стороны ни во что не упирается.
	node.MouseEnter:Connect(function()
		hovered = key
		hintBar.Text = hintFor(key)
		hintBar.Visible = true
		TweenService:Create(node, LIFT, { Size = nodeSize(nodeGui[key], true) }):Play()
		repaint()
	end)

	node.MouseLeave:Connect(function()
		if hovered == key then
			hovered = nil
			hintBar.Visible = false
		end
		TweenService:Create(node, LIFT, { Size = nodeSize(nodeGui[key], false) }):Play()
		repaint()
	end)

	node.MouseButton1Click:Connect(function()
		if panMoved > 6 then
			return -- это была протяжка карты, а не выбор
		end
		selectNode(key)
		-- Повторное нажатие снимает выбор: наводиться тогда не на что, и карта снова крутится.
		if selected == key then
			focusOn(key)
		end
	end)
end

-- Цепочка создания: сам элемент, всё, из чего он собран, и всё, из чего собрано то.
-- Вверх идём ровно по тем связям, которые нарисованы: у неоткрытого рецепта второй связи
-- нет вовсе, и цепочка по ней не пойдёт — пару она не выдаст.
local function chainOf(key)
	local nodes, edges = {}, {}
	local function walk(from)
		if nodes[from] then
			return
		end
		nodes[from] = true
		for _, record in (edgesOf[from] or {}) do
			if record.child == from then
				edges[record] = true
				walk(record.parent)
			end
		end
	end
	walk(key)
	return nodes, edges
end

-- Что сейчас горит. nil — не выделено ничего, вся карта в полную силу.
local function litSets()
	if not (selected or hovered) then
		return nil, nil
	end

	local nodes, edges = {}, {}
	for key in chainNodes do
		nodes[key] = true
	end
	for record in chainEdges do
		edges[record] = true
	end

	if hovered then
		-- Под курсором зажигается сам узел, его связи и соседи на их концах — сразу
		-- видно и откуда элемент взялся, и во что он идёт дальше.
		nodes[hovered] = true
		for _, record in (edgesOf[hovered] or {}) do
			edges[record] = true
			nodes[record.parent] = true
			nodes[record.child] = true
		end
	end

	return nodes, edges
end

function repaint()
	local nodes, edges = litSets()

	for _, record in edgeGui do
		local lit, state = nil, "rest"
		if edges then
			if edges[record] then
				-- Цепочка — бирюзой, связи узла под курсором — сталью: одним цветом
				-- они бы слились, а наводить мышь приходится как раз поверх выбранной цепочки.
				lit = chainEdges[record] and HOT or WARM
				state = chainEdges[record] and "hot" or "warm"
			else
				state = "fade"
			end
		end
		-- Звенья переписываются только у связей, чьё состояние сменилось: звеньев у кривых
		-- тысячи, а переход курсора с узла на узел меняет лишь горстку связей.
		if record.state ~= state then
			record.state = state
			-- Подсвеченная связь на пиксель толще своей обычной, а не всегда в два:
			-- магистраль и так толще паутины, и общая двойка стёрла бы эту разницу.
			local thickness = record.thick + (lit and 1 or 0)
			-- Горящая связь — слоем выше остальных: линии непрозрачные, и погасшая,
			-- нарисованная позже, резала бы цепочку на каждом пересечении.
			local layer = lit and 2 or 1
			-- Подсвеченная связь горит одним цветом целиком, обычная — своим градиентом
			-- по звеньям: цепочку надо видеть как одну линию, а не как перелив.
			-- Кривые пишутся в Path2D на ближайшем wire.update.
			if record.items then
				for i, item in record.items do
					local color = record.itemColors[i]
					item.color = lit or (state == "fade" and color:Lerp(LINE_GROUND, FADE_LINE)) or color
					item.thick = thickness
					item.z = layer
					item.dirty = true
				end
				for _, item in record.headItems do
					item.want = lit ~= nil
					item.color = lit or item.color
					item.thick = thickness
					item.z = layer
					item.dirty = true
				end
				wire.dirty = true
			end
		end
	end

	for key, ui in nodeGui do
		local state = "normal"
		if key == selected then
			state = "hot"
		elseif nodes then
			state = nodes[key] and "lit" or "dim"
		end

		local tint = ui.known and Theme.Legible(ui.color) or Theme.color.textMute
		-- Загоревшийся узел не меняет цвет, а только светлеет в своём: цвет — это опознание
		-- элемента во всём окне, и подсветка не должна его перебивать.
		local depth = (state == "hot" and 0.42) or (state == "lit" and 0.58) or 0.74
		local dots = lodTier() == 1
		if dots then
			-- На полном отдалении узел — светящаяся точка своего цвета, а не тёмная плашка:
			-- читать там нечего, и вся работа карты — показать форму и пятна групп.
			ui.frame.BackgroundColor3 = tint
			ui.frame.BackgroundTransparency = (state == "dim") and 0.75 or 0.08
		else
			ui.frame.BackgroundColor3 = ui.known and Theme.Shadowed(ui.color, depth) or NODE_UNKNOWN
			ui.frame.BackgroundTransparency = (state == "dim") and FADE_NODE or GLASS
		end
		ui.frame.ZIndex = (state == "dim") and 2 or 3
		ui.label.ZIndex = ui.frame.ZIndex
		ui.label.TextColor3 = tint
		ui.label.TextTransparency = (state == "dim") and 0.5 or 0
		ui.detail.TextTransparency = (state == "dim") and 0.7 or 0.2
		ui.stroke.Color = (state == "hot") and HOT or tint
		ui.stroke.Thickness = (state == "hot") and 2 or 1
		ui.stroke.Transparency = (state == "dim") and 0.85 or ((state == "normal") and 0.2 or 0)

		-- Ореол — только у базовых: на полном отдалении это мягкий круг вокруг ядра,
		-- ближе — едва заметный. У остальных точек его нет: они мелкие и чёткие.
		local halo = 1
		if ui.base then
			halo = dots and ((state == "dim") and 0.93 or 0.82) or ((state == "dim") and 0.93 or 0.82)
		end
		ui.glow.BackgroundColor3 = tint
		ui.glow.BackgroundTransparency = halo
		if ui.side then
			ui.side.TextColor3 = tint
			ui.side.TextTransparency = (state == "dim") and 0.6 or 0
		end
	end
end

-- Имя базовой стихии — снаружи от точки, по лучу от середины ромба. Луч, а не ближайшая
-- из четырёх сторон: карта вращается, и подпись, прыгающая со стороны на сторону
-- на сорока пяти градусах, мелькала бы.
-- Звенья поворачивает сам их слой (spin.layer.Rotation) — одна запись вместо четырёх
-- тысяч. Узлы, ореолы, строки рецептов и подписи переставляются по одному: в повёрнутом
-- слое повернулся бы и текст.
function spin.place()
	if not graph then
		return
	end
	if spin.layer then
		spin.layer.Rotation = math.deg(spin.angle)
	end
	local ox, oy = graph.centre[1], graph.centre[2]
	local c, s = math.cos(spin.angle), math.sin(spin.angle)
	for key, ui in nodeGui do
		local place = graph.nodes[key]
		local dx, dy = place.x - ox, place.y - oy
		local x, y = ox + dx * c - dy * s, oy + dx * s + dy * c
		local at = UDim2.new(0, x, 0, y)
		ui.frame.Position = at
		ui.glow.Position = at
		ui.detail.Position = UDim2.new(0, x, 0, y + place.h / 2 + 4)
		if ui.side then
			local length = math.sqrt(dx * dx + dy * dy)
			local dir = length > 0 and Vector2.new(x - ox, y - oy) / length or Vector2.new(1, 0)
			local gap = ui.frame.Size.X.Offset / 2 + SIDE_GAP / zoom
			ui.side.AnchorPoint = Vector2.new(0.5 - dir.X / 2, 0.5 - dir.Y / 2)
			ui.side.Position = UDim2.new(0, x + dir.X * gap, 0, y + dir.Y * gap)
		end
	end
end

-- Чем ближе карта, тем больше подробностей: точки → буква → имя → имя с рецептом.
-- Зовётся из applyZoom, то есть на каждое изменение масштаба (при наведении — на каждом
-- кадре движения), а не просто каждый кадр.
function applyLod()
	local tier = lodTier()
	local ring = (tier == 1) and 16 or 18
	for key, ui in nodeGui do
		local size = nodeSize(ui, hovered == key)
		ui.frame.Size = size
		ui.label.Visible = tier >= 2
		ui.label.Text = (tier == 2) and ui.glyph or ui.caption
		ui.detail.Visible = tier >= 4 and ui.detailText ~= nil
		if tier == 1 and ui.base then
			ui.glow.Size = UDim2.new(0, HALO / zoom, 0, HALO / zoom)
		else
			ui.glow.Size = UDim2.new(0, size.X.Offset + ring, 0, size.Y.Offset + ring)
		end
		if ui.side then
			ui.side.Visible = tier == 1
			ui.side.TextSize = math.min(SIDE_TEXT / zoom, 100)
		end
	end
	-- Узлы — на места под нынешний поворот, заодно с отступом подписей стихий:
	-- он зависит от размера точки, а тот только что сменился.
	spin.place()
	repaint()
end

local function drawGraph()
	-- Сносятся только рисунки: UIScale — тоже ребёнок слоя, и ClearAllChildren унёс бы
	-- вместе с ними весь масштаб.
	for _, child in graphLayer:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	table.clear(nodeGui)
	table.clear(edgeGui)
	table.clear(edgesOf)
	wire.reset()
	hovered = nil
	hintBar.Visible = false

	-- Подложка во весь холст: нажатие мимо узлов снимает выбор. Отдельной кнопкой,
	-- а не разбором координат в обработчике протяжки: узлы лежат выше и забирают нажатие себе.
	local plate = Instance.new("TextButton")
	plate.Size = UDim2.new(1, 0, 1, 0)
	plate.BackgroundTransparency = 1
	plate.Text = ""
	plate.AutoButtonColor = false
	plate.ZIndex = 0
	plate.Parent = graphLayer
	plate.MouseButton1Click:Connect(function()
		if panMoved <= 6 then
			selectNode(nil)
		end
	end)

	-- Звенья — в своём слое: поворот карты — это Rotation слоя вокруг его середины,
	-- поэтому середина слоя стоит ровно в середине ромба.
	local lines = Instance.new("Frame")
	lines.Name = "Lines"
	lines.BackgroundTransparency = 1
	lines.Size = UDim2.new(0, graph.centre[1] * 2, 0, graph.centre[2] * 2)
	lines.Rotation = math.deg(spin.angle)
	lines.ZIndex = 1
	lines.Parent = graphLayer
	spin.layer = lines

	-- Кольца ярусов — первыми, под связями, кривыми, как и связи.
	wire.rings()
	for _, key in graph.keys do
		edgesOf[key] = {}
	end
	for _, edge in graph.edges do
		drawEdge(edge)
	end
	for _, key in graph.keys do
		drawNode(key)
	end

	-- Связи нарисованы заново, и прежние записи о них — уже мусор: цепочку пересчитываем.
	if selected then
		chainNodes, chainEdges = chainOf(selected)
	end
	-- Не repaint, а applyLod: узлы только что собраны в полную величину, а масштаб к этому
	-- моменту уже выставлен — подробность надо привести в соответствие сразу.
	-- Он же ставит узлы под нынешний поворот: собраны они на неповёрнутых местах.
	applyLod()
end

-- Наведение на элемент: карта поворачивается так, чтобы он встал справа от середины
-- ромба, а вид едет к нему и приближается (spin.AIM_ZOOM). Само движение — в RenderStepped,
-- одним счётом на кадр, а не твинами: поворот уносит элемент, и вид догоняет его каждый кадр.
-- Плавно, а не прыжком: на карте в две тысячи пикселей мгновенный перенос вида читается
-- как «страница подменилась», и найти прежнее место потом невозможно.
function focusOn(key)
	local place = graph and graph.nodes[key]
	if not place then
		return
	end
	local view = graphScroll.AbsoluteSize
	local angle = math.atan2(place.y - graph.centre[2], place.x - graph.centre[1])
	spin.aim = {
		key = key,
		t = 0,
		look = (graphScroll.CanvasPosition + view / 2 - canvasPad()) / zoom, -- точка под серединой окна
		from = spin.angle,
		turn = (-angle - spin.angle + math.pi) % (math.pi * 2) - math.pi, -- кратчайший путь до «направо»
		zoom = zoom,
		toZoom = math.clamp(math.max(zoom, spin.AIM_ZOOM), ZOOM_MIN, ZOOM_MAX),
	}
end

-- Список под картой: либо все открытые рецепты, либо — когда элемент выбран — его цепочка
-- создания по шагам, от базовых вверх. На карте цепочка видна целиком, но порядка шагов
-- по ней не прочитать — список говорит ровно это. Строка ведёт обратно на карту: нажатие
-- выбирает элемент и подводит к нему вид — искать нужный узел глазами по всей карте не надо.
local function refreshBook()
	listScroll:ClearAllChildren()
	-- Сетка: рецепт — короткая строка в три слова, и на полном экране колонка таких
	-- строк — это метр пустоты справа от каждой и прокрутка после десятой.
	Theme.Grid(listScroll, 24, 340, 4)

	backButton.Visible = selected ~= nil

	local steps = {}
	if selected then
		for key in chainNodes do
			if graph.producedBy[key] then
				table.insert(steps, { key = key, recipe = graph.producedBy[key] })
			end
		end
		-- Порядок цепочки — по глубине: сначала то, что делается прямо из базовых.
		table.sort(steps, function(one, two)
			if graph.depth[one.key] ~= graph.depth[two.key] then
				return graph.depth[one.key] < graph.depth[two.key]
			end
			return Elements[one.key].name < Elements[two.key].name
		end)
	else
		for _, recipe in Recipes.List do
			if knownRecipes[recipe.result] then
				table.insert(steps, { key = recipe.result, recipe = recipe })
			end
		end
	end

	local opened = 0
	for order, entry in steps do
		local known = knownRecipes[entry.key] == true
		if known then
			opened += 1
		end

		local row = Instance.new("TextButton")
		row.LayoutOrder = order -- размер задаёт сетка
		row.Text = ""
		row.AutoButtonColor = false
		row.Parent = listScroll

		-- Строка залита цветом результата, сам рецепт — на подложке затемнённого
		-- того же цвета, как в остальных списках. Неоткрытый шаг цепочки — нейтральной
		-- сталью: цвет элемента назвал бы его не хуже имени.
		Theme.ElementFill(row, known and Elements[entry.key].color or Theme.color.steel, {
			wide = true,
			element = known and entry.key or nil,
		})

		local label = Instance.new("TextLabel")
		label.FontFace = Theme.font.body
		label.TextSize = 13
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.Text = known
			and Theme.Caps(("%s + %s = %s"):format(
				Elements[entry.recipe.a].name, Elements[entry.recipe.b].name, Elements[entry.key].name
			))
			or "??? + ??? = ???"
		label.Parent = row

		-- Отступ меньше обычного: строка рецепта высотой всего 24px, и пять пикселей
		-- с каждой стороны съели бы её целиком.
		Theme.Inner(label, 3)

		-- Текст прижат влево, поэтому отступ от края начинки делает UIPadding.
		local labelPad = Instance.new("UIPadding")
		labelPad.PaddingLeft = UDim.new(0, 8)
		labelPad.PaddingRight = UDim.new(0, 8)
		labelPad.Parent = label

		row.MouseButton1Click:Connect(function()
			if Theme.WasDragged(listScroll) then
				return
			end
			selectNode(entry.key)
			focusOn(entry.key)
		end)
	end

	if #steps == 0 then
		local empty = Instance.new("TextLabel")
		empty.Size = UDim2.new(1, -10, 0, 24)
		empty.BackgroundTransparency = 1
		empty.FontFace = Theme.font.body
		empty.TextSize = 13
		empty.TextColor3 = Theme.color.textMute
		empty.TextXAlignment = Enum.TextXAlignment.Left
		empty.Text = selected ~= nil
			and "Это базовый элемент — его не создают, а покупают за материю."
			or "Пока ничего не открыто — скрестите два элемента во вкладке «Крафт»."
		empty.Parent = listScroll
	end

	if selected then
		-- Имя неоткрытого элемента не называется и в заголовке — на карте он тоже «???».
		local ui = nodeGui[selected]
		local title = (ui and ui.known) and Elements[selected].name or "???"
		Theme.Section(openedLabel, ("цепочка: %s"):format(title), ("%d из %d шагов"):format(opened, #steps))
	else
		Theme.Section(openedLabel, "рецепты", ("%d из %d"):format(opened, #Recipes.List))
	end
end

-- Повторное нажатие на тот же элемент снимает выбор: карта возвращается в полную силу,
-- список — ко всем открытым рецептам.
function selectNode(key)
	if key ~= nil and key == selected then
		key = nil
	end
	selected = key
	if key then
		chainNodes, chainEdges = chainOf(key)
	else
		chainNodes, chainEdges = {}, {}
	end
	repaint()
	refreshBook()
end

backButton.MouseButton1Click:Connect(function()
	selectNode(nil)
end)

-- Раскладка считается не при входе в игру, а при первом открытии справочника: счёт
-- занимает около четверти секунды, и на слабом телефоне это заметная пауза ровно в тот
-- момент, когда игрок появляется на арене. До справочника он доходит гораздо позже.
local function ensureGraph()
	if graph then
		return
	end
	graph = Graph.Build()
	graphLayer.Size = UDim2.new(0, graph.width, 0, graph.height)
	fitZoom()
	drawGraph()
end

bookFrame:GetPropertyChangedSignal("Visible"):Connect(function()
	if bookFrame.Visible then
		ensureGraph()
	end
end)

graphScroll:GetPropertyChangedSignal("AbsoluteSize"):Connect(applyZoom)

-- ---------- как двигают граф ----------
-- Нажатие ловится через UserInputService, а не на самом холсте: узлы лежат поверх него
-- и забирали бы нажатие себе (та же причина, что у Theme.DragScroll).

local panning = false
local panLast = Vector2.new(0, 0)

local function overGraph(position)
	if not (gui.Enabled and bookFrame.Visible) then
		return false
	end
	local at = graphScroll.AbsolutePosition
	local size = graphScroll.AbsoluteSize
	return position.X >= at.X and position.X <= at.X + size.X
		and position.Y >= at.Y and position.Y <= at.Y + size.Y
end

UserInputService.InputBegan:Connect(function(input)
	if input.UserInputType ~= Enum.UserInputType.MouseButton1
		and input.UserInputType ~= Enum.UserInputType.Touch then
		return
	end
	local position = Vector2.new(input.Position.X, input.Position.Y)
	if not overGraph(position) then
		return
	end
	panning = true
	panLast = position
	panMoved = 0
	-- Карту взяли рукой: наведение отпускает вид. Нажатие на узел тоже сюда попадает,
	-- но его наведение заводится позже, на отпускании (MouseButton1Click).
	spin.aim = nil
end)

UserInputService.InputChanged:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseWheel then
		if overGraph(Vector2.new(input.Position.X, input.Position.Y)) then
			setZoom(zoom + input.Position.Z * ZOOM_STEP)
		end
		return
	end
	if not panning then
		return
	end
	if input.UserInputType ~= Enum.UserInputType.MouseMovement
		and input.UserInputType ~= Enum.UserInputType.Touch then
		return
	end
	local position = Vector2.new(input.Position.X, input.Position.Y)
	local shift = position - panLast
	-- Копим пройденное, а не смотрим на расстояние от начала: карту часто тащат
	-- туда-сюда и отпускают там же, где взяли, — выбором это быть не должно.
	panMoved += shift.Magnitude
	graphScroll.CanvasPosition = graphScroll.CanvasPosition - shift
	panLast = position
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		panning = false
	end
end)

-- Каждый кадр, пока карта на экране: вращение или наведение, затем перенос кривых.
-- Пока элемент выбран, поворот стоит там, куда его привело наведение (или протяжка,
-- которая его прервала); снятый выбор снова пускает карту. Кривые сверяются каждый
-- кадр: вид двигают и рукой, и колесом, и наведением, и поворотом, и ростом окна при
-- открытии — ловить каждое по отдельности ненадёжно, а сверка пяти значений за кадр
-- ничего не стоит.
RunService.RenderStepped:Connect(function(dt)
	if not (gui.Enabled and bookFrame.Visible and graph) then
		return
	end
	local aim = spin.aim
	if aim then
		aim.t = math.min(1, aim.t + dt / spin.AIM_TIME)
		local k = TweenService:GetValue(aim.t, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
		spin.angle = (aim.from + aim.turn * k) % (math.pi * 2)
		zoom = aim.zoom + (aim.toZoom - aim.zoom) * k
		applyZoom() -- через applyLod ставит и узлы под новый поворот
		local place = graph.nodes[aim.key]
		local ox, oy = graph.centre[1], graph.centre[2]
		local c, s = math.cos(spin.angle), math.sin(spin.angle)
		local dx, dy = place.x - ox, place.y - oy
		local target = Vector2.new(ox + dx * c - dy * s, oy + dx * s + dy * c)
		local want = aim.look:Lerp(target, k) * zoom + canvasPad() - graphScroll.AbsoluteSize / 2
		graphScroll.CanvasPosition = Vector2.new(math.max(0, want.X), math.max(0, want.Y))
		if aim.t >= 1 then
			spin.aim = nil
		end
	elseif selected == nil then
		spin.angle = (spin.angle + spin.SPEED * dt) % (math.pi * 2)
		spin.place()
	end
	wire.update()
end)

-- ============ Подключение к серверу ============

InventoryChanged.OnClientEvent:Connect(function(counts)
	inventory = counts
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
	if graph then
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
