-- Вкладка «Справочник»: граф рецептов — рисование, кривые, перемещение и масштаб карты
-- Вынесено из CraftingUI.client.luau без изменений кода (задача #240): файл был слишком
-- велик, чтобы агент читал его целиком. deps — локальные основного файла, которые нужны
-- этому куску; возвращается то, что основной файл использует дальше.
-- Сам разрезан дальше тем же способом: кривые — ReferenceWire, рисование карты — ReferenceDraw,
-- список под картой и выбор — ReferenceList, сборка и движение карты — ReferenceInput, разделы,
-- поиск и события сервера — ReferenceSections. Вызываются в прежнем порядке кода.
return function(deps)
	local Theme = deps.Theme
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
	local root = deps.root

	local Detail = require(script.Parent:WaitForChild("ReferenceDetail"))
	local EntityInfo = require(script.Parent:WaitForChild("EntityInfo"))
	local Pages = require(script.Parent:WaitForChild("ReferencePages"))
	local Mastery = require(game:GetService("ReplicatedStorage"):WaitForChild("Mastery"))
	local Show = require(script.Parent:WaitForChild("ProducerShow"))
	local UISound = require(script.Parent:WaitForChild("UISound"))
	local ReferenceFrame = require(script.Parent:WaitForChild("ReferenceFrame"))

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
	local LINE_GROUND = Theme.color.ink
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

	-- Три раздела справочника — жуки, карта рецептов, элементы — переключаются пунктами
	-- внизу, как режимы производителя (просьба автора). Окно своё, как у производителя
	-- (ReferenceFrame, #269). Карта — прежнее содержимое вкладки, на своей странице
	-- mapFrame; «Жуки» и «Элементы» собирает ReferencePages.
	local MODES = {
		{ id = "enemies", name = "Жуки" },
		{ id = "map", name = "Карта" },
		{ id = "elements", name = "Элементы" },
	}
	local window = ReferenceFrame.Build(root, gui, MODES)
	local bookFrame = window.bookFrame
	tabFrames["Справочник"] = bookFrame
	local PAGE_SIZE = UDim2.new(1, 0, 1, 0)

	local mapFrame = Instance.new("Frame")
	mapFrame.Name = "MapPage"
	mapFrame.Size = PAGE_SIZE
	mapFrame.BackgroundTransparency = 1
	mapFrame.Parent = window.screen

	-- Карта и список лежат на стеклянных плашках (#271): фон окна под ними размыт, и
	-- звёзды не путаются со связями. Плашки создаются раньше содержимого: из равных по
	-- ZIndex позже рисуется тот, кто позже в дереве.
	local function plate(name)
		local f = Instance.new("Frame")
		f.Name = name
		f.BorderSizePixel = 0
		f.ZIndex = 1
		f.Parent = mapFrame
		window.glass(f)
		return f
	end
	local mapPlate = plate("MapPlate")
	local listPlate = plate("ListPlate")

	-- Рамка кривых карты — поверх плашки и под самой картой: из равных по ZIndex
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

	-- Общее для модулей карты (ReferenceWire, ReferenceDraw, ReferenceList, ReferenceInput,
	-- ReferenceSections): то, что меняется после сборки (раскладка, масштаб, выбор), и функции,
	-- которые зовутся раньше, чем определены. Местной переменной модуль получил бы только
	-- значение на момент вызова, а не нынешнее.
	local ref = {}
	ref.graph = nil
	ref.zoom = 1
	-- Подробность узлов зависит от масштаба, поэтому applyZoom её дёргает (ref.applyLod), а
	-- определена она в ReferenceDraw, вместе с остальным рисованием.

	local function applyZoom()
		if not ref.graph then
			return
		end
		graphScale.Scale = ref.zoom
		if ref.applyLod then
			ref.applyLod()
		end
		local w = math.ceil(ref.graph.width * ref.zoom)
		local h = math.ceil(ref.graph.height * ref.zoom)
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
		if not ref.graph or math.abs(value - ref.zoom) < 0.001 then
			return
		end
		-- Держим ту же точку графа в середине окна: иначе с каждым щелчком масштаба картинка
		-- уезжает к левому верхнему углу, и приближать приходится вслепую.
		local view = graphScroll.AbsoluteSize
		local centre = (graphScroll.CanvasPosition + view / 2 - canvasPad()) / ref.zoom
		ref.zoom = value
		applyZoom()
		local want = centre * ref.zoom + canvasPad() - view / 2
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
		if not ref.graph then
			return
		end
		local view = graphScroll.AbsoluteSize
		if view.X < 50 or view.Y < 50 then
			return
		end

		spin.aim = nil
		local focusX, focusY
		if whole then
			ref.zoom = math.clamp(math.min(view.X / ref.graph.width, view.Y / ref.graph.height), ZOOM_MIN, 1)
			focusX, focusY = ref.graph.width / 2, ref.graph.height / 2
		else
			ref.zoom = HOME_ZOOM
			focusX, focusY = ref.graph.centre[1], ref.graph.centre[2]
		end

		applyZoom()
		local want = Vector2.new(focusX, focusY) * ref.zoom + canvasPad() - view / 2
		graphScroll.CanvasPosition = Vector2.new(math.max(0, want.X), math.max(0, want.Y))
	end

	local openedLabel = Instance.new("TextLabel")
	openedLabel.Size = UDim2.new(1, 0, 0, 18)
	openedLabel.Position = UDim2.new(0, 0, GRAPH_SHARE, 6)
	openedLabel.BackgroundTransparency = 1
	openedLabel.FontFace = Theme.font.strong
	openedLabel.TextSize = Theme.MIN_TEXT
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
		Show.Press(btn)
		btn.MouseButton1Click:Connect(action)
		return btn
	end

	zoomButton("−", ZOOM_BTN * 2 + 14, function()
		setZoom(ref.zoom - ZOOM_STEP)
	end)
	zoomButton("+", ZOOM_BTN + 8, function()
		setZoom(ref.zoom + ZOOM_STEP)
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
	hintBar.TextSize = Theme.MIN_TEXT
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

	-- Список рецептов под картой убирается (просьба автора): вся высота вкладки
	-- уходит карте. Кнопка стоит в том же углу, что и возврат из цепочки, — обе про то,
	-- что сейчас показано, а не про саму карту.
	local listButton = Instance.new("TextButton")
	listButton.Size = UDim2.new(0, 96, 0, MobileUI.isMobile and MobileUI.MIN_TAP or 22)
	listButton.Position = UDim2.new(0, 2, 0, 2)
	listButton.FontFace = Theme.font.strong
	listButton.TextSize = Theme.MIN_TEXT
	listButton.Text = "СПИСОК ▲"
	listButton.ZIndex = 6
	listButton.Parent = mapFrame

	chromeButton(listButton, "quiet")
	Show.Press(listButton)

	-- Кнопки карты собраны в один угол — справа, рядом с масштабом. Слева от них теперь
	-- нет ничего, кроме самой карты, и одинокая кнопка под вкладками читалась как третий
	-- этаж шапки. На телефоне кнопка списка остаётся слева: три кнопки масштаба шириной
	-- в палец и так занимают там весь правый угол. Кнопки «Все рецепты» больше нет (#272):
	-- из цепочки выходят нажатием на пустое место карты.
	if not MobileUI.isMobile then
		local zoomRow = ZOOM_BTN * 3 + 20
		listButton.AnchorPoint = Vector2.new(1, 0)
		listButton.Position = UDim2.new(1, -(zoomRow + 8), 0, 2)
	end

	local listShown = false -- по умолчанию вся вкладка — карте (#272)

	-- Пустая полоса между шапкой и картой. Раньше холст выводился вверх на всю высоту
	-- шапки, и узлы, проходя под вкладками, торчали из-под них краями (замечание
	-- автора со скриншотом). Чёрной ленты из #114 это не возвращает: в полосе видна
	-- та же решётка окна, что и под самой картой, а место заняты кнопками карты:
	-- высота считается от них, чтобы они умещались целиком и на телефоне.
	local GRAPH_TOP = ZOOM_BTN + 8

	-- Карточка выбранного элемента — слева на карте, на стеклянной плашке: что он делает,
	-- сколько его есть, во что идёт. Слева, потому что наведение ставит выбранный элемент
	-- справа от середины карты (spin), и карточка его не закрывает.
	-- Стекло — на обычной плашке, а прокрутка внутри неё: у ScrollingFrame доли размера
	-- детей считаются от холста, и слой пятен стекла растянулся бы по всей карточке (#269).
	local cardPlate = Instance.new("Frame")
	cardPlate.Name = "CardPlate"
	cardPlate.BorderSizePixel = 0
	cardPlate.ZIndex = 7
	cardPlate.Visible = false
	cardPlate.Parent = mapFrame
	window.glass(cardPlate)
	-- Ширина — доля карты с потолком: при сборке окна размер карты ещё нулевой, и число
	-- в пикселях, посчитанное от него, так бы и осталось нулём.
	local cardLimit = Instance.new("UISizeConstraint")
	cardLimit.MaxSize = Vector2.new(MobileUI.isMobile and 250 or 330, math.huge)
	cardLimit.Parent = cardPlate

	local mapCard = Instance.new("ScrollingFrame")
	mapCard.Name = "Card"
	mapCard.Size = UDim2.new(1, 0, 1, 0)
	mapCard.BackgroundTransparency = 1
	mapCard.BorderSizePixel = 0
	mapCard.ScrollBarThickness = 4
	mapCard.AutomaticCanvasSize = Enum.AutomaticSize.Y
	mapCard.CanvasSize = UDim2.new(0, 0, 0, 0)
	mapCard.ZIndex = 7
	mapCard.Parent = cardPlate
	Theme.Scroller(mapCard)
	Theme.DragScroll(mapCard)

	local function applyBookLayout()
		local share = listShown and GRAPH_SHARE or 1
		graphScroll.Position = UDim2.new(0, 0, 0, GRAPH_TOP)
		graphScroll.Size = UDim2.new(1, 0, share, -GRAPH_TOP)
		mapPlate.Position = graphScroll.Position
		mapPlate.Size = graphScroll.Size
		wire.view.Position = graphScroll.Position
		wire.view.Size = graphScroll.Size
		hintBar.Position = UDim2.new(0, 4, share, -4)
		-- Список — на своей плашке под картой, содержимое с отступом от её краёв.
		local inset = 10
		listPlate.Visible = listShown
		listPlate.Position = UDim2.new(0, 0, share, 6)
		listPlate.Size = UDim2.new(1, 0, 1 - share, -6)
		openedLabel.Position = UDim2.new(0, inset, share, 6 + inset)
		openedLabel.Size = UDim2.new(1, -2 * inset, 0, 18)
		listScroll.Position = UDim2.new(0, inset, share, 6 + inset + 22)
		listScroll.Size = UDim2.new(1, -2 * inset, 1 - share, -(6 + 2 * inset + 22))
		openedLabel.Visible = listShown
		listScroll.Visible = listShown
		-- Стрелка — куда поедет список: вверх выехать, вниз уйти.
		listButton.Text = listShown and "СПИСОК ▼" or "СПИСОК ▲"
		cardPlate.Position = UDim2.new(0, 6, 0, GRAPH_TOP + 6)
		cardPlate.Size = UDim2.new(0.45, 0, share, -(GRAPH_TOP + 40))
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
	ref.selected = nil -- элемент, чья цепочка создания подсвечена
	ref.chainNodes, ref.chainEdges = {}, {}
	-- Насколько уехал палец с момента нажатия: на карте, которую тянут рукой, каждая
	-- протяжка заканчивается отпусканием над каким-нибудь узлом — иначе он бы выбирался.
	ref.panMoved = 0

	-- Кого игрок уже убивал — из профиля (ProfileSynced, четвёртый аргумент). Первое
	-- убийство нового жука сервер досылает сразу (Plutonium.AwardEnemyKill).
	local killed = {}
	-- Промокод CODEX (PromoCode) открывает справочник целиком — всех жуков и все ступени
	-- карточек (Mastery) — до выхода из игры.
	ref.codexRevealed = false
	local function isMet(key)
		return ref.codexRevealed or killed[key] == true or (ref.enemyKills[key] or 0) > 0
	end

	-- Орбиты карты открываются поэтапно (#273, #274): пока видны ярусы до OPEN_DEPTH
	-- включительно, дальних колец и их элементов на карте нет вовсе.
	-- Условия открытия следующих орбит ещё не придуманы; CODEX открывает всё. Ярус — глубина по рецептам (RecipeGraph.depth),
	-- до сборки карты — ярус из Elements.
	local OPEN_DEPTH = 1
	local function orbitShown(depth)
		return ref.codexRevealed or depth <= OPEN_DEPTH
	end
	local function orbitOpen(key)
		local depth = ref.graph and ref.graph.depth[key] or (Elements[key] and Elements[key].tier) or 0
		return orbitShown(depth)
	end

	-- Счёт убийств для ступеней карточек (Mastery): приходит событием ProfileStats.
	ref.elementKills, ref.enemyKills = {}, {}
	local function killsByElement(key)
		if ref.codexRevealed then
			return math.huge
		end
		return ref.elementKills[key] or 0
	end
	local function killsOfEnemy(key)
		if ref.codexRevealed then
			return math.huge
		end
		return math.max(ref.enemyKills[key] or 0, killed[key] and 1 or 0)
	end

	-- Открыт ли элемент: базовые — всегда (их покупают, а не открывают), остальные — по рецепту.
	local function isKnown(key)
		return Elements[key] ~= nil and (Elements[key].tier == 0 or knownRecipes[key] == true)
	end

	-- Нарисован ли элемент на карте: его орбита открыта. Неоткрытые элементы открытых
	-- орбит стоят «???», как и раньше (#275).
	-- drawnCount — сколько их нарисовано при последней сборке (-1 — ещё не собрана).
	ref.drawnCount = -1
	local function onMap(key)
		return orbitOpen(key)
	end

	local function countOf(key)
		return inventory[key] or 0
	end

	-- Можно ли скрафтить прямо сейчас: рецепт открыт и оба ингредиента в инвентаре
	-- (для пары из двух одинаковых — два штуки, как проверяет сервер в Crafting).
	-- Неоткрытый рецепт не подсвечивается: подсветка выдала бы пару.
	local function isCraftable(key)
		local recipe = ref.graph and ref.graph.producedBy[key] or EntityInfo.RecipeOf(key)
		if not recipe or knownRecipes[key] ~= true then
			return false
		end
		if recipe.a == recipe.b then
			return countOf(recipe.a) >= 2
		end
		return countOf(recipe.a) >= 1 and countOf(recipe.b) >= 1
	end

	-- Совпадения поиска на карте: пока строка не пуста, горят только они.
	ref.searchHits = nil

	local function hintFor(key)
		local recipe = ref.graph.producedBy[key]
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

	require(script.Parent:WaitForChild("ReferenceWire"))({
		Theme = Theme,
		Graph = Graph,
		LINE_GROUND = LINE_GROUND,
		wire = wire,
		spin = spin,
		graphLayer = graphLayer,
		ref = ref,
		orbitShown = orbitShown,
	})

	local drawExports = require(script.Parent:WaitForChild("ReferenceDraw"))({
		Theme = Theme,
		Elements = Elements,
		knownRecipes = knownRecipes,
		TweenService = TweenService,
		UISound = UISound,
		ZOOM_MIN = ZOOM_MIN,
		ZOOM_MAX = ZOOM_MAX,
		LINE_GROUND = LINE_GROUND,
		wire = wire,
		spin = spin,
		graphScroll = graphScroll,
		graphLayer = graphLayer,
		ref = ref,
		canvasPad = canvasPad,
		hintBar = hintBar,
		nodeGui = nodeGui,
		edgeGui = edgeGui,
		edgesOf = edgesOf,
		onMap = onMap,
		isCraftable = isCraftable,
		hintFor = hintFor,
	})
	local chainOf = drawExports.chainOf
	local drawGraph = drawExports.drawGraph

	local listExports = require(script.Parent:WaitForChild("ReferenceList"))({
		Theme = Theme,
		Elements = Elements,
		knownRecipes = knownRecipes,
		Recipes = Recipes,
		Detail = Detail,
		UISound = UISound,
		ref = ref,
		openedLabel = openedLabel,
		listScroll = listScroll,
		cardPlate = cardPlate,
		mapCard = mapCard,
		nodeGui = nodeGui,
		orbitOpen = orbitOpen,
		killsByElement = killsByElement,
		isKnown = isKnown,
		onMap = onMap,
		countOf = countOf,
		isCraftable = isCraftable,
		chainOf = chainOf,
	})
	local refreshBook = listExports.refreshBook

	require(script.Parent:WaitForChild("ReferenceInput"))({
		Graph = Graph,
		TweenService = TweenService,
		gui = gui,
		UserInputService = UserInputService,
		RunService = RunService,
		ZOOM_STEP = ZOOM_STEP,
		wire = wire,
		spin = spin,
		bookFrame = bookFrame,
		mapFrame = mapFrame,
		graphScroll = graphScroll,
		graphLayer = graphLayer,
		ref = ref,
		applyZoom = applyZoom,
		canvasPad = canvasPad,
		setZoom = setZoom,
		fitZoom = fitZoom,
		cardPlate = cardPlate,
		drawGraph = drawGraph,
	})

	local sectionsExports = require(script.Parent:WaitForChild("ReferenceSections"))({
		Theme = Theme,
		Elements = Elements,
		gui = gui,
		Remotes = Remotes,
		Detail = Detail,
		Pages = Pages,
		Mastery = Mastery,
		Show = Show,
		UISound = UISound,
		MODES = MODES,
		window = window,
		bookFrame = bookFrame,
		PAGE_SIZE = PAGE_SIZE,
		mapFrame = mapFrame,
		ref = ref,
		nodeGui = nodeGui,
		killed = killed,
		isMet = isMet,
		orbitOpen = orbitOpen,
		killsByElement = killsByElement,
		killsOfEnemy = killsOfEnemy,
		isKnown = isKnown,
		onMap = onMap,
		countOf = countOf,
		isCraftable = isCraftable,
		drawGraph = drawGraph,
		refreshBook = refreshBook,
	})
	local refreshKnowledge = sectionsExports.refreshKnowledge

	return {
		-- inventory CraftingUI заменяет целиком на каждое InventoryChanged — новая таблица
		-- приходит сюда, и всё, что считает «можно скрафтить», перерисовывается.
		setInventory = function(value)
			inventory = value
			refreshKnowledge()
		end,
		-- graph собирается позже (Graph.Build при первом показе) — отдаётся функцией, а не значением.
		getGraph = function()
			return ref.graph
		end,
		drawGraph = drawGraph,
		applyBookLayout = applyBookLayout,
		refreshBook = refreshBook,
	}
end
