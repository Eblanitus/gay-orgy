-- Страница «Журнал» алхимического стола (#287): что происходило на столе за эту игру.
-- Сверху — сводка (крафтов, новых рецептов, неудачных проб, открыто из всех), ниже — записи,
-- свежие первыми: удачный крафт цветом результата, новый рецепт со звездой, неудача красным.
-- Щелчок по записи кладёт ту же пару обратно на стол.
return function(T, page)
	local Theme, Elements, MobileUI = T.Theme, T.Elements, T.MobileUI
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

	local query = ""

	local plate = make("Frame", "Plate", page)
	T.glass(plate)

	local summary = make("TextLabel", "Summary", page)
	summary.FontFace = Theme.font.strong
	summary.RichText = true
	summary.TextColor3 = Theme.color.textDim
	summary.TextXAlignment = Enum.TextXAlignment.Left
	summary.TextTruncate = Enum.TextTruncate.AtEnd

	local bar = make("Frame", "Progress", page)
	bar.BackgroundColor3 = Theme.color.field
	bar.BackgroundTransparency = 0
	Theme.Corner(bar, Theme.radius.mark)
	local fill = make("Frame", "Fill", bar)
	fill.BackgroundColor3 = Theme.color.accent
	fill.BackgroundTransparency = 0
	Theme.Corner(fill, Theme.radius.mark)

	local list = make("ScrollingFrame", "List", page)
	list.ScrollBarThickness = 6
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new(0, 0, 0, 0)
	Theme.Scroller(list)
	Theme.DragScroll(list)

	local emptyLabel = make("TextLabel", "Empty", page)
	emptyLabel.FontFace = Theme.font.body
	emptyLabel.TextWrapped = true
	emptyLabel.TextColor3 = Theme.color.textMute
	emptyLabel.Text = "Журнал пуст. Здесь появится каждый крафт и каждая проба за эту игру."

	local rowH = mobile and 34 or 38

	local function layout()
		local W, H = page.AbsoluteSize.X, page.AbsoluteSize.Y
		if W < 60 or H < 60 then
			return
		end
		local compact = mobile or H < 420 or W < 760
		local pad = compact and 6 or 12
		local headH = compact and 24 or 30
		place(summary, 0, 0, W, headH)
		summary.TextSize = compact and 15 or 18
		place(bar, 0, headH + 2, W, 4)
		local ly = headH + (compact and 12 or 16)
		place(plate, 0, ly, W, H - ly)
		place(list, pad, ly + pad, W - pad * 2, H - ly - pad * 2)
		place(emptyLabel, pad * 3, ly + pad * 3, W - pad * 6, 60)
		emptyLabel.TextSize = compact and Theme.MIN_TEXT or 15
	end
	page:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)

	local function hex(color)
		return Theme.Hex(color)
	end

	local function entryText(e)
		local a, b = Elements[e.a].name, Elements[e.b].name
		if e.ok then
			local r = Elements[e.result]
			local text = ('%s + %s = <font color="%s">%s</font>'):format(a, b, hex(Theme.Legible(r.color)), Theme.Caps(r.name))
			if e.first then
				text ..= ('   <font color="%s">★ НОВЫЙ РЕЦЕПТ</font>'):format(hex(Theme.color.energy))
			end
			return text
		end
		if e.kind == "nomix" then
			return ('%s + %s   <font color="%s">не смешиваются</font>'):format(a, b, hex(Theme.color.danger))
		end
		return ('%s + %s   <font color="%s">%s</font>'):format(a, b, hex(Theme.color.warn), e.reason or "")
	end

	local function matches(e)
		return T.matches(e.a, query) or T.matches(e.b, query) or (e.result ~= nil and T.matches(e.result, query))
	end

	local function refresh()
		local s = T.stats
		local known = T.knownCount()
		-- Сводка одним кеглем, без мелких подписей (#290): слово и число его цветом.
		local function part(word, value, color)
			return ('%s <font color="%s">%s</font>'):format(word, Theme.Hex(color), tostring(value))
		end
		summary.Text = table.concat({
			part("КРАФТОВ", s.crafted, Theme.color.action),
			part("НОВЫХ", s.found, Theme.color.energy),
			part("НЕУДАЧ", s.failed, Theme.color.danger),
			part("ОТКРЫТО", ("%d / %d"):format(known, T.total), Theme.color.accent),
		}, "      ")
		fill.Size = UDim2.fromScale(T.total > 0 and known / T.total or 0, 1)


		list:ClearAllChildren()
		local lay = Instance.new("UIListLayout")
		lay.SortOrder = Enum.SortOrder.LayoutOrder
		lay.Padding = UDim.new(0, 4)
		lay.Parent = list

		local shown = 0
		for i, e in T.history do
			if matches(e) then
				shown += 1
				local row = make("TextButton", "Entry" .. i, list)
				row.LayoutOrder = i
				row.Size = UDim2.new(1, -8, 0, rowH)
				row.AutoButtonColor = false
				row.Text = ""
				row.BackgroundColor3 = Theme.color.row
				row.BackgroundTransparency = 0.15
				Theme.Corner(row, Theme.radius.control)

				-- Полоса слева — цвет исхода: результат, неудача или нехватка.
				local stripe = make("Frame", "Stripe", row)
				stripe.Size = UDim2.new(0, 4, 1, 0)
				stripe.BackgroundTransparency = 0
				stripe.BackgroundColor3 = e.ok and Elements[e.result].color
					or e.kind == "nomix" and Theme.color.danger
					or Theme.color.warn

				local text = make("TextLabel", "Text", row)
				local tx = 14
				text.Position = UDim2.fromOffset(tx, 0)
				text.Size = UDim2.new(1, -(tx + 8), 1, 0)
				text.FontFace = Theme.font.strong
				text.TextSize = mobile and 15 or 16
				text.RichText = true
				text.TextColor3 = Theme.color.text
				text.TextXAlignment = Enum.TextXAlignment.Left
				text.TextTruncate = Enum.TextTruncate.AtEnd
				text.Text = entryText(e)

				row.MouseButton1Click:Connect(function()
					if Theme.WasDragged(list) then
						return
					end
					T.UISound.Play("Click")
					T.fill(e.a, e.b)
				end)
			end
		end
		emptyLabel.Visible = shown == 0
		emptyLabel.Text = #T.history == 0 and "Журнал пуст. Здесь появится каждый крафт и каждая проба за эту игру."
			or "Ничего не нашлось."
	end

	layout()
	refresh()

	return {
		frame = page,
		refresh = refresh,
		filter = function(text)
			if text ~= query then
				query = text
				refresh()
			end
		end,
	}
end
