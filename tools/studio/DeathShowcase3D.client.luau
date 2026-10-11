-- Просмотрщик смертей от снаряда — настоящий локальный 3D-стенд для Roblox Studio.
-- Установка и запуск: tools/studio/README.md. Только Studio; в игре ничего не запускает.
-- Важно: этот файл — отдельный инструмент, не часть Rojo-маппинга и не правка игровых модулей.

local RunService = game:GetService("RunService")
if not RunService:IsStudio() then
	return
end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
if not player then
	return
end

local playerGui = player:WaitForChild("PlayerGui")
local Elements = require(ReplicatedStorage:WaitForChild("Elements"))
local Enemies = require(ReplicatedStorage:WaitForChild("Enemies"))
local EnemyModel = require(ReplicatedStorage:WaitForChild("EnemyModel"))
local EnemyGait = require(ReplicatedStorage:WaitForChild("EnemyGait"))

-- Отдельная копия модуля нужна, чтобы его внутренний список демонстрационных трупов
-- не вытеснял трупы настоящей игры при просмотре каталога подряд.
local corpseModule = ReplicatedStorage:WaitForChild("CorpseFX"):Clone()
corpseModule.Name = "DeathShowcaseCorpseFX"
corpseModule.Parent = script
local CorpseFX = require(corpseModule)

local COLORS = {
	background = Color3.fromRGB(7, 12, 15),
	panel = Color3.fromRGB(12, 20, 23),
	panelRaised = Color3.fromRGB(17, 28, 31),
	line = Color3.fromRGB(43, 62, 66),
	text = Color3.fromRGB(226, 237, 231),
	muted = Color3.fromRGB(132, 153, 153),
	teal = Color3.fromRGB(100, 220, 194),
	gold = Color3.fromRGB(235, 185, 112),
	red = Color3.fromRGB(231, 112, 100),
}

local PROFILE_ORDER = { "body", "char", "crush", "melt", "brittle", "dissolve", "gib", "destroy" }
local PROFILE_LABELS = {
	body = "ТЕЛО",
	char = "ОБУГЛИВАЕТСЯ",
	crush = "РАЗДАВЛИВАЕТСЯ",
	melt = "ПЛАВИТСЯ",
	brittle = "ХРУПКИЙ ТРУП",
	dissolve = "РАСТВОРЯЕТСЯ",
	gib = "РАЗРЫВАЕТСЯ",
	destroy = "УНИЧТОЖАЕТСЯ",
}
local PROFILE_DESCRIPTIONS = {
	body = "Обычная физическая туша: модель жука переходит в позу смерти и падает на пол.",
	char = "Обугленный труп из CorpseFX: дым, осыпание и игровые тайминги останков.",
	crush = "Ветка CorpseRemains.crush: расплющивание тела, след и отлетевшие куски.",
	melt = "Ветка CorpseRemains.melt: плавление модели и лужа останков.",
	brittle = "Холодный труп из CorpseFX; после смерти его можно отдельно расколоть.",
	dissolve = "Ветка CorpseRemains.dissolve: тело исчезает в настоящем эффекте растворения.",
	gib = "Ветка CorpseRemains.gib: остаются оторванные части и игровые брызги.",
	destroy = "Ветка CorpseRemains.destroy: цель уничтожается без обычного трупа.",
}

local UNIQUE_SAMPLE_KEYS = {
	body = "Water",
	char = "Fire",
	crush = "Earth",
	melt = "Lava",
	brittle = "Cold",
	dissolve = "Acid",
	gib = "Gunpowder",
	destroy = "Star",
}

local function profileOf(data)
	return data.remains or "body"
end

local allItems = {}
local itemsByKey = {}
for key, data in Elements do
	local item = {
		key = key,
		name = data.name or key,
		data = data,
		profile = profileOf(data),
	}
	table.insert(allItems, item)
	itemsByKey[key] = item
end

table.sort(allItems, function(a, b)
	if a.name == b.name then
		return a.key < b.key
	end
	return a.name < b.name
end)

local uniqueItems = {}
for _, profile in PROFILE_ORDER do
	local sample = itemsByKey[UNIQUE_SAMPLE_KEYS[profile]]
	if not sample or sample.profile ~= profile then
		for _, item in allItems do
			if item.profile == profile then
				sample = item
				break
			end
		end
	end
	if sample then
		table.insert(uniqueItems, sample)
	end
end

local function elementColor(item)
	return item and item.data.color or COLORS.teal
end

local function rgbText(color)
	return ("#%02X%02X%02X"):format(
		math.floor(color.R * 255 + 0.5),
		math.floor(color.G * 255 + 0.5),
		math.floor(color.B * 255 + 0.5)
	)
end

local function make(className, parent, properties)
	local instance = Instance.new(className)
	for property, value in properties do
		instance[property] = value
	end
	instance.Parent = parent
	return instance
end

local function round(instance, radius)
	make("UICorner", instance, { CornerRadius = UDim.new(0, radius or 8) })
end

local function stroke(instance, color, transparency)
	make("UIStroke", instance, {
		Color = color or COLORS.line,
		Transparency = transparency or 0,
		Thickness = 1,
	})
end

local gui = make("ScreenGui", playerGui, {
	Name = "DeathShowcase3D",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = 10000,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Enabled = false,
})

local dim = make("Frame", gui, {
	Name = "Dim",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = COLORS.background,
	BackgroundTransparency = 0.40,
	BorderSizePixel = 0,
})

