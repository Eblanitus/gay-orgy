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

local function rule(scroll, order)
	local line = Instance.new("Frame")
	line.LayoutOrder = order
	line.Size = UDim2.new(1, 0, 0, 1)
	line.ZIndex = scroll.ZIndex + 1
	line.Parent = scroll
	Theme.Rule(line)
	line.BackgroundTransparency = 0.6
	return line
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
	button.Text = (on and "> " or "") .. Theme.Caps(caption)
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
local function patternHead(scroll, order, key)
	local element = Elements[key]
	local spec = Theme.patterns and Theme.patterns[key]

	local head = Instance.new("Frame")
	head.Name = "Head"
	head.LayoutOrder = order
	head.Size = UDim2.new(1, 0, 0, 0)
	head.AutomaticSize = Enum.AutomaticSize.Y
	head.BackgroundColor3 = Theme.Shadowed(element.color, 0.6)
	head.ClipsDescendants = true
	head.ZIndex = scroll.ZIndex + 1
	head.Parent = scroll
	Theme.Corner(head, Theme.radius.control)

	if spec then
		local image = Instance.new("ImageLabel")
		image.Size = UDim2.new(1, 0, 1, 0)
		image.BackgroundTransparency = 1
		image.Image = spec.image
		image.ImageColor3 = spec.color or Theme.PatternTint(element.color)
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
		title(scroll, 10, "???", Theme.color.textMute, ("тир %d"):format(element.tier))
		text(scroll, 30, "Рецепт ещё не открыт. Скрестите нужную пару на столе — и здесь появится всё об элементе.")
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
		patternView(scroll, 20, key)
		return
	end

	if elementTab == "uses" then
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
	local head = patternHead(scroll, 20, key)
	title(head, 10, element.name, Theme.Legible(element.color))

	if recipe then
		reading(head, 20, "рецепт", Theme.Caps(("%s + %s"):format(Elements[recipe.a].name, Elements[recipe.b].name)))
	else
		reading(head, 20, "источник", Theme.Caps("производитель"))
	end

	for index, row in EntityInfo.ElementStats(key, element) do
		reading(head, 30 + index, row.label, Theme.Caps(row.value))
	end

	local features = EntityInfo.ElementFeatures(key, element)
	if #features > 0 then
		reading(head, 60, "особенности", Theme.Caps(table.concat(features, " · ")), Theme.color.accent)
	end
	local effects = EntityInfo.ElementEffects(key, element)
	if #effects > 0 then
		-- *так* в подписи эффекта — выделение (EntityInfo.ELEMENT_EFFECTS). Теги — после Caps:
		-- заглавные имена тегов RichText не понимает.
		local value = Theme.Caps(table.concat(effects, " · ")):gsub("%*(.-)%*",
			("<font color=\"#%s\">%%1</font>"):format(Theme.color.action:ToHex()))
		reading(head, 61, "эффект", value, Theme.color.accent)
	end
	if recipe and ctx.craftable and ctx.craftable(key) then
		text(head, 70, Theme.Caps("● можно скрафтить сейчас — ингредиенты есть"), SMALL, Theme.color.action,
			Theme.font.strong)
	end
	if ctx.onShowOnMap then
		local go = Instance.new("TextButton")
		go.LayoutOrder = 80
		go.Size = UDim2.new(0, 170, 0, mobile and MobileUI.MIN_TAP or 26)
		go.FontFace = Theme.font.strong
		go.TextSize = 11
		go.Text = Theme.Caps("показать на карте")
		go.ZIndex = head.ZIndex + 1
		go.Parent = head
		Theme.Button(go, "quiet")
		go.MouseButton1Click:Connect(function()
			ctx.onShowOnMap(key)
		end)
	end

	text(scroll, 40, ReferenceTexts.elements[element.name] or "Описания в вики пока нет.", TEXT, Theme.color.text)
end

-- ---------- жук ----------

-- Показания жука: что написано в его строке таблицы. Порядок — от того, что видно
-- в бою сразу (здоровье, скорость), к тому, что нужно для расчёта.
local ENEMY_READINGS = {
	{ field = "hp", label = "здоровье" },
	{ field = "speed", label = "скорость" },
	{ field = "armor", label = "броня" },
	{ field = "shield", label = "щит" },
	{ field = "matter", label = "материя за убийство" },
}

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
	local caste = EntityInfo.CASTE_NAME[enemy.caste] or "прочие"

	if not ctx.met(key) then
		title(scroll, 10, "???", Theme.color.textMute, ("каста: %s"):format(caste))
		text(scroll, 30, "Этот жук ещё не убит. Описание откроется после первого убийства.")
		return
	end

	title(scroll, 10, enemy.name, enemy.color and Theme.Legible(enemy.color) or Theme.color.text,
		("каста: %s"):format(caste))

	for index, spec in ENEMY_READINGS do
		local value = enemy[spec.field]
		if type(value) == "number" and value ~= 0 then
			reading(scroll, 20 + index, spec.label, EntityInfo.Number(value))
		end
	end

	local traits = EntityInfo.EnemyTraits(enemy, 99)
	if #traits > 0 then
		reading(scroll, 30, "особенности", Theme.Caps(table.concat(traits, " · ")), Theme.color.danger)
	end

	rule(scroll, 40)
	local wiki = ReferenceTexts.enemies[enemy.name]
	text(scroll, 50, wiki and wiki.text or "Описания в вики пока нет.", TEXT, Theme.color.text)
	if wiki and wiki.lesson then
		text(scroll, 60, ("<b>%s</b>  %s"):format(Theme.Caps("урок:"), wiki.lesson), TEXT, Theme.color.accent)
	end

	enemyView(scroll, 70, enemy)
end

return Detail
