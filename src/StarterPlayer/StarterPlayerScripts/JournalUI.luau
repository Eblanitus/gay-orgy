-- Журнал главного меню: статистика и три справочника — рецепты, жуки, элементы.
--
-- ВСЁ содержимое берётся из таблиц игры (ReplicatedStorage.Elements / .Enemies / .Recipes /
-- .Levels) и из профиля игрока. Собственных описаний здесь нет ни одного: стоит написать
-- в справочнике хоть одну фразу от себя — и она разойдётся с тем, что реально делает
-- код, при первой же правке баланса. Названия каст — из вики (alchemy_td_enemies_v1.1.md,
-- раздел «Касты»), в самой таблице жуков у каст есть только номера.
--
-- Справочники показывают все записи сразу и помечают, что из этого игрок уже открыл
-- или встречал, а не прячут неоткрытое: правило, что именно скрывать, ни в одном
-- дизайн-документе не записано, а придуманное гаданием прятание ломает справочник
-- как справочник. Отметки открытого при этом настоящие и живут в профиле.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MobileUI = require(script.Parent:WaitForChild("MobileUI"))
local Theme = require(script.Parent:WaitForChild("UITheme"))
local EntityInfo = require(script.Parent:WaitForChild("EntityInfo"))

local Elements = require(ReplicatedStorage:WaitForChild("Elements"))
local Enemies = require(ReplicatedStorage:WaitForChild("Enemies"))
local Recipes = require(ReplicatedStorage:WaitForChild("Recipes"))
local Levels = require(ReplicatedStorage:WaitForChild("Levels"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local ProfileSyncedRemote = Remotes:WaitForChild("ProfileSynced")
local RecipeLearnedRemote = Remotes:WaitForChild("RecipeLearned")

local Journal = {}

-- Подписи свойств, названия каст и обратный поиск рецепта живут в общем модуле EntityInfo:
-- ровно те же таблицы нужны плитке покупки в Лаборатории, а две копии однажды разойдутся.
local CASTE_NAME = EntityInfo.CASTE_NAME
local ENEMY_TRAITS = EntityInfo.ENEMY_TRAITS
local ELEMENT_TRAITS = EntityInfo.ELEMENT_TRAITS
local traitsOf = EntityInfo.Traits
local num = EntityInfo.Number


-- ============ Собранные один раз списки ============


local function elementName(key)
	local element = Elements[key]
	return element and element.name or tostring(key)
end

local function elementColor(key)
	local element = Elements[key]
	return element and element.color or Theme.color.steel
end

-- Элементы по тирам, внутри тира — по алфавиту. Собирается один раз на загрузке
-- модуля: порядок pairs в Luau не закреплён, и без сортировки справочник выглядел бы
-- перетасованным при каждом заходе в игру.
local elementOrder = {}
for key in Elements do
	table.insert(elementOrder, key)
end
table.sort(elementOrder, function(a, b)
	local ea, eb = Elements[a], Elements[b]
	if ea.tier ~= eb.tier then
		return ea.tier < eb.tier
	end
	return ea.name < eb.name
end)

-- Жуки по кастам. Группируем по полю caste самого жука, а не по Enemies.ByCaste:
-- в ByCaste лежат те, кого выбирают волны, а в справочнике должны быть все, включая
-- тех, кто появляется не из волны (личинка из кокона, королева).
local enemyOrder = {}
for key, entry in Enemies do
	if type(entry) == "table" and entry.name then
		table.insert(enemyOrder, key)
	end
end
table.sort(enemyOrder, function(a, b)
	local ea, eb = Enemies[a], Enemies[b]
	local ca, cb = ea.caste or 99, eb.caste or 99
	if ca ~= cb then
		return ca < cb
	end
	return ea.name < eb.name
end)

-- Рецепты по тиру результата: список читается как дерево сверху вниз,
-- а не как алфавитный список без порядка изучения.
local recipeOrder = {}
for _, recipe in Recipes.List do
	table.insert(recipeOrder, recipe)
end
table.sort(recipeOrder, function(a, b)
	local ra, rb = Elements[a.result], Elements[b.result]
	local ta = ra and ra.tier or 99
	local tb = rb and rb.tier or 99
	if ta ~= tb then
		return ta < tb
	end
	return elementName(a.result) < elementName(b.result)
end)

local BASE_ELEMENTS = 0
for _, key in elementOrder do
	if Elements[key].tier == 0 then
		BASE_ELEMENTS += 1
	end
end

-- ============ Профиль игрока ============

-- Журнал сам ничего у сервера не спрашивает — слушает те же события, что и остальной
-- интерфейс. Собственный запрос означал бы второй источник правды о том же самом,
-- и однажды они бы разошлись.
local profile = {
	plutonium = 0,
	levels = {},
	recipes = {},
	killedTypes = {},
}

local watchers = {}

local function profileChanged()
	for _, fn in watchers do
		task.spawn(fn)
	end
end

ProfileSyncedRemote.OnClientEvent:Connect(function(plutonium, levels, recipes, killedTypes)
	profile.plutonium = plutonium or 0
	profile.levels = levels or {}
	profile.recipes = recipes or {}
	profile.killedTypes = killedTypes or {}
	profileChanged()
end)

-- Рецепт, открытый посреди забега: профиль целиком придёт только при начислении
-- плутония или при следующем входе, а справочник должен пометить элемент открытым
-- сразу — игрок только что его скрестил.
RecipeLearnedRemote.OnClientEvent:Connect(function(resultKey)
	if type(resultKey) == "string" then
		profile.recipes[resultKey] = true
		profileChanged()
	end
end)

local function elementKnown(key)
	-- Базовые четыре покупаются за материю и рецептом не открываются вовсе
	-- (см. PlayerData: «базовые элементы покупаются за материю сами, это не рецепт»).
	local element = Elements[key]
	if element and element.tier == 0 then
		return true
	end
	return profile.recipes[key] == true
end

local function countKeys(t)
	local n = 0
	for _ in t do
		n += 1
	end
	return n
end

-- Сводка прогресса для тех, кто рисует её вне журнала (главное меню). Те же самые
-- числа, что и на вкладке «Статистика», и считаются они здесь же: второй счётчик
-- в MainMenu однажды разошёлся бы с этим при первой же правке таблиц.
function Journal.Progress()
	local known = countKeys(profile.recipes)

	local met = 0
	for key in profile.killedTypes do
		if Enemies[key] then
			met += 1
		end
	end

	local cleared, unlocked, total = 0, 0, 0
	for number in Levels do
		total += 1
		local data = profile.levels[number]
		if data and data.unlocked then
			unlocked += 1
			if data.completed then
				cleared += 1
			end
		end
	end

	return {
		plutonium = profile.plutonium,
		recipes = known,
		recipesTotal = #recipeOrder,
		-- Базовые четыре рецептом не открываются, но доступны всегда — так же,
		-- как считает строка «Элементов доступно» в buildStats.
		elements = known + BASE_ELEMENTS,
		elementsTotal = #elementOrder,
		enemies = met,
		enemiesTotal = #enemyOrder,
		levelsCleared = cleared,
		levelsUnlocked = unlocked,
		levelsTotal = total,
	}
end

-- Подписка на обновление профиля — тот же список, по которому обновляются сами
-- справочники. Отписки нет намеренно: меню живёт всю сессию и никогда не сносится.
function Journal.OnChanged(fn)
	table.insert(watchers, fn)
	fn()
end

-- ============ Сборщики ============

local mobile = MobileUI.isMobile
local CELL_H = mobile and 78 or 74
local CELL_W = mobile and 260 or 330
local NAME_SIZE = mobile and 14 or 15
local LINE_SIZE = mobile and 11 or 12

local function line(parent, y, height, size, color, align)
	local label = Instance.new("TextLabel")
	label.Position = UDim2.new(0, 0, 0, y)
	label.Size = UDim2.new(1, 0, 0, height)
	label.BackgroundTransparency = 1
	label.FontFace = Theme.font.body
	label.TextSize = size
	label.TextXAlignment = align or Enum.TextXAlignment.Left
	label.TextColor3 = color
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Text = ""
	label.Parent = parent
	return label
end

-- Ячейка справочника: три строки на корпусе цвета самой сущности — тот же язык,
-- что у списков инвентаря и Лаборатории (Theme.ElementFill), а не свой вид для журнала.
-- Неоткрытое не прячется, а гаснет через dim — тот же признак «есть, но не взято»,
-- что и у невыбранных кнопок панели стройки.
local function makeCell(parent, order)
	local cell = Instance.new("TextButton")
	cell.LayoutOrder = order
	cell.Text = ""
	cell.AutoButtonColor = false
	cell.Parent = parent

	local inner = Instance.new("Frame")
	inner.Name = "Inner"
	inner.Parent = cell

	local top = mobile and 21 or 20
	local nameLabel = line(inner, 0, top, NAME_SIZE, Theme.color.text)
	nameLabel.FontFace = Theme.font.strong
	nameLabel.Size = UDim2.new(1, -64, 0, top)

	local markLabel = line(inner, 0, top, LINE_SIZE, Theme.color.textMute, Enum.TextXAlignment.Right)
	markLabel.AnchorPoint = Vector2.new(1, 0)
	markLabel.Position = UDim2.new(1, 0, 0, 2)
	markLabel.Size = UDim2.new(0, 62, 0, top)

	local statLabel = line(inner, top + 2, 17, LINE_SIZE, Theme.color.textDim)
	local traitLabel = line(inner, top + 20, 17, LINE_SIZE, Theme.color.textMute)

	return {
		cell = cell,
		inner = inner,
		name = nameLabel,
		mark = markLabel,
		stat = statLabel,
		trait = traitLabel,
	}
end

-- Цвет и геометрия ячейки задаются отдельно от создания: при смене профиля ячейка
-- перекрашивается, а не пересобирается: семьдесят ячеек заново на каждое начисление
-- плутония — видимый рывок на телефоне.
-- element — ключ элемента для его узора; у врагов нет. У неоткрытого узора нет.
local function paintCell(parts, color, known, element)
	Theme.ElementFill(parts.cell, color, { dim = not known, element = known and element or nil })
	Theme.Inner(parts.inner)
	parts.name.TextColor3 = known and Theme.color.text or Theme.color.textDim
end

local function makeScroll(parent, name)
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = name
	scroll.Size = UDim2.new(1, 0, 1, 0)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 4
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.Visible = false
	scroll.Parent = parent
	Theme.Scroller(scroll)
	Theme.DragScroll(scroll)
	return scroll
end

-- ============ Сам журнал ============

-- onStatus — кому сообщить подсказку текущей вкладки. Строка состояния живёт внизу рамки
-- меню и журналу не принадлежит; заводить вторую внутри вкладок значило бы две подсказки
-- одна над другой на одном экране.
function Journal.Mount(parent, onStatus)
	local TAB_H = mobile and 34 or 38

	local page = Instance.new("Frame")
	page.Name = "JournalPage"
	page.Size = UDim2.new(1, 0, 1, 0)
	page.BackgroundTransparency = 1
	page.BorderSizePixel = 0
	page.Visible = false
	page.Parent = parent

	local tabsRow = Instance.new("Frame")
	tabsRow.Name = "Tabs"
	tabsRow.Size = UDim2.new(1, 0, 0, TAB_H)
	tabsRow.BackgroundTransparency = 1
	tabsRow.BorderSizePixel = 0
	tabsRow.Parent = page

	local tabsLayout = Instance.new("UIListLayout")
	tabsLayout.FillDirection = Enum.FillDirection.Horizontal
	tabsLayout.Padding = UDim.new(0, 6)
	tabsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	tabsLayout.Parent = tabsRow

	local content = Instance.new("Frame")
	content.Name = "Content"
	content.Position = UDim2.new(0, 0, 0, TAB_H + 10)
	content.Size = UDim2.new(1, 0, 1, -(TAB_H + 10))
	content.BackgroundTransparency = 1
	content.BorderSizePixel = 0
	content.Parent = page

	-- Списки собираются при первом открытии своей вкладки, а не при сборке меню:
	-- семьдесят один элемент плюс двадцать девять жуков плюс шестьдесят семь рецептов —
	-- это полторы сотни ячеек в момент входа в игру, ради экрана, который могут
	-- и не открыть.
	local built = {}
	local refreshers = {}
	local grids = {}

	local function addRefresher(tab, fn)
		refreshers[tab] = refreshers[tab] or {}
		table.insert(refreshers[tab], fn)
	end

	-- ---- Статистика ----

	local statsScroll = makeScroll(content, "StatsList")

	local statsLayout = Instance.new("UIListLayout")
	statsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	statsLayout.Padding = UDim.new(0, 4)
	statsLayout.Parent = statsScroll

	-- Строка статистики ограничена по ширине. Во всю ширину рамки подпись и число
	-- разносит на тысячу пикселей, и они читаются как два несвязных списка — та же
	-- причина, по которой у самой рамки есть потолок ширины (MainMenu.FRAME_MAX_W).
	local STATS_W = mobile and 420 or 560

	local function statsWidth(gui)
		local limit = Instance.new("UISizeConstraint")
		limit.MaxSize = Vector2.new(STATS_W, math.huge)
		limit.Parent = gui
		return gui
	end

	local function statsSection(order, caption)
		local label = Instance.new("TextLabel")
		label.LayoutOrder = order
		label.Size = UDim2.new(1, -8, 0, 26)
		label.TextSize = mobile and 11 or 12
		label.Parent = statsScroll
		Theme.Section(label, caption)
		return statsWidth(label)
	end

	-- Строка показания: подпись слева, значение справа, между ними — пусто.
	-- Два отдельных TextLabel, а не один с RichText: число должно стоять в колонку
	-- со всеми остальными, а при склейке в одну строку его место зависело бы
	-- от длины подписи.
	local function statsRow(order)
		local row = Instance.new("Frame")
		row.LayoutOrder = order
		row.Size = UDim2.new(1, -8, 0, mobile and 24 or 25)
		row.BackgroundTransparency = 1
		row.BorderSizePixel = 0
		row.Parent = statsScroll
		statsWidth(row)

		local caption = line(row, 0, mobile and 24 or 25, mobile and 12 or 13, Theme.color.textDim)
		caption.Size = UDim2.new(1, -130, 1, 0)

		local value = line(row, 0, mobile and 24 or 25, mobile and 13 or 14, Theme.color.accent, Enum.TextXAlignment.Right)
		value.AnchorPoint = Vector2.new(1, 0)
		value.Position = UDim2.new(1, 0, 0, 0)
		value.Size = UDim2.new(0, 128, 1, 0)
		value.FontFace = Theme.font.strong

		return caption, value
	end

	local function buildStats()
		statsSection(1, "Профиль")

		local plutoniumCap, plutoniumVal = statsRow(2)
		plutoniumCap.Text = Theme.Caps("Плутоний")
		plutoniumVal.TextColor3 = Theme.color.energy

		local recipeCap, recipeVal = statsRow(3)
		recipeCap.Text = Theme.Caps("Рецептов открыто")

		local elementCap, elementVal = statsRow(4)
		elementCap.Text = Theme.Caps("Элементов доступно")

		local enemyCap, enemyVal = statsRow(5)
		enemyCap.Text = Theme.Caps("Типов жуков встречено")

		statsSection(6, "Уровни")

		-- Строка на каждый уровень из таблицы, а не только на открытые: в ТЗ лобби
		-- прямо сказано — «непройденные и неоткрытые видны, но недоступны».
		local levelNumbers = {}
		for number in Levels do
			table.insert(levelNumbers, number)
		end
		table.sort(levelNumbers)

		local levelRows = {}
		for i, number in levelNumbers do
			local cap, val = statsRow(6 + i)
			cap.Text = Theme.Caps(("%d. %s"):format(number, Levels[number].name or "?"))
			levelRows[number] = val
		end

		local function refresh()
			plutoniumVal.Text = tostring(profile.plutonium)

			local known = countKeys(profile.recipes)
			recipeVal.Text = ("%d / %d"):format(known, #recipeOrder)
			elementVal.Text = ("%d / %d"):format(known + BASE_ELEMENTS, #elementOrder)

			local met = 0
			for key in profile.killedTypes do
				if Enemies[key] then
					met += 1
				end
			end
			enemyVal.Text = ("%d / %d"):format(met, #enemyOrder)

			for number, val in levelRows do
				local data = profile.levels[number]
				if not data or not data.unlocked then
					val.Text = Theme.Caps("закрыт")
					val.TextColor3 = Theme.color.textMute
				elseif data.completed then
					val.Text = Theme.Caps(("пройден · волна %d"):format(data.bestWave or 0))
					val.TextColor3 = Theme.color.action
				else
					val.Text = Theme.Caps(("волна %d"):format(data.bestWave or 0))
					val.TextColor3 = Theme.color.accent
				end
			end
		end

		addRefresher("stats", refresh)
		refresh()
	end

	-- ---- Справочники на сетке ----

	local recipesScroll = makeScroll(content, "RecipesList")
	local enemiesScroll = makeScroll(content, "EnemiesList")
	local elementsScroll = makeScroll(content, "ElementsList")

	local function buildRecipes()
		grids.recipes = Theme.Grid(recipesScroll, CELL_H - 22, CELL_W, 8)
		for index, recipe in recipeOrder do
			local parts = makeCell(recipesScroll, index)
			local result = Elements[recipe.result]
			parts.name.Text = Theme.Caps(elementName(recipe.result))
			parts.mark.Text = result and ("Т%d"):format(result.tier) or ""
			parts.stat.Text = Theme.Caps(("%s + %s"):format(elementName(recipe.a), elementName(recipe.b)))
			-- Третьей строки у рецепта нет: ячейка ниже остальных на её высоту.
			parts.trait:Destroy()

			local function refresh()
				local known = elementKnown(recipe.result)
				paintCell(parts, elementColor(recipe.result), known, recipe.result)
				parts.mark.TextColor3 = known and Theme.color.accent or Theme.color.textMute
			end
			addRefresher("recipes", refresh)
			refresh()
		end
	end

	local function buildEnemies()
		grids.enemies = Theme.Grid(enemiesScroll, CELL_H, CELL_W, 8)
		for index, key in enemyOrder do
			local enemy = Enemies[key]
			local parts = makeCell(enemiesScroll, index)
			parts.name.Text = Theme.Caps(enemy.name)
			parts.mark.Text = "HP " .. num(enemy.hp)

			local casteName = CASTE_NAME[enemy.caste] or "прочие"
			parts.stat.Text = Theme.Caps(("%s · скор %s · материя %s"):format(
				casteName, num(enemy.speed), num(enemy.matter)
			))

			local traits = traitsOf(enemy, ENEMY_TRAITS)
			parts.trait.Text = #traits > 0 and Theme.Caps(table.concat(traits, " · ")) or ""

			local function refresh()
				local met = profile.killedTypes[key] == true
				paintCell(parts, enemy.color or Theme.color.steel, met)
				parts.mark.TextColor3 = met and Theme.color.danger or Theme.color.textMute
			end
			addRefresher("enemies", refresh)
			refresh()
		end
	end

	local function buildElements()
		grids.elements = Theme.Grid(elementsScroll, CELL_H, CELL_W, 8)
		for index, key in elementOrder do
			local element = Elements[key]
			local parts = makeCell(elementsScroll, index)
			parts.name.Text = Theme.Caps(element.name)
			parts.mark.Text = ("ТИР %d"):format(element.tier)

			local recipe = EntityInfo.RecipeOf(key)
			parts.stat.Text = recipe
				and Theme.Caps(("%s + %s"):format(elementName(recipe.a), elementName(recipe.b)))
				or Theme.Caps("базовый · покупается за материю")

			local traits = traitsOf(element, ELEMENT_TRAITS)
			parts.trait.Text = #traits > 0 and Theme.Caps(table.concat(traits, " · ")) or ""

			local function refresh()
				local known = elementKnown(key)
				paintCell(parts, element.color, known, key)
				parts.mark.TextColor3 = known and Theme.color.accent or Theme.color.textMute
			end
			addRefresher("elements", refresh)
			refresh()
		end
	end

	-- ---- Вкладки ----

	local TABS = {
		{ key = "stats", name = "Статистика", frame = statsScroll, build = buildStats,
			status = "Сводка по профилю и прогресс по уровням" },
		{ key = "recipes", name = "Рецепты", frame = recipesScroll, build = buildRecipes,
			status = "Яркие — уже открыты, приглушённые — ещё нет" },
		{ key = "enemies", name = "Жуки", frame = enemiesScroll, build = buildEnemies,
			status = "Яркие — уже встречались в забегах" },
		{ key = "elements", name = "Элементы", frame = elementsScroll, build = buildElements,
			status = "Яркие — доступны к крафту, приглушённые — нет" },
	}

	local buttons = {}
	local current = nil
	local statusText = TABS[1].status

	local function select(key)
		for _, tab in TABS do
			local on = tab.key == key
			Theme.Button(buttons[tab.key], on and "active" or "ghost")
			tab.frame.Visible = on
			if on then
				statusText = tab.status
				if not built[key] then
					built[key] = true
					tab.build()
				end
			end
		end
		current = key
		if onStatus then
			onStatus(statusText)
		end
	end

	for index, tab in TABS do
		local button = Instance.new("TextButton")
		button.Name = tab.key
		button.LayoutOrder = index
		-- Четыре вкладки делят ширину поровну в долях, а не в пикселях: иначе на телефоне
		-- в портрете последняя уезжает за край экрана.
		button.Size = UDim2.new(0.25, -5, 1, 0)
		button.FontFace = Theme.font.strong
		button.TextSize = mobile and 11 or 13
		button.TextTruncate = Enum.TextTruncate.AtEnd
		button.Text = Theme.Caps(tab.name)
		button.Parent = tabsRow
		Theme.Button(button, "ghost")
		buttons[tab.key] = button

		button.MouseButton1Click:Connect(function()
			select(tab.key)
		end)
	end

	-- Профиль поменялся — перерисовываются только те вкладки, которые уже собраны:
	-- несобранная всё равно возьмёт свежий профиль при сборке.
	table.insert(watchers, function()
		for key, list in refreshers do
			if built[key] then
				for _, fn in list do
					fn()
				end
			end
		end
	end)

	-- Сетка пересчитывается при повороте телефона и изменении окна на ПК: число колонок
	-- считается от фактической ширины, а она меняется.
	MobileUI.OnViewportChanged(function()
		for _, layout in grids do
			Theme.GridFit(layout)
		end
	end)

	select("stats")

	return {
		frame = page,
		Open = function()
			page.Visible = true
			-- При каждом открытии сетка подгоняется заново: при первой сборке список ещё
			-- не был показан, и AbsoluteSize у него нулевой — Theme.GridFit в таком случае
			-- отдаёт одну колонку, и без повторного счёта так бы и осталось.
			task.defer(function()
				for _, layout in grids do
					Theme.GridFit(layout)
				end
			end)
		end,
		Close = function()
			page.Visible = false
		end,
		Status = function()
			return statusText
		end,
		Select = select,
		Current = function()
			return current
		end,
	}
end

return Journal
