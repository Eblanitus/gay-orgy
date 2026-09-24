-- Бетонный пол бункера: рельеф, который можно поднимать и опускать прямо в бою.
--
-- Зачем он есть. В игре накопилось несколько механик, которые по документам меняют
-- рельеф, а на деле клали на пол плоскую картонку:
--
--   Окопщик (юнит)   — «копает окопы в полу... жук в окопе ниже линии огня турелей»
--   Литосфера (элемент) — «при убийстве ландшафт карты поднимается/опускается»
--
-- Обе должны трогать один и тот же пол одним и тем же способом — иначе каждая новая
-- механика заводит свою картонку, и две такие картонки в одном месте друг про друга
-- не знают. Поэтому рельеф здесь ведётся одной сеткой высот, а механики только
-- зовут Shape/Restore.
--
-- Как устроено. Пол бункера — решётка бетонных плит поверх невидимого ArenaFloor.
-- ArenaFloor остаётся на месте и остаётся опорной плоскостью: по нему считается вся
-- сетка путей (Arena) и по нему же ставится курсор стройки. Рельеф на поиск пути
-- не влияет вовсе — и это нарочно: окоп по документу прячет жука от турелей,
-- а не меняет маршрут; пересчитывать поле волн на каждую яму было бы ещё и дорого.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local Arena = require(ReplicatedStorage:WaitForChild("Arena"))
-- Только за занятостью клеток: под постройкой пол не шевелится (см. Shape).
-- Grid про ConcreteFloor не знает, так что цикла тут нет.
local Grid = require(script.Parent:WaitForChild("Grid"))

local ConcreteFloor = {}

-- Числа рельефа. Согласованы с геометрией в Workspace: верх BunkerFoundation лежит
-- ниже самой глубокой ямы, иначе яма пробила бы его насквозь и было бы видно небо.
-- Сторона плиты, studs (точный размер подгоняется под поле ниже). Она же — предел
-- того, насколько УЗКИМ вообще может быть окоп: яма набирается из целых плит, и уже
-- одной её не сделать. Было 8 (735 плит) — при нём самый узкий окоп выходил в
-- восемь студов, а тот, что копал Окопщик, — в двадцать четыре.
ConcreteFloor.TILE = 6
-- Глубина выросла вместе с узостью: узкая и мелкая канавка читалась бы царапиной.
-- Предел глубины — чуть меньше высоты прыжка игрока (Humanoid.JumpHeight = 7.2).
-- Стенки окопа отвесные, и яма глубже прыжка заперла бы игрока насмерть. Один
-- окоп и так всего 6, но два наложившихся складываются и упираются именно в этот потолок.
ConcreteFloor.MAX_DEPTH = 6.5 -- на сколько можно опустить
ConcreteFloor.MAX_RISE = 4 -- и на сколько поднять

-- Толщина плиты НЕ косметика. Поднятая на R плита уезжает дном вверх на те же R;
-- если дно поднимется выше соседнего пола, под приподнятым участком останется ЩЕЛЬ:
-- в неё видно насквозь и через неё же проходит луч линии огня (найдено замером:
-- при толщине 2 турель стреляла под вспученным полом). Поэтому толщина не меньше
-- суммы подъёма и самой глубокой ямы рядом: тогда бок плиты закрывает перепад целиком.
ConcreteFloor.THICKNESS = ConcreteFloor.MAX_RISE + ConcreteFloor.MAX_DEPTH

-- С какой скоростью плита едет к своей высоте, studs/сек. Мгновенный перенос
-- читался бы поломкой, а не движением пола.
ConcreteFloor.SPEED = 3

-- Глубина, начиная с которой жук считается «в окопе» — ниже линии огня турелей
-- (атрибут InTrench читает Targeting). Мелкая вмятина укрытием быть не должна.
ConcreteFloor.COVER_DEPTH = 1.5

local BASE_Y, minX, minZ, COLS, ROWS, TILE_X, TILE_Z

