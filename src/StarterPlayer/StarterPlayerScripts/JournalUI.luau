-- Журнал главного меню: статистика профиля — плутоний, открытые рецепты, встреченные
-- жуки, уровни.
--
-- Справочники рецептов, жуков и элементов отсюда переехали в справочник лаборатории
-- (CraftingReference: разделы «Жуки», «Карта», «Элементы») — решение автора: в меню
-- остаётся статистика, подробные описания — у доски-справочника.
--
-- Числа берутся из таблиц игры (ReplicatedStorage.Elements / .Enemies / .Recipes / .Levels)
-- и из профиля игрока — своего счётчика здесь нет.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MobileUI = require(script.Parent:WaitForChild("MobileUI"))
local Theme = require(script.Parent:WaitForChild("UITheme"))

local Elements = require(ReplicatedStorage:WaitForChild("Elements"))
local Enemies = require(ReplicatedStorage:WaitForChild("Enemies"))
local Recipes = require(ReplicatedStorage:WaitForChild("Recipes"))
local Levels = require(ReplicatedStorage:WaitForChild("Levels"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local ProfileSyncedRemote = Remotes:WaitForChild("ProfileSynced")
local RecipeLearnedRemote = Remotes:WaitForChild("RecipeLearned")
local ProfileStatsRemote = Remotes:WaitForChild("ProfileStats")

local Journal = {}

-- ============ Собранные один раз списки ============


local function elementName(key)
	local element = Elements[key]
	return element and element.name or tostring(key)
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
	-- Статистика (ServerScriptService.ProfileStats): счёт убийств и счётчики журнала.
	elementKills = {},
	enemyKills = {},
	stats = {},
	enemySeen = {},
	elementCrafted = {},
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

ProfileStatsRemote.OnClientEvent:Connect(function(elementKills, enemyKills, stats, enemySeen, elementCrafted)
	profile.enemySeen = type(enemySeen) == "table" and enemySeen or {}
	profile.elementCrafted = type(elementCrafted) == "table" and elementCrafted or {}
	profile.elementKills = type(elementKills) == "table" and elementKills or {}
	profile.enemyKills = type(enemyKills) == "table" and enemyKills or {}
	profile.stats = type(stats) == "table" and stats or {}
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
	local page = Instance.new("Frame")
	page.Name = "JournalPage"
	page.Size = UDim2.new(1, 0, 1, 0)
	page.BackgroundTransparency = 1
	page.BorderSizePixel = 0
	page.Visible = false
	page.Parent = parent

	local content = Instance.new("Frame")
	content.Name = "Content"
	local TAB_H = mobile and MobileUI.MIN_TAP or 34
	content.Position = UDim2.new(0, 0, 0, TAB_H + 8)
	content.Size = UDim2.new(1, 0, 1, -(TAB_H + 8))
	content.BackgroundTransparency = 1
	content.BorderSizePixel = 0
	content.Parent = page

	-- Вкладки: общая сводка, жуки, элементы — у каждой свой список.
	local tabBar = Instance.new("Frame")
	tabBar.Name = "Tabs"
	tabBar.Size = UDim2.new(1, 0, 0, TAB_H)
	tabBar.BackgroundTransparency = 1
	tabBar.Parent = page
	local tabLayout = Instance.new("UIListLayout")
	tabLayout.FillDirection = Enum.FillDirection.Horizontal
	tabLayout.Padding = UDim.new(0, 6)
	tabLayout.Parent = tabBar

	local refreshers = {}

	local function addRefresher(fn)
		table.insert(refreshers, fn)
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
	local STATS_W = mobile and 480 or 640
	local ROW_H = mobile and 30 or 32

	local function statsWidth(gui)
		local limit = Instance.new("UISizeConstraint")
		limit.MaxSize = Vector2.new(STATS_W, math.huge)
		limit.Parent = gui
		return gui
	end

	local function statsSection(order, caption, parent)
		local label = Instance.new("TextLabel")
		label.LayoutOrder = order
		label.Size = UDim2.new(1, -8, 0, 34)
		label.TextSize = mobile and 15 or 16
		label.Parent = parent or statsScroll
		Theme.Section(label, caption)
		return statsWidth(label)
	end

	-- Строка показания: подпись слева, значение справа, между ними — пусто.
	-- Два отдельных TextLabel, а не один с RichText: число должно стоять в колонку
	-- со всеми остальными, а при склейке в одну строку его место зависело бы
	-- от длины подписи.
	local function statsRow(order, parent)
		local row = Instance.new("Frame")
		row.LayoutOrder = order
		row.Size = UDim2.new(1, -8, 0, ROW_H)
		row.BackgroundTransparency = 1
		row.BorderSizePixel = 0
		row.Parent = parent or statsScroll
		statsWidth(row)

		local caption = line(row, 0, ROW_H, mobile and 16 or 18, Theme.color.textDim)
		caption.Size = UDim2.new(1, -170, 1, 0)

		local value = line(row, 0, ROW_H, mobile and 17 or 19, Theme.color.accent, Enum.TextXAlignment.Right)
		value.AnchorPoint = Vector2.new(1, 0)
		value.Position = UDim2.new(1, 0, 0, 0)
		value.Size = UDim2.new(0, 168, 1, 0)
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

		-- ---- Бой, забеги, лаборатория (ProfileStats) ----
		local function counter(order, caption)
			local cap, val = statsRow(order)
			cap.Text = Theme.Caps(caption)
			return val
		end

		statsSection(10, "Бой")
		local killsVal = counter(11, "Жуков убито")

		local favouriteVal = counter(12, "Любимый элемент")

		statsSection(50, "Забеги")
		local runsVal = counter(51, "Забегов начато")
		local winsVal = counter(52, "Уровней пройдено")
		local defeatsVal = counter(53, "Поражений")
		local wavesVal = counter(54, "Волн пройдено")
		local timeVal = counter(55, "Время в игре")

		statsSection(60, "Лаборатория")
		local craftsVal = counter(61, "Скрещиваний")
		local towersVal = counter(62, "Построек")
		local earnedVal = counter(63, "Материи получено")
		local spentVal = counter(64, "Материи потрачено")

		local function playTime(seconds)
			local minutes = math.floor(seconds / 60)
			if minutes < 60 then
				return ("%d мин"):format(minutes)
			end
			return ("%d ч %d мин"):format(minutes // 60, minutes % 60)
		end

		local function refreshCounters()
			local total = 0
			for key, count in profile.enemyKills do
				if Enemies[key] then
					total += count
				end
			end
			killsVal.Text = tostring(total)

			local best, bestCount = nil, 0
			for key, count in profile.elementKills do
				if Elements[key] and count > bestCount then
					best, bestCount = key, count
				end
			end
			favouriteVal.Text = best and Theme.Caps(Elements[best].name) or "—"

			local stats = profile.stats
			runsVal.Text = tostring(stats.runs or 0)
			winsVal.Text = tostring(stats.wins or 0)
			defeatsVal.Text = tostring(stats.defeats or 0)
			wavesVal.Text = tostring(stats.waves or 0)
			timeVal.Text = Theme.Caps(playTime(stats.playTime or 0))
			craftsVal.Text = tostring(stats.crafts or 0)
			towersVal.Text = tostring(stats.towers or 0)
			earnedVal.Text = tostring(math.floor(stats.matterEarned or 0))
			spentVal.Text = tostring(math.floor(stats.matterSpent or 0))
		end
		addRefresher(refreshCounters)
		refreshCounters()

		statsSection(200, "Уровни")

		-- Строка на каждый уровень из таблицы, а не только на открытые: в ТЗ лобби
		-- прямо сказано — «непройденные и неоткрытые видны, но недоступны».
		local levelNumbers = {}
		for number in Levels do
			table.insert(levelNumbers, number)
		end
		table.sort(levelNumbers)

		local levelRows = {}
		for i, number in levelNumbers do
			local cap, val = statsRow(200 + i)
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

		addRefresher(refresh)
		refresh()
	end

	local STATUS = "Сводка по профилю и прогресс по уровням. Рецепты, жуки и элементы — в справочнике лаборатории"

	statsScroll.Visible = true
	buildStats()

	-- ---- Вкладки «Жуки» и «Элементы»: по строке-разделу на каждого, без карточек ----
	-- Список пересобирается целиком на каждое обновление профиля: строк — десятки, а
	-- обновление приходит не чаще раза в пару секунд.
	local function entityList(name, order, show)
		local scroll = makeScroll(content, name)
		local layout = Instance.new("UIListLayout")
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Padding = UDim.new(0, 4)
		layout.Parent = scroll
		addRefresher(function()
			for _, child in scroll:GetChildren() do
				if child:IsA("GuiObject") then
					child:Destroy()
				end
			end
			local shown = 0
			for _, key in order do
				local rows = show(key)
				if rows then
					shown += 1
					local base = shown * 10
					statsSection(base, rows.name, scroll)
					for i, row in rows do
						local cap, val = statsRow(base + i, scroll)
						cap.Text = Theme.Caps(row[1])
						val.Text = tostring(row[2])
					end
				end
			end
			if shown == 0 then
				local cap = statsRow(1, scroll)
				cap.Text = Theme.Caps("пока пусто")
			end
		end)
		return scroll
	end

	local enemiesScroll = entityList("EnemiesList", enemyOrder, function(key)
		local seen = profile.enemySeen[key] or 0
		local kills = profile.enemyKills[key] or 0
		if seen == 0 and kills == 0 then
			return nil
		end
		return { name = Enemies[key].name, { "Встречено", seen }, { "Убито", kills } }
	end)

	local elementsScroll = entityList("ElementsList", elementOrder, function(key)
		local kills = profile.elementKills[key] or 0
		local crafted = profile.elementCrafted[key] or 0
		if kills == 0 and crafted == 0 then
			return nil
		end
		return { name = Elements[key].name, { "Жуков добито", kills }, { "Создано скрещиванием", crafted } }
	end)

	local TABS = {
		{ caption = "Общее", frame = statsScroll },
		{ caption = "Жуки", frame = enemiesScroll },
		{ caption = "Элементы", frame = elementsScroll },
	}
	local buttons = {}
	local function selectTab(index)
		for i, tab in TABS do
			tab.frame.Visible = i == index
			Theme.Button(buttons[i], i == index and "active" or "ghost")
		end
	end
	for i, tab in TABS do
		local button = Instance.new("TextButton")
		button.Size = UDim2.new(1 / #TABS, -4, 1, 0)
		button.FontFace = Theme.font.strong
		button.TextSize = mobile and 15 or 16
		button.Text = Theme.Caps(tab.caption)
		button.Parent = tabBar
		buttons[i] = button
		button.MouseButton1Click:Connect(function()
			selectTab(i)
		end)
	end
	selectTab(1)
	for _, fn in refreshers do
		fn()
	end

	-- Профиль поменялся — статистика перерисовывается.
	table.insert(watchers, function()
		for _, fn in refreshers do
			fn()
		end
	end)

	return {
		frame = page,
		Open = function()
			page.Visible = true
			if onStatus then
				onStatus(STATUS)
			end
		end,
		Close = function()
			page.Visible = false
		end,
		Status = function()
			return STATUS
		end,
		-- Вкладок в журнале больше нет; оставлено для прежних вызовов.
		Select = function() end,
		Current = function()
			return "stats"
		end,
	}
end

return Journal
