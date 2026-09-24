-- Карточка справочника: всё, что игра знает об одном элементе или жуке.
--
-- Одна сборка на три места: карточка выбранного узла на карте рецептов и правая половина
-- вкладок «Элементы» и «Жуки». Две копии разошлись бы при первой же правке — то же правило,
-- что у EntityInfo.
--
-- Слова — из ReferenceTexts (тексты для игрока по смыслу вики), числа и свойства — из
-- таблиц игры (Elements, Enemies, EntityInfo). Своих описаний здесь нет: фраза от себя
-- разошлась бы с тем, что делает код, при первой правке баланса.
--
-- Неоткрытое не называется: у элемента без открытого рецепта нет ни имени, ни описания,
-- ни списка «идёт в» — иначе справочник выдал бы рецепт, который надо открыть самому
-- (решение автора: «учи крафты»). Жук, которого ещё ни разу не убили, — так же.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Theme = require(script.Parent:WaitForChild("UITheme"))
local EntityInfo = require(script.Parent:WaitForChild("EntityInfo"))
local MobileUI = require(script.Parent:WaitForChild("MobileUI"))

local Elements = require(ReplicatedStorage:WaitForChild("Elements"))
local Enemies = require(ReplicatedStorage:WaitForChild("Enemies"))
local Recipes = require(ReplicatedStorage:WaitForChild("Recipes"))
local ReferenceTexts = require(ReplicatedStorage:WaitForChild("ReferenceTexts"))
local EnemyModel = require(ReplicatedStorage:WaitForChild("EnemyModel"))
local Mastery = require(ReplicatedStorage:WaitForChild("Mastery"))

local Detail = {}

local mobile = MobileUI.isMobile
-- Места в карточке много — текст крупный (просьба автора: описание было слишком мелким).
local TEXT = mobile and 15 or 18
local SMALL = mobile and 13 or 14

-- Во что идёт элемент: рецепты, где он один из двух ингредиентов. Считается один раз.
local usedIn = {}
for _, recipe in Recipes.List do
	for _, part in { recipe.a, recipe.b } do
		usedIn[part] = usedIn[part] or {}
		if not table.find(usedIn[part], recipe) then
			table.insert(usedIn[part], recipe)
		end
	end
end
for _, list in usedIn do
	table.sort(list, function(one, two)
		local a, b = Elements[one.result], Elements[two.result]
		if a.tier ~= b.tier then
			return a.tier < b.tier
		end
		return a.name < b.name
	end)
end

function Detail.UsedIn(key)
	return usedIn[key] or {}
end

-- Строчные буквы для поиска. string.lower в Luau знает только латиницу, а имена
-- в игре русские: А–Я сдвигаются на 32, Ё — отдельно.
function Detail.Lower(text)
	local out = {}
	for _, code in utf8.codes(text) do
		if code >= 0x410 and code <= 0x42F then
			code += 32
		elseif code == 0x401 then
			code = 0x451
		elseif code >= 65 and code <= 90 then
			code += 32
		end
		table.insert(out, utf8.char(code))
	end
	return table.concat(out)
end

-- ---------- сборка строк ----------

local function clear(scroll)
	for _, child in scroll:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	if not scroll:FindFirstChildOfClass("UIListLayout") then
		local layout = Instance.new("UIListLayout")
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Padding = UDim.new(0, 6)
		layout.Parent = scroll
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 12)
		pad.PaddingRight = UDim.new(0, 12)
		pad.PaddingTop = UDim.new(0, 10)
		pad.PaddingBottom = UDim.new(0, 12)
		pad.Parent = scroll
	end
	scroll.CanvasPosition = Vector2.new(0, 0)
end

local function text(scroll, order, value, size, color, font)
	local label = Instance.new("TextLabel")
	label.LayoutOrder = order
	label.Size = UDim2.new(1, 0, 0, 0)
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.BackgroundTransparency = 1
	label.FontFace = font or Theme.font.body
	label.TextSize = size or TEXT
	label.TextColor3 = color or Theme.color.textDim
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.RichText = true
	label.Text = value
	label.ZIndex = scroll.ZIndex + 1
	label.Parent = scroll
	return label