-- Прямоугольник пола активной локации. Пересчитывается при смене локации (Arena.OnChanged).
local function bindFloor()
	local floorPart = Arena.Location():WaitForChild("ArenaFloor")
	BASE_Y = Arena.floorY

	minX = floorPart.Position.X - floorPart.Size.X / 2
	minZ = floorPart.Position.Z - floorPart.Size.Z / 2

	-- Плитка ложится РОВНО в поле: число плит целое, а сторона подгоняется под неё.
	-- Иначе по краю арены оставалась бы щель или нахлёст.
	COLS = math.max(1, math.floor(floorPart.Size.X / ConcreteFloor.TILE + 0.5))
	ROWS = math.max(1, math.floor(floorPart.Size.Z / ConcreteFloor.TILE + 0.5))
	TILE_X = floorPart.Size.X / COLS
	TILE_Z = floorPart.Size.Z / ROWS

	ConcreteFloor.Cols = COLS
	ConcreteFloor.Rows = ROWS
end
bindFloor()

local folder = Workspace:FindFirstChild("ConcreteFloor")
if not folder then
	folder = Instance.new("Folder")
	folder.Name = "ConcreteFloor"
	folder.Parent = Workspace
end

local decorate -- объявлена ниже, зовётся из build
local tiles = {} -- ключ -> Part
local height = {} -- ключ -> текущее смещение от BASE_Y
local target = {} -- ключ -> куда едет
local moving = {} -- ключ -> true, пока плита в пути
local speed = {} -- ключ -> своя скорость, если отличается от общей
-- Разметка пола (Location.FloorMarkings). Лежит отдельными тонкими деталями поверх плиты
-- и ездит по высоте вместе с ней: сварка к якорной плите при правке Position не держит.
local decor = {} -- ключ -> { {part, lift}, ... }

-- Участки, которые сейчас отличаются от ровного пола. Нужны Литосфере: по ним она
-- считает жуков в яме и возвращает возвышенность к норме. Списком, а не поиском
-- по всей сетке: участков единицы, а плит сотни.
local zones = {}

local function key(tx, tz)
	return (tz - 1) * COLS + tx
end

local function tileCentre(tx, tz)
	return minX + (tx - 0.5) * TILE_X, minZ + (tz - 0.5) * TILE_Z
end

local function toTile(x, z)
	return math.clamp(math.floor((x - minX) / TILE_X) + 1, 1, COLS),
		math.clamp(math.floor((z - minZ) / TILE_Z) + 1, 1, ROWS)
end

-- Тонкая деталь разметки: не мешает ни ходьбе, ни лучам линии огня, ни курсору стройки.
local function flat(k, cx, cz, sx, sz, lift, color, material, transparency)
	local part = Instance.new("Part")
	part.Name = "Marking"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Size = Vector3.new(sx, 0.02, sz)
	part.Position = Vector3.new(cx, BASE_Y + lift, cz)
	part.Material = material or Enum.Material.SmoothPlastic
	part.Color = color
	part.Transparency = transparency or 0
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = folder
	decor[k] = decor[k] or {}
	table.insert(decor[k], { part = part, lift = lift })
	return part
end

-- Швы: тёмная кромка по четырём краям плиты. Все четыре одинаковы, поэтому
-- неважно, как холст SurfaceGui повёрнут на верхней грани.
local function addSeam(part, seam)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Seam"
	gui.Face = Enum.NormalId.Top
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 25
	local px = math.max(1, math.floor(seam.width * gui.PixelsPerStud + 0.5))
	for _, spec in {
		{ UDim2.new(1, 0, 0, px), UDim2.fromScale(0, 0) },
		{ UDim2.new(1, 0, 0, px), UDim2.new(0, 0, 1, -px) },
		{ UDim2.new(0, px, 1, 0), UDim2.fromScale(0, 0) },
		{ UDim2.new(0, px, 1, 0), UDim2.new(1, -px, 0, 0) },
	} do
		local edge = Instance.new("Frame")
		edge.Size = spec[1]
		edge.Position = spec[2]
		edge.BorderSizePixel = 0
		edge.BackgroundColor3 = seam.color
		edge.BackgroundTransparency = seam.transparency or 0
		edge.Parent = gui
	end
	gui.Parent = part
