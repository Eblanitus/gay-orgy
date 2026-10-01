-- Сплетание элементов на столе (идея автора, #291). Дёрнули рычаг — из обоих слотов
-- выходят шары цветом своих элементов и по спирали сходятся между слотами, сливаясь
-- в один шар смешанного цвета. Он пульсирует, пока не ответит сервер. Удача — шар
-- перекрашивается в цвет результата, летит в слот результата и там «рождается»:
-- расходится кольцо. Неудача — шар распадается на два, они гаснут на пути назад.
--
-- Fusion.Play(page, slotA, slotB, resultSlot, colorA, colorB) возвращает
-- finish(ok, color, after): after() — обычный отклик стола (вспышка, «+1», баннер),
-- его зовут в миг рождения или распада.
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Fusion = {}

local TUNING = {
	orb = 0.42, -- шар: доля высоты слота
	spiral = 0.9, -- схождение, секунды
	turns = 1.25, -- оборотов по спирали
	travel = 0.35, -- полёт в слот результата, секунды
	birth = 0.55, -- кольцо рождения, секунды
	birthGrow = 1.5, -- кольцо расходится до этой доли высоты слота
	split = 0.45, -- распад, секунды
	wait = 4, -- ответа нет столько секунд — шар гаснет сам
	pulse = 0.08, -- пульс шара в ожидании, доля размера
}

local function circle(parent, color, size)
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.BackgroundColor3 = color
	f.BackgroundTransparency = 0.1
	f.Size = UDim2.fromOffset(size, size)
	f.ZIndex = parent.ZIndex
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(0.5, 0)
	round.Parent = f
	local rim = Instance.new("UIStroke")
	rim.Color = Color3.new(1, 1, 1)
	rim.Transparency = 0.55
	rim.Thickness = 1.5
	rim.Parent = f
	local glint = Instance.new("Frame")
	glint.BorderSizePixel = 0
	glint.BackgroundColor3 = Color3.new(1, 1, 1)
	glint.BackgroundTransparency = 0.45
	glint.Position = UDim2.fromScale(0.22, 0.18)
	glint.Size = UDim2.fromScale(0.24, 0.24)
	glint.ZIndex = f.ZIndex
	local gr = Instance.new("UICorner")
	gr.CornerRadius = UDim.new(0.5, 0)
	gr.Parent = glint
	glint.Parent = f
	f.Parent = parent
	return f
end

local function fade(f, time)
	local info = TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(f, info, { BackgroundTransparency = 1 }):Play()
	for _, d in f:GetDescendants() do
		if d:IsA("UIStroke") then
			TweenService:Create(d, info, { Transparency = 1 }):Play()
		elseif d:IsA("Frame") then
			TweenService:Create(d, info, { BackgroundTransparency = 1 }):Play()
		end
	end
end

function Fusion.Play(page, slotA, slotB, resultSlot, colorA, colorB)
	local layer = Instance.new("Frame")
	layer.Name = "Fusion"
	layer.BackgroundTransparency = 1
	layer.Size = UDim2.fromScale(1, 1)
	layer.ZIndex = 7
	layer.Parent = page

	local function center(gui)
		return gui.AbsolutePosition + gui.AbsoluteSize / 2 - page.AbsolutePosition
	end
	local function at(f, p)
		f.Position = UDim2.fromOffset(p.X, p.Y)
	end

	local p0, p1 = center(slotA), center(slotB)
	local mid = (p0 + p1) / 2
	local r0 = (p1 - p0).Magnitude / 2
	local a0 = math.atan2(p0.Y - mid.Y, p0.X - mid.X)
	local s0 = math.max(16, slotA.AbsoluteSize.Y * TUNING.orb)
	local orbA, orbB = circle(layer, colorA, s0), circle(layer, colorB, s0)
	at(orbA, p0)
	at(orbB, p1)

	local fused, outcome, waited = nil, nil, 0
	local finishedAt = nil
	local resolve

	local t = 0
	local conn
	conn = RunService.Heartbeat:Connect(function(dt)
		t += dt
		if not fused then
			local e = math.clamp(t / TUNING.spiral, 0, 1)
			e = e * e * (3 - 2 * e) -- плавно в начале и в конце
			local r = r0 * (1 - e)
			local ang = a0 + TUNING.turns * math.pi * 2 * e
			local off = Vector2.new(math.cos(ang), math.sin(ang)) * r
			at(orbA, mid + off)
			at(orbB, mid - off)
			local s = s0 * (1 - 0.3 * e)
			orbA.Size = UDim2.fromOffset(s, s)
			orbB.Size = UDim2.fromOffset(s, s)
			if t >= TUNING.spiral then
				orbA:Destroy()
				orbB:Destroy()
				fused = circle(layer, colorA:Lerp(colorB, 0.5), s0 * 0.9)
				at(fused, mid)
				finishedAt = t
				if outcome then
					resolve()
				end
			end
			return
		end
		if outcome then
			return
		end
		-- Ждём сервер: шар дышит.
		waited = t - finishedAt
		local s = s0 * 0.9 * (1 + TUNING.pulse * math.sin(waited * 9))
		fused.Size = UDim2.fromOffset(s, s)
		if waited > TUNING.wait then
			conn:Disconnect()
			fade(fused, 0.3)
			task.delay(0.35, function()
				layer:Destroy()
			end)
		end
	end)

	function resolve()
		conn:Disconnect()
		local ok, color, after = outcome[1], outcome[2], outcome[3]
		if ok then
			local info = TweenInfo.new(TUNING.travel, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
			local dest = center(resultSlot)
			TweenService:Create(fused, info, { BackgroundColor3 = color, Position = UDim2.fromOffset(dest.X, dest.Y) }):Play()
			task.delay(TUNING.travel, function()
				fused:Destroy()
				-- Рождение: кольцо цвета результата расходится из середины слота.
				local ring = Instance.new("Frame")
				ring.AnchorPoint = Vector2.new(0.5, 0.5)
				ring.BackgroundTransparency = 1
				ring.Position = UDim2.fromOffset(dest.X, dest.Y)
				ring.Size = UDim2.fromOffset(s0, s0)
				ring.ZIndex = layer.ZIndex
				local round = Instance.new("UICorner")
				round.CornerRadius = UDim.new(0.5, 0)
				round.Parent = ring
				local stroke = Instance.new("UIStroke")
				stroke.Color = color
				stroke.Thickness = 3
				stroke.Parent = ring
				ring.Parent = layer
				local big = resultSlot.AbsoluteSize.Y * TUNING.birthGrow
				local binfo = TweenInfo.new(TUNING.birth, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
				TweenService:Create(ring, binfo, { Size = UDim2.fromOffset(big, big) }):Play()
				TweenService:Create(stroke, binfo, { Transparency = 1 }):Play()
				after()
				task.delay(TUNING.birth, function()
					layer:Destroy()
				end)
			end)
		else
			-- Распад: два шара разлетаются к своим слотам и гаснут.
			local here = fused.Position
			local s = fused.AbsoluteSize.X
			fused:Destroy()
			local info = TweenInfo.new(TUNING.split, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			for i, p in { p0, p1 } do
				local part = circle(layer, i == 1 and colorA or colorB, s * 0.7)
				part.Position = here
				local to = mid + (p - mid) * 0.6
				TweenService:Create(part, info, { Position = UDim2.fromOffset(to.X, to.Y) }):Play()
				fade(part, TUNING.split)
			end
			after()
			task.delay(TUNING.split, function()
				layer:Destroy()
			end)
		end
	end

	return function(ok, color, after)
		if outcome then
			return
		end
		outcome = { ok, color, after }
		if fused and conn.Connected then
			resolve()
		elseif not conn.Connected then
			after() -- шар уже погас по таймауту
		end
	end
end

return Fusion
