-- Модели хозяйственных построек экономики — ВРЕМЕННЫЕ ЗАГЛУШКИ из примитивов.
-- Настоящие модели Биореактора, Станции носильщиков и дронов-носильщиков делаются отдельно;
-- чтобы их подключить, достаточно заменить функции ниже (сигнатуры те же).
--
-- Договор для постройки (как у Стены, TowerModels.buildWallModel): Model с PrimaryPart "Root"
-- в точке (0, 0, 0) модели; пивот ставится на TOWER_Y над полом, низ модели — на -1.6;
-- след на полу — не шире Towers[тип].footprint (по умолчанию Grid.BuildSize = 4 studs).
-- Логика смотрит только на атрибуты модели, которые ставит TowerBuilder/Carriers:
--   Type, HP, MaxHP, CellX, CellZ — как у любой постройки;
--   Processing (Биореактор) — сколько грузов сейчас перерабатывается (Bioreactor);
--   Carriers (Биореактор) — сколько всего носильщиков у реактора, Unreachable — сколько
--   трупов лежит без проезда (Carriers).
--
-- Договор для дрона-носильщика: Model с PrimaryPart "Root", пивот — центр корпуса на полу
-- (Carriers ставит его на высоту пола + DRONE_LIFT). Атрибуты, которые ведёт Carriers:
--   State — "idle" | "out" (едет к трупу) | "wait" (ждёт напарников у туши) | "back" (везёт);
--   Loaded — везёт ли груз; Crew — сколько дронов тянет эту тушу вместе.
-- Деталь "Cargo" (если есть) Carriers показывает только с грузом.
local EconomyModels = {}

local BASE_Y = -1.6 -- низ постройки в координатах модели (как у Стены и Колбы)

local function part(model, name, size, cframe, color, material, transparency)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Transparency = transparency or 0
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = model
	return p
end

local function rootOf(model)
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(0.2, 0.2, 0.2)
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.CFrame = CFrame.new()
	root.Parent = model
	model.PrimaryPart = root
	return root
end

-- Биореактор: стальной корпус, приёмный лоток спереди, зелёная колонна с материей.
function EconomyModels.Bioreactor(towerData)
	local model = Instance.new("Model")
	model.Name = towerData.name
	rootOf(model)
	local side = (towerData.footprint or 4) - 0.4
	local steel = Color3.fromRGB(88, 94, 102)
	local body = part(model, "Body", Vector3.new(side, 2.2, side), CFrame.new(0, BASE_Y + 1.1, 0), steel, Enum.Material.Metal)
	body.CanCollide = true
	part(model, "Hopper", Vector3.new(side * 0.8, 0.5, 1), CFrame.new(0, BASE_Y + 2.45, side / 2 - 0.5),
		Color3.fromRGB(60, 62, 66), Enum.Material.DiamondPlate)
	part(model, "Column", Vector3.new(1.4, 4.2, 1.4), CFrame.new(0, BASE_Y + 4.3, -0.4),
		Color3.fromRGB(90, 220, 120), Enum.Material.Neon, 0.25)
	part(model, "Cap", Vector3.new(1.8, 0.4, 1.8), CFrame.new(0, BASE_Y + 6.6, -0.4), steel, Enum.Material.Metal)
	return model
end

-- Станция носильщиков: низкий гараж с тремя док-площадками.
function EconomyModels.CarrierStation(towerData)
	local model = Instance.new("Model")
	model.Name = towerData.name
	rootOf(model)
	local side = (towerData.footprint or 4) - 0.4
	local body = part(model, "Body", Vector3.new(side, 1.4, side), CFrame.new(0, BASE_Y + 0.7, 0),
		Color3.fromRGB(96, 100, 92), Enum.Material.Metal)
	body.CanCollide = true
	for i = -1, 1 do
		part(model, "Dock" .. (i + 2), Vector3.new(side / 3 - 0.2, 0.1, side * 0.6),
			CFrame.new(i * side / 3, BASE_Y + 1.45, 0), Color3.fromRGB(230, 180, 60), Enum.Material.Neon)
	end
	return model
end

-- Дрон-носильщик: плоская «таблетка» робота-пылесоса и груз сверху.
function EconomyModels.Carrier()
	local model = Instance.new("Model")
	model.Name = "Носильщик"
	local root = rootOf(model)
	root.CFrame = CFrame.new()
	part(model, "Body", Vector3.new(1.4, 0.5, 1.4), CFrame.new(0, 0, 0), Color3.fromRGB(70, 74, 80), Enum.Material.Metal)
	part(model, "Lamp", Vector3.new(0.3, 0.15, 0.3), CFrame.new(0, 0.32, 0.45), Color3.fromRGB(90, 220, 120), Enum.Material.Neon)
	local cargo = part(model, "Cargo", Vector3.new(1.1, 0.6, 1.1), CFrame.new(0, 0.55, 0), Color3.fromRGB(110, 96, 70),
		Enum.Material.Slate, 1)
	cargo.CanQuery = false
	for _, item in model:GetDescendants() do
		if item:IsA("BasePart") then
			item.CanQuery = false
		end
	end
	return model
end

return EconomyModels