end

local function title(scroll, order, value, color, mark)
	local label = text(scroll, order, Theme.Caps(value), mobile and 22 or 30, color, Theme.font.strong)
	label.TextWrapped = false
	label.TextTruncate = Enum.TextTruncate.AtEnd
	if mark then
		text(scroll, order + 1, Theme.Caps(mark), SMALL, Theme.color.textMute, Theme.font.strong)
	end
	return label
end

-- Показание «подпись — значение» одной строкой: число в цвете, подпись приглушена.
local function reading(scroll, order, name, value, color)
	return text(scroll, order, ("%s  <font color=\"#%s\"><b>%s</b></font>"):format(
		Theme.Caps(name), (color or Theme.color.text):ToHex(), value
	), TEXT, Theme.color.textMute)
end

-- Строка «что откроется следующим» (ступени Mastery): одна, ближайшая — не список замков.
local function nextStep(scroll, order, steps, kills, whose)
	local step, need = Mastery.Next(steps, kills)
	if step and Mastery.CAPTION[step] then
		text(scroll, order, Theme.Caps(("%s — откроется за %d убийств %s · сейчас %d"):format(
			Mastery.CAPTION[step], need, whose, kills
		)), SMALL, Theme.color.textMute, Theme.font.strong)
	end
end

-- Закрытая вкладка: чем открыть.
local function lockedTab(scroll, need, kills, whose)
	text(scroll, 30, ("Откроется за %d убийств %s. Сейчас: %d."):format(need, whose, kills), TEXT,
		Theme.color.textMute)
end

-- Разделитель: «эффект», справа от него сами эффекты, дальше черта до края. Цвет — цвет
-- имени элемента. Длинный список эффектов переносится, черта тогда сжимается.
local function divider(scroll, order, caption, effects, color)
	local row = Instance.new("Frame")
	row.LayoutOrder = order
	row.Size = UDim2.new(1, 0, 0, TEXT + 12)
	row.AutomaticSize = Enum.AutomaticSize.Y
	row.BackgroundTransparency = 1
	row.ZIndex = scroll.ZIndex + 1
	row.Parent = scroll
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 10)
	layout.Parent = row
	local label = text(row, 1, Theme.Caps(caption), TEXT, Theme.color.textMute, Theme.font.strong)
	label.AutomaticSize = Enum.AutomaticSize.XY
	label.Size = UDim2.new(0, 0, 0, 0)
	label.TextWrapped = false
	if effects then
		local list = text(row, 2, effects, TEXT, color, Theme.font.strong)
		list.AutomaticSize = Enum.AutomaticSize.XY
		list.Size = UDim2.new(0, 0, 0, 0)
		local shrink = Instance.new("UIFlexItem")
		shrink.FlexMode = Enum.UIFlexMode.Shrink
		shrink.Parent = list
	end
	local line = Instance.new("Frame")
	line.LayoutOrder = 3
	line.Size = UDim2.new(0, 0, 0, 2)
	line.BackgroundColor3 = color
	line.BackgroundTransparency = 0.35
	line.BorderSizePixel = 0
	line.ZIndex = row.ZIndex + 1
	line.Parent = row
	local fill = Instance.new("UIFlexItem") -- черта занимает всё место справа
	fill.FlexMode = Enum.UIFlexMode.Fill
	fill.Parent = line
	return row
end

-- Блок под разделителем: строки с отступом и цветной чертой слева — видно, что это уже
-- не общие характеристики, а своё у элемента.
local function effectBlock(scroll, order, color)
	local block = Instance.new("Frame")
	block.LayoutOrder = order
	block.Size = UDim2.new(1, 0, 0, 0)
	block.AutomaticSize = Enum.AutomaticSize.Y
	block.BackgroundTransparency = 1
	block.ZIndex = scroll.ZIndex + 1
	block.Parent = scroll
	-- Черта — отдельно от списка строк: UIListLayout поставил бы её в очередь.
	local bar = Instance.new("Frame")
	bar.Size = UDim2.new(0, 2, 1, 0)
	bar.BackgroundColor3 = color
	bar.BackgroundTransparency = 0.3
	bar.BorderSizePixel = 0
	bar.ZIndex = block.ZIndex + 1
	bar.Parent = block
	local rows = Instance.new("Frame")
	rows.Position = UDim2.new(0, 10, 0, 0)
	rows.Size = UDim2.new(1, -10, 0, 0)
	rows.AutomaticSize = Enum.AutomaticSize.Y
	rows.BackgroundTransparency = 1
	rows.ZIndex = block.ZIndex
	rows.Parent = block
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 4)
	layout.Parent = rows
	local pad = Instance.new("UIPadding")
	pad.PaddingBottom = UDim.new(0, 8) -- отступ до кнопки «показать на карте»
	pad.Parent = rows
	return rows