local topBar = make("Frame", dim, {
	Name = "TopBar",
	Position = UDim2.new(0, 18, 0, 14),
	Size = UDim2.new(1, -36, 0, 56),
	BackgroundColor3 = COLORS.panel,
	BackgroundTransparency = 0.08,
	BorderSizePixel = 0,
})
round(topBar, 10)
stroke(topBar)

local logo = make("Frame", topBar, {
	Position = UDim2.new(0, 12, 0, 9),
	Size = UDim2.fromOffset(38, 38),
	BackgroundColor3 = Color3.fromRGB(20, 51, 47),
	BorderSizePixel = 0,
})
round(logo, 8)
stroke(logo, COLORS.teal, 0.25)
make("TextLabel", logo, {
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Text = "3D",
	TextColor3 = COLORS.teal,
	Font = Enum.Font.GothamBold,
	TextSize = 13,
})

make("TextLabel", topBar, {
	Position = UDim2.new(0, 60, 0, 8),
	Size = UDim2.new(0.62, -60, 0, 22),
	BackgroundTransparency = 1,
	Text = "АЛХИМИЧЕСКАЯ ЛАБОРАТОРИЯ  /  СМЕРТЬ ОТ СНАРЯДА",
	TextColor3 = COLORS.text,
	Font = Enum.Font.GothamBold,
	TextSize = 13,
	TextXAlignment = Enum.TextXAlignment.Left,
})
make("TextLabel", topBar, {
	Position = UDim2.new(0, 60, 0, 30),
	Size = UDim2.new(0.62, -60, 0, 16),
	BackgroundTransparency = 1,
	Text = "ЛОКАЛЬНЫЙ СТЕНД STUDIO  ·  EnemyModel + CorpseFX + CorpseRemains",
	TextColor3 = COLORS.muted,
	Font = Enum.Font.Code,
	TextSize = 9,
	TextXAlignment = Enum.TextXAlignment.Left,
})

local closeButton = make("TextButton", topBar, {
	Name = "Close",
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -12, 0.5, 0),
	Size = UDim2.fromOffset(174, 34),
	BackgroundColor3 = Color3.fromRGB(30, 44, 47),
	BorderSizePixel = 0,
	Text = "ЗАКРЫТЬ  ·  ESC",
	TextColor3 = COLORS.text,
	Font = Enum.Font.GothamBold,
	TextSize = 10,
	AutoButtonColor = true,
})
round(closeButton, 7)
stroke(closeButton)

local leftPanel = make("Frame", dim, {
	Name = "Catalog",
	Position = UDim2.new(0, 18, 0, 82),
	Size = UDim2.new(0, 286, 1, -100),
	BackgroundColor3 = COLORS.panel,
	BackgroundTransparency = 0.06,
	BorderSizePixel = 0,
})
round(leftPanel, 10)
stroke(leftPanel)

make("TextLabel", leftPanel, {
	Position = UDim2.new(0, 14, 0, 12),
	Size = UDim2.new(1, -28, 0, 18),
	BackgroundTransparency = 1,
	Text = "КАТАЛОГ ЭЛЕМЕНТОВ",
	TextColor3 = COLORS.teal,
	Font = Enum.Font.Code,
	TextSize = 10,
	TextXAlignment = Enum.TextXAlignment.Left,
})
make("TextLabel", leftPanel, {
	Position = UDim2.new(0, 14, 0, 31),
	Size = UDim2.new(1, -28, 0, 25),
	BackgroundTransparency = 1,
	Text = "Выбери снаряд",
	TextColor3 = COLORS.text,
	Font = Enum.Font.GothamBold,
	TextSize = 17,
	TextXAlignment = Enum.TextXAlignment.Left,
})

