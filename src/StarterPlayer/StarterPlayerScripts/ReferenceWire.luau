-- Кривые карты справочника (Path2D): добавление, обрезка по окну, перенос под вид — функции таблицы wire.
-- Вынесено из CraftingReference.luau (поведение то же): файл был слишком велик, чтобы
-- агент читал его целиком. deps — локальные CraftingReference и модулей до этого; ref — общее
-- изменяемое (см. CraftingReference). Возвращается то, что нужно дальше.
return function(deps)
	local Theme = deps.Theme
	local Graph = deps.Graph
	local LINE_GROUND = deps.LINE_GROUND
	local wire = deps.wire
	local spin = deps.spin
	local graphLayer = deps.graphLayer
	local ref = deps.ref
	local orbitShown = deps.orbitShown

	local ARROW = 8 -- длина уса наконечника

	-- Бледность колец ярусов: насколько их цвет смешан с фоном (wire.rings).
	local BEAD = 0.35
	-- Кольца ярусов под связями (RecipeGraph, guides): сплошные и еле заметные — подложка,
	-- по которой читается глубина, а не ещё одна сетка поверх паутины.
	local GUIDE = Theme.color.panel:Lerp(Theme.color.steel, 0.14)
	-- ---------- кривые карты ----------
	-- Связь — не цепочка повёрнутых рамок, а Path2D: настоящая кривая
	-- Безье из раскладки (RecipeGraph, edge.curve). Цепочка рамок давала засечку на каждом
	-- стыке звеньев, а пять тысяч рамок во вращающемся слое перерисовывались каждый кадр
	-- и роняли частоту кадров до двадцати (замечание автора).
	--
	-- Path2D не подчиняется ни UIScale слоя, ни повороту родителя, ни обрезке окна
	-- (ClipsDescendants и CanvasGroup — проверено на сборке). Поэтому кривые лежат не в слое,
	-- а в своей рамке поверх окна (wire.view), и когда вид сдвинулся, переводятся в её
	-- пиксели: поворот вокруг середины ромба, масштаб, сдвиг. Безье при таком переносе
	-- остаётся той же кривой — переносятся только четыре её точки. За края окна её режет
	-- wire.clip. Неизменную прозрачности у Path2D нет, и бледность линии всюду смешана с фоном в цвет.

	-- Кривая c — восемь чисел в координатах карты (см. RecipeGraph, BezierAt).
	function wire.add(c, color, thick, z, want)
		local item = {
			c = c,
			q = table.create(8, 0), -- та же кривая в пикселях окна
			paths = {},
			shown = 0, -- сколько из paths сейчас видны
			color = color,
			thick = thick,
			z = z,
			want = want ~= false,
			dirty = true,
		}
		table.insert(wire.items, item)
		wire.dirty = true
		return item
	end

	-- Прямой отрезок той же записью: точки управления на трети и двух третях.
	function wire.segment(x1, y1, x2, y2)
		local dx, dy = (x2 - x1) / 3, (y2 - y1) / 3
		return { x1, y1, x1 + dx, y1 + dy, x2 - dx, y2 - dy, x2, y2 }
	end

	function wire.reset()
		for _, item in wire.items do
			for _, path in item.paths do
				path:Destroy()
			end
		end
		table.clear(wire.items)
		wire.last = nil
	end

	-- Кольца ярусов: каждое — четыре четверти окружности, каждая — кубика с усами в ARC
	-- радиуса (отклонение от окружности — сотые доли радиуса). Радиус берётся
	-- у первой точки кольца: раскладка начинает его с угла ноль, справа от середины.
	function wire.rings()
		local ARC = 0.5523
		local ox, oy = ref.graph.centre[1], ref.graph.centre[2]
		local color = LINE_GROUND:Lerp(GUIDE, 1 - BEAD)
		for d, ring in ref.graph.guides do
			if not orbitShown(d) then
				continue
			end
			local r = ring[1][1] - ox
			for quarter = 0, 3 do
				local a, b = quarter * math.pi / 2, (quarter + 1) * math.pi / 2
				local ca, sa, cb, sb = math.cos(a), math.sin(a), math.cos(b), math.sin(b)
				wire.add({
					ox + ca * r, oy + sa * r,
					ox + (ca - sa * ARC) * r, oy + (sa + ca * ARC) * r,
					ox + (cb + sb * ARC) * r, oy + (sb - cb * ARC) * r,
					ox + cb * r, oy + sb * r,
				}, color, 1, 1)
			end
		end
	end

	-- Связь: полосы градиента от цвета родителя к цвету ребёнка (одна, если цвет один)
	-- и два уса наконечника, по умолчанию скрытые — их зажигает repaint, как и рамки.
	function wire.edge(record, curve, fromColor, toColor, thick)
		local bands = fromColor == toColor and 1 or wire.BANDS
		-- Нахлёст в долях параметра — по длине ломаной точек управления: она не короче кривой.
		local len = 0
		for k = 1, 5, 2 do
			len += math.sqrt((curve[k + 2] - curve[k]) ^ 2 + (curve[k + 3] - curve[k + 1]) ^ 2)
		end
		local lap = wire.LAP / math.max(len, 1)
		record.items, record.itemColors, record.headItems = {}, {}, {}
		for k = 1, bands do
			local t0, t1 = math.max((k - 1) / bands - lap, 0), math.min(k / bands + lap, 1)
			local color = fromColor:Lerp(toColor, (k - 0.5) / bands)
			table.insert(record.items, wire.add(Graph.BezierPart(curve, t0, t1), color, thick, 1))
			table.insert(record.itemColors, color)
		end
		-- Усы идут от конца назад вдоль касательной в конце кривой.
		local ex, ey = curve[7], curve[8]
		local hx, hy = curve[5], curve[6]
		if (ex - hx) ^ 2 + (ey - hy) ^ 2 < 1e-6 then
			hx, hy = curve[3], curve[4]
		end
		local ang = math.atan2(ey - hy, ex - hx)
		for _, side in { 0.45, -0.45 } do
			local wing = wire.segment(ex, ey, ex - math.cos(ang + side) * ARROW, ey - math.sin(ang + side) * ARROW)
			table.insert(record.headItems, wire.add(wing, toColor, thick, 1, false))
		end
	end

	-- Участки кривой q (уже в пикселях окна) внутри окна w×h — пары t0, t1 подряд в out.
	-- Кривая пробуется в PROBES точках, граница участка уточняется делением пополам.
	function wire.clip(q, w, h, out)
		table.clear(out)
		local function inside(t)
			local x, y = Graph.BezierAt(q, t)
			return x >= 0 and x <= w and y >= 0 and y <= h
		end
		local was = inside(0)
		local from = 0
		for k = 1, wire.PROBES do
			local t = k / wire.PROBES
			local now = inside(t)
			if now ~= was then
				local lo, hi = (k - 1) / wire.PROBES, t
				for _ = 1, 10 do
					local mid = (lo + hi) / 2
					if inside(mid) == was then
						lo = mid
					else
						hi = mid
					end
				end
				if now then
					from = lo
				else
					table.insert(out, from)
					table.insert(out, hi)
				end
				was = now
			end
		end
		if was then
			table.insert(out, from)
			table.insert(out, 1)
		end
		return out
	end

	-- Перенос кривых в окно. Зовётся каждый кадр из RenderStepped, но считает только тогда,
	-- когда сдвинулся слой, окно или поворот, либо кривые перекрасили (wire.dirty).
	function wire.update()
		if not ref.graph then
			return
		end
		local view = wire.view
		local layerAt, layerSize = graphLayer.AbsolutePosition, graphLayer.AbsoluteSize
		local viewAt, viewSize = view.AbsolutePosition, view.AbsoluteSize
		if layerSize.X <= 0 or viewSize.X <= 0 then
			return
		end
		local last = wire.last
		if last and not wire.dirty and last[1] == layerAt and last[2] == layerSize and last[3] == viewAt
			and last[4] == viewSize and last[5] == spin.angle then
			return
		end
		wire.last = { layerAt, layerSize, viewAt, viewSize, spin.angle }
		wire.dirty = false

		local scale = layerSize.X / ref.graph.width
		local rescaled = scale ~= wire.scale
		wire.scale = scale
		local ox, oy = ref.graph.centre[1], ref.graph.centre[2]
		local c, s = math.cos(spin.angle) * scale, math.sin(spin.angle) * scale
		-- Точка карты p в пикселях окна: слой − окно + (середина + поворот(p − середина)) · масштаб.
		local bx = layerAt.X - viewAt.X + ox * scale
		local by = layerAt.Y - viewAt.Y + oy * scale
		local w, h = viewSize.X, viewSize.Y
		local spans = wire.spans
		local none = UDim2.new()

		for _, item in wire.items do
			local paths = item.paths
			local count = 0
			-- Толщина тянется с масштабом, как у рамок в слое, но не тоньше пикселя: тоньше
			-- Path2D на отдалении рассыпается на обрывки.
			local thick = math.max(item.thick * scale, 1)
			if item.want then
				local src, q = item.c, item.q
				local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
				for k = 1, 7, 2 do
					local dx, dy = src[k] - ox, src[k + 1] - oy
					local x, y = bx + dx * c - dy * s, by + dx * s + dy * c
					q[k], q[k + 1] = x, y
					x0, x1 = math.min(x0, x), math.max(x1, x)
					y0, y1 = math.min(y0, y), math.max(y1, y)
				end
				-- Кривая лежит внутри оболочки своих точек управления: оболочка за окном —
				-- рисовать нечего, в окне целиком — резать нечего.
				if x1 >= 0 and x0 <= w and y1 >= 0 and y0 <= h then
					if x0 >= 0 and x1 <= w and y0 >= 0 and y1 <= h then
						table.clear(spans)
						spans[1], spans[2] = 0, 1
					else
						wire.clip(q, w, h, spans)
					end
					for k = 1, #spans - 1, 2 do
						local t0, t1 = spans[k], spans[k + 1]
						if t1 > t0 then
							count += 1
							local path = paths[count]
							if not path then
								path = Instance.new("Path2D")
								path.Visible = false
								path.Color3 = item.color
								path.Thickness = thick
								path.ZIndex = item.z
								path.Parent = view
								paths[count] = path
							end
							local p = (t0 == 0 and t1 == 1) and q or Graph.BezierPart(q, t0, t1)
							-- Усы точки Path2D — смещение соседней точки управления Безье от неё самой.
							path:SetControlPoints({
								Path2DControlPoint.new(
									UDim2.fromOffset(p[1], p[2]),
									none,
									UDim2.fromOffset(p[3] - p[1], p[4] - p[2])
								),
								Path2DControlPoint.new(
									UDim2.fromOffset(p[7], p[8]),
									UDim2.fromOffset(p[5] - p[7], p[6] - p[8]),
									none
								),
							})
						end
					end
				end
			end
			-- Видимость и вид пишутся только при перемене: кривых сотни, кадров — шестьдесят в секунду.
			for k = count + 1, item.shown do
				paths[k].Visible = false
			end
			for k = item.shown + 1, count do
				paths[k].Visible = true
			end
			item.shown = count
			if item.dirty or rescaled then
				item.dirty = false
				for _, path in paths do
					path.Color3 = item.color
					path.Thickness = thick
					path.ZIndex = item.z
				end
			end
		end
	end
end
