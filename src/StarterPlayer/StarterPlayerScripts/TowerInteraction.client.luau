-- Клиент только просит: ловит срабатывание ProximityPrompt, следит за клеткой под курсором
-- и шлёт запросы на сервер. Никакой проверки материи/занятости здесь нет — всё решает
-- BuildInteraction на сервере; подсветка клетки — чисто картинка.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ProximityPromptService = game:GetService("ProximityPromptService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

-- Мобильная адаптация: панель стройки, тап по арене, крупные кнопки. На ПК ничего не меняется.
local MobileUI = require(script.Parent:WaitForChild('MobileUI'))
local Theme = require(script.Parent:WaitForChild("UITheme"))

local Arena = require(ReplicatedStorage:WaitForChild("Arena"))
local Elements = require(ReplicatedStorage:WaitForChild("Elements"))
local Towers = require(ReplicatedStorage:WaitForChild("Towers"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RequestBuildTower = Remotes:WaitForChild("RequestBuildTower")
local RequestPourElement = Remotes:WaitForChild("RequestPourElement")
local InventoryChanged = Remotes:WaitForChild("InventoryChanged")
local Notify = Remotes:WaitForChild("Notify")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Список элементов для заливки — всё, что есть в инвентаре (счётчик > 0), а не только
-- 4 базовых: ТЗ v3 прямо требует заливать скрафченные элементы («скрести до Лавы, залей
-- в башню», v3_craft_draft.md). Тот же подход, что в CraftingUI.refreshInventoryList — список
-- пересобирается целиком на каждый InventoryChanged. Список скроллится независимо
-- от заголовка и кнопки отмены — раньше все три были соседями под одним UIListLayout,
-- что не работает при переменном числе элементов (от 0 до 40).
local pickerGui = Instance.new("ScreenGui")
pickerGui.Name = "ElementPicker"
pickerGui.ResetOnSpawn = false
pickerGui.DisplayOrder = MobileUI.Layer.Window
pickerGui.Enabled = false
pickerGui.Parent = playerGui

local pickerFrame = Instance.new("Frame")
-- Ширина долей экрана, центрирование через AnchorPoint: посчитанный один раз отступ
-- -pickerWidth/2 после поворота телефона описывал уже другой экран, и окно уезжало из центра.
-- Высота — по числу строк списка (applyPickerHeight ниже), а не долей экрана.
local PICK_ROW_H = MobileUI.isMobile and 56 or 30
local PICK_ROW_GAP = 4
local PICK_CLOSE = MobileUI.isMobile and 44 or 28 -- крестик, как у окон Лаборатории и инвентаря
local PICK_TITLE_H = PICK_CLOSE + 18
local PICK_FOOTER_H = 12

pickerFrame.AnchorPoint = Vector2.new(0.5, 0.5)
pickerFrame.Size = MobileUI.isMobile and UDim2.new(0.7, 0, 0, 200) or UDim2.new(0, 260, 0, 200)
pickerFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
pickerFrame.Parent = pickerGui

local pickerRows = 0

local function applyPickerHeight()
	local content = pickerRows > 0 and (pickerRows * PICK_ROW_H + (pickerRows - 1) * PICK_ROW_GAP) or 60
	-- Потолок — от рабочей высоты ScreenGui, а не от вьюпорта: сверху экран съедает
	-- полоса Roblox (на телефоне 58px), и окно от вьюпорта вылезало за верхний край.
	local usable = pickerGui.AbsoluteSize.Y
	if usable <= 100 then
		usable = MobileUI.viewportY -- до первой отрисовки AbsoluteSize ещё нулевой
	end
	local maxH = math.floor(usable * 0.9)
	pickerFrame.Size = UDim2.new(
		pickerFrame.Size.X.Scale,
		pickerFrame.Size.X.Offset,
		0,
		math.min(PICK_TITLE_H + content + PICK_FOOTER_H, maxH)
	)
end

MobileUI.OnViewportChanged(applyPickerHeight)
pickerGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(applyPickerHeight)

-- Выбор заливки — карточка поверх арены и поверх окон, поэтому решётка на ней
-- плотнее и быстрее, чем у Лаборатории (см. Theme.scene.build).
Theme.Panel(pickerFrame, { scene = "build" })

local title = Instance.new("TextLabel")
-- Поля по бокам под ширину крестика: заголовок остаётся по центру окна и не заходит под него.
title.Size = UDim2.new(1, -2 * (PICK_CLOSE + 12), 0, PICK_CLOSE)
title.Position = UDim2.new(0, PICK_CLOSE + 12, 0, 8)
title.BackgroundTransparency = 1
title.TextSize = 18
title.Text = "Выберите элемент"
title.Parent = pickerFrame

-- Заголовок здесь по центру, поэтому вертикальной засечки слева сборщик не рисует —
-- она привязана к левому краю текста, а у центрированного его нет.
Theme.Title(title)

local elementList = Instance.new("ScrollingFrame")
elementList.Size = UDim2.new(1, -24, 1, -(PICK_TITLE_H + PICK_FOOTER_H))
elementList.Position = UDim2.new(0, 12, 0, PICK_TITLE_H)
elementList.BackgroundTransparency = 1
elementList.BorderSizePixel = 0
elementList.ScrollBarThickness = 6
elementList.AutomaticCanvasSize = Enum.AutomaticSize.Y
elementList.CanvasSize = UDim2.new(0, 0, 0, 0)
elementList.Parent = pickerFrame

Theme.Scroller(elementList)
Theme.DragScroll(elementList)

local currentTower = nil

local function closePicker()
	pickerGui.Enabled = false
	currentTower = nil
end

local inventory = {} -- elementKey -> count, приходит целиком по InventoryChanged (см. CraftingUI)

local function refreshElementList()
	elementList:ClearAllChildren()
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, PICK_ROW_GAP)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = elementList

	local keys = {}
	for key, count in inventory do
		if count > 0 then
			table.insert(keys, key)
		end
	end
	table.sort(keys, function(a, b)
		local tierA, tierB = Elements[a].tier or 0, Elements[b].tier or 0
		if tierA ~= tierB then
			return tierA < tierB
		end
		return Elements[a].name < Elements[b].name
	end)

	if #keys == 0 then
		local emptyLabel = Instance.new("TextLabel")
		emptyLabel.Size = UDim2.new(1, 0, 0, 60)
		emptyLabel.BackgroundTransparency = 1
		emptyLabel.FontFace = Theme.font.body
		emptyLabel.TextSize = 14
		emptyLabel.TextWrapped = true
		emptyLabel.TextColor3 = Theme.color.textMute
		emptyLabel.Text = "Элементов нет — купите или скрестите"
		emptyLabel.Parent = elementList
		pickerRows = 0
		applyPickerHeight()
		return
	end

	for i, key in keys do
		local data = Elements[key]

		local button = Instance.new("TextButton")
		button.Size = UDim2.new(1, -8, 0, PICK_ROW_H)
		button.LayoutOrder = i
		button.FontFace = Theme.font.strong
		button.TextSize = 14
		-- Номер, имя и счётчик разным кеглем — та же анатомия строки, что в списке
		-- инвентаря Лаборатории.
		button.RichText = true
		button.TextXAlignment = Enum.TextXAlignment.Left
		button.Text = ("%s   %s"):format(
			Theme.Caps(data.name),
			Theme.Readout("шт", inventory[key], Theme.Legible(data.color), 10)
		)
		button.Parent = elementList

		-- Ячейка в цвете элемента: тёмный корпус, кант и засечка — как в списке
		-- инвентаря и слотах крафта.
		Theme.ElementButton(button, data.color, { wide = true, element = key })

		button.MouseButton1Click:Connect(function()
			-- Список тянули, а не выбирали: заливка элемента необратима.
			if Theme.WasDragged(elementList) then
				return
			end
			if currentTower then
				RequestPourElement:FireServer(currentTower, key)
			end
			closePicker()
		end)
	end

	pickerRows = #keys
	applyPickerHeight()
end

-- Отмена — крестиком справа вверху, как у всех окон игры: выход из любого окна
-- стоит в одном и том же углу.
local closeButton = Instance.new("TextButton")
closeButton.AnchorPoint = Vector2.new(1, 0)
closeButton.Size = UDim2.new(0, PICK_CLOSE, 0, PICK_CLOSE)
closeButton.Position = UDim2.new(1, -10, 0, 8)
closeButton.Parent = pickerFrame

Theme.CloseButton(closeButton)

closeButton.MouseButton1Click:Connect(closePicker)

local function openPicker(tower)
	currentTower = tower
	pickerGui.Enabled = true
	elementList.CanvasPosition = Vector2.new(0, 0)
	Theme.Open(pickerFrame)
end

ProximityPromptService.PromptTriggered:Connect(function(prompt)
	if prompt.Name == "PourPrompt" then
		openPicker(prompt.Parent)
	end
end)

InventoryChanged.OnClientEvent:Connect(function(counts)
	inventory = counts
	refreshElementList()
end)

refreshElementList()

-- Короткое сообщение от сервера (например, не хватает материи)
local notifyGui = Instance.new("ScreenGui")
notifyGui.Name = "Notify"
notifyGui.ResetOnSpawn = false
notifyGui.DisplayOrder = MobileUI.Layer.Notify
notifyGui.Parent = playerGui

-- Экранные кнопки (панель стройки и подсказка режима) вынесены из notifyGui в свой слой:
-- сообщение сервера («не хватает материи» при покупке) должно быть видно поверх открытого
-- окна Лаборатории, а панель стройки — наоборот, прятаться под ним. В одном ScreenGui
-- эти два правила не уживаются — DisplayOrder общий на весь ScreenGui.
local controlsGui = Instance.new("ScreenGui")
controlsGui.Name = "BuildControls"
controlsGui.ResetOnSpawn = false
controlsGui.DisplayOrder = MobileUI.Layer.Controls
controlsGui.Parent = playerGui

local notifyLabel = Instance.new("TextLabel")
-- На телефоне сообщение уехало в единственный прямоугольник, свободный и в лобби, и в забеге:
-- справа от верхней панели, ниже кнопки инвентаря, выше подсказки стройки.
-- На прежних 0.72 высоты оно ложилось ровно на нижний ряд управления (замерено на
-- 750x322: 37,231..712,267 — перекрывало кнопку волны на 214x13 и панель стройки
-- на 254x21), а слой Notify выше обоих — текст печатался поверх кнопок. Доля 0.3 по
-- ширине подобрана так, чтобы не доставать до панели лобби (та — 0.62 слева)
-- ни на одной ширине вьюпорта.
notifyLabel.AnchorPoint = MobileUI.isMobile and Vector2.new(1, 0) or Vector2.new(0.5, 0)
notifyLabel.Size = MobileUI.isMobile and UDim2.new(0.3, 0, 0, 60) or UDim2.new(0.9, 0, 0, 36)
notifyLabel.Position = MobileUI.isMobile and UDim2.new(1, -12, 0, 74) or UDim2.new(0.5, 0, 0.72, 0)
notifyLabel.TextWrapped = true
notifyLabel.FontFace = Theme.font.strong
notifyLabel.TextSize = MobileUI.isMobile and 17 or 20
notifyLabel.TextColor3 = Theme.color.danger
notifyLabel.TextStrokeTransparency = 1
notifyLabel.TextTransparency = 1
notifyLabel.Parent = notifyGui

-- Сообщение собрано той же ячейкой, что и строки списков: тёмный красный корпус,
-- кант и засечка слева — в референсе автора строка журнала выглядит ровно так же,
-- как строка списка. Прозрачность начальная — полная: до первого сообщения никакой
-- плашки на экране быть не должно.
-- Собрано вручную, а не Theme.ElementFill: сообщение гаснет прозрачностью, а у ячейки
-- кант и засечка — отдельные объекты со своей прозрачностью: они остались бы висеть
-- на экране красной рамкой и до первого сообщения, и после его угасания. Кантом
-- при этом ведает своя переменная — её гасит тот же Tween, что и текст.
notifyLabel.BackgroundColor3 = Theme.Shadowed(Theme.color.danger, 0.9)
notifyLabel.BackgroundTransparency = 1
Theme.Corner(notifyLabel, Theme.radius.mark)
local notifyEdge = Theme.Stroke(notifyLabel, Theme.Shadowed(Theme.color.danger, 0.35), 1, 1)

local notifyPad = Instance.new("UIPadding")
notifyPad.PaddingLeft = UDim.new(0, 10)
notifyPad.PaddingRight = UDim.new(0, 10)
notifyPad.Parent = notifyLabel

Notify.OnClientEvent:Connect(function(message)
	notifyLabel.Text = tostring(message)
	notifyLabel.TextTransparency = 0
	-- Гаснет вместе с текстом и плашка: иначе тёмный прямоугольник остался бы висеть
	-- на экране навсегда после первого же сообщения.
	notifyLabel.BackgroundTransparency = 0
	notifyEdge.Transparency = 0
	local fade = TweenInfo.new(2.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 1.5)
	TweenService:Create(notifyLabel, fade, { TextTransparency = 1, BackgroundTransparency = 1 }):Play()
	TweenService:Create(notifyEdge, fade, { Transparency = 1 }):Play()
end)

-- Режим стройки (ТЗ v2.1). Площадок больше нет, строить можно в любую свободную клетку, поэтому
-- постройка идёт кликом по арене. Режим включается отдельно (B): иначе любой случайный клик
-- по полу молча тратил бы материю. Подсветка показывает ровно ту клетку, которая уйдёт на сервер.
local arenaFloor = Arena.Location():WaitForChild("ArenaFloor")
-- Уже стоящие постройки: по ним рамка понимает, что место занято (isOccupied ниже).
local towersFolder = Workspace:WaitForChild("Towers")
local camera = Workspace.CurrentCamera

-- Запретные клетки (пролом и выход, см. Grid.IsEntranceCell/IsExitCell на сервере) считаются тем
-- же переводом Arena.ToCell по тем же позициям входа/выхода активной локации (Arena.entrance/exit) —
-- отдельного remote’а не нужно. Пересчитываются при смене локации (Arena.OnChanged ниже).
local entranceX, entranceZ = Arena.ToCell(Arena.entrance)
local exitX, exitZ = Arena.ToCell(Arena.exit)
-- Клетка стола — см. Grid.IsTableCell: стол больше не стоит на выходе и запрещён отдельно.
local tableX, tableZ = Arena.ToCell(Arena.table)
local FORBIDDEN_COLOR = Color3.fromRGB(220, 70, 70)
-- Прозрачность колец дальности/слепой зоны при стройке (rangeIndicator/minRangeIndicator ниже). Было 0.8 —
-- при ForceField это почти невидимый налёт, особенно рядом с ярким полом арены.
local RING_TRANSPARENCY = 0.5

-- Цвет текущего выбора (турель/стена), обновляется в refreshBuildChoice. Объявлен здесь явно,
-- чтобы и refreshBuildChoice, и RenderStepped ниже ссылались на одну и ту же переменную,
-- а не на неявную глобальную.
local buildColor = Color3.fromRGB(90, 200, 90)
-- Радиус текущего выбора в студах, тоже обновляется в refreshBuildChoice. nil у Стены —
-- по нему RenderStepped решает, показывать ли rangeIndicator.
local buildRange = nil
-- Радиус слепой зоны текущего выбора (Мортира), тоже из refreshBuildChoice. nil у всех,
-- у кого своего minRange нет — по нему RenderStepped решает, показывать ли minRangeIndicator.
local buildMinRange = nil
-- Радиус следа выбранной постройки в клетках, обновляется в refreshBuildChoice.
-- Раньше везде брался общий Arena.reach — тот самый след 4 студа, из-за которого
-- рамка Колбы (10.2) пускала вторую Колбу внутрь первой.
local buildReach = Arena.reach
-- Половина сектора обстрела в радианах (Towers[тип].arc, Инжектор), тоже из
-- refreshBuildChoice. nil у всех, кто бьёт кругом — по нему RenderStepped решает,
-- рисовать ли круг дальности или сектор.
local buildArc = nil

local HEX_THICKNESS = 0.2

-- Куски подсветки все зовутся Slice, и по имени же их сносит пересборка: у трапеции
-- Станции FPV-дронов средний кусок — обычная деталь, а не WedgePart, и проверка
-- по классу оставила бы его лежать на поле после смены постройки.
local function clearSlices(model)
	for _, child in model:GetChildren() do
		if child.Name == "Slice" then
			child:Destroy()
		end
	end
end

local function rebuildHexWedges(model, diameter, thickness)
	clearSlices(model)

	-- Клинья считаются в системе координат хекса (центр = локальный ноль), а не в мировой:
	-- при пересборке (смена постройки во время наведения) Root уже стоит не в (0,0,0),
	-- и без этого умножения свежие клинья ставились мировыми координатами вокруг настоящего
	-- нуля мира — далеко от текущей клетки, плавающими обломками (задача с плавающими
	-- треугольниками при стройке).
	local rootCFrame = model.PrimaryPart.CFrame

	local apothem = diameter / math.sqrt(2 * math.sqrt(3))
	local halfEdge = apothem / math.sqrt(3)

	-- WedgePart таперится не так, как кажется: полная грань — при Size.Z (ось высоты), ножовой край
	-- (нулевая высота) — при -Size.Z, и он лежит не по середине высоты (Y=0), а по низу
	-- (Y=-Size.Y/2) — проверено Raycast'ом по тестовому WedgePart в Workspace. Старая версия считала
	-- Y осью тапера (thickness/apothem по X/Y) и путала знак у тангенциального смещения — 12 клиньев
	-- вместо шестигранника давали ветряк-воронку с дырами между лепестками.
	--
	-- Верная геометрия: локальная X — вертикаль (толщина, ось экструзии, без тапера), локальная
	-- Z — радиально наружу (Size.Z=apothem: полная грань у края клетки, нож в центре), локальная
	-- Y — тангенциально (Size.Y=halfEdge: от середины ребра до её угла). Правая тройка каждого
	-- клина — центр, середина ребра и его угол; два клина на ребро (sign) вместе дают целый
	-- треугольник от центра до ребра, а шесть таких треугольников — весь шестигранник без дыр.
	--
	-- localX умножается на sign, а не всегда (0,1,0): без этого базис (localX, localY, localZ) у клина
	-- с sign=-1 получается леворуким (отражённым) вместо праворукого, и CFrame.fromMatrix строит часть
	-- клиньев зеркально; толщина симметрична по X, поэтому смена знака на форму никак не влияет.
	for i = 0, 5 do
		local edgeAngle = math.rad(60 * i)
		local radialDir = Vector3.new(math.cos(edgeAngle), 0, math.sin(edgeAngle))
		local tangentDir = Vector3.new(-math.sin(edgeAngle), 0, math.cos(edgeAngle))
		local edgeMid = radialDir * apothem

		for _, sign in { 1, -1 } do
			local localX = Vector3.new(0, sign, 0)
			local localY = tangentDir * sign
			local localZ = radialDir

			local pos = edgeMid - radialDir * (apothem / 2) + tangentDir * sign * (halfEdge / 2)
			local cframe = CFrame.fromMatrix(pos, localX, localY, localZ)

			local wedge = Instance.new("WedgePart")
			wedge.Name = "Slice"
			wedge.Size = Vector3.new(thickness, halfEdge, apothem)
			wedge.CFrame = rootCFrame * cframe
			wedge.Anchored = true
			wedge.CanCollide = false
			wedge.CanQuery = false
			wedge.Material = Enum.Material.Neon
			wedge.Color = Color3.fromRGB(90, 200, 90)
			wedge.Transparency = 1
			wedge.Parent = model
		end
	end
end

-- Трапеция вместо шестигранника (Станция FPV-дронов, Towers.footprintShape). Платформа
-- станции у -Z уже, чем у +Z, и подсветка обязана повторять её, а не показывать чужую фигуру:
-- зелёное пятно — это обещание того, что встанет на пол.
--
-- Собирается тремя кусками: плита шириной с узкую сторону на всю глубину и две косынки
-- по бокам, добирающие ширину до широкой стороны. Грабли WedgePart те же, что расписаны
-- у шестигранника выше: тапер идёт вдоль локальной Z (полная грань у +Z, нож у -Z), а основание
-- лежит по -Y, поэтому базис задаётся вручную через CFrame.fromMatrix, а не поворотами:
-- у левой косынки локальный X смотрит вверх, у правой вниз — иначе тройка получается леворукой
-- и косынка строится зеркально (толщина симметрична, на форму смена знака не влияет).
local function rebuildTrapezoidSlices(model, shape, thickness)
	clearSlices(model)

	local rootCFrame = model.PrimaryPart.CFrame
	local near, far, depth = shape.near, shape.far, shape.depth

	-- offset — сдвиг плиты по Z относительно пивота постройки. У Станции его нет
	-- (платформа симметрична относительно оси), а у Инжектора ось поворота стоит
	-- не в центре станины: без сдвига зелёное пятно уехало бы от его плиты.
	local offset = shape.offset or 0

	local slab = Instance.new("Part")
	slab.Name = "Slice"
	slab.Size = Vector3.new(near, thickness, depth)
	slab.CFrame = rootCFrame * CFrame.new(0, 0, offset)
	slab.Anchored = true
	slab.CanCollide = false
	slab.CanQuery = false
	slab.Material = Enum.Material.Neon
	slab.Color = Color3.fromRGB(90, 200, 90)
	slab.Transparency = 1
	slab.Parent = model

	local growth = (far - near) / 2 -- насколько каждый бок расширяется к +Z
	if growth <= 0 then
		return -- ровные стороны: трапеции нет, плиты выше достаточно
	end

	for _, side in { 1, -1 } do
		local wedge = Instance.new("WedgePart")
		wedge.Name = "Slice"
		wedge.Size = Vector3.new(thickness, growth, depth)
		wedge.CFrame = rootCFrame * CFrame.fromMatrix(
			Vector3.new(side * (near + far) / 4, 0, offset),
			Vector3.new(0, -side, 0),
			Vector3.new(side, 0, 0)
		)
		wedge.Anchored = true
		wedge.CanCollide = false
		wedge.CanQuery = false
		wedge.Material = Enum.Material.Neon
		wedge.Color = Color3.fromRGB(90, 200, 90)
		wedge.Transparency = 1
		wedge.Parent = model
	end
end

-- Сектор обстрела вместо полного круга дальности (Towers[тип].arc, Инжектор).
-- Турель с сектором физически не выбирает цель вне него (см. Targeting на сервере),
-- и сплошной круг обещал бы игроку не то поле боя, которое она накрывает.
--
-- Собирается тем же способом, что и шестигранник выше: дуга режется на равные
-- сегменты, каждый сегмент — треугольник от центра до хорды, а треугольник складывается
-- из двух прямоугольных клиньев по обе стороны от середины хорды. Грабли WedgePart
-- те же, что расписаны у шестигранника: локальная X — толщина, Z — радиально наружу,
-- Y — тангенциально, и localX умножается на sign, иначе тройка у одной из половин
-- получается леворукой и клин строится зеркально.
--
-- Сектор симметричен относительно -Z модели — фронта будущей постройки, того же
-- нуля, от которого считает сектор сервер (Aiming.AngleTo). Крутит его вместе с рамкой
-- тот же PivotTo в RenderStepped, что и подсветку платформы.
local ARC_SEGMENTS = 16 -- на 90° это сегмент в 5.6°: кромка читается дугой, а не многоугольником

local function rebuildArcSlices(model, radius, arcRad, thickness)
	clearSlices(model)

	local rootCFrame = model.PrimaryPart.CFrame
	local step = arcRad / ARC_SEGMENTS
	local apothem = radius * math.cos(step / 2)
	local halfChord = radius * math.sin(step / 2)

	for i = 0, ARC_SEGMENTS - 1 do
		local mid = -arcRad / 2 + (i + 0.5) * step
		local radialDir = Vector3.new(-math.sin(mid), 0, -math.cos(mid))
		local tangentDir = Vector3.new(-math.cos(mid), 0, math.sin(mid))
		local edgeMid = radialDir * apothem

		for _, sign in { 1, -1 } do
			local pos = edgeMid - radialDir * (apothem / 2) + tangentDir * sign * (halfChord / 2)
			local wedge = Instance.new("WedgePart")
			wedge.Name = "Slice"
			wedge.Size = Vector3.new(thickness, halfChord, apothem)
			wedge.CFrame = rootCFrame * CFrame.fromMatrix(pos, Vector3.new(0, sign, 0), tangentDir * sign, radialDir)
			wedge.Anchored = true
			wedge.CanCollide = false
			wedge.CanQuery = false
			-- ForceField, а не Neon: это зона дальности, и выглядеть она должна как круг,
			-- который она заменяет, а не как вторая рамка постройки.
			wedge.Material = Enum.Material.ForceField
			wedge.Color = Color3.fromRGB(90, 200, 90)
			wedge.Transparency = 1
			wedge.Parent = model
		end
	end
end

local function buildHexHighlight(name, diameter, thickness)
	local model = Instance.new("Model")
	model.Name = name

	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(0.2, 0.2, 0.2)
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.Transparency = 1
	root.CFrame = CFrame.new(0, 0, 0)
	root.Parent = model
	model.PrimaryPart = root

	rebuildHexWedges(model, diameter, thickness)

	return model
end

-- Квадратная подсветка (Стена — мешки песка): её след квадратный, как и у всего остальных
-- построек (занятость клеток всегда по footprint, см. Arena.ReachFor), а шестигранник повторяет только
-- круглые платформы турелей (Колба, Инжектор и прочие). Стене нужен отдельный вид зоны:
-- один плоский квадрат, без клиньев и без тапера — чтобы зелёное пятно честно повторяло
-- квадратную платформу мешков, а не обещало круглую площадку, которой у неё нет.
local function rebuildSquareSlice(model, size, thickness)
	clearSlices(model)

	local slab = Instance.new("Part")
	slab.Name = "Slice"
	slab.Size = Vector3.new(size, thickness, size)
	slab.CFrame = model.PrimaryPart.CFrame
	slab.Anchored = true
	slab.CanCollide = false
	slab.CanQuery = false
	slab.Material = Enum.Material.Neon
	slab.Color = Color3.fromRGB(90, 200, 90)
	slab.Transparency = 1
	slab.Parent = model
end

local function setHighlightAppearance(model, color, transparency)
	for _, part in model:GetChildren() do
		if part.Name == "Slice" then
			part.Color = color
			part.Transparency = transparency
		end
	end
end

local cellHighlight = buildHexHighlight("BuildCell", Arena.buildSize, HEX_THICKNESS)
-- Текущая форма зоны подсветки строкой — чтобы refreshBuildChoice перестраивала её только
-- при реальной смене формы или размера, а не на каждом вызове. Раньше хватало одного
-- диаметра: форма у всех построек была одна и та же.
local currentHighlightKey = ("hex:%.2f"):format(Arena.buildSize)
cellHighlight.Name = "BuildCell"
-- Рамка размером с ПОСТРОЙКУ, а не с клетку: клетка теперь впятеро мельче того,
-- что встанет на поле, и подсветка по CellSize показывала бы не то место, которое займёт
-- постройка. Двигается рамка при этом шагом клетки — в этом вся разница для игрока:
-- тот же блок, но ставится впятеро точнее.
local highlightColor = Color3.fromRGB(90, 200, 90)
cellHighlight.Parent = Workspace

-- Сектор обстрела — своя модель, а не куски в cellHighlight: у рамки свой размер
-- (платформа) и своя высота над полом, а сектор рисуется радиусом стрельбы.
-- Пустая, пока не выбрана турель с сектором.
local arcIndicator = Instance.new("Model")
arcIndicator.Name = "BuildArc"
local arcRoot = Instance.new("Part")
arcRoot.Name = "Root"
arcRoot.Size = Vector3.new(0.2, 0.2, 0.2)
arcRoot.Anchored = true
arcRoot.CanCollide = false
arcRoot.CanQuery = false
arcRoot.Transparency = 1
arcRoot.CFrame = CFrame.new(0, 0, 0)
arcRoot.Parent = arcIndicator
arcIndicator.PrimaryPart = arcRoot
arcIndicator.Parent = Workspace
-- Текущая фигура сектора строкой — по той же причине, что и currentHighlightKey выше:
-- пересобирать тридцать два клина на каждый вызов refreshBuildChoice ни к чему.
local currentArcKey = nil

-- Круг радиуса стрельбы — только у турелей (у Стены нет range). Показывается вместе
-- с cellHighlight и гаснет по тем же правилам: вышли из режима стройки, увели курсор
-- с пола или выбрали постройку без range. Форма — сплющенный цилиндр (диск): у Cylinder
-- ось по умолчанию идёт вдоль X, поворот на 90° вокруг Z укладывает его плашмя, как шайбу.
local rangeIndicator = Instance.new("Part")
rangeIndicator.Name = "BuildRange"
rangeIndicator.Shape = Enum.PartType.Cylinder
rangeIndicator.Size = Vector3.new(0.05, 1, 1)
rangeIndicator.Anchored = true
rangeIndicator.CanCollide = false
rangeIndicator.CanQuery = false
rangeIndicator.Material = Enum.Material.ForceField
rangeIndicator.Color = Color3.fromRGB(90, 200, 90)
rangeIndicator.Transparency = 1
rangeIndicator.Parent = Workspace

-- Второй диск для слепой зоны (minRange, задача #56) — например, у Мортиры: рисуется
-- поверх rangeIndicator своим цветом, чтобы игрок видел не просто круг дальности,
-- а кольцо с дырой там, куда снаряд физически не долетает. У построек без minRange
-- просто остаётся погашенным.
local minRangeIndicator = Instance.new("Part")
minRangeIndicator.Name = "BuildMinRange"
minRangeIndicator.Shape = Enum.PartType.Cylinder
minRangeIndicator.Size = Vector3.new(0.05, 1, 1)
minRangeIndicator.Anchored = true
minRangeIndicator.CanCollide = false
minRangeIndicator.CanQuery = false
minRangeIndicator.Material = Enum.Material.ForceField
minRangeIndicator.Color = Color3.fromRGB(220, 70, 70)
minRangeIndicator.Transparency = 1
minRangeIndicator.Parent = Workspace

local buildHint = Instance.new("TextLabel")
-- На мобильном подсказка уезжает под HUD: тот занимает левый верхний угол (220x110
-- от точки 20,20), и на узком экране центрированная строка накрывала бы его.
-- Прижата к правому краю, а не по центру: кнопка промокода под HUD стала шире и выше
-- (MIN_TAP), и центрированная строка на той же высоте начала бы на неё налезать.
buildHint.AnchorPoint = MobileUI.isMobile and Vector2.new(1, 0) or Vector2.new(0.5, 0)
buildHint.Size = MobileUI.isMobile and UDim2.new(0.62, 0, 0, 26) or UDim2.new(0, 0, 0, 28)
buildHint.Position = MobileUI.isMobile and UDim2.new(1, -12, 0, 138) or UDim2.new(0.5, 0, 0, 12)
buildHint.FontFace = Theme.font.strong
buildHint.TextSize = 17
buildHint.RichText = true
buildHint.TextTruncate = Enum.TextTruncate.AtEnd
buildHint.Visible = false
buildHint.Parent = controlsGui

-- Подсказка лежит на тёмной плашке, а не висит голой надписью с обводкой поверх арены:
-- её читаемость не зависит от того, что под ней на поле.
--
-- Это строка состояния терминала, а не ячейка элемента. До задачи #129 она собиралась
-- Theme.ElementFill цветом интерфейса — бирюзовая дымка во всю строку и бирюзовый текст
-- на ней, — а отступ, поставленный ПОСЛЕ сборщика, сдвигал дымку и засечку внутрь
-- (замерено: строка 659,12 шириной 596, засечка и дымка — от 669 шириной 576). По краям
-- плашки оставались тёмные зазоры в десять пикселей, засечка висела поверх слова
-- «СТРОЙКА». Теперь это тёмная плашка с кантом и засечкой у самого левого края
-- (Theme.Swatch сам выходит за отступ, см. Theme.Bleed); текст приглушённый, а цветом
-- выделены раздел и выбранная постройка — их красит сама строка (refreshBuildChoice).
buildHint.BackgroundColor3 = Theme.color.panel
buildHint.BackgroundTransparency = 0.06
buildHint.BorderSizePixel = 0
buildHint.TextStrokeTransparency = 1
buildHint.TextColor3 = Theme.color.textDim
buildHint.ClipsDescendants = true
Theme.Corner(buildHint, Theme.radius.control)
Theme.Stroke(buildHint, Theme.color.accentDim, 1, 0)
Theme.Swatch(buildHint, Theme.color.accent)

local buildHintPad = Instance.new("UIPadding")
-- Слева ещё и ширина засечки: текст на неё не налезает.
buildHintPad.PaddingLeft = UDim.new(0, 10 + Theme.EDGE_W)
buildHintPad.PaddingRight = UDim.new(0, 10)
buildHintPad.Parent = buildHint

-- На ПК плашка растёт под свой текст, а не держит фиксированную ширину: хвост строки
-- («1–N — выбор · R — поворот · B — выйти») меняется вместе с числом открытых построек,
-- и любая заранее выбранная ширина рано или поздно обрезала его многоточием — так и было
-- при семи постройках. TextTruncate остаётся страховкой: он сработает, только если строка
-- упрётся в ограничитель по ширине экрана. На телефоне клавиш в строке нет, она короткая,
-- и там ширина по-прежнему долевая от экрана.
if not MobileUI.isMobile then
	buildHint.AutomaticSize = Enum.AutomaticSize.X

	local hintLimit = Instance.new("UISizeConstraint")
	hintLimit.Parent = buildHint

	local function applyHintLimit()
		hintLimit.MaxSize = Vector2.new(math.max(200, MobileUI.viewportX - 40), math.huge)
	end
	applyHintLimit()
	MobileUI.OnViewportChanged(applyHintLimit)
end

-- Что можно строить, в порядке цифровых клавиш. Имена и цены берутся из таблицы Towers:
-- добавить постройку = добавить строку туда и ключ сюда, подсказка подстроится сама.
-- Бур (Drill) в списке намеренно отсутствует: по решению автора (задача #53) он скрыт
-- из стройки. Сама турель цела и рабочая (Towers.Drill, модель и режим стрельбы на месте) —
-- вернуть её игроку значит дописать "Drill" в эту строку, больше ничего не нужно.
local ALL_TOWERS_ORDER = { "Ballista", "Wall", "Mortar", "Injector", "Vaporizer", "Centrifuge" }
local NUMBER_KEYS = {
	Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four,
	Enum.KeyCode.Five, Enum.KeyCode.Six, Enum.KeyCode.Seven,
}
local selected = 1

-- Поворот будущей постройки — четвертями (0..3). Четвертями, а не плавно, потому что
-- след постройки в клетках — квадрат, и только поворот на 90° оставляет его тем же самым:
-- на 45° платформа торчала бы из своего же следа углами (та же причина, что и на сервере,
-- см. TowerBuilder.turnCFrame). Уходит на сервер четвёртым аргументом RequestBuildTower;
-- решает, как всегда, сервер — здесь только картинка и намерение.
local TURN_STEP = math.rad(90)
local buildTurn = 0
-- Кнопка поворота на мобильной панели (на ПК её нет вовсе, там клавиша R). Объявлена
-- здесь, а не возле панели: cycleTurn ниже подписывает её подпись, а сама кнопка создаётся
-- ещё ниже — без этой строки имя внутри cycleTurn читалось бы как глобальное (тот же случай,
-- что с setBuildMode ниже).
local rotateBtn = nil

-- Панель стройки и перекраска её кнопок объявлены здесь, а создаются ниже: refreshBuildChoice
-- зовёт перекраску, а без этой строки имя внутри читалось бы как глобальное, то есть nil
-- (тот же случай, что с setBuildMode и rotateBtn).
local buildPanel = nil
local refreshBuildSelection = nil

-- Цвет постройки: тот же, каким подсвечивается клетка под неё — турель бирюзовая,
-- Стена стальная. Выбранное на панели и выбранное на поле должны быть одного цвета.
local function towerColor(key)
	return Towers[key].fireRate and Theme.color.accent or Theme.color.steel
end

-- Построек в списке может быть меньше шести: запертое (Towers[key].locked,
-- задача #56 — Мортира/Инжектор/Испаритель/Центрифуга) появляется в BUILD_ORDER только
-- после промокода. TurretsUnlocked — атрибут на ReplicatedStorage, сервер ставит его
-- в true разом всем при разгадке кода (см. TowerUnlocks/PromoCode); отдельный RemoteEvent клиенту
-- не нужен, атрибут и так реплицируется.
local BUILD_ORDER = {}
-- Пересобирает список открытых построек по текущему атрибуту. Вызывается один раз здесь
-- и повторно из листенера TurretsUnlocked ниже — та же таблица мутируется на месте
-- (table.clear + table.insert), поэтому всем, кто уже захватил BUILD_ORDER как upvalue
-- (мобильная панель, RenderStepped), новую версию видно без переприсваивания переменной.
local function rebuildOrder()
	table.clear(BUILD_ORDER)
	local turretsUnlocked = ReplicatedStorage:GetAttribute("TurretsUnlocked") == true
	for _, key in ALL_TOWERS_ORDER do
		if not Towers[key].locked or turretsUnlocked then
			table.insert(BUILD_ORDER, key)
		end
	end
end
rebuildOrder()

local function refreshBuildChoice()
	local data = Towers[BUILD_ORDER[selected]]

	-- Построек стало семь (задача #53), и полный список «1 — Колба, 2 — Стена, …»
	-- в строку подсказки больше не влезает ни на телефоне, ни на ПК — остался только
	-- диапазон клавиш. Что под какой цифрой, игрок видит, перебирая их: имя и цена
	-- выбранного по-прежнему в начале строки.
	-- Раздел слева приглушён, имя постройки — самое светлое в строке, клавиши опять тише:
	-- в режиме стройки взгляд ищет только ответ на «что сейчас ставится».
	local what = ('<font color="%s">%s</font>  за %d · %d°'):format(
		Theme.Hex(Theme.color.text), Theme.Caps(data.name), data.cost, buildTurn * 90)
	local keys = MobileUI.isMobile and ""
		or (("  ·  1–%d — выбор · R — поворот · B — выйти"):format(#BUILD_ORDER))
	buildHint.Text = ('<font color="%s">СТРОЙКА  //</font>  %s%s'):format(
		Theme.Hex(Theme.color.accentDim), what, keys)

	-- Турель и стена подсвечиваются разным цветом — выбранное видно на поле, а не только
	-- в подсказке наверху, куда во время стройки не смотрят. Запоминается в переменную,
	-- а не пишется прямо в cellHighlight: над проломом/выходом подсветка должна остаться
	-- красной независимо от выбора.
	buildColor = towerColor(BUILD_ORDER[selected])
	buildRange = data.range
	buildMinRange = data.minRange
	buildReach = Arena.ReachFor(data.footprint)
	buildArc = data.arc and math.rad(data.arc) or nil

	-- Сектор пересобирается только при смене радиуса или угла; у постройки без сектора
	-- куски сносятся вовсе, чтобы прежний сектор не остался лежать на поле.
	local arcKey = buildArc and buildRange and ("arc:%.2f:%.3f"):format(buildRange, buildArc) or "none"
	if arcKey ~= currentArcKey then
		if buildArc and buildRange then
			rebuildArcSlices(arcIndicator, buildRange, buildArc, 0.05)
		else
			clearSlices(arcIndicator)
		end
		currentArcKey = arcKey
	end

	-- Зона подсветки — по фактическому размеру платформы этой турели (Towers[key].footprint),
	-- а не по общему шагу сетки: раньше рамка всегда была Arena.buildSize одной и той же
	-- для всех построек, хотя настоящая платформа турели то мельче (Инжектор — 1.8),
	-- то крупнее (Колба — её OctoBase шире 10 студов, задача #63), и рамка не совпадала
	-- с тем, что реально встанет на поле.
	-- Форма зоны — по фактической платформе именно этой постройки: у большинства это
	-- шестигранник по footprint, у Станции FPV-дронов — трапеция её платформы
	-- (Towers[ключ].footprintShape). Занятость клеток от формы не зависит вовсе — след всегда
	-- квадратный, по footprint (buildReach выше и Grid на сервере).
	local footprint = data.footprint or Arena.buildSize
	local shape = data.footprintShape
	local key
	if shape == "square" then
		key = ("square:%.2f"):format(footprint)
	elseif shape then
		key = ("trapezoid:%.2f:%.2f:%.2f:%.2f"):format(shape.near, shape.far, shape.depth, shape.offset or 0)
	else
		key = ("hex:%.2f"):format(footprint)
	end
	if key ~= currentHighlightKey then
		if shape == "square" then
			rebuildSquareSlice(cellHighlight, footprint, HEX_THICKNESS)
		elseif shape then
			rebuildTrapezoidSlices(cellHighlight, shape, HEX_THICKNESS)
		else
			rebuildHexWedges(cellHighlight, footprint, HEX_THICKNESS)
		end
		currentHighlightKey = key
	end

	-- Панель стройки показывает выбор заливкой — без этого шесть турелей одного
	-- цвета неотличимы друг от друга. На ПК панели нет вовсе, поэтому проверка.
	if refreshBuildSelection then
		refreshBuildSelection()
	end
end

refreshBuildChoice()

-- Крутит выбор на четверть. Отдельной пересборки подсветки не нужно: фигура та же,
-- её поворачивает сам PivotTo в RenderStepped ниже.
local function cycleTurn()
	buildTurn = (buildTurn + 1) % 4
	if rotateBtn then
		-- Через сборщик: у ячейки собственный текст погашен, надпись живёт на подложке.
		Theme.SetCellText(rotateBtn, ("ПОВОРОТ\n%d°"):format(buildTurn * 90))
	end
	refreshBuildChoice()
end

-- Занято ли место под постройку с центром в этой клетке. Серверная правда живёт в Grid,
-- но отдельного remote'а под неё не нужно: у каждой постройки на арене есть
-- реплицируемые CellX/CellZ/Type, а размер её следа считается из Type тем же самым
-- Arena.ReachFor, каким его считает сервер — ответ получается тот же, что даст Grid.IsFree.
--
-- Нужно это ровно для картинки: без проверки рамка над занятым местом оставалась зелёной,
-- игрок держал кнопку полсекунды и только потом получал отказ «клетка занята».
-- Два следа пересекаются, когда расстояние между центрами меньше суммы их радиусов —
-- по обеим осям сразу, следы квадратные.
local function isOccupied(cx, cz, reach)
	for _, building in towersFolder:GetChildren() do
		local bx, bz = building:GetAttribute("CellX"), building:GetAttribute("CellZ")
		if bx and bz then
			-- Гора (MountainBarrier) в таблице Towers не лежит вовсе — footprint выйдет nil,
			-- и ReachFor вернёт общий след, ровно как на сервере у BuildBarrier.
			local other = Towers[building:GetAttribute("Type")]
			local span = reach + Arena.ReachFor(other and other.footprint)
			if math.abs(cx - bx) <= span and math.abs(cz - bz) <= span then
				return true
			end
		end
	end
	return false
end

-- Луч пускается только по полу арены: попадание в жука, стену или уже стоящую башню
-- не должно уводить подсветку в сторону от клетки, куда целится игрок.
local floorOnly = RaycastParams.new()
floorOnly.FilterType = Enum.RaycastFilterType.Include
floorOnly.FilterDescendantsInstances = { arenaFloor }

-- Сменилась локация — другой пол под лучом и другие запретные клетки.
Arena.OnChanged(function()
	entranceX, entranceZ = Arena.ToCell(Arena.entrance)
	exitX, exitZ = Arena.ToCell(Arena.exit)
	tableX, tableZ = Arena.ToCell(Arena.table)
	arenaFloor = Arena.Location():WaitForChild("ArenaFloor")
	floorOnly.FilterDescendantsInstances = { arenaFloor }
end)

local buildMode = false
local hoveredX, hoveredZ = nil, nil

-- Постройка теперь не по одному клику, а удержанием кнопки/пальца на клетке — так игрок
-- не спускает материю по случайному клику мимо цели, и на телефоне то же движение,
-- что для панорамирования камеры, не начинает стройку мгновенно.
local BUILD_HOLD_TIME = 0.5 -- секунд удержания на клетке перед RequestBuildTower

local progressGui = Instance.new("BillboardGui")
progressGui.Name = "BuildHoldProgress"
progressGui.Size = UDim2.new(0, 90, 0, 14)
progressGui.StudsOffset = Vector3.new(0, 1.4, 0)
progressGui.AlwaysOnTop = true
progressGui.Enabled = false
progressGui.Adornee = cellHighlight.PrimaryPart
progressGui.Parent = cellHighlight.PrimaryPart

local progressTrack = Instance.new("Frame")
progressTrack.Size = UDim2.new(1, 0, 1, 0)
progressTrack.BackgroundColor3 = Theme.color.panel
progressTrack.BackgroundTransparency = 0
progressTrack.BorderSizePixel = 0
progressTrack.Parent = progressGui

-- Граница у полоски над клеткой: она висит над полом арены и без неё терялась
-- на светлом фоне.
Theme.Corner(progressTrack, 4)
Theme.Hairline(progressTrack, 0.2)

local progressFill = Instance.new("Frame")
progressFill.Size = UDim2.new(0, 0, 1, 0)
progressFill.BorderSizePixel = 0
progressFill.Parent = progressTrack

Theme.Corner(progressFill, 3)

local holding = false
local holdStart = 0
local holdX, holdZ = nil, nil

local function cancelHold()
	holding = false
	holdX, holdZ = nil, nil
	progressGui.Enabled = false
	progressFill.Size = UDim2.new(0, 0, 1, 0)
end

local function startHold(cx, cz)
	holding = true
	holdStart = os.clock()
	holdX, holdZ = cx, cz
	progressGui.Enabled = true
	progressFill.Size = UDim2.new(0, 0, 1, 0)
end

-- ============ Мобильная панель стройки ============
-- На телефоне клавиш B/1/2 нет, поэтому режим стройки и тип постройки переключаются
-- экранными кнопками 56x56 в зоне большого пальца (низ левого края). Панель создаётся
-- только когда isMobile — на ПК ничего не добавляется, клавиатура остаётся как есть.
-- Объявление идёт до создания панели: обработчик кнопки вызывает setBuildMode, а без этой
-- строки имя внутри замыкания читалось как глобальное (то есть nil): local function ниже
-- создаёт НОВУЮ переменную, а не заполняет ту, на которую сослался обработчик. Из-за этого
-- тап по «Стройке» на телефоне падал с attempt to call a nil value и режим не включался вообще.
local setBuildMode

local BUILD_BTN = 64
local BUILD_BTN_GAP = 8

-- Кнопок стало восемь (семь построек плюс переключатель режима), и в одну строку по низу
-- экрана они больше не влезают: 8 x 64 плюс зазоры — это 568 px, шире рабочей ширины
-- альбомного телефона. Поэтому панель складывается в сетку по BUILD_COLS в ряд и растёт
-- вверх от нижнего края (AnchorPoint по низу), а не вправо за экран.
local BUILD_COLS = 4

-- Слот 0 — кнопка режима, дальше постройки в том же порядке, что и цифровые клавиши на ПК.
local function buildSlotPosition(slot)
	return UDim2.new(
		0,
		(slot % BUILD_COLS) * (BUILD_BTN + BUILD_BTN_GAP),
		0,
		math.floor(slot / BUILD_COLS) * (BUILD_BTN + BUILD_BTN_GAP)
	)
end

local rebuildMobilePanel -- пересбирает кнопки построек; вызывается ниже и из листенера TurretsUnlocked
if MobileUI.isMobile then
	buildPanel = Instance.new('Frame')
	-- Панель легла в строку вдоль низа, а не столбиком вдоль левого края: столбик высотой
	-- 200px на альбомном телефоне (рабочая высота ~340px) доходил до HUD в левом верхнем
	-- углу и налезал на него. В строке панель занимает 64px по высоте и не пересекается
	-- с HUD ни в одной ориентации.
	-- Отступ слева — не 12, а 180: ровно в левом нижнем углу Roblox рисует свой джойстик
	-- движения, и кнопка «Стройка» стояла прямо на нём (замерено на 750x322: кольцо
	-- ThumbstickStart 29,229..103,303 против кнопки 12,246..76,310 — перекрытие 47x57,
	-- видно и на скриншоте). 180 берётся с запасом на планшет: там джойстик крупнее
	-- (120px против 70) и его правый край уходит за 160.
	buildPanel.AnchorPoint = Vector2.new(0, 1)
	buildPanel.Position = UDim2.new(0, 180, 1, -12)
	buildPanel.BackgroundTransparency = 1
	buildPanel.Parent = controlsGui

	local buildBtn = Instance.new('TextButton')
	-- Имя, а не текст: у ячейки собственный текст погашен и переехал на подложку,
	-- и setBuildMode ниже узнаёт эту кнопку по имени.
	buildBtn.Name = "BuildModeButton"
	buildBtn.Size = UDim2.new(0, BUILD_BTN, 0, BUILD_BTN)
	buildBtn.Position = buildSlotPosition(0)
	buildBtn.FontFace = Theme.font.strong
	buildBtn.TextSize = 13
	buildBtn.TextWrapped = true
	buildBtn.Text = 'СТРОЙКА'
	buildBtn.Parent = buildPanel

	-- Та же ячейка, что и у элементов в Лаборатории: заливка цветом, надпись на подложке.
	Theme.ElementButton(buildBtn, Theme.color.action)

	buildBtn.Activated:Connect(function()
		setBuildMode(not buildMode)
	end)

	-- Выбранная постройка горит кантом и засечкой своего цвета, остальные приглушены (dim).
	-- До этого кнопки были приглушёнными плашками и выбор был виден только в строке
	-- подсказки наверху, куда во время стройки не смотрят.
	--
	-- Приглушение передаётся флагом, а не разбавленным цветом на входе (было
	-- Lerp к фону панели): сборщик теперь сам затемняет цвет до корпуса ячейки,
	-- и от разбавленного вторым затемнением не осталось бы цвета вовсе.
	function refreshBuildSelection()
		for _, child in buildPanel:GetChildren() do
			local slot = child:GetAttribute("Slot")
			local key = slot and BUILD_ORDER[slot]
			if key then
				Theme.ElementButton(child, towerColor(key), { dim = slot ~= selected })
			end
		end
	end

	-- Пересобирает кнопки построек с нуля: вызывается один раз здесь и повторно из листенера
	-- TurretsUnlocked, когда промокод расширяет BUILD_ORDER — список на экране должен
	-- вырасти сразу, без перезахода. «Стройка» (buildBtn) не TowerButton, её не трогает.
	function rebuildMobilePanel()
		for _, child in buildPanel:GetChildren() do
			if child.Name == "TowerButton" or child.Name == "RotateButton" then
				child:Destroy()
			end
		end

		-- Плюс два слота к постройкам: режим (слот 0) и поворот (последний).
		local rows = math.ceil((#BUILD_ORDER + 2) / BUILD_COLS)
		buildPanel.Size = UDim2.new(
			0,
			BUILD_BTN * BUILD_COLS + BUILD_BTN_GAP * (BUILD_COLS - 1),
			0,
			BUILD_BTN * rows + BUILD_BTN_GAP * (rows - 1)
		)

		for i, key in BUILD_ORDER do
			local b = Instance.new('TextButton')
			b.Name = "TowerButton"
			b.Size = UDim2.new(0, BUILD_BTN, 0, BUILD_BTN)
			b.Position = buildSlotPosition(i)
			b.FontFace = Theme.font.strong
			-- Имена стали длиннее («Центрифуга» вдвое длиннее «Колбы») — переносим по словам,
			-- иначе в квадрат 64x64 они просто обрезаются.
			b.TextWrapped = true
			b.TextSize = 11
			b.Text = Theme.Caps(Towers[key].name)
			b.Visible = buildMode
			-- Номер слота атрибутом: по нему refreshBuildSelection узнаёт, какая из ячеек
			-- выбрана — по тексту кнопки этого уже не понять, он переехал на подложку.
			b:SetAttribute("Slot", i)
			b.Parent = buildPanel

			-- Вид ячейки ставит refreshBuildSelection ниже: он же решает, какая из них выбрана.

			b.Activated:Connect(function()
				selected = i
				refreshBuildChoice()
			end)
		end

		-- Поворот — последним слотом, за постройками: порядок кнопок построек должен
		-- совпадать с цифровыми клавишами ПК, и вставлять что-то в середину нельзя.
		rotateBtn = Instance.new('TextButton')
		rotateBtn.Name = "RotateButton"
		rotateBtn.Size = UDim2.new(0, BUILD_BTN, 0, BUILD_BTN)
		rotateBtn.Position = buildSlotPosition(#BUILD_ORDER + 1)
		rotateBtn.FontFace = Theme.font.strong
		rotateBtn.TextWrapped = true
		rotateBtn.TextSize = 11
		rotateBtn.Text = ("ПОВОРОТ\n%d°"):format(buildTurn * 90)
		rotateBtn.Visible = buildMode
		rotateBtn.Parent = buildPanel

		-- Свой цвет, не совпадающий ни с турелью, ни со Стеной: это не выбор постройки,
		-- а действие над уже выбранной.
		Theme.ElementButton(rotateBtn, Theme.color.info)

		rotateBtn.Activated:Connect(cycleTurn)

		refreshBuildSelection()
	end

	rebuildMobilePanel()
end

function setBuildMode(enabled)
	buildMode = enabled
	buildHint.Visible = enabled
	if not enabled then
		setHighlightAppearance(cellHighlight, highlightColor, 1)
		setHighlightAppearance(arcIndicator, highlightColor, 1)
		rangeIndicator.Transparency = 1
		minRangeIndicator.Transparency = 1
		hoveredX, hoveredZ = nil, nil
		cancelHold()
	end
	if buildPanel then
		for _, child in buildPanel:GetChildren() do
			if child:IsA('TextButton') then
				if child.Name == "BuildModeButton" then
					-- В режиме стройки эта же кнопка значит уже «выйти» — и выглядит соответственно.
					-- Узнаётся по имени, а не по тексту: у ячейки он погашен и живёт на подложке.
					Theme.ElementButton(child, enabled and Theme.color.danger or Theme.color.action)
				else
					child.Visible = enabled
				end
			end
		end
	end
end

-- Промокод (задача #56) может разблокировать турели в любой момент партии, не только
-- до её начала — атрибут меняется сразу для всех, кто уже в игре. rebuildMobilePanel
-- равна nil на ПК (мобильной панели там нет), поэтому проверяется перед вызовом.
ReplicatedStorage:GetAttributeChangedSignal("TurretsUnlocked"):Connect(function()
	rebuildOrder()
	if rebuildMobilePanel then
		rebuildMobilePanel()
	end
	refreshBuildChoice()
end)

RunService.RenderStepped:Connect(function()
	if not buildMode then
		return
	end

	local mouse = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
	local hit = Workspace:Raycast(ray.Origin, ray.Direction * 1000, floorOnly)

	if hit then
		-- Клетка поджимается к тем, в которых постройка целиком помещается на поле:
		-- у самого края арены рамка должна показывать то место, куда башня встанет,
		-- а не то, куда сервер откажется её ставить.
		local cellX, cellZ = Arena.ToCell(hit.Position)
		hoveredX, hoveredZ = Arena.ClampBuildCell(cellX, cellZ, buildReach)
		-- Запрет считается по всему следу постройки, а не по одной клетке — ровно так же,
		-- как это делают Grid.IsEntranceCell/IsExitCell/IsFree на сервере, и тем же радиусом.
		local forbidden = (math.abs(hoveredX - entranceX) <= buildReach and math.abs(hoveredZ - entranceZ) <= buildReach)
			or (math.abs(hoveredX - exitX) <= buildReach and math.abs(hoveredZ - exitZ) <= buildReach)
			or Arena.IsTableCell(hoveredX, hoveredZ, buildReach)
			or isOccupied(hoveredX, hoveredZ, buildReach)
		highlightColor = forbidden and FORBIDDEN_COLOR or buildColor
		-- Подсветка крутится вместе с будущей постройкой: у Станции FPV-дронов фигура
		-- несимметричная (трапеция), и без этого зелёное пятно обещало бы не то, что встанет.
		cellHighlight:PivotTo(CFrame.new(Arena.ToWorld(hoveredX, hoveredZ) + Vector3.new(0, 0.15, 0))
			* CFrame.Angles(0, buildTurn * TURN_STEP, 0))
		setHighlightAppearance(cellHighlight, highlightColor, 0.45)

		-- У Стены range нет — кольцо прячется, показывать нечего.
		if buildRange and not forbidden then
			if buildArc then
				-- Турель с сектором (Инжектор): вместо сплошного круга — сектор
				-- вперёд, и крутится он тем же buildTurn, что и сама постройка:
				-- игрок видит, куда будет смотреть турель, ещё до того, как её поставит.
				arcIndicator:PivotTo(CFrame.new(Arena.ToWorld(hoveredX, hoveredZ) + Vector3.new(0, 0.05, 0))
					* CFrame.Angles(0, buildTurn * TURN_STEP, 0))
				setHighlightAppearance(arcIndicator, buildColor, RING_TRANSPARENCY)
				rangeIndicator.Transparency = 1
			else
				setHighlightAppearance(arcIndicator, buildColor, 1)
				local diameter = buildRange * 2
				rangeIndicator.Size = Vector3.new(0.05, diameter, diameter)
				rangeIndicator.CFrame = CFrame.new(Arena.ToWorld(hoveredX, hoveredZ) + Vector3.new(0, 0.05, 0))
					* CFrame.Angles(0, 0, math.rad(90))
				rangeIndicator.Color = buildColor
				rangeIndicator.Transparency = RING_TRANSPARENCY
			end

			-- Слепая зона (Мортира, minRange, задача #56) — второй диск чуть выше первого,
			-- закрывает своим цветом середину общего круга: «зелёная зона» на глаз
			-- превращается в кольцо с дырой, а не остаётся сплошным кругом дальности.
			if buildMinRange then
				local minDiameter = buildMinRange * 2
				minRangeIndicator.Size = Vector3.new(0.05, minDiameter, minDiameter)
				minRangeIndicator.CFrame = CFrame.new(Arena.ToWorld(hoveredX, hoveredZ) + Vector3.new(0, 0.07, 0))
					* CFrame.Angles(0, 0, math.rad(90))
				minRangeIndicator.Color = FORBIDDEN_COLOR
				minRangeIndicator.Transparency = RING_TRANSPARENCY
			else
				minRangeIndicator.Transparency = 1
			end
		else
			rangeIndicator.Transparency = 1
			minRangeIndicator.Transparency = 1
			setHighlightAppearance(arcIndicator, buildColor, 1)
		end
	else
		hoveredX, hoveredZ = nil, nil
		setHighlightAppearance(cellHighlight, highlightColor, 1)
		rangeIndicator.Transparency = 1
		minRangeIndicator.Transparency = 1
		setHighlightAppearance(arcIndicator, buildColor, 1)
	end

	-- Курсор/палец увели с клетки, на которой начали удержание — прогресс сбрасывается,
	-- иначе можно было бы начать держать одну клетку, а достроить уже другую.
	if holding then
		if hoveredX ~= holdX or hoveredZ ~= holdZ then
			cancelHold()
		else
			progressFill.BackgroundColor3 = highlightColor
			local progress = math.clamp((os.clock() - holdStart) / BUILD_HOLD_TIME, 0, 1)
			progressFill.Size = UDim2.new(progress, 0, 1, 0)
			if progress >= 1 then
				RequestBuildTower:FireServer(holdX, holdZ, BUILD_ORDER[selected], buildTurn)
				cancelHold()
			end
		end
	end
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return -- ввод съел интерфейс (например, клик по списку элементов)
	end

	if input.KeyCode == Enum.KeyCode.B then
		setBuildMode(not buildMode)
		return
	end

	if not buildMode then
		return
	end

	if input.KeyCode == Enum.KeyCode.R then
		cycleTurn()
		return
	end

	local picked = table.find(NUMBER_KEYS, input.KeyCode)
	if picked and picked <= #BUILD_ORDER then
		selected = picked
		refreshBuildChoice()
	elseif (input.UserInputType == Enum.UserInputType.MouseButton1
			or (MobileUI.isMobile and input.UserInputType == Enum.UserInputType.Touch))
		and hoveredX then
		-- Не строим сразу по клику — только начинаем отсчёт удержания, само
		-- RequestBuildTower уходит из RenderStepped через BUILD_HOLD_TIME секунд.
		startHold(hoveredX, hoveredZ)
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or (MobileUI.isMobile and input.UserInputType == Enum.UserInputType.Touch) then
		cancelHold()
	end
end)
