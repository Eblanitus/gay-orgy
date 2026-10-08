-- Твёрдые детали карты, которые в месте сохранены без коллизии.
--
-- Зачем. Аудит коллизии (#380, #385) нашёл в лаборатории детали, сквозь которые игрок проходит:
-- тумбы и верстак, ножки стола крафта, комнаты наблюдения в стенах над залом (вместе с
-- бронестеклом). Раньше их чинил разовый скрипт tools/studio/map_collision.luau, но такая
-- правка живёт только в сохранённом месте: забыл Ctrl+S или сменил ветку — коллизии снова нет.
-- Здесь то же самое делается при каждой загрузке локации, так что место сохранять не нужно.
--
-- Мелочь на полках и столах (колбы, пробирки, ручки, швы) и мебель внутри комнат наблюдения
-- остаются без коллизии нарочно. Форму столкновения мешей турелей (CollisionFidelity) из
-- скрипта во время игры менять нельзя — она остаётся за tools/studio/map_collision.luau.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Arena = require(ReplicatedStorage:WaitForChild("Arena"))
local Loose = require(ReplicatedStorage:WaitForChild("Loose"))

Loose.SetupGroups()

-- parent — имя модели-владельца (или prefix — начало имени), names — какие её детали твёрдые.
local RULES = {
	{ parent = "LabBench", names = { Cabinet = true, Top = true, Plinth = true } },
	{ parent = "Workbench", names = { Cabinet = true, Plinth = true } },
	{ parent = "CraftTable", names = { Leg1 = true, Leg2 = true, Leg3 = true, Leg4 = true } },
	{
		prefix = "ObsPost_",
		names = {
			Shell = true, ShellFill = true, RoomFloor = true,
			LiningFront = true, LiningSide = true, LiningBack = true,
			Reveal = true, Sill = true, Frame = true, FrameHead = true, Mullion = true, ArmorGlass = true,
		},
	},
}

-- Общее правило поверх имён: любая заметная непрозрачная деталь локации твёрдая, на любой
-- высоте. Имена в месте меняются (тумба у южной стены — LabBench в одной версии места и иначе
-- в другой; операторская на южной стене собрана в Studio под своим именем), и правила по именам
-- их теряли. Заметность — по самой большой грани, а не по объёму: тонкое стекло операторской
-- (4×3×0.2) по объёму сходило за мелочь, и в комнату заходили сквозь окно (скрины автора).
-- Мелочь (колбы, пробирки, ручки) отсекает грань, плоскую разметку пола — высота верха.
local BODY_BOTTOM = 0.7 -- верх детали выше этого над полом — в неё можно войти телом
local MIN_FACE = 2 -- studs²: самая большая грань меньше — мелочь на столах, её не трогаем
-- потолок прячет камера, маркеры — разметка, GateSoft — световые линии и плоский декор двери (EntranceGate)
local SKIP = { Ceiling = true, Markers = true, GateSoft = true }

local function noticeable(part, floorY)
	local size = part.Size
	local face = math.max(size.X * size.Y, size.Y * size.Z, size.X * size.Z)
	if face < MIN_FACE or part.Transparency >= 0.95 then
		return false
	end
	-- Полувысота ящика детали по вертикали с учётом поворота.
	local cf = part.CFrame
	local halfY = (math.abs(cf.RightVector.Y) * size.X + math.abs(cf.UpVector.Y) * size.Y
		+ math.abs(cf.LookVector.Y) * size.Z) / 2
	return part.Position.Y - floorY + halfY > BODY_BOTTOM
end

local function skipped(part, location)
	local p = part.Parent
	while p and p ~= location do
		if SKIP[p.Name] then
			return true
		end
		p = p.Parent
	end
	return false
end

-- Комната наблюдения целиком, со всеми подпорками и обшивкой снизу, какой бы мелкой ни была
-- деталь: в неё лезут прыжком снизу. Мебель внутри за твёрдой коробкой и так недоступна.
local function inObsPost(part, location)
	local p = part.Parent
	while p and p ~= location do
		if p.Name:sub(1, 8) == "ObsPost_" then
			return true
		end
		p = p.Parent
	end
	return false
end

local function parentMatches(rule, name)
	if rule.prefix then
		return name:sub(1, #rule.prefix) == rule.prefix
	end
	return name == rule.parent
end

local function apply()
	local location = Arena.Location()
	if not location then
		return
	end
	local floorY = Arena.floorY or 0 -- верх пола активной локации
	local changed = 0
	for _, d in location:GetDescendants() do
		if d:IsA("BasePart") and not d.CanCollide and d.Parent and not skipped(d, location)
			and (noticeable(d, floorY) or inObsPost(d, location)) then
			d.CanCollide = true
			changed += 1
		elseif d:IsA("BasePart") and not d.CanCollide and d.Parent then
			for _, rule in RULES do
				if parentMatches(rule, d.Parent.Name) and rule.names[d.Name] then
					d.CanCollide = true
					changed += 1
					break
				end
			end
		end
	end
	if changed > 0 then
		print(("[Коллизия] стало твёрдыми деталей карты: %d"):format(changed))
	end
end

-- Всё, что висит на стенах выше роста (операторская, посты наблюдения, короба), закрыто
-- целиком невидимым блоком по габариту модели. Одних твёрдых деталей мало: снизу на обшивку
-- и подоконник запрыгивается, а в комнату ведёт любой зазор между стеклом, рамой и крышей
-- (скрин автора: стоял внутри кабины). Без имён: берётся каждая верхняя модель локации, низ
-- которой выше HIGH над полом, и посты НП (ObsPost_*), даже если это папки. Блок в группе
-- PlayerBarrier — держит только игрока; луч линии огня (Probe), трупы и камера его не видят.
local BLOCK_NAME = "PlayerBlock"
local HIGH = 6 -- низ модели выше этого над полом — она над головой, внутрь ей входить нечем

local function bounds(node)
	local lo, hi
	for _, d in node:GetDescendants() do
		if d:IsA("BasePart") and d.Name ~= BLOCK_NAME then
			local cf, size = d.CFrame, d.Size
			local half = Vector3.new(
				math.abs(cf.RightVector.X) * size.X + math.abs(cf.UpVector.X) * size.Y + math.abs(cf.LookVector.X) * size.Z,
				math.abs(cf.RightVector.Y) * size.X + math.abs(cf.UpVector.Y) * size.Y + math.abs(cf.LookVector.Y) * size.Z,
				math.abs(cf.RightVector.Z) * size.X + math.abs(cf.UpVector.Z) * size.Y + math.abs(cf.LookVector.Z) * size.Z
			) / 2
			lo = lo and lo:Min(d.Position - half) or d.Position - half
			hi = hi and hi:Max(d.Position + half) or d.Position + half
		end
	end
	return lo, hi
end

local function block(node, lo, hi)
	local old = node:FindFirstChild(BLOCK_NAME)
	if old then
		old:Destroy()
	end
	local part = Instance.new("Part")
	part.Name = BLOCK_NAME
	part.Anchored = true
	part.CanCollide = true
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = hi - lo
	part.CFrame = CFrame.new((lo + hi) / 2)
	part.CollisionGroup = Loose.Groups.Barrier
	part.Parent = node
end

-- Верхняя модель: модель, у которой между ней и локацией нет другой модели.
local function topModel(node, location)
	local p = node.Parent
	while p and p ~= location do
		if p:IsA("Model") then
			return false
		end
		p = p.Parent
	end
	return true
end

local function blockHigh(location, floorY)
	local count = 0
	for _, node in location:GetDescendants() do
		local obsPost = (node:IsA("Model") or node:IsA("Folder")) and node.Name:sub(1, 8) == "ObsPost_"
		local model = node:IsA("Model") and topModel(node, location)
		if (obsPost or model) and not skipped(node, location) and not SKIP[node.Name] then
			local lo, hi = bounds(node)
			if lo and (obsPost or lo.Y - floorY > HIGH) then
				block(node, lo, hi)
				count += 1
			end
		end
	end
	if count > 0 then
		print(("[Коллизия] закрыто блоками верхних объектов: %d"):format(count))
	end
end

local function applyAll()
	apply()
	local location = Arena.Location()
	if location then
		blockHigh(location, Arena.floorY or 0)
	end
end

applyAll()
Arena.OnChanged(applyAll)