end

-- Разметка и напольный декор активной локации (документ локации: «Пол: разметка
-- и напольный декор»). Данные — модуль FloorMarkings в самой локации; нет модуля —
-- пол голый. Прямоугольники режутся по плитам, чтобы каждый кусок ездил со своей.
function decorate()
	table.clear(decor)
	local module = Arena.Location():FindFirstChild("FloorMarkings")
	if not module then
		return
	end
	local data = require(module)

	if data.seam then
		for _, part in tiles do
			addSeam(part, data.seam)
		end
	end

	for _, r in data.rects or {} do
		local tx0, tz0 = toTile(r.x0, r.z0)
		local tx1, tz1 = toTile(r.x1 - 1e-3, r.z1 - 1e-3)
		for tz = tz0, tz1 do
			for tx = tx0, tx1 do
				local ax, az = minX + (tx - 1) * TILE_X, minZ + (tz - 1) * TILE_Z
				local x0, x1 = math.max(r.x0, ax), math.min(r.x1, ax + TILE_X)
				local z0, z1 = math.max(r.z0, az), math.min(r.z1, az + TILE_Z)
				if x1 - x0 > 1e-3 and z1 - z0 > 1e-3 then
					flat(key(tx, tz), (x0 + x1) / 2, (z0 + z1) / 2, x1 - x0, z1 - z0,
						0.01 + 0.01 * (r.layer or 1), r.color, r.material, r.transparency)
				end
			end
		end
	end

	for _, d in data.discs or {} do
		local tx, tz = toTile(d.x, d.z)
		local part = flat(key(tx, tz), d.x, d.z, 0.02, 0.02, 0.015, d.color, nil, d.transparency)
		part.Shape = Enum.PartType.Cylinder
		part.Size = Vector3.new(0.02, d.r * 2, d.r * 2)
		part.CFrame = CFrame.new(part.Position) * CFrame.Angles(0, 0, math.pi / 2)
	end
end

-- Поставить плиту на высоту и увезти с ней её разметку.
local function placeTile(k, offset)
	local part = tiles[k]
	part.Position = Vector3.new(part.Position.X, BASE_Y + offset - ConcreteFloor.THICKNESS / 2, part.Position.Z)
	for _, item in decor[k] or {} do
		local p = item.part.Position
		item.part.Position = Vector3.new(p.X, BASE_Y + offset + item.lift, p.Z)
	end
end

-- Плиты строятся один раз при загрузке и дальше только ездят по Y. Пересобирать их
-- на каждую яму значило бы гнать клиентам сотни созданий и удалений посреди боя.
local function build()
	for _, child in folder:GetChildren() do
		child:Destroy()
	end
	table.clear(tiles)
	table.clear(height)
	table.clear(target)
	table.clear(moving)
	table.clear(zones)

	for tz = 1, ROWS do
		for tx = 1, COLS do
			local cx, cz = tileCentre(tx, tz)
			local part = Instance.new("Part")
			part.Name = ("Tile_%d_%d"):format(tx, tz)
			part.Anchored = true
			part.Size = Vector3.new(TILE_X, ConcreteFloor.THICKNESS, TILE_Z)
			part.Position = Vector3.new(cx, BASE_Y - ConcreteFloor.THICKNESS / 2, cz)
			part.Material = Enum.Material.Concrete
			part.Color = Color3.fromRGB(126, 126, 122)
			part.TopSurface = Enum.SurfaceType.Smooth
			part.BottomSurface = Enum.SurfaceType.Smooth
			-- Коллизия есть: по плитам ходит игрок, и по ним же он проваливается в яму.
			part.CanCollide = true
			part.CanTouch = false
			part.Parent = folder

			local k = key(tx, tz)
			tiles[k] = part
			height[k] = 0
			target[k] = 0
		end
	end
	decorate()
