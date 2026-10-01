-- Пресс алхимического стола (идея автора, #292–#294). Два поршня — слева и справа от
-- слотов: «один пресс слева, другой справа, сливают в одну точку». Каждый поршень — корпус
-- у края верстака, шток и голова с рабочей кромкой. Рисунок плоский, как весь интерфейс:
-- заливка панели и тонкий кант, без объёма (#295: «3д графика не вписывается»).
--
-- Рычаг пресс не ведёт (#294: «рукой анимация не реалистичная»): дотянули — пресс работает
-- сам. Замах (головы чуть уходят в корпуса), удар (резко к середине, слоты сжимаются по
-- ширине и вспучиваются), отскок, вспышка в точке встречи, брызги цветами элементов,
-- тряска верстака, кромки раскалены смешанным цветом. Дальше поршни сжаты и подрагивают,
-- пока не ответит сервер. Ответ — поршни расходятся, в середине лежит результат.
--
-- Press.Mount(page, parts) — parts: { slotA, slotB, plus, result }. Возвращает:
--   layout(g)    — g: { left, right, y, h, sign } — ряд слотов: края, верх, высота, место «+»;
--   squeeze(cA, cB, onImpact) — полный ход: замах, удар, поршни остаются сжатыми;
--                  onImpact() — в миг удара;
--   release(fn, start) — поршни расходятся (если удар ещё идёт — после него); start() —
--                  в миг, когда пошли, fn() — когда открылась середина;
--   slam(cA, cB, fn) — короткий удар туда-обратно (пачка, шаги цепочки); fn() — в миг удара;
--   crack()      — осколки неудачи из середины;
--   fly(from, to, color, done) — шар из середины from (GuiObject) в середину to.
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent:WaitForChild("UITheme"))

local Press = {}

local TUNING = {
	head = 0.12, -- толщина головы поршня: доля высоты слота
	housing = 0.14, -- ширина корпуса: доля высоты слота
	housingH = 0.5, -- высота корпуса: доля высоты слота
	rod = 4, -- толщина штока, пиксели
	overhang = 4, -- голова выше и ниже слота на столько пикселей
	gap = 4, -- в покое между головой и слотом столько пикселей
	meet = 1, -- сжатые головы не доходят до середины на столько пикселей
	bulge = 0.14, -- сжатый слот вспучивается по высоте на эту долю
	windup = -0.07, -- замах: головы уходят в корпус на эту долю хода
	windupTime = 0.16, -- замах, секунды
	strikeTime = 0.2, -- удар, секунды
	rebound = 0.9, -- отскок после удара: до этой доли хода
	reboundTime = 0.06, -- отскок, секунды
	settleTime = 0.14, -- обратно в упор, секунды
	minClosed = 0.25, -- сжатыми не меньше, секунды (ответ сервера пришёл раньше удара)
	shake = 5, -- тряска при ударе, пиксели
	shakeDecay = 0.3, -- тряска гаснет за столько секунд
	wobble = 1.5, -- дрожь сжатых поршней в ожидании, пиксели
	lift = 0.45, -- расход после ответа, секунды
	slamWindup = 0.08, -- пачка: замах, секунды
	slamTime = 0.12, -- пачка: удар, секунды
	slamBack = 0.24, -- пачка: расход, секунды
	flash = 0.35, -- вспышка в точке встречи, секунды
	drops = 8, -- брызг от каждого раздавленного элемента
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

-- Плоская деталь: заливка и тонкий кант, скругление как у кнопок.
local function part(f, fill, edge)
	f.BackgroundColor3 = fill
	f.BackgroundTransparency = 0
	round(f, UDim.new(0, Theme.radius.control))
	local s = Instance.new("UIStroke")
	s.Color = edge
	s.Thickness = 1
	s.Parent = f
end

function Press.Mount(page, parts)
	local slotA, slotB, plus, result = parts.slotA, parts.slotB, parts.plus, parts.result
	local z = slotA.ZIndex + 3

	-- side 1 — левый поршень, 2 — правый.
	local pistons = {}
	for side = 1, 2 do
		local p = {}
		p.housing = make("PressHousing" .. side, page, z + 1)
		part(p.housing, Theme.color.row, Theme.color.hairline)

		p.rod = make("PressRod" .. side, page, z)
		p.rod.BackgroundColor3 = Theme.color.hairline
		p.rod.BackgroundTransparency = 0

		p.head = make("PressHead" .. side, page, z + 1)
		part(p.head, Theme.color.panelSoft, Theme.color.accentDim)

		-- Кромка — рабочая грань головы, смотрит на слоты; при ударе раскаляется.
		p.face = make("Face", p.head, z + 1)
		p.face.AnchorPoint = Vector2.new(side == 1 and 1 or 0, 0)
		p.face.Position = UDim2.fromScale(side == 1 and 1 or 0, 0)
		p.face.Size = UDim2.new(0, 2, 1, 0)
		p.face.BackgroundTransparency = 0
		-- Отсвет кромки на слот — полоса за гранью, гаснущая наружу.
		p.glow = make("Glow", p.head, z)
		p.glow.AnchorPoint = Vector2.new(side == 1 and 0 or 1, 0)
		p.glow.Position = UDim2.fromScale(side == 1 and 1 or 0, 0)
		p.glow.Size = UDim2.new(0, 14, 1, 0)
		p.glow.BackgroundTransparency = 0
		local fadeOut = Instance.new("UIGradient")
		fadeOut.Rotation = side == 1 and 0 or 180
		fadeOut.Transparency = NumberSequence.new(0.2, 1)
		fadeOut.Parent = p.glow
		pistons[side] = p
	end

	local layer = make("PressFx", page, z + 3)
	layer.Size = UDim2.fromScale(1, 1)

	local g = nil
	local holdValue = Instance.new("NumberValue")
	local waiting, clock = false, 0
	local shake, heat, heatColor = 0, 0, Theme.color.energy

	local function apply()
		if not g then
			return
		end
		local p = holdValue.Value
		local pw = math.max(8, math.floor(g.h * TUNING.head))
		local hw = math.max(8, math.floor(g.h * TUNING.housing))
		local mid = (g.left + g.right) / 2
		local rest = g.left + hw + pw -- внутренняя кромка левой головы в покое
		local push = p * (mid - TUNING.meet - rest)
		if waiting then
			push += math.sin(clock * 40) * TUNING.wobble * 0.5
		end
		local dy = shake > 0 and (math.random() * 2 - 1) * shake or 0
		local edgeL, edgeR = rest + push, g.right - (rest - g.left) - push
		local y = g.y + dy
		local hy, hh = math.floor(y - TUNING.overhang), g.h + TUNING.overhang * 2
		local cy, ch = y + g.h * (1 - TUNING.housingH) / 2, math.floor(g.h * TUNING.housingH)
		local rh = TUNING.rod
		local ry = math.floor(y + (g.h - rh) / 2)
		local faceColor = Theme.color.accentDim:Lerp(heatColor, heat)
		for side, piston in pistons do
			local headX = side == 1 and edgeL - pw or edgeR
			local housingX = side == 1 and g.left or g.right - hw
			piston.head.Position = UDim2.fromOffset(math.floor(headX), hy)
			piston.head.Size = UDim2.fromOffset(pw, hh)
			piston.housing.Position = UDim2.fromOffset(housingX, math.floor(cy))
			piston.housing.Size = UDim2.fromOffset(hw, ch)
			local x0 = side == 1 and g.left + hw or math.floor(edgeR + pw)
			local x1 = side == 1 and math.floor(edgeL - pw) or g.right - hw
			piston.rod.Position = UDim2.fromOffset(x0, ry)
			piston.rod.Size = UDim2.fromOffset(math.max(0, x1 - x0), rh)
			piston.face.BackgroundColor3 = faceColor
			piston.glow.BackgroundColor3 = faceColor
			piston.glow.Visible = heat > 0.02
			piston.glow.BackgroundTransparency = 1 - heat * 0.7
		end
		-- Слоты зажаты между головами и «+»: сжимаются по ширине и вспучиваются по высоте.
		local q = math.max(0, p)
		local gap, half = TUNING.gap * (1 - q), g.sign / 2 * (1 - q)
		local sh = math.floor(g.h * (1 + TUNING.bulge * q))
		local sy = math.floor(y - (sh - g.h) / 2)
		slotA.Position = UDim2.fromOffset(math.floor(edgeL + gap), sy)
		slotB.Position = UDim2.fromOffset(math.floor(mid + half), sy)
		slotA.Size = UDim2.fromOffset(math.floor(math.max(0, mid - half - (edgeL + gap))), sh)
		slotB.Size = UDim2.fromOffset(math.floor(math.max(0, edgeR - gap - (mid + half))), sh)
		local fade = math.clamp(q * 2, 0, 1)
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
		local moving = waiting or shake > 0 or heat > 0
		if waiting then
			clock += dt
		end
		if shake > 0 then
			shake = math.max(0, shake - TUNING.shake * dt / TUNING.shakeDecay)
		end
		if heat > 0 and not waiting then
			heat = math.max(0, heat - dt / TUNING.lift)
		end
		if moving then
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
		local pw = math.max(8, math.floor(g.h * TUNING.head))
		local hw = math.max(8, math.floor(g.h * TUNING.housing))
		local w = math.floor(mid - g.sign / 2 - g.left - hw - pw - TUNING.gap)
		result.Position = UDim2.fromOffset(math.floor(mid - w / 2), g.y)
		result.Size = UDim2.fromOffset(w, g.h)
		apply()
	end

	local tween
	local function to(value, time, style, dir, done)
		if tween then
			tween:Cancel()
		end
		tween = TweenService:Create(holdValue, TweenInfo.new(time, style, dir), { Value = value })
		if done then
			tween.Completed:Connect(function(state)
				if state == Enum.PlaybackState.Completed then
					done()
				end
			end)
		end
		tween:Play()
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

	-- Миг удара: вспышка в точке встречи, брызги вверх и вниз, тряска, кромки раскалены.
	local function impact(colorA, colorB)
		if not g then
			return
		end
		local mix = colorA:Lerp(colorB, 0.5)
		heatColor, heat, shake = mix, 1, TUNING.shake
		local c = Vector2.new((g.left + g.right) / 2, g.y + g.h / 2) + page.AbsolutePosition - layer.AbsolutePosition

		local flash = make("Flash", layer, layer.ZIndex)
		flash.AnchorPoint = Vector2.new(0.5, 0.5)
		flash.Position = UDim2.fromOffset(c.X, c.Y)
		-- Вспышка — вертикальная черта в точке встречи, расходится в полосу и гаснет.
		flash.Size = UDim2.fromOffset(2, g.h * 1.2)
		flash.BackgroundColor3 = Color3.new(1, 1, 1):Lerp(mix, 0.4)
		flash.BackgroundTransparency = 0
		local info = TweenInfo.new(TUNING.flash, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(flash, info, {
			Size = UDim2.fromOffset(g.h * 0.35, g.h * 1.5),
			BackgroundTransparency = 1,
		}):Play()
		task.delay(TUNING.flash, function()
			flash:Destroy()
		end)

		local rng = Random.new()
		for i = 1, 2 do
			local color = i == 1 and colorA or colorB
			for _ = 1, TUNING.drops do
				local up = rng:NextNumber() < 0.5 and -1 or 1
				local sideX = (i == 1 and -1 or 1) * rng:NextNumber(0, 0.5) * g.h
				particle(c, Vector2.new(sideX, up * rng:NextNumber(0.45, 0.95) * g.h), color, rng:NextNumber(5, 11), TUNING.dropFly)
			end
		end
	end

	-- Ход пресса: phase — "open", "strike" (замах и удар), "closed" (сжаты, ждём сервер).
	-- pending — ответ пришёл, пока пресс ещё бил: { done, start } расхода после удара.
	local phase, closedAt, pending = "open", 0, nil

	local function open(done, start)
		waiting = false
		phase = "open"
		if start then
			start()
		end
		to(0, TUNING.lift, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		if done then
			task.delay(TUNING.lift * 0.3, done)
		end
	end

	local function go()
		if pending == nil then
			return
		end
		local job = pending
		pending = nil
		open(job[1], job[2])
	end

	-- Сжатыми не меньше minClosed: иначе удар и расход слились бы в один кадр.
	local function openLater()
		local left = TUNING.minClosed - (os.clock() - closedAt)
		if left > 0 then
			task.delay(left, go)
		else
			go()
		end
	end

	function self.squeeze(colorA, colorB, onImpact)
		phase, pending = "strike", nil
		to(TUNING.windup, TUNING.windupTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, function()
			to(1, TUNING.strikeTime, Enum.EasingStyle.Quint, Enum.EasingDirection.In, function()
				impact(colorA, colorB)
				if onImpact then
					onImpact()
				end
				phase, closedAt = "closed", os.clock()
				if pending ~= nil then
					openLater()
					return
				end
				to(TUNING.rebound, TUNING.reboundTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, function()
					to(1, TUNING.settleTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In, function()
						waiting = phase == "closed"
					end)
				end)
			end)
		end)
	end

	function self.release(done, start)
		if phase == "strike" then
			pending = { done, start } -- откроется после удара
			return
		end
		if phase == "closed" then
			pending = { done, start }
			openLater()
			return
		end
		open(done, start)
	end

	function self.slam(colorA, colorB, done)
		if phase ~= "open" then
			if done then
				done()
			end
			return
		end
		to(TUNING.windup, TUNING.slamWindup, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, function()
			to(1, TUNING.slamTime, Enum.EasingStyle.Quint, Enum.EasingDirection.In, function()
				impact(colorA, colorB)
				if done then
					done()
				end
				to(0, TUNING.slamBack, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
			end)
		end)
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
