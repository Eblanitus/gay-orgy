-- Разовая правка места: мебель лаборатории твёрдая, у мешей турелей настоящая форма столкновения.
-- Запуск: Studio, Edit-режим, вставить в Command Bar целиком (или через MCP execute_luau),
-- потом сохранить место (Ctrl+S / Save to Roblox). Повторный запуск ничего не ломает.
--
-- Что правится (найдено аудитом коллизии, задача #380):
--   Lab/LabBench (6 тумб у стен)   — Cabinet, Top, Plinth были без коллизии: игрок проходил насквозь.
--   Lab/Workbench                  — Cabinet, Plinth без коллизии (столешница и ножки уже твёрдые).
--   CraftTable                     — ножки Leg1..Leg4 без коллизии (столешница твёрдая).
--   Шаблоны турелей в ServerStorage — CollisionFidelity = Hull у каждого MeshPart (#382).
--     Детали турелей твёрдые с #382 (TowerBuilder.solidify), но форму столкновения меша
--     движок считает только в Studio: без неё каждая деталь сталкивается своим ящиком.
-- Мелочь на полках и столах (колбы, пробирки, ручки, швы) остаётся без коллизии нарочно.
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local location = workspace:FindFirstChild("Location")
assert(location, "нет Workspace.Location")

local RULES = {
	{ parent = "LabBench", names = { Cabinet = true, Top = true, Plinth = true } },
	{ parent = "Workbench", names = { Cabinet = true, Plinth = true } },
	{ parent = "CraftTable", names = { Leg1 = true, Leg2 = true, Leg3 = true, Leg4 = true } },
}

local recording = ChangeHistoryService:TryBeginRecording("Коллизия мебели лаборатории")
local changed = 0
for _, d in location:GetDescendants() do
	if d:IsA("BasePart") and not d.CanCollide and d.Parent then
		for _, rule in RULES do
			if d.Parent.Name == rule.parent and rule.names[d.Name] then
				d.CanCollide = true
				changed += 1
				break
			end
		end
	end
end
local TEMPLATES = { "ColbaTurretTemplate", "DroneStationTemplate", "InjectorTurretTemplate", "CraftTableTemplate" }
local meshes = 0
for _, name in TEMPLATES do
	local template = game:GetService("ServerStorage"):FindFirstChild(name, true)
	if template then
		for _, d in template:GetDescendants() do
			if d:IsA("MeshPart") and d.CollisionFidelity ~= Enum.CollisionFidelity.Hull then
				d.CollisionFidelity = Enum.CollisionFidelity.Hull
				meshes += 1
			end
		end
	else
		warn("[Коллизия] нет шаблона " .. name)
	end
end
print(("[Коллизия] мешей турелей с формой Hull: %d"):format(meshes))

if recording then
	ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
end
print(("[Коллизия] стало твёрдыми деталей: %d (ожидается 6*3 + 2 + 4 = 24)"):format(changed))
