-- Экран производителя: режимы «Купить», «Рулетка», «Апгрейдер» (buildProducer)
-- Вынесено из CraftingUI.client.luau без изменений кода (задача #240): файл был слишком
-- велик, чтобы агент читал его целиком. deps — локальные основного файла, которые нужны
-- этому куску; возвращается то, что основной файл использует дальше.
return function(deps)
	local ReplicatedStorage = deps.ReplicatedStorage
	local Remotes = deps.Remotes
	local inventory = deps.inventory
	local Theme = deps.Theme
	local Elements = deps.Elements
	local TextService = deps.TextService
	local buyFrame = deps.buyFrame
	local gui = deps.gui
	local BASE_ORDER = deps.BASE_ORDER
	local RequestBuyElement = deps.RequestBuyElement
	local Settings = deps.Settings
	local MobileUI = deps.MobileUI
	local GuiService = deps.GuiService
	local InventoryChanged = deps.InventoryChanged

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

		-- Подложка — жидкое стекло (просьба автора, #226), общее со справочником (MonitorGlass).
		local glass = require(script.Parent:WaitForChild("MonitorGlass")).Mount(mon)
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

			-- Выбранный режим — вывороткой плашки. Скобка «>» убрана: занимала место (просьба автора).
			for _, m in MODES do
				local on = m.id == st.mode
				Theme.Button(modeButtons[m.id], on and "active" or "ghost")
				modeButtons[m.id].Text = Theme.Caps(m.name)
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

	return {
		-- inventory основной файл заменяет целиком на каждое InventoryChanged (не правит
		-- на месте: производитель сравнивает прежнюю таблицу с новой). Сюда новая
		-- приходит через этот сеттер — ровно в тот же миг, что и раньше.
		setInventory = function(value)
			inventory = value
		end,
	}
end
