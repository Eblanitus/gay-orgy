-- Фон окна алхимического стола: колба кипит (просьба автора — у каждого окна свой узор;
-- точки у производителя, звёзды у справочника). Со дна окна всплывают пузырьки-кольца
-- с бликом, покачиваются, по дороге понемногу растут и лопаются каждый на своей высоте —
-- кольцо разлетается и гаснет. Удачный крафт — струя пузырьков цветом результата, новый
-- рецепт — струя вдвое гуще.
--
-- Под стеклянными плашками (MonitorGlass) пузырёк виден мягким пятном: Bubbles.frost кладёт
-- в слой Frost каждой плашки по пятну на пузырёк и двигает их вместе с пузырьками. Пятно —
-- три круга друг в друге, к середине плотнее: так край размыт, а не обрезан (#287).
-- Пока окно закрыто, ничего не движется.
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent:WaitForChild("UITheme"))

local Bubbles = {}

local TUNING = {
	count = 18, -- пузырьков в покое
	size = { 6, 20 }, -- поперечник у дна, пиксели
	grow = 0.4, -- к месту, где лопнет, пузырёк вырастает на эту долю
	speed = { 14, 34 }, -- подъём, пикселей в секунду
	sway = 9, -- раскачка вбок, пиксели
	swayRate = { 0.6, 1.4 }, -- раскачка, раз в секунду
	pop = { 0.05, 0.7 }, -- где лопается: доля высоты окна от верха
	popGrow = 2, -- кольцо лопнувшего пузырька разлетается во столько раз
	popTime = 0.35, -- и гаснет за столько секунд
	ring = 0.55, -- прозрачность кольца
	frostSpread = 1.8, -- пятно под стеклом шире пузырька во столько раз
	-- Пятно: доля поперечника и прозрачность каждого из трёх кругов, от внешнего к середине.
	frostRings = { { 1, 0.94 }, { 0.68, 0.9 }, { 0.38, 0.86 } },
	burst = 12, -- пузырьков в струе за крафт
	burstSpeed = 2.4, -- струя быстрее покоя во столько раз
	burstSpread = 0.18, -- струя бьёт из середины дна: ширина — доля окна
}

local function rand(rng, range)
	return rng:NextNumber(range[1], range[2])
end

local function circle(parent, z)
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	f.BackgroundTransparency = 1
	f.ZIndex = z
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(0.5, 0)
	round.Parent = f
	f.Parent = parent
	return f
end

-- Мягкое пятно: прозрачная рамка с тремя кругами по центру.
local function soft(parent)
	local holder = Instance.new("Frame")
	holder.BackgroundTransparency = 1
	holder.BorderSizePixel = 0
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.ZIndex = parent.ZIndex
	holder.Parent = parent
	for i, spec in TUNING.frostRings do
		local c = circle(holder, parent.ZIndex)
		c.Name = "R" .. i
		c.AnchorPoint = Vector2.new(0.5, 0.5)
		c.Position = UDim2.fromScale(0.5, 0.5)
		c.Size = UDim2.fromScale(spec[1], spec[1])
		c.BackgroundTransparency = spec[2]
	end
	return holder
end

local function tint(holder, color)
	for _, c in holder:GetChildren() do
		c.BackgroundColor3 = color
	end
end