end

-- Строка-ссылка на другой элемент: нажатие ведёт к нему (ctx.onPick).
local function link(scroll, order, key, value, ctx)
	local button = Instance.new("TextButton")
	button.LayoutOrder = order
	button.Size = UDim2.new(1, 0, 0, mobile and 32 or 24)
	button.Text = ""
	button.AutoButtonColor = false
	-- Карточка лежит на плашке с высоким ZIndex (поверх карты); при общем порядке слоёв
	-- строки с ZIndex по умолчанию ушли бы под её полупрозрачный фон и еле читались.
	button.ZIndex = scroll.ZIndex + 1
	button.Parent = scroll
	Theme.ElementFill(button, Elements[key].color, { wide = true, element = key })

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.FontFace = Theme.font.body
	label.TextSize = SMALL + 1
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Text = value
	label.ZIndex = button.ZIndex + 1
	label.Parent = button
	Theme.Inner(label, 3)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 8)
	pad.Parent = label

	if ctx.onPick then
		button.MouseButton1Click:Connect(function()
			ctx.onPick(key)
		end)
	end
	return button
end

-- ---------- элемент ----------

-- Карточка элемента делится на две вкладки: «Описание» (узор во всю ширину, показания,
-- текст) и «В крафтах» (во что элемент идёт дальше) — просьба автора: узор и описание
-- главное, использование в рецептах — отдельно. Выбранная вкладка помнится между
-- элементами: листая элементы, игрок обычно смотрит одно и то же.
local elementTab = "about"

-- Кнопка вкладки карточки.
local function tabButton(parent, caption, on, action)
	local button = Instance.new("TextButton")
	button.Size = UDim2.new(0.5, -3, 1, 0)
	button.FontFace = Theme.font.strong
	button.TextSize = SMALL
	button.Text = Theme.Caps(caption)
	button.ZIndex = parent.ZIndex + 1
	button.Parent = parent
	Theme.Button(button, on and "active" or "ghost")
	button.MouseButton1Click:Connect(action)
	return button
end

