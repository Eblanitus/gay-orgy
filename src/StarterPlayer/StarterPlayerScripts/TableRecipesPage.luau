-- Страница «Рецепты» алхимического стола (#286): открытые рецепты сеткой.
-- Ячейка — результат его цветом, из чего он и на сколько крафтов хватает запаса.
-- Щелчок кладёт пару на стол и переключает на «Крафт». Кнопка «МОЖНО» оставляет только
-- то, на что хватает запаса. Неоткрытые рецепты не показываются: стол не подсказывает.
return function(T, page)
	local Theme, Elements, Recipes, MobileUI, Show = T.Theme, T.Elements, T.Recipes, T.MobileUI, T.Show
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
	local onlyReady = false

	local plate = make("Frame", "Plate", page)
	T.glass(plate)

	local section = make("TextLabel", "Section", page)
	section.TextSize = 11

	local readyButton = make("TextButton", "Ready", page)
	readyButton.FontFace = Theme.font.strong
	Show.Press(readyButton)

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
	emptyLabel.Visible = false

	local function layout()
		local W, H = page.AbsoluteSize.X, page.AbsoluteSize.Y
		if W < 60 or H < 60 then
			return
		end
		local compact = mobile or H < 420 or W < 760
		local pad = compact and 6 or 12
		local rowH = compact and 30 or 36
		local btnW = compact and 120 or 170
		place(readyButton, W - btnW, 0, btnW, rowH)
		readyButton.TextSize = compact and 11 or 13
		place(section, 0, math.floor((rowH - 16) / 2), W - btnW - pad, 16)
		local ly = rowH + (compact and 4 or 6)
		place(plate, 0, ly, W, H - ly)
		place(list, pad, ly + pad, W - pad * 2, H - ly - pad * 2)
		place(emptyLabel, pad * 3, ly + pad * 3, W - pad * 6, 60)
		emptyLabel.TextSize = compact and 13 or 15
		local grid = list:FindFirstChildOfClass("UIGridLayout")
		if grid then
			Theme.GridFit(grid)
		end
	end
	page:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)

	local function matches(recipe)
		return T.matches(recipe.result, query) or T.matches(recipe.a, query) or T.matches(recipe.b, query)
	end

	-- Запас меняется часто (покупки любого игрока), а сетка — шестьдесят с лишним ячеек:
	-- пока страница скрыта, она только помечается, пересборка — при показе.
	local dirty = false

	local function refresh()
		if not page.Visible then
			dirty = true
			return
		end
		dirty = false
		list:ClearAllChildren()
		local grid = Theme.Grid(list, mobile and 48 or 44, 360, 6)
		local known = T.knownCount()
		Theme.Section(section, "рецепты", ("%d / %d"):format(known, T.total))
		readyButton.Text = onlyReady and "ВСЕ РЕЦЕПТЫ" or "ТОЛЬКО МОЖНО"
		Theme.Button(readyButton, onlyReady and "active" or "ghost")

		local shown = 0
		for _, recipe in Recipes.List do
			if T.known[recipe.result] and matches(recipe) then
				local n = T.times(recipe.a, recipe.b)
				if not onlyReady or n > 0 then
					shown += 1
					local data = Elements[recipe.result]
					local btn = make("TextButton", recipe.result, list)
					btn.LayoutOrder = shown
					btn.FontFace = Theme.font.strong
					btn.TextSize = mobile and 15 or 14
					btn.RichText = true
					btn.TextXAlignment = Enum.TextXAlignment.Left
					btn.Text = Theme.Caps(data.name)
					Theme.ElementButton(btn, data.color, { wide = true, element = recipe.result, dim = n < 1 })
					local count = n > 0
							and ('<font color="%s">×%d</font>'):format(Theme.Hex(Theme.color.action), n)
						or ('<font color="%s">—</font>'):format(Theme.Hex(Theme.color.textMute))
					Theme.SetCellText(btn, ('%s   <font size="11" color="%s">%s + %s</font>   %s'):format(
						Theme.Caps(data.name),
						Theme.Hex(Theme.color.textDim),
						Elements[recipe.a].name,
						Elements[recipe.b].name,
						count
					))
					btn.MouseButton1Click:Connect(function()
						if Theme.WasDragged(list) then
							return
						end
						T.UISound.Play("Click")
						T.fill(recipe.a, recipe.b)
					end)
				end
			end
		end
		Theme.GridFit(grid)

		emptyLabel.Visible = shown == 0
		emptyLabel.Text = known == 0 and "Рецептов пока нет. Первый откроется на столе — попробуйте скрестить два элемента."
			or onlyReady and "На открытые рецепты сейчас не хватает запаса."
			or "Ничего не нашлось."
	end

	readyButton.MouseButton1Click:Connect(function()
		onlyReady = not onlyReady
		refresh()
	end)

	page:GetPropertyChangedSignal("Visible"):Connect(function()
		if page.Visible and dirty then
			refresh()
		end
	end)

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
