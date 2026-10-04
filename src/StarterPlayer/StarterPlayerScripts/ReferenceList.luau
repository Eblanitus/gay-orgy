-- Список рецептов под картой справочника и карточка выбранного узла; выбор узла (ref.selectNode).
-- Вынесено из CraftingReference.luau (поведение то же): файл был слишком велик, чтобы
-- агент читал его целиком. deps — локальные CraftingReference и модулей до этого; ref — общее
-- изменяемое (см. CraftingReference). Возвращается то, что нужно дальше.
return function(deps)
	local Theme = deps.Theme
	local Elements = deps.Elements
	local knownRecipes = deps.knownRecipes
	local Recipes = deps.Recipes
	local Detail = deps.Detail
	local UISound = deps.UISound
	local ref = deps.ref
	local openedLabel = deps.openedLabel
	local listScroll = deps.listScroll
	local cardPlate = deps.cardPlate
	local mapCard = deps.mapCard
	local nodeGui = deps.nodeGui
	local orbitOpen = deps.orbitOpen
	local killsByElement = deps.killsByElement
	local isKnown = deps.isKnown
	local onMap = deps.onMap
	local countOf = deps.countOf
	local isCraftable = deps.isCraftable
	local chainOf = deps.chainOf

	-- Список под картой: либо все открытые рецепты, либо — когда элемент выбран — его цепочка
	-- создания по шагам, от базовых вверх. На карте цепочка видна целиком, но порядка шагов
	-- по ней не прочитать — список говорит ровно это. Строка ведёт обратно на карту: нажатие
	-- выбирает элемент и подводит к нему вид — искать нужный узел глазами по всей карте не надо.
	local function refreshBook()
		listScroll:ClearAllChildren()
		-- Сетка: рецепт — короткая строка в три слова, и на полном экране колонка таких
		-- строк — это метр пустоты справа от каждой и прокрутка после десятой.
		Theme.Grid(listScroll, 24, 340, 4)

		local steps = {}
		if ref.selected then
			for key in ref.chainNodes do
				if ref.graph.producedBy[key] then
					table.insert(steps, { key = key, recipe = ref.graph.producedBy[key] })
				end
			end
			-- Порядок цепочки — по глубине: сначала то, что делается прямо из базовых.
			table.sort(steps, function(one, two)
				if ref.graph.depth[one.key] ~= ref.graph.depth[two.key] then
					return ref.graph.depth[one.key] < ref.graph.depth[two.key]
				end
				return Elements[one.key].name < Elements[two.key].name
			end)
		else
			for _, recipe in Recipes.List do
				if knownRecipes[recipe.result] and orbitOpen(recipe.result) then
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
				UISound.Play("Click")
				ref.selectNode(entry.key)
				ref.focusOn(entry.key)
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
			empty.Text = ref.selected ~= nil
				and "Это базовый элемент — его не создают, а покупают за материю."
				or "Пока ничего не открыто — скрестите два элемента во вкладке «Крафт»."
			empty.Parent = listScroll
		end

		if ref.selected then
			-- Имя неоткрытого элемента не называется и в заголовке — на карте он тоже «???».
			local ui = nodeGui[ref.selected]
			local title = (ui and ui.known) and Elements[ref.selected].name or "???"
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
		cardPlate.Visible = ref.selected ~= nil
		if ref.selected then
			Detail.Element(mapCard, ref.selected, {
				known = isKnown,
				count = countOf,
				craftable = isCraftable,
				kills = killsByElement,
				onPick = function(key)
					ref.selectNode(key)
					ref.focusOn(key)
				end,
			})
		end
	end

	-- Повторное нажатие на тот же элемент снимает выбор: карта возвращается в полную силу,
	-- список — ко всем открытым рецептам.
	function ref.selectNode(key)
		-- Узел за закрытой орбитой на карте не нарисован — и выбрать нечего.
		if key ~= nil and not onMap(key) then
			return
		end
		if key ~= nil and key == ref.selected then
			key = nil
		end
		ref.selected = key
		if key then
			ref.chainNodes, ref.chainEdges = chainOf(key)
		else
			ref.chainNodes, ref.chainEdges = {}, {}
		end
		ref.repaint()
		refreshBook()
	end

	return {
		refreshBook = refreshBook,
	}
end
