-- Фон окна алхимического стола: колба кипит (просьба автора — у каждого окна свой узор;
-- точки у производителя, звёзды у справочника). Со дна окна всплывают пузырьки-кольца
-- с бликом, покачиваются и у поверхности тают. Удачный крафт — струя пузырьков цветом
-- результата, новый рецепт — струя вдвое гуще.
--
-- Под стеклянными плашками (MonitorGlass) пузырёк виден размытым пятном: Bubbles.frost
-- кладёт в слой Frost каждой плашки по пятну на пузырёк и двигает их вместе с пузырьками.
-- Пока окно закрыто, ничего не движется.
local RunService = game:GetService("RunService")

local Theme = require(script.Parent:WaitForChild("UITheme"))

local Bubbles = {}

local TUNING = {
	count = 18, -- пузырьков в покое
	size = { 6, 22 }, -- поперечник, пиксели
	speed = { 14, 34 }, -- подъём, пикселей в секунду
	sway = 9, -- раскачка вбок, пиксели
	swayRate = { 0.6, 1.4 }, -- раскачка, раз в секунду (в радианах — умножается на 2π)
	ring = 0.55, -- прозрачность кольца
	fadeFrom = 0.3, -- доля высоты сверху, где пузырёк тает
	frostSpread = 2.2, -- пятно под стеклом шире пузырька во столько раз
	frostT = 0.86, -- прозрачность пятна
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
	local list = {} -- { ring, x0, y, size, speed, rate, phase, color, burst, blobs = { [plateLayer] = Frame } }
	local plates = {} -- слой Frost → плашка

	local function shape(b)
		local ring = b.ring
		ring.Size = UDim2.fromOffset(b.size, b.size)
		ring.Stroke.Color = b.color
		ring.Glint.Size = UDim2.fromOffset(math.max(2, b.size * 0.22), math.max(2, b.size * 0.22))
		ring.Glint.Position = UDim2.fromScale(0.22, 0.2)
		for _, blob in b.blobs do
			blob.BackgroundColor3 = b.color
			local s = b.size * TUNING.frostSpread
			blob.Size = UDim2.fromOffset(s, s)
		end
	end

	local function spawn(b, fromBottom)
		b.size = rand(rng, TUNING.size)
		b.speed = rand(rng, TUNING.speed)
		b.rate = rand(rng, TUNING.swayRate) * math.pi * 2
		b.phase = rng:NextNumber(0, math.pi * 2)
		b.x0 = rng:NextNumber(0, math.max(1, W))
		b.y = fromBottom and (H + b.size) or rng:NextNumber(0, math.max(1, H))
		b.color = Theme.color.grid
		shape(b)
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
		local b = { ring = ring, burst = burst, blobs = {} }
		for plateLayer in plates do
			b.blobs[plateLayer] = circle(plateLayer, plateLayer.ZIndex)
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

	local t = 0
	RunService.Heartbeat:Connect(function(dt)
		if W < 1 or not isOn() then
			return
		end
		t += dt
		local open = mon:FindFirstChild("OpenScale")
		local scale = open and open.Scale or 1
		-- Где каждая видимая плашка относительно слоя пузырьков, в пикселях окна.
		local offsets = {}
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
			if b.y < -b.size then
				if b.burst then
					remove(i)
					continue
				end
				spawn(b, true)
			end
			local x = b.x0 + math.sin(t * b.rate + b.phase) * TUNING.sway
			-- У поверхности (верхняя доля окна) пузырёк тает.
			local fade = math.clamp(1 - b.y / (H * TUNING.fadeFrom), 0, 1)
			b.ring.Position = UDim2.fromOffset(x, b.y)
			b.ring.Stroke.Transparency = TUNING.ring + (1 - TUNING.ring) * fade
			b.ring.Glint.BackgroundTransparency = 0.6 + 0.4 * fade
			for plateLayer, blob in b.blobs do
				local off = offsets[plateLayer]
				if off then
					local s = b.size * TUNING.frostSpread
					blob.Position = UDim2.fromOffset(x - off.X - s / 2, b.y - off.Y - s / 2)
					blob.BackgroundTransparency = TUNING.frostT + (1 - TUNING.frostT) * fade
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
			b.blobs[plateLayer] = circle(plateLayer, plateLayer.ZIndex)
			shape(b)
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
			b.y += rng:NextNumber(0, H * 0.25) -- не стеной, а вразнобой
			b.speed *= TUNING.burstSpeed
			b.color = color
			shape(b)
		end
	end

	return self
end

return Bubbles
