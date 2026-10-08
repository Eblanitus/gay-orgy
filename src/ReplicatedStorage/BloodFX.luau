-- Кровь (гемолимфа) и лужи останков на полу. КЛИЕНТСКАЯ часть.
--
-- Сервер шлёт только точку, размер, число брызг и направление удара (Corpses.Splat ->
-- Remotes.EnemyFX "splat"), пятно строит каждый клиент сам. Числа — PhysicsFX.blood,
-- цвет — BugPalette.Blood (свежая) и BugPalette.BloodDry (высохшая).
--
-- Раньше пятно было плоским цилиндром-овалом, брызги — овалами поменьше вокруг. На поле это
-- читалось мультяшными кругляшками-наклейками (жалоба автора). Теперь по правде, как у
-- настоящего раздавленного или подстреленного жука:
--   * форма — рваный плоский многоугольник из треугольников (каждый — пара WedgePart):
--     лоу-поли, грань видна, ни одного круга;
--   * брызги летят ПО удару (от стрелка), вытянуты остриём от удара и ложатся тем позже,
--     чем дальше упали; само пятно вытянуто и сдвинуто туда же;
--   * свежая кровь растекается из меньшего пятна, мокро блестит и почти глухая; через
--     wetTime темнеет, теряет блик и впитывается (прозрачнее) — ступенями, не каждый кадр;
--   * капля следа Кровотечения вытянута по ходу жука.
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PhysicsFX = require(ReplicatedStorage:WaitForChild("PhysicsFX"))
local BugPalette = require(ReplicatedStorage:WaitForChild("BugPalette"))
local Loose = require(ReplicatedStorage:WaitForChild("Loose"))

local plan = PhysicsFX.blood

local BloodFX = {}

local TAU = math.pi * 2
local MIN_SIZE = 0.001 -- меньше движок деталь не делает

local function lerp(a, b, t)
	return a + (b - a) * t
end

local function between(range)
	return lerp(range[1], range[2], math.random())
end

-- Сдвиг оттенка на ±spread единиц RGB, одинаковый для всех трёх каналов.
local function shifted(color, offset)
	return Color3.new(
		math.clamp(color.R + offset, 0, 1),
		math.clamp(color.G + offset, 0, 1),
		math.clamp(color.B + offset, 0, 1)
	)
end

local function randomShade(spread)
	return (math.random() - 0.5) * 2 * spread / 255
end

-- Плоский единичный вектор по полу или nil.
local function flat(vector)
	if not vector then
		return nil
	end
	local v = Vector3.new(vector.X, 0, vector.Z)
	return v.Magnitude > 1e-3 and v.Unit or nil
end

local function turned(direction, angle)
	local c, s = math.cos(angle), math.sin(angle)
	return Vector3.new(direction.X * c - direction.Z * s, 0, direction.X * s + direction.Z * c)
end

local function randomDirection()
	local angle = math.random() * TAU
	return Vector3.new(math.cos(angle), 0, math.sin(angle))
end

-- ============ Треугольник из двух клиньев ============

local function wedge(parent, material)
	local part = Instance.new("WedgePart")
	part.Name = "Blood"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = material or Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

-- Треугольник abc: высота на самую длинную сторону режет его на два прямоугольных,
-- каждый — один клин. thickness — толщина плашки.
local function place(w1, w2, a, b, c, thickness)
	local ab, ac, bc = b - a, c - a, c - b
	local abd, acd, bcd = ab:Dot(ab), ac:Dot(ac), bc:Dot(bc)
	if abd > acd and abd > bcd then
		c, a = a, c
	elseif acd > bcd and acd > abd then
		a, b = b, a
	end
	ab, ac, bc = b - a, c - a, c - b
	local normal = ac:Cross(ab)
	if normal.Magnitude < 1e-8 or bc.Magnitude < 1e-4 then
		-- Вырожденный (точка или отрезок): прячем в точку, а не в огромный NaN.
		local tiny = Vector3.new(MIN_SIZE, MIN_SIZE, MIN_SIZE)
		w1.Size, w2.Size = tiny, tiny
		w1.CFrame, w2.CFrame = CFrame.new(a), CFrame.new(a)
		return
	end
	local right = normal.Unit
	local up = bc:Cross(right).Unit
	local back = bc.Unit
	local height = math.max(math.abs(ab:Dot(up)), MIN_SIZE)
	w1.Size = Vector3.new(thickness, height, math.max(math.abs(ab:Dot(back)), MIN_SIZE))
	w1.CFrame = CFrame.fromMatrix((a + b) / 2, right, up, back)
	w2.Size = Vector3.new(thickness, height, math.max(math.abs(ac:Dot(back)), MIN_SIZE))
	w2.CFrame = CFrame.fromMatrix((a + c) / 2, -right, up, -back)
end

-- Треугольник пятна: origin — точка на полу, a/b/c — смещения от неё. Рисуется в масштабе k
-- от origin — так пятно растекается, а брызга «разбивается» из точки.
local function draw(tri, k)
	local o = tri.origin
	place(tri.w1, tri.w2, o + tri.a * k, o + tri.b * k, o + tri.c * k, plan.thickness)
