-- Панель: фон-соты и сцены, точки, скобки, перетаскивание списков, Theme.Panel
-- Вынесено из UITheme.luau без изменений кода (задача #240): файл был слишком
-- велик, чтобы агент читал его целиком. deps — локальные основного файла, которые нужны
-- этому куску; возвращается то, что основной файл использует дальше.
return function(deps)
	local Theme = deps.Theme
	local Settings = deps.Settings
	local RunService = deps.RunService
	local UserInputService = deps.UserInputService

	-- ============ Панель ============

	-- ФОН — соты. Шестигранник в этой игре не украшение: это клетка арены, её рисует
	-- подсветка постройки (TowerInteraction.rebuildHexWedges — шесть клиньев через 60°,
	-- рёбра по бокам, вершина вверх), и решётка окна собрана из той же фигуры и в той же
	-- ориентации.
	--
	-- Прошлая решётка была двумя семействами прямых под ±60°, и автор назвал её тем, чем
	-- она и была: рубашкой игральных карт. Два семейства прямых дают ромбы, а не соты;
	-- шестигранник приходится собирать рёбрами — по три на клетку, остальные три у неё
	-- общие с соседями (правое вертикальное ребро клетки — это левое ребро соседа справа,
	-- верхние наклонные — нижние у верхних соседей). Рисовать все шесть значит провести
	-- каждую линию решётки дважды и удвоить ей яркость.
	--
	-- ГЛУБИНА. У каждой панели своя, по её месту в стопке окон: 0 — самое дальнее
	-- (журнал Лаборатории лежит под всем остальным), 1 — самое близкое (карточка
	-- подтверждения крафта — поверх всего). Чем ближе, тем клетка мельче, линия светлее
	-- и ход быстрее — тот же закон, что у параллакса за окном поезда.
	--
	-- КРАЙ. Обрезать решётку в Roblox нечем. Что ClipsDescendants не режет повёрнутые
	-- кадры — было известно и раньше; но CanvasGroup их не режет ТОЖЕ, хотя рисует детей
	-- в собственный буфер. Проверено прямым опытом: две одинаковые наклонные линии, одна
	-- в CanvasGroup, другая в обычном фрейме с ClipsDescendants, вышли за свою плашку
	-- одинаково — обе через весь экран. До этой проверки решётка панели забега 232x72
	-- расписывала полнеба, и это первое, что увидел автор.
	--
	-- Поэтому решётка режется СЧЁТОМ. У каждого ребра известны центр, единичное направление
	-- вдоль длины и половина длины; отрезок пересекается с прямоугольником панели по
	-- параметру вдоль самого себя, и ребру, задевшему край, переписываются середина и длина —
	-- оно кончается ровно на канте. Целиком вылезшее гасится.
	--
	-- До задачи #129 рёбра не резались, а гасли к краям, и поле сот растворялось, не доходя
	-- до канта. Замечание автора: «фон не заходит за рамки. Это ухудшает атмосферу. Если
	-- шестиугольники будут за рамкой, будет ощущение что они бесконечные». Растворение
	-- читается как край нарисованной текстуры; срез по канту — как окно в поле, которое
	-- продолжается и за окном.
	Theme.depth = {
		journal = 0, -- Лаборатория с журналом — самое дно стопки
		window = 0.2, -- инвентарь: тоже окно, но открывается поверх игры
		hud = 0.45, -- панель забега и прочее поверх арены
		dialog = 0.7, -- выбор заливки, карточка плутония, промокод
		top = 1, -- подтверждение крафта — поверх всего
	}

	-- ОБСТАНОВКА. Решётка была одна на все окна, и любой экран читался одинаково —
	-- замечание автора: «сейчас в любом фоне, просто шестиугольники и темнота».
	-- Здесь на каждую ситуацию своя: размер клетки, цвет, сила линии, ход и опрос.
	-- Это таблица, а не разветвление в коде: новая ситуация добавляется строкой.
	--
	-- cell — радиус клетки в пикселях (потолок — половина короткой стороны панели);
	-- line — сила линии до опроса;
	-- tint — цвет рёбер;
	-- drift — ход по вертикали в пикселях в секунду, МИНУС значит вверх;
	-- driftX — ход по горизонтали, МИНУС значит влево; без него решётка едет только
	--   по вертикали, а с ним вместе с drift — по диагонали;
	-- pulse — сколько кругов волны опроса в секунду;
	-- wave — насколько волна поднимает яркость в самой гуще;
	-- sheen — прозрачность перепада яркости стекла в самой сильной точке;
	-- at — где этот перепад стоит: 0 — вверху панели, 1 — внизу;
	-- far — во сколько раз крупнее клетка дальнего слоя; без него — Theme.BACKDROP_FAR.
	Theme.scene = {
		-- Главное меню: самая крупная клетка и медленный ход — за меню нет ничего.
		menu = { cell = 128, line = 0.075, tint = Theme.color.grid, drift = 4, pulse = 0.05, wave = 0.26, sheen = 0.955, at = 0, far = 2.2 },
		-- Журнал: мелкая частая сетка почти без хода — страница записей, а не прибор.
		journal = { cell = 58, line = 0.06, tint = Theme.color.steel, drift = 1.2, pulse = 0.03, wave = 0.12, sheen = 0.965, at = 0 },
		-- Настройки: та же комната, но ход развёрнут вверх и перепад ушёл вниз —
		-- смена страницы видна сразу, ещё до того как прочитан заголовок.
		settings = { cell = 96, line = 0.07, tint = Theme.color.info, drift = -3, pulse = 0.045, wave = 0.2, sheen = 0.96, at = 1 },
		-- Лаборатория: самая крупная и самая спокойная — карта рецептов и так пёстрая.
		lab = { cell = 150, line = 0.055, tint = Theme.color.grid, drift = 2, pulse = 0.035, wave = 0.16, sheen = 0.96, at = 0, far = 2 },
		-- Инвентарь: окно поверх игры, ход заметнее меню.
		inventory = { cell = 84, line = 0.08, tint = Theme.color.steel, drift = 5, pulse = 0.06, wave = 0.24, sheen = 0.955, at = 0 },
		-- Панель забега: мелко, быстро и с сильным опросом — прибор под нагрузкой.
		run = { cell = 46, line = 0.13, tint = Theme.color.accentDim, drift = 12, pulse = 0.13, wave = 0.34, sheen = 0.95, at = 0 },
		-- Диалог поверх игры: карточка плутония, промокод.
		dialog = { cell = 62, line = 0.12, tint = Theme.color.accentDim, drift = 9, pulse = 0.1, wave = 0.3, sheen = 0.95, at = 0 },
		-- Выбор заливки турели: зелень действия — сейчас что-то поставят на поле.
		build = { cell = 54, line = 0.13, tint = Theme.color.action, drift = 10, pulse = 0.12, wave = 0.32, sheen = 0.95, at = 0 },
		-- Подтверждение крафта: янтарь и самый быстрый ход — минута решения.
		confirm = { cell = 40, line = 0.16, tint = Theme.color.energy, drift = 16, pulse = 0.18, wave = 0.38, sheen = 0.94, at = 0 },
		-- Вкладка «Купить»: янтарь — здесь тратится материя, а всё считаемое в игре этого цвета.
		shop = { cell = 76, line = 0.065, tint = Theme.color.energy, drift = 3, pulse = 0.05, wave = 0.2, sheen = 0.955, at = 0 },
		-- Вкладка «Крафт»: зелень действия и ход вверх — из двух элементов собирается третий.
		craft = { cell = 104, line = 0.07, tint = Theme.color.action, drift = -2.5, pulse = 0.055, wave = 0.22, sheen = 0.955, at = 1 },
		-- Редактор волн: служебное окно, синь показаний.
		editor = { cell = 72, line = 0.1, tint = Theme.color.info, drift = 6, pulse = 0.07, wave = 0.26, sheen = 0.955, at = 0 },
	}

	-- Числовая глубина из Theme.depth (вызовы, которые ещё не назвали свою ситуацию)
	-- превращается в обстановку теми же формулами, что стояли внутри Theme.Backdrop
	-- до задачи #129: ни одно такое окно вида не меняет.
	-- ГЛУБИНА ФОНА (просьба автора, #221): «дальше от игрока — больше, тусклее и
	-- непримечательнее, ближе — примечательнее». Это закон для всех окон сразу, а не
	-- своя решётка на каждое: под сотами обстановки лежит тот же рисунок, крупнее во
	-- столько-то раз, бледнее и медленнее. Заметен ближний слой, дальний только даёт
	-- ощущение, что поле уходит вглубь. Плашке, на которой крупной клетке негде
	-- поместиться целиком, дальний слой не даётся: он совпал бы с ближним.
	Theme.BACKDROP_FAR = 2.2 -- во сколько раз крупнее клетка дальнего слоя
	Theme.BACKDROP_FAR_LINE = 0.45 -- доля силы линии и волны опроса
	Theme.BACKDROP_FAR_SPEED = 0.5 -- доля хода: дальнее едет медленнее, как за окном поезда

	local function sceneOf(name)
		if type(name) == "table" then
			return name
		end
		if type(name) == "string" then
			return Theme.scene[name] or Theme.scene.menu
		end
		local depth = math.clamp(tonumber(name) or Theme.depth.window, 0, 1)
		return {
			cell = 130 - 86 * depth,
			line = 0.05 + 0.13 * depth,
			tint = Theme.color.grid,
			drift = 1.5 + 13 * depth,
			pulse = 0.055 + 0.075 * depth,
			wave = 0.3,
			sheen = 0.955,
			at = 0,
		}
	end

	-- Все решётки игры ведёт одна подписка на Heartbeat: свой цикл на каждое окно — это
	-- пять циклов ради одного числа.
	local layers = {}

	-- Настройка «Сетка на панелях». Уже построенные решётки гасятся, а не перестают
	-- строиться: к моменту переключения они висят во всех уже собранных окнах,
	-- и «не строить новые» на экране не изменило бы ничего.
	local gridEnabled = Settings.Get("panelGrid")

	Settings.Changed.Event:Connect(function(key, value)
		if key ~= "panelGrid" then
			return
		end
		gridEnabled = value
		for holder in layers do
			holder.Visible = value
		end
	end)

	-- Волна опроса, идущая по сотам сверху вниз. Ни одного нового кадра не заводит: это
	-- слагаемое к яркости тех же рёбер, что и так пересчитываются каждый кадр. Без неё
	-- решётка ровно одной и той же яркости по всей панели и читается как напечатанная
	-- текстура; с ней поле сот выглядит опрашиваемым, а не нарисованным.
	--
	-- Ширина и сила взяты так, чтобы волна была заметна краем глаза и никогда не спорила
	-- с текстом поверх неё: даже в самой гуще ребро остаётся прозрачнее половины.
	local PULSE_SPAN = 0.26 -- полуширина волны в долях высоты панели

	RunService.Heartbeat:Connect(function(dt)
		for holder, state in layers do
			if not holder.Parent then
				layers[holder] = nil -- окно снесли — слой уходит из списка сам
			-- Снятая настройка отключает счёт, но не уборку снесённых слоёв выше:
			-- иначе за время с выключенной сеткой в списке копились бы мёртвые записи.
			elseif gridEnabled and state.frame.Visible then
				-- Ход замыкается на 3R — это вертикальный период сот: соседние строки клеток
				-- сдвинуты по горизонтали на полклетки, и рисунок повторяет себя только через
				-- две строки. Замкни его на 1.5R — решётка прыгала бы вбок на каждом круге.
				--
				-- Ход вверх — это отрицательная скорость, и никакой отдельной ветки ему
				-- не нужно: остаток от деления в Luau всегда неотрицателен, поэтому фаза
				-- при убывании перескакивает через тот же самый период.
				state.phase = (state.phase + dt * state.speed) % state.period
				local offset = state.phase - state.period
				-- Вбок ход замыкается на ширину клетки 2·R·cos 30°: через неё ряд повторяет себя.
				local slide = state.speedX ~= 0
				local offsetX = 0
				if slide then
					state.phaseX = (state.phaseX + dt * state.speedX) % state.periodX
					offsetX = state.phaseX - state.periodX
				end
				holder.Position = UDim2.new(0, offsetX, 0, offset)
				local width = state.width

				local height = state.height
				-- Волна заходит выше панели и уходит ниже неё, чтобы не зарождаться
				-- и не гаснуть прямо на виду.
				state.pulse = (state.pulse + dt * state.pulseSpeed) % 1
				local pulseAt = (state.pulse * (1 + PULSE_SPAN * 2) - PULSE_SPAN) * height
				local pulseHalf = height * PULSE_SPAN
				local gain = state.wave

				for i, seg in state.segs do
					-- ---- срез по верхнему и нижнему краю ----
					-- Слева и справа края не двигаются, и там всё посчитано при сборке
					-- (tx0..tx1). Сверху и снизу решётка едет, и пересечение считается
					-- каждый кадр — по тому же параметру вдоль отрезка.
					local uy = state.uy[i]
					local cy = state.cy[i] + offset
					local t0, t1 = state.tx0[i], state.tx1[i]
					local ya, yb = (0 - cy) / uy, (height - cy) / uy
					if ya > yb then
						ya, yb = yb, ya
					end
					if ya > t0 then
						t0 = ya
					end
					if yb < t1 then
						t1 = yb
					end
					-- Решётка, едущая вбок, режется и по боковым краям — каждый кадр,
					-- так же как по верхнему и нижнему.
					if slide then
						local ux = state.ux[i]
						local cx = state.cx[i] + offsetX
						if ux ~= 0 then
							local xa, xb = (0 - cx) / ux, (width - cx) / ux
							if xa > xb then
								xa, xb = xb, xa
							end
							if xa > t0 then
								t0 = xa
							end
							if xb < t1 then
								t1 = xb
							end
						elseif cx < 0 or cx > width then
							t1 = t0
						end
					end

					if t1 - t0 < 1 then
						-- Ребро целиком за краем панели: гасим и больше о нём не думаем.
						if state.shown[i] then
							state.shown[i] = false
							seg.Visible = false
						end
					else
						if not state.shown[i] then
							state.shown[i] = true
							seg.Visible = true
						end
						-- Целое ребро возвращается к своей исходной геометрии одним
						-- присваиванием, а не пересчётом: у краёв панели урезанных рёбер
						-- меньшинство, а в середине целы почти все.
						if t0 <= state.tx0[i] + 0.01 and t1 >= state.tx1[i] - 0.01 then
							if state.cut[i] then
								state.cut[i] = false
								seg.Position = state.pos[i]
								seg.Size = state.size[i]
							end
						else
							state.cut[i] = true
							local mid = (t0 + t1) / 2
							local len = t1 - t0
							-- Середина считается в координатах слоя, а не панели: сам сдвиг
							-- слоя уже стоит в holder.Position, и прибавить его второй раз
							-- значило бы услать урезанное ребро вдвое дальше.
							seg.Position = UDim2.new(
								0, state.cx[i] + state.ux[i] * mid,
								0, state.cy[i] + uy * mid
							)
							seg.Size = state.tall[i] and UDim2.fromOffset(1, len) or UDim2.fromOffset(len, 1)
						end

						local off = math.abs(cy - pulseAt)
						local wave = off < pulseHalf and (1 - off / pulseHalf) or 0
						local t = 1 - math.min(state.base[i] + gain * wave * wave, 0.55)
						-- Пишем только изменившимся: вне волны прозрачность постоянна,
						-- а таких рёбер большая часть.
						if math.abs(t - state.last[i]) > 0.004 then
							state.last[i] = t
							seg.BackgroundTransparency = t
						end
					end
				end
			end
		end
	end)

	-- Обстановка каждой панели лежит при самой панели: Theme.SetScene меняет её у уже
	-- собранной, не зная, кто и с какими параметрами эту панель собирал. Ключи слабые —
	-- снесённое окно эти таблицы в памяти не держат.
	local sceneAt = setmetatable({}, { __mode = "k" })
	local builtAt = setmetatable({}, { __mode = "k" })

	-- Потолок рёбер на один слой. Клетка мельче допустимой укрупняется: мелкая сота,
	-- заданная обстановке плашки, на окне во весь экран стоила бы тысяч кадров.
	local LATTICE_MAX = 2400

	-- Цвет стекла, к которому подмешивается тон обстановки: чистый цвет рёбер в подсветке
	-- дал бы цветное пятно во всю панель, а не перепад яркости.
	local SHEEN_BASE = Color3.fromRGB(122, 156, 176)

	function Theme.Backdrop(frame, name)
		-- Панель, которая сама растёт по содержимому, решётки не получает: слой размером
		-- в панель для AutomaticSize — это содержимое размером в панель, и панель тянется
		-- за ним по кругу. Замерено на карточке плутония: высота 211004 пикселя за пару секунд.
		if frame.AutomaticSize ~= Enum.AutomaticSize.None then
			return nil
		end
		local scene = sceneOf(name)
		sceneAt[frame] = scene

		local root = frame:FindFirstChild("Backdrop")
		if not root then
			root = Instance.new("Frame")
			root.Name = "Backdrop"
			root.BackgroundTransparency = 1
			root.BorderSizePixel = 0
			root.ZIndex = frame.ZIndex
			root.Parent = frame
		end
		-- Решётка доходит до настоящего края панели, под самый кант, а не до края её
		-- внутреннего отступа: иначе у окна с отступом по периметру оставалась пустая рамка.
		Theme.Bleed(root, UDim2.new(0, 0, 0, 0), UDim2.new(1, 0, 1, 0))

		-- Мерка масштаба. Рёбра стоят в пикселях до масштаба, а AbsoluteSize — уже после
		-- него, и во время открытия окна (Theme.Open, UIScale 0.96 → 1) панель меряется
		-- на 4% меньше, чем она есть. Решётка, срезанная по такой мерке, так и осталась бы
		-- с пустой полосой у правого и нижнего канта. Кадр в сто пикселей показывает
		-- настоящий масштаб всей цепочки предков.
		local probe = root:FindFirstChild("Probe")
		if not probe then
			probe = Instance.new("Frame")
			probe.Name = "Probe"
			probe.BackgroundTransparency = 1
			probe.BorderSizePixel = 0
			probe.Size = UDim2.fromOffset(100, 100)
			probe.Parent = root
		end

		-- Один слой сот. cellScale, lineScale и speedScale — доли от обстановки: дальний
		-- слой крупнее, бледнее и медленнее ближнего (Theme.BACKDROP_FAR).
		local function build(width, height, cellScale, lineScale, speedScale)
			-- Потолок от короткой стороны панели: клетка втрое мельче панели стоила плашке
			-- забега 232x72 ста двадцати четырёхпиксельных кадров — шероховатость вместо сот.
			local radius = math.min(scene.cell * cellScale, math.min(width, height) / 2)
			if radius < 14 then
				return -- на плашку меньше сорока пикселей высотой соты не положить
			end
			-- Три ребра на клетку; строк — на высоту панели и ещё на период хода.
			local estimate = 3 * (width / (radius * 1.732) + 2) * ((height + radius * 3) / (radius * 1.5) + 3)
			if estimate > LATTICE_MAX then
				radius *= math.sqrt(estimate / LATTICE_MAX)
			end
			local across = radius * 0.8660254 -- половина ширины клетки: R * cos(30°)
			local pitch = radius * 1.5 -- шаг строк: строки сот заходят друг в друга на четверть клетки
			local period = radius * 3
			local line = scene.line * lineScale
			local speedX = (scene.driftX or 0) * speedScale
			local slide = speedX ~= 0

			local holder = Instance.new("Frame")
			holder.Name = "Lattice"
			holder.BackgroundTransparency = 1
			holder.Size = UDim2.new(1, 0, 1, 0)
			holder.Position = UDim2.new(0, slide and -across * 2 or 0, 0, -period)
			holder.ZIndex = root.ZIndex
			-- Окно могли открыть уже после того, как сетку выключили
			holder.Visible = gridEnabled

			local state = {
				frame = frame,
				phase = 0,
				-- Фаза волны стартует со случайного места: два окна рядом, опрашиваемые
				-- в один такт, читаются как одна мигающая плашка, а не как два прибора.
				pulse = math.random(),
				pulseSpeed = scene.pulse,
				wave = scene.wave * lineScale,
				speed = scene.drift * speedScale,
				period = period,
				speedX = speedX,
				periodX = across * 2,
				phaseX = 0,
				width = width,
				height = height,
				segs = {}, cx = {}, cy = {}, ux = {}, uy = {}, tx0 = {}, tx1 = {},
				pos = {}, size = {}, tall = {}, shown = {}, cut = {}, base = {}, last = {},
			}

			-- Слева и справа край панели не двигается, и срез по нему считается здесь,
			-- один раз: ребру, целиком ушедшему за боковой край, незачем и рождаться.
			-- Сверху и снизу решётка едет, и тот срез считает Heartbeat выше.
			local function edge(x, y, angle)
				local tall = angle == 90
				local ux = tall and 0 or math.cos(math.rad(angle))
				local uy = tall and 1 or math.sin(math.rad(angle))
				local t0, t1 = -radius / 2, radius / 2
				if slide then
					-- Едущая вбок решётка режется по бокам в Heartbeat: здесь ребро целое.
				elseif ux ~= 0 then
					local a, b = -x / ux, (width - x) / ux
					if a > b then
						a, b = b, a
					end
					t0, t1 = math.max(t0, a), math.min(t1, b)
				elseif x < 0 or x > width then
					return
				end
				if t1 - t0 < 1 then
					return
				end
				local mid, len = (t0 + t1) / 2, t1 - t0
				local pos = UDim2.new(0, x + ux * mid, 0, y + uy * mid)
				local size = tall and UDim2.fromOffset(1, len) or UDim2.fromOffset(len, 1)

				local seg = Instance.new("Frame")
				seg.BorderSizePixel = 0
				seg.BackgroundColor3 = scene.tint
				seg.BackgroundTransparency = 1
				seg.AnchorPoint = Vector2.new(0.5, 0.5)
				seg.Position = pos
				seg.Size = size
				-- Вертикальное ребро — не повёрнутый кадр, а просто узкий: поворот на 90°
				-- дал бы ту же линию дороже.
				seg.Rotation = tall and 0 or angle
				seg.ZIndex = root.ZIndex
				seg.Parent = holder

				local i = #state.segs + 1
				state.segs[i] = seg
				state.cx[i], state.cy[i] = x, y
				state.ux[i], state.uy[i] = ux, uy
				state.tx0[i], state.tx1[i] = t0, t1
				state.pos[i], state.size[i] = pos, size
				state.tall[i] = tall
				state.shown[i], state.cut[i] = true, false
				state.base[i] = line
				state.last[i] = 1
			end

			-- Клетка вершиной вверх: два верхних ребра под ±30° к горизонту и правое
			-- вертикальное. Слой поднят на период хода и едет в пределах одного периода,
			-- поэтому строки нужны на всю высоту панели и ещё на период ниже.
			local rows = math.ceil((height + period + radius * 2) / pitch)
			-- Едущей вбок решётке нужна ещё одна колонка справа: слой сдвинут влево
			-- на ширину клетки и едет в её пределах.
			local cols = math.ceil(width / (across * 2)) + (slide and 2 or 1)
			for row = 0, rows do
				local y = row * pitch - radius
				local shift = (row % 2 == 1) and across or 0
				for col = -1, cols do
					local x = shift + col * across * 2
					local top = y - radius * 0.75
					edge(x - across / 2, top, -30)
					edge(x + across / 2, top, 30)
					edge(x + across, y, 90)
				end
			end

			holder.Parent = root
			layers[holder] = state
		end

		-- Решётка пересобирается на любое изменение размера, а не на огрублённое до сорока
		-- пикселей, как при гаснущих краях: срезу по канту нужен точный размер. Панель
		-- стала шире постройки — у правого канта пустая полоса; уже — повёрнутые рёбра
		-- вылезают за неё, а их ClipsDescendants не режет.
		local function rebuild()
			local current = sceneAt[frame]
			local k = probe.AbsoluteSize.X / 100
			if not current or k <= 0 then
				return -- окно ещё не отрисовано
			end
			local size = frame.AbsoluteSize
			local width, height = size.X / k, size.Y / k
			if width < 40 or height < 20 then
				return
			end
			local built = builtAt[root]
			if built and built.scene == current and math.abs(built.w - width) < 1.5 and math.abs(built.h - height) < 1.5 then
				return
			end
			builtAt[root] = { scene = current, w = width, h = height }
			-- Сносится только сама решётка: рядом в том же корне лежат подсветка стекла
			-- и мерка масштаба.
			for _, child in root:GetChildren() do
				if child.Name == "Lattice" then
					layers[child] = nil
					child:Destroy()
				end
			end
			scene = current
			local far = scene.far or Theme.BACKDROP_FAR
			if scene.cell * far <= math.min(width, height) / 2 then
				build(width, height, far, Theme.BACKDROP_FAR_LINE, Theme.BACKDROP_FAR_SPEED)
			end
			build(width, height, 1, 1, 1)
		end

		-- Подсветка стекла. Не ореол и не свечение (их в этом языке нет), а перепад
		-- яркости самого стекла: без него плашка во весь экран — ровный чёрный
		-- прямоугольник без верха и низа, и глазу не за что зацепиться. Тон подмешан
		-- от обстановки, сторона берётся из неё же: темнота у каждой ситуации своя.
		local sheen = root:FindFirstChild("Sheen")
		if not sheen then
			sheen = Instance.new("Frame")
			sheen.Name = "Sheen"
			sheen.BorderSizePixel = 0
			sheen.BackgroundTransparency = 0
			sheen.ZIndex = root.ZIndex
			sheen.Parent = root
			Instance.new("UIGradient").Parent = sheen
		end
		sheen.AnchorPoint = Vector2.new(0, scene.at)
		sheen.Position = UDim2.new(0, 0, scene.at, 0)
		sheen.Size = UDim2.new(1, 0, 0.5, 0)
		sheen.BackgroundColor3 = SHEEN_BASE:Lerp(scene.tint, 0.5)
		sheen.Visible = scene.sheen < 1
		local fade = sheen:FindFirstChildOfClass("UIGradient")
		-- Градиент гаснет ОТ своей стороны: у подсветки внизу он развёрнут.
		fade.Rotation = scene.at == 1 and -90 or 90
		fade.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, math.clamp(scene.sheen, 0, 1)),
			NumberSequenceKeypoint.new(1, 1),
		})

		rebuild()
		-- Одна подписка на панель, даже если сборщик позвали повторно (SetScene).
		-- Пересборка отложена на десятую долю секунды: окно, меняющее размер плавно,
		-- иначе пересобирало бы решётку в каждом кадре. Мерка слушается тоже: у только что
		-- заведённой панели она получает размер кадром позже самой панели.
		if not frame:GetAttribute("BackdropWatch") then
			frame:SetAttribute("BackdropWatch", true)
			local pending = false
			local function later()
				if pending then
					return
				end
				pending = true
				task.delay(0.1, function()
					pending = false
					rebuild()
				end)
			end
			frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(later)
			probe:GetPropertyChangedSignal("AbsoluteSize"):Connect(later)
		end
		frame.ClipsDescendants = true
		return root
	end

	-- Сменить обстановку уже собранной панели: страница главного меню, вкладка Лаборатории.
	-- Панель, собранная без решётки (depth = false), без неё и остаётся.
	function Theme.SetScene(frame, name)
		if frame:FindFirstChild("Backdrop") then
			Theme.Backdrop(frame, name)
		end
	end
	-- Сетка точек — фон окна, отличный от сот вокруг него (#223): рисунок другой формы,
	-- а не те же соты темнее. Неподвижная; пересобирается, только когда меняется размер.
	-- Кадр сетки выносится под кант окна (Theme.Bleed): внутренний отступ окна её не сужает.
	--
	-- opts: step — шаг сетки, size — сторона точки, transparency — прозрачность точки,
	-- keep — доля позиций, на которых точка стоит (1 — на всех), zIndex.
	-- Какие позиции пустуют, решает посев, а не случай на каждой пересборке: при смене
	-- размера окна рисунок иначе перетасовывался бы у игрока на глазах.
	--
	-- Где стоят точки, сетка пишет в атрибуты своего кадра Dots: OriginX, OriginY — левый
	-- верхний угол первой точки, Step и Size. По ним стекло над сеткой рисует на тех же
	-- местах размытые точки (CraftingUI, glass).
	--
	-- Возвращает paint(w, h): размер передаёт сборщик окна, в пикселях до масштаба.
	-- AbsoluteSize для этого не годится — во время Theme.Open окно меряется на 4% меньше.
	function Theme.Dots(frame, opts)
		opts = opts or {}
		local step = opts.step or 28
		local size = opts.size or 2
		local transparency = opts.transparency or 0.3
		local keep = opts.keep or 1

		local dots = Instance.new("Frame")
		dots.Name = "Dots"
		dots.BackgroundTransparency = 1
		dots.BorderSizePixel = 0
		dots.ZIndex = opts.zIndex or frame.ZIndex
		dots.Parent = frame
		Theme.Bleed(dots, UDim2.new(0, 0, 0, 0), UDim2.new(1, 0, 1, 0))

		local paintedFor
		return function(w, h)
			w, h = math.floor(w), math.floor(h)
			local key = w .. "x" .. h
			if paintedFor == key then
				return
			end
			paintedFor = key
			dots:ClearAllChildren()
			local rng = Random.new(1)
			local cols, rows = math.floor(w / step), math.floor(h / step)
			local ox = math.floor((w - (cols - 1) * step - size) / 2)
			local oy = math.floor((h - (rows - 1) * step - size) / 2)
			dots:SetAttribute("Step", step)
			dots:SetAttribute("Size", size)
			dots:SetAttribute("OriginX", ox)
			dots:SetAttribute("OriginY", oy)
			for r = 0, rows - 1 do
				for c = 0, cols - 1 do
					if keep >= 1 or rng:NextNumber() < keep then
						local d = Instance.new("Frame")
						d.BorderSizePixel = 0
						d.BackgroundColor3 = Theme.color.grid
						d.BackgroundTransparency = transparency
						d.Size = UDim2.fromOffset(size, size)
						d.Position = UDim2.fromOffset(ox + c * step, oy + r * step)
						d.ZIndex = dots.ZIndex
						d.Parent = dots
					end
				end
			end
		end
	end


	-- Звёзды — фон окна справочника (#270, #271): у каждого окна свой узор (точки у
	-- производителя, редкие точки у меню), справочнику досталось
	-- ночное небо: редкие тусклые звёзды разной величины. Линий между ними нет — линиями
	-- говорит сама карта рецептов, фон с ней не спорит.
	-- Звезда — одна на ячейку сетки, со сдвигом внутри ячейки: так рисунок выглядит
	-- случайным, но без пустых дыр и слипшихся кучек. Посев постоянный, как у Theme.Dots:
	-- при смене размера окна небо не перетасовывается.
	--
	-- Где стоят звёзды, знает Theme.StarsOf(layer) — по ним стекло кладёт свои пятна
	-- (MonitorGlass). После каждой перерисовки у слоя растёт атрибут Version.
	--
	-- opts: cell — сторона ячейки, zIndex. Возвращает paint(w, h), как Theme.Dots.
	local starsOf = setmetatable({}, { __mode = "k" })

	function Theme.StarsOf(layer)
		return starsOf[layer]
	end

	function Theme.Stars(frame, opts)
		opts = opts or {}
		local cell = opts.cell or 110

		local layer = Instance.new("Frame")
		layer.Name = "Stars"
		layer.BackgroundTransparency = 1
		layer.BorderSizePixel = 0
		layer.ZIndex = opts.zIndex or frame.ZIndex
		layer.Parent = frame
		Theme.Bleed(layer, UDim2.new(0, 0, 0, 0), UDim2.new(1, 0, 1, 0))

		local paintedFor
		return function(w, h)
			w, h = math.floor(w), math.floor(h)
			local key = w .. "x" .. h
			if paintedFor == key then
				return
			end
			paintedFor = key
			layer:ClearAllChildren()
			local rng = Random.new(7)
			local cols, rows = math.max(1, math.floor(w / cell)), math.max(1, math.floor(h / cell))
			local cw, ch = w / cols, h / rows
			local list = {}
			for r = 0, rows - 1 do
				for c = 0, cols - 1 do
					-- Сдвиг не до самого края ячейки: соседние звёзды не слипаются.
					local x = math.floor(c * cw + cw * rng:NextNumber(0.2, 0.8))
					local y = math.floor(r * ch + ch * rng:NextNumber(0.2, 0.8))
					local roll = rng:NextNumber()
					local size = roll < 0.12 and 4 or roll < 0.4 and 3 or 2
					local star = { x = x, y = y, size = size }
					list[#list + 1] = star
				end
			end

			for _, star in list do
				local d = Instance.new("Frame")
				d.BorderSizePixel = 0
				d.BackgroundColor3 = Theme.color.grid
				-- Крупные ярче: у звёзд величина и блеск идут вместе.
				d.BackgroundTransparency = star.size == 4 and 0.15 or star.size == 3 and 0.35 or 0.5
				d.Size = UDim2.fromOffset(star.size, star.size)
				d.Position = UDim2.fromOffset(star.x - star.size / 2, star.y - star.size / 2)
				d.ZIndex = layer.ZIndex
				local round = Instance.new("UICorner")
				round.CornerRadius = UDim.new(0.5, 0)
				round.Parent = d
				d.Parent = layer
			end

			starsOf[layer] = list
			layer:SetAttribute("Version", (layer:GetAttribute("Version") or 0) + 1)
		end
	end

	-- Угловые засечки: по две линии в пиксель в каждом углу окна — визир прибора.
	--
	-- Зачем они при том, что у панели уже есть кант: окна игры открываются во весь экран,
	-- и кант по самому краю там либо не виден вовсе, либо частично уезжает за скруглённые
	-- углы экрана телефона. Засечка, отступившая внутрь, видна всегда.
	--
	-- Геометрию окна не трогают — лежат внутри его собственных границ, как и остальные
	-- сборщики темы (см. шапку файла).
	--
	-- ВНУТРЕННИЙ ОТСТУП ОКНА компенсируется нарочно. UIPadding сдвигает всех детей
	-- без исключения, и засечка «в семи пикселях от края» у окна с отступом в двадцать
	-- оказывается не у края, а поверх заголовка — ровно так и вышло с первого раза.
	-- Короткая и прижатая к углу: длинная засечка дотягивалась до строки состояния
	-- в подвале окна и подчёркивала её первое слово.
	--
	-- Сам отступ берётся ЗАМЕРОМ, а не чтением UIPadding в момент вызова: сборщик
	-- часто зовут сразу за Corner и Stroke, то есть ДО того, как окну поставили отступ
	-- (так и было в MainMenu: засечки легли на подвал и на кнопку — замерено: черта
	-- на 1480,689 внутри кнопки 1337..1487). Прочитанные в тот момент нули замирали
	-- навсегда. Разница между краем окна и краем собственного кадра засечек — это
	-- и есть отступ, каким бы он ни стал потом.
	Theme.BRACKET = { inset = 6, arm = 14 }

	local BRACKET_CORNERS = { Vector2.new(0, 0), Vector2.new(1, 0), Vector2.new(0, 1), Vector2.new(1, 1) }

	function Theme.Brackets(frame, color)
		local holder = frame:FindFirstChild("Brackets")
		if not holder then
			holder = Instance.new("Frame")
			holder.Name = "Brackets"
			holder.BackgroundTransparency = 1
			holder.BorderSizePixel = 0
			holder.Size = UDim2.new(1, 0, 1, 0)
			holder.Parent = frame
		end
		holder.ZIndex = frame.ZIndex + 1

		local tint = color or Theme.color.accentDim
		local inset, arm = Theme.BRACKET.inset, Theme.BRACKET.arm

		local bars = {}
		for index, corner in BRACKET_CORNERS do
			for axis = 1, 2 do
				local name = ("Mark%d_%d"):format(index, axis)
				local bar = holder:FindFirstChild(name)
				if not bar then
					bar = Instance.new("Frame")
					bar.Name = name
					bar.BorderSizePixel = 0
					bar.Parent = holder
				end
				bar.BackgroundColor3 = tint
				bar.BackgroundTransparency = 0
				bar.AnchorPoint = corner
				-- Первая линия угла горизонтальная, вторая вертикальная — вместе они дают «L».
				bar.Size = axis == 1 and UDim2.fromOffset(arm, 1) or UDim2.fromOffset(1, arm)
				bar.ZIndex = holder.ZIndex
				table.insert(bars, { bar = bar, corner = corner })
			end
		end

		local function place()
			local fp, fs = frame.AbsolutePosition, frame.AbsoluteSize
			local hp, hs = holder.AbsolutePosition, holder.AbsoluteSize
			if hs.X <= 0 or hs.Y <= 0 then
				return -- окно ещё не отрисовано или весь ScreenGui выключен
			end
			local padL = hp.X - fp.X
			local padT = hp.Y - fp.Y
			local padR = (fp.X + fs.X) - (hp.X + hs.X)
			local padB = (fp.Y + fs.Y) - (hp.Y + hs.Y)
			for _, entry in bars do
				local corner = entry.corner
				entry.bar.Position = UDim2.new(
					corner.X, corner.X == 0 and (inset - padL) or (padR - inset),
					corner.Y, corner.Y == 0 and (inset - padT) or (padB - inset)
				)
			end
		end

		place()
		-- Одна подписка на окно, даже если сборщик позвали повторно (тот же приём,
		-- что у BackdropWatch выше).
		if not frame:GetAttribute("BracketWatch") then
			frame:SetAttribute("BracketWatch", true)
			holder:GetPropertyChangedSignal("AbsoluteSize"):Connect(place)
			holder:GetPropertyChangedSignal("AbsolutePosition"):Connect(place)
		end

		return holder
	end

	-- Списки листаются перетаскиванием, а не только колесом: колеса на телефоне нет вовсе,
	-- а на ПК тянуть журнал рукой быстрее, чем крутить его по три строки.
	--
	-- Нажатие ловится через UserInputService, а не на самом списке: его строки — кнопки,
	-- они забирают нажатие себе, и до фрейма оно не доходит вовсе.
	--
	-- Пока тянули больше порога, на списке стоит атрибут Dragged — обработчики нажатий
	-- его проверяют (Theme.WasDragged) и молчат: иначе отпускание пальца над строкой
	-- уходило бы кликом по ней — пролистал список и заодно положил элемент в слот.
	local DRAG_SLOP = 6

	local function isShown(inst)
		while inst and inst ~= game do
			if inst:IsA("GuiObject") and not inst.Visible then
				return false
			end
			if inst:IsA("ScreenGui") and not inst.Enabled then
				return false
			end
			inst = inst.Parent
		end
		return true
	end

	function Theme.WasDragged(frame)
		return frame:GetAttribute("Dragged") == true
	end

	function Theme.DragScroll(frame)
		if frame:GetAttribute("DragScroll") then
			return frame
		end
		frame:SetAttribute("DragScroll", true)

		local dragging = false
		local lastY = 0
		local travelled = 0

		local function pressed(input)
			return input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
		end

		UserInputService.InputBegan:Connect(function(input)
			if not pressed(input) or not isShown(frame) then
				return
			end
			local pos, size = frame.AbsolutePosition, frame.AbsoluteSize
			if input.Position.X < pos.X or input.Position.X > pos.X + size.X
				or input.Position.Y < pos.Y or input.Position.Y > pos.Y + size.Y then
				return
			end
			dragging = true
			travelled = 0
			lastY = input.Position.Y
			frame:SetAttribute("Dragged", false)
		end)

		UserInputService.InputChanged:Connect(function(input)
			if not dragging then
				return
			end
			if input.UserInputType ~= Enum.UserInputType.MouseMovement
				and input.UserInputType ~= Enum.UserInputType.Touch then
				return
			end
			local dy = input.Position.Y - lastY
			lastY = input.Position.Y
			travelled += math.abs(dy)
			if travelled > DRAG_SLOP then
				frame:SetAttribute("Dragged", true)
			end
			local limit = math.max(0, frame.AbsoluteCanvasSize.Y - frame.AbsoluteSize.Y)
			frame.CanvasPosition = Vector2.new(
				frame.CanvasPosition.X,
				math.clamp(frame.CanvasPosition.Y - dy, 0, limit)
			)
		end)

		UserInputService.InputEnded:Connect(function(input)
			if not pressed(input) then
				return
			end
			dragging = false
			-- Флаг снимается чуть позже: клик кнопки приходит в том же кадре, что и InputEnded,
			-- и порядок между ними не закреплён.
			task.delay(0.05, function()
				frame:SetAttribute("Dragged", false)
			end)
		end)

		return frame
	end

	-- Окно: почти чёрная плашка с ползущей сеткой, обведённая приглушённой бирюзой.
	-- opts.color — своя заливка, opts.transparency — если сквозь панель нужно видеть арену,
	-- opts.edge — свой цвет канта, opts.depth — глубина решётки (см. Theme.depth),
	-- opts.depth = false — без решётки вовсе.
	function Theme.Panel(frame, opts)
		opts = opts or {}
		frame.BackgroundColor3 = opts.color or Theme.color.panel
		frame.BackgroundTransparency = opts.transparency or 0
		frame.BorderSizePixel = 0
		Theme.Corner(frame, Theme.radius.panel)
		Theme.Stroke(frame, opts.edge or Theme.color.frame, 1, 0)
		-- opts.scene — обстановка из Theme.scene; opts.depth — прежняя числовая глубина
		-- у панелей, которые свою обстановку не назвали. false в любом из двух — без решётки.
		if opts.depth ~= false and opts.scene ~= false then
			Theme.Backdrop(frame, opts.scene or opts.depth)
		end
		return frame
	end

end
