-- Пресс алхимического стола (идея автора, #292; сменил сплетание TableFusion из #291).
-- Два поршня — слева и справа от слотов (просьба автора: «один пресс слева, другой справа,
-- сливают в одну точку»). Рычаг (TableLever) ведёт их к середине: слоты сжимаются по
-- ширине, пока поршни не сойдутся. Дотянули — элементы раздавлены (брызги их цветами вверх
-- и вниз), поршни сжаты и подрагивают, пока не ответит сервер. Ответ — поршни расходятся,
-- в середине лежит результат; неудача — осколки цвета danger.
-- Забранный результат летит дугой в свою ячейку инвентаря.
--
-- Press.Mount(page, parts) — parts: { slotA, slotB, plus, result }. Возвращает:
--   layout(g)    — g: { left, right, y, h, sign } — ряд слотов: края, верх, высота, место «+»;
--   lever(pos)   — положение ручки рычага, 0..1;
--   hold()       — поршни остаются сжатыми (ждём сервер);
--   release(fn)  — поршни расходятся; fn() — когда открылась середина;
--   slam(fn)     — быстрый удар без рычага (пачка, шаги цепочки); fn() — в миг удара;
--   crush(cA, cB) — брызги раздавленных элементов;
--   crack()      — осколки неудачи из середины;
--   fly(from, to, color, done) — шар из середины from (GuiObject) в середину to.
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent:WaitForChild("UITheme"))

local Press = {}

local TUNING = {
	plate = 0.16, -- толщина поршня: доля высоты слота
	overhang = 4, -- поршень выше и ниже слота на столько пикселей
	gap = 4, -- в покое между поршнем и слотом столько пикселей
	meet = 2, -- сжатые поршни не доходят до середины на столько пикселей
	rods = 0.3, -- штоки: на этой доле высоты поршня от краёв
	wobble = 2, -- дрожь поршней в ожидании, пиксели
	lift = 0.4, -- расход после ответа, секунды
	slamDown = 0.1, -- удар: сжатие, секунды
	slamUp = 0.22, -- удар: расход, секунды
	drops = 7, -- брызг от каждого раздавленного элемента
	dropFly = 0.55, -- брызги летят, секунды
	shards = 10, -- осколков неудачи
	flyTime = 0.55, -- полёт результата в инвентарь, секунды
	flyArc = 0.35, -- дуга полёта: подъём на эту долю расстояния
}

local function make(name, parent, z)
	local f = Instance.new("Frame")
	f.Name = name
	f.BorderSizePixel = 0
	f.BackgroundTransparency = 1
	f.ZIndex = z
	f.Parent = parent
	return f
end