end

-- ============ Растекание ============
-- Свежие треугольники растут от spreadFrom до полного размера. hidden — брызга ещё летит:
-- детали прозрачны, пока не придёт её время.
local growing = {}

local function grow(tri, delay, time, hidden)
	tri.start = os.clock() + delay
	tri.time = math.max(time, 1e-3)
	tri.hidden = hidden
	draw(tri, plan.spreadFrom)
	table.insert(growing, tri)
end

RunService.Heartbeat:Connect(function()
	if #growing == 0 then
		return
	end
	local now = os.clock()
	for index = #growing, 1, -1 do
		local tri = growing[index]
		if not tri.w1.Parent then
			table.remove(growing, index)
		else
			local t = (now - tri.start) / tri.time
			if t >= 0 then
				t = math.min(t, 1)
				if tri.hidden then
					tri.hidden = false
					tri.w1.Transparency = tri.transparency
					tri.w2.Transparency = tri.transparency
				end
				draw(tri, lerp(plan.spreadFrom, 1, 1 - (1 - t) * (1 - t)))
				if t >= 1 then
					table.remove(growing, index)
				end
			end
		end
	end
end)

-- ============ Формы ============

-- Высота над полом: соседние пятна в разных слоях, иначе перекрытые мерцают.
local layer = 0
local function nextLift()
	layer = layer % plan.layers + 1
	return plan.lift + layer * plan.layerStep
end

-- Контур вокруг нуля: углы по кругу со сдвигом, радиус рваный. direction (единичный) и
-- stretch — вытяжка вдоль удара с сохранением площади.
local function outline(radius, corners, ragged, direction, stretch)
	local points = {}
	local start = math.random() * TAU
	local step = TAU / corners
	for index = 0, corners - 1 do
		local angle = start + index * step + (math.random() - 0.5) * step * 0.6
		local r = radius * (1 - ragged / 2 + math.random() * ragged)
		local point = Vector3.new(math.cos(angle) * r, 0, math.sin(angle) * r)
		if direction and stretch ~= 1 then
			local along = point:Dot(direction)
			local side = point - direction * along
			point = direction * along * stretch + side / math.sqrt(stretch)
		end
		table.insert(points, point)
	end
	return points
end

