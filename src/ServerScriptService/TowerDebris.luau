-- Обломки разрушенных турелей: турель РАСПАДАЕТСЯ на свои настоящие детали.
--
-- Когда постройка ломается, её детали отваливаются: верх разлетается дальше, низ оседает
-- на месте, каждая кувыркается в полёте и ложится плашмя. Дальше детали делятся на два сорта:
--
--   * куски (piece) — крупные детали и те, что годятся в материал. Остаются лежать, по ним
--     жуки ХОДЯТ: тело поднимается на них (Crowd спрашивает HeightAt), лапы встают на них
--     (EnemyGait ловит лучом папку TowerDebris). Клеток сетки не занимают, маршрут не меняют.
--   * крошки — мелочь (винтики, трубки). Разлетаются вместе со всеми и через пару секунд тают:
--     у Колбы под семь десятков деталей, и оставлять их все на поле незачем.
--
-- Часть кусков несёт материал (атрибут Material): это то, что жуки СОБИРАЮТ. Работяга
-- поднимает деталь и несёт её на спине к Строителю (Pick/Carry/Drop), Строитель её съедает
-- и строит из неё (Consume). Сколько деталей несут материал — та же формула, что у руины
-- (EnemyStructures.MaterialFor): разрушенная турель даёт жукам столько же, сколько давала.
--
-- Полёт считается здесь же, кадрами, а не физикой движка: пол арены без коллизии
-- (бетон — визуальный, см. ConcreteFloor), и отпущенная деталь провалилась бы сквозь него.
--
-- Число кусков на поле ограничено (MAX_PIECES): новые вытесняют самые старые.
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local ConcreteFloor = require(ServerScriptService:WaitForChild("ConcreteFloor"))

local TowerDebris = {}

-- Сколько деталей одной постройки остаются лежать кусками (без учёта материала) и сколько
-- разлетаются крошками. Остальная мелочь исчезает сразу, в момент распада.
local KEEP = 6
local CRUMBS = 24

-- Потолок кусков на всём поле.
local MAX_PIECES = 48

-- Деталь, которую жук может унести: самая длинная сторона не больше этого.
local CARRY_MAX = 3.5

-- Падение. Не взрыв, а развал: детали в основном валятся вниз и чуть в стороны.
-- Тяжёлая деталь (объём от HEAVY_VOLUME) почти не отлетает и не подпрыгивает — оседает
-- и заваливается; лёгкая отлетает дальше и успевает немного повернуться.
local HEAVY_VOLUME = 6
local SCATTER = { 0.08, 0.35 } -- разлёт лёгкой детали с верха турели, доля ширины следа
local ARC_HEIGHT = { 0.2, 0.8 } -- подскок над прямой траекторией у лёгкой детали, студы
local TUMBLE = { 0.15, 0.6 } -- лишний поворот в воздухе у лёгкой, радианы (сверх укладки)
local YAW_DRIFT = 0.5 -- насколько деталь доворачивается вокруг вертикали, радианы
-- Время падения — от высоты, как у настоящего падения (растёт корнем), в этих пределах.
local FALL_TIME_PER_ROOT = 0.25
local FALL_TIME = { 0.45, 0.9 }
-- Детали отваливаются не все в один кадр, а вразнобой — верх раньше.
local STAGGER = 0.25

-- Крошки: сколько лежат после падения и за сколько тают.
local CRUMB_LIFE = 2.5
local CRUMB_FADE = 1

-- Обгоревший вид: цвет детали подтемняется к этому.
local SCORCH = Color3.fromRGB(40, 36, 32)
local SCORCH_SHARE = 0.3

-- Ячейка пространственной сетки для HeightAt: спрашивают каждый кадр на каждого жука.
local BUCKET = 4

local folder = Workspace:FindFirstChild("TowerDebris")
if not folder then
	folder = Instance.new("Folder")
	folder.Name = "TowerDebris"
	folder.Parent = Workspace
end

local pieces = {} -- лежащие куски по порядку появления, старые первые
local buckets = {} -- "bx|bz" -> { piece, ... }
local flying = {} -- детали в полёте