local function round(f, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = r or UDim.new(0.5, 0)
	c.Parent = f
end

function Press.Mount(page, parts)
	local slotA, slotB, plus, result = parts.slotA, parts.slotB, parts.plus, parts.result
	local z = slotA.ZIndex + 3

	local plates, rods = {}, {}
	for side = 1, 2 do
		local plate = make("PressPlate" .. side, page, z)
		plate.BackgroundColor3 = Theme.color.panelSoft
		plate.BackgroundTransparency = 0.05
		round(plate, UDim.new(0, 4))
		local plateStroke = Instance.new("UIStroke")
		plateStroke.Color = Theme.color.textDim
		plateStroke.Thickness = 2
		plateStroke.Parent = plate
		-- Насечки поперёк поршня — чтобы читался как металл, а не как кнопка.
		for i = 1, 3 do
			local line = make("Rib", plate, z)
			line.AnchorPoint = Vector2.new(0.5, 0.5)
			line.Position = UDim2.fromScale(i / 4, 0.5)
			line.Size = UDim2.new(0, 1, 0.8, 0)
			line.BackgroundColor3 = Theme.color.textDim
			line.BackgroundTransparency = 0.5
		end
		plates[side] = plate
		-- Штоки: от края верстака к поршню, видны, когда поршень выехал.
		rods[side] = {}
		for i = 1, 2 do
			local rod = make("Rod", page, z - 1)
			rod.AnchorPoint = Vector2.new(0, 0.5)
			rod.BackgroundColor3 = Theme.color.textDim
			rod.BackgroundTransparency = 0.3
			rods[side][i] = rod
		end
	end

	local layer = make("PressFx", page, z + 2)
	layer.Size = UDim2.fromScale(1, 1)

	local g = nil
	local leverPos, holdValue, waiting = 0, Instance.new("NumberValue"), false
	local clock = 0

	local function apply()
		if not g then
			return
		end
		local p = math.max(leverPos, holdValue.Value)
		local pw = math.max(8, math.floor(g.h * TUNING.plate))
		local mid = (g.left + g.right) / 2
		-- Внутренние кромки поршней: в покое у краёв, дотянули — почти в середине.
		local push = p * (mid - TUNING.meet - g.left - pw)
		if waiting then
			push += math.sin(clock * 40) * TUNING.wobble * 0.5
		end
		local edgeL, edgeR = g.left + pw + push, g.right - pw - push
		local py, ph = g.y - TUNING.overhang, g.h + TUNING.overhang * 2
		plates[1].Position = UDim2.fromOffset(math.floor(edgeL - pw), py)
		plates[2].Position = UDim2.fromOffset(math.floor(edgeR), py)
		for side = 1, 2 do
			plates[side].Size = UDim2.fromOffset(pw, ph)
			for i, rod in rods[side] do
				local y = math.floor(py + ph * (i == 1 and TUNING.rods or 1 - TUNING.rods))
				local x0 = side == 1 and g.left or math.floor(edgeR + pw)
				local x1 = side == 1 and math.floor(edgeL - pw) or g.right
				rod.Position = UDim2.fromOffset(x0, y)
				rod.Size = UDim2.fromOffset(math.max(0, x1 - x0), 3)
			end
		end
		-- Слоты зажаты между поршнем и «+»: сжимаются по ширине, «+» исчезает.
		local gap, half = TUNING.gap * (1 - p), g.sign / 2 * (1 - p)
		local wA = math.max(0, mid - half - (edgeL + gap))
		slotA.Position = UDim2.fromOffset(math.floor(edgeL + gap), g.y)
		slotB.Position = UDim2.fromOffset(math.floor(mid + half), g.y)
		slotA.Size = UDim2.fromOffset(math.floor(wA), g.h)
		slotB.Size = UDim2.fromOffset(math.floor(math.max(0, edgeR - gap - (mid + half))), g.h)
		local fade = math.clamp(p * 2, 0, 1)
		plus.TextTransparency = fade
		for _, slot in { slotA, slotB } do
			local caption = slot:FindFirstChild("Caption")
			if caption then
				caption.TextTransparency = fade
			end
		end
	end
	holdValue.Changed:Connect(apply)

	RunService.Heartbeat:Connect(function(dt)
		if waiting then
			clock += dt
			apply()
		end
	end)

	local self = {}

	function self.layout(geom)
		g = geom
		local mid = (g.left + g.right) / 2
		plus.Position = UDim2.fromOffset(math.floor(mid - g.sign / 2), g.y)
		plus.Size = UDim2.fromOffset(g.sign, g.h)
		-- Результат — в середине, шириной со слот в покое.
		local pw = math.max(8, math.floor(g.h * TUNING.plate))
		local w = math.floor(mid - g.sign / 2 - g.left - pw - TUNING.gap)
		result.Position = UDim2.fromOffset(math.floor(mid - w / 2), g.y)
		result.Size = UDim2.fromOffset(w, g.h)
		apply()
	end

	function self.lever(pos)
		leverPos = pos
		apply()
	end

	local tween
	local function to(value, time, style, dir, done)
		if tween then
			tween:Cancel()
		end
		tween = TweenService:Create(holdValue, TweenInfo.new(time, style, dir), { Value = value })
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

	function self.hold()
		if tween then
			tween:Cancel()
		end
		holdValue.Value = 1
		waiting = true
	end

	function self.release(done)
		waiting = false
		to(0, TUNING.lift, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		if done then
			-- Середина открывается, когда поршни чуть разошлись.
			task.delay(TUNING.lift * 0.35, done)
		end
	end

	function self.slam(done)
		if waiting then
			if done then
				done()
			end
			return
		end
		to(1, TUNING.slamDown, Enum.EasingStyle.Quad, Enum.EasingDirection.In, function()
			if done then
				done()
			end
			to(0, TUNING.slamUp, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		end)
	end

	local function center(gui)
		return gui.AbsolutePosition + gui.AbsoluteSize / 2 - layer.AbsolutePosition
	end

	-- Частица: кружок из точки from летит на смещение by и гаснет.
	local function particle(from, by, color, size, time)
		local f = make("Drop", layer, layer.ZIndex)
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.BackgroundColor3 = color
		f.BackgroundTransparency = 0.05
		f.Position = UDim2.fromOffset(from.X, from.Y)
		f.Size = UDim2.fromOffset(size, size)
		round(f)
		local info = TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local to2 = from + by
		TweenService:Create(f, info, {
			Position = UDim2.fromOffset(to2.X, to2.Y),
			Size = UDim2.fromOffset(size * 0.4, size * 0.4),
			BackgroundTransparency = 1,
		}):Play()
		task.delay(time, function()
			f:Destroy()
		end)
	end

	function self.crush(colorA, colorB)
		if not g then
			return
		end
		local rng = Random.new()
		for i, slot in { slotA, slotB } do
			local c = center(slot)
			local color = i == 1 and colorA or colorB
			if color then
				for _ = 1, TUNING.drops do
					-- Брызги — вверх и вниз: поршни давят с боков.
					local up = rng:NextNumber() < 0.5 and -1 or 1
					local by = Vector2.new(rng:NextNumber(-0.25, 0.25) * g.h, up * rng:NextNumber(0.4, 0.8) * g.h)
					particle(c, by, color, rng:NextNumber(5, 11), TUNING.dropFly)
				end
			end
		end
	end

	function self.crack()
		if not g then
			return
		end
		local rng = Random.new()
		local c = center(result)
		for i = 1, TUNING.shards do
			local ang = (i / TUNING.shards) * math.pi * 2 + rng:NextNumber(-0.3, 0.3)
			local by = Vector2.new(math.cos(ang), math.sin(ang)) * g.h * rng:NextNumber(0.35, 0.7)
			particle(c, by, Theme.color.danger, rng:NextNumber(4, 9), TUNING.dropFly)
		end
	end

	-- Полёт по дуге (квадратичная кривая через точку над серединой пути).
	function self.fly(from, target, color, done)
		local p0 = center(from)
		local p2 = center(target)
		local lift = (p2 - p0).Magnitude * TUNING.flyArc
		local p1 = (p0 + p2) / 2 - Vector2.new(0, lift)
		local s = math.max(14, from.AbsoluteSize.Y * 0.4)
		local orb = make("Flying", layer, layer.ZIndex)
		orb.AnchorPoint = Vector2.new(0.5, 0.5)
		orb.BackgroundColor3 = color
		orb.BackgroundTransparency = 0.05
		orb.Size = UDim2.fromOffset(s, s)
		round(orb)
		local rim = Instance.new("UIStroke")
		rim.Color = Color3.new(1, 1, 1)
		rim.Transparency = 0.5
		rim.Thickness = 1.5
		rim.Parent = orb
		local t = 0
		local conn
		conn = RunService.Heartbeat:Connect(function(dt)
			t = math.min(1, t + dt / TUNING.flyTime)
			local e = t * t * (3 - 2 * t)
			local q = (1 - e) * (1 - e) * p0 + 2 * (1 - e) * e * p1 + e * e * p2
			orb.Position = UDim2.fromOffset(q.X, q.Y)
			local k = 1 - 0.45 * e
			orb.Size = UDim2.fromOffset(s * k, s * k)
			if t >= 1 then
				conn:Disconnect()
				orb:Destroy()
				if done then
					done()
				end
			end
		end)
	end

	return self
end

return Press
