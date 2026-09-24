-- Жидкое стекло под плашками окна-монитора (просьба автора, #226): фон под плашкой размыт,
-- а не засветлён. Вынесено из CraftingProducer (#269): тем же стеклом теперь лежат и
-- карточки справочника.
--
-- Размывать интерфейс под кадром Roblox не умеет, поэтому размытие нарисовано: тёмное
-- почти непрозрачное стекло закрывает чёткие точки окна (Theme.Dots), а на их местах слой
-- Frost кладёт мягкие пятна — так выглядит точка сквозь матовое стекло. Кромка — ровная
-- тонкая линия.
local Theme = require(script.Parent:WaitForChild("UITheme"))

local Glass = {}

-- Пятно вчетверо шире точки и во столько же бледнее: свет точки растёкся по стеклу.
local FROST_SIZE, FROST_T = 9, 0.9

-- Под звездой (Theme.Stars) пятно шире самой звезды втрое: звёзды разной величины, и
-- пятна тоже.
local STAR_SPREAD, STAR_T = 3, 0.86

local function blob(layer, x, y, size, transparency)
	local d = Instance.new("Frame")
	d.BorderSizePixel = 0
	d.BackgroundColor3 = Theme.color.grid
	d.BackgroundTransparency = transparency
	d.Size = UDim2.fromOffset(size, size)
	d.Position = UDim2.fromOffset(x - size / 2, y - size / 2)
	d.ZIndex = layer.ZIndex
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(0.5, 0)
	round.Parent = d
	d.Parent = layer
end

-- Созвездия справочника: пятна на местах звёзд.
local function frostStars(mon, stars, plate, layer)
	local open = mon:FindFirstChild("OpenScale")
	local list = Theme.StarsOf(stars)
	if (open and open.Scale < 1) or not list then
		return
	end
	local rel = plate.AbsolutePosition - stars.AbsolutePosition
	local rx, ry = math.floor(rel.X + 0.5), math.floor(rel.Y + 0.5)
	local w, h = plate.AbsoluteSize.X, plate.AbsoluteSize.Y
	local key = rx .. ":" .. ry .. ":" .. w .. "x" .. h .. ":" .. tostring(stars:GetAttribute("Version"))
	if layer:GetAttribute("For") == key then
		return
	end
	layer:SetAttribute("For", key)
	layer:ClearAllChildren()
	for _, star in list do
		local x, y = star.x - rx, star.y - ry
		local size = star.size * STAR_SPREAD
		if x > -size and y > -size and x < w + size and y < h + size then
			blob(layer, x, y, size, STAR_T)
		end
	end
end

-- mon — рамка окна, у которой уже есть точки (Theme.Dots) или созвездия (Theme.Stars). Возвращает glass(plate):
-- превращает плашку в стекло. Слой Frost ложится ребёнком плашки на её ZIndex, поэтому
-- содержимое плашки должно быть на слой выше или создано после слоя.
function Glass.Mount(mon)
	local monDots = mon:FindFirstChild("Dots")
	local stars = mon:FindFirstChild("Stars")
	local frosted = {}
	local function frost(plate, layer)
		if stars then
			frostStars(mon, stars, plate, layer)
			return
		end
		local open = mon:FindFirstChild("OpenScale")
		local step = monDots:GetAttribute("Step")
		if (open and open.Scale < 1) or not step then
			return -- окно раскрывается и меряется меньше настоящего; конец анимации даст верный замер
		end
		local ox, oy = monDots:GetAttribute("OriginX"), monDots:GetAttribute("OriginY")
		local half = monDots:GetAttribute("Size") / 2
		local rel = plate.AbsolutePosition - monDots.AbsolutePosition
		local rx, ry = math.floor(rel.X + 0.5), math.floor(rel.Y + 0.5)
		local w, h = plate.AbsoluteSize.X, plate.AbsoluteSize.Y
		local key = rx .. ":" .. ry .. ":" .. w .. "x" .. h .. ":" .. ox .. ":" .. oy
		if layer:GetAttribute("For") == key then
			return
		end
		layer:SetAttribute("For", key)
		layer:ClearAllChildren()
		-- Центры точек окна в координатах подложки
		local c0 = math.ceil((rx - ox - half) / step)
		local r0 = math.ceil((ry - oy - half) / step)
		local cx = ox + half + c0 * step - rx
		while cx <= w do
			local cy = oy + half + r0 * step - ry
			while cy <= h do
				blob(layer, cx, cy, FROST_SIZE, FROST_T)
				cy += step
			end
			cx += step
		end
	end
	local function refrostAll()
		for plate, layer in frosted do
			frost(plate, layer)
		end
	end
	if stars then
		stars:GetAttributeChangedSignal("Version"):Connect(refrostAll)
	else
		monDots:GetAttributeChangedSignal("OriginX"):Connect(refrostAll)
		monDots:GetAttributeChangedSignal("OriginY"):Connect(refrostAll)
	end

	return function(plate)
		plate.BackgroundColor3 = Theme.color.ink
		plate.BackgroundTransparency = 0.1
		Theme.Corner(plate, Theme.radius.mark)
		-- Кромка ровная, без блика сверху (просьба автора, #230): блик тянул в «Frutiger
		-- Aero» и спорил с неоном интерфейса.
		Theme.Stroke(plate, Theme.color.text, 1, 0.85)

		local layer = Instance.new("Frame")
		layer.Name = "Frost"
		layer.BackgroundTransparency = 1
		layer.BorderSizePixel = 0
		layer.Size = UDim2.fromScale(1, 1)
		layer.ClipsDescendants = true
		layer.ZIndex = plate.ZIndex
		layer.Parent = plate
		frosted[plate] = layer
		local function again()
			frost(plate, layer)
		end
		plate:GetPropertyChangedSignal("AbsolutePosition"):Connect(again)
		plate:GetPropertyChangedSignal("AbsoluteSize"):Connect(again)
	end
end

return Glass
