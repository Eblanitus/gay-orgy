-- Страница «Крафт» алхимического стола (#282–#284, #290–#294).
-- Верх — верстак на стеклянной плашке: «пусто + пусто» между поршнями пресса (TablePress) и рычаг
-- с иконкой колбы (TableLever); под слотами строка инструментов: обмен, сброс, случайная
-- проба, сортировка и крафт пачкой. Ниже — инвентарь: имя и запас.
--
-- Положенный в слот элемент — одна штука из запаса (#292): ячейка показывает на одну меньше,
-- последняя штука прячет ячейку. Это только показ: сервер списывает при крафте сам.
-- Результата заранее не видно. Рычаг запускает пресс, бьёт он сам (#294): элементы раздавлены, слоты
-- пусты, ушёл запрос. Ответ — поршни расходятся, в середине лежит результат; его надо
-- забрать щелчком, и он летит в свою ячейку. Неудача — осколки, а элементы возвращаются в
-- инвентарь: сервер при неудаче ничего не списывает (Crafting.Craft).
-- T — общее состояние стола (CraftingCraftTab), page — рамка страницы.
return function(T, page)
	local Theme, Elements, MobileUI, Show, UISound = T.Theme, T.Elements, T.MobileUI, T.Show, T.UISound
	local UserInputService = game:GetService("UserInputService")
	local Lever = require(script.Parent:WaitForChild("TableLever"))
	local Press = require(script.Parent:WaitForChild("TablePress"))
	local mobile = MobileUI.isMobile

	local function make(className, name, parent, z)
		local inst = Instance.new(className)
		inst.Name = name
		inst.BorderSizePixel = 0
		inst.BackgroundTransparency = 1
		inst.ZIndex = z or 1
		inst.Parent = parent
		return inst
	end

	local function place(inst, x, y, w, h)
		inst.Position = UDim2.fromOffset(math.floor(x + 0.5), math.floor(y + 0.5))
		inst.Size = UDim2.fromOffset(math.max(0, math.floor(w + 0.5)), math.max(0, math.floor(h + 0.5)))
	end

	local function button(name, parent, text, kind)
		local b = make("TextButton", name, parent)
		b.FontFace = Theme.font.strong
		b.TextTruncate = Enum.TextTruncate.AtEnd
		b.Text = text
		Show.Press(b)
		Theme.Button(b, kind)
		return b
	end

	local SORTS = {
		{ id = "tier", name = "ярус" },
		{ id = "name", name = "имя" },
		{ id = "count", name = "запас" },
	}

	local slots = { nil, nil }
	local sortIndex = 1
	local query = ""
	local state = "empty" -- что лежит на столе: empty, known, unknown, failed
	local chain = nil -- открытый рецепт, на который не хватает: шаги цепочки, если она есть
	local pressed = nil -- { a, b }: раздавлены рычагом, ответа ещё нет
	local held = nil -- ключ результата под прессом: ещё не забран
	local frozen = false -- пресс идёт к удару: слоты ещё рисуют раздавливаемую пару
	local run = nil -- что сейчас крафтится: "single", "chain" или "batch"

	-- Стеклянные плашки — первыми детьми: из равных по ZIndex позже рисуется тот, кто позже в дереве.
	local benchPlate = make("Frame", "BenchPlate", page)
	T.glass(benchPlate)
	local invPlate = make("Frame", "InventoryPlate", page)
	T.glass(invPlate)

	local slotA = button("SlotA", page, "", "muted")
	local plusLabel = make("TextLabel", "Plus", page)
	local slotB = button("SlotB", page, "", "muted")
	-- Результат — не слот, а то, что лежит под прессом после крафта: виден, пока не забран.
	local resultSlot = make("TextButton", "Result", page)
	resultSlot.AutoButtonColor = false
	resultSlot.FontFace = Theme.font.strong
	resultSlot.Text = ""
	resultSlot.Visible = false
	local press = Press.Mount(page, { slotA = slotA, slotB = slotB, plus = plusLabel, result = resultSlot })
	local craftButton = button("Craft", page, "", "muted")
	craftButton.AutoButtonColor = false
	local craft -- объявлена ниже, рычаг зовёт её
	local lever

	-- Иконка вместо надписи «СКРЕСТИТЬ» (просьба автора, #290): круглая колба с узким
	-- горлом, налитая до половины. Нарисована кадрами, как лупа поиска; цвет — цвет текста
	-- кнопки (Theme.Button), то есть готова кнопка или нет.
	local flask = make("Frame", "Flask", craftButton, craftButton.ZIndex + 1)
	flask.AnchorPoint = Vector2.new(0.5, 0.5)
	flask.Position = UDim2.fromScale(0.5, 0.5)
	flask.Size = UDim2.fromScale(0.6, 0.6)
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectType = Enum.AspectType.FitWithinMaxSize
	aspect.Parent = flask
	local flaskParts = {}
	do
		local z = flask.ZIndex
		local body = make("Frame", "Body", flask, z)
		body.AnchorPoint = Vector2.new(0.5, 0.5)
		body.Position = UDim2.fromScale(0.5, 0.66)
		body.Size = UDim2.fromScale(0.66, 0.66)
		Theme.Corner(body, UDim.new(0.5, 0))
		local bodyStroke = Instance.new("UIStroke")
		bodyStroke.Thickness = 2
		bodyStroke.Parent = body
		table.insert(flaskParts, { bodyStroke, "Color" })

		-- Жидкость — нижняя половина круга поменьше, обрезанная рамкой.
		local clip = make("Frame", "Liquid", body, z)
		clip.Position = UDim2.fromScale(0, 0.52)
		clip.Size = UDim2.fromScale(1, 0.48)
		clip.ClipsDescendants = true
		local liquid = make("Frame", "Fill", clip, z)
		liquid.AnchorPoint = Vector2.new(0.5, 0.5)
		liquid.Position = UDim2.new(0.5, 0, 0, -1)
		liquid.Size = UDim2.fromScale(0.74, 0.74 / 0.48)
		liquid.BackgroundTransparency = 0.35
		Theme.Corner(liquid, UDim.new(0.5, 0))
		table.insert(flaskParts, { liquid, "BackgroundColor3" })

		-- Горло — две стенки от плеч колбы вверх и кромка поперёк.
		for _, x in { 0.38, 0.62 } do
			local wall = make("Frame", "Wall", flask, z)
			wall.AnchorPoint = Vector2.new(0.5, 0)
			wall.Position = UDim2.fromScale(x, 0.1)
			wall.Size = UDim2.new(0, 2, 0.28, 0)
			wall.BackgroundTransparency = 0
			table.insert(flaskParts, { wall, "BackgroundColor3" })
		end
		local rim = make("Frame", "Rim", flask, z)
		rim.AnchorPoint = Vector2.new(0.5, 0)
		rim.Position = UDim2.fromScale(0.5, 0.1)
		rim.Size = UDim2.new(0.36, 0, 0, 2)
		rim.BackgroundTransparency = 0
		table.insert(flaskParts, { rim, "BackgroundColor3" })
	end
	local function paintFlask()
		for _, part in flaskParts do
			part[1][part[2]] = craftButton.TextColor3
		end
		if lever then
			lever.paint(craftButton.TextColor3)
		end
	end
	-- Кнопка — жёлоб рычага: колба переезжает в ручку, дотянули до низа — крафт.
	-- Рычаг только запускает: пресс бьёт сам (#294).
	lever = Lever.Mount(craftButton, flask, function()
		craft()
	end)

	plusLabel.FontFace = Theme.font.strong
	plusLabel.TextColor3 = Theme.color.textDim
	plusLabel.Text = "+"
	for _, s in { slotA, slotB, resultSlot } do
		s.FontFace = Theme.font.strong
		s.TextWrapped = true
	end

	local swapButton = button("Swap", page, "ОБМЕН", "quiet")
	local clearButton = button("Clear", page, "СБРОС", "quiet")
	local randomButton = button("Random", page, "НАУГАД", "quiet")
	local fiveButton = button("Five", page, "×" .. T.TUNING.batchSize, "quiet")
	local maxButton = button("Max", page, "МАКС", "quiet")
	local sortButton = button("Sort", page, "", "quiet")

	local invList = make("ScrollingFrame", "Inventory", page)
	invList.ScrollBarThickness = 6
	invList.AutomaticCanvasSize = Enum.AutomaticSize.Y
	invList.CanvasSize = UDim2.new(0, 0, 0, 0)
	Theme.Scroller(invList)
	Theme.DragScroll(invList)

	local emptyLabel = make("TextLabel", "Empty", page)
	emptyLabel.FontFace = Theme.font.body
	emptyLabel.TextWrapped = true
	emptyLabel.TextColor3 = Theme.color.textMute
	emptyLabel.Visible = false

	-- ---------- раскладка ----------
	local function setCellTextSize(b, size)
		b.TextSize = size
		local caption = b:FindFirstChild("Caption")
		if caption then
			caption.TextSize = size
		end
	end

	local function layout()
		local W, H = page.AbsoluteSize.X, page.AbsoluteSize.Y
		if W < 60 or H < 60 then
			return
		end
		local compact = mobile or H < 420 or W < 760
		local function by(phone, pc)
			return compact and phone or pc
		end
		local pad = by(6, 12)
		local gap = by(6, 10)
		local slotH = compact and 56 or math.clamp(math.floor(H * 0.22), 84, 190)
		local toolH = by(30, 36)
		local craftW = compact and 112 or math.clamp(math.floor(W * 0.17), 170, 260)
		local signW = by(18, 34)

		-- Ряд слотов с поршнями по краям: слоты, «+» и поршни ставит сам пресс.
		local sy = pad
		local benchH = sy + slotH + gap + toolH + pad
		place(benchPlate, 0, 0, W, benchH)
		press.layout({ left = pad, right = W - pad - craftW - gap, y = sy, h = slotH, sign = signW })
		-- Рычаг — во всю высоту верстака, чтобы было куда тянуть.
		place(craftButton, W - pad - craftW, pad, craftW, slotH + gap + toolH)

		local big = slotH >= 110
		for _, s in { slotA, slotB, resultSlot } do
			setCellTextSize(s, big and 24 or by(14, 16))
		end
		plusLabel.TextSize = big and 32 or 22

		-- Строка инструментов: слева обмен, сброс, наугад, сортировка; справа пачка.
		-- Мелких подписей нет (просьба автора, #290): только кнопки.
		local ty = sy + slotH + gap
		local toolW = by(78, 120)
		local batchW = by(54, 80)
		for i, b in { swapButton, clearButton, randomButton } do
			place(b, pad + (i - 1) * (toolW + gap), ty, toolW, toolH)
		end
		local right = W - pad - craftW - gap
		local sortX = pad + (toolW + gap) * 3
		local sortW = math.max(0, math.min(by(110, 170), right - batchW * 2 - gap * 2 - sortX))
		place(sortButton, sortX, ty, sortW, toolH)
		place(maxButton, right - batchW, ty, batchW, toolH)
		place(fiveButton, right - batchW * 2 - gap, ty, batchW, toolH)
		for _, b in { swapButton, clearButton, randomButton, sortButton, fiveButton, maxButton } do
			b.TextSize = by(14, 16)
		end

		local ly = benchH + gap
		place(invPlate, 0, ly, W, H - ly)
		place(invList, pad, ly + pad, W - pad * 2, H - ly - pad * 2)
		place(emptyLabel, pad * 3, ly + pad * 3, W - pad * 6, 60)
		emptyLabel.TextSize = by(13, 15)
		local grid = invList:FindFirstChildOfClass("UIGridLayout")
		if grid then
			Theme.GridFit(grid)
		end
	end

	page:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)

	-- ---------- верстак ----------
	-- Сколько штук key лежит на столе: в слотах, под прессом и в результате. Это резерв:
	-- инвентарь показывает запас за его вычетом. Больше запаса резерв не бывает — слот без
	-- штуки (рецепт из «Рецептов», на который не хватает) только призрак цепочки.
	local function slotUses(key)
		return (slots[1] == key and 1 or 0) + (slots[2] == key and 1 or 0)
	end

	local function uses(key)
		local n = slotUses(key)
		-- Раздавленное держится, пока сервер его не списал: запас упал ниже снимка — уже списано.
		if pressed and T.count(key) >= (pressed.base[key] or 0) then
			n += (pressed[1] == key and 1 or 0) + (pressed[2] == key and 1 or 0)
		end
		return n + (held == key and 1 or 0)
	end

	-- Сколько штук key показывает инвентарь.
	local function avail(key)
		local have = T.count(key)
		return have - math.min(have, uses(key))
	end

	-- Стол занят: идёт крафт или под прессом лежит результат.
	local function locked()
		return T.busy() or pressed ~= nil or held ~= nil
	end

	local drawn = {} -- номер слота → что нарисовано: перерисовка только при перемене
	local function renderSlot(i)
		if frozen then
			return
		end
		local b = i == 1 and slotA or slotB
		local key = slots[i]
		local ghost = key ~= nil and T.count(key) < slotUses(key)
		local sig = tostring(key) .. (ghost and "~" or "")
		if drawn[i] == sig then
			return
		end
		drawn[i] = sig
		b.Text = key and Theme.Caps(Elements[key].name) or "ПУСТО"
		-- Цветная полоса смотрит в сторону «+» (решение автора, #105). Призрак — притушен.
		Theme.ElementButton(b, key and Elements[key].color or nil, { right = i == 1, element = key, dim = ghost })
	end

	local function refreshBench()
		local a, b = slots[1], slots[2]
		local result = nil
		if not (a and b) then
			state = "empty"
		else
			result = T.knownResult(a, b)
			state = result and "known" or T.isFailed(a, b) and "failed" or "unknown"
		end

		local n = (a and b) and T.times(a, b) or 0
		local busy = locked()
		chain = (state == "known" and n < 1) and T.plan(result) or nil

		-- Запас ушёл (его потратил другой игрок): штука без покрытия снимается со слота.
		-- Не трогаем во время крафта и когда на столе цель цепочки.
		if not busy and not chain then
			local changed = false
			for i = 2, 1, -1 do
				local key = slots[i]
				if key and T.count(key) < slotUses(key) then
					slots[i] = nil
					changed = true
				end
			end
			if changed then
				refreshBench()
				return
			end
		end
		renderSlot(1)
		renderSlot(2)

		local ready = ((state == "known" or state == "unknown") and n > 0 or chain ~= nil) and not busy
		Theme.Button(craftButton, ready and "action" or "muted")
		if state == "failed" then
			craftButton.TextColor3 = Theme.color.danger
		end
		paintFlask()

		local canBatch = state == "known" and n >= 2 and not busy
		fiveButton.Visible, maxButton.Visible = canBatch, canBatch
		Theme.Button(swapButton, (a or b) and not busy and "quiet" or "muted")
		Theme.Button(clearButton, (a or b) and not busy and "quiet" or "muted")
	end

	-- ---------- инвентарь ----------
	local cells = {} -- ключ → { btn, dim }

	-- Элемент, к которому подбираем пару: ровно один занятый слот.
	local function anchor()
		if slots[1] and not slots[2] then
			return slots[1]
		end
		if slots[2] and not slots[1] then
			return slots[2]
		end
		return nil
	end

	-- Ячейка — имя и запас тем же кеглем, без мелких подписей (#290). Пара с элементом
	-- в слоте уже не смешалась — ячейка притенена.
	local function cellText(key, partner)
		local data = Elements[key]
		local text = ('%s   <font color="%s">%d</font>'):format(
			Theme.Caps(data.name),
			Theme.Hex(Theme.Legible(data.color)),
			avail(key)
		)
		return text, partner ~= nil and T.isFailed(partner, key)
	end

	-- Подсказки и отметки — без пересборки сетки: щелчок по ячейке не должен её перерисовывать.
	local function refreshCells()
		local partner = anchor()
		for key, c in cells do
			local text, dim = cellText(key, partner)
			Theme.SetCellText(c.btn, text)
			c.dim.Visible = dim
			c.mark.Visible = slots[1] == key or slots[2] == key
		end
	end

	local function sortKeys(keys)
		local by = SORTS[sortIndex].id
		table.sort(keys, function(a, b)
			local ea, eb = Elements[a], Elements[b]
			if by == "count" and T.count(a) ~= T.count(b) then
				return T.count(a) > T.count(b)
			end
			if by ~= "name" and (ea.tier or 0) ~= (eb.tier or 0) then
				return (ea.tier or 0) < (eb.tier or 0)
			end
			return ea.name < eb.name
		end)
	end

	local assignToSlot

	-- Пока стол скрыт, сетка только помечается: запас меняется на каждую покупку любого игрока.
	local dirty = false

	local function rebuild()
		if not page.Visible then
			dirty = true
			return
		end
		dirty = false
		invList:ClearAllChildren()
		cells = {}
		local grid = Theme.Grid(invList, mobile and 48 or 40, 300, 6)

		local keys, total = {}, 0
		for key in T.inventory do
			if Elements[key] and avail(key) > 0 then
				total += 1
				if T.matches(key, query) then
					table.insert(keys, key)
				end
			end
		end
		sortKeys(keys)
		sortButton.Text = "↕ " .. Theme.Caps(SORTS[sortIndex].name)

		emptyLabel.Visible = #keys == 0
		emptyLabel.Text = total == 0 and "Класть в слоты пока нечего. Базовые элементы — у производителя."
			or "Ничего не нашлось."

		for i, key in keys do
			local data = Elements[key]
			local btn = make("TextButton", key, invList)
			btn.LayoutOrder = i
			btn.FontFace = Theme.font.strong
			btn.TextSize = mobile and 16 or 14
			btn.RichText = true
			btn.TextXAlignment = Enum.TextXAlignment.Left
			btn.Text = Theme.Caps(data.name)
			Theme.ElementButton(btn, data.color, { wide = true, element = key })

			-- Пара уже не смешалась — ячейку притеняет полупрозрачная шторка.
			local dim = make("Frame", "Dim", btn, btn.ZIndex + 3)
			dim.Size = UDim2.fromScale(1, 1)
			dim.BackgroundColor3 = Theme.color.ink
			dim.BackgroundTransparency = 0.45
			dim.Visible = false
			Theme.Corner(dim, Theme.radius.mark)

			local mark = make("TextLabel", "SlotMark", btn, btn.ZIndex + 4)
			mark.AnchorPoint = Vector2.new(1, 0)
			mark.Position = UDim2.new(1, -3, 0, 2)
			mark.Size = UDim2.fromOffset(16, 16)
			mark.FontFace = Theme.font.strong
			mark.TextSize = 14
			mark.TextColor3 = Theme.color.accent
			mark.Text = "✓"
			mark.Visible = false

			cells[key] = { btn = btn, dim = dim, mark = mark }
			btn.MouseButton1Click:Connect(function()
				if Theme.WasDragged(invList) then
					return
				end
				UISound.Play("Click")
				assignToSlot(key)
			end)
		end
		Theme.GridFit(grid)
		refreshCells()
	end

	local function refresh()
		-- Ответа так и не было (стол сбросил ожидание): раздавленное вернулось в запас,
		-- поршни расходятся.
		if pressed and not T.busy() then
			pressed = nil
			run = nil
			press.release()
		end
		refreshBench()
		rebuild()
	end

	-- ---------- действия ----------
	-- Ячейка появилась или пропала (последняя штука ушла в слот, вернулась) — сетка
	-- пересобирается; иначе хватит подписей.
	local function shownChanged(keys)
		for _, key in keys do
			if key and (avail(key) > 0 and T.matches(key, query)) ~= (cells[key] ~= nil) then
				return true
			end
		end
		return false
	end

	local function setSlots(a, b)
		local was = { slots[1] or false, slots[2] or false }
		slots[1], slots[2] = a, b
		refreshBench()
		if shownChanged({ was[1], was[2], a or false, b or false }) then
			rebuild()
		else
			refreshCells()
		end
	end

	-- Стол занят — щелчки по слотам и инвентарю не проходят. Лежит результат — он
	-- подпрыгивает: «сначала забери».
	local function refuse()
		if held then
			Show.Pop(resultSlot, 0.12, 0.3)
		end
	end

	-- Пустой слот заполняется первым. Оба заняты — меняется второй (прежний возвращается
	-- в запас): первый остаётся «якорем», и перебирать ему пары можно одними щелчками.
	-- Со стола в слот уходит ровно одна штука.
	function assignToSlot(key)
		if locked() then
			refuse()
			return
		end
		local target = slots[1] == nil and 1 or 2
		if slots[target] ~= key and avail(key) < 1 then
			return
		end
		if target == 1 then
			setSlots(key, slots[2])
		else
			setSlots(slots[1], key)
		end
		Show.Pop(target == 1 and slotA or slotB, 0.08, 0.22)
	end

	-- Щелчок по слоту — штука возвращается в инвентарь.
	slotA.MouseButton1Click:Connect(function()
		if locked() then
			refuse()
			return
		end
		setSlots(nil, slots[2])
	end)
	slotB.MouseButton1Click:Connect(function()
		if locked() then
			refuse()
			return
		end
		setSlots(slots[1], nil)
	end)

	swapButton.MouseButton1Click:Connect(function()
		if (slots[1] or slots[2]) and not locked() then
			setSlots(slots[2], slots[1])
			Show.Pop(slotA, 0.08, 0.22)
			Show.Pop(slotB, 0.08, 0.22)
		end
	end)

	clearButton.MouseButton1Click:Connect(function()
		if locked() then
			refuse()
			return
		end
		setSlots(nil, nil)
	end)

	-- Наугад: случайная пара из запаса, которую ещё не пробовали (и рецепт не открыт).
	-- Занят один слот — партнёр подбирается к нему. Подсказкой это не служит: среди
	-- непробованных пар есть и пустые.
	randomButton.MouseButton1Click:Connect(function()
		if locked() then
			refuse()
			return
		end
		local keys = {}
		for key, count in T.inventory do
			if count > 0 and Elements[key] then
				table.insert(keys, key)
			end
		end
		table.sort(keys)
		local fixed = anchor()
		local pool = {}
		for i, a in keys do
			for j = i, #keys do
				local b = keys[j]
				local fits = not fixed or a == fixed or b == fixed
				if fits and T.times(a, b) > 0 and not T.knownResult(a, b) and not T.isFailed(a, b) then
					table.insert(pool, { a, b })
				end
			end
		end
		if #pool == 0 then
			Show.Shake(randomButton, 5, 0.3)
			return
		end
		local pick = pool[math.random(#pool)]
		if fixed and pick[2] == fixed and pick[1] ~= fixed then
			pick[1], pick[2] = pick[2], pick[1]
		end
		setSlots(pick[1], pick[2])
		Show.Noise(slotA)
		Show.Noise(slotB)
	end)

	sortButton.MouseButton1Click:Connect(function()
		sortIndex = sortIndex % #SORTS + 1
		rebuild()
	end)

	-- ---------- крафт ----------
	-- Подтверждения нет (#291): рычаг сам и есть «точно?» — его надо дотянуть. Дотянули —
	-- пресс раздавил пару (#292): слоты пусты, поршни сжаты до ответа сервера.
	function craft()
		local a, b = slots[1], slots[2]
		if not (a and b) or locked() then
			refuse()
			return
		end
		local steps
		if chain then
			steps = chain
		elseif state == "failed" or T.times(a, b) < 1 then
			Show.Shake(craftButton, 6, 0.3)
			UISound.Play("Fail")
			return
		else
			steps = { { a, b } }
		end
		run = chain and "chain" or "single"
		pressed = { a, b, base = { [a] = T.count(a), [b] = T.count(b) } }
		slots[1], slots[2] = nil, nil
		-- Слоты пусты сразу (резерв держит pressed), но до удара рисуют пару: её и давят.
		frozen = true
		press.squeeze(Elements[a].color, Elements[b].color, function()
			frozen = false
			UISound.Play("Stop")
			refreshBench()
		end)
		T.run(steps) -- сам зовёт T.refresh: слоты и инвентарь перерисуются
	end

	-- Пачка: пара остаётся на столе, пресс бьёт на каждый шаг, результаты летят сами.
	local function batchOf(n)
		local a, b = slots[1], slots[2]
		if a and b and state == "known" and not locked() then
			run = "batch"
			T.craft(a, b, math.min(n, T.times(a, b), T.TUNING.batchMax))
		end
	end
	fiveButton.MouseButton1Click:Connect(function()
		batchOf(T.TUNING.batchSize)
	end)
	maxButton.MouseButton1Click:Connect(function()
		batchOf(T.TUNING.batchMax)
	end)

	-- Клавиатура ПК: Enter — дёрнуть рычаг, Backspace — очистить слоты. Только когда стол на экране и поиск не в фокусе.
	local function onScreen()
		local node = page
		while node do
			if node:IsA("LayerCollector") then
				return node.Enabled
			end
			if node:IsA("GuiObject") and not node.Visible then
				return false
			end
			node = node.Parent
		end
		return false
	end

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or UserInputService:GetFocusedTextBox() or not onScreen() then
			return
		end
		local k = input.KeyCode
		if k == Enum.KeyCode.Return or k == Enum.KeyCode.KeypadEnter then
			lever.pull()
		elseif k == Enum.KeyCode.Backspace and not locked() then
			setSlots(nil, nil)
		end
	end)

	-- ---------- ответ сервера ----------
	-- Новый рецепт — баннер посреди страницы: что открыто и из чего.
	local function banner(e)
		local color = Elements[e.result].color
		local card = make("Frame", "NewRecipe", page, 8)
		card.AnchorPoint = Vector2.new(0.5, 0.5)
		card.Position = UDim2.fromScale(0.5, 0.55)
		card.Size = UDim2.new(0.8, 0, 0, mobile and 92 or 132)
		card.BackgroundColor3 = Theme.color.panelSoft
		card.BackgroundTransparency = 0.05
		Theme.Corner(card, Theme.radius.panel)
		Theme.Stroke(card, Theme.Legible(color), 2, 0)
		local limit = Instance.new("UISizeConstraint")
		limit.MaxSize = Vector2.new(620, math.huge)
		limit.Parent = card

		local bar = make("Frame", "Bar", card, 8)
		bar.BackgroundColor3 = color
		bar.BackgroundTransparency = 0
		bar.Size = UDim2.new(1, 0, 0, 4)

		local head = make("TextLabel", "Head", card, 9)
		head.Position = UDim2.new(0, 0, 0, mobile and 10 or 16)
		head.Size = UDim2.new(1, 0, 0, mobile and 18 or 22)
		head.FontFace = Theme.font.body
		head.TextSize = mobile and 14 or 16
		head.TextColor3 = Theme.color.energy
		head.Text = "★  НОВЫЙ РЕЦЕПТ  ★"

		local name = make("TextLabel", "Name", card, 9)
		name.Position = UDim2.new(0, 0, 0, mobile and 30 or 42)
		name.Size = UDim2.new(1, 0, 0, mobile and 30 or 44)
		name.FontFace = Theme.font.strong
		name.TextSize = mobile and 24 or 36
		name.TextColor3 = Theme.Legible(color)
		name.Text = Theme.Caps(Elements[e.result].name)
		Theme.Display(name)
		name.TextColor3 = Theme.Legible(color)

		local from = make("TextLabel", "From", card, 9)
		from.Position = UDim2.new(0, 0, 1, mobile and -26 or -36)
		from.Size = UDim2.new(1, 0, 0, mobile and 18 or 24)
		from.FontFace = Theme.font.body
		from.TextSize = mobile and 14 or 15
		from.TextColor3 = Theme.color.textDim
		from.Text = ("%s + %s"):format(Elements[e.a].name, Elements[e.b].name)

		Theme.Open(card)
		Show.Pop(card, 0.15, 0.4)
		UISound.Play("Win")
		task.delay(T.TUNING.bannerTime, function()
			card:Destroy()
		end)
	end

	-- Куда лететь элементу key: его ячейка, если она видна в списке, иначе сам список.
	local function home(key)
		local c = cells[key]
		if c then
			local p, s = c.btn.AbsolutePosition + c.btn.AbsoluteSize / 2, invList.AbsolutePosition
			local e = s + invList.AbsoluteSize
			if p.X >= s.X and p.Y >= s.Y and p.X <= e.X and p.Y <= e.Y then
				return c.btn
			end
		end
		return invList
	end

	local function landed(key)
		local c = cells[key]
		if c then
			Show.Flash(c.btn, Elements[key].color, 0.5)
			Show.Pop(c.btn, 0.1, 0.25)
		end
	end

	-- Результат шага пачки летит из-под пресса в инвентарь сам.
	local function flyHome(key)
		press.fly(resultSlot, home(key), Elements[key].color, function()
			landed(key)
		end)
	end

	-- Пока в середине лежит результат, пустые слоты и «+» спрятаны: поршни разошлись,
	-- между ними только он.
	local function bare(on)
		slotA.Visible, slotB.Visible, plusLabel.Visible = not on, not on, not on
	end

	local function showResult(key)
		local color = Elements[key].color
		resultSlot.Text = Theme.Caps(Elements[key].name)
		Theme.ElementButton(resultSlot, color, { element = key })
		resultSlot.Visible = true
		Show.Pop(resultSlot, 0.18, 0.4)
		Show.Flash(resultSlot, color, 0.6)
	end

	-- Забрать результат: летит дугой в свою ячейку, там вспышка и запас +1. instant — без
	-- полёта (окно закрыли, со стола взяли другой рецепт).
	local taking = false
	local function take(instant)
		local key = held
		if not key or taking then
			return
		end
		resultSlot.Visible = false
		bare(false)
		if instant or not onScreen() then
			held = nil
			refreshBench()
			rebuild()
			return
		end
		UISound.Play("Click")
		taking = true
		-- Ячейки ещё нет (такого элемента не было): запас открывается сразу, чтобы было куда лететь.
		if not cells[key] then
			held = nil
			rebuild()
		end
		press.fly(resultSlot, home(key), Elements[key].color, function()
			taking = false
			held = nil
			refreshBench()
			rebuild()
			landed(key)
			local c = cells[key]
			if c then
				Show.Float(c.btn, "+1", Theme.Legible(Elements[key].color), mobile and 16 or 20)
			end
		end)
	end
	resultSlot.MouseButton1Click:Connect(function()
		take(false)
	end)

	-- Ответ сервера.
	local function onResult(e)
		local mode = run
		local last = not T.busy()
		if last then
			run = nil
		end

		-- Шаг пачки или промежуточный шаг цепочки: удар пресса, результат летит сам.
		if mode == "batch" or (mode == "chain" and not last and e.ok) then
			if mode == "batch" and last then
				slots[1], slots[2] = nil, nil -- пачка кончилась: пара раздавлена
			end
			refreshBench()
			rebuild()
			if not onScreen() then
				return
			end
			if e.ok then
				press.slam(Elements[e.a].color, Elements[e.b].color, function()
					UISound.Play("Stop")
					flyHome(e.result)
				end)
				if e.first then
					banner(e)
				end
			else
				press.crack()
				UISound.Play("Fail")
			end
			return
		end

		-- Ответ не на рычаг (стол уже сбросил ожидание) — только перерисовать.
		if not mode then
			refreshBench()
			rebuild()
			return
		end

		-- Одиночный крафт или конец цепочки: поршни расходятся, в середине результат.
		pressed = nil
		if e.ok then
			held = e.result
		end
		if not onScreen() then
			held = nil
			press.release()
			refreshBench()
			rebuild()
			return
		end
		refreshBench()
		rebuild()
		press.release(function()
			if e.ok then
				if held == e.result then
					showResult(e.result)
				end
				if e.first then
					banner(e)
				else
					UISound.Play("Gain")
				end
			else
				-- Неудача: осколки; элементы уже вернулись в инвентарь (сервер их не списал).
				press.crack()
				Show.Float(resultSlot, e.kind == "nomix" and "НЕ СМЕШИВАЮТСЯ" or "НЕ ХВАТАЕТ",
					Theme.color.danger, mobile and 16 or 20)
				UISound.Play("Fail")
			end
		end, function()
			-- Поршни пошли: пустые слоты прячутся, между поршнями только результат.
			if e.ok and held == e.result then
				bare(true)
			end
		end)
	end

	page:GetPropertyChangedSignal("Visible"):Connect(function()
		if page.Visible and dirty then
			rebuild()
		end
	end)

	layout()
	refresh()

	return {
		frame = page,
		refresh = refresh,
		onResult = onResult,
		-- Окно закрыли: результат из-под пресса забирается сам.
		close = function()
			take(true)
		end,
		filter = function(text)
			if text ~= query then
				query = text
				rebuild()
			end
		end,
		fill = function(a, b)
			if T.busy() or pressed then
				return
			end
			take(true)
			setSlots(a, b)
			Show.Pop(slotA, 0.08, 0.22)
			Show.Pop(slotB, 0.08, 0.22)
		end,
	}
end
