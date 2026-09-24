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
	content.Size = UDim2.new(1, 0, 1, 0)
	content.BackgroundTransparency = 1
	content.BorderSizePixel = 0
	content.Parent = page

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

		addRefresher(refresh)
		refresh()
	end

	local STATUS = "Сводка по профилю и прогресс по уровням. Рецепты, жуки и элементы — в справочнике лаборатории"

	statsScroll.Visible = true
	buildStats()

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
