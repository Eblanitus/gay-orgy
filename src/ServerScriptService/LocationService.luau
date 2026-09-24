-- Смена локации забега (карта уровня, Levels[n].map).
--
-- Активная локация — содержимое Workspace.Location (имя — атрибут Map). Остальные лежат
-- папками в ServerStorage.Locations.<имя>. Смена — переезд деталей, а не копирование: у каждой
-- локации ровно одна копия, и правка в Studio не расходится с тем, что увидит игрок.
-- После переезда Arena.Rebind пересчитывает сетку, а подписчики Arena.OnChanged — свои ссылки.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local Arena = require(ReplicatedStorage:WaitForChild("Arena"))
local LevelSchema = require(ServerScriptService:WaitForChild("LevelSchema"))

local location = Arena.Location()
local parked = ServerStorage:FindFirstChild("Locations")
if not parked then
	parked = Instance.new("Folder")
	parked.Name = "Locations"
	parked.Parent = ServerStorage
end

local LocationService = {}

function LocationService.Current()
	return location:GetAttribute("Map")
end

function LocationService.Exists(map)
	return map == LocationService.Current() or parked:FindFirstChild(map) ~= nil
end

-- Возвращает true или false и текст ошибки. Зовётся на разобранной арене (см. WaveRunner.startRun).
function LocationService.Load(map)
	local current = LocationService.Current()
	if map == current then
		return true
	end

	local template = parked:FindFirstChild(map)
	local ok, reason = LevelSchema.CheckLocation(template)
	if not ok then
		return false, ("локация \"%s\": %s"):format(tostring(map), reason)
	end

	-- Текущая уезжает на склад под своим именем, новая — со склада в Workspace.Location.
	local outgoing = Instance.new("Folder")
	outgoing.Name = current
	for _, child in location:GetChildren() do
		child.Parent = outgoing
	end
	for _, child in template:GetChildren() do
		child.Parent = location
	end
	template:Destroy()
	outgoing.Parent = parked

	location:SetAttribute("Map", map)
	Arena.Rebind()
	-- После серверного пересчёта: к этому моменту атрибуты геометрии уже новые, и клиент
	-- пересчитается по ним.
	location:SetAttribute("Version", (location:GetAttribute("Version") or 0) + 1)
	print(("[Локация] %s -> %s"):format(tostring(current), map))
	return true
end

-- Проверка активной локации при старте: без неё ничего из арены не заработает.
do
	local ok, reason = LevelSchema.CheckLocation(location)
	if not ok then
		warn(("[Локация] активная \"%s\": %s"):format(tostring(LocationService.Current()), reason))
	end
end

return LocationService
