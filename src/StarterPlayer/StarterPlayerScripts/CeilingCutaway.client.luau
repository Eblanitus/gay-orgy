-- Срез потолка: камера выше перекрытия — перекрытие не рисуется у этого игрока.
--
-- У лаборатории и коридора есть потолок (Location.Ceiling), а камера Classic отъезжает
-- до 128 studs и смотрит на поле сверху. С потолком сверху видно было бы одну крышу.
-- Поэтому, как только камера поднялась выше низа перекрытия, всё в его папке (плита и
-- светильники) прячется через LocalTransparencyModifier: только у себя, сервер и другие
-- игроки ничего не видят. Изнутри комнаты потолок на месте.
--
-- Каждая подпапка Ceiling — отдельное перекрытие со своей высотой (комната, коридор):
-- высота — низ детали Slab в этой подпапке, считать её руками не надо.
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local cachedFolder = nil
local groups = {} -- { { bottom = Y низа плиты, parts = { BasePart } } }
-- В плейсе включён StreamingEnabled: детали потолка могут приехать позже самой папки.
-- Любое добавление или уход внутри папки — список пересобирается на следующем кадре.
local dirty = false
local connections = {}

local function rebuild(folder)
	for _, group in groups do
		for _, part in group.parts do
			part.LocalTransparencyModifier = 0
		end
	end
	groups = {}
	cachedFolder = folder
	dirty = false
	for _, connection in connections do
		connection:Disconnect()
	end
	connections = {}
	if not folder then
		return
	end
	local function markDirty()
		dirty = true
	end
	table.insert(connections, folder.DescendantAdded:Connect(markDirty))
	table.insert(connections, folder.DescendantRemoving:Connect(markDirty))
	for _, sub in folder:GetChildren() do
		local slab = sub:FindFirstChild("Slab")
		if slab and slab:IsA("BasePart") then
			local parts = {}
			for _, d in sub:GetDescendants() do
				if d:IsA("BasePart") then
					table.insert(parts, d)
				end
			end
			table.insert(groups, { bottom = slab.Position.Y - slab.Size.Y / 2, parts = parts, hidden = false })
		end
	end
end

RunService.RenderStepped:Connect(function()
	local location = Workspace:FindFirstChild("Location")
	local folder = location and location:FindFirstChild("Ceiling")
	if folder ~= cachedFolder or dirty then
		rebuild(folder)
	end
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local y = camera.CFrame.Position.Y
	for _, group in groups do
		local hide = y > group.bottom
		if hide ~= group.hidden then
			group.hidden = hide
			for _, part in group.parts do
				part.LocalTransparencyModifier = hide and 1 or 0
			end
		end
	end
end)