-- Веер треугольников от центра по контуру.
local function fan(list, origin, points, make)
	for index = 1, #points do
		local tri = make()
		tri.origin = origin
		tri.a = Vector3.zero
		tri.b = points[index]
		tri.c = points[index % #points + 1]
		table.insert(list, tri)
	end
end

-- ============ Учёт ============
-- Пятна крови в порядке появления и сколько в них деталей: потолок — по деталям
-- (plan.maxParts), а не по пятнам, — пятно смерти в разы тяжелее капли.
local live = {}
local liveParts = 0

local function keep(stain)
	table.insert(live, stain)
	liveParts += stain.parts
	while liveParts > plan.maxParts and #live > 1 do
		local old = table.remove(live, 1)
		liveParts -= old.parts
		old.gone = true
		Loose.Dissolve(old.model)
	end
end

-- Высыхание ступенями: цвет к высохшему, блик в ноль, прозрачность вверх.
local function dryLater(stain)
	local steps = math.max(plan.drySteps, 1)
	for step = 1, steps do
		task.delay(plan.wetTime + plan.dryTime * step / steps, function()
			if stain.gone or not stain.model.Parent then
				return
			end
			local t = step / steps
			local reflectance = lerp(plan.wetReflectance, 0, t)
			for _, tri in stain.tris do
				if not tri.hidden then
					local color = tri.fresh:Lerp(tri.dry, t)
					local transparency = lerp(plan.wetTransparency, plan.dryTransparency, t)
					tri.transparency = transparency
					for _, part in { tri.w1, tri.w2 } do
						part.Color = color
						part.Reflectance = reflectance
						part.Transparency = transparency
					end
				end
			end
		end)
	end
end

-- ============ Пятно крови ============
-- position — где кровь вышла (жук); size — диаметр основного пятна, studs; drops — брызг.
-- floorY — высота пола для всех капель (Аркада); nil — каждая капля на свою опору (Loose.FloorAt).
-- direction — куда летит кровь (от стрелка, по ходу жука); длина вектора — вытяжка пятна
-- (1 — без вытяжки). nil — капает под себя, брызги во все стороны.
function BloodFX.Splat(position, size, drops, floorY, direction)
	if typeof(position) ~= "Vector3" or not size or size <= 0 then
		return
	end
	drops = drops or 0
	local dir = flat(direction)
	local stretch = dir and math.max(direction.Magnitude, 1) or 1

	local model = Instance.new("Model")
	model.Name = "Blood"
	local stain = { model = model, tris = {}, parts = 0 }

	-- Свой оттенок у пятна, у каждого треугольника — чуть свой поверх (грань видна).
	local shade = randomShade(plan.shade)
	local function make()
		local facet = shade + randomShade(plan.facet)
		local tri = {
			w1 = wedge(model),
			w2 = wedge(model),
			fresh = shifted(BugPalette.Blood, facet),
			dry = shifted(BugPalette.BloodDry, facet),
			transparency = plan.wetTransparency,
		}
		for _, part in { tri.w1, tri.w2 } do
			part.Color = tri.fresh
			part.Reflectance = plan.wetReflectance
			part.Transparency = plan.wetTransparency
		end
		stain.parts += 2
		table.insert(stain.tris, tri)
		return tri
	end
	local function floorAt(at)
		return (floorY or Loose.FloorAt(at.X, at.Z)) + nextLift()
	end

	-- Основное пятно: вытянуто и сдвинуто по удару.
	local radius = size / 2
	local center = position
	if dir then
		center += dir * radius * plan.push
	end
	local corners = math.clamp(math.round(plan.corners[1] + size * plan.cornersPerStud),
		plan.corners[1], plan.corners[2])
	local origin = Vector3.new(center.X, floorAt(center), center.Z)
	local main = {}
	fan(main, origin, outline(radius, corners, plan.ragged, dir, stretch), make)
	local spread = lerp(plan.spreadTime[1], plan.spreadTime[2], math.clamp(size / 2, 0, 1))
	for _, tri in main do
		grow(tri, 0, spread, false)
	end

	-- Брызги: вытянутые остриём от удара, дальние — длиннее. Рядом — мелкие капли.
	local cone = math.rad(plan.cone) / 2
	for _ = 1, drops do
		local u = dir and turned(dir, (math.random() * 2 - 1) * cone) or randomDirection()
		local reach = between(plan.reach)
		local distance = radius * reach
		local far = (reach - plan.reach[1]) / math.max(plan.reach[2] - plan.reach[1], 1e-3)
		local length = size * lerp(plan.dropLength[1], plan.dropLength[2], far)
		local width = length * plan.dropWidth
		local at = position + u * distance
		-- Ромб-«капля»: тупая голова к удару, длинный хвост от него — так ложится капля,
		-- упавшая наискосок. Два треугольника по продольной оси.
		local side = Vector3.new(-u.Z, 0, u.X)
		local origin = Vector3.new(at.X, floorAt(at), at.Z)
		local tail, head = u * length * 0.65, -u * length * 0.35
		local shoulder = -u * length * 0.05
		local delay = distance / plan.flySpeed
		for _, sign in { 1, -1 } do
			local tri = make()
			tri.origin = origin
			tri.a = tail
			tri.b = head
			tri.c = shoulder + side * sign * width / 2
			tri.w1.Transparency, tri.w2.Transparency = 1, 1
			grow(tri, delay, 0.08, true)
		end

		for _ = 1, plan.mist do
			local m = turned(u, (math.random() * 2 - 1) * cone * 0.7)
			local dot = position + m * distance * (0.45 + math.random() * 0.8)
			local s = size * between(plan.mistSize)
			local spin = math.random() * TAU
			local mist = make()
			mist.origin = Vector3.new(dot.X, floorAt(dot), dot.Z)
			mist.a = turned(Vector3.xAxis, spin) * s
			mist.b = turned(Vector3.xAxis, spin + 2.1 + math.random() * 0.4) * s
			mist.c = turned(Vector3.xAxis, spin + 4.2 + math.random() * 0.4) * s
			mist.w1.Transparency, mist.w2.Transparency = 1, 1
			grow(mist, (dot - position).Magnitude / plan.flySpeed, 0.05, true)
		end
	end

	model.Parent = Loose.Folder("Blood")
	keep(stain)
	dryLater(stain)
end

-- ============ Лужа останков ============
-- Лужа лавы, кислоты, талой воды, слизи, болота (CorpseRemains): та же рваная форма, но
-- один цвет и свой материал; жизнь лужи (остывание, исчезание) ведёт вызвавший по
-- возвращённым деталям. Растекается из точки за growTime. В учёт крови не входит —
-- лужи считает список останков.
function BloodFX.Pool(parent, center, floorY, diameter, color, material, growTime)
	local parts = {}
	local origin = Vector3.new(center.X, floorY + nextLift(), center.Z)
	local tris = {}
	local corners = plan.corners[2] + 2
	fan(tris, origin, outline(diameter / 2, corners, plan.ragged * 0.5, nil, 1), function()
		local tri = { w1 = wedge(parent, material), w2 = wedge(parent, material) }
		for _, part in { tri.w1, tri.w2 } do
			part.Name = "Spot"
			part.Color = color
			table.insert(parts, part)
		end
		return tri
	end)
	for _, tri in tris do
		grow(tri, 0, growTime or 0, false)
	end
	return parts
end

-- Забег кончился: поле чистое, сразу и без растворения.
function BloodFX.Clear()
	for _, stain in live do
		stain.gone = true
		if stain.model.Parent then
			stain.model:Destroy()
		end
	end
	table.clear(live)
	table.clear(growing)
	liveParts = 0
end

return BloodFX
