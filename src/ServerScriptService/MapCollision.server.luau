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

-- Общее правило поверх имён: любая заметная непрозрачная деталь локации на высоте тела
-- игрока твёрдая. Имена мебели в месте меняются (тумба у южной стены зала в одной версии
-- места — LabBench, в другой — иначе), и правило по именам её теряло: игрок заходил в тумбу
-- по пояс. Мелочь (колбы, слоты, решётки) отсекает объём, плитку пола — высота верха.
local BODY_BOTTOM = 0.7 -- верх детали выше этого над полом — в неё можно войти телом
local BODY_TOP = 6 -- низ детали ниже этого — она на высоте тела (рост персонажа ~5.5)
local MIN_VOLUME = 3 -- studs³: меньше — мелочь на столах, её не трогаем
local SKIP = { Ceiling = true, Markers = true } -- потолок прячет камера, маркеры — разметка

local function bodyHigh(part, floorY)
	local size = part.Size
	if size.X * size.Y * size.Z < MIN_VOLUME or part.Transparency >= 0.95 then
		return false
	end
	-- Полувысота ящика детали по вертикали с учётом поворота.
	local cf = part.CFrame
	local halfY = (math.abs(cf.RightVector.Y) * size.X + math.abs(cf.UpVector.Y) * size.Y
		+ math.abs(cf.LookVector.Y) * size.Z) / 2
	local y = part.Position.Y - floorY
	return y - halfY < BODY_TOP and y + halfY > BODY_BOTTOM
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
		if d:IsA("BasePart") and not d.CanCollide and d.Parent and not skipped(d, location) and bodyHigh(d, floorY) then
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

apply()
Arena.OnChanged(apply)
