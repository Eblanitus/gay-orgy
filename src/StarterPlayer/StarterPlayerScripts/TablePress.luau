-- Пресс алхимического стола (идея автора, #292; сменил сплетание TableFusion из #291).
-- Над двумя слотами — плита на штоках. Рычаг (TableLever) ведёт её вниз: плита ложится
-- на слоты, сплющивает их и сдвигает друг к другу. Дотянули — элементы раздавлены (брызги
-- их цветами), плита остаётся внизу и подрагивает, пока не ответит сервер. Ответ — плита
-- поднимается, под ней в середине лежит результат; неудача — осколки цвета danger.
-- Забранный результат летит дугой в свою ячейку инвентаря.
--
-- Press.Mount(page, parts) — parts: { slotA, slotB, plus, result }. Возвращает:
--   room(h)      — сколько места оставить над слотами высотой h;
--   layout(g)    — g: { ax, bx, y, w, h, top } — где слоты в покое и верх верстака;
--   lever(pos)   — положение ручки рычага, 0..1;
--   hold()       — плита остаётся внизу (ждём сервер);
--   release(fn)  — плита поднимается; fn() — когда открылась середина;
--   slam(fn)     — быстрый удар без рычага (пачка, шаги цепочки); fn() — в миг удара;
--   crush(cA, cB) — брызги раздавленных элементов;
--   crack()      — осколки неудачи из середины;
--   fly(from, to, color, done) — шар из середины from (GuiObject) в середину to.
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent:WaitForChild("UITheme"))

local Press = {}

local TUNING = {
	plate = 0.16, -- толщина плиты: доля высоты слота
	gap = 4, -- в покое плита висит над слотами на столько пикселей
	squash = 0.62, -- дотянули — слот сплющен на эту долю высоты
	converge = 0.3, -- слоты сдвигаются к середине на эту долю ширины слота (поверх зазора)
	rods = 0.18, -- штоки: на этой доле ширины плиты от краёв
	wobble = 2, -- дрожь плиты в ожидании, пиксели
	lift = 0.4, -- подъём после ответа, секунды
	slamDown = 0.1, -- удар: вниз, секунды
	slamUp = 0.22, -- удар: вверх, секунды
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

	local plate = make("PressPlate", page, z)
	plate.BackgroundColor3 = Theme.color.panelSoft
	plate.BackgroundTransparency = 0.05
	round(plate, UDim.new(0, 4))
	local plateStroke = Instance.new("UIStroke")
	plateStroke.Color = Theme.color.grid
	plateStroke.Thickness = 2
	plateStroke.Parent = plate
	-- Насечки по плите — чтобы читалась как металл, а не как кнопка.
	for i = 1, 3 do
		local line = make("Rib", plate, z)
		line.AnchorPoint = Vector2.new(0.5, 0.5)
		line.Position = UDim2.fromScale(0.5, i / 4)
		line.Size = UDim2.new(0.9, 0, 0, 1)
		line.BackgroundColor3 = Theme.color.grid
		line.BackgroundTransparency = 0.5
	end
	local rods = {}
	for i = 1, 2 do
		local rod = make("Rod" .. i, page, z - 1)
		rod.AnchorPoint = Vector2.new(0.5, 0)
		rod.BackgroundColor3 = Theme.color.grid
		rod.BackgroundTransparency = 0.2
		rods[i] = rod
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
		local ph = math.max(6, math.floor(g.h * TUNING.plate))
		local drop = g.h * TUNING.squash
		local bottom = g.y - TUNING.gap + p * (drop + TUNING.gap)
		if waiting then
			bottom += math.sin(clock * 40) * TUNING.wobble * 0.5
		end
		local left, right = g.ax, g.bx + g.w
		plate.Position = UDim2.fromOffset(left, math.floor(bottom - ph))
		plate.Size = UDim2.fromOffset(right - left, ph)
		for i, rod in rods do
			local x = left + (right - left) * (i == 1 and TUNING.rods or 1 - TUNING.rods)
			rod.Position = UDim2.fromOffset(math.floor(x), g.top)
			rod.Size = UDim2.fromOffset(3, math.max(0, math.floor(bottom - ph - g.top)))
		end
		local squash = math.max(0, bottom - g.y)
		local shift = p * ((g.bx - g.ax - g.w) / 2 + g.w * TUNING.converge)
		local h = math.max(2, g.h - squash)
		slotA.Position = UDim2.fromOffset(math.floor(g.ax + shift), math.floor(g.y + squash))
		slotB.Position = UDim2.fromOffset(math.floor(g.bx - shift), math.floor(g.y + squash))
		slotA.Size = UDim2.fromOffset(g.w, math.floor(h))
		slotB.Size = slotA.Size
		plus.TextTransparency = math.clamp(p * 2, 0, 1)
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
		plus.Position = UDim2.fromOffset(g.ax + g.w, g.y)
		plus.Size = UDim2.fromOffset(g.bx - g.ax - g.w, g.h)
		local mid = (g.ax + g.bx + g.w) / 2
		result.Position = UDim2.fromOffset(math.floor(mid - g.w / 2), g.y)
		result.Size = UDim2.fromOffset(g.w, g.h)
		apply()
	end

	-- Сколько места над слотами нужно плите и штокам при высоте слота h.
	function self.room(h)
		return math.max(6, math.floor(h * TUNING.plate)) + TUNING.gap + 6
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
			-- Середина открывается, когда плита поднялась над слотами наполовину.
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
					-- Брызги — вбок и чуть вверх: плита давит сверху.
					local side = rng:NextNumber(-1, 1)
					local by = Vector2.new(side * g.w * 0.6, -rng:NextNumber(0.05, 0.45) * g.h)
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