-- Узор элемента целиком: вся текстура, а не окно размером с ячейку, как в списках. Цвет —
-- как у ячейки: фон цвета элемента, узор его светлым оттенком. Нажатие раскрывает узор
-- на всю панель (overlay) — разглядеть детали.
local function patternView(scroll, order, key)
	local spec = Theme.patterns and Theme.patterns[key]
	local element = Elements[key]
	if not spec then
		return
	end
	local ratio = spec.size.X / spec.size.Y

	local function paint(frame, image)
		frame.BackgroundColor3 = Theme.Shadowed(element.color, 0.55)
		frame.BackgroundTransparency = 0
		image.Image = spec.image
		image.ImageColor3 = spec.color or Theme.PatternTint(element.color)
		-- Прозрачнее, чем в ячейке: там узор — фон под текстом, здесь — сам предмет показа.
		image.ImageTransparency = math.min(spec.transparency or 0.7, 0.35)
		image.ScaleType = Enum.ScaleType.Fit
		image.BackgroundTransparency = 1
	end

	local box = Instance.new("ImageButton")
	box.Name = "Pattern"
	box.LayoutOrder = order
	box.Size = UDim2.new(1, 0, 0, 0)
	box.AutoButtonColor = false
	box.ZIndex = scroll.ZIndex + 1
	box.Parent = scroll
	Theme.Corner(box, Theme.radius.control)
	-- Высота — в пикселях от ширины карточки: у списка с AutomaticCanvasSize высота в долях
	-- считалась бы от холста, который сам зависит от детей. Ширина карточки меняется
	-- (окно, поворот телефона) — высота следом.
	local function fit()
		local width = math.max(0, scroll.AbsoluteSize.X - 28)
		box.Size = UDim2.new(1, 0, 0, math.floor(width / ratio))
	end
	fit()
	local resized = scroll:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	box.Destroying:Once(function()
		resized:Disconnect()
	end)
	local image = Instance.new("ImageLabel")
	image.Size = UDim2.new(1, 0, 1, 0)
	image.ZIndex = box.ZIndex + 1
	image.Parent = box
	Theme.Corner(image, Theme.radius.control)
	paint(box, image)

	box.MouseButton1Click:Connect(function()
		local host = scroll.Parent
		if not host or host:FindFirstChild("PatternZoom") then
			return
		end
		local zoom = Instance.new("ImageButton")
		zoom.Name = "PatternZoom"
		zoom.AutoButtonColor = false
		zoom.Size = UDim2.new(1, 0, 1, 0)
		zoom.ZIndex = scroll.ZIndex + 10
		zoom.Parent = host
		local big = Instance.new("ImageLabel")
		big.Size = UDim2.new(1, -16, 1, -16)
		big.Position = UDim2.new(0, 8, 0, 8)
		big.ZIndex = zoom.ZIndex + 1
		big.Parent = zoom
		paint(zoom, big)
		local close = text(zoom, 0, Theme.Caps("нажмите, чтобы закрыть"), SMALL, Theme.color.text, Theme.font.strong)
		close.AutomaticSize = Enum.AutomaticSize.None
		close.Size = UDim2.new(1, -24, 0, 18)
		close.Position = UDim2.new(0, 12, 1, -26)
		close.ZIndex = big.ZIndex + 1
		zoom.MouseButton1Click:Connect(function()
			zoom:Destroy()
		end)
		scroll.Destroying:Once(function()
			zoom:Destroy()
		end)
	end)
	return box
end

-- Шапка карточки: имя, рецепт и характеристики на фоне узора элемента (просьба автора).
-- Узор — целиком по ширине шапки, обрезан по высоте; поверх — тёмная вуаль, чтобы текст
-- читался на любом узоре.
-- Печать «в разработке» поверх всей шапки: содержимое под ней затемнено, как бумага,
-- которую отклонили. Под словом — что именно пока не работает.
local function rejectStamp(head, reason)
	local veil = Instance.new("Frame")
	veil.Name = "Rejected"
	veil.Size = UDim2.new(1, 0, 1, 0)
	veil.BackgroundColor3 = Color3.new(0, 0, 0)
	veil.BackgroundTransparency = 0.35
	veil.BorderSizePixel = 0
	veil.ZIndex = head.ZIndex + 20
	veil.Parent = head
	local stamp = Instance.new("TextLabel")
	stamp.AnchorPoint = Vector2.new(0.5, 0.5)
	stamp.Position = UDim2.new(0.5, 0, 0.5, 0)
	stamp.AutomaticSize = Enum.AutomaticSize.XY
	stamp.Size = UDim2.new(0, 0, 0, 0)
	stamp.Rotation = -8
	stamp.BackgroundTransparency = 1
	stamp.RichText = true
	stamp.FontFace = Theme.font.strong
	stamp.TextSize = mobile and 26 or 38
	stamp.TextColor3 = Theme.color.danger
	stamp.Text = ("%s\n<font size=\"%d\">%s</font>"):format(Theme.Caps("в разработке"), SMALL, Theme.Caps(reason))
	stamp.ZIndex = veil.ZIndex + 1
	stamp.Parent = veil
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 14)
	pad.PaddingRight = UDim.new(0, 14)
	pad.PaddingTop = UDim.new(0, 6)
	pad.PaddingBottom = UDim.new(0, 8)
	pad.Parent = stamp
	local frame = Instance.new("UIStroke")
	frame.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	frame.Color = Theme.color.danger
	frame.Thickness = 3
	frame.Parent = stamp
	Theme.Corner(stamp, 6)
end

