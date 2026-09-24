-- Карточка справочника: всё, что игра знает об одном элементе или жуке.
--
-- Одна сборка на три места: карточка выбранного узла на карте рецептов и правая половина
-- вкладок «Элементы» и «Жуки». Две копии разошлись бы при первой же правке — то же правило,
-- что у EntityInfo.
--
-- Слова берутся из вики (WikiTexts, собирается tools/wiki_texts.py), числа и свойства — из
-- таблиц игры (Elements, Enemies, EntityInfo). Своих описаний здесь нет: фраза от себя
-- разошлась бы с тем, что делает код, при первой правке баланса.
--
-- Неоткрытое не называется: у элемента без открытого рецепта нет ни имени, ни описания,
-- ни списка «идёт в» — иначе справочник выдал бы рецепт, который надо открыть самому
-- (решение автора: «учи крафты»). Жук, которого ещё ни разу не убили, — так же.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(script.Parent:WaitForChild("UITheme"))
local EntityInfo = require(script.Parent:WaitForChild("EntityInfo"))
local MobileUI = require(script.Parent:WaitForChild("MobileUI"))

local Elements = require(ReplicatedStorage:WaitForChild("Elements"))
local Enemies = require(ReplicatedStorage:WaitForChild("Enemies"))
local Recipes = require(ReplicatedStorage:WaitForChild("Recipes"))
local WikiTexts = require(ReplicatedStorage:WaitForChild("WikiTexts"))

local Detail = {}

local mobile = MobileUI.isMobile
local TEXT = mobile and 13 or 14
local SMALL = mobile and 11 or 12

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
	label.Parent = scroll
	return label
end

local function caption(scroll, order, value)
	local label = text(scroll, order, Theme.Caps(value), SMALL, Theme.color.textMute, Theme.font.strong)
	label.TextWrapped = false
	return label
end

local function title(scroll, order, value, color, mark)
	local label = text(scroll, order, Theme.Caps(value), mobile and 20 or 24, color, Theme.font.strong)
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
	button.Parent = scroll
	Theme.ElementFill(button, Elements[key].color, { wide = true, element = key })

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.FontFace = Theme.font.body
	label.TextSize = SMALL + 1
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Text = value
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

-- ctx: known(key) — открыт ли элемент, count(key) — сколько в инвентаре (nil — вне забега),
-- craftable(key) — можно ли скрафтить сейчас, onPick(key) — переход к другому элементу.
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

	title(scroll, 10, element.name, Theme.Legible(element.color),
		recipe and ("тир %d"):format(element.tier) or ("тир %d · базовый"):format(element.tier))

	if recipe then
		reading(scroll, 30, "рецепт", Theme.Caps(("%s + %s"):format(Elements[recipe.a].name, Elements[recipe.b].name)))
	else
		reading(scroll, 30, "где взять", Theme.Caps("производитель, за материю"))
	end

	local have = ctx.count and ctx.count(key)
	if have then
		reading(scroll, 40, "в инвентаре", tostring(have), have > 0 and Theme.color.text or Theme.color.textMute)
	end
	if recipe and ctx.craftable and ctx.craftable(key) then
		text(scroll, 50, Theme.Caps("● можно скрафтить сейчас — ингредиенты есть"), SMALL, Theme.color.action,
			Theme.font.strong)
	end

	local traits = EntityInfo.ElementTraits(element, 99)
	if #traits > 0 then
		reading(scroll, 60, "свойства", Theme.Caps(table.concat(traits, " · ")), Theme.color.accent)
	end

	rule(scroll, 70)
	text(scroll, 80, WikiTexts.elements[element.name] or "Описания в вики пока нет.", TEXT, Theme.color.text)

	-- Во что идёт дальше. Неоткрытые рецепты не называются даже вторым ингредиентом:
	-- «Огонь + ??? = ???» уже подсказка. Остаётся только их число.
	local uses = Detail.UsedIn(key)
	if #uses > 0 then
		rule(scroll, 90)
		caption(scroll, 100, "идёт в")
		local hidden = 0
		for index, use in uses do
			if ctx.known(use.result) then
				link(scroll, 100 + index, use.result, Theme.Caps(("%s = %s + %s"):format(
					Elements[use.result].name, Elements[use.a].name, Elements[use.b].name
				)), ctx)
			else
				hidden += 1
			end
		end
		if hidden > 0 then
			text(scroll, 100 + #uses + 1, Theme.Caps(("и ещё %d %s"):format(hidden,
				hidden == 1 and "неоткрытый рецепт" or (hidden < 5 and "неоткрытых рецепта" or "неоткрытых рецептов")
			)), SMALL, Theme.color.textMute)
		end
	end
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
	local wiki = WikiTexts.enemies[enemy.name]
	text(scroll, 50, wiki and wiki.text or "Описания в вики пока нет.", TEXT, Theme.color.text)
	if wiki and wiki.lesson then
		text(scroll, 60, ("<b>%s</b>  %s"):format(Theme.Caps("урок:"), wiki.lesson), TEXT, Theme.color.accent)
	end
end

return Detail