local allButton = make("TextButton", leftPanel, {
	Name = "AllMode",
	Position = UDim2.new(0, 12, 0, 67),
	Size = UDim2.new(0.5, -7, 0, 32),
	BackgroundColor3 = COLORS.panelRaised,
	BorderSizePixel = 0,
	Text = ("ВСЕ · %d"):format(#allItems),
	TextColor3 = COLORS.muted,
	Font = Enum.Font.Code,
	TextSize = 10,
	AutoButtonColor = true,
})
round(allButton, 6)

local uniqueButton = make("TextButton", leftPanel, {
	Name = "UniqueMode",
	Position = UDim2.new(0.5, 2, 0, 67),
	Size = UDim2.new(0.5, -14, 0, 32),
	BackgroundColor3 = COLORS.panelRaised,
	BorderSizePixel = 0,
	Text = ("УНИКАЛЬНЫЕ · %d"):format(#uniqueItems),
	TextColor3 = COLORS.muted,
	Font = Enum.Font.Code,
	TextSize = 9,
	AutoButtonColor = true,
})
round(uniqueButton, 6)

local searchBox = make("TextBox", leftPanel, {
	Name = "Search",
	Position = UDim2.new(0, 12, 0, 107),
	Size = UDim2.new(1, -24, 0, 34),
	BackgroundColor3 = Color3.fromRGB(7, 13, 16),
	BorderSizePixel = 0,
	ClearTextOnFocus = false,
	PlaceholderText = "Найти элемент…",
	PlaceholderColor3 = Color3.fromRGB(101, 122, 123),
	Text = "",
	TextColor3 = COLORS.text,
	Font = Enum.Font.Gotham,
	TextSize = 12,
	TextXAlignment = Enum.TextXAlignment.Left,
})
round(searchBox, 6)
stroke(searchBox, COLORS.line, 0.2)
make("UIPadding", searchBox, {
	PaddingLeft = UDim.new(0, 10),
	PaddingRight = UDim.new(0, 8),
})

local listCount = make("TextLabel", leftPanel, {
	Position = UDim2.new(0, 14, 0, 146),
	Size = UDim2.new(1, -28, 0, 16),
	BackgroundTransparency = 1,
	Text = "71 ЭЛЕМЕНТОВ",
	TextColor3 = COLORS.muted,
	Font = Enum.Font.Code,
	TextSize = 9,
	TextXAlignment = Enum.TextXAlignment.Left,
})

local listFrame = make("ScrollingFrame", leftPanel, {
	Name = "ElementList",
	Position = UDim2.new(0, 8, 0, 166),
	Size = UDim2.new(1, -16, 1, -211),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 4,
	ScrollBarImageColor3 = Color3.fromRGB(65, 111, 106),
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.None,
})
local listLayout = make("UIListLayout", listFrame, {
	Padding = UDim.new(0, 4),
	SortOrder = Enum.SortOrder.LayoutOrder,
})
make("UIPadding", listFrame, {
	PaddingTop = UDim.new(0, 2),
	PaddingLeft = UDim.new(0, 2),
	PaddingRight = UDim.new(0, 4),
	PaddingBottom = UDim.new(0, 6),
})
listLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
	listFrame.CanvasSize = UDim2.new(0, 0, 0, listLayout.AbsoluteContentSize.Y + 10)
end)

make("TextLabel", leftPanel, {
	Position = UDim2.new(0, 13, 1, -36),
	Size = UDim2.new(1, -26, 0, 24),
	BackgroundTransparency = 1,
	Text = "← → СМЕНИТЬ · ПКМ ВРАЩАТЬ · ESC ВЫЙТИ",
	TextColor3 = Color3.fromRGB(103, 126, 127),
	Font = Enum.Font.Code,
	TextSize = 8,
	TextXAlignment = Enum.TextXAlignment.Left,
})

local infoPanel = make("Frame", dim, {
	Name = "Inspector",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -18, 0, 82),
	Size = UDim2.new(0, 276, 0, 294),
	BackgroundColor3 = COLORS.panel,
	BackgroundTransparency = 0.06,
	BorderSizePixel = 0,
})
round(infoPanel, 10)
stroke(infoPanel)

make("TextLabel", infoPanel, {
	Position = UDim2.new(0, 15, 0, 13),
	Size = UDim2.new(1, -30, 0, 16),
	BackgroundTransparency = 1,
	Text = "ВЫБРАННЫЙ ЭЛЕМЕНТ",
	TextColor3 = COLORS.teal,
	Font = Enum.Font.Code,
	TextSize = 9,
	TextXAlignment = Enum.TextXAlignment.Left,
})
local elementNameLabel = make("TextLabel", infoPanel, {
	Name = "ElementName",
	Position = UDim2.new(0, 15, 0, 33),
	Size = UDim2.new(1, -30, 0, 34),
	BackgroundTransparency = 1,
	Text = "Огонь",
	TextColor3 = COLORS.text,
	Font = Enum.Font.GothamBold,
	TextSize = 22,
	TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Center,
})
local keyLabel = make("TextLabel", infoPanel, {
	Name = "ElementKey",
	Position = UDim2.new(0, 15, 0, 69),
	Size = UDim2.new(1, -30, 0, 16),
	BackgroundTransparency = 1,
	Text = "Fire",
	TextColor3 = COLORS.muted,
	Font = Enum.Font.Code,
	TextSize = 10,
	TextXAlignment = Enum.TextXAlignment.Left,
})

local profilePill = make("TextLabel", infoPanel, {
	Name = "Profile",
	Position = UDim2.new(0, 15, 0, 94),
	Size = UDim2.new(1, -30, 0, 28),
	BackgroundColor3 = Color3.fromRGB(19, 45, 42),
	BorderSizePixel = 0,
	Text = "ОБУГЛИВАЕТСЯ  ·  CHAR",
	TextColor3 = COLORS.teal,
	Font = Enum.Font.Code,
	TextSize = 10,
	TextXAlignment = Enum.TextXAlignment.Left,
})
round(profilePill, 6)
make("UIPadding", profilePill, { PaddingLeft = UDim.new(0, 9) })

local profileDescription = make("TextLabel", infoPanel, {
	Name = "Description",
	Position = UDim2.new(0, 15, 0, 132),
	Size = UDim2.new(1, -30, 0, 50),
	BackgroundTransparency = 1,
	Text = PROFILE_DESCRIPTIONS.char,
	TextColor3 = COLORS.muted,
	Font = Enum.Font.Gotham,
	TextSize = 10,
	TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
})

local colorLine = make("Frame", infoPanel, {
	Position = UDim2.new(0, 15, 0, 191),
	Size = UDim2.new(1, -30, 0, 1),
	BackgroundColor3 = COLORS.line,
	BorderSizePixel = 0,
})