-- color — цвет сущности (элемента или жука), spec — узор из Theme.patterns (у жуков нет).
local function patternHead(scroll, order, color, spec)

	local head = Instance.new("Frame")
	head.Name = "Head"
	head.LayoutOrder = order
	head.Size = UDim2.new(1, 0, 0, 0)
	head.AutomaticSize = Enum.AutomaticSize.Y
	head.BackgroundColor3 = Theme.Shadowed(color, 0.6)
	head.ClipsDescendants = true
	head.ZIndex = scroll.ZIndex + 1
	head.Parent = scroll
	Theme.Corner(head, Theme.radius.control)

	if spec then
		local image = Instance.new("ImageLabel")
		image.Size = UDim2.new(1, 0, 1, 0)
		image.BackgroundTransparency = 1
		image.Image = spec.image
		image.ImageColor3 = spec.color or Theme.PatternTint(color)
		image.ImageTransparency = math.min(spec.transparency or 0.7, 0.45)
		image.ScaleType = Enum.ScaleType.Crop
		image.ZIndex = head.ZIndex + 1
		image.Parent = head
	end

	local veil = Instance.new("Frame")
	veil.Size = UDim2.new(1, 0, 1, 0)
	veil.BackgroundColor3 = Color3.new(0, 0, 0)
	veil.BackgroundTransparency = 0.45
	veil.BorderSizePixel = 0
	veil.ZIndex = head.ZIndex + 2
	veil.Parent = head

	local body = Instance.new("Frame")
	body.Name = "Body"
	body.Size = UDim2.new(1, 0, 0, 0)
	body.AutomaticSize = Enum.AutomaticSize.Y
	body.BackgroundTransparency = 1
	body.ZIndex = head.ZIndex + 3
	body.Parent = head
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 5)
	layout.Parent = body
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 12)
	pad.PaddingRight = UDim.new(0, 12)
	pad.PaddingTop = UDim.new(0, 10)
	pad.PaddingBottom = UDim.new(0, 12)
	pad.Parent = body
	return body
end

