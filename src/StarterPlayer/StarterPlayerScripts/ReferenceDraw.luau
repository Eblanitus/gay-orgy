-- Рисование карты справочника: узлы, связи, подсветка цепочки, поворот, подробность по масштабу, наведение.
-- Вынесено из CraftingReference.luau (поведение то же): файл был слишком велик, чтобы
-- агент читал его целиком. deps — локальные CraftingReference и модулей до этого; ref — общее
-- изменяемое (см. CraftingReference). Возвращается то, что нужно дальше.
return function(deps)
	local Theme = deps.Theme
	local Elements = deps.Elements
	local knownRecipes = deps.knownRecipes
	local TweenService = deps.TweenService
	local UISound = deps.UISound
	local ZOOM_MIN = deps.ZOOM_MIN
	local ZOOM_MAX = deps.ZOOM_MAX
	local LINE_GROUND = deps.LINE_GROUND
	local wire = deps.wire
	local spin = deps.spin
	local graphScroll = deps.graphScroll
	local graphLayer = deps.graphLayer
	local ref = deps.ref
	local canvasPad = deps.canvasPad
	local hintBar = deps.hintBar
	local nodeGui = deps.nodeGui
	local edgeGui = deps.edgeGui
	local edgesOf = deps.edgesOf
	local onMap = deps.onMap
	local isCraftable = deps.isCraftable
	local hintFor = deps.hintFor

	local hovered = nil

	-- Неизвестная связь заметно светлее решётки сцены: при равной яркости ствол
	-- неоткрытой ветки терялся на обзоре среди прямых линий сетки окна (#130).
	local LINE_UNKNOWN = Theme.color.panel:Lerp(Theme.color.steel, 0.24)
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
	local SIDE_TEXT, SIDE_GAP = Theme.MIN_TEXT, 4

	-- Постороннее не прячется совсем, а гаснет: карта должна остаться на месте, иначе
	-- по одной висящей в пустоте цепочке не понять, откуда в дереве она растёт.
	local FADE_LINE = 0.78 -- на столько цвет погасшей связи уходит в фон
	local FADE_NODE = 0.6
	local HOT = Theme.color.accent -- выбранная цепочка
	local WARM = Theme.color.steel -- связи узла под курсором

	local LIFT = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	-- Доля глубины связи (0 — от самих стихий, 1 — последнее кольцо) на диапазон [near, far].
	-- Глубина берётся у ребёнка: связь всегда идёт из более раннего яруса в более поздний,
	-- поэтому именно он определяет, на каком кольце линия заканчивается. Определена здесь,
	-- а не выше вместе с wire: там ещё нет локальной graph (объявлена ниже по файлу), и
	-- функция бы считала её глобальной — всегда nil (баг #131).
	local function wireThick(edge, near, far)
		local maxDepth = math.max(#ref.graph.guides, 1)
		local d = ref.graph.depth[edge.child] or maxDepth
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
		if ref.zoom < LOD_GLYPH then
			return 1 -- только светящиеся точки
		elseif ref.zoom < LOD_NAME then
			return 2 -- плашка с одной буквой
		elseif ref.zoom < LOD_DETAIL then
			return 3 -- имя
		end
		return 4 -- имя и рецепт под узлом
	end

	local function nodeSize(ui, lifted)
		local w, h = ui.w, ui.h
		if lodTier() == 1 then
			w = (ui.base and DOT_BASE or DOT) / ref.zoom
			h = w
		end
		if lifted then
			w, h = w + 8, h + 4
		end
		return UDim2.new(0, w, 0, h)
	end

	local function drawNode(key)
		local place = ref.graph.nodes[key]
		local data = Elements[key]
		-- Базовые открыты всегда: рецепта, который надо открыть, у них нет — их покупают.
		local known = (ref.graph.producedBy[key] == nil) or knownRecipes[key] == true

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
		nameLabel.TextSize = Theme.MIN_TEXT -- ширину узла под этот кегль считает RecipeGraph (CHAR_W)
		-- Ширину узла раскладка считала по числу букв в моноширинном шрифте, поэтому имя
		-- влезает целиком; обрезка оставлена на случай, если шрифт когда-нибудь сменят.
		nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
		nameLabel.ZIndex = 2
		local caption = known and Theme.Caps(data.name) or "???"
		nameLabel.Text = caption
		nameLabel.Parent = node

		-- Метка «можно скрафтить сейчас» — яркая точка в углу узла (repaint решает, видна ли).
		local craftDot = Instance.new("Frame")
		craftDot.Name = "Craftable"
		craftDot.AnchorPoint = Vector2.new(0.5, 0.5)
		craftDot.Position = UDim2.new(1, -2, 0, 2)
		craftDot.Size = UDim2.new(0, 8, 0, 8)
		craftDot.BackgroundColor3 = Theme.color.action
		craftDot.BorderSizePixel = 0
		craftDot.ZIndex = 4
		craftDot.Visible = false
		craftDot.Parent = node
		Theme.Corner(craftDot, 999)

		-- Строка рецепта под узлом — самая подробная ступень. Лежит не внутри узла,
		-- а рядом: в коробку в двадцать два пикселя вторая строка не влезает. Место под неё
		-- раскладка оставляет на орбите (RecipeGraph, DETAIL_H), а тёмная подложка по ширине
		-- текста не даёт ей читаться поверх линии, идущей в соседнем просвете.
		local recipe = ref.graph.producedBy[key]
		local detailText
		if recipe and known then
			detailText = Theme.Caps(("%s + %s"):format(Elements[recipe.a].name, Elements[recipe.b].name))
		end

		local detail = Instance.new("TextLabel")
		detail.AnchorPoint = Vector2.new(0.5, 0)
		detail.Position = UDim2.new(0, place.x, 0, place.y + place.h / 2 + 4)
		detail.AutomaticSize = Enum.AutomaticSize.X
		detail.Size = UDim2.new(0, 0, 0, 18)
		detail.BackgroundColor3 = Theme.color.panel
		detail.BackgroundTransparency = 0.15
		detail.BorderSizePixel = 0
		detail.FontFace = Theme.font.body
		detail.TextSize = Theme.MIN_TEXT
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
			craftDot = craftDot,
			side = side,
			stroke = stroke,
			known = known,
			base = ref.graph.producedBy[key] == nil,
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
			ref.repaint()
		end)

		node.MouseLeave:Connect(function()
			if hovered == key then
				hovered = nil
				hintBar.Visible = false
			end
			TweenService:Create(node, LIFT, { Size = nodeSize(nodeGui[key], false) }):Play()
			ref.repaint()
		end)

		node.MouseButton1Click:Connect(function()
			if ref.panMoved > 6 then
				return -- это была протяжка карты, а не выбор
			end
			UISound.Play("Click")
			ref.selectNode(key)
			-- Повторное нажатие снимает выбор: наводиться тогда не на что, и карта снова крутится.
			if ref.selected == key then
				ref.focusOn(key)
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
		if not (ref.selected or hovered) then
			if ref.searchHits then
				return ref.searchHits, {}
			end
			return nil, nil
		end

		local nodes, edges = {}, {}
		for key in ref.chainNodes do
			nodes[key] = true
		end
		for record in ref.chainEdges do
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

	function ref.repaint()
		local nodes, edges = litSets()

		for _, record in edgeGui do
			local lit, state = nil, "rest"
			if edges then
				if edges[record] then
					-- Цепочка — бирюзой, связи узла под курсором — сталью: одним цветом
					-- они бы слились, а наводить мышь приходится как раз поверх выбранной цепочки.
					lit = ref.chainEdges[record] and HOT or WARM
					state = ref.chainEdges[record] and "hot" or "warm"
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
			if key == ref.selected then
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
			-- «Можно скрафтить» — ореол цвета действия вокруг узла на любом масштабе
			-- и точка в углу, когда узел крупнее точки.
			local craftable = isCraftable(key)
			if craftable and state ~= "dim" then
				ui.glow.BackgroundColor3 = Theme.color.action
				ui.glow.BackgroundTransparency = dots and 0.35 or 0.7
			else
				ui.glow.BackgroundColor3 = tint
				ui.glow.BackgroundTransparency = halo
			end
			ui.craftDot.Visible = craftable and not dots
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
		if not ref.graph then
			return
		end
		if spin.layer then
			spin.layer.Rotation = math.deg(spin.angle)
		end
		local ox, oy = ref.graph.centre[1], ref.graph.centre[2]
		local c, s = math.cos(spin.angle), math.sin(spin.angle)
		for key, ui in nodeGui do
			local place = ref.graph.nodes[key]
			local dx, dy = place.x - ox, place.y - oy
			local x, y = ox + dx * c - dy * s, oy + dx * s + dy * c
			local at = UDim2.new(0, x, 0, y)
			ui.frame.Position = at
			ui.glow.Position = at
			ui.detail.Position = UDim2.new(0, x, 0, y + place.h / 2 + 4)
			if ui.side then
				local length = math.sqrt(dx * dx + dy * dy)
				local dir = length > 0 and Vector2.new(x - ox, y - oy) / length or Vector2.new(1, 0)
				local gap = ui.frame.Size.X.Offset / 2 + SIDE_GAP / ref.zoom
				ui.side.AnchorPoint = Vector2.new(0.5 - dir.X / 2, 0.5 - dir.Y / 2)
				ui.side.Position = UDim2.new(0, x + dir.X * gap, 0, y + dir.Y * gap)
			end
		end
	end

	-- Чем ближе карта, тем больше подробностей: точки → буква → имя → имя с рецептом.
	-- Зовётся из applyZoom, то есть на каждое изменение масштаба (при наведении — на каждом
	-- кадре движения), а не просто каждый кадр.
	function ref.applyLod()
		local tier = lodTier()
		local ring = (tier == 1) and 16 or 18
		for key, ui in nodeGui do
			local size = nodeSize(ui, hovered == key)
			ui.frame.Size = size
			ui.label.Visible = tier >= 2
			ui.label.Text = (tier == 2) and ui.glyph or ui.caption
			ui.detail.Visible = tier >= 4 and ui.detailText ~= nil
			if tier == 1 and ui.base then
				ui.glow.Size = UDim2.new(0, HALO / ref.zoom, 0, HALO / ref.zoom)
			else
				ui.glow.Size = UDim2.new(0, size.X.Offset + ring, 0, size.Y.Offset + ring)
			end
			if ui.side then
				ui.side.Visible = tier == 1
				ui.side.TextSize = math.min(SIDE_TEXT / ref.zoom, 100)
			end
		end
		-- Узлы — на места под нынешний поворот, заодно с отступом подписей стихий:
		-- он зависит от размера точки, а тот только что сменился.
		spin.place()
		ref.repaint()
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
			if ref.panMoved <= 6 then
				ref.selectNode(nil)
			end
		end)

		-- Звенья — в своём слое: поворот карты — это Rotation слоя вокруг его середины,
		-- поэтому середина слоя стоит ровно в середине ромба.
		local lines = Instance.new("Frame")
		lines.Name = "Lines"
		lines.BackgroundTransparency = 1
		lines.Size = UDim2.new(0, ref.graph.centre[1] * 2, 0, ref.graph.centre[2] * 2)
		lines.Rotation = math.deg(spin.angle)
		lines.ZIndex = 1
		lines.Parent = graphLayer
		spin.layer = lines

		-- Кольца ярусов — первыми, под связями, кривыми, как и связи.
		wire.rings()
		for _, key in ref.graph.keys do
			edgesOf[key] = {}
		end
		for _, edge in ref.graph.edges do
			if onMap(edge.child) and onMap(edge.parent) then
				drawEdge(edge)
			end
		end
		ref.drawnCount = 0
		for _, key in ref.graph.keys do
			if onMap(key) then
				drawNode(key)
				ref.drawnCount += 1
			end
		end

		-- Связи нарисованы заново, и прежние записи о них — уже мусор: цепочку пересчитываем.
		if ref.selected then
			ref.chainNodes, ref.chainEdges = chainOf(ref.selected)
		end
		-- Не repaint, а applyLod: узлы только что собраны в полную величину, а масштаб к этому
		-- моменту уже выставлен — подробность надо привести в соответствие сразу.
		-- Он же ставит узлы под нынешний поворот: собраны они на неповёрнутых местах.
		ref.applyLod()
	end

	-- Наведение на элемент: карта поворачивается так, чтобы он встал справа от середины
	-- ромба, а вид едет к нему и приближается (spin.AIM_ZOOM). Само движение — в RenderStepped,
	-- одним счётом на кадр, а не твинами: поворот уносит элемент, и вид догоняет его каждый кадр.
	-- Плавно, а не прыжком: на карте в две тысячи пикселей мгновенный перенос вида читается
	-- как «страница подменилась», и найти прежнее место потом невозможно.
	function ref.focusOn(key)
		local place = ref.graph and ref.graph.nodes[key]
		if not place then
			return
		end
		local view = graphScroll.AbsoluteSize
		local angle = math.atan2(place.y - ref.graph.centre[2], place.x - ref.graph.centre[1])
		spin.aim = {
			key = key,
			t = 0,
			look = (graphScroll.CanvasPosition + view / 2 - canvasPad()) / ref.zoom, -- точка под серединой окна
			from = spin.angle,
			turn = (-angle - spin.angle + math.pi) % (math.pi * 2) - math.pi, -- кратчайший путь до «направо»
			zoom = ref.zoom,
			toZoom = math.clamp(math.max(ref.zoom, spin.AIM_ZOOM), ZOOM_MIN, ZOOM_MAX),
		}
	end

	return {
		chainOf = chainOf,
		drawGraph = drawGraph,
	}
end
