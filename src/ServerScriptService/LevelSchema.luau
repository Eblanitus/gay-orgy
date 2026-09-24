-- Схема уровня и локации: что обязано быть в описании, чтобы в него можно было войти.
--
-- Уровень (alchemy_td_lobby.md: «номер, название, состав волн, карта») — строка ReplicatedStorage.Levels:
--   number — равен ключу в Levels
--   name   — строка
--   waves  — непустой массив { number = n, groups = { { enemyType, count, hp }, ... } }
--   map    — имя локации: активная Workspace.Location (атрибут Map) или папка
--            ServerStorage.Locations.<map>
--
-- Локация — папка с деталями (см. REQUIRED). Всё остальное в ней (грунт, фундамент) —
-- произвольное окружение, которое переезжает вместе с локацией.
--
-- Ошибка в описании не роняет сервер: уровень помечается невалидным и в него нельзя войти,
-- а в вывод уходит warn с тем, что именно не так.
local LevelSchema = {}

-- Обязательные части локации: путь внутри папки -> класс (IsA).
LevelSchema.REQUIRED = {
	{ path = { "ArenaFloor" }, class = "BasePart" }, -- пол: размер сетки и высота земли
	{ path = { "Walls" }, class = "Folder" }, -- стены (West*/East*/North/South — сторож сдвига пола)
	{ path = { "Markers", "Entrance" }, class = "BasePart" }, -- пролом, откуда идут жуки
	{ path = { "Markers", "Exit" }, class = "BasePart" }, -- выход
	{ path = { "Markers", "PlayerSpawn" }, class = "BasePart" }, -- куда ставится игрок на входе
	{ path = { "CraftTable" }, class = "Model" }, -- лабораторный стол
}

-- Возвращает true или false и текст ошибки.
function LevelSchema.CheckLocation(folder)
	if typeof(folder) ~= "Instance" then
		return false, "папка локации не найдена"
	end
	for _, item in LevelSchema.REQUIRED do
		local node = folder
		for _, name in item.path do
			node = node and node:FindFirstChild(name)
		end
		if not node or not node:IsA(item.class) then
			return false, ("нет %s (%s)"):format(table.concat(item.path, "."), item.class)
		end
	end
	return true
end

-- exists(map) -> есть ли такая локация (LocationService.Exists).
function LevelSchema.CheckLevel(key, level, exists)
	if type(level) ~= "table" then
		return false, "описание уровня — не таблица"
	end
	if level.number ~= key then
		return false, ("number = %s, а ключ в Levels = %s"):format(tostring(level.number), tostring(key))
	end
	if type(level.name) ~= "string" or level.name == "" then
		return false, "нет name (строка)"
	end
	if type(level.waves) ~= "table" or #level.waves == 0 then
		return false, "waves — не массив или пуст"
	end
	for i, wave in ipairs(level.waves) do
		if type(wave) ~= "table" or type(wave.number) ~= "number" or type(wave.groups) ~= "table" then
			return false, ("волна %d: нужны number и groups"):format(i)
		end
	end
	if type(level.map) ~= "string" then
		return false, "нет map (имя локации)"
	end
	if not exists(level.map) then
		return false, ("локации \"%s\" нет ни в Workspace.Location, ни в ServerStorage.Locations"):format(level.map)
	end
	return true
end

return LevelSchema