-- mon — рамка окна, isOn() — открыто ли окно. Возвращает { paint(w, h), frost(plate, layer),
-- burst(color, scale) }: paint и frost зовут ReferenceFrame и MonitorGlass, burst — стол.
function Bubbles.Mount(mon, isOn, zIndex)
	local z = zIndex or 1
	local layer = Instance.new("Frame")
	layer.Name = "Bubbles"
	layer.BackgroundTransparency = 1
	layer.BorderSizePixel = 0
	layer.ClipsDescendants = true
	layer.ZIndex = z
	layer.Parent = mon
	Theme.Bleed(layer, UDim2.new(0, 0, 0, 0), UDim2.new(1, 0, 1, 0))

	local rng = Random.new()
	local W, H = 0, 0
	local list = {} -- пузырьки: ring, x, y, x0, size0, top, speed, rate, phase, color, burst, blobs
	local plates = {} -- слой Frost → плашка
	local offsets = {} -- слой Frost видимой плашки → её сдвиг от слоя пузырьков

	local function spawn(b, fromBottom)
		b.size0 = rand(rng, TUNING.size)
		b.speed = rand(rng, TUNING.speed)
		b.rate = rand(rng, TUNING.swayRate) * math.pi * 2
		b.phase = rng:NextNumber(0, math.pi * 2)
		b.x0 = rng:NextNumber(0, math.max(1, W))
		b.x = b.x0
		b.top = H * rand(rng, TUNING.pop)
		b.y = fromBottom and (H + b.size0) or rng:NextNumber(b.top, math.max(b.top + 1, H))
		b.color = Theme.color.grid
		b.ring.Stroke.Color = b.color
		for _, blob in b.blobs do
			tint(blob, b.color)
		end
	end

	local function make(burst)
		local ring = circle(layer, z)
		ring.AnchorPoint = Vector2.new(0.5, 0.5)
		local stroke = Instance.new("UIStroke")
		stroke.Name = "Stroke"
		stroke.Thickness = 1
		stroke.Transparency = TUNING.ring
		stroke.Parent = ring
		local glint = circle(ring, z)
		glint.Name = "Glint"
		glint.BackgroundColor3 = Theme.color.text
		glint.BackgroundTransparency = 0.6
		glint.Position = UDim2.fromScale(0.22, 0.2)
		glint.Size = UDim2.fromScale(0.22, 0.22)
		local b = { ring = ring, burst = burst, blobs = {} }
		for plateLayer in plates do
			b.blobs[plateLayer] = soft(plateLayer)
		end
		table.insert(list, b)
		return b
	end

	local function remove(i)
		local b = table.remove(list, i)
		b.ring:Destroy()
		for _, blob in b.blobs do
			blob:Destroy()
		end
	end

	-- Лопнул: на его месте кольцо (и пятна под стеклом) разлетается и гаснет.
	local function pop(b)
		local info = TweenInfo.new(TUNING.popTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local s = b.size0 * (1 + TUNING.grow)
		local big = UDim2.fromOffset(s * TUNING.popGrow, s * TUNING.popGrow)
		local ring = circle(layer, z)
		ring.AnchorPoint = Vector2.new(0.5, 0.5)
		ring.Position = UDim2.fromOffset(b.x, b.y)
		ring.Size = UDim2.fromOffset(s, s)
		local stroke = Instance.new("UIStroke")
		stroke.Color = b.color
		stroke.Transparency = TUNING.ring
		stroke.Parent = ring
		TweenService:Create(ring, info, { Size = big }):Play()
		TweenService:Create(stroke, info, { Transparency = 1 }):Play()
		local gone = { ring }
		for plateLayer, off in offsets do
			local blob = soft(plateLayer)
			table.insert(gone, blob)
			tint(blob, b.color)
			blob.Position = UDim2.fromOffset(b.x - off.X, b.y - off.Y)
			local fs = s * TUNING.frostSpread
			blob.Size = UDim2.fromOffset(fs, fs)
			TweenService:Create(blob, info, { Size = UDim2.fromOffset(fs * TUNING.popGrow, fs * TUNING.popGrow) }):Play()
			for _, c in blob:GetChildren() do
				TweenService:Create(c, info, { BackgroundTransparency = 1 }):Play()
			end
		end
		task.delay(TUNING.popTime, function()
			for _, inst in gone do
				inst:Destroy()
			end
		end)
	end

	local t = 0
	RunService.Heartbeat:Connect(function(dt)
		if W < 1 or not isOn() then
			return
		end
		t += dt
		local open = mon:FindFirstChild("OpenScale")
		local scale = open and open.Scale or 1
		-- Где каждая видимая плашка относительно слоя пузырьков, в пикселях окна.
		table.clear(offsets)
		for plateLayer, plate in plates do
			local shown = true
			local node = plate
			while node and node ~= mon do
				if node:IsA("GuiObject") and not node.Visible then
					shown = false
					break
				end
				node = node.Parent
			end
			plateLayer.Visible = shown
			if shown then
				offsets[plateLayer] = (plateLayer.AbsolutePosition - layer.AbsolutePosition) / scale
			end
		end

		for i = #list, 1, -1 do
			local b = list[i]
			b.y -= b.speed * dt
			if b.y < b.top then
				pop(b)
				if b.burst then
					remove(i)
					continue
				end
				spawn(b, true)
			end
			b.x = b.x0 + math.sin(t * b.rate + b.phase) * TUNING.sway
			-- Растёт, пока всплывает: у дна size0, у места, где лопнет, — на grow больше.
			local rise = math.clamp((H - b.y) / math.max(1, H - b.top), 0, 1)
			local s = b.size0 * (1 + TUNING.grow * rise)
			b.ring.Position = UDim2.fromOffset(b.x, b.y)
			b.ring.Size = UDim2.fromOffset(s, s)
			local fs = s * TUNING.frostSpread
			for plateLayer, blob in b.blobs do
				local off = offsets[plateLayer]
				if off then
					blob.Position = UDim2.fromOffset(b.x - off.X, b.y - off.Y)
					blob.Size = UDim2.fromOffset(fs, fs)
				end
			end
		end
	end)

	local self = {}

	function self.paint(w, h)
		W, H = math.floor(w), math.floor(h)
		local calm = 0
		for _, b in list do
			if not b.burst then
				calm += 1
			end
		end
		for _ = calm + 1, TUNING.count do
			spawn(make(false), false)
		end
	end

	-- Стекло (MonitorGlass) отдаёт свой слой Frost: под ним пузырьки — пятнами.
	function self.frost(plate, plateLayer)
		if plates[plateLayer] then
			return
		end
		plates[plateLayer] = plate
		for _, b in list do
			local blob = soft(plateLayer)
			tint(blob, b.color)
			b.blobs[plateLayer] = blob
		end
	end

	-- Струя со дна цветом результата; scale — во сколько раз гуще (новый рецепт — 2).
	function self.burst(color, scale)
		if W < 1 then
			return
		end
		for _ = 1, math.floor(TUNING.burst * (scale or 1)) do
			local b = make(true)
			spawn(b, true)
			b.x0 = W / 2 + rng:NextNumber(-0.5, 0.5) * W * TUNING.burstSpread
			b.x = b.x0
			b.y += rng:NextNumber(0, H * 0.25) -- не стеной, а вразнобой
			b.speed *= TUNING.burstSpeed
			b.color = color
			b.ring.Stroke.Color = color
			for _, blob in b.blobs do
				tint(blob, color)
			end
		end
	end

	return self
end

return Bubbles
