-- Обломки разрушенных турелей: куски самой постройки, разбросанные по её следу.
--
-- Это не руина (EnemyStructures.Ruin) — руина остаётся как была: куча материала, которую
-- ест Строитель. Обломки — то, по чему жуки ХОДЯТ: тело поднимается на них (Crowd спрашивает
-- HeightAt), лапы ставятся на них (EnemyGait ловит лучом папку TowerDebris). Клеток сетки
-- они не занимают и маршрут не меняют: низкие, жук через них перешагивает, а не обходит.
--
-- Каждый обломок — уменьшенная копия детали той самой постройки (её меш, цвет, материал),
-- положенная плашмя: по куску видно, что тут стояло. Деталей нет (не нашлось) — простой
-- брусок в цвет постройки.
--
-- Число деталей на поле ограничено (MAX_PIECES): новые вытесняют самые старые. Иначе к концу
-- длинного забега обломки копились бы сотнями — те же грабли, что с останками жуков.
local Workspace = game:GetService("Workspace")
local ServerScriptService = game:GetService("ServerScriptService")

local ConcreteFloor = require(ServerScriptService:WaitForChild("ConcreteFloor"))

local TowerDebris = {}

-- Сколько обломков от одной постройки: от её ширины, в пределах [MIN_PER, MAX_PER].
local MIN_PER, MAX_PER = 3, 7
local PER_STUD = 0.6 -- обломков на студ ширины следа

-- Потолок обломков на всём поле.
local MAX_PIECES = 48

-- Обломок лежит плашмя и невысокий — по нему ходят, а не лезут. Высота куска над полом
-- не больше MAX_HEIGHT, длинная сторона — не больше доли ширины постройки.
local MAX_HEIGHT = 0.7
local MAX_LENGTH_SHARE = 0.35
local MIN_LENGTH = 0.6
local MAX_LENGTH = 3

-- Обгоревший вид: цвет детали подтемняется к этому.
local SCORCH = Color3.fromRGB(40, 36, 32)
local SCORCH_SHARE = 0.35

-- Ячейка пространственной сетки для HeightAt: спрашивают каждый кадр на каждого жука,
-- и проход по всем обломкам на каждый вопрос стоил бы зря.
local BUCKET = 4

local folder = Workspace:FindFirstChild("TowerDebris")
if not folder then
	folder = Instance.new("Folder")
	folder.Name = "TowerDebris"
	folder.Parent = Workspace
end

local pieces = {} -- по порядку появления, старые первые
local buckets = {} -- "bx|bz" -> { piece, ... }

local function bucketKey(bx, bz)
	return bx .. "|" .. bz
end

-- Ячейки, которые накрывает обломок (по описанному кругу — с запасом, дёшево).
local function eachBucket(piece, fn)
	local r = piece.radius
	local x0, x1 = math.floor((piece.x - r) / BUCKET), math.floor((piece.x + r) / BUCKET)
	local z0, z1 = math.floor((piece.z - r) / BUCKET), math.floor((piece.z + r) / BUCKET)
	for bx = x0, x1 do
		for bz = z0, z1 do
			fn(bucketKey(bx, bz))
		end
	end
end

local function unindex(piece)
	eachBucket(piece, function(k)
		local list = buckets[k]
		if list then
			local i = table.find(list, piece)
			if i then
				table.remove(list, i)
			end
			if #list == 0 then
				buckets[k] = nil
			end
		end
	end)
end

local function removePiece(index)
	local piece = table.remove(pieces, index)
	if piece then
		unindex(piece)
		if piece.part.Parent then
			piece.part:Destroy()
		end
	end
end

local function addPiece(part, flat, hx, hz, top)
	local at = flat.Position
	local piece = {
		part = part,
		x = at.X,
		z = at.Z,
		-- Плоский кадр (только поворот вокруг вертикали): в нём проверяется, накрывает ли
		-- кусок точку. Наклон куска на высоту почти не влияет — им пренебрегаем.
		flat = flat,
		hx = hx,
		hz = hz,
		top = top,
		radius = math.sqrt(hx * hx + hz * hz),
	}
	table.insert(pieces, piece)
	eachBucket(piece, function(k)
		local list = buckets[k]
		if not list then
			list = {}
			buckets[k] = list
		end
		table.insert(list, piece)
	end)

	while #pieces > MAX_PIECES do
		removePiece(1)
	end
end

-- Детали постройки, годные в обломки: видимые и не служебные. Самые крупные (платформа)
-- тоже годятся — их всё равно уменьшат до куска.
local function sourceParts(tower)
	local list = {}
	for _, part in tower:GetDescendants() do
		if part:IsA("BasePart") and part ~= tower.PrimaryPart and part.Transparency < 0.6
			and part.Size.Magnitude > 0.4 then
			table.insert(list, part)
		end
	end
	return list
end