local colorDot = make("Frame", infoPanel, {
	Position = UDim2.new(0, 15, 0, 204),
	Size = UDim2.fromOffset(10, 10),
	BackgroundColor3 = COLORS.teal,
	BorderSizePixel = 0,
})
round(colorDot, 8)
local colorCode = make("TextLabel", infoPanel, {
	Position = UDim2.new(0, 31, 0, 201),
	Size = UDim2.new(0, 90, 0, 16),
	BackgroundTransparency = 1,
	Text = "#64DCC2",
	TextColor3 = COLORS.muted,
	Font = Enum.Font.Code,
	TextSize = 9,
	TextXAlignment = Enum.TextXAlignment.Left,
})
local countLabel = make("TextLabel", infoPanel, {
	Position = UDim2.new(1, -136, 0, 201),
	Size = UDim2.new(0, 121, 0, 16),
	BackgroundTransparency = 1,
	Text = ("%d / %d ПРОФИЛЕЙ"):format(#allItems, #uniqueItems),
	TextColor3 = COLORS.muted,
	Font = Enum.Font.Code,
	TextSize = 8,
	TextXAlignment = Enum.TextXAlignment.Right,
})

local statusPanel = make("Frame", dim, {
	Name = "Playback",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -18),
	Size = UDim2.fromOffset(442, 58),
	BackgroundColor3 = COLORS.panel,
	BackgroundTransparency = 0.04,
	BorderSizePixel = 0,
})
round(statusPanel, 10)
stroke(statusPanel)

local previousButton = make("TextButton", statusPanel, {
	Name = "Previous",
	Position = UDim2.new(0, 9, 0, 9),
	Size = UDim2.fromOffset(42, 40),
	BackgroundColor3 = COLORS.panelRaised,
	BorderSizePixel = 0,
	Text = "‹",
	TextColor3 = COLORS.text,
	Font = Enum.Font.GothamBold,
	TextSize = 25,
	AutoButtonColor = true,
})
round(previousButton, 7)

local playButton = make("TextButton", statusPanel, {
	Name = "Replay",
	Position = UDim2.new(0, 59, 0, 9),
	Size = UDim2.new(1, -159, 0, 40),
	BackgroundColor3 = Color3.fromRGB(20, 62, 55),
	BorderSizePixel = 0,
	Text = "ЗАПУСТИТЬ СМЕРТЬ",
	TextColor3 = Color3.fromRGB(196, 247, 226),
	Font = Enum.Font.GothamBold,
	TextSize = 11,
	AutoButtonColor = true,
})
round(playButton, 7)

local nextButton = make("TextButton", statusPanel, {
	Name = "Next",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -9, 0, 9),
	Size = UDim2.fromOffset(42, 40),
	BackgroundColor3 = COLORS.panelRaised,
	BorderSizePixel = 0,
	Text = "›",
	TextColor3 = COLORS.text,
	Font = Enum.Font.GothamBold,
	TextSize = 25,
	AutoButtonColor = true,
})
round(nextButton, 7)

local statusLabel = make("TextLabel", dim, {
	Name = "Status",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -82),
	Size = UDim2.fromOffset(500, 18),
	BackgroundTransparency = 1,
	Text = "ГОТОВ К ДЕМОНСТРАЦИИ",
	TextColor3 = COLORS.teal,
	Font = Enum.Font.Code,
	TextSize = 9,
})

local shatterButton = make("TextButton", infoPanel, {
	Name = "ShatterBrittle",
	Position = UDim2.new(0, 15, 0, 248),
	Size = UDim2.new(1, -30, 0, 34),
	BackgroundColor3 = Color3.fromRGB(27, 46, 58),
	BorderSizePixel = 0,
	Text = "РАСКОЛОТЬ ХРУПКИЙ ТРУП",
	TextColor3 = Color3.fromRGB(192, 228, 246),
	Font = Enum.Font.GothamBold,
	TextSize = 9,
	AutoButtonColor = true,
	Visible = false,
})
round(shatterButton, 7)
stroke(shatterButton, Color3.fromRGB(81, 130, 157), 0.2)

local currentRows = allItems
local uniqueMode = false
local selectedItem = itemsByKey.Fire or allItems[1]
local rowButtons = {}
local isOpen = false
local sessionToken = 0
local sceneRoot = nil
local effectsFolder = nil
local targetModel = nil
local projectilePart = nil
local activeTween = nil
local currentDemoId = nil
local nextDemoId = 0
local demoShattered = false
local watchedFolders = {}
local managedArtifacts = {}
local savedScreens = {}
local savedCamera = nil
local camera = nil
local savedMouseBehavior = nil
local rotateCamera = false
local cameraYaw = 0
local cameraPitch = 0.16
local cameraDistance = 21
local SHOWCASE_ORIGIN = Vector3.new(0, 1200, 0)
local FLOOR_Y = SHOWCASE_ORIGIN.Y
local TARGET_FOCUS = SHOWCASE_ORIGIN + Vector3.new(0, 3.0, 0)

local function nearShowcase(instance)
	local ok, position = pcall(function()
		if instance:IsA("BasePart") then
			return instance.Position
		elseif instance:IsA("Model") then
			return instance:GetPivot().Position
		end
		return nil
	end)
	if not ok or not position then
		return false
	end
	local delta = position - SHOWCASE_ORIGIN
	return math.abs(delta.Y) < 150 and Vector3.new(delta.X, 0, delta.Z).Magnitude < 150
end

local function captureShowcaseEffect(instance)
	if not nearShowcase(instance) then
		return
	end
	managedArtifacts[instance] = true
	if isOpen and effectsFolder and effectsFolder.Parent then
		pcall(function()
			instance.Parent = effectsFolder
		end)
	else
		pcall(function()
			instance:Destroy()
		end)
	end
end

