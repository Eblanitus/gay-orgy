-- Вкладка «Справочник»: граф рецептов — рисование, кривые, перемещение и масштаб карты
-- Вынесено из CraftingUI.client.luau без изменений кода (задача #240): файл был слишком
-- велик, чтобы агент читал его целиком. deps — локальные основного файла, которые нужны
-- этому куску; возвращается то, что основной файл использует дальше.
return function(deps)
	local Theme = deps.Theme
	local body = deps.body
	local tabFrames = deps.tabFrames
	local MobileUI = deps.MobileUI
	local chromeButton = deps.chromeButton
	local Elements = deps.Elements
	local knownRecipes = deps.knownRecipes
	local Graph = deps.Graph
	local TweenService = deps.TweenService
	local Recipes = deps.Recipes
	local gui = deps.gui
	local UserInputService = deps.UserInputService
	local RunService = deps.RunService
	local inventory = deps.inventory
	local Remotes = deps.Remotes
	local statusLabel = deps.statusLabel

	local Detail = require(script.Parent:WaitForChild("ReferenceDetail"))
	local EntityInfo = require(script.Parent:WaitForChild("EntityInfo"))
	local Pages = require(script.Parent:WaitForChild("ReferencePages"))

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

	-- Три раздела справочника — жуки, карта рецептов, элементы — переключаются пунктами
	-- внизу, как режимы производителя (просьба автора). Карта — прежнее содержимое вкладки,
	-- теперь на своей странице mapFrame; «Жуки» и «Элементы» собирает ReferencePages.
	local FOOT_H = MobileUI.isMobile and MobileUI.MIN_TAP or 30
	local PAGE_SIZE = UDim2.new(1, 0, 1, -(FOOT_H + 8))

	local mapFrame = Instance.new("Frame")
	mapFrame.Name = "MapPage"
	mapFrame.Size = PAGE_SIZE
	mapFrame.BackgroundTransparency = 1
	mapFrame.Parent = bookFrame

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
	graphShade.Parent = mapFrame
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
	wire.view.Parent = mapFrame

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
	graphScroll.Parent = mapFrame

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
	openedLabel.Parent = mapFrame

	local listScroll = Instance.new("ScrollingFrame")
	listScroll.Size = UDim2.new(1, 0, 1 - GRAPH_SHARE, -28)
	listScroll.Position = UDim2.new(0, 0, GRAPH_SHARE, 28)
	listScroll.BackgroundTransparency = 1
	listScroll.BorderSizePixel = 0
	listScroll.ScrollBarThickness = 6
	listScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	listScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	listScroll.Parent = mapFrame

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
		btn.Parent = mapFrame
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
	hintBar.Parent = mapFrame

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
	backButton.Parent = mapFrame

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
	listButton.Parent = mapFrame

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

	-- Карточка выбранного элемента — слева на карте, на стеклянной плашке: что он делает,
	-- сколько его есть, во что идёт. Слева, потому что наведение ставит выбранный элемент
	-- справа от середины карты (spin), и карточка его не закрывает.
	local mapCard = Instance.new("ScrollingFrame")
	mapCard.Name = "Card"
	mapCard.BackgroundColor3 = Theme.color.panel
	mapCard.BackgroundTransparency = 0.12
	mapCard.BorderSizePixel = 0
	mapCard.ScrollBarThickness = 4
	mapCard.AutomaticCanvasSize = Enum.AutomaticSize.Y
	mapCard.CanvasSize = UDim2.new(0, 0, 0, 0)
	mapCard.ZIndex = 7
	mapCard.Visible = false
	mapCard.Parent = mapFrame
	Theme.Corner(mapCard, Theme.radius.control)
	Theme.Hairline(mapCard, 0.5)
	Theme.Scroller(mapCard)
	Theme.DragScroll(mapCard)
	-- Ширина — доля карты с потолком: при сборке окна размер карты ещё нулевой, и число
	-- в пикселях, посчитанное от него, так бы и осталось нулём.
	local cardLimit = Instance.new("UISizeConstraint")
	cardLimit.MaxSize = Vector2.new(MobileUI.isMobile and 250 or 330, math.huge)
	cardLimit.Parent = mapCard

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
		mapCard.Position = UDim2.new(0, 6, 0, GRAPH_TOP + 6)
		mapCard.Size = UDim2.new(0.45, 0, share, -(GRAPH_TOP + 40))
	end

	listButton.MouseButton1Click:Connect(function()
		listShown = not listShown
		applyBookLayout()
	end)

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

	-- Открыт ли элемент: базовые — всегда (их покупают, а не открывают), остальные — по рецепту.
	local function isKnown(key)
		return Elements[key] ~= nil and (Elements[key].tier == 0 or knownRecipes[key] == true)
	end

	local function countOf(key)
		return inventory[key] or 0
	end

	-- Можно ли скрафтить прямо сейчас: рецепт открыт и оба ингредиента в инвентаре
	-- (для пары из двух одинаковых — два штуки, как проверяет сервер в Crafting).
	-- Неоткрытый рецепт не подсвечивается: подсветка выдала бы пару.
	local function isCraftable(key)
		local recipe = graph and graph.producedBy[key] or EntityInfo.RecipeOf(key)
		if not recipe or knownRecipes[key] ~= true then
			return false
		end
		if recipe.a == recipe.b then
			return countOf(recipe.a) >= 2
		end
		return countOf(recipe.a) >= 1 and countOf(recipe.b) >= 1
	end

	-- Совпадения поиска на карте: пока строка не пуста, горят только они.
	local searchHits = nil

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
			craftDot = craftDot,
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
			if searchHits then
				return searchHits, {}
			end
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
			-- То, что можно скрафтить прямо сейчас, — наверх списка: за этим к справочнику
			-- и подходят посреди забега. Остальное — в прежнем порядке.
			for index, entry in steps do
				entry.order = index
			end
			table.sort(steps, function(one, two)
				local a, b = isCraftable(one.key), isCraftable(two.key)
				if a ~= b then
					return a
				end
				return one.order < two.order
			end)
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
				and ((isCraftable(entry.key) and "● " or "") .. Theme.Caps(("%s + %s = %s"):format(
					Elements[entry.recipe.a].name, Elements[entry.recipe.b].name, Elements[entry.key].name
				)))
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
			local ready = 0
			for _, entry in steps do
				if isCraftable(entry.key) then
					ready += 1
				end
			end
			Theme.Section(openedLabel, "рецепты", ready > 0
				and ("%d из %d · ● можно скрафтить: %d"):format(opened, #Recipes.List, ready)
				or ("%d из %d"):format(opened, #Recipes.List))
		end

		-- Карточка выбранного элемента на карте.
		mapCard.Visible = selected ~= nil
		if selected then
			Detail.Element(mapCard, selected, {
				known = isKnown,
				count = countOf,
				craftable = isCraftable,
				onPick = function(key)
					selectNode(key)
					focusOn(key)
				end,
			})
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

	-- Карта на экране — только когда открыт справочник и выбран раздел «Карта».
	local function mapShown()
		return gui.Enabled and bookFrame.Visible and mapFrame.Visible
	end

	local function onMapShown()
		if bookFrame.Visible and mapFrame.Visible then
			ensureGraph()
		end
	end
	bookFrame:GetPropertyChangedSignal("Visible"):Connect(onMapShown)
	mapFrame:GetPropertyChangedSignal("Visible"):Connect(onMapShown)

	graphScroll:GetPropertyChangedSignal("AbsoluteSize"):Connect(applyZoom)

	-- ---------- как двигают граф ----------
	-- Нажатие ловится через UserInputService, а не на самом холсте: узлы лежат поверх него
	-- и забирали бы нажатие себе (та же причина, что у Theme.DragScroll).

	local panning = false
	local panLast = Vector2.new(0, 0)

	local function inside(gui2d, position)
		local at = gui2d.AbsolutePosition
		local size = gui2d.AbsoluteSize
		return position.X >= at.X and position.X <= at.X + size.X
			and position.Y >= at.Y and position.Y <= at.Y + size.Y
	end

	local function overGraph(position)
		if not mapShown() then
			return false
		end
		-- Карточка лежит поверх карты: протяжка и колесо над ней — её собственная прокрутка.
		if mapCard.Visible and inside(mapCard, position) then
			return false
		end
		return inside(graphScroll, position)
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
		if not (mapShown() and graph) then
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

	-- ---------- разделы справочника и поиск ----------

	local pagesFrame = Instance.new("Frame")
	pagesFrame.Name = "Pages"
	pagesFrame.Size = PAGE_SIZE
	pagesFrame.BackgroundTransparency = 1
	pagesFrame.Parent = bookFrame

	-- Кого игрок уже убивал — из профиля (ProfileSynced, четвёртый аргумент). Первое
	-- убийство нового жука сервер досылает сразу (Plutonium.AwardEnemyKill).
	local killed = {}
	local function isMet(key)
		return killed[key] == true
	end

	local pages
	local mode = "map"
	local setMode

	pages = Pages.Mount(pagesFrame, {
		known = isKnown,
		count = countOf,
		craftable = isCraftable,
		met = isMet,
		showOnMap = function(key)
			setMode("map")
			task.defer(function()
				ensureGraph()
				if selected ~= key then
					selectNode(key)
				end
				focusOn(key)
			end)
		end,
	})

	local MODES = {
		{ id = "enemies", name = "Жуки", frame = pages.enemies.frame,
			status = "нажмите жука — покажу, как он себя ведёт; неубитые скрыты" },
		{ id = "map", name = "Карта", frame = mapFrame,
			status = "● — можно скрафтить сейчас; нажмите элемент — покажу его цепочку; «+», «−», «[]» — масштаб" },
		{ id = "elements", name = "Элементы", frame = pages.elements.frame,
			status = "нажмите элемент — покажу, что он делает и во что идёт" },
	}

	local modeBar = Instance.new("Frame")
	modeBar.Name = "Modes"
	modeBar.AnchorPoint = Vector2.new(0, 1)
	modeBar.Position = UDim2.new(0, 0, 1, 0)
	modeBar.Size = UDim2.new(1, 0, 0, FOOT_H)
	modeBar.BackgroundTransparency = 1
	modeBar.Parent = bookFrame

	local MODE_W = MobileUI.isMobile and 104 or 150
	local modeButtons = {}
	for index, m in MODES do
		local b = Instance.new("TextButton")
		b.Name = "Mode_" .. m.id
		b.Size = UDim2.new(0, MODE_W, 1, 0)
		b.Position = UDim2.new(0, (index - 1) * (MODE_W + 8), 0, 0)
		b.FontFace = Theme.font.strong
		b.TextSize = MobileUI.isMobile and 12 or 14
		b.TextXAlignment = Enum.TextXAlignment.Left
		b.Parent = modeBar
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 10)
		pad.Parent = b
		modeButtons[m.id] = b
		b.MouseButton1Click:Connect(function()
			setMode(m.id)
		end)
	end

	-- Поиск по имени — справа от разделов. Ищет только среди открытого: неоткрытое
	-- по имени и так не найти, а подсказка «такой есть» была бы подсказкой рецепта.
	local searchBox = Instance.new("TextBox")
	searchBox.Name = "Search"
	searchBox.AnchorPoint = Vector2.new(1, 0)
	searchBox.Position = UDim2.new(1, 0, 0, 0)
	searchBox.Size = UDim2.new(0, MobileUI.isMobile and 150 or 260, 1, 0)
	searchBox.ClearTextOnFocus = false
	searchBox.PlaceholderText = "поиск…"
	searchBox.Text = ""
	searchBox.FontFace = Theme.font.body
	searchBox.TextSize = MobileUI.isMobile and 13 or 14
	searchBox.TextXAlignment = Enum.TextXAlignment.Left
	searchBox.Parent = modeBar
	Theme.Field(searchBox)
	local searchPad = Instance.new("UIPadding")
	searchPad.PaddingLeft = UDim.new(0, 10)
	searchPad.PaddingRight = UDim.new(0, 10)
	searchPad.Parent = searchBox

	-- Первое совпадение на карте — по порядку карты, чтобы Enter вёл всегда к одному и тому же.
	local function mapSearch(text)
		local query = Detail.Lower(text)
		if query == "" or not graph then
			searchHits = nil
			return nil
		end
		searchHits = {}
		local first
		for _, key in graph.keys do
			if isKnown(key) and string.find(Detail.Lower(Elements[key].name), query, 1, true) then
				searchHits[key] = true
				first = first or key
			end
		end
		return first
	end

	local function applySearch()
		local text = searchBox.Text
		if mode == "map" then
			mapSearch(text)
			if graph then
				repaint()
			end
			return
		end
		local p = mode == "elements" and pages.elements or pages.enemies
		p.filter(text)
	end

	searchBox:GetPropertyChangedSignal("Text"):Connect(applySearch)
	searchBox.FocusLost:Connect(function(enter)
		if not enter or searchBox.Text == "" then
			return
		end
		if mode == "map" then
			local first = mapSearch(searchBox.Text)
			if first then
				if selected ~= first then
					selectNode(first)
				end
				focusOn(first)
			end
		else
			local p = mode == "elements" and pages.elements or pages.enemies
			local first = p.filter(searchBox.Text)
			if first then
				p.show(first)
			end
		end
	end)

	local function modeStatus()
		for _, m in MODES do
			if m.id == mode then
				return m.status
			end
		end
		return ""
	end

	function setMode(id)
		mode = id
		for _, m in MODES do
			local on = m.id == id
			m.frame.Visible = on
			chromeButton(modeButtons[m.id], on and "active" or "ghost")
			modeButtons[m.id].Text = (on and "> " or "  ") .. Theme.Caps(m.name)
		end
		pagesFrame.Visible = id ~= "map"
		applySearch()
		if bookFrame.Visible then
			Theme.Status(statusLabel, "Справочник", modeStatus())
		end
	end

	-- Строку статуса вкладке ставит CraftingUI.selectTab — общей для всего раздела.
	-- Справочник уточняет её под свой раздел, после (defer), чтобы его строка осталась.
	bookFrame:GetPropertyChangedSignal("Visible"):Connect(function()
		if bookFrame.Visible then
			task.defer(function()
				if bookFrame.Visible then
					Theme.Status(statusLabel, "Справочник", modeStatus())
				end
			end)
		end
	end)

	setMode("map")

	-- Всё, что зависит от инвентаря и открытого, перерисовывается одним вызовом.
	local function refreshKnowledge()
		if graph then
			repaint()
		end
		refreshBook()
		pages.elements.refresh()
		pages.enemies.refresh()
	end

	-- Обработчики CraftingUI обновляют knownRecipes раньше или позже этого — порядок
	-- подписчиков не закреплён, поэтому перерисовка отложена до конца кадра событий.
	Remotes:WaitForChild("RecipeLearned").OnClientEvent:Connect(function()
		task.defer(refreshKnowledge)
	end)
	Remotes:WaitForChild("ProfileSynced").OnClientEvent:Connect(function(_plutonium, _levels, _recipes, killedTypes)
		if type(killedTypes) == "table" then
			table.clear(killed)
			for key, value in killedTypes do
				killed[key] = value == true
			end
			task.defer(function()
				pages.enemies.refresh()
			end)
		end
	end)

	return {
		-- inventory CraftingUI заменяет целиком на каждое InventoryChanged — новая таблица
		-- приходит сюда, и всё, что считает «можно скрафтить», перерисовывается.
		setInventory = function(value)
			inventory = value
			refreshKnowledge()
		end,
		-- graph собирается позже (Graph.Build при первом показе) — отдаётся функцией, а не значением.
		getGraph = function()
			return graph
		end,
		drawGraph = drawGraph,
		applyBookLayout = applyBookLayout,
		refreshBook = refreshBook,
	}
end