local function bucketKey(bx, bz)
	return bx .. "|" .. bz
end

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

local function index(piece)
	eachBucket(piece, function(k)
		local list = buckets[k]
		if not list then
			list = {}
			buckets[k] = list
		end
		table.insert(list, piece)
	end)
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

-- Снять кусок с поля (из списка и сетки высот). Деталь при этом остаётся — её решает вызвавший.
local function detach(piece)
	local i = table.find(pieces, piece)
	if i then
		table.remove(pieces, i)
		unindex(piece)
	end
end

local function destroyPiece(piece)
	detach(piece)
	if piece.part.Parent then
		piece.part:Destroy()
	end
end

-- Как положить деталь плашмя: самая тонкая её ось — вверх. Возвращает поворот укладки,
-- толщину (высоту над полом) и две стороны по горизонтали.
local function layFlat(size)
	if size.Y <= size.X and size.Y <= size.Z then
		return CFrame.identity, size.Y, size.X, size.Z
	elseif size.X <= size.Z then
		return CFrame.Angles(0, 0, math.pi / 2), size.X, size.Y, size.Z
	end
	return CFrame.Angles(math.pi / 2, 0, 0), size.Z, size.X, size.Y
end

-- Где и как деталь ляжет на полу в точке (x, z) с поворотом yaw.
local function restingFrame(part, x, z, yaw)
	local lay, up, a, b = layFlat(part.Size)
	local floorY = ConcreteFloor.HeightAt(x, z)
	local flat = CFrame.new(x, floorY + up / 2, z) * CFrame.Angles(0, yaw, 0)
	return flat * lay, flat, up, a, b, floorY
end

-- Положить кусок на поле: по нему ходят, его можно подобрать (если несёт материал).
local function rest(part, flat, up, a, b, floorY, material)
	local piece = {
		part = part,
		x = flat.Position.X,
		z = flat.Position.Z,
		flat = flat,
		hx = a / 2,
		hz = b / 2,
		top = floorY + up,
		radius = math.sqrt(a * a + b * b) / 2,
		material = material,
	}
	part:SetAttribute("Material", material)
	table.insert(pieces, piece)
	index(piece)

	while #pieces > MAX_PIECES do
		destroyPiece(pieces[1])
	end
	return piece
end

-- Деталь отрывается от модели: чистая, анкорнутая, без коллизии (игрок и снаряды сквозь неё
-- проходят, линию огня она не закрывает — Targeting берёт только то, что с коллизией),
-- но ловится лучом (по ней ставятся лапы).
-- Внешний вид детали (текстура меша, наклейки) остаётся, всё остальное — сварки, крепления,
-- частицы, звуки — снимается: деталь больше не часть турели.
local KEEP_CHILD = { SurfaceAppearance = true, Decal = true, Texture = true, SpecialMesh = true }

local function prepare(part)
	for _, child in part:GetChildren() do
		if not KEEP_CHILD[child.ClassName] then
			child:Destroy()
		end
	end
	for name in part:GetAttributes() do
		part:SetAttribute(name, nil)
	end
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = true
	part.Color = part.Color:Lerp(SCORCH, SCORCH_SHARE)
	part.Parent = folder
end

local function crumbFade(part)
	task.delay(CRUMB_LIFE, function()
		local start = os.clock()
		local base = part.Transparency
		while part.Parent and os.clock() - start < CRUMB_FADE do
			part.Transparency = base + (1 - base) * (os.clock() - start) / CRUMB_FADE
			RunService.Heartbeat:Wait()
		end
		if part.Parent then
			part:Destroy()
		end
	end)
end