local function watchEffectFolders()
	for _, name in { "Corpses", "Blood", "Debris" } do
		local folder = Workspace:FindFirstChild(name)
		if not folder then
			folder = Instance.new("Folder")
			folder.Name = name
			folder.Parent = Workspace
		end
		if not watchedFolders[folder] then
			watchedFolders[folder] = folder.ChildAdded:Connect(function(child)
				-- Некоторые игровые функции сначала кладут деталь в папку, затем выставляют ей
				-- позицию. Проверяем после текущего шага планировщика, когда позиция уже задана.
				task.defer(function()
					captureShowcaseEffect(child)
				end)
			end)
		end
	end
end

local function collectShowcaseEffects()
	for _, name in { "Corpses", "Blood", "Debris" } do
		local folder = Workspace:FindFirstChild(name)
		if folder then
			for _, child in folder:GetChildren() do
				captureShowcaseEffect(child)
			end
		end
	end
end

local function makeWorldPart(parent, name, size, cframe, color, material, transparency)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.Transparency = transparency or 0
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = true
	part.Parent = parent
	return part
end

local function createScene()
	if sceneRoot and sceneRoot.Parent then
		return
	end
	watchEffectFolders()

	sceneRoot = Instance.new("Folder")
	sceneRoot.Name = "DeathShowcase3D_Local"
	sceneRoot.Parent = Workspace

	local stage = Instance.new("Folder")
	stage.Name = "Stage"
	stage.Parent = sceneRoot

	local floor = makeWorldPart(
		stage,
		"PreviewFloor",
		Vector3.new(84, 1, 84),
		CFrame.new(SHOWCASE_ORIGIN.X, FLOOR_Y - 0.5, SHOWCASE_ORIGIN.Z),
		Color3.fromRGB(20, 31, 34),
		Enum.Material.Slate
	)
	floor.CanCollide = true

	makeWorldPart(
		stage,
		"Backdrop",
		Vector3.new(72, 28, 1),
		CFrame.new(SHOWCASE_ORIGIN + Vector3.new(0, 13.5, -26)),
		Color3.fromRGB(11, 20, 24),
		Enum.Material.Basalt
	)

	-- Ненавязчивые кольца на полу дают масштаб сцены, не подменяя игровые эффекты.
	for index, diameter in { 18, 30, 46 } do
		local ring = makeWorldPart(
			stage,
			"StageRing" .. index,
			Vector3.new(0.05, diameter, diameter),
			CFrame.new(SHOWCASE_ORIGIN + Vector3.new(0, 0.04 + index * 0.005, 0))
				* CFrame.Angles(0, 0, math.rad(90)),
			Color3.fromRGB(48, 91, 86),
			Enum.Material.Neon,
			0.48
		)
		ring.CastShadow = false
	end

	effectsFolder = Instance.new("Folder")
	effectsFolder.Name = "Effects"
	effectsFolder.Parent = sceneRoot
end

local function clearCurrentDemo()
	if activeTween then
		pcall(function()
			activeTween:Cancel()
		end)
		activeTween = nil
	end
	if currentDemoId then
		-- Убираем только собственную демонстрацию из локального экземпляра CorpseFX.
		pcall(function()
			CorpseFX.Eat(currentDemoId)
		end)
		currentDemoId = nil
	end
	if targetModel and targetModel.Parent then
		targetModel:Destroy()
	end
	targetModel = nil
	if projectilePart and projectilePart.Parent then
		projectilePart:Destroy()
	end
	projectilePart = nil
	if effectsFolder and effectsFolder.Parent then
		for _, child in effectsFolder:GetChildren() do
			child:Destroy()
		end
	end
	for instance in managedArtifacts do
		if instance.Parent then
			pcall(function()
				instance:Destroy()
			end)
		end
	end
	table.clear(managedArtifacts)
	demoShattered = false
	shatterButton.Visible = false
end

local function updateCamera()
	if not camera or not isOpen then
		return
	end
	local horizontal = math.cos(cameraPitch) * cameraDistance
	local offset = Vector3.new(
		math.sin(cameraYaw) * horizontal,
		math.sin(cameraPitch) * cameraDistance,
		math.cos(cameraYaw) * horizontal
	)
	local position = TARGET_FOCUS + offset
	camera.CFrame = CFrame.lookAt(position, TARGET_FOCUS)
	camera.Focus = CFrame.new(TARGET_FOCUS)
end

local function buildProjectile(color, fromPosition, impactPosition)
	local bolt = Instance.new("Part")
	bolt.Name = "ShowcaseProjectile"
	bolt.Shape = Enum.PartType.Ball
	bolt.Size = Vector3.new(0.66, 0.66, 0.66)
	bolt.CFrame = CFrame.lookAt(fromPosition, impactPosition)
	bolt.Color = color
	bolt.Material = Enum.Material.Neon
	bolt.Anchored = true
	bolt.CanCollide = false
	bolt.CanQuery = false
	bolt.CanTouch = false
	bolt.CastShadow = false
	bolt.Parent = sceneRoot

	local front = Instance.new("Attachment")
	front.Name = "TrailFront"
	front.Position = Vector3.new(0, 0, -0.2)
	front.Parent = bolt
	local rear = Instance.new("Attachment")
	rear.Name = "TrailRear"
	rear.Position = Vector3.new(0, 0, 0.2)
	rear.Parent = bolt

	local trail = Instance.new("Trail")
	trail.Name = "ProjectileTrail"
	trail.Attachment0 = front
	trail.Attachment1 = rear
	trail.Color = ColorSequence.new(color, color:Lerp(Color3.new(1, 1, 1), 0.5))
	trail.LightEmission = 1
	trail.Lifetime = 0.2
	trail.MinLength = 0.04
	trail.FaceCamera = true
	trail.WidthScale = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.34),
		NumberSequenceKeypoint.new(1, 0),
	})
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.05),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.Parent = bolt

	local light = Instance.new("PointLight")
	light.Color = color
	light.Brightness = 1.8
	light.Range = 9
	light.Shadows = false
	light.Parent = bolt
	return bolt