-- ctx: known(key) — открыт ли элемент, craftable(key) — можно ли скрафтить сейчас,
-- onPick(key) — переход к другому элементу, onShowOnMap(key) — кнопка «показать на карте»
-- (нет поля — нет кнопки: на самой карте она не нужна).
function Detail.Element(scroll, key, ctx)
	clear(scroll)
	local element = Elements[key]
	if not element then
		return
	end
	local recipe = EntityInfo.RecipeOf(key)
	local known = ctx.known(key)

	if not known then
		title(scroll, 10, "???", Theme.color.textMute)
		text(scroll, 30, "Рецепт ещё не открыт. Скрестите нужную пару на столе — и здесь появится всё об элементе.")
		return
	end

	-- Ступени (Mastery.ELEMENT): что открыто — по числу жуков, добитых этим элементом.
	-- Нет счёта в ctx — открыто всё.
	local kills = ctx.kills and ctx.kills(key) or math.huge
	local function open(step)
		return kills >= Mastery.ELEMENT[step]
	end
	local WHOSE = "этим элементом"
	if not open("card") then
		title(scroll, 10, element.name, Theme.Legible(element.color))
		text(scroll, 30, "Добейте этим элементом хотя бы одного жука — откроется карточка.", TEXT,
			Theme.color.textMute)
		return
	end

	-- Вкладки карточки — сверху, над шапкой с узором.
	local tabs = Instance.new("Frame")
	tabs.Name = "Tabs"
	tabs.LayoutOrder = 10
	tabs.Size = UDim2.new(1, 0, 0, mobile and MobileUI.MIN_TAP or 26)
	tabs.BackgroundTransparency = 1
	tabs.ZIndex = scroll.ZIndex + 1
	tabs.Parent = scroll
	local tabsLayout = Instance.new("UIListLayout")
	tabsLayout.FillDirection = Enum.FillDirection.Horizontal
	tabsLayout.Padding = UDim.new(0, 6)
	tabsLayout.Parent = tabs
	local uses = Detail.UsedIn(key)
	for _, tab in {
		{ id = "about", caption = "описание" },
		{ id = "uses", caption = ("используется в · %d"):format(#uses) },
		{ id = "pattern", caption = "узор" },
	} do
		local button = tabButton(tabs, tab.caption, elementTab == tab.id, function()
			elementTab = tab.id
			Detail.Element(scroll, key, ctx)
		end)
		button.Size = UDim2.new(1 / 3, -4, 1, 0)
	end

	if elementTab == "pattern" then
		-- Узор целиком — разглядеть все детали; нажатие раскрывает его на всю панель.
		if open("pattern") then
			patternView(scroll, 20, key)
		else
			lockedTab(scroll, Mastery.ELEMENT.pattern, kills, WHOSE)
		end
		return
	end

	if elementTab == "uses" then
		if not open("crafts") then
			lockedTab(scroll, Mastery.ELEMENT.crafts, kills, WHOSE)
			return
		end
		-- Во что идёт дальше. Неоткрытые рецепты не называются даже вторым ингредиентом:
		-- «Огонь + ??? = ???» уже подсказка. Остаётся только их число.
		if #uses == 0 then
			text(scroll, 30, "Этот элемент ни в какой рецепт не идёт — это вершина ветки.", TEXT, Theme.color.textMute)
			return
		end
		local hidden = 0
		for index, use in uses do
			if ctx.known(use.result) then
				link(scroll, 30 + index, use.result, Theme.Caps(("%s = %s + %s"):format(
					Elements[use.result].name, Elements[use.a].name, Elements[use.b].name
				)), ctx)
			else
				hidden += 1
			end
		end
		if hidden > 0 then
			text(scroll, 30 + #uses + 1, Theme.Caps(("и ещё %d %s"):format(hidden,
				hidden == 1 and "неоткрытый рецепт" or (hidden < 5 and "неоткрытых рецепта" or "неоткрытых рецептов")
			)), SMALL, Theme.color.textMute)
		end
		return
	end

	-- «Описание»: шапка на узоре — от имени до «показать на карте», под ней текст.
	local head = patternHead(scroll, 20, element.color,
		open("pattern") and Theme.patterns and Theme.patterns[key] or nil)
	title(head, 10, element.name, Theme.Legible(element.color))
	local unfinished = EntityInfo.IN_DEVELOPMENT[key]
	if unfinished then
		rejectStamp(head.Parent, unfinished) -- head — тело шапки, печать ложится на всю шапку
	end

	nextStep(head, 15, Mastery.ELEMENT, kills, WHOSE)
	if not open("crafts") then
		-- рецепт закрыт
	elseif recipe then
		reading(head, 20, "рецепт", Theme.Caps(("%s + %s"):format(Elements[recipe.a].name, Elements[recipe.b].name)))
	else
		reading(head, 20, "источник", Theme.Caps("производитель"))
	end

	-- Над разделителем «эффект» — что есть у каждого элемента, под ним — чем он особенный.
	local unique = {}
	for index, row in open("stats") and EntityInfo.ElementStats(key, element) or {} do
		if EntityInfo.STANDARD_STATS[row.label] then
			reading(head, 30 + index, row.label, Theme.Caps(row.value))
		else
			table.insert(unique, row)
		end
	end
	local features = open("stats") and EntityInfo.ElementFeatures(key, element) or {}
	local effects = open("stats") and EntityInfo.ElementEffects(key, element) or {}
	if #unique + #features + #effects > 0 then
		local tint = Theme.Legible(element.color) -- как у имени элемента
		-- Подпись разделителя — по тому, что стоит рядом: эффект (остаётся на жуке) или
		-- особенность (как стреляет турель). Есть и то и другое — особенности строкой ниже.
		local featureCaption = #features > 1 and "особенности" or "особенность"
		local featureList = Theme.Caps(table.concat(features, " · "))
		local caption, list = "эффект", nil
		if #effects > 0 then
			-- *так* в подписи эффекта — выделение (EntityInfo.ELEMENT_EFFECTS). Теги — после Caps:
			-- заглавные имена тегов RichText не понимает.
			list = Theme.Caps(table.concat(effects, " · ")):gsub("%*(.-)%*",
				("<font color=\"#%s\">%%1</font>"):format(Theme.color.action:ToHex()))
		elseif #features > 0 then
			caption, list = featureCaption, featureList
		end
		divider(head, 50, caption, list, tint)
		local featuresBelow = #effects > 0 and #features > 0
		if featuresBelow or #unique > 0 then
			local block = effectBlock(head, 51, tint)
			if featuresBelow then
				reading(block, 2, featureCaption, featureList, tint)
			end
			for index, row in unique do
				reading(block, 10 + index, row.label, Theme.Caps(row.value))
			end
		end
	end
	if recipe and open("crafts") and ctx.craftable and ctx.craftable(key) then
		text(head, 70, Theme.Caps("● можно скрафтить сейчас — ингредиенты есть"), SMALL, Theme.color.action,
			Theme.font.strong)
	end
	if ctx.onShowOnMap then
		-- Круглая кнопка в правом нижнем углу шапки, без надписи: значок — прицел (кольцо
		-- с точкой), «где это на карте». Поверх печати «в разработке» — это управление.
		local size = mobile and MobileUI.MIN_TAP or 34
		local go = Instance.new("TextButton")
		go.Name = "ShowOnMap"
		go.AnchorPoint = Vector2.new(1, 1)
		go.Position = UDim2.new(1, -10, 1, -10)
		go.Size = UDim2.new(0, size, 0, size)
		go.Text = ""
		go.ZIndex = head.Parent.ZIndex + 30
		go.Parent = head.Parent
		Theme.Button(go, "quiet")
		Theme.Corner(go, size / 2)
		local ring = Instance.new("Frame")
		ring.AnchorPoint = Vector2.new(0.5, 0.5)
		ring.Position = UDim2.new(0.5, 0, 0.5, 0)
		ring.Size = UDim2.new(0, size * 0.5, 0, size * 0.5)
		ring.BackgroundTransparency = 1
		ring.ZIndex = go.ZIndex + 1
		ring.Parent = go
		Theme.Corner(ring, size)
		local stroke = Instance.new("UIStroke")
		stroke.Color = go.TextColor3 -- цвет надписи кнопки из темы
		stroke.Thickness = 2
		stroke.Parent = ring
		local dot = Instance.new("Frame")
		dot.AnchorPoint = Vector2.new(0.5, 0.5)
		dot.Position = UDim2.new(0.5, 0, 0.5, 0)
		dot.Size = UDim2.new(0, 5, 0, 5)
		dot.BackgroundColor3 = go.TextColor3
		dot.BorderSizePixel = 0
		dot.ZIndex = go.ZIndex + 2
		dot.Parent = go
		Theme.Corner(dot, 3)
		go.MouseButton1Click:Connect(function()
			ctx.onShowOnMap(key)
		end)
	end

	-- Антиматерия — загадка: у неё описания нет совсем (просьба автора), без заглушки.
	if not EntityInfo.MYSTERY[key] then
		text(scroll, 40, ReferenceTexts.elements[element.name] or "Описания в вики пока нет.", TEXT, Theme.color.text)
	end
