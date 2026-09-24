-- Вкладки справочника «Элементы» и «Жуки»: сетка слева, карточка выбранного справа.
--
-- Раньше эти списки жили в журнале главного меню. Журнал теперь — только статистика
-- (решение автора), а подробное описание — здесь, у доски-справочника в лаборатории:
-- туда игрок идёт, когда хочет что-то узнать посреди забега.
--
-- Карточку собирает ReferenceDetail — та же, что у выбранного узла на карте рецептов.
-- На узком экране (телефон в портрете) двум колонкам места нет: карточка открывается
-- поверх сетки и закрывается кнопкой «К списку».
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(script.Parent:WaitForChild("UITheme"))
local MobileUI = require(script.Parent:WaitForChild("MobileUI"))
local Detail = require(script.Parent:WaitForChild("ReferenceDetail"))

local Elements = require(ReplicatedStorage:WaitForChild("Elements"))
local Enemies = require(ReplicatedStorage:WaitForChild("Enemies"))

local Pages = {}

local mobile = MobileUI.isMobile
local CELL_H = mobile and 56 or 50
local CELL_W = mobile and 220 or 250
-- Уже этого две колонки не помещаются: карточка уходит поверх сетки.
local TWO_COLUMNS = 640
local GAP = 12
local BACK_H = mobile and MobileUI.MIN_TAP or 26

-- Элементы — по тирам, внутри тира по алфавиту; жуки — по кастам. Порядок pairs в Luau
-- не закреплён, без сортировки сетка перетасовывалась бы при каждом входе.
local elementOrder = {}
for key in Elements do
	table.insert(elementOrder, key)
end
table.sort(elementOrder, function(a, b)
	local ea, eb = Elements[a], Elements[b]
	if ea.tier ~= eb.tier then
		return ea.tier < eb.tier
	end
	return ea.name < eb.name
end)

local enemyOrder = {}
for key, entry in Enemies do
	if type(entry) == "table" and entry.name then
		table.insert(enemyOrder, key)
	end
end
table.sort(enemyOrder, function(a, b)
	local ea, eb = Enemies[a], Enemies[b]
	local ca, cb = ea.caste or 99, eb.caste or 99
	if ca ~= cb then
		return ca < cb
	end
	return ea.name < eb.name
end)

local function label(parent, size, color, font, align)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.FontFace = font or Theme.font.body
	l.TextSize = size
	l.TextColor3 = color
	l.TextXAlignment = align or Enum.TextXAlignment.Left
	l.TextTruncate = Enum.TextTruncate.AtEnd
	l.Text = ""
	l.Parent = parent
	return l
end

local function scroller(parent, name)
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = name
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 4
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.Parent = parent
	Theme.Scroller(scroll)
	Theme.DragScroll(scroll)
	return scroll
end