end

local function impactFlash(position, color)
	if not effectsFolder or not effectsFolder.Parent then
		return
	end
	local flash = Instance.new("Part")
	flash.Name = "ProjectileImpact"
	flash.Shape = Enum.PartType.Ball
	flash.Size = Vector3.new(0.5, 0.5, 0.5)
	flash.CFrame = CFrame.new(position)
	flash.Color = color
	flash.Material = Enum.Material.Neon
	flash.Anchored = true
	flash.CanCollide = false
	flash.CanQuery = false
	flash.CanTouch = false
	flash.CastShadow = false
	flash.Parent = effectsFolder

	local light = Instance.new("PointLight")
	light.Color = color
	light.Brightness = 5
	light.Range = 14
	light.Shadows = false
	light.Parent = flash

	TweenService:Create(flash, TweenInfo.new(0.24, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(4.5, 4.5, 4.5),
		Transparency = 1,
	}):Play()
	TweenService:Create(light, TweenInfo.new(0.24), { Brightness = 0, Range = 2 }):Play()
	Debris:AddItem(flash, 0.35)

	local ring = Instance.new("Part")
	ring.Name = "ImpactRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.08, 0.7, 0.7)
	ring.CFrame = CFrame.new(position) * CFrame.Angles(0, math.rad(90), 0)
	ring.Color = color
	ring.Material = Enum.Material.Neon
	ring.Transparency = 0.15
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CastShadow = false
	ring.Parent = effectsFolder
	TweenService:Create(ring, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.08, 5.5, 5.5),
		Transparency = 1,
	}):Play()
	Debris:AddItem(ring, 0.38)
end

local function setStatus(text, color)
	statusLabel.Text = text
	statusLabel.TextColor3 = color or COLORS.teal
end

local function runDemo(item)
	if not isOpen or not item then
		return
	end
	sessionToken += 1
	local token = sessionToken
	clearCurrentDemo()
	createScene()
	setStatus("СОБИРАЮ НАСТОЯЩУЮ МОДЕЛЬ ЖУКА…", COLORS.gold)
	playButton.Text = "СНАРЯД В ПОЛЁТЕ…"

	local built, modelOrError = pcall(function()
		local enemyData = Enemies.Normal
		local model = EnemyModel.Build(enemyData, enemyData.scale or 3)
		model.Name = "DeathShowcase_Target"
		for _, descendant in model:GetDescendants() do
			if descendant:IsA("BasePart") then
				descendant.Anchored = true
				descendant.CanCollide = false
				descendant.CanQuery = false
				descendant.CanTouch = false
				descendant.CollisionGroup = "Default"
			end
		end
		model:PivotTo(CFrame.new(SHOWCASE_ORIGIN + Vector3.new(0, enemyData.rideHeight or 3, 0)))
		model.Parent = sceneRoot
		return model
	end)

	if not built then
		setStatus("НЕ УДАЛОСЬ СОБРАТЬ МОДЕЛЬ: " .. tostring(modelOrError), COLORS.red)
		playButton.Text = "ПОВТОРИТЬ"
		warn("[DeathShowcase3D] EnemyModel.Build: " .. tostring(modelOrError))
		return
	end

	targetModel = modelOrError
	local targetForDemo = targetModel
	local scale = targetForDemo:GetAttribute("Scale") or Enemies.Normal.scale or 3
	local launchPosition = SHOWCASE_ORIGIN + Vector3.new(0, 4.2, 20)
	local impactPosition = SHOWCASE_ORIGIN + Vector3.new(0, 3.2, 0)
	projectilePart = buildProjectile(elementColor(item), launchPosition, impactPosition)
	local bolt = projectilePart
	local tween = TweenService:Create(
		bolt,
		TweenInfo.new(0.62, Enum.EasingStyle.Linear),
		{ Position = impactPosition }
	)
	activeTween = tween
	setStatus("СНАРЯД " .. string.upper(item.name) .. " · ПОЛЁТ К ЦЕЛИ", elementColor(item))
	tween:Play()

	task.spawn(function()
		local playbackState = tween.Completed:Wait()
		if token ~= sessionToken or not isOpen or playbackState ~= Enum.PlaybackState.Completed then
			return
		end
		if bolt.Parent then
			bolt:Destroy()
		end
		projectilePart = nil
		activeTween = nil
		impactFlash(impactPosition, elementColor(item))
		setStatus("ПОПАДАНИЕ · ВЫПОЛНЯЮ ИГРОВОЙ CORPSEFX", COLORS.gold)

		nextDemoId += 1
		local demoId = -nextDemoId
		currentDemoId = demoId
		local hit = {
			remains = item.profile,
			scorched = item.profile == "char",
			fraction = 1,
			from = launchPosition,
			floorY = FLOOR_Y,
			scale = scale,
			throw = item.data.knockback and item.data.knockback.distance or nil,
		}

		local ok, err = pcall(function()
			CorpseFX.Leave(targetForDemo, hit, demoId)
		end)
		if targetForDemo.Parent then
			targetForDemo:Destroy()
		end
		if targetModel == targetForDemo then
			targetModel = nil
		end
		collectShowcaseEffects()

		if not ok then
			setStatus("ОШИБКА CORPSEFX: " .. tostring(err), COLORS.red)
			playButton.Text = "ПОВТОРИТЬ"
			warn("[DeathShowcase3D] CorpseFX.Leave: " .. tostring(err))
			return
		end

		setStatus(PROFILE_LABELS[item.profile] .. " · " .. item.name, COLORS.teal)
		playButton.Text = "ПОВТОРИТЬ СМЕРТЬ"
		if item.profile == "brittle" then
			shatterButton.Visible = true
		end
	end)