-- Делает из детали плоский кусок: тонкая ось — вверх, уменьшение — равномерное (меш не
-- плющится), так чтобы и высота, и длина влезли в пределы. Возвращает кусок и его размеры
-- по горизонтали и вертикали после укладки.
local function shapeChunk(source, maxLength)
	local chunk
	if source then
		chunk = source:Clone()
		chunk:ClearAllChildren()
		for name in chunk:GetAttributes() do
			chunk:SetAttribute(name, nil)
		end
		chunk.Color = chunk.Color:Lerp(SCORCH, SCORCH_SHARE)
	else
		chunk = Instance.new("Part")
		chunk.Color = Color3.fromRGB(96, 90, 82)
		chunk.Material = Enum.Material.Metal
		chunk.Size = Vector3.new(1.2, 0.4, 0.9)
	end

	local size = chunk.Size
	local longest = math.max(size.X, size.Y, size.Z)
	local thinnest = math.min(size.X, size.Y, size.Z)
	local scale = math.min(1, maxLength / longest, MAX_HEIGHT / thinnest)
	local length = math.clamp(longest * scale, MIN_LENGTH, maxLength)
	scale = length / longest
	-- Деталь-брусок (толщина почти равна длине) остаётся выше MAX_HEIGHT и после этого —
	-- тогда она урезается по высоте ещё раз, уже ценой длины.
	if thinnest * scale > MAX_HEIGHT then
		scale = MAX_HEIGHT / thinnest
	end
	chunk.Size = size * scale
	size = chunk.Size

	-- Какую локальную ось класть вверх: самую тонкую.
	local lay
	local up, a, b
	if size.Y <= size.X and size.Y <= size.Z then
		lay, up, a, b = CFrame.identity, size.Y, size.X, size.Z
	elseif size.X <= size.Z then
		lay, up, a, b = CFrame.Angles(0, 0, math.pi / 2), size.X, size.Y, size.Z
	else
		lay, up, a, b = CFrame.Angles(math.pi / 2, 0, 0), size.Z, size.X, size.Y
	end

	chunk.Name = "Debris"
	chunk.Anchored = true
	-- Игрок и снаряды сквозь обломки проходят, линию огня они не закрывают (Targeting берёт
	-- только то, что с коллизией). Луч походки их ловит — по белому списку папки.
	chunk.CanCollide = false
	chunk.CanTouch = false
	chunk.CanQuery = true
	chunk.CastShadow = true
	return chunk, lay, up, a, b
end

-- Оставляет обломки разрушенной постройки. Звать ДО tower:Destroy() — детали берутся с неё.
-- footprint — ширина следа в студах (Towers[type].footprint), по ней разбрасываются куски.
function TowerDebris.Leave(tower, footprint)
	local centre = tower:GetPivot().Position
	local width = math.max(footprint or 4, 2)
	local count = math.clamp(math.round(width * PER_STUD), MIN_PER, MAX_PER)
	local maxLength = math.clamp(width * MAX_LENGTH_SHARE, MIN_LENGTH, MAX_LENGTH)
	local sources = sourceParts(tower)

	for _ = 1, count do
		local source = #sources > 0 and sources[math.random(1, #sources)] or nil
		local chunk, lay, up, a, b = shapeChunk(source, maxLength)

		-- Разлёт — по всему следу, гуще к центру.
		local angle = math.random() * math.pi * 2
		local distance = math.sqrt(math.random()) * width * 0.5
		local x = centre.X + math.cos(angle) * distance
		local z = centre.Z + math.sin(angle) * distance
		local floorY = ConcreteFloor.HeightAt(x, z)

		-- Чуть утоплен в пол и с небольшим наклоном: кусок лежит, а не парит ровной плиткой.
		local yaw = math.random() * math.pi * 2
		local sink = up * 0.2
		local flat = CFrame.new(x, floorY + up / 2 - sink, z) * CFrame.Angles(0, yaw, 0)
		local tilt = CFrame.Angles((math.random() - 0.5) * 0.25, 0, (math.random() - 0.5) * 0.25)
		chunk.CFrame = flat * tilt * lay
		chunk.Parent = folder

		addPiece(chunk, flat, a / 2, b / 2, floorY + up - sink)
	end
end

-- На сколько поверхность обломков в этой точке выше пола. 0 — обломков тут нет.
-- Толкучка поднимает на это тело жука (Crowd), чтобы он шёл ПО обломкам, а не сквозь них.
function TowerDebris.HeightAt(x, z)
	local list = buckets[bucketKey(math.floor(x / BUCKET), math.floor(z / BUCKET))]
	if not list then
		return 0
	end
	local best = nil
	for _, piece in list do
		local dx, dz = x - piece.x, z - piece.z
		if dx * dx + dz * dz <= piece.radius * piece.radius then
			local p = piece.flat:PointToObjectSpace(Vector3.new(x, piece.flat.Position.Y, z))
			if math.abs(p.X) <= piece.hx and math.abs(p.Z) <= piece.hz then
				if not best or piece.top > best then
					best = piece.top
				end
			end
		end
	end
	if not best then
		return 0
	end
	return math.max(0, best - ConcreteFloor.HeightAt(x, z))
end

-- Убирает обломки в круге — на месте новой постройки: она встаёт на чистый пол,
-- а не вперемешку с кусками старой.
function TowerDebris.ClearUnder(position, radius)
	for i = #pieces, 1, -1 do
		local piece = pieces[i]
		local dx, dz = piece.x - position.X, piece.z - position.Z
		if dx * dx + dz * dz <= (radius + piece.radius) ^ 2 then
			removePiece(i)
		end
	end
end

-- Сносит всё разом — для рестарта забега, как EnemyStructures.Clear.
function TowerDebris.Clear()
	for i = #pieces, 1, -1 do
		removePiece(i)
	end
	table.clear(buckets)
	folder:ClearAllChildren()
end

return TowerDebris
