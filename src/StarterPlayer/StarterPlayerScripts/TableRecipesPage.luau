-- Страница «Рецепты» алхимического стола (#286): открытые рецепты сеткой.
-- Ячейка — результат его цветом и на сколько крафтов хватает запаса (#290: без мелких подписей).
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
		local btnW = compact and 150 or 200
		place(readyButton, 0, 0, btnW, rowH)
		readyButton.TextSize = compact and 14 or 16
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
		readyButton.Text = onlyReady and "ВСЕ РЕЦЕПТЫ" or "ТОЛЬКО МОЖНО"
		Theme.Button(readyButton, onlyReady and "active" or "ghost")

		local shown = 0
		for _, recipe in Recipes.List do
			if T.known[recipe.result] and matches(recipe) then
				local n = T.times(recipe.a, recipe.b)
				local chain = n < 1 and T.plan(recipe.result) or nil
				if not onlyReady or n > 0 or chain then
					shown += 1
					local data = Elements[recipe.result]
					local btn = make("TextButton", recipe.result, list)
					btn.LayoutOrder = shown
					btn.FontFace = Theme.font.strong
					btn.TextSize = mobile and 15 or 14
					btn.RichText = true
					btn.TextXAlignment = Enum.TextXAlignment.Left
					btn.Text = Theme.Caps(data.name)
					Theme.ElementButton(btn, data.color, { wide = true, element = recipe.result, dim = n < 1 and not chain })
					-- Только имя тем же кеглем (без мелких подписей, #290): хватает запаса —
					-- «×N», открыт за эту игру — звезда. Из чего рецепт — видно на столе.
					local text = Theme.Caps(data.name)
					if n > 0 then
						text ..= ('   <font color="%s">×%d</font>'):format(Theme.Hex(Theme.color.action), n)
					end
					if T.fresh[recipe.result] then
						text ..= ('   <font color="%s">★</font>'):format(Theme.Hex(Theme.color.energy))
					end
					Theme.SetCellText(btn, text)
					if (n > 0 or chain) and not onlyReady then
						btn.LayoutOrder = shown - 1000 -- что можно сделать сейчас — наверху
					end
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