end

-- Высота поверхности под точкой. По ней жуки держатся пола (см. Crowd): без этого
-- они бы парили над ямой и тонули в холме.
function ConcreteFloor.HeightAt(x, z)
	local tx, tz = toTile(x, z)
	return BASE_Y + (height[key(tx, tz)] or 0)
end

-- На сколько пол в этой точке отличается от ровного: минус — яма, плюс — возвышенность.
function ConcreteFloor.OffsetAt(x, z)
	local tx, tz = toTile(x, z)
	return height[key(tx, tz)] or 0
end

-- Глубоко ли здесь, чтобы считаться укрытием от турелей.
function ConcreteFloor.IsCover(x, z)
	return ConcreteFloor.OffsetAt(x, z) <= -ConcreteFloor.COVER_DEPTH
end

local function setTarget(k, value, tileSpeed)
	value = math.clamp(value, -ConcreteFloor.MAX_DEPTH, ConcreteFloor.MAX_RISE)
	if math.abs((target[k] or 0) - value) < 1e-3 then
		return
	end
	target[k] = value
	-- Скорость задаётся на движение, а не на плиту навсегда: возвышенность Литосферы
	-- вспучивается резко, а оседает медленно — это два разных движения одних плит.
	speed[k] = tileSpeed
	moving[k] = true
end

-- ОСНОВНАЯ РУЧКА. Поднять (delta > 0) или опустить (delta < 0) круг пола.
--
-- Края сглаживаются: в центре смещение полное, к краю сходит на нет. Без этого
-- яма выглядит вырезанным в полу колодцем с отвесными стенками, и из неё не выйти.
--
-- opts.absolute — не прибавлять к текущей высоте, а задать её (нужно Restore).
-- opts.tag      — чем пометить участок: по нему механика узнаёт свои ямы среди чужих.
-- opts.core     — доля радиуса с ПОЛНЫМ смещением, 0..1. Единица — плоское дно
--                 и отвесные стенки (окоп), маленькая — пологая воронка (ландшафт).
function ConcreteFloor.Shape(position, radius, delta, opts)
	opts = opts or {}
	local cx, cz = position.X, position.Z
	local reachX = math.ceil(radius / TILE_X)
	local reachZ = math.ceil(radius / TILE_Z)
	local centreX, centreZ = toTile(cx, cz)
	local centreKey = key(centreX, centreZ)

	for dz = -reachZ, reachZ do
		for dx = -reachX, reachX do
			local tx, tz = centreX + dx, centreZ + dz
			if tx >= 1 and tx <= COLS and tz >= 1 and tz <= ROWS then
				local px, pz = tileCentre(tx, tz)
				local distance = math.sqrt((px - cx) ^ 2 + (pz - cz) ^ 2)
				-- Под постройкой пол не трогается. Иначе Окопщик подкапывал бы турель, а та оставалась
				-- висеть в воздухе на прежней высоте: постройки ставятся по номинальному уровню
				-- пола и за рельефом не следят. Фундамент под бетонной турелью — это и по-игровому
				-- верно: подкопать её нельзя, можно только снести.
				-- Клетка сетки путей считается по ЦЕНТРУ плиты, а не по её номеру: клетка сетки
				-- — 0.8 студа, плита — восемь, и номера у них разные вещи.
				local built = false
				if opts.overBuildings ~= true then
					built = Grid.GetOccupant(Grid.ToCell(Vector3.new(px, 0, pz))) ~= nil
				end
				if distance <= radius and not built then
					-- Спад от центра к краю, но с ПЛОСКИМ ЯДРОМ. Чистый косинус годится, пока яма
					-- много шире плиты. У узкого окопа (радиус с плиту) он съедал глубину
					-- почти целиком: центр ямы почти никогда не попадает в центр плиты, и уже
					-- на полплиты смещения заказанные пять студов превращались в полтора (замерено).
					--
					-- Теперь ближняя треть радиуса получает полное смещение, а сглаживается
					-- только край. Плюс плита, в которой стоит сам центр, берёт смещение целиком
					-- всегда: «выкопал на пять» должно значить пять, а не сколько вышло по сетке.
					local k = key(tx, tz)
					local falloff
					if k == centreKey then
						falloff = 1
					else
						-- Доля радиуса, где смещение ещё полное. У ландшафта она маленькая
						-- (пологая воронка), у окопа — единица: у окопа дно плоское.
						local core = math.clamp(opts.core or 0.35, 0, 1)
						if core >= 1 then
							falloff = 1
						else
							local t = math.clamp((distance - radius * core) / (radius * (1 - core)), 0, 1)
							falloff = 0.5 + 0.5 * math.cos(math.pi * t)
						end
					end
					if opts.absolute then
						setTarget(k, (target[k] or 0) + (delta - (target[k] or 0)) * falloff, opts.speed)
					else
						setTarget(k, (target[k] or 0) + delta * falloff, opts.speed)
					end
				end
			end
		end
	end

	local zone = {
		position = Vector3.new(cx, BASE_Y, cz),
		radius = radius,
		delta = delta,
		tag = opts.tag,
		created = os.clock(),
	}
	table.insert(zones, zone)
	return zone