end

-- ---------- жук ----------

local SPIN_SPEED = math.rad(30) -- градусов в секунду: жука видно со всех сторон за 12 секунд
local VIEW_PITCH = math.rad(22) -- взгляд чуть сверху: у жука главное — спина и лапы

-- Жук, медленно вращающийся в окне (ViewportFrame). Модель — та же, что в бою
-- (EnemyModel.Build), только стоит на месте: в окне нет физики и походки.
local function enemyView(scroll, order, enemy)
	local ok, model = pcall(EnemyModel.Build, enemy, enemy.scale)
	if not ok or not model then
		return
	end

	local view = Instance.new("ViewportFrame")
	view.Name = "Model"
	view.LayoutOrder = order
	-- Окно — на всё свободное место карточки под текстом, но не ниже 220: пустое поле
	-- под описанием и есть место для жука (просьба автора).
	view.Size = UDim2.new(1, 0, 0, math.max(220, math.floor(scroll.AbsoluteSize.Y * 0.5)))
	view.BackgroundColor3 = Theme.color.panel
	view.BackgroundTransparency = 0.4
	view.Ambient = Color3.fromRGB(150, 150, 160)
	view.LightColor = Color3.fromRGB(255, 250, 240)
	view.LightDirection = Vector3.new(-0.4, -1, -0.6)
	view.ZIndex = scroll.ZIndex + 1
	view.Parent = scroll
	Theme.Corner(view, Theme.radius.control)

	local world = Instance.new("WorldModel")
	world.Parent = view
	model:PivotTo(CFrame.new())
	model.Parent = world

	local camera = Instance.new("Camera")
	camera.FieldOfView = 40
	camera.Parent = view
	view.CurrentCamera = camera

	-- Камера смотрит в середину габарита, отступив так, чтобы жук целиком влез в кадр.
	local box, size = model:GetBoundingBox()
	local centre = box.Position
	local radius = size.Magnitude / 2
	local distance = radius / math.sin(math.rad(camera.FieldOfView / 2)) * 1.05
	local angle = math.rad(35)

	local function place()
		local flat = Vector3.new(math.sin(angle), 0, math.cos(angle))
		local eye = centre + (flat * math.cos(VIEW_PITCH) + Vector3.new(0, math.sin(VIEW_PITCH), 0)) * distance
		camera.CFrame = CFrame.lookAt(eye, centre)
	end
	place()

	-- Крутится, только пока окно на экране: закрытая лаборатория кадры не тратит.
	local connection
	connection = RunService.RenderStepped:Connect(function(dt)
		if not view.Parent then
			connection:Disconnect()
			return
		end
		local screen = view:FindFirstAncestorOfClass("ScreenGui")
		if not (screen and screen.Enabled and view.AbsoluteSize.X > 0) then
			return
		end
		angle = (angle + SPIN_SPEED * dt) % (math.pi * 2)
		place()
	end)
	view.Destroying:Once(function()
		connection:Disconnect()
	end)
