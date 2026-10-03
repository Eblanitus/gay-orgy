-- Рычаг крафта на алхимическом столе (идея автора, #291): кнопка не спрашивает «точно?»,
-- её тянут вниз. Ручка с колбой ходит по жёлобу; дотянули до низа — крафт, отпустили —
-- ручка пружинит обратно. По жёлобу бегут стрелки вниз. Простой щелчок только качнёт
-- ручку; второй щелчок подряд — значит, игрок не понял: рядом всплывает «ТЯНИ ВНИЗ»,
-- стрелки разгораются.
--
-- Вид терминальный (#297: «выглядит не в терминально»): прямые углы, кант в пиксель.
-- Ручка — плашка во всю ширину с рифлением по бокам; по краям жёлоба шкала из засечек —
-- пройденные загораются; внизу уголками размечено место, куда тянуть; стрелки — пиксельные
-- уголки из квадратиков, а не повёрнутые черты.
--
-- Lever.Mount(button, flask, onPull, onMove) — button — кнопка-жёлоб, flask — иконка
-- (переезжает в ручку), onPull() — дотянули, onMove(pos) — ручка сдвинулась (0 — верх,
-- 1 — низ; необязательный). Возвращает { paint(color), pull() }: pull — тот же ход
-- рычага без мыши (Enter на ПК).
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent:WaitForChild("UITheme"))

local Lever = {}

local TUNING = {
	knob = 0.3, -- ручка: доля высоты жёлоба (и не выше половины его ширины)
	margin = 6, -- зазор ручки от краёв жёлоба, пиксели
	tick = 8, -- шаг засечек шкалы, пиксели
	major = 4, -- каждая такая засечка длиннее
	pixel = 3, -- квадратик стрелки, пиксели
	fire = 0.92, -- на какой доле хода срабатывает
	back = 0.45, -- пружина обратно, секунды
	nudge = 0.22, -- щелчок качает ручку на эту долю хода
	auto = 0.18, -- ход вниз при pull(), секунды
	arrows = 2, -- стрелок вниз по жёлобу
	arrowRate = 3, -- бег стрелок, радиан в секунду
	confusedTaps = 2, -- столько щелчков без хода подряд — показать подсказку
	confusedWindow = 4, -- щелчки считаются подряд, если между ними меньше стольких секунд
	hintTime = 2.5, -- подсказка висит, секунды
}

local function frame(name, parent, z)
	local f = Instance.new("Frame")
	f.Name = name
	f.BorderSizePixel = 0
	f.BackgroundTransparency = 1
	f.ZIndex = z
	f.Parent = parent
	return f
end

function Lever.Mount(button, flask, onPull, onMove)
	local z = button.ZIndex + 1

	-- Жёлоб — линия в пиксель по середине.
	local groove = frame("Groove", button, z)
	groove.AnchorPoint = Vector2.new(0.5, 0)
	groove.BackgroundTransparency = 0.7

	-- Место, куда тянуть: уголки по краям нижнего положения ручки.
	local target = frame("Target", button, z)
	local corners = {}
	for _, c in { Vector2.new(0, 0), Vector2.new(1, 0), Vector2.new(0, 1), Vector2.new(1, 1) } do
		for axis = 1, 2 do
			local bar = frame("Corner", target, z)
			bar.AnchorPoint = c
			bar.Position = UDim2.fromScale(c.X, c.Y)
			bar.Size = axis == 1 and UDim2.fromOffset(8, 1) or UDim2.fromOffset(1, 8)
			bar.BackgroundTransparency = 0.3
			table.insert(corners, bar)
		end
	end

	-- Шкала: засечки по обоим краям жёлоба, пересобираются при смене размера.
	local scale = frame("Scale", button, z)
	scale.Size = UDim2.fromScale(1, 1)
	local ticks = {} -- { bar, y }

	-- Ручка: плашка с кантом, по бокам от колбы рифление — три черты.
	local knob = frame("Knob", button, z + 1)
	knob.AnchorPoint = Vector2.new(0.5, 0)
	knob.BackgroundTransparency = 0
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 1
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = knob
	local grips = {}
	for side = 0, 1 do
		for row = 1, 3 do
			local line = frame("Grip", knob, z + 1)
			line.AnchorPoint = Vector2.new(side, 0.5)
			line.Position = UDim2.new(side, side == 0 and 6 or -6, 0.5, (row - 2) * 4)
			line.Size = UDim2.new(0.18, 0, 0, 1)
			line.BackgroundTransparency = 0.45
			table.insert(grips, line)
		end
	end

	-- Стрелки вниз: уголок из пяти квадратиков, как пиксельная «v».
	local arrows = {}
	for i = 1, TUNING.arrows do
		local holder = frame("Arrow" .. i, button, z)
		holder.AnchorPoint = Vector2.new(0.5, 0.5)
		local px = TUNING.pixel
		holder.Size = UDim2.fromOffset(px * 5, px * 3)
		local bars = {}
		for k, off in { { -2, 0 }, { -1, 1 }, { 0, 2 }, { 1, 1 }, { 2, 0 } } do
			local bar = frame("Px" .. k, holder, z)
			bar.Position = UDim2.fromOffset((off[1] + 2) * px, off[2] * px)
			bar.Size = UDim2.fromOffset(px, px)
			bar.BackgroundTransparency = 0.5
			table.insert(bars, bar)
		end
		arrows[i] = { holder = holder, bars = bars }
	end

	-- Подсказка «тяни вниз» — слева от рычага, крупно.
	local hint = Instance.new("TextLabel")
	hint.Name = "LeverHint"
	hint.AnchorPoint = Vector2.new(1, 0.5)
	hint.BackgroundColor3 = Color3.new(0, 0, 0)
	hint.BackgroundTransparency = 0.25
	hint.BorderSizePixel = 0
	hint.FontFace = Theme.font.strong
	hint.TextSize = 18
	hint.TextColor3 = Color3.new(1, 1, 1)
	hint.Text = "ТЯНИ ВНИЗ  ↓"
	hint.AutomaticSize = Enum.AutomaticSize.X
	hint.Size = UDim2.fromOffset(0, 40)
	hint.ZIndex = z + 4
	hint.Visible = false
	local hintPad = Instance.new("UIPadding")
	hintPad.PaddingLeft = UDim.new(0, 14)
	hintPad.PaddingRight = UDim.new(0, 14)
	hintPad.Parent = hint
	local hintStroke = Instance.new("UIStroke")
	hintStroke.Thickness = 1
	hintStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	hintStroke.Parent = hint
	hint.Parent = button.Parent

	flask.Parent = knob
	flask.Size = UDim2.fromScale(0.72, 0.72)
	for _, d in flask:GetDescendants() do
		if d:IsA("GuiObject") then
			d.ZIndex = z + 2
		end
	end
	flask.ZIndex = z + 2

	local pos = 0 -- ход ручки, 0 — верх, 1 — низ
	local k, travel, margin = 0, 0, TUNING.margin

	local color = Theme.color.textMute
	local function place()
		knob.Position = UDim2.new(0.5, 0, 0, margin + pos * travel)
		-- Пройденные засечки (выше низа ручки) горят.
		local bottom = margin + pos * travel + k
		for _, tk in ticks do
			tk.bar.BackgroundTransparency = tk.y <= bottom and 0.15 or 0.7
		end
		if onMove then
			onMove(pos)
		end
	end

	local function layout()
		local W, H = button.AbsoluteSize.X, button.AbsoluteSize.Y
		local kw = math.max(0, math.floor(W - margin * 2 - 16))
		k = math.floor(math.min(W * 0.5, H * TUNING.knob))
		travel = math.max(0, H - margin * 2 - k)
		knob.Size = UDim2.fromOffset(kw, k)
		groove.Position = UDim2.new(0.5, 0, 0, margin + k / 2)
		groove.Size = UDim2.new(0, 1, 0, travel)
		target.AnchorPoint = Vector2.new(0.5, 0)
		target.Position = UDim2.new(0.5, 0, 0, margin + travel - 3)
		target.Size = UDim2.fromOffset(kw + 6, k + 6)
		local gap = math.max(1, travel - k) -- между ручкой в покое и местом внизу
		for i, arrow in arrows do
			arrow.holder.Position = UDim2.new(0.5, 0, 0, margin + k + gap * i / (#arrows + 1))
		end
		for _, tk in ticks do
			tk.bar:Destroy()
		end
		table.clear(ticks)
		local n = math.floor((H - margin * 2) / TUNING.tick)
		for i = 0, n do
			local y = margin + i * TUNING.tick
			local long = i % TUNING.major == 0
			for side = 0, 1 do
				local bar = frame("Tick", scale, z)
				bar.AnchorPoint = Vector2.new(side, 0)
				bar.Position = UDim2.new(side, side == 0 and 2 or -2, 0, y)
				bar.Size = UDim2.fromOffset(long and 6 or 3, 1)
				bar.BackgroundColor3 = color
				table.insert(ticks, { bar = bar, y = y })
			end
		end
		place()
	end
	button:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
	layout()

	-- Плавный ход — через NumberValue: твин двигает число, число — ручку.
	local value = Instance.new("NumberValue")
	value.Changed:Connect(function(v)
		pos = v
		place()
	end)
	local tween
	local function moveTo(target, time, style, dir, done)
		if tween then
			tween:Cancel()
		end
		value.Value = pos
		tween = TweenService:Create(value, TweenInfo.new(time, style, dir), { Value = target })
		if done then
			local t = tween
			t.Completed:Connect(function(state)
				if state == Enum.PlaybackState.Completed then
					done()
				end
			end)
		end
		tween:Play()
	end
	local function springBack()
		moveTo(0, TUNING.back, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	end

	-- Стрелки бегут волной вниз; пока висит подсказка — ярче и быстрее.
	local hintUntil = 0
	local clock = 0
	RunService.Heartbeat:Connect(function(dt)
		if button.AbsoluteSize.X < 1 or not button.Visible then
			return
		end
		clock += dt
		local loud = os.clock() < hintUntil
		local rate = TUNING.arrowRate * (loud and 2 or 1)
		for i, arrow in arrows do
			local wave = 0.5 + 0.5 * math.sin(clock * rate - i * 0.9)
			local t = loud and (0.6 - 0.6 * wave) or (0.85 - 0.45 * wave)
			for _, bar in arrow.bars do
				bar.BackgroundTransparency = t
			end
		end
		if hint.Visible and not loud then
			hint.Visible = false
		end
	end)

	local taps = {}
	local function confused()
		local now = os.clock()
		table.insert(taps, now)
		while #taps > 0 and now - taps[1] > TUNING.confusedWindow do
			table.remove(taps, 1)
		end
		if #taps < TUNING.confusedTaps then
			return
		end
		table.clear(taps)
		local parent = button.Parent
		local rel = button.AbsolutePosition - parent.AbsolutePosition
		hint.Position = UDim2.fromOffset(rel.X - 10, rel.Y + button.AbsoluteSize.Y / 2)
		hint.Visible = true
		hintUntil = now + TUNING.hintTime
	end

	local dragging, startY, fired, moved = nil, 0, false, false

	button.InputBegan:Connect(function(input)
		local kind = input.UserInputType
		if kind ~= Enum.UserInputType.MouseButton1 and kind ~= Enum.UserInputType.Touch then
			return
		end
		if tween then
			tween:Cancel()
		end
		dragging, startY, fired, moved = input, input.Position.Y - pos * travel, false, false
		hint.Visible = false
		hintUntil = 0
	end)

	UserInputService.InputChanged:Connect(function(input)
		if not dragging then
			return
		end
		local touch = dragging.UserInputType == Enum.UserInputType.Touch
		if (touch and input ~= dragging) or (not touch and input.UserInputType ~= Enum.UserInputType.MouseMovement) then
			return
		end
		if fired or travel < 1 then
			return
		end
		pos = math.clamp((input.Position.Y - startY) / travel, 0, 1)
		moved = moved or pos > 0.05
		place()
		if pos >= TUNING.fire then
			fired = true
			pos = 1
			place()
			onPull()
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		if not dragging then
			return
		end
		local touch = dragging.UserInputType == Enum.UserInputType.Touch
		if (touch and input ~= dragging) or (not touch and input.UserInputType ~= Enum.UserInputType.MouseButton1) then
			return
		end
		dragging = nil
		if not fired and not moved then
			-- Щелчок: ручка качнулась вниз и вернулась — «тяни».
			moveTo(TUNING.nudge, 0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, springBack)
			confused()
			return
		end
		springBack()
	end)

	local self = {}

	function self.paint(c)
		color = c
		stroke.Color = color
		knob.BackgroundColor3 = Theme.color.panel:Lerp(color, 0.1)
		groove.BackgroundColor3 = color
		for _, bar in corners do
			bar.BackgroundColor3 = color
		end
		for _, line in grips do
			line.BackgroundColor3 = color
		end
		for _, tk in ticks do
			tk.bar.BackgroundColor3 = color
		end
		hintStroke.Color = color
		hint.TextColor3 = color
		for _, arrow in arrows do
			for _, bar in arrow.bars do
				bar.BackgroundColor3 = color
			end
		end
	end

	function self.pull()
		if dragging then
			return
		end
		moveTo(1, TUNING.auto, Enum.EasingStyle.Quad, Enum.EasingDirection.In, function()
			onPull()
			springBack()
		end)
	end

	return self
end

return Lever