-- Все детали в полёте ведёт одна подписка на кадр, а не по потоку на деталь.
local connection = nil
local function step()
	local now = os.clock()
	for i = #flying, 1, -1 do
		local f = flying[i]
		local t = math.clamp((now - f.start) / f.duration, 0, 1)
		if not f.part.Parent then
			table.remove(flying, i)
		elseif now >= f.start then
			-- По горизонтали — с затуханием (толчок в начале), по вертикали — с разгоном
			-- вниз (t²), как падение, плюс небольшой подскок у лёгких деталей.
			local from, to = f.from.Position, f.to.Position
			local h = 1 - (1 - t) * (1 - t)
			local x = from.X + (to.X - from.X) * h
			local z = from.Z + (to.Z - from.Z) * h
			local y = from.Y + (to.Y - from.Y) * t * t + f.arc * 4 * t * (1 - t)
			-- Поворот к положению лёжа идёт вместе с падением (заваливается), а лишний
			-- поворот в воздухе невелик и к касанию гаснет.
			local rotation = f.from.Rotation:Lerp(f.to.Rotation, t)
				* CFrame.fromAxisAngle(f.axis, f.spin * math.sin(math.pi * t))
			f.part.CFrame = CFrame.new(x, y, z) * rotation
			if t >= 1 then
				table.remove(flying, i)
				f.part.CFrame = f.to
				f.landed()
			end
		end
	end
	if #flying == 0 and connection then
		connection:Disconnect()
		connection = nil
	end
end

local function launch(part, to, arc, spin, duration, delay, landed)
	table.insert(flying, {
		part = part,
		from = part.CFrame,
		to = to,
		arc = arc,
		duration = duration,
		start = os.clock() + delay,
		axis = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5).Unit,
		spin = spin,
		landed = landed,
	})
	if not connection then
		connection = RunService.Heartbeat:Connect(step)
	end
end

local function between(range)
	return range[1] + math.random() * (range[2] - range[1])
end

-- Видимые детали постройки, крупные первыми.
local function partsOf(tower)
	local list = {}
	for _, part in tower:GetDescendants() do
		if part:IsA("BasePart") and part ~= tower.PrimaryPart and part.Transparency < 0.9
			and part.Size.Magnitude > 0.3 then
			table.insert(list, part)
		end
	end
	table.sort(list, function(a, b)
		local sa, sb = a.Size, b.Size
		return sa.X * sa.Y * sa.Z > sb.X * sb.Y * sb.Z
	end)
	return list
end

-- Турель распадается. Звать ДО tower:Destroy() — детали переезжают из модели в папку обломков.
-- footprint — ширина следа в студах (Towers[type].footprint), material — сколько деталей
-- понесут материал для жуков.
function TowerDebris.Leave(tower, footprint, material)
	local centre = tower:GetPivot().Position
	local width = math.max(footprint or 4, 2)
	local parts = partsOf(tower)

	-- Кто несёт материал: крупнейшие из тех, что жук способен унести.
	local carriers, carrierCount = {}, 0
	for _, part in parts do
		if carrierCount >= (material or 0) then
			break
		end
		if math.max(part.Size.X, part.Size.Y, part.Size.Z) <= CARRY_MAX then
			carriers[part] = true
			carrierCount += 1
		end
	end

	local kept, crumbs = 0, 0
	for _, part in parts do
		local role
		if carriers[part] then
			role = "material"
		elseif kept < KEEP then
			kept += 1
			role = "piece"
		elseif crumbs < CRUMBS then
			crumbs += 1
			role = "crumb"
		end

		if not role then
			part:Destroy()
		else
			local from = part.CFrame
			prepare(part)

			-- Куда валится: от центра в сторону своего места на турели, и тем дальше, чем выше
			-- деталь сидела и чем она легче. Низ (платформа) оседает на месте.
			local offset = from.Position - centre
			local outward = Vector3.new(offset.X, 0, offset.Z)
			local angle = outward.Magnitude > 0.2 and math.atan2(outward.Z, outward.X) or math.random() * math.pi * 2
			angle += (math.random() - 0.5) * 0.8
			local lift = math.clamp(offset.Y / 4, 0, 1)
			local size = part.Size
			local light = 1 - math.clamp(size.X * size.Y * size.Z / HEAVY_VOLUME, 0, 1)
			local distance = outward.Magnitude + width * between(SCATTER) * lift * (0.3 + 0.7 * light)
			local x = centre.X + math.cos(angle) * distance
			local z = centre.Z + math.sin(angle) * distance
			-- Ложится почти как стояла, лишь немного довернувшись, — а не в случайную сторону:
			-- полный случайный разворот в полёте читался как волчок.
			local _, yaw = from:ToEulerAnglesYXZ()
			local to, flat, up, a, b, floorY = restingFrame(part, x, z, yaw + (math.random() - 0.5) * YAW_DRIFT)

			local drop = math.max(from.Position.Y - to.Position.Y, 0)
			local duration = math.clamp(math.sqrt(drop) * FALL_TIME_PER_ROOT, FALL_TIME[1], FALL_TIME[2])
			local delay = (1 - lift) * STAGGER * math.random()

			local unit = role == "material" and 1 or nil
			launch(part, to, between(ARC_HEIGHT) * lift * light, between(TUMBLE) * light,
				duration, delay, function()
				if role == "crumb" then
					crumbFade(part)
				else
					rest(part, flat, up, a, b, floorY, unit)
				end
			end)
		end
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

