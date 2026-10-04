-- Невидимые крышки над стенами: игрок не уходит с карты поверху.
--
-- Зачем. Потолок бункера (Location.Ceiling) без коллизии нарочно: камера Classic отъезжает
-- вверх сквозь него, а CeilingCutaway прячет его, как только камера выше. Но стены кончаются
-- ровно под потолком, и с того, что стоит у стены, на верх стены запрыгивается: в коридоре —
-- с хомутов труб (верх около 9.3 при стене 10.1), в зале — с короба вытяжки (около 11.1 при
-- стене 16.1). Дальше игрок идёт по стене сквозь потолок и падает наружу, под карту. В лобби
-- потолка нет совсем, а стены 8 studs: со стойки входа в уровень (5 studs) они перепрыгиваются.
--
-- Как. Над каждой плитой потолка — невидимая плита той же площади, низом на низ потолка.
-- В лобби — невидимое продолжение стен вверх. Всё это:
--   — прозрачно (Transparency 1): камера Classic такие детали не считает преградой (Popper
--     пропускает прозрачное), так что вид сверху и срез потолка работают как раньше;
--   — в своей группе столкновений (Loose.Groups.Barrier): держит игрока, а трупы, жуков
--     и машину Аркады пропускает;
--   — в своей папке Workspace.MapBarriers: её исключает луч линии огня (Targeting), а лучи
--     пола, курсора и походки ищут только по своим папкам и сюда не смотрят.
--
-- Размеры не забиты числами: берутся из самих деталей места при каждой смене локации.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Arena = require(ReplicatedStorage:WaitForChild("Arena"))
local Loose = require(ReplicatedStorage:WaitForChild("Loose"))

-- Толщина крышки. Должна быть больше, чем игрок поднимается над низом потолка в прыжке
-- с самой высокой опоры, — иначе он проскочит её насквозь. Запас с лихвой.
local LID_THICKNESS = 4
-- На сколько стены лобби продолжаются вверх. Прыжок игрока 7.2, опора в лобби до 5.
local LOBBY_RAISE = 24
local LOBBY_WALLS = { "WallNear", "WallFar", "WallEast", "WallWest" }

Loose.SetupGroups()

local folder = Workspace:FindFirstChild("MapBarriers")
if not folder then
	folder = Instance.new("Folder")
	folder.Name = "MapBarriers"
	folder.Parent = Workspace
end

local function barrier(name, size, cframe)
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = true
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = size
	part.CFrame = cframe
	part.CollisionGroup = Loose.Groups.Barrier
	part.Parent = folder
	return part
end

local function build()
	folder:ClearAllChildren()

	-- Каждая подпапка Ceiling — своё перекрытие (комната, коридор), как у CeilingCutaway.
	local location = Arena.Location()
	local ceiling = location and location:FindFirstChild("Ceiling")
	if ceiling then
		for _, sub in ceiling:GetChildren() do
			local slab = sub:FindFirstChild("Slab")
			if slab and slab:IsA("BasePart") then
				local bottom = slab.Position.Y - slab.Size.Y / 2
				local cf = slab.CFrame
				barrier("Lid_" .. sub.Name, Vector3.new(slab.Size.X, LID_THICKNESS, slab.Size.Z),
					cf - Vector3.new(0, cf.Position.Y, 0) + Vector3.new(0, bottom + LID_THICKNESS / 2, 0))
			end
		end
	end

	local lobby = Workspace:FindFirstChild("Lobby")
	if lobby then
		for _, name in LOBBY_WALLS do
			local wall = lobby:FindFirstChild(name)
			if wall and wall:IsA("BasePart") then
				local top = wall.CFrame * CFrame.new(0, wall.Size.Y / 2 + LOBBY_RAISE / 2, 0)
				barrier("Raise_" .. name, Vector3.new(wall.Size.X, LOBBY_RAISE, wall.Size.Z), top)
			end
		end
	end
end

build()
Arena.OnChanged(build)
