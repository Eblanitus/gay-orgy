-- Карта справочника: сборка раскладки при первом показе, протяжка и масштаб рукой, движение по кадрам.
-- Вынесено из CraftingReference.luau (поведение то же): файл был слишком велик, чтобы
-- агент читал его целиком. deps — локальные CraftingReference и модулей до этого; ref — общее
-- изменяемое (см. CraftingReference). Возвращается то, что нужно дальше.
return function(deps)
	local Graph = deps.Graph
	local TweenService = deps.TweenService
	local gui = deps.gui
	local UserInputService = deps.UserInputService
	local RunService = deps.RunService
	local ZOOM_STEP = deps.ZOOM_STEP
	local wire = deps.wire
	local spin = deps.spin
	local bookFrame = deps.bookFrame
	local mapFrame = deps.mapFrame
	local graphScroll = deps.graphScroll
	local graphLayer = deps.graphLayer
	local ref = deps.ref
	local applyZoom = deps.applyZoom
	local canvasPad = deps.canvasPad
	local setZoom = deps.setZoom
	local fitZoom = deps.fitZoom
	local cardPlate = deps.cardPlate
	local drawGraph = deps.drawGraph

	-- Раскладка считается не при входе в игру, а при первом открытии справочника: счёт
	-- занимает около четверти секунды, и на слабом телефоне это заметная пауза ровно в тот
	-- момент, когда игрок появляется на арене. До справочника он доходит гораздо позже.
	local function ensureGraph()
		if ref.graph then
			return
		end
		ref.graph = Graph.Build()
		graphLayer.Size = UDim2.new(0, ref.graph.width, 0, ref.graph.height)
		fitZoom()
		drawGraph()
	end

	-- Карта на экране — только когда открыт справочник и выбран раздел «Карта».
	local function mapShown()
		return gui.Enabled and bookFrame.Visible and mapFrame.Visible
	end

	local function onMapShown()
		if bookFrame.Visible and mapFrame.Visible then
			ensureGraph()
		end
	end
	bookFrame:GetPropertyChangedSignal("Visible"):Connect(onMapShown)
	mapFrame:GetPropertyChangedSignal("Visible"):Connect(onMapShown)

	graphScroll:GetPropertyChangedSignal("AbsoluteSize"):Connect(applyZoom)

	-- ---------- как двигают граф ----------
	-- Нажатие ловится через UserInputService, а не на самом холсте: узлы лежат поверх него
	-- и забирали бы нажатие себе (та же причина, что у Theme.DragScroll).

	local panning = false
	local panLast = Vector2.new(0, 0)

	local function inside(gui2d, position)
		local at = gui2d.AbsolutePosition
		local size = gui2d.AbsoluteSize
		return position.X >= at.X and position.X <= at.X + size.X
			and position.Y >= at.Y and position.Y <= at.Y + size.Y
	end

	local function overGraph(position)
		if not mapShown() then
			return false
		end
		-- Карточка лежит поверх карты: протяжка и колесо над ней — её собственная прокрутка.
		if cardPlate.Visible and inside(cardPlate, position) then
			return false
		end
		return inside(graphScroll, position)
	end

	UserInputService.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		local position = Vector2.new(input.Position.X, input.Position.Y)
		if not overGraph(position) then
			return
		end
		panning = true
		panLast = position
		ref.panMoved = 0
		-- Карту взяли рукой: наведение отпускает вид. Нажатие на узел тоже сюда попадает,
		-- но его наведение заводится позже, на отпускании (MouseButton1Click).
		spin.aim = nil
	end)

	UserInputService.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseWheel then
			if overGraph(Vector2.new(input.Position.X, input.Position.Y)) then
				setZoom(ref.zoom + input.Position.Z * ZOOM_STEP)
			end
			return
		end
		if not panning then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.MouseMovement
			and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		local position = Vector2.new(input.Position.X, input.Position.Y)
		local shift = position - panLast
		-- Копим пройденное, а не смотрим на расстояние от начала: карту часто тащат
		-- туда-сюда и отпускают там же, где взяли, — выбором это быть не должно.
		ref.panMoved += shift.Magnitude
		graphScroll.CanvasPosition = graphScroll.CanvasPosition - shift
		panLast = position
	end)

	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			panning = false
		end
	end)

	-- Каждый кадр, пока карта на экране: вращение или наведение, затем перенос кривых.
	-- Пока элемент выбран, поворот стоит там, куда его привело наведение (или протяжка,
	-- которая его прервала); снятый выбор снова пускает карту. Кривые сверяются каждый
	-- кадр: вид двигают и рукой, и колесом, и наведением, и поворотом, и ростом окна при
	-- открытии — ловить каждое по отдельности ненадёжно, а сверка пяти значений за кадр
	-- ничего не стоит.
	RunService.RenderStepped:Connect(function(dt)
		if not (mapShown() and ref.graph) then
			return
		end
		local aim = spin.aim
		if aim then
			aim.t = math.min(1, aim.t + dt / spin.AIM_TIME)
			local k = TweenService:GetValue(aim.t, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
			spin.angle = (aim.from + aim.turn * k) % (math.pi * 2)
			ref.zoom = aim.zoom + (aim.toZoom - aim.zoom) * k
			applyZoom() -- через applyLod ставит и узлы под новый поворот
			local place = ref.graph.nodes[aim.key]
			local ox, oy = ref.graph.centre[1], ref.graph.centre[2]
			local c, s = math.cos(spin.angle), math.sin(spin.angle)
			local dx, dy = place.x - ox, place.y - oy
			local target = Vector2.new(ox + dx * c - dy * s, oy + dx * s + dy * c)
			local want = aim.look:Lerp(target, k) * ref.zoom + canvasPad() - graphScroll.AbsoluteSize / 2
			graphScroll.CanvasPosition = Vector2.new(math.max(0, want.X), math.max(0, want.Y))
			if aim.t >= 1 then
				spin.aim = nil
			end
		elseif ref.selected == nil then
			spin.angle = (spin.angle + spin.SPEED * dt) % (math.pi * 2)
			spin.place()
		end
		wire.update()
	end)
end