end

local function updateInspector(item)
	if not item then
		return
	end
	local color = elementColor(item)
	elementNameLabel.Text = item.name
	keyLabel.Text = item.key
	profilePill.Text = PROFILE_LABELS[item.profile] .. "  ·  " .. string.upper(item.profile)
	profilePill.TextColor3 = color
	profilePill.BackgroundColor3 = color:Lerp(COLORS.panel, 0.78)
	profileDescription.Text = PROFILE_DESCRIPTIONS[item.profile] or "Игровой профиль останков."
	colorDot.BackgroundColor3 = color
	colorCode.Text = rgbText(color)
	countLabel.Text = ("%d ЭЛЕМЕНТОВ  /  %d ПРОФИЛЕЙ"):format(#allItems, #uniqueItems)
end

local function refreshModeButtons()
	local activeColor = Color3.fromRGB(20, 51, 47)
	local inactiveColor = COLORS.panelRaised
	allButton.BackgroundColor3 = if uniqueMode then inactiveColor else activeColor
	allButton.TextColor3 = if uniqueMode then COLORS.muted else COLORS.teal
	uniqueButton.BackgroundColor3 = if uniqueMode then activeColor else inactiveColor
	uniqueButton.TextColor3 = if uniqueMode then COLORS.teal else COLORS.muted
end

local function rebuildList()
	for _, child in listFrame:GetChildren() do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end
	table.clear(rowButtons)
	currentRows = if uniqueMode then uniqueItems else allItems
	local query = string.lower(searchBox.Text)
	local visibleCount = 0

	for _, item in currentRows do
		local searchable = string.lower(item.name .. " " .. item.key .. " " .. item.profile)
		if query == "" or string.find(searchable, query, 1, true) then
			visibleCount += 1
			local selected = selectedItem == item
			local button = make("TextButton", listFrame, {
				Name = "Element_" .. item.key,
				LayoutOrder = visibleCount,
				Size = UDim2.new(1, -7, 0, 34),
				BackgroundColor3 = if selected then Color3.fromRGB(20, 43, 40) else Color3.fromRGB(13, 22, 25),
				BackgroundTransparency = if selected then 0 else 0.18,
				BorderSizePixel = 0,
				Text = "",
				AutoButtonColor = false,
			})
			round(button, 6)
			if selected then
				stroke(button, Color3.fromRGB(57, 111, 99), 0.15)
			end
			local swatch = make("Frame", button, {
				Position = UDim2.new(0, 8, 0.5, -5),
				Size = UDim2.fromOffset(10, 10),
				BackgroundColor3 = elementColor(item),
				BorderSizePixel = 0,
			})
			round(swatch, 6)
			make("TextLabel", button, {
				Position = UDim2.new(0, 26, 0, 0),
				Size = UDim2.new(1, -84, 1, 0),
				BackgroundTransparency = 1,
				Text = item.name,
				TextColor3 = if selected then COLORS.text else Color3.fromRGB(194, 208, 201),
				Font = Enum.Font.Gotham,
				TextSize = 11,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
			})
			make("TextLabel", button, {
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -8, 0.5, 0),
				Size = UDim2.fromOffset(48, 16),
				BackgroundTransparency = 1,
				Text = if uniqueMode then string.upper(item.profile) else item.key,
				TextColor3 = if selected then COLORS.teal else Color3.fromRGB(97, 122, 123),
				Font = Enum.Font.Code,
				TextSize = 8,
				TextXAlignment = Enum.TextXAlignment.Right,
				TextTruncate = Enum.TextTruncate.AtEnd,
			})
			rowButtons[item] = button
			button.Activated:Connect(function()
				selectedItem = item
				updateInspector(item)
				rebuildList()
				runDemo(item)
			end)
		end
	end
	listCount.Text = ("%d / %d ПОКАЗАНО"):format(visibleCount, #currentRows)
	listFrame.CanvasPosition = Vector2.zero
	refreshModeButtons()
end

allButton.Activated:Connect(function()
	uniqueMode = false
	rebuildList()
end)
uniqueButton.Activated:Connect(function()
	uniqueMode = true
	rebuildList()
end)
searchBox:GetPropertyChangedSignal("Text"):Connect(rebuildList)
playButton.Activated:Connect(function()
	runDemo(selectedItem)
end)

local function selectOffset(offset)
	if not selectedItem then
		return
	end
	local currentIndex = table.find(currentRows, selectedItem) or 1
	local nextIndex = ((currentIndex - 1 + offset) % #currentRows) + 1
	selectedItem = currentRows[nextIndex]
	updateInspector(selectedItem)
	rebuildList()
	runDemo(selectedItem)
end

previousButton.Activated:Connect(function()
	selectOffset(-1)
end)
nextButton.Activated:Connect(function()
	selectOffset(1)
end)

shatterButton.Activated:Connect(function()
	if not currentDemoId or demoShattered or not isOpen then
		return
	end
	local ok, err = pcall(function()
		CorpseFX.Shatter(currentDemoId)
	end)
	if not ok then
		setStatus("ОШИБКА РАСКОЛА: " .. tostring(err), COLORS.red)
		warn("[DeathShowcase3D] CorpseFX.Shatter: " .. tostring(err))
		return
	end
	demoShattered = true
	shatterButton.Visible = false
	setStatus("ХРУПКИЙ ТРУП РАСКОЛОТ · ОСКОЛКИ ИЗ CORPSEREMAINS", COLORS.teal)
	collectShowcaseEffects()
end)

local function hideGameScreens()
	table.clear(savedScreens)
	for _, child in playerGui:GetChildren() do
		if child:IsA("ScreenGui") and child ~= gui then
			savedScreens[child] = child.Enabled
			child.Enabled = false
		end
	end
end

playerGui.ChildAdded:Connect(function(child)
	if isOpen and child:IsA("ScreenGui") and child ~= gui then
		savedScreens[child] = child.Enabled
		child.Enabled = false
	end
end)

local function restoreGameScreens()
	for screen, wasEnabled in savedScreens do
		if screen.Parent then
			screen.Enabled = wasEnabled
		end
	end
	table.clear(savedScreens)
end

local function openShowcase()
	if isOpen then
		return
	end
	isOpen = true
	sessionToken += 1
	createScene()
	hideGameScreens()
	gui.Enabled = true

	camera = Workspace.CurrentCamera
	if camera then
		savedCamera = {
			camera = camera,
			cameraType = camera.CameraType,
			cameraSubject = camera.CameraSubject,
			cframe = camera.CFrame,
			focus = camera.Focus,
			fieldOfView = camera.FieldOfView,
		}
		camera.CameraType = Enum.CameraType.Scriptable
		camera.FieldOfView = 38
	end
	savedMouseBehavior = UserInputService.MouseBehavior
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	cameraYaw = 0
	cameraPitch = 0.16
	cameraDistance = 21
	updateCamera()

	if selectedItem then
		updateInspector(selectedItem)
		rebuildList()
		runDemo(selectedItem)
	end
end

local function closeShowcase()
	if not isOpen then
		return
	end
	isOpen = false
	sessionToken += 1
	rotateCamera = false
	gui.Enabled = false
	clearCurrentDemo()
	if sceneRoot and sceneRoot.Parent then
		sceneRoot:Destroy()
	end
	sceneRoot = nil
	effectsFolder = nil

	if savedCamera then
		local oldCamera = savedCamera.camera
		if oldCamera and oldCamera.Parent then
			oldCamera.CameraType = savedCamera.cameraType
			oldCamera.CameraSubject = savedCamera.cameraSubject
			oldCamera.CFrame = savedCamera.cframe
			oldCamera.Focus = savedCamera.focus
			oldCamera.FieldOfView = savedCamera.fieldOfView
		end
		if Workspace.CurrentCamera and Workspace.CurrentCamera ~= oldCamera then
			Workspace.CurrentCamera.CameraType = Enum.CameraType.Custom
		end
	end
	savedCamera = nil
	camera = nil
	if savedMouseBehavior then
		UserInputService.MouseBehavior = savedMouseBehavior
	end
	savedMouseBehavior = nil
	restoreGameScreens()
end

closeButton.Activated:Connect(closeShowcase)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	local controlDown = UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
		or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
	local shiftDown = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
		or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
	if input.KeyCode == Enum.KeyCode.B and controlDown and shiftDown then
		if isOpen then
			closeShowcase()
		else
			openShowcase()
		end
		return
	end
	if not isOpen or gameProcessed then
		return
	end
	if input.KeyCode == Enum.KeyCode.Escape then
		closeShowcase()
	elseif input.KeyCode == Enum.KeyCode.Left then
		selectOffset(-1)
	elseif input.KeyCode == Enum.KeyCode.Right then
		selectOffset(1)
	elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
		rotateCamera = true
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		rotateCamera = false
	end
end)

UserInputService.InputChanged:Connect(function(input, gameProcessed)
	if not isOpen then
		return
	end
	if rotateCamera and input.UserInputType == Enum.UserInputType.MouseMovement then
		cameraYaw -= input.Delta.X * 0.006
		cameraPitch = math.clamp(cameraPitch + input.Delta.Y * 0.004, -0.05, 0.82)
		updateCamera()
	elseif input.UserInputType == Enum.UserInputType.MouseWheel and not gameProcessed then
		local mouse = UserInputService:GetMouseLocation()
		local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
		if mouse.X > 310 and mouse.X < viewport.X - 290 then
			cameraDistance = math.clamp(cameraDistance - input.Position.Z * 1.6, 12, 38)
			updateCamera()
		end
	end
end)

RunService.RenderStepped:Connect(function(dt)
	if isOpen and targetModel and targetModel.Parent then
		-- Настоящая походка/idle pose из EnemyGait; на момент попадания позу смерти
		-- выставляет сам CorpseFX.Leave, точно так же, как в игровом клиенте.
		local ok, err = pcall(function()
			EnemyGait.Step(targetModel, math.min(dt, 0.1), "idle")
		end)
		if not ok then
			warn("[DeathShowcase3D] EnemyGait.Step: " .. tostring(err))
		end
	end
end)

rebuildList()
if selectedItem then
	updateInspector(selectedItem)
end
