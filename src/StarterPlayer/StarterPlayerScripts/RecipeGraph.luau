-- Раскладка графа рецептов для справочника: где стоит каждый элемент и как между ними
-- идут связи. Рисование — в CraftingUI, здесь только числа.
--
-- Кольца (вариант, который автор выбрал по снимку, #131): четыре базовые стихии стоят
-- ромбом в середине, каждый ярус глубины — на своей окружности, окружности на равном шаге.
-- Узел встаёт на своём кольце в сторону своих ингредиентов, соседи по кольцу расходятся
-- ровно на свои габариты. Связь — кубическая дуга, которая выходит из родителя по радиусу
-- и по радиусу же входит в ребёнка: от каждой стихии связи расходятся фонтаном, а между
-- ветками ложатся паутиной.
--
-- До этого были силовая раскладка (#108–#117) и дорожки платы (#129) — автор отверг обе.
--
-- Раскладка одна (#220: прежний «Эксперимент» стал основной, «Стандарт» убран вместе
-- с настройкой вида). Кольца и радиусы — те, что описаны выше; угол, который даёт
-- формула (куда смотрят родители), — только начальная точка. Окончательный угол на кольце
-- ищет силовое поле: узел толкают все остальные узлы и тянут его связи, при этом движение
-- заперто вдоль своего кольца (радиус не меняется ни на шаг) — орбита в буквальном смысле.
--
-- Раскладка считается из Recipes, а не берётся таблицей готовых координат: новый рецепт
-- должен добавляться строкой в Recipes и попадать в справочник сам. Случайности нет:
-- порядок задают углы и имена элементов, картинка одна и та же у всех игроков.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Elements = require(ReplicatedStorage:WaitForChild("Elements"))
local Recipes = require(ReplicatedStorage:WaitForChild("Recipes"))

local Graph = {}

-- Габариты узла. Ширина — на глаз по числу букв: TextService:GetTextBoundsAsync ради
-- семидесяти одной подписи заставил бы раскладку ждать сервер шрифтов.
--
-- Базовые крупнее остальных (решение автора), поэтому высота своя у каждого узла
-- (массив hh): расстановка по кольцу считает именно те коробки, что будут нарисованы.
local NODE_H = 22
local BASE_H = 36 -- высота базовой стихии
local BASE_PAD = 34 -- и насколько она шире своей подписи
local CHAR_W = 6.6
local NAME_PAD = 16
local MIN_W, MAX_W = 46, 132

-- Группы для кластеризации берутся из цвета самого элемента, а не из нового поля
-- в таблице: цвета автор уже расставил по смыслу (Растение, Дерево и Жизнь зелёные,
-- Металл и Сталь серые, Плазма и Антиматерия фиолетовые), и вторая, выдуманная
-- мною классификация расходилась бы с ними при первой же правке цвета.
local function groupOf(color)
	local r, g, b = color.R, color.G, color.B
	local high = math.max(r, g, b)
	local low = math.min(r, g, b)
	local delta = high - low
	-- Бесцветное делится по светлоте: Воздух и Снег — свет, Металл и Камень — камень.
	if delta < 0.08 or high < 1e-6 or delta / high < 0.18 then
		return high > 0.85 and "свет" or "камень"
	end
	local hue
	if high == r then
		hue = ((g - b) / delta) % 6
	elseif high == g then
		hue = (b - r) / delta + 2
	else
		hue = (r - g) / delta + 4
	end
	hue *= 60
	if hue < 45 then
		-- Коричневое — тот же тон, что и оранжевое, только тёмное: Земля и Грунт
		-- иначе попадают к Огню.
		return high < 0.72 and "земля" or "огонь"
	end
	if hue < 70 then
		return "энергия"
	end
	if hue < 165 then
		return "природа"
	end
	if hue < 255 then
		return "вода"
	end
	if hue < 330 then
		return "космос"
	end
	return "огонь"
end

-- Ромб базовых: расстояние от середины до каждой стихии и сторона каждой. Стихия без
-- записи в BASE_ANGLE встаёт на круг по порядку.
local BASE_RING = 130
local BASE_ANGLE = { Air = -math.pi / 2, Water = math.pi, Fire = 0, Earth = math.pi / 2 }

-- Шаг колец. Нижняя граница — чтобы узлы соседних колец не задевали друг друга при любом
-- повороте (самая широкая плашка на боку кольца); выше её шаг поднимается, только если
-- самое людное кольцо не помещается на окружности с запасом RING_FILL.
local RING_GAP_MIN = 180
local RING_FILL = 0.85
local NODE_GAP = 14 -- просвет между соседями по кольцу
local DETAIL_H = 18 -- место под строку рецепта под узлом (ступень подробности 4 в CraftingUI)

-- Желаемый угол узла — сумма направлений на ингредиенты, второй весит чуть меньше старшего:
-- у рецепта из противоположных стихий (Вода + Огонь) равные веса дали бы нулевой вектор.
local MATE_WEIGHT = 0.85

-- Доля, на которую желаемые углы кольца подтягиваются к равному шагу по окружности.
-- Без неё узлы сбиваются в ту половину, куда смотрят старшие родители (у рецептов
-- с Водой старший почти всегда другой ингредиент), и сторона Воды пустеет.
local EVEN = 0.5

-- Расстановка по кольцу: первая доля проходов тянет узлы к желаемым углам, остальные
-- только разводят соседей, пока не разойдутся все.
local SPREAD_ITERS = 600
local SPREAD_PULL = 0.05
local SPREAD_PULL_SHARE = 0.5

-- Числа силового поля: узел кольца отталкивается от всех остальных и
-- тянется по своим связям, но радиус ему не принадлежит — только угол на своём же
-- кольце: сила, что тянула бы узел ближе к центру
-- или дальше от него, отбрасывается, остаётся только та её часть, что толкает вдоль кольца.
-- Так узел «облетает» своё кольцо в поисках места, а не срывается с орбиты.
local EXP_LINK = 150
local EXP_REPEL = 1.6
local EXP_ITERS = 240
local EXP_STEP_MAX, EXP_STEP_MIN = 60, 1.5

local END_PAD = 3 -- связь начинается и кончается на столько дальше половины высоты узла

local RING_POINTS = 120 -- звеньев в окружности кольца
local MARGIN = 20

local TWO_PI = math.pi * 2

local function wrap(a)
	a %= TWO_PI
	if a > math.pi then
		a -= TWO_PI
	end
	return a
end

-- ---------- кубическая Безье ----------
-- Кривая — плоский массив из восьми чисел: x0, y0, x1, y1, x2, y2, x3, y3. Нужна не только
-- раскладке: карта рисует связь самой кривой (Path2D), а не ломаной, и режет её
-- по окну и на полосы градиента (CraftingUI, wire).

-- Точка кривой при параметре t.
function Graph.BezierAt(c, t)
	local u = 1 - t
	local a, b, d, e = u * u * u, 3 * u * u * t, 3 * u * t * t, t * t * t
	return a * c[1] + b * c[3] + d * c[5] + e * c[7], a * c[2] + b * c[4] + d * c[6] + e * c[8]
end

-- Полярная форма кубики: де Кастельжо, где каждый уровень берёт свой параметр.
local function blossom(c, p, q, r)
	local x0, y0 = c[1] + (c[3] - c[1]) * p, c[2] + (c[4] - c[2]) * p
	local x1, y1 = c[3] + (c[5] - c[3]) * p, c[4] + (c[6] - c[4]) * p
	local x2, y2 = c[5] + (c[7] - c[5]) * p, c[6] + (c[8] - c[6]) * p
	x0, y0 = x0 + (x1 - x0) * q, y0 + (y1 - y0) * q
	x1, y1 = x1 + (x2 - x1) * q, y1 + (y2 - y1) * q
	return x0 + (x1 - x0) * r, y0 + (y1 - y0) * r
end

-- Кусок кривой между t0 и t1 — снова кубическая Безье, та же линия без изломов.
function Graph.BezierPart(c, t0, t1)
	local ax, ay = blossom(c, t0, t0, t0)
	local bx, by = blossom(c, t0, t0, t1)
	local cx, cy = blossom(c, t0, t1, t1)
	local dx, dy = blossom(c, t1, t1, t1)
	return { ax, ay, bx, by, cx, cy, dx, dy }
end

-- Готовая раскладка: счёт стоит заметной доли секунды, считается один раз.
local built = nil

-- ---------- структура дерева ----------
-- Глубина считается по Recipes, а не берётся из Elements.tier: там ярус проставлен руками
-- по шагам документа и с числом шагов от базовых не совпадает.
local function structure()
	local producedBy = {}
	for _, recipe in Recipes.List do
		producedBy[recipe.result] = recipe
	end

	-- Корни — покупные элементы: есть cost, значит рецепта у него нет и быть не должно.
	local depth = {}
	for key, data in Elements do
		if data.cost then
			depth[key] = 0
		end
	end

	-- Порядок в Recipes.List произвольный, поэтому гоняем до сходимости, а не одним проходом.
	local settling = true
	while settling do
		settling = false
		for _, recipe in Recipes.List do
			local da, db = depth[recipe.a], depth[recipe.b]
			if da and db then
				local d = 1 + math.max(da, db)
				if depth[recipe.result] ~= d then
					depth[recipe.result] = d
					settling = true
				end
			end
		end
	end

	local mainParent, mate = {}, {}
	for _, recipe in Recipes.List do
		local hi, lo = recipe.a, recipe.b
		if (depth[lo] or 0) > (depth[hi] or 0) then
			hi, lo = lo, hi
		end
		mainParent[recipe.result] = hi
		mate[recipe.result] = lo
	end

	-- Ветка — базовый элемент, до которого доводит цепочка старших родителей. Нужна
	-- и раскладке (с какой стороны начинать), и рисованию (каким цветом вести спину).
	local branch = {}
	local function branchOf(key)
		if branch[key] then
			return branch[key]
		end
		branch[key] = (producedBy[key] == nil) and key or branchOf(mainParent[key])
		return branch[key]
	end
	for key in Elements do
		branchOf(key)
	end

	-- Признака «чистокровный» (спина ветки от базового до четвёртого тира) здесь больше
	-- нет: справочник красил их связи цветом ветки, и автор попросил цветные линии убрать —
	-- все стрелки серые, цвет остался узлам и подсветке выбранной цепочки.

	return producedBy, depth, mainParent, mate, branch
end

-- ---------- сама раскладка ----------
function Graph.Build()
	if built then
		return built
	end
	local baseRing = BASE_RING
	local ringGapMin = RING_GAP_MIN
	local ringFill = RING_FILL

	local producedBy, depth, mainParent, mate, branch = structure()

	-- Элемент, до которого не доводит ни один рецепт от покупных, в графе не участвует:
	-- места ему определить не из чего.
	local keys = {}
	for key in Elements do
		if depth[key] then
			table.insert(keys, key)
		end
	end
	table.sort(keys)

	local n = #keys
	local index = {}
	local hw, hh = table.create(n), table.create(n)
	local group = {}
	local maxDepth = 0
	for i, key in keys do
		index[key] = i
		local base = producedBy[key] == nil
		local width = utf8.len(Elements[key].name) * CHAR_W + (base and BASE_PAD or NAME_PAD)
		hw[i] = math.clamp(width, MIN_W, MAX_W) / 2
		hh[i] = (base and BASE_H or NODE_H) / 2
		group[key] = groupOf(Elements[key].color)
		maxDepth = math.max(maxDepth, depth[key])
	end

	local rings = {}
	for d = 1, maxDepth do
		rings[d] = {}
	end
	local bases = {}
	for i, key in keys do
		if depth[key] == 0 then
			table.insert(bases, key)
		else
			table.insert(rings[depth[key]], i)
		end
	end

	-- Шаг колец: самое людное кольцо должно поместиться даже при худшем повороте плашек.
	local gap = ringGapMin
	for d = 1, maxDepth do
		local need = 0
		for _, i in rings[d] do
			need += 2 * (math.sqrt(hw[i] ^ 2 + (hh[i] + DETAIL_H) ^ 2) + NODE_GAP / 2)
		end
		gap = math.max(gap, (need / (TWO_PI * ringFill) - baseRing) / d)
	end

	local px, py = table.create(n), table.create(n)
	local theta, radiusOf = {}, table.create(n)
	for k, key in bases do
		local i = index[key]
		theta[key] = BASE_ANGLE[key] or (-math.pi / 2 + (k - 1) * TWO_PI / #bases)
		radiusOf[i] = baseRing
		px[i] = math.cos(theta[key]) * baseRing
		py[i] = math.sin(theta[key]) * baseRing
	end

	-- Охват узла — описанный круг плашки вместе со строкой рецепта под ней. Соседи по
	-- кольцу расходятся по охватам, а не по проекции плашки на кольцо: карта в справочнике
	-- вращается (CraftingUI), и плашка, стоявшая на боку кольца, приезжает наверх, где
	-- по кольцу идёт уже её ширина. По кругам соседи не налезают ни при каком повороте.
	local function reach(i)
		return math.sqrt(hw[i] ^ 2 + (hh[i] + DETAIL_H) ^ 2)
	end
	local function halfArc(i, radius)
		return (reach(i) + NODE_GAP / 2) / radius
	end

	-- Узлы кольца идут по порядку желаемых углов и расталкиваются только с соседями
	-- по кругу. Порядок при равных углах — по номеру, то есть по имени.
	local function spread(members, want, radius)
		table.sort(members, function(a, b)
			if want[a] ~= want[b] then
				return want[a] < want[b]
			end
			return a < b
		end)
		local count = #members
		local at = {}
		for k, i in members do
			at[k] = want[i]
		end
		if count < 2 then
			return at
		end
		for pass = 1, SPREAD_ITERS do
			local worst = 0
			for k = 1, count do
				local nxt = k % count + 1
				local room = at[nxt] - at[k] + (nxt == 1 and TWO_PI or 0)
				local need = halfArc(members[k], radius) + halfArc(members[nxt], radius)
				if room < need then
					local push = (need - room) / 2
					at[k] -= push
					at[nxt] += push
					worst = math.max(worst, need - room)
				end
			end
			if pass <= SPREAD_ITERS * SPREAD_PULL_SHARE then
				for k, i in members do
					at[k] += wrap(want[i] - at[k]) * SPREAD_PULL
				end
			elseif worst < 1e-5 then
				break
			end
		end
		return at
	end

	for d = 1, maxDepth do
		local radius = baseRing + gap * d
		local want = {}
		for _, i in rings[d] do
			local key = keys[i]
			local main, other = theta[mainParent[key]], theta[mate[key]]
			local sx = math.cos(main) + math.cos(other) * MATE_WEIGHT
			local sy = math.sin(main) + math.sin(other) * MATE_WEIGHT
			want[i] = math.atan2(sy, sx) % TWO_PI
		end

		-- Равный шаг: слоты идут в порядке желаемых углов, а весь набор слотов повёрнут
		-- на средний сдвиг желаемых углов от них — кольцо не проворачивается.
		local members = rings[d]
		local count = #members
		if count > 0 then
			table.sort(members, function(a, b)
				if want[a] ~= want[b] then
					return want[a] < want[b]
				end
				return a < b
			end)
			local cs, sn = 0, 0
			for k, i in members do
				local off = want[i] - (k - 1) * TWO_PI / count
				cs += math.cos(off)
				sn += math.sin(off)
			end
			local turn = math.atan2(sn, cs)
			for k, i in members do
				local slot = turn + (k - 1) * TWO_PI / count
				want[i] = (want[i] + wrap(slot - want[i]) * EVEN) % TWO_PI
			end
		end

		local at = spread(members, want, radius)
		for k, i in rings[d] do
			theta[keys[i]] = at[k]
			radiusOf[i] = radius
			px[i] = math.cos(at[k]) * radius
			py[i] = math.sin(at[k]) * radius
		end
	end

	-- ---------- силовое поле по кольцу ----------
	-- Фрухтерман-Рейнгольд поверх тех же колец: все узлы отталкиваются
	-- по k²/d, связи тянут по d²/k, шаг за проход остывает. Радиус узла в этой силе не
	-- участвует: из накопленной силы берётся только составляющая вдоль кольца (перпендикулярная
	-- радиусу), а та, что тянула бы к центру или наружу, отбрасывается — узел облетает
	-- своё кольцо, но с него не сходит. Базовые стихии приколоты: ромб в середине
	-- — решение автора, и поле его не двигает.
	--
	-- Случайных начальных точек нет: поле стартует с углов, что дала формула выше. После
	-- него — та же spread(), что расставляла их: она берёт угол, до которого
	-- долетел узел, следующим желаемым и гарантирует, что соседи по кольцу не налезут
	-- друг на друга ни при каком повороте карты.
	do
		local pinned = {}
		for _, key in bases do
			pinned[index[key]] = true
		end

		local links = {}
		for _, recipe in Recipes.List do
			local child = index[recipe.result]
			if child then
				local i = index[mainParent[recipe.result]]
				local j = index[mate[recipe.result]]
				if i then
					table.insert(links, { i, child })
				end
				if j and j ~= i then
					table.insert(links, { j, child })
				end
			end
		end

		local fx, fy = table.create(n), table.create(n)
		local repel = EXP_LINK * EXP_LINK * EXP_REPEL
		for pass = 1, EXP_ITERS do
			for i = 1, n do
				fx[i], fy[i] = 0, 0
			end
			for i = 1, n - 1 do
				for j = i + 1, n do
					local dx, dy = px[i] - px[j], py[i] - py[j]
					local d2 = dx * dx + dy * dy
					if d2 < 1 then
						-- Два узла в одной точке дали бы деление на ноль: разводим по номеру.
						dx, dy, d2 = (i - j) * 0.5, 0.5, 1
					end
					local push = repel / d2 -- k²/d вдоль единичного вектора между узлами
					fx[i] += dx * push
					fy[i] += dy * push
					fx[j] -= dx * push
					fy[j] -= dy * push
				end
			end
			for _, link in links do
				local i, j = link[1], link[2]
				local dx, dy = px[i] - px[j], py[i] - py[j]
				local pull = math.sqrt(dx * dx + dy * dy) / EXP_LINK -- d²/k вдоль того же вектора
				fx[i] -= dx * pull
				fy[i] -= dy * pull
				fx[j] += dx * pull
				fy[j] += dy * pull
			end
			-- Шаг остывает к концу счёта: с постоянным узлы качались бы вокруг равновесия.
			local step = EXP_STEP_MIN + (EXP_STEP_MAX - EXP_STEP_MIN) * (1 - (pass - 1) / EXP_ITERS)
			for i = 1, n do
				if not pinned[i] then
					-- Только составляющая вдоль кольца: радиальную сила не двигает.
					local r = math.sqrt(px[i] ^ 2 + py[i] ^ 2)
					if r > 1e-6 then
						local tx, ty = -py[i] / r, px[i] / r
						local along = fx[i] * tx + fy[i] * ty
						fx[i], fy[i] = tx * along, ty * along
					end
					local f = math.sqrt(fx[i] ^ 2 + fy[i] ^ 2)
					if f > step then
						fx[i], fy[i] = fx[i] * step / f, fy[i] * step / f
					end
					px[i] += fx[i]
					py[i] += fy[i]
					-- Прямой шаг по касательной чуть срезает дугу окружности — возвращаем
					-- узел точно на его радиус.
					local nr = math.sqrt(px[i] ^ 2 + py[i] ^ 2)
					if nr > 1e-6 then
						local back = radiusOf[i] / nr
						px[i], py[i] = px[i] * back, py[i] * back
					end
				end
			end
		end

		for i = 1, n do
			theta[keys[i]] = math.atan2(py[i], px[i])
		end

		-- Финальная расстановка каждого кольца — той же функцией, что и начальная,
		-- только желаемый угол берёт не сумма направлений на ингредиенты, а то, куда
		-- узел довело поле.
		for d = 1, maxDepth do
			local members = rings[d]
			if #members > 0 then
				local radius = baseRing + gap * d
				local want = {}
				for _, i in members do
					want[i] = theta[keys[i]]
				end
				local at = spread(members, want, radius)
				for k, i in members do
					theta[keys[i]] = at[k]
					px[i] = math.cos(at[k]) * radius
					py[i] = math.sin(at[k]) * radius
				end
			end
		end
	end

	-- ---------- дуги ----------
	-- Связь — кубическая Безье: точки управления на середине пути по радиусу, каждая на угле
	-- своего конца, так что дуга выходит из родителя и входит в ребёнка вдоль радиуса.
	-- Концы срезаны у узлов на END_PAD. Параметр среза ищется делением пополам: у края узла расстояние
	-- от конца вдоль дуги только растёт.
	local function curve(i, j)
		local mid = (radiusOf[i] + radiusOf[j]) / 2
		local thI, thJ = theta[keys[i]], theta[keys[j]]
		local c = {
			px[i], py[i],
			math.cos(thI) * mid, math.sin(thI) * mid,
			math.cos(thJ) * mid, math.sin(thJ) * mid,
			px[j], py[j],
		}
		local function away(t, x, y)
			local bx, by = Graph.BezierAt(c, t)
			return math.sqrt((bx - x) ^ 2 + (by - y) ^ 2)
		end
		local lo, hi = 0, 1
		for _ = 1, 30 do
			local t = (lo + hi) / 2
			if away(t, c[1], c[2]) >= hh[i] + END_PAD then
				hi = t
			else
				lo = t
			end
		end
		local t0 = hi
		lo, hi = 0, 1
		for _ = 1, 30 do
			local t = (lo + hi) / 2
			if away(t, c[7], c[8]) >= hh[j] + END_PAD then
				lo = t
			else
				hi = t
			end
		end
		return Graph.BezierPart(c, t0, math.max(lo, t0))
	end

	-- Связи: обе — и от старшего родителя, и от второго ингредиента.
	local edges = {}
	for _, recipe in Recipes.List do
		local child = index[recipe.result]
		if child then
			local main, other = mainParent[recipe.result], mate[recipe.result]
			table.insert(edges, {
				parent = main,
				child = recipe.result,
				main = true,
				curve = curve(index[main], child),
			})
			if other ~= main then
				table.insert(edges, {
					parent = other,
					child = recipe.result,
					main = false,
					curve = curve(index[other], child),
				})
			end
		end
	end

	-- ---------- кольца ярусов ----------
	-- Узел сидит ровно на своём кольце, и круг под ним — не обещание, а факт раскладки.
	local guides = {}
	for d = 1, maxDepth do
		local radius = baseRing + gap * d
		local ring = {}
		for k = 0, RING_POINTS do
			local a = k / RING_POINTS * TWO_PI
			ring[k + 1] = { math.cos(a) * radius, math.sin(a) * radius }
		end
		table.insert(guides, ring)
	end

	-- ---------- перенос в холст ----------
	-- Холст — квадрат с серединой ромба в центре: CraftingUI вращает карту вокруг этой
	-- точки, и в квадрат со стороной в два самых дальних охвата помещается любой поворот.
	-- Дуги из него не выходят: их точки управления лежат не дальше концов от середины.
	-- Кольца входят в холст наравне с узлами.
	local extent = baseRing + gap * maxDepth
	for i = 1, n do
		extent = math.max(extent, math.sqrt(px[i] ^ 2 + py[i] ^ 2) + reach(i))
	end
	local minX, minY = -extent, -extent
	local maxX, maxY = extent, extent

	local offX, offY = MARGIN - minX, MARGIN - minY
	local nodes = {}
	for i, key in keys do
		nodes[key] = {
			x = px[i] + offX,
			y = py[i] + offY,
			w = hw[i] * 2,
			h = hh[i] * 2,
			base = producedBy[key] == nil,
			group = group[key],
		}
	end
	for _, edge in edges do
		for k = 1, 7, 2 do
			edge.curve[k] += offX
			edge.curve[k + 1] += offY
		end
	end
	for _, ring in guides do
		for _, pt in ring do
			pt[1] += offX
			pt[2] += offY
		end
	end

	built = {
		nodes = nodes,
		edges = edges,
		guides = guides,
		-- Середина ромба базовых: на неё смотрит кнопка «домой», от неё же сторона подписей.
		centre = { offX, offY },
		keys = keys,
		depth = depth,
		mainParent = mainParent,
		mate = mate,
		branch = branch,
		group = group,
		producedBy = producedBy,
		width = math.ceil(maxX - minX + MARGIN * 2),
		height = math.ceil(maxY - minY + MARGIN * 2),
	}
	return built
end

return Graph
