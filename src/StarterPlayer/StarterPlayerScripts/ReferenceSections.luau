-- Разделы справочника («Жуки», «Карта», «Элементы»), поиск, отклик на открытие, события сервера.
-- Вынесено из CraftingReference.luau (поведение то же): файл был слишком велик, чтобы
-- агент читал его целиком. deps — локальные CraftingReference и модулей до этого; ref — общее
-- изменяемое (см. CraftingReference). Возвращается то, что нужно дальше.
return function(deps)
	local Theme = deps.Theme
	local Elements = deps.Elements
	local gui = deps.gui
	local Remotes = deps.Remotes
	local Detail = deps.Detail
	local Pages = deps.Pages
	local Mastery = deps.Mastery
	local Show = deps.Show
	local UISound = deps.UISound
	local MODES = deps.MODES
	local window = deps.window
	local bookFrame = deps.bookFrame
	local PAGE_SIZE = deps.PAGE_SIZE
	local mapFrame = deps.mapFrame
	local ref = deps.ref
	local nodeGui = deps.nodeGui
	local killed = deps.killed
	local isMet = deps.isMet
	local orbitOpen = deps.orbitOpen
	local killsByElement = deps.killsByElement
	local killsOfEnemy = deps.killsOfEnemy
	local isKnown = deps.isKnown
	local onMap = deps.onMap
	local countOf = deps.countOf
	local isCraftable = deps.isCraftable
	local drawGraph = deps.drawGraph
	local refreshBook = deps.refreshBook

	-- ---------- разделы справочника и поиск ----------

	local pagesFrame = Instance.new("Frame")
	pagesFrame.Name = "Pages"
	pagesFrame.Size = PAGE_SIZE
	pagesFrame.BackgroundTransparency = 1
	pagesFrame.Parent = window.screen

	local pages
	local mode = "map"
	local setMode

	pages = Pages.Mount(pagesFrame, {
		known = isKnown,
		count = countOf,
		craftable = isCraftable,
		met = isMet,
		elementKills = killsByElement,
		enemyKills = killsOfEnemy,
		glass = window.glass,
	})

	MODES[1].frame = pages.enemies.frame
	MODES[2].frame = mapFrame
	MODES[3].frame = pages.elements.frame

	local modeButtons = window.modeButtons
	for _, m in MODES do
		modeButtons[m.id].MouseButton1Click:Connect(function()
			setMode(m.id)
		end)
	end

	-- Поиск по имени — в шапке окна. Ищет только среди открытого: неоткрытое
	-- по имени и так не найти, а подсказка «такой есть» была бы подсказкой рецепта.
	local searchBox = window.searchBox

	-- Первое совпадение на карте — по порядку карты, чтобы Enter вёл всегда к одному и тому же.
	local function mapSearch(text)
		local query = Detail.Lower(text)
		if query == "" or not ref.graph then
			ref.searchHits = nil
			return nil
		end
		ref.searchHits = {}
		local first
		for _, key in ref.graph.keys do
			if isKnown(key) and orbitOpen(key) and string.find(Detail.Lower(Elements[key].name), query, 1, true) then
				ref.searchHits[key] = true
				first = first or key
			end
		end
		return first
	end

	local function applySearch()
		local text = searchBox.Text
		if mode == "map" then
			mapSearch(text)
			if ref.graph then
				ref.repaint()
			end
			return
		end
		local p = mode == "elements" and pages.elements or pages.enemies
		p.filter(text)
	end

	searchBox:GetPropertyChangedSignal("Text"):Connect(applySearch)
	searchBox.FocusLost:Connect(function(enter)
		if not enter or searchBox.Text == "" then
			return
		end
		if mode == "map" then
			local first = mapSearch(searchBox.Text)
			if first then
				if ref.selected ~= first then
					ref.selectNode(first)
				end
				ref.focusOn(first)
			end
		else
			local p = mode == "elements" and pages.elements or pages.enemies
			local first = p.filter(searchBox.Text)
			if first then
				p.show(first)
			end
		end
	end)

	-- Строки статуса у справочника больше нет: окно своё, без общей шапки лаборатории (#269).
	function setMode(id)
		local was = mode
		mode = id
		local from, to = 0, 0
		for index, m in MODES do
			local on = m.id == id
			m.frame.Visible = on
			Theme.Button(modeButtons[m.id], on and "active" or "ghost")
			if m.id == was then
				from = index
			end
			if on then
				to = index
			end
		end
		pagesFrame.Visible = id ~= "map"
		applySearch()
		-- Новый раздел въезжает с той стороны, где его пункт в подвале, — как у производителя.
		if was ~= id then
			Show.Slide(id == "map" and mapFrame or pagesFrame, to > from and 1 or -1)
		end
	end

	setMode("map")

	-- ---------- отклик на открытие (#269) ----------
	-- Открылась ступень карточки или новый рецепт — на пункте раздела «+N», пока раздел
	-- не показан. На показанном разделе свежие ячейки вспыхивают, над ними всплывает, что
	-- открылось, и звучит один «Gain» на всю пачку — как прибавка запаса у производителя.
	-- Всё, что было открыто до входа, свежим не считается: первый счёт убийств
	-- (ProfileStats) и рецепты профиля (ProfileSynced) — только отсчёт.
	local fresh = { enemies = {}, map = {}, elements = {} }
	local statsReady, recipesReady = false, false
	local seenRecipes = {}

	-- Какая ступень открылась между old и new убийств — старшая из перешагнутых.
	local function openedStep(steps, old, new)
		local best, bestNeed = nil, -1
		for step, need in steps do
			if (old or 0) < need and (new or 0) >= need and need > bestNeed then
				best, bestNeed = step, need
			end
		end
		return best
	end

	local function stepCaption(step)
		return Mastery.CAPTION[step] or "открыт"
	end

	local function badge()
		for _, m in MODES do
			local n = 0
			for _ in fresh[m.id] do
				n += 1
			end
			modeButtons[m.id].Text = Theme.Caps(m.name) .. (n > 0 and ("  +" .. n) or "")
		end
	end

	local function showFresh()
		if not (gui.Enabled and bookFrame.Visible) then
			return
		end
		local list = fresh[mode]
		if next(list) == nil then
			return
		end
		if mode == "map" and not ref.graph then
			return -- карта ещё собирается; покажется со следующим входом в раздел
		end
		fresh[mode] = {}
		badge()
		local any = false
		for key, caption in list do
			local target, radius
			if mode == "map" then
				target = nodeGui[key] and nodeGui[key].frame
				radius = 999
			else
				target = pages[mode].cell(key)
				radius = Theme.radius.control
			end
			if target then
				Show.Flash(target, Theme.color.accent, 0.9, radius)
				Show.Float(target, Theme.Caps(caption), Theme.color.accent, 14)
				any = true
			end
		end
		if any then
			UISound.Play("Gain")
		end
	end

	local function markFresh(page, key, caption)
		if ref.codexRevealed then
			return
		end
		fresh[page][key] = caption
		badge()
		-- Пересборка карты и ячеек идёт отложенно (refreshKnowledge, drawGraph в CraftingUI):
		-- вспышка — после неё, иначе легла бы на узел, который тут же заменят.
		task.delay(0.1, showFresh)
	end

	local function onOpen()
		task.defer(showFresh)
	end
	gui:GetPropertyChangedSignal("Enabled"):Connect(onOpen)
	bookFrame:GetPropertyChangedSignal("Visible"):Connect(onOpen)
	for _, m in MODES do
		modeButtons[m.id].MouseButton1Click:Connect(onOpen)
	end

	-- Всё, что зависит от инвентаря и открытого, перерисовывается одним вызовом.
	-- Сколько элементов сейчас на карте: изменилось — карту надо пересобрать, а не
	-- перекрасить (новый элемент на ней ещё не нарисован). Сам счёт ведёт drawGraph.
	local function mapCount()
		local n = 0
		for _, key in ref.graph.keys do
			if onMap(key) then
				n += 1
			end
		end
		return n
	end

	local function refreshKnowledge()
		if ref.graph then
			local n = mapCount()
			if n ~= ref.drawnCount then
				drawGraph()
			else
				ref.repaint()
			end
		end
		refreshBook()
		pages.elements.refresh()
		pages.enemies.refresh()
	end

	-- Обработчики CraftingUI обновляют knownRecipes раньше или позже этого — порядок
	-- подписчиков не закреплён, поэтому перерисовка отложена до конца кадра событий.
	Remotes:WaitForChild("RecipeLearned").OnClientEvent:Connect(function(resultKey)
		task.defer(refreshKnowledge)
		-- Сервер досылает при входе все известные рецепты: свежий — только ещё не виденный.
		if type(resultKey) == "string" and not seenRecipes[resultKey] then
			seenRecipes[resultKey] = true
			if recipesReady then
				if onMap(resultKey) then
					markFresh("map", resultKey, "новый")
				end
				markFresh("elements", resultKey, "открыт")
			end
		end
	end)
	Remotes:WaitForChild("EnemiesRevealed").OnClientEvent:Connect(function()
		ref.codexRevealed = true
		-- CODEX открывает всё сразу: сотня вспышек ничего бы не сказала.
		for _, list in fresh do
			table.clear(list)
		end
		badge()
		refreshKnowledge()
	end)
	-- Перерисовка — только когда у кого-то открылась новая ступень: счёт приходит раз
	-- в пару секунд, а карточка с крутящимся жуком не должна мигать на каждое убийство.
	Remotes:WaitForChild("ProfileStats").OnClientEvent:Connect(function(byElement, byEnemy)
		if type(byElement) ~= "table" or type(byEnemy) ~= "table" then
			return
		end
		local changed = false
		-- Первое убийство жука открывает его в «Жуках», даже если killedTypes не дошёл до клиента.
		local newlyMet = false
		for key, count in byEnemy do
			if count > 0 and (ref.enemyKills[key] or 0) == 0 then
				newlyMet = true
			end
		end
		for key, count in byElement do
			if Mastery.Level(Mastery.ELEMENT, count) ~= Mastery.Level(Mastery.ELEMENT, ref.elementKills[key]) then
				changed = true
				local step = statsReady and openedStep(Mastery.ELEMENT, ref.elementKills[key], count)
				if step then
					markFresh("elements", key, stepCaption(step))
				end
			end
		end
		for key, count in byEnemy do
			if Mastery.Level(Mastery.ENEMY, count) ~= Mastery.Level(Mastery.ENEMY, ref.enemyKills[key]) then
				changed = true
				local step = statsReady and openedStep(Mastery.ENEMY, ref.enemyKills[key], count)
				if step then
					markFresh("enemies", key, stepCaption(step))
				end
			end
		end
		statsReady = true
		ref.elementKills, ref.enemyKills = byElement, byEnemy
		if changed then
			task.defer(refreshKnowledge)
		elseif newlyMet then
			task.defer(function()
				pages.enemies.refresh()
			end)
		end
	end)
	-- Профиль досылается сервером по запросу: событие при загрузке могло прийти раньше этого окна.
	Remotes:WaitForChild("RequestProfile"):FireServer()
	Remotes:WaitForChild("ProfileSynced").OnClientEvent:Connect(function(_plutonium, _levels, recipes, killedTypes)
		if type(recipes) == "table" then
			for key in recipes do
				seenRecipes[key] = true
			end
			recipesReady = true
		end
		if type(killedTypes) == "table" then
			table.clear(killed)
			for key, value in killedTypes do
				killed[key] = value == true
			end
			task.defer(function()
				pages.enemies.refresh()
			end)
		end
	end)

	return {
		refreshKnowledge = refreshKnowledge,
	}
end
