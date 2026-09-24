-- Уборка ServerStorage от старых бэкапов и промежуточных импортов (задача #241).
-- Запуск: Studio → View → Command Bar, вставить весь файл, Enter. Потом Ctrl+S.
-- Отменить: Ctrl+Z сразу после запуска.
--
-- Удаляется только то, на что не ссылается ни код (проверено grep по src/), ни объекты места.
-- Не трогаются: шаблоны, которые читает код (ColbaTurretTemplate, InjectorTurretTemplate,
-- DroneStationTemplate, ArcadeCarTemplate, Locations), Models, сохранённые анимации
-- RBX_ANIMSAVES и та копия Scene_OLD_BROKEN_IMPORT, на которую они ссылаются.
-- EXPORT_SNAPSHOT и SFD_Import оставлены: по коду не видно, нужны ли они автору.
local ServerStorage = game:GetService("ServerStorage")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local DEAD = {
	"ColbaTurretTemplate_OLD_backup",
	"ElementProducerTemplate_OLD_backup",
	"NormalBeetleTemplate_BACKUP",
	"NormalBeetleTemplate_PREMESH",
	"NormalBeetleTemplate_PRE140",
	"NormalBeetleTemplate_PRESHL",
	"Injector_Import_1",
	"Injector_Import_2",
	"Injector_Import_3",
	"Injector_Import_4",
	"ElementProducer_Import_1",
	"ElementProducer_Import_2",
	"BeetleImport_RAW",
	"Scene_OLD_BROKEN_IMPORT",
}

-- Копия сцены, к которой привязаны сохранённые анимации, остаётся.
local keep = {}
local saves = ServerStorage:FindFirstChild("RBX_ANIMSAVES")
if saves then
	for _, item in saves:GetDescendants() do
		if item:IsA("ObjectValue") and item.Value then
			keep[item.Value] = true
		end
	end
end

local recording = ChangeHistoryService:TryBeginRecording("Уборка ServerStorage")
local removed, objects = 0, 0
for _, name in DEAD do
	for _, item in ServerStorage:GetChildren() do
		if item.Name == name and not keep[item] then
			objects += #item:GetDescendants() + 1
			removed += 1
			item:Destroy()
		end
	end
end
if recording then
	ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
end
print(("Уборка ServerStorage: удалено %d моделей, %d объектов. Сохраните место (Ctrl+S)."):format(removed, objects))