end

-- ctx: met(key) — убит ли хоть раз.
function Detail.Enemy(scroll, key, ctx)
	clear(scroll)
	local enemy = Enemies[key]
	if type(enemy) ~= "table" then
		return
	end

	-- Ступени (Mastery.ENEMY) — по числу убийств этого жука. Нет счёта в ctx — открыто всё.
	local kills = ctx.kills and ctx.kills(key) or math.huge
	local function open(step)
		return kills >= Mastery.ENEMY[step]
	end

	if not ctx.met(key) or not open("card") then
		title(scroll, 10, "???", Theme.color.textMute)
		text(scroll, 30, "Этот жук ещё не убит. Описание откроется после первого убийства.")
		return
	end

	-- Та же шапка, что у элемента: сверху общее для всех жуков, под разделителем — своё.
	local color = enemy.color or Theme.color.textMute
	local tint = Theme.Legible(color)
	local head = patternHead(scroll, 20, color, nil)
	title(head, 10, enemy.name, tint)
	nextStep(head, 15, Mastery.ENEMY, kills, "этого жука")

	local unique = {}
	for index, row in open("stats") and EntityInfo.EnemyStats(enemy) or {} do
		if row.standard then
			reading(head, 20 + index, row.label, Theme.Caps(row.value))
		else
			table.insert(unique, row)
		end
	end
	local traits = open("stats") and EntityInfo.EnemyTraits(enemy, 99) or {}
	if #traits + #unique > 0 then
		local caption = #traits > 1 and "особенности" or "особенность"
		divider(head, 50, caption, #traits > 0 and Theme.Caps(table.concat(traits, " · ")) or nil, tint)
		if #unique > 0 then
			local block = effectBlock(head, 51, tint)
			for index, row in unique do
				reading(block, 10 + index, row.label, Theme.Caps(row.value))
			end
		end
	end

	local wiki = ReferenceTexts.enemies[enemy.name]
	text(scroll, 50, wiki and wiki.text or "Описания в вики пока нет.", TEXT, Theme.color.text)
	if wiki and wiki.lesson then
		text(scroll, 60, ("<b>%s</b>  %s"):format(Theme.Caps("урок:"), wiki.lesson), TEXT, Theme.color.accent)
	end

	if open("model") then
		enemyView(scroll, 70, enemy)
	end
end

return Detail
