-- Модели хозяйственных построек экономики.
-- Биореактор (Завод Материи, по вики) — настоящая модель в BioreactorModel, дрон-носильщик —
-- квадрокоптер CarrierRig, движение его деталей — клиент BioreactorVisuals. Станция носильщиков пока
-- ВРЕМЕННАЯ ЗАГЛУШКА из примитивов; чтобы подключить настоящую, достаточно заменить функцию
-- ниже (сигнатура та же).
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
-- Договор для дрона-носильщика: Model с PrimaryPart "Root", пивот — центр корпуса
-- (Carriers ставит его на высоту Economy.carrierLift над полом). Атрибуты, которые ведёт Carriers:
--   State — "idle" | "out" (едет к трупу) | "wait" (ждёт напарников у туши) | "back" (везёт);
--   Loaded — везёт ли груз; Crew — сколько дронов тянет эту тушу вместе.
-- Деталь "Cargo" (если есть) Carriers показывает только с грузом.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Economy = require(ReplicatedStorage:WaitForChild("Economy"))
local CarrierRig = require(ServerScriptService:WaitForChild("CarrierRig"))

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

-- Биореактор: деталь корпуса одной строкой (те же правила, что у TowerModels.addPart).
local function reactorPart(model, name, size, cframe, color, material, shape)
	local p = Instance.new("Part")
	p.Name = name
	if shape then
		p.Shape = shape
	end
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material
	p.Anchored = true
	p.CanCollide = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = model
	return p
end

local buildBioreactor = require(ServerScriptService:WaitForChild("BioreactorModel"))({
	addPart = reactorPart,
	addRoot = rootOf,
})

-- Биореактор (Завод Материи): восьмиугольная платформа, приёмный конвейер, прижимной валец,
-- портал шредера, шнек, шламовый насос, экстракционная колонна (BioreactorModel).
function EconomyModels.Bioreactor(towerData)
	return buildBioreactor(towerData)
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

-- Дрон-носильщик: квадрокоптер с подвесным контейнером (CarrierRig). Ужат до CARRIER_SCALE: путь
-- Carriers ищет по занятости клеток без запаса на ширину тела — размах винтов около 1.4 студа,
-- как у прежнего ровера, не задевает постройки, мимо которых проходит центр.
local CARRIER_SCALE = 0.42

function EconomyModels.Carrier()
	local model = CarrierRig.Build(CARRIER_SCALE, Economy.carrierLift)
	model.Name = "Носильщик"
	return model
end

return EconomyModels
