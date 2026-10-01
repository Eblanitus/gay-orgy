-- Алхимический стол (#282–#287). Своё окно-монитор, как у производителя и справочника: рамка
-- ReferenceFrame, фон точками, поиск в шапке, режимы в подвале — «Крафт», «Рецепты», «Журнал».
-- Страницы собирают модули TableCraftPage, TableRecipesPage и TableJournalPage. Общее
-- состояние стола (запас, открытые рецепты, несмешиваемые пары, журнал) — таблица T.
--
-- Сервер решает всё сам, как и раньше: стол шлёт RequestCraft и только показывает ответ
-- CraftResult. Модуль — return function(deps), как остальные куски CraftingUI (задача #240).
return function(deps)
	local tabFrames = deps.tabFrames
	local Theme = deps.Theme
	local Elements = deps.Elements
	local Recipes = deps.Recipes
	local root = deps.root
	local gui = deps.gui
	local Remotes = deps.Remotes
	local RequestCraft = deps.RequestCraft

	local ReferenceFrame = require(script.Parent:WaitForChild("ReferenceFrame"))
	local Detail = require(script.Parent:WaitForChild("ReferenceDetail"))
	local Show = require(script.Parent:WaitForChild("ProducerShow"))
	local UISound = require(script.Parent:WaitForChild("UISound"))
	local CraftResult = Remotes:WaitForChild("CraftResult")

	-- Числа стола — здесь, а не в коде страниц.
	local TUNING = {
		batchPause = 0.15, -- пауза между крафтами пачкой, секунды
		batchSize = 5, -- кнопка «×5»
		batchMax = 50, -- «МАКС» за один раз не больше
		journalMax = 60, -- строк в журнале
		bannerTime = 2.6, -- сколько висит «новый рецепт», секунды
		pendingTimeout = 3, -- ответа нет столько секунд — стол снова принимает крафт
	}

	local MODES = {
		{ id = "craft", name = "Крафт" },
		{ id = "recipes", name = "Рецепты" },
		{ id = "journal", name = "Журнал" },
	}
	local window = ReferenceFrame.Build(root, gui, MODES, {
		title = "АЛХИМИЧЕСКИЙ СТОЛ",
		placeholder = "элемент…",
		name = "TableTab",
		backdrop = "dots",
	})
	tabFrames["Крафт"] = window.bookFrame

	local T = {
		Theme = Theme,
		Elements = Elements,
		Recipes = Recipes,
		MobileUI = deps.MobileUI,
		Show = Show,
		UISound = UISound,
		TUNING = TUNING,
		Lower = Detail.Lower,
		glass = window.glass,
		gui = gui,
		root = root,
		inventory = deps.inventory,
		known = deps.knownRecipes,
		failed = {}, -- ключ пары → true: пара уже не смешалась (на эту игру)
		history = {}, -- журнал, свежее первым
		stats = { crafted = 0, found = 0, failed = 0 },
		pending = false, -- запрос ушёл, ответа ещё нет
		total = #Recipes.List,
	}

	function T.pairKey(a, b)
		if a > b then
			a, b = b, a
		end
		return a .. "+" .. b
	end

	function T.count(key)
		return T.inventory[key] or 0
	end

	-- Сколько раз пару можно скрестить из запаса: одинаковые — две штуки на раз.
	function T.times(a, b)
		if a == b then
			return math.floor(T.count(a) / 2)
		end
		return math.min(T.count(a), T.count(b))
	end

	-- Результат пары, только если её рецепт уже открыт: неизвестное стол не выдаёт.
	function T.knownResult(a, b)
		local r = Recipes.Find(a, b)
		return (r and T.known[r]) and r or nil
	end

	function T.isFailed(a, b)
		return T.failed[T.pairKey(a, b)] == true
	end

	function T.knownCount()
		local n = 0
		for _, recipe in Recipes.List do
			if T.known[recipe.result] then
				n += 1
			end
		end
		return n
	end

	function T.matches(key, query)
		return query == "" or string.find(Detail.Lower(Elements[key].name), query, 1, true) ~= nil
	end

	-- Крафт пачкой: n раз подряд, следующий запрос — только после ответа на предыдущий.
	-- Каждый раз сервер проверяет заново, клиент ничего не списывает сам.
	local batch = nil
	local pendingId = 0

	local function send(a, b)
		T.pending = true
		pendingId += 1
		local id = pendingId
		RequestCraft:FireServer(a, b)
		-- Ответ мог не прийти (стол разгрызли, игрок отошёл): стол не должен залипнуть.
		task.delay(TUNING.pendingTimeout, function()
			if T.pending and pendingId == id then
				T.pending = false
				batch = nil
				T.refresh()
			end
		end)
	end

	function T.craft(a, b, n)
		if T.pending then
			return
		end
		batch = { a = a, b = b, left = math.max(0, (n or 1) - 1) }
		send(a, b)
		T.refresh()
	end

	function T.batchLeft()
		return batch and batch.left or 0
	end

	function T.stopBatch()
		batch = nil
	end

	-- ---------- страницы ----------
	local function pageFrame(name)
		local f = Instance.new("Frame")
		f.Name = name
		f.Size = UDim2.fromScale(1, 1)
		f.BackgroundTransparency = 1
		f.Visible = false
		f.Parent = window.screen
		return f
	end

	local craftPage = require(script.Parent:WaitForChild("TableCraftPage"))(T, pageFrame("CraftPage"))
	local recipesPage = require(script.Parent:WaitForChild("TableRecipesPage"))(T, pageFrame("RecipesPage"))
	local journalPage = require(script.Parent:WaitForChild("TableJournalPage"))(T, pageFrame("JournalPage"))
	local pages = { craft = craftPage, recipes = recipesPage, journal = journalPage }

	function T.refresh()
		craftPage.refresh()
		recipesPage.refresh()
	end

	-- ---------- режимы и поиск ----------
	local mode = "craft"
	local unseen = 0 -- записей журнала, которых игрок ещё не видел
	local modeButtons = window.modeButtons
	local searchBox = window.searchBox

	local function badge()
		local b = modeButtons.journal
		b.Text = Theme.Caps("Журнал") .. (unseen > 0 and ("  +" .. unseen) or "")
	end

	local function applySearch()
		pages[mode].filter(Detail.Lower(searchBox.Text))
	end

	local function setMode(id)
		local was = mode
		mode = id
		local from, to = 1, 1
		for index, m in MODES do
			local on = m.id == id
			pages[m.id].frame.Visible = on
			Theme.Button(modeButtons[m.id], on and "active" or "ghost")
			if m.id == was then
				from = index
			end
			if on then
				to = index
			end
		end
		if id == "journal" then
			unseen = 0
		end
		badge()
		applySearch()
		if was ~= id then
			Show.Slide(pages[id].frame, to > from and 1 or -1)
		end
	end
	T.setMode = setMode

	for _, m in MODES do
		modeButtons[m.id].MouseButton1Click:Connect(function()
			setMode(m.id)
		end)
	end
	searchBox:GetPropertyChangedSignal("Text"):Connect(applySearch)

	-- Положить пару на стол из рецептов или журнала.
	function T.fill(a, b)
		craftPage.fill(a, b)
		setMode("craft")
	end

	setMode("craft")

	-- ---------- ответ сервера ----------
	CraftResult.OnClientEvent:Connect(function(ok, result, extra, a, b)
		if typeof(a) ~= "string" or typeof(b) ~= "string" or not Elements[a] or not Elements[b] then
			return
		end
		T.pending = false
		local entry = { ok = ok == true, a = a, b = b, time = os.time() }
		if entry.ok then
			if not Elements[result] then
				return
			end
			entry.result = result
			entry.first = extra == true
			T.stats.crafted += 1
			if entry.first then
				T.stats.found += 1
				T.known[result] = true
			end
		else
			entry.kind = extra
			entry.reason = typeof(result) == "string" and result or ""
			if extra == "nomix" then
				T.failed[T.pairKey(a, b)] = true
				T.stats.failed += 1
			end
		end
		table.insert(T.history, 1, entry)
		if #T.history > TUNING.journalMax then
			table.remove(T.history)
		end
		if mode ~= "journal" then
			unseen += 1
			badge()
		end

		-- Пачка: следующий раз — после паузы, если ещё хватает и окно открыто.
		if batch and batch.a == a and batch.b == b then
			if entry.ok and batch.left > 0 and gui.Enabled and T.times(a, b) > 0 then
				batch.left -= 1
				local mine = batch
				task.delay(TUNING.batchPause, function()
					if batch == mine and not T.pending then
						send(a, b)
						T.refresh()
					end
				end)
			else
				batch = nil
			end
		end

		craftPage.onResult(entry)
		recipesPage.refresh()
		journalPage.refresh()
	end)

	-- Закрыли окно — пачка останавливается.
	gui:GetPropertyChangedSignal("Enabled"):Connect(function()
		if not gui.Enabled then
			batch = nil
			craftPage.closeConfirm()
		end
	end)

	return {
		-- inventory основной файл заменяет целиком на каждое InventoryChanged (не правит
		-- на месте: производитель сравнивает прежнюю таблицу с новой).
		setInventory = function(value)
			T.inventory = value
		end,
		refreshInventoryList = function()
			T.refresh()
		end,
		-- Рецепт открыт (этим игроком или другим): подсказки стола и список рецептов.
		onLearned = function()
			T.refresh()
			journalPage.refresh()
		end,
	}
end
