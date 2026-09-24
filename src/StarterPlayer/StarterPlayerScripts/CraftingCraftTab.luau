-- Вкладка «Крафт»: слоты, кнопка, список инвентаря, подтверждение крафта
-- Вынесено из CraftingUI.client.luau без изменений кода (задача #203): файл был слишком
-- велик, чтобы агент читал его целиком. deps — локальные основного файла, которые нужны
-- этому куску; возвращается то, что основной файл использует дальше.
return function(deps)
	local body = deps.body
	local tabFrames = deps.tabFrames
	local MobileUI = deps.MobileUI
	local Theme = deps.Theme
	local Elements = deps.Elements
	local Recipes = deps.Recipes
	local knownRecipes = deps.knownRecipes
	local inventory = deps.inventory
	local root = deps.root
	local RequestCraft = deps.RequestCraft

	-- ============ Вкладка "Крафт" ============

	local craftFrame = Instance.new("Frame")
	craftFrame.Size = UDim2.new(1, 0, 1, 0)
	craftFrame.BackgroundTransparency = 1
	craftFrame.Visible = false
	craftFrame.Parent = body
	craftFrame.Name = "CraftTab"
	tabFrames["Крафт"] = craftFrame

	-- Верхний блок (слоты + кнопка + подсказка) фиксированной высоты, ниже — список инвентаря.
	-- 200px под список — это примерно четыре строки, дальше он скроллится.
	--
	-- Кнопка «Скрестить» стоит в одной строке со слотами, а не отдельной полосой под ними.
	-- Отдельной полосой она забирала на телефоне 86 пикселей высоты, а высота окна там упирается
	-- в потолок applyHeight (0.92 рабочей высоты экрана) — вычитались эти пиксели ровно из списка
	-- инвентаря снизу: на узком экране ему оставалось около 30px, то есть половина одной строки
	-- из 48. Справа кнопке хватает своей ширины, слотам достаётся остальное.
	local SLOT_H = MobileUI.isMobile and 56 or 84
	local PLUS_W = MobileUI.isMobile and 22 or 40
	local CRAFT_W = MobileUI.isMobile and 100 or 200
	local ROW_GAP = 8
	local TOP_PAD = 6
	-- Стол занимает всю ширину вкладки и стал выше: это главное действие вкладки,
	-- и полоска в 752 пикселя посреди полного экрана читалась как обрезок старого окна.
	-- Потолок остаётся только от сверхшироких экранов, где слот ушёл бы за метр.
	local CRAFT_ROW_MAX = 1400
	-- Высота верхнего блока: отступ, строка слотов, отступ, подпись раздела, отступ.
	-- Подсказка отсюда ушла в статусную строку окна, а её место заняла подпись со счётчиком.
	local SECTION_H = 16
	local TOP_H = TOP_PAD + SLOT_H + 8 + SECTION_H + 4

	local slots = { nil, nil } -- ключи выбранных элементов, порядок значения не имеет (см. Recipes)

	-- Кнопки списка инвентаря по ключу элемента — чтобы пометить галочкой ту, что сейчас
	-- лежит в слоте крафта. Число «шт N» рядом с ней при этом не меняется: сервер спишет
	-- элемент только в момент самого крафта (см. подтверждение ниже), а не при выборе.
	-- Без пометки строка в инвентаре выглядела так, будто выбор в слот вообще ни на что
	-- не повлиял — количество то же самое, связи со столом не видно.
	local invButtons = {}

	local function refreshSlotMarks()
		for key, btn in invButtons do
			local inSlot = slots[1] == key or slots[2] == key
			local mark = btn:FindFirstChild("SlotMark")
			if inSlot and not mark then
				mark = Instance.new("TextLabel")
				mark.Name = "SlotMark"
				mark.AnchorPoint = Vector2.new(1, 0)
				mark.Position = UDim2.new(1, -3, 0, 2)
				mark.Size = UDim2.new(0, 16, 0, 16)
				mark.BackgroundTransparency = 1
				mark.FontFace = Theme.font.strong
				mark.TextSize = 14
				mark.TextColor3 = Theme.color.accent
				mark.Text = "✓"
				mark.ZIndex = btn.ZIndex + 1
				mark.Parent = btn
			elseif not inSlot and mark then
				mark:Destroy()
			end
		end
	end

	-- Слоты лежат в своей строке-контейнере, а не считают доли от ширины вкладки: справа от них
	-- теперь стоит кнопка фиксированной ширины, и вычитать её пришлось бы из каждой доли
	-- отдельно. Контейнер вычитает её один раз, внутри слоты снова делят ширину пополам,
	-- а «+» встаёт по центру строки — то есть ровно между ними при любой ширине окна.
	-- (Раньше место «+» задавалось жёсткими 186px от края — верно только для пиксельных слотов
	-- ПК, а на телефоне слоты считались долями, и «+» печатался поверх первого слота.)
	local craftRow = Instance.new("Frame")
	craftRow.Size = UDim2.new(1, 0, 0, SLOT_H)
	craftRow.Position = UDim2.new(0, 0, 0, TOP_PAD)
	craftRow.BackgroundTransparency = 1
	craftRow.Parent = craftFrame

	local craftLimit = Instance.new("UISizeConstraint")
	craftLimit.MaxSize = Vector2.new(CRAFT_ROW_MAX, math.huge)
	craftLimit.Parent = craftRow

	local slotRow = Instance.new("Frame")
	slotRow.Size = UDim2.new(1, -(CRAFT_W + ROW_GAP), 1, 0)
	slotRow.Position = UDim2.new(0, 0, 0, 0)
	slotRow.BackgroundTransparency = 1
	slotRow.Parent = craftRow

	local slotA = Instance.new("TextButton")
	slotA.Size = UDim2.new(0.5, -PLUS_W / 2, 1, 0)
	slotA.Position = UDim2.new(0, 0, 0, 0)
	slotA.FontFace = Theme.font.strong
	slotA.TextSize = 16
	slotA.Parent = slotRow

	local plusLabel = Instance.new("TextLabel")
	plusLabel.Size = UDim2.new(0, PLUS_W, 1, 0)
	plusLabel.Position = UDim2.new(0.5, -PLUS_W / 2, 0, 0)
	plusLabel.BackgroundTransparency = 1
	plusLabel.FontFace = Theme.font.strong
	plusLabel.TextSize = 22
	plusLabel.TextColor3 = Theme.color.textDim
	plusLabel.Text = "+"
	plusLabel.Parent = slotRow

	local slotB = Instance.new("TextButton")
	slotB.AnchorPoint = Vector2.new(1, 0)
	slotB.Size = UDim2.new(0.5, -PLUS_W / 2, 1, 0)
	slotB.Position = UDim2.new(1, 0, 0, 0)
	slotB.FontFace = Theme.font.strong
	slotB.TextSize = 16
	slotB.Parent = slotRow


	-- Прижата к правому краю вкладки, а не поставлена по пиксельному отступу: на ПК окно шире
	-- слотов, и кнопка, посаженная на 412px, висела посреди пустого места.
	local craftButton = Instance.new("TextButton")
	craftButton.AnchorPoint = Vector2.new(1, 0)
	craftButton.Size = UDim2.new(0, CRAFT_W, 1, 0)
	craftButton.Position = UDim2.new(1, 0, 0, 0)
	craftButton.FontFace = Theme.font.strong
	craftButton.TextSize = 16
	craftButton.TextTruncate = Enum.TextTruncate.AtEnd -- «→ ЭЛЕКТРИЧЕСТВО» шире кнопки
	craftButton.Text = "СКРЕСТИТЬ"
	craftButton.Parent = craftRow


	local invSection = Instance.new("TextLabel")
	invSection.Size = UDim2.new(1, 0, 0, SECTION_H)
	invSection.Position = UDim2.new(0, 0, 0, TOP_PAD + SLOT_H + 8)
	invSection.TextSize = 11
	invSection.Parent = craftFrame

	Theme.Section(invSection, "инвентарь", 0)

	local invList = Instance.new("ScrollingFrame")
	-- Занимает всё, что осталось от вкладки под верхним блоком: список — единственное здесь,
	-- что растёт вместе с окном, и отдавать ему остаток целиком правильнее, чем резервировать
	-- пиксели, которых на телефоне и так нет.
	invList.Size = UDim2.new(1, 0, 1, -TOP_H)
	invList.Position = UDim2.new(0, 0, 0, TOP_H)
	invList.BackgroundTransparency = 1
	invList.BorderSizePixel = 0
	invList.ScrollBarThickness = 6
	invList.AutomaticCanvasSize = Enum.AutomaticSize.Y
	invList.CanvasSize = UDim2.new(0, 0, 0, 0)
	invList.Parent = craftFrame

	Theme.Scroller(invList)
	Theme.DragScroll(invList)

	-- Пустой инвентарь под столом был просто пустотой: подпись «ИНВЕНТАРЬ // 0»
	-- и полэкрана ничего — непонятно, вкладка не догрузилась или класть в слоты нечего.
	-- Та же карточка, что в окне инвентаря (InventoryUI.emptyCard), и лежит она так же
	-- РЯДОМ со списком, а не внутри: refreshInventoryList зовёт invList:ClearAllChildren()
	-- на каждый приход инвентаря.
	local invEmpty = Instance.new("Frame")
	invEmpty.Name = "Empty"
	invEmpty.AnchorPoint = Vector2.new(0.5, 0)
	invEmpty.Size = UDim2.new(0, MobileUI.isMobile and 300 or 420, 0, 0)
	invEmpty.AutomaticSize = Enum.AutomaticSize.Y
	invEmpty.Visible = false
	invEmpty.Parent = craftFrame

	-- Без решётки (depth = false): на плашках с AutomaticSize она не строится вовсе
	-- (см. Theme.Backdrop) — тот же разбор, что у карточки в InventoryUI.
	Theme.Panel(invEmpty, { color = Theme.color.panelSoft, depth = false })

	local invEmptyPad = Instance.new("UIPadding")
	invEmptyPad.PaddingTop = UDim.new(0, 16)
	invEmptyPad.PaddingBottom = UDim.new(0, 16)
	invEmptyPad.PaddingLeft = UDim.new(0, 18)
	invEmptyPad.PaddingRight = UDim.new(0, 18)
	invEmptyPad.Parent = invEmpty

	local invEmptyList = Instance.new("UIListLayout")
	invEmptyList.SortOrder = Enum.SortOrder.LayoutOrder
	invEmptyList.Padding = UDim.new(0, 6)
	invEmptyList.Parent = invEmpty

	local invEmptyTitle = Instance.new("TextLabel")
	invEmptyTitle.LayoutOrder = 1
	invEmptyTitle.Size = UDim2.new(1, 0, 0, 20)
	invEmptyTitle.BackgroundTransparency = 1
	invEmptyTitle.FontFace = Theme.font.strong
	invEmptyTitle.TextSize = 15
	invEmptyTitle.TextXAlignment = Enum.TextXAlignment.Left
	invEmptyTitle.TextColor3 = Theme.color.textDim
	invEmptyTitle.Text = Theme.Caps("пусто")
	invEmptyTitle.Parent = invEmpty

	local invEmptyText = Instance.new("TextLabel")
	invEmptyText.LayoutOrder = 2
	invEmptyText.Size = UDim2.new(1, 0, 0, 0)
	invEmptyText.AutomaticSize = Enum.AutomaticSize.Y
	invEmptyText.BackgroundTransparency = 1
	invEmptyText.FontFace = Theme.font.body
	invEmptyText.TextSize = 13
	invEmptyText.TextWrapped = true
	invEmptyText.TextXAlignment = Enum.TextXAlignment.Left
	invEmptyText.TextYAlignment = Enum.TextYAlignment.Top
	invEmptyText.TextColor3 = Theme.color.textMute
	invEmptyText.Text = "Класть в слоты пока нечего. Возьмите базовый элемент на вкладке «Купить» — он появится здесь."
	invEmptyText.Parent = invEmpty

	-- Окно меняет ширину вместе с экраном, а число колонок считается от неё.
	invList:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		local layout = invList:FindFirstChildOfClass("UIGridLayout")
		if layout then
			Theme.GridFit(layout)
		end
	end)

	-- Надпись ячейки живёт на дочернем Caption (см. Theme.ElementButton), поэтому кегль
	-- меняется в двух местах: на самой кнопке (оттуда его возьмёт следующая пересборка)
	-- и на готовой надписи (чтобы видно было сразу).
	local function setCellTextSize(button, size)
		button.TextSize = size
		local caption = button:FindFirstChild("Caption")
		if caption then
			caption.TextSize = size
		end
	end

	-- Стол — главный предмет вкладки, и высота у него долевая, а не постоянная: полоской
	-- в пятьдесят пикселей посреди полного экрана он читался обрезком старого окна.
	-- На телефоне высоты и так нет — там остаётся пальцевая строка.
	local function applyCraftLayout()
		local w, h = craftFrame.AbsoluteSize.X, craftFrame.AbsoluteSize.Y
		if h < 40 or w < 40 then
			return
		end
		local slotH = MobileUI.isMobile and SLOT_H or math.clamp(math.floor(h * 0.26), 84, 220)

		-- Вся вкладка стоит одной колонкой. До этого стол был ограничен CRAFT_ROW_MAX и прижат
		-- влево, а подпись раздела и список под ним шли во всю ширину: на мониторе 1914
		-- стол кончался на 1415, а линия под ним — на 1900, и вкладка читалась как два разных
		-- окна, наложенных друг на друга.
		--
		-- Ширина и отступ считаются здесь, а не задаются UISizeConstraint внутри списка:
		-- refreshInventoryList зовёт invList:ClearAllChildren(), и ограничение, положенное внутрь,
		-- снесло бы первым же обновлением инвентаря — та же грабля, что в InventoryUI.
		local colW = math.min(w, CRAFT_ROW_MAX)
		local colX = math.max(0, math.floor((w - colW) / 2))

		craftRow.Position = UDim2.new(0, colX, 0, TOP_PAD)
		craftRow.Size = UDim2.new(0, colW, 0, slotH)

		local topH = TOP_PAD + slotH + 8 + SECTION_H + 4
		invSection.Position = UDim2.new(0, colX, 0, TOP_PAD + slotH + 8)
		invSection.Size = UDim2.new(0, colW, 0, SECTION_H)
		invList.Position = UDim2.new(0, colX, 0, topH)
		invList.Size = UDim2.new(0, colW, 1, -topH)
		-- Карточка «пусто» — по середине той же колонки, чуть ниже верха списка:
		-- точно по центру остатка она на мониторе уезжала бы к самому низу экрана.
		invEmpty.Position = UDim2.new(0, colX + math.floor(colW / 2), 0, topH + 24)

		-- Кегль внутри стола тоже от его высоты: имя элемента в шестнадцать пунктов
		-- теряется посреди поля в двести.
		local big = slotH >= 120
		setCellTextSize(slotA, big and 26 or 16)
		setCellTextSize(slotB, big and 26 or 16)
		setCellTextSize(craftButton, big and 20 or 16)
		plusLabel.TextSize = big and 34 or 22
	end

	applyCraftLayout()
	craftFrame:GetPropertyChangedSignal("AbsoluteSize"):Connect(applyCraftLayout)

	local function renderSlot(button, key)
		button.Text = key and Theme.Caps(Elements[key].name) or "— ПУСТО —"
		-- Цветная полоска смотрит в сторону «+»: у левого слота она у правого края, у правого —
		-- у левого (решение автора, задача #105). Слоты сходятся к плюсу, и цвет, отвёрнутый
		-- от него наружу, показывал не туда, куда идёт действие. Сторона считается по самой
		-- кнопке, а не приходит аргументом: renderSlot зовут из восьми мест, и восьмой раз
		-- этот флаг однажды передали бы неверно.
		Theme.ElementButton(button, key and Elements[key].color or nil, { right = button == slotA, element = key })
	end

	local function refreshCraftButton()
		local ready = slots[1] ~= nil and slots[2] ~= nil
		-- Готовность кнопки — это целиком её вид, а не два отдельных цвета: в выключенном
		-- состоянии гаснет и кант тоже.
		Theme.Button(craftButton, ready and "action" or "muted")

		-- Уже открытый рецепт показывается прямо на кнопке. Это не новое знание — пара
		-- уже лежит в «Справочнике», — но избавляет от привычки скрещивать и только потом
		-- сверяться с деревом. Неизвестная пара остаётся неизвестной: кнопка не намекает
		-- даже на то, есть ли у неё рецепт вообще.
		local known = nil
		if ready then
			local recipe = Recipes.Find(slots[1], slots[2])
			if recipe and knownRecipes[recipe.result] then
				known = Elements[recipe.result].name
			end
		end
		craftButton.Text = known and ("→ " .. Theme.Caps(known)) or "СКРЕСТИТЬ"
		refreshSlotMarks()
	end

	renderSlot(slotA, nil)
	renderSlot(slotB, nil)
	refreshCraftButton()

	-- Клик по слоту очищает его — проще, чем перетаскивание, и хватает для двух слотов.
	slotA.MouseButton1Click:Connect(function()
		slots[1] = nil
		renderSlot(slotA, nil)
		refreshCraftButton()
	end)

	slotB.MouseButton1Click:Connect(function()
		slots[2] = nil
		renderSlot(slotB, nil)
		refreshCraftButton()
	end)

	-- Клик по элементу инвентаря кладёт его ключ в первый свободный слот; если оба заняты —
	-- заменяет первый. Одинаковый элемент можно выбрать в оба слота (Recipes.Find("Fire","Fire")
	-- существует) — здесь только ключи, реальные счётчики проверяет сервер при крафте.
	local function assignToSlot(key)
		if slots[1] == nil then
			slots[1] = key
		elseif slots[2] == nil then
			slots[2] = key
		else
			slots[1] = key
			slots[2] = nil
		end
		renderSlot(slotA, slots[1])
		renderSlot(slotB, slots[2])
		refreshCraftButton()
	end

	local function refreshInventoryList()
		invList:ClearAllChildren() -- вместе с ячейками сносит и раскладку, поэтому сетка собирается заново
		invButtons = {} -- список пересобран целиком, старые кнопки больше не существуют
		-- Сетка, а не колонка: под столом остаётся половина экрана, и сорок элементов
		-- одной колонкой — это десять видимых строк и прокрутка при пустых боках.
		local layout = Theme.Grid(invList, MobileUI.isMobile and 48 or 40, 300, 6)

		local keys = {}
		for key, count in inventory do
			if count > 0 then
				table.insert(keys, key)
			end
		end
		table.sort(keys, function(a, b)
			local tierA, tierB = Elements[a].tier or 0, Elements[b].tier or 0
			if tierA ~= tierB then
				return tierA < tierB
			end
			return Elements[a].name < Elements[b].name
		end)

		Theme.Section(invSection, "инвентарь", #keys)
		invEmpty.Visible = #keys == 0

		for i, key in keys do
			local data = Elements[key]

			local btn = Instance.new("TextButton")
			btn.LayoutOrder = i -- размер ячейки задаёт сетка
			btn.FontFace = Theme.font.strong
			btn.TextSize = MobileUI.isMobile and 16 or 14
			-- Номер, имя и счётчик одной строкой с разным кеглем — второго TextLabel
			-- у ячейки-кнопки нет, её надпись одна на всю строку.
			btn.RichText = true
			btn.TextXAlignment = Enum.TextXAlignment.Left
			btn.Text = ("%s   %s"):format(
				Theme.Caps(data.name),
				Theme.Readout("шт", inventory[key], Theme.Legible(data.color), 10)
			)
			btn.Parent = invList

			Theme.ElementButton(btn, data.color, { wide = true, element = key })
			invButtons[key] = btn

			btn.MouseButton1Click:Connect(function()
				if Theme.WasDragged(invList) then
					return
				end
				assignToSlot(key)
			end)
		end

		refreshSlotMarks()
	end

	-- ============ Подтверждение крафта ============
	-- ТЗ v3: ошибка может стоить два элемента (верная пара, но не та, которую хотел), поэтому
	-- крафт уходит на сервер только после явного подтверждения.

	local confirmOverlay = Instance.new("Frame")
	confirmOverlay.Size = UDim2.new(1, 0, 1, 0)
	confirmOverlay.BackgroundColor3 = Theme.color.ink
	confirmOverlay.BackgroundTransparency = 0.2
	confirmOverlay.Visible = false
	confirmOverlay.ZIndex = 10
	confirmOverlay.Parent = root

	local confirmBox = Instance.new("Frame")
	-- Доля ширины окна с потолком: фиксированные 360px шире самого окна на узком телефоне.
	-- Кнопки подтверждения на телефоне в MIN_TAP высотой: тут ошибка стоит двух элементов,
	-- и промахнуться по 38px между «Скрестить» и «Отмена» дороже, чем где-либо ещё.
	local CONFIRM_BTN_H = MobileUI.isMobile and MobileUI.MIN_TAP or 38

	confirmBox.AnchorPoint = Vector2.new(0.5, 0.5)
	confirmBox.Size = UDim2.new(0.9, 0, 0, 102 + CONFIRM_BTN_H)
	confirmBox.Position = UDim2.new(0.5, 0, 0.5, 0)
	confirmBox.ZIndex = 11
	confirmBox.Parent = confirmOverlay

	-- Карточка подтверждения — та же панель, но на тон светлее и без прозрачности: она лежит
	-- поверх самого окна, и одинаковый цвет читался бы как дыра в нём.
	-- Самое близкое к игроку окно во всём интерфейсе: лежит поверх Лаборатории, которая
	-- сама поверх всего. Решётка здесь самая плотная, светлая и быстрая.
	Theme.Panel(confirmBox, { color = Theme.color.panelSoft, transparency = 0, scene = "confirm" })

	local confirmSize = Instance.new("UISizeConstraint")
	confirmSize.MaxSize = Vector2.new(360, 102 + CONFIRM_BTN_H)
	confirmSize.Parent = confirmBox

	local confirmLabel = Instance.new("TextLabel")
	confirmLabel.Size = UDim2.new(1, -24, 0, 64)
	confirmLabel.Position = UDim2.new(0, 12, 0, 14)
	confirmLabel.BackgroundTransparency = 1
	confirmLabel.FontFace = Theme.font.strong
	confirmLabel.TextSize = 17
	confirmLabel.TextWrapped = true
	confirmLabel.TextColor3 = Theme.color.text
	confirmLabel.ZIndex = 11
	confirmLabel.Parent = confirmBox

	local yesButton = Instance.new("TextButton")
	yesButton.Size = UDim2.new(0.44, 0, 0, CONFIRM_BTN_H)
	yesButton.Position = UDim2.new(0, 16, 1, -(CONFIRM_BTN_H + 12))
	yesButton.FontFace = Theme.font.strong
	yesButton.TextSize = 15
	yesButton.Text = "СКРЕСТИТЬ"
	yesButton.ZIndex = 11
	yesButton.Parent = confirmBox

	Theme.Button(yesButton, "action")

	local noButton = Instance.new("TextButton")
	noButton.AnchorPoint = Vector2.new(1, 0)
	noButton.Size = UDim2.new(0.44, 0, 0, CONFIRM_BTN_H)
	noButton.Position = UDim2.new(1, -16, 1, -(CONFIRM_BTN_H + 12))
	noButton.FontFace = Theme.font.strong
	noButton.TextSize = 15
	noButton.Text = "ОТМЕНА"
	noButton.ZIndex = 11
	noButton.Parent = confirmBox

	Theme.Button(noButton, "quiet")

	craftButton.MouseButton1Click:Connect(function()
		if not (slots[1] and slots[2]) then
			return
		end
		confirmLabel.Text = ("Скрестить %s + %s?"):format(Elements[slots[1]].name, Elements[slots[2]].name)
		confirmOverlay.Visible = true
		Theme.Open(confirmBox)
	end)

	noButton.MouseButton1Click:Connect(function()
		confirmOverlay.Visible = false
	end)

	yesButton.MouseButton1Click:Connect(function()
		RequestCraft:FireServer(slots[1], slots[2])
		confirmOverlay.Visible = false
		slots[1], slots[2] = nil, nil
		renderSlot(slotA, nil)
		renderSlot(slotB, nil)
		refreshCraftButton()
	end)


	return {
		-- inventory основной файл заменяет целиком на каждое InventoryChanged (не правит
		-- на месте: производитель сравнивает прежнюю таблицу с новой). Сюда новая
		-- приходит через этот сеттер — ровно в тот же миг, что и раньше.
		setInventory = function(value)
			inventory = value
		end,
		refreshInventoryList = refreshInventoryList,
	}
end
