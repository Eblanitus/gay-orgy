-- Страница «Крафт» алхимического стола (#282–#285).
-- Верх — верстак на стеклянной плашке: два слота, «+», «=», слот результата и кнопка крафта;
-- под ними строка инструментов: обмен, сброс, случайная проба, подсказка и крафт пачкой.
-- Ниже — инвентарь с подсказками: пока в слоте один элемент, у каждого другого видно,
-- что выйдет из пары (если рецепт открыт), что пара уже не смешалась или что её не пробовали.
-- Ответ сервера играется на самом столе: вспышка, «+1», баннер нового рецепта, дрожь неудачи.
-- T — общее состояние стола (CraftingCraftTab), page — рамка страницы.
return function(T, page)
	local Theme, Elements, MobileUI, Show, UISound = T.Theme, T.Elements, T.MobileUI, T.Show, T.UISound
	local UserInputService = game:GetService("UserInputService")
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

	-- Стеклянные плашки — первыми детьми: из равных по ZIndex позже рисуется тот, кто позже в дереве.
	local benchPlate = make("Frame", "BenchPlate", page)
	T.glass(benchPlate)
	local invPlate = make("Frame", "InventoryPlate", page)
	T.glass(invPlate)

	local slotA = button("SlotA", page, "", "muted")
	local plusLabel = make("TextLabel", "Plus", page)
	local slotB = button("SlotB", page, "", "muted")
	local eqLabel = make("TextLabel", "Equals", page)
	local resultSlot = make("TextButton", "Result", page)
	resultSlot.AutoButtonColor = false
	resultSlot.FontFace = Theme.font.strong
	local craftButton = button("Craft", page, "СКРЕСТИТЬ", "muted")

	for _, l in { plusLabel, eqLabel } do
		l.FontFace = Theme.font.strong
		l.TextColor3 = Theme.color.textDim
	end
	plusLabel.Text = "+"
	eqLabel.Text = "="
	for _, s in { slotA, slotB, resultSlot } do
		s.FontFace = Theme.font.strong
		s.TextWrapped = true
	end

	local swapButton = button("Swap", page, "ОБМЕН", "quiet")
	local clearButton = button("Clear", page, "СБРОС", "quiet")
	local randomButton = button("Random", page, "НАУГАД", "quiet")
	local fiveButton = button("Five", page, "×" .. T.TUNING.batchSize, "quiet")
	local maxButton = button("Max", page, "МАКС", "quiet")
	local hintLabel = make("TextLabel", "Hint", page)
	hintLabel.FontFace = Theme.font.body
	hintLabel.TextXAlignment = Enum.TextXAlignment.Left
	hintLabel.TextTruncate = Enum.TextTruncate.AtEnd
	hintLabel.RichText = true

	local invSection = make("TextLabel", "Section", page)
	invSection.TextSize = 11
	Theme.Section(invSection, "инвентарь", 0)
	local sortButton = button("Sort", page, "", "ghost")

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

		local benchH = pad + slotH + gap + toolH + pad
		place(benchPlate, 0, 0, W, benchH)
		local slotW = (W - pad * 2 - craftW - gap - signW * 2) / 3
		local x = pad
		place(slotA, x, pad, slotW, slotH)
		place(plusLabel, x + slotW, pad, signW, slotH)
		place(slotB, x + slotW + signW, pad, slotW, slotH)
		place(eqLabel, x + slotW * 2 + signW, pad, signW, slotH)
		place(resultSlot, x + slotW * 2 + signW * 2, pad, slotW, slotH)
		place(craftButton, W - pad - craftW, pad, craftW, slotH)

		local big = slotH >= 110
		for _, s in { slotA, slotB, resultSlot } do
			setCellTextSize(s, big and 24 or by(14, 16))
		end
		craftButton.TextSize = big and 20 or by(13, 16)
		plusLabel.TextSize = big and 32 or 22
		eqLabel.TextSize = plusLabel.TextSize

		-- Строка инструментов: слева обмен, сброс, наугад; справа пачка; между ними подсказка.
		local ty = pad + slotH + gap
		local toolW = by(70, 104)
		local batchW = by(54, 80)
		for i, b in { swapButton, clearButton, randomButton } do
			place(b, pad + (i - 1) * (toolW + gap), ty, toolW, toolH)
			b.TextSize = by(12, 14)
		end
		place(maxButton, W - pad - batchW, ty, batchW, toolH)
		place(fiveButton, W - pad - batchW * 2 - gap, ty, batchW, toolH)
		fiveButton.TextSize, maxButton.TextSize = by(12, 14), by(12, 14)
		local hintX = pad + (toolW + gap) * 3 + by(4, 8)
		place(hintLabel, hintX, ty, W - pad - batchW * 2 - gap * 2 - hintX, toolH)
		hintLabel.TextSize = by(12, 15)

		-- Подпись инвентаря и сортировка.
		local sy = benchH + gap
		local sortW = by(110, 150)
		place(sortButton, W - sortW, sy, sortW, toolH)
		sortButton.TextSize = by(11, 13)
		place(invSection, 0, sy + math.floor((toolH - 16) / 2), W - sortW - gap, 16)

		local ly = sy + toolH + by(4, 6)
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
	local function renderSlot(b, key)
		b.Text = key and Theme.Caps(Elements[key].name) or "— ПУСТО —"
		-- Цветная полоса смотрит в сторону «+» (решение автора, #105).
		Theme.ElementButton(b, key and Elements[key].color or nil, { right = b == slotA, element = key })
	end

	local function lack(a, b)
		if a == b then
			return Elements[a].name
		end
		local names = {}
		for _, k in { a, b } do
			if T.count(k) < 1 then
				table.insert(names, Elements[k].name)
			end
		end
		return table.concat(names, ", ")
	end

	local function setHint(text, color)
		hintLabel.Text = text
		hintLabel.TextColor3 = color
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

		-- Слот результата: открытый рецепт — сам элемент; неизвестная пара — «???»;
		-- пара, которая уже не смешалась, — так и написано.
		resultSlot.Text = state == "known" and Theme.Caps(Elements[result].name)
			or state == "failed" and "НЕ СМЕШИВАЮТСЯ"
			or state == "unknown" and "???"
			or "= ?"
		Theme.ElementButton(resultSlot, result and Elements[result].color or nil, { element = result })
		local caption = resultSlot:FindFirstChild("Caption")
		if caption and not result then
			caption.TextColor3 = state == "failed" and Theme.color.danger
				or state == "unknown" and Theme.color.accent
				or Theme.buttonKind.muted.text
		end

		local n = (a and b) and T.times(a, b) or 0
		local left = T.batchLeft()
		local busy = T.pending or left > 0
		chain = (state == "known" and n < 1) and T.plan(result) or nil
		local ready = ((state == "known" or state == "unknown") and n > 0 or chain ~= nil) and not busy
		Theme.Button(craftButton, ready and "action" or "muted")
		craftButton.Text = busy and (left > 0 and ("ЕЩЁ ×" .. left) or "…")
			or state == "failed" and "НЕЛЬЗЯ"
			or chain and ("СОБРАТЬ ×" .. #chain)
			or (a and b and n < 1) and "НЕ ХВАТАЕТ"
			or state == "unknown" and "ПРОБОВАТЬ"
			or "СКРЕСТИТЬ"

		local canBatch = state == "known" and n >= 2 and not busy
		fiveButton.Visible, maxButton.Visible = canBatch, canBatch
		Theme.Button(swapButton, (a or b) and "quiet" or "muted")
		Theme.Button(clearButton, (a or b) and "quiet" or "muted")

		if state == "empty" then
			setHint((a or b) and "выберите второй элемент" or "клик по элементу — в слот, по слоту — убрать",
				Theme.color.textMute)
		elseif state == "failed" then
			setHint("уже пробовали — не смешиваются", Theme.color.danger)
		elseif chain then
			setHint(("не хватает: %s — соберу цепочкой из %d шагов"):format(lack(a, b), #chain), Theme.color.energy)
		elseif n < 1 then
			setHint("не хватает: " .. lack(a, b), Theme.color.warn)
		elseif state == "known" then
			setHint(("хватит на ×%d"):format(n), Theme.color.action)
		else
			setHint("пара не пробовалась — спрошу подтверждение", Theme.color.textDim)
		end
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

	local function cellText(key, partner)
		local data = Elements[key]
		local text = ("%s   %s"):format(
			Theme.Caps(data.name),
			Theme.Readout("шт", T.count(key), Theme.Legible(data.color), 10)
		)
		if not partner then
			return text, false
		end
		local r = T.knownResult(partner, key)
		local tag, color, dim
		if r then
			tag, color = "→ " .. Theme.Caps(Elements[r].name), Theme.Legible(Elements[r].color)
		elseif T.isFailed(partner, key) then
			tag, color, dim = "✕", Theme.color.danger, true
		else
			tag, color = "?", Theme.color.textMute
		end
		return ('%s   <font size="11" color="%s">%s</font>'):format(text, Theme.Hex(color), tag), dim
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
		for key, count in T.inventory do
			if count > 0 and Elements[key] then
				total += 1
				if T.matches(key, query) then
					table.insert(keys, key)
				end
			end
		end
		sortKeys(keys)
		Theme.Section(invSection, "инвентарь", query ~= "" and (#keys .. " / " .. total) or total)
		sortButton.Text = "СОРТ: " .. Theme.Caps(SORTS[sortIndex].name)

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
		refreshBench()
		rebuild()
	end

	-- ---------- действия ----------
	local function setSlots(a, b)
		slots[1], slots[2] = a, b
		renderSlot(slotA, a)
		renderSlot(slotB, b)
		refreshBench()
		refreshCells()
	end

	-- Пустой слот заполняется первым. Оба заняты — меняется второй: первый остаётся
	-- «якорем», и перебирать ему пары можно одними щелчками по инвентарю.
	function assignToSlot(key)
		local target
		if slots[1] == nil then
			target = 1
		else
			target = 2
		end
		if target == 1 then
			setSlots(key, slots[2])
		else
			setSlots(slots[1], key)
		end
		Show.Pop(target == 1 and slotA or slotB, 0.08, 0.22)
	end

	slotA.MouseButton1Click:Connect(function()
		setSlots(nil, slots[2])
	end)
	slotB.MouseButton1Click:Connect(function()
		setSlots(slots[1], nil)
	end)

	swapButton.MouseButton1Click:Connect(function()
		if slots[1] or slots[2] then
			setSlots(slots[2], slots[1])
			Show.Slide(slotA, 1)
			Show.Slide(slotB, -1)
		end
	end)

	clearButton.MouseButton1Click:Connect(function()
		setSlots(nil, nil)
	end)

	-- Наугад: случайная пара из запаса, которую ещё не пробовали (и рецепт не открыт).
	-- Занят один слот — партнёр подбирается к нему. Подсказкой это не служит: среди
	-- непробованных пар есть и пустые.
	randomButton.MouseButton1Click:Connect(function()
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
			setHint("все пары из запаса уже пробовали", Theme.color.warn)
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

	-- ---------- подтверждение неизвестной пары ----------
	-- ТЗ v3: ошибка может стоить два элемента (верная пара, но не та), поэтому неизвестная
	-- пара уходит на сервер только после явного «да». Открытый рецепт крафтится сразу:
	-- игрок знает, что получит.
	local overlay = make("Frame", "CraftConfirm", T.root, 10)
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.BackgroundColor3 = Theme.color.ink
	overlay.BackgroundTransparency = 0.2
	overlay.Active = true
	overlay.Visible = false

	local CONFIRM_BTN_H = mobile and MobileUI.MIN_TAP or 38
	local box = make("Frame", "Box", overlay, 11)
	box.AnchorPoint = Vector2.new(0.5, 0.5)
	box.Position = UDim2.fromScale(0.5, 0.5)
	box.Size = UDim2.new(0.9, 0, 0, 112 + CONFIRM_BTN_H)
	Theme.Panel(box, { color = Theme.color.panelSoft, transparency = 0, scene = "confirm" })
	local boxLimit = Instance.new("UISizeConstraint")
	boxLimit.MaxSize = Vector2.new(400, 112 + CONFIRM_BTN_H)
	boxLimit.Parent = box

	local confirmLabel = make("TextLabel", "Text", box, 11)
	confirmLabel.Size = UDim2.new(1, -24, 0, 74)
	confirmLabel.Position = UDim2.fromOffset(12, 12)
	confirmLabel.FontFace = Theme.font.strong
	confirmLabel.TextSize = 17
	confirmLabel.TextWrapped = true
	confirmLabel.RichText = true
	confirmLabel.TextColor3 = Theme.color.text

	local yesButton = make("TextButton", "Yes", box, 11)
	yesButton.Size = UDim2.new(0.44, 0, 0, CONFIRM_BTN_H)
	yesButton.Position = UDim2.new(0, 16, 1, -(CONFIRM_BTN_H + 12))
	yesButton.FontFace = Theme.font.strong
	yesButton.TextSize = 15
	yesButton.Text = "ПРОБОВАТЬ"
	Show.Press(yesButton)
	Theme.Button(yesButton, "action")

	local noButton = make("TextButton", "No", box, 11)
	noButton.AnchorPoint = Vector2.new(1, 0)
	noButton.Size = UDim2.new(0.44, 0, 0, CONFIRM_BTN_H)
	noButton.Position = UDim2.new(1, -16, 1, -(CONFIRM_BTN_H + 12))
	noButton.FontFace = Theme.font.strong
	noButton.TextSize = 15
	noButton.Text = "ОТМЕНА"
	Show.Press(noButton)
	Theme.Button(noButton, "quiet")

	local function closeConfirm()
		overlay.Visible = false
	end

	local function craft()
		local a, b = slots[1], slots[2]
		if not (a and b) or overlay.Visible or T.pending or T.batchLeft() > 0 then
			return
		end
		if chain then
			T.run(chain)
			return
		end
		if state == "failed" or T.times(a, b) < 1 then
			Show.Shake(craftButton, 6, 0.3)
			UISound.Play("Fail")
			return
		end
		if state == "known" then
			T.craft(a, b, 1)
			return
		end
		confirmLabel.Text = ("Скрестить %s + %s?\n<font size=\"13\" color=\"%s\">Пару ещё не пробовали. Не смешаются — ничего не сгорит.</font>")
			:format(Elements[a].name, Elements[b].name, Theme.Hex(Theme.color.textMute))
		overlay.Visible = true
		Theme.Open(box)
	end

	craftButton.MouseButton1Click:Connect(craft)
	noButton.MouseButton1Click:Connect(closeConfirm)
	yesButton.MouseButton1Click:Connect(function()
		closeConfirm()
		if slots[1] and slots[2] then
			T.craft(slots[1], slots[2], 1)
		end
	end)

	local function batchOf(n)
		local a, b = slots[1], slots[2]
		if a and b and state == "known" then
			T.craft(a, b, math.min(n, T.times(a, b), T.TUNING.batchMax))
		end
	end
	fiveButton.MouseButton1Click:Connect(function()
		batchOf(T.TUNING.batchSize)
	end)
	maxButton.MouseButton1Click:Connect(function()
		batchOf(T.TUNING.batchMax)
	end)

	-- Клавиатура ПК: Enter — скрестить (или «да» в подтверждении), Esc — отмена,
	-- Backspace — очистить слоты. Только когда стол на экране и поиск не в фокусе.
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
			if overlay.Visible then
				closeConfirm()
				if slots[1] and slots[2] then
					T.craft(slots[1], slots[2], 1)
				end
			else
				craft()
			end
		elseif k == Enum.KeyCode.Escape and overlay.Visible then
			closeConfirm()
		elseif k == Enum.KeyCode.Backspace and not overlay.Visible then
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
		head.TextSize = mobile and 13 or 16
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
		from.TextSize = mobile and 12 or 15
		from.TextColor3 = Theme.color.textDim
		from.Text = ("%s + %s"):format(Elements[e.a].name, Elements[e.b].name)

		Theme.Open(card)
		Show.Pop(card, 0.15, 0.4)
		UISound.Play("Win")
		task.delay(T.TUNING.bannerTime, function()
			card:Destroy()
		end)
	end

	local function onResult(e)
		refreshBench()
		rebuild()
		if not onScreen() then
			return
		end
		if e.ok then
			local color = Elements[e.result].color
			Show.Flash(slotA, color, 0.45)
			Show.Flash(slotB, color, 0.45)
			Show.Flash(resultSlot, color, 0.6)
			Show.Pop(resultSlot, 0.12, 0.3)
			Show.Float(resultSlot, "+1 " .. Theme.Caps(Elements[e.result].name), Theme.Legible(color), mobile and 16 or 22)
			if e.first then
				banner(e)
			else
				UISound.Play("Gain")
			end
		else
			Show.Shake(slotA, 7, 0.35)
			Show.Shake(slotB, 7, 0.35)
			Show.Flash(resultSlot, Theme.color.danger, 0.5)
			UISound.Play("Fail")
		end
	end

	page:GetPropertyChangedSignal("Visible"):Connect(function()
		if page.Visible and dirty then
			rebuild()
		end
	end)

	renderSlot(slotA, nil)
	renderSlot(slotB, nil)
	layout()
	refresh()

	return {
		frame = page,
		refresh = refresh,
		onResult = onResult,
		closeConfirm = closeConfirm,
		filter = function(text)
			if text ~= query then
				query = text
				rebuild()
			end
		end,
		fill = function(a, b)
			setSlots(a, b)
			Show.Pop(slotA, 0.08, 0.22)
			Show.Pop(slotB, 0.08, 0.22)
		end,
	}
end