-- Ближайший лежащий кусок с материалом в радиусе.
local function nearestMaterial(position, radius)
	local best, bestDistance = nil, radius
	for _, piece in pieces do
		if piece.material then
			local distance = Vector3.new(piece.x - position.X, 0, piece.z - position.Z).Magnitude
			if distance <= bestDistance then
				best, bestDistance = piece, distance
			end
		end
	end
	return best
end

-- Строитель съедает деталь: она уходит с поля. true — съел.
function TowerDebris.Consume(position, radius)
	local piece = nearestMaterial(position, radius)
	if not piece then
		return false
	end
	destroyPiece(piece)
	return true
end

-- Положить деталь на пол в точке (с поля она уже снята): снова кусок, по которому ходят,
-- снова материал, который можно подобрать.
local function putDown(part, position, material)
	local to, flat, up, a, b, floorY = restingFrame(part, position.X, position.Z, math.random() * math.pi * 2)
	part.Anchored = true
	part.CFrame = to
	part.Parent = folder
	rest(part, flat, up, a, b, floorY, material)
end

-- Работяга поднимает деталь и несёт её на спине: деталь приварена к его якорю и едет
-- вместе с ним. Возвращает деталь (её потом отдают в Drop) или nil, если рядом нечего брать.
-- Умер с ношей — деталь падает там, где он упал, и снова лежит материалом.
function TowerDebris.Carry(enemy, position, radius, backHeight)
	local root = enemy.PrimaryPart
	local piece = root and nearestMaterial(position, radius)
	if not piece then
		return nil
	end
	detach(piece)

	local part = piece.part
	local lay, up = layFlat(part.Size)
	part.Anchored = false
	part.Massless = true
	part.CFrame = root.CFrame * CFrame.new(0, (backHeight or 1) + up / 2, 0) * lay
	-- Деталь остаётся в папке обломков, а не в модели жука: модель жука — это якорь с атрибутами,
	-- и лишняя деталь внутри неё попалась бы всему, что меряет жука по его частям.
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = part
	weld.Parent = part

	enemy.Destroying:Once(function()
		if weld.Parent and part.Parent then
			local at = part.Position
			weld:Destroy()
			putDown(part, at, 1)
		end
	end)
	return part
end

-- Положить принесённую деталь у ног Строителя.
function TowerDebris.Drop(part, position)
	if not part or not part.Parent then
		return
	end
	local weld = part:FindFirstChildWhichIsA("WeldConstraint")
	if weld then
		weld:Destroy()
	end
	putDown(part, position, 1)
end

-- Убирает лежащие куски в круге — на месте новой постройки: она встаёт на чистый пол.
function TowerDebris.ClearUnder(position, radius)
	for i = #pieces, 1, -1 do
		local piece = pieces[i]
		local dx, dz = piece.x - position.X, piece.z - position.Z
		if dx * dx + dz * dz <= (radius + piece.radius) ^ 2 then
			destroyPiece(piece)
		end
	end
end

-- Сносит всё разом — для рестарта забега, как EnemyStructures.Clear.
function TowerDebris.Clear()
	table.clear(flying)
	for i = #pieces, 1, -1 do
		destroyPiece(pieces[i])
	end
	table.clear(buckets)
	folder:ClearAllChildren()
end

return TowerDebris