-- Одна страница: spec говорит, чем её наполнить.
--   order         — ключи по порядку
--   known(key)    — открыт ли (неоткрытое — «???» и приглушено)
--   paint(key)    — цвет ячейки и ключ узора (или nil)
--   name(key)     — имя в ячейке и для поиска
--   show(scroll, key) — собрать карточку
local function page(parent, name, spec)
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.Size = UDim2.new(1, 0, 1, 0)
	frame.BackgroundTransparency = 1
	frame.Visible = false
	frame.Parent = parent

	local list = scroller(frame, "List")
	local grid = Theme.Grid(list, CELL_H, CELL_W, 8)

	-- Карточка — на стеклянной плашке, как карточка узла на карте рецептов.
	local card = Instance.new("Frame")
	card.Name = "Card"
	card.BackgroundColor3 = Theme.color.panel
	card.BackgroundTransparency = 0.15
	card.ZIndex = 4
	card.Parent = frame
	Theme.Corner(card, Theme.radius.control)
	Theme.Hairline(card, 0.5)

	local detail = scroller(card, "Detail")
	detail.ZIndex = 4

	local back = Instance.new("TextButton")
	back.Name = "Back"
	back.Size = UDim2.new(0, 120, 0, BACK_H)
	back.Position = UDim2.new(0, 8, 0, 8)
	back.FontFace = Theme.font.strong
	back.TextSize = 11
	back.Text = Theme.Caps("< к списку")
	back.ZIndex = 5
	back.Parent = card
	Theme.Button(back, "quiet")

	local empty = label(card, 13, Theme.color.textMute)
	empty.Size = UDim2.new(1, -24, 0, 40)
	empty.Position = UDim2.new(0, 12, 0, 12)
	empty.TextWrapped = true
	empty.TextTruncate = Enum.TextTruncate.None
	empty.TextYAlignment = Enum.TextYAlignment.Top
	empty.Text = spec.hint
	empty.ZIndex = 4

	local cells = {}
	local selected = nil
	local query = ""
	local narrow = false

	local function layout()
		local width = frame.AbsoluteSize.X
		narrow = width < TWO_COLUMNS
		if narrow then
			list.Position = UDim2.new(0, 0, 0, 0)
			list.Size = UDim2.new(1, 0, 1, 0)
			card.Position = UDim2.new(0, 0, 0, 0)
			card.Size = UDim2.new(1, 0, 1, 0)
			card.Visible = selected ~= nil
			back.Visible = true
			detail.Position = UDim2.new(0, 0, 0, BACK_H + 12)
			detail.Size = UDim2.new(1, 0, 1, -(BACK_H + 12))
		else
			local listW = math.floor((width - GAP) * 0.56)
			list.Position = UDim2.new(0, 0, 0, 0)
			list.Size = UDim2.new(0, listW, 1, 0)
			card.Position = UDim2.new(0, listW + GAP, 0, 0)
			card.Size = UDim2.new(1, -(listW + GAP), 1, 0)
			card.Visible = true
			back.Visible = false
			detail.Position = UDim2.new(0, 0, 0, 0)
			detail.Size = UDim2.new(1, 0, 1, 0)
		end
		empty.Visible = selected == nil
		detail.Visible = selected ~= nil
		Theme.GridFit(grid)
	end

	local function paintCell(key)
		local parts = cells[key]
		local known = spec.known(key)
		local color, pattern = spec.paint(key)
		Theme.ElementFill(parts.cell, color, { dim = not known, element = known and pattern or nil })
		Theme.Inner(parts.inner)
		parts.name.Text = Theme.Caps(known and spec.name(key) or "???")
		parts.name.TextColor3 = known and Theme.color.text or Theme.color.textDim
		parts.pick.Enabled = key == selected
	end

	local function visible(key)
		if query == "" then
			return true
		end
		return spec.known(key) and string.find(Detail.Lower(spec.name(key)), query, 1, true) ~= nil
	end

	local function show(key)
		local was = selected
		selected = key
		if was and cells[was] then
			cells[was].pick.Enabled = false
		end
		if key and cells[key] then
			cells[key].pick.Enabled = true
			spec.show(detail, key)
		end
		layout()
	end

	-- Ячейки собираются при первом показе страницы, а не при входе в игру: это сотня
	-- ячеек с узорами ради экрана, до которого игрок доходит не сразу (тот же приём,
	-- что у карты рецептов). Скрытая страница не перекрашивается на каждое
	-- изменение инвентаря — только помечается, и перекрашивается при показе.
	local built = false
	local dirty = false

	local function build()
		for index, key in spec.order do
			local cell = Instance.new("TextButton")
			cell.LayoutOrder = index
			cell.Text = ""
			cell.AutoButtonColor = false
			cell.Parent = list

			local inner = Instance.new("Frame")
			inner.Name = "Inner"
			inner.Parent = cell

			local nameLabel = label(inner, mobile and 14 or 14, Theme.color.text, Theme.font.strong)
			nameLabel.Size = UDim2.new(1, 0, 1, 0)

			-- Выбранная ячейка — рамкой, а не цветом: цвет у ячейки — опознание элемента.
			-- Рамка на своей прозрачной плашке поверх ячейки: у самой ячейки свой кант
			-- (Theme.ElementFill), и второй UIStroke на ней не рисуется.
			local pickFrame = Instance.new("Frame")
			pickFrame.Name = "Pick"
			pickFrame.Size = UDim2.new(1, 0, 1, 0)
			pickFrame.BackgroundTransparency = 1
			pickFrame.ZIndex = 3
			pickFrame.Parent = cell
			Theme.Corner(pickFrame, Theme.radius.control)
			local pick = Instance.new("UIStroke")
			pick.Color = Theme.color.accent
			pick.Thickness = 2
			pick.Enabled = false
			pick.Parent = pickFrame

			cells[key] = { cell = cell, inner = inner, name = nameLabel, pick = pick }
			paintCell(key)

			cell.MouseButton1Click:Connect(function()
				if Theme.WasDragged(list) then
					return
				end
				show(key)
			end)
		end
	end

	local function refresh()
		if not built then
			return
		end
		if not frame.Visible then
			dirty = true
			return
		end
		dirty = false
		for key in cells do
			paintCell(key)
		end
		if selected then
			spec.show(detail, selected)
		end
	end

	local function applyFilter()
		local first
		for _, key in spec.order do
			local on = visible(key)
			if cells[key] then
				cells[key].cell.Visible = on
			end
			if on and not first and query ~= "" then
				first = key
			end
		end
		return first
	end

	back.MouseButton1Click:Connect(function()
		show(nil)
	end)

	frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
	frame:GetPropertyChangedSignal("Visible"):Connect(function()
		if not frame.Visible then
			return
		end
		if not built then
			built = true
			build()
			applyFilter()
		elseif dirty then
			refresh()
		end
		task.defer(layout)
	end)
	layout()

	return {
		frame = frame,
		refresh = refresh,
		filter = function(text)
			query = Detail.Lower(text)
			return applyFilter()
		end,
		show = show,
	}
end

-- ctx: known, count, craftable, met — как у ReferenceDetail; showOnMap(key) — перейти
-- к элементу на карте рецептов.
function Pages.Mount(parent, ctx)
	local elements
	local elementCtx = {
		known = ctx.known,
		count = ctx.count,
		craftable = ctx.craftable,
		onPick = function(key)
			elements.show(key)
		end,
		-- Открытый элемент можно найти и на карте: оттуда видна вся его ветка.
		onShowOnMap = ctx.showOnMap,
	}

	elements = page(parent, "ElementsPage", {
		order = elementOrder,
		hint = "Выберите элемент — здесь появится, что он делает, из чего собран и во что идёт дальше.",
		known = ctx.known,
		name = function(key)
			return Elements[key].name
		end,
		paint = function(key)
			return Elements[key].color, key
		end,
		show = function(scroll, key)
			Detail.Element(scroll, key, elementCtx)
		end,
	})

	local enemies = page(parent, "EnemiesPage", {
		order = enemyOrder,
		hint = "Выберите жука — здесь появится, как он себя ведёт и чем опасен.",
		known = ctx.met,
		name = function(key)
			return Enemies[key].name
		end,
		paint = function(key)
			return Enemies[key].color or Theme.color.steel, nil
		end,
		show = function(scroll, key)
			Detail.Enemy(scroll, key, { met = ctx.met })
		end,
	})

	return {
		elements = elements,
		enemies = enemies,
	}
end

return Pages