end

-- Вернуть участок к ровному полу. Нужно Литосфере («возвышенность медленно
-- опускается до нормального уровня») и ремонту пола.
function ConcreteFloor.Restore(position, radius, opts)
	opts = opts or {}
	local cx, cz = position.X, position.Z
	local reachX = math.ceil(radius / TILE_X)
	local reachZ = math.ceil(radius / TILE_Z)
	local centreX, centreZ = toTile(cx, cz)

	for dz = -reachZ, reachZ do
		for dx = -reachX, reachX do
			local tx, tz = centreX + dx, centreZ + dz
			if tx >= 1 and tx <= COLS and tz >= 1 and tz <= ROWS then
				local px, pz = tileCentre(tx, tz)
				if math.sqrt((px - cx) ^ 2 + (pz - cz) ^ 2) <= radius then
					setTarget(key(tx, tz), 0, opts.speed)
				end
			end
		end
	end

	for i = #zones, 1, -1 do
		local zone = zones[i]
		if (Vector3.new(zone.position.X, 0, zone.position.Z)
			- Vector3.new(cx, 0, cz)).Magnitude <= radius then
			table.remove(zones, i)
		end
	end
end

-- Участки, которые сейчас не ровные. Копия списка: править его снаружи нельзя.
function ConcreteFloor.Zones(tag)
	local list = {}
	for _, zone in zones do
		if not tag or zone.tag == tag then
			table.insert(list, zone)
		end
	end
	return list
end

-- Ровный пол заново — на рестарт забега, вместе со всей остальной ареной.
-- Плиты не пересоздаются, а сразу встают на место: новый забег начинается с ровного
-- пола, а не с медленно выползающего из ям прошлого.
function ConcreteFloor.Reset()
	table.clear(zones)
	table.clear(moving)
	table.clear(speed)
	for k in tiles do
		height[k] = 0
		target[k] = 0
		placeTile(k, 0)
	end
end

build()

Arena.OnChanged(function()
	bindFloor()
	table.clear(speed)
	build()
end)

-- Движение плит. Шагают только те, что ещё едут: проходить всю сетку каждый кадр
-- ради десятка двигающихся — семьсот холостых проверок шестьдесят раз в секунду.
RunService.Heartbeat:Connect(function(dt)
	if next(moving) == nil then
		return
	end

	local step = ConcreteFloor.SPEED * dt
	for k in moving do
		local part = tiles[k]
		if not part then
			moving[k] = nil
		else
			local now, want = height[k] or 0, target[k] or 0
			local diff = want - now
			local step = speed[k] and speed[k] * dt or step
			if math.abs(diff) <= step then
				now = want
				moving[k] = nil
			else
				now += step * math.sign(diff)
			end
			height[k] = now
			placeTile(k, now)
		end
	end
end)

return ConcreteFloor
