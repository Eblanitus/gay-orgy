-- Экран загрузки (просьба автора). Стоит в ReplicatedFirst: только отсюда он успевает
-- закрыть экран раньше, чем появится мир, и только отсюда можно снять стандартный
-- экран Roblox (RemoveDefaultLoadingScreen).
--
-- Все показания настоящие, ничего не крутится для вида (правило «без декоративного
-- интерфейса» и «без анимации в интерфейсе»): три этапа и полоса, которая растёт
-- ровно на столько, сколько реально загружено.
--   СОЕДИНЕНИЕ — ждём game.Loaded: мир и скрипты доехали до клиента.
--   РЕСУРСЫ    — ContentProvider:PreloadAsync по мешам, текстурам и звукам игры;
--                счётчик n / N — число загруженных адресов.
--   ТЕРМИНАЛ   — ждём, пока главное меню (MainMenu) соберёт себя; снимаемся, когда оно
--                уже под нами, чтобы между экранами не мелькнул остров лобби.
--
-- Внизу экрана — подсказки из LoadingTips (просьба автора): советы по игре, факты
-- бункера и записки персонала. Меняются простой сменой текста, без перехода; нажатие
-- на подсказку показывает следующую.
--
-- Свои цвета и шрифт — копия UITheme: модули из StarterPlayerScripts на этом этапе ещё
-- не пришли, а подождать их — значит показать пустой экран, ради которого экран и нужен.
local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- = UITheme.color
local C = {
	panel = Color3.fromRGB(10, 12, 15),
	hairline = Color3.fromRGB(46, 55, 66),
	frame = Color3.fromRGB(56, 104, 100),
	accent = Color3.fromRGB(96, 214, 200),
	text = Color3.fromRGB(228, 236, 244),
	textDim = Color3.fromRGB(168, 186, 207),
	textMute = Color3.fromRGB(125, 144, 166),
}
local MONO = "rbxasset://fonts/families/RobotoMono.json"
local BOLD = Font.new(MONO, Enum.FontWeight.Bold)
local BODY = Font.new(MONO, Enum.FontWeight.Regular)

local camera = workspace.CurrentCamera
local small = camera and camera.ViewportSize.Y < 500 -- телефон в альбоме

local gui = Instance.new("ScreenGui")
gui.Name = "LoadingScreen"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 1000 -- выше всего, включая меню (MobileUI.Layer.Menu = 150)
gui.Parent = playerGui

ReplicatedFirst:RemoveDefaultLoadingScreen()

local screen = Instance.new("Frame")
screen.Size = UDim2.fromScale(1, 1)
screen.BackgroundColor3 = C.panel
screen.BorderSizePixel = 0
screen.Parent = gui

local W = small and 360 or 520
local LINE_H = small and 18 or 22
local block = Instance.new("Frame")
block.AnchorPoint = Vector2.new(0.5, 0.5)
block.Position = UDim2.fromScale(0.5, 0.5)
block.Size = UDim2.new(0, W, 0, 0)
block.AutomaticSize = Enum.AutomaticSize.Y
block.BackgroundTransparency = 1
block.Parent = screen

local sizeLimit = Instance.new("UISizeConstraint")
sizeLimit.MaxSize = Vector2.new(W, math.huge)
sizeLimit.Parent = block

local list = Instance.new("UIListLayout")
list.SortOrder = Enum.SortOrder.LayoutOrder
list.Padding = UDim.new(0, small and 4 or 6)
list.Parent = block

local order = 0
local function label(font, size, color, text, h)
	order += 1
	local l = Instance.new("TextLabel")
	l.LayoutOrder = order
	l.Size = UDim2.new(1, 0, 0, h or LINE_H)
	l.BackgroundTransparency = 1
	l.FontFace = font
	l.TextSize = size
	l.TextColor3 = color
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Text = text
	l.Parent = block
	return l
end

local function rule(gap)
	order += 1
	local r = Instance.new("Frame")
	r.LayoutOrder = order
	r.Size = UDim2.new(1, 0, 0, gap)
	r.BackgroundTransparency = 1
	r.Parent = block
	local line = Instance.new("Frame")
	line.AnchorPoint = Vector2.new(0, 0.5)
	line.Position = UDim2.fromScale(0, 0.5)
	line.Size = UDim2.new(1, 0, 0, 1)
	line.BackgroundColor3 = C.hairline
	line.BorderSizePixel = 0
	line.Parent = r
end

-- Строка этапа: название слева, состояние справа.
local STAGES = {
	{ key = "connect", name = "СОЕДИНЕНИЕ" },
	{ key = "assets", name = "РЕСУРСЫ" },
	{ key = "terminal", name = "ТЕРМИНАЛ" },
}
local rows = {}
for _, stage in STAGES do
	local name = label(BODY, small and 11 or 13, C.textMute, stage.name)
	local state = Instance.new("TextLabel")
	state.Size = UDim2.fromScale(1, 1)
	state.BackgroundTransparency = 1
	state.FontFace = BOLD
	state.TextSize = small and 11 or 13
	state.TextXAlignment = Enum.TextXAlignment.Right
	state.Parent = name
	rows[stage.key] = { name = name, state = state }
end

local function setStage(key, status, detail)
	local row = rows[key]
	local base
	for _, stage in STAGES do
		if stage.key == key then
			base = stage.name
		end
	end
	row.name.Text = detail and (base .. "   " .. detail) or base
	if status == "done" then
		row.name.TextColor3 = C.textDim
		row.state.TextColor3 = C.accent
		row.state.Text = "[ ОК ]"
	elseif status == "active" then
		row.name.TextColor3 = C.text
		row.state.TextColor3 = C.text
		row.state.Text = "[ ИДЁТ ]"
	else
		row.name.TextColor3 = C.textMute
		row.state.TextColor3 = C.textMute
		row.state.Text = "[ -- ]"
	end
end
for _, stage in STAGES do
	setStage(stage.key, "wait")
end

rule(small and 10 or 16)

-- Полоса — те же столбики, что у ползунков громкости: горят по доле загруженного.
local SEGMENTS = 40
local BAR_H = small and 10 or 14
order += 1
local barRow = Instance.new("Frame")
barRow.LayoutOrder = order
barRow.Size = UDim2.new(1, 0, 0, BAR_H)
barRow.BackgroundTransparency = 1
barRow.Parent = block

local percent = Instance.new("TextLabel")
percent.AnchorPoint = Vector2.new(1, 0)
percent.Position = UDim2.fromScale(1, 0)
percent.Size = UDim2.new(0, 48, 1, 0)
percent.BackgroundTransparency = 1
percent.FontFace = BOLD
percent.TextSize = small and 11 or 13
percent.TextColor3 = C.accent
percent.TextXAlignment = Enum.TextXAlignment.Right
percent.Text = "0%"
percent.Parent = barRow

-- Столбики — во всю ширину, кроме места под проценты справа.
local track = Instance.new("Frame")
track.Size = UDim2.new(1, -56, 1, 0)
track.BackgroundTransparency = 1
track.Parent = barRow

local segs = {}
for i = 1, SEGMENTS do
	local seg = Instance.new("Frame")
	seg.Position = UDim2.fromScale((i - 1) / SEGMENTS, 0)
	seg.Size = UDim2.new(1 / SEGMENTS, -2, 1, 0)
	seg.BackgroundColor3 = C.hairline
	seg.BorderSizePixel = 0
	seg.Parent = track
	segs[i] = seg
end

-- Доля всей загрузки: соединение — первые 10%, ресурсы — до 90%, терминал — остаток.
local function setProgress(fraction)
	fraction = math.clamp(fraction, 0, 1)
	local lit = math.floor(fraction * SEGMENTS + 0.5)
	for i, seg in segs do
		seg.BackgroundColor3 = i <= lit and C.accent or C.hairline
	end
	percent.Text = math.floor(fraction * 100 + 0.5) .. "%"
end
setProgress(0)

-- ---- Подсказки ----
-- Все три списка перемешиваются в одну колоду и идут по ней без повторов; кончилась —
-- перемешивается заново. Первой всегда идёт подсказка по игре: экран может сняться
-- через секунду, и лучше успеть показать полезное.
local TIP_SECONDS = 7
local KIND_CAPTION = { tip = "СОВЕТ", lore = "БУНКЕР", note = "ЗАПИСКА" }

local tipsModule = script.Parent:WaitForChild("LoadingTips", 5)
local okTips, tipLists = false, nil
if tipsModule then
	okTips, tipLists = pcall(require, tipsModule)
end

if okTips and type(tipLists) == "table" then
	local pool = {}
	for kind in KIND_CAPTION do
		for _, text in tipLists[kind] or {} do
			table.insert(pool, { kind = kind, text = text })
		end
	end

	local rng = Random.new()
	local deck, pos = {}, 0
	local function reshuffle()
		deck = table.clone(pool)
		for i = #deck, 2, -1 do
			local j = rng:NextInteger(1, i)
			deck[i], deck[j] = deck[j], deck[i]
		end
		pos = 0
	end
	reshuffle()
	for i, entry in deck do
		if entry.kind == "tip" then
			deck[1], deck[i] = deck[i], deck[1]
			break
		end
	end

	local tipBox = Instance.new("TextButton")
	tipBox.AutoButtonColor = false
	tipBox.Text = ""
	tipBox.AnchorPoint = Vector2.new(0.5, 1)
	tipBox.Position = UDim2.new(0.5, 0, 1, small and -12 or -32)
	tipBox.Size = UDim2.new(1, -32, 0, 0)
	tipBox.AutomaticSize = Enum.AutomaticSize.Y
	tipBox.BackgroundTransparency = 1
	tipBox.Parent = screen

	local tipLimit = Instance.new("UISizeConstraint")
	tipLimit.MaxSize = Vector2.new(W, math.huge) -- по краям блока загрузки
	tipLimit.Parent = tipBox

	local tipList = Instance.new("UIListLayout")
	tipList.SortOrder = Enum.SortOrder.LayoutOrder
	tipList.Padding = UDim.new(0, small and 4 or 6)
	tipList.Parent = tipBox

	local topLine = Instance.new("Frame")
	topLine.LayoutOrder = 1
	topLine.Size = UDim2.new(1, 0, 0, 1)
	topLine.BackgroundColor3 = C.hairline
	topLine.BorderSizePixel = 0
	topLine.Parent = tipBox

	local head = Instance.new("TextLabel")
	head.LayoutOrder = 2
	head.Size = UDim2.new(1, 0, 0, LINE_H)
	head.BackgroundTransparency = 1
	head.FontFace = BOLD
	head.TextSize = small and 11 or 13
	head.TextColor3 = C.accent
	head.TextXAlignment = Enum.TextXAlignment.Left
	head.Parent = tipBox

	-- Справа — что будет по нажатию: подсказка и правда листается.
	local nextHint = Instance.new("TextLabel")
	nextHint.Size = UDim2.fromScale(1, 1)
	nextHint.BackgroundTransparency = 1
	nextHint.FontFace = BODY
	nextHint.TextSize = small and 11 or 13
	nextHint.TextColor3 = C.textMute
	nextHint.TextXAlignment = Enum.TextXAlignment.Right
	nextHint.Text = "[ ДАЛЕЕ ]"
	nextHint.Parent = head

	local body = Instance.new("TextLabel")
	body.LayoutOrder = 3
	body.Size = UDim2.new(1, 0, 0, 0)
	body.AutomaticSize = Enum.AutomaticSize.Y
	body.BackgroundTransparency = 1
	body.FontFace = BODY
	body.TextSize = small and 12 or 15
	body.LineHeight = 1.15
	body.TextColor3 = C.text
	body.TextWrapped = true
	body.TextXAlignment = Enum.TextXAlignment.Left
	body.TextYAlignment = Enum.TextYAlignment.Top
	body.Parent = tipBox

	local shownAt = 0
	local function nextTip()
		pos += 1
		if pos > #deck then
			reshuffle()
			pos = 1
		end
		local entry = deck[pos]
		head.Text = "> " .. KIND_CAPTION[entry.kind]
		body.Text = entry.text
		shownAt = os.clock()
	end

	if #pool > 0 then
		nextTip()
		tipBox.Activated:Connect(nextTip)
		-- Смена по времени считается от последнего показа: пролистанная вручную
		-- подсказка тоже стоит полные TIP_SECONDS.
		task.spawn(function()
			while gui.Parent do
				task.wait(0.25)
				if os.clock() - shownAt >= TIP_SECONDS then
					nextTip()
				end
			end
		end)
	else
		tipBox:Destroy()
	end
end

-- ---- 1. Соединение ----
setStage("connect", "active")
if not game:IsLoaded() then
	game.Loaded:Wait()
end
setStage("connect", "done")
setProgress(0.1)

-- ---- 2. Ресурсы ----
-- Адреса всего, что грузится с сервера Roblox: меши, текстуры, звуки, картинки, анимации.
-- Одинаковый адрес у сотни деталей — один файл, поэтому счёт идёт по уникальным адресам.
-- Одним вызовом PreloadAsync, а не пачками: движок качает их параллельно, и отчёт
-- приходит по каждому адресу — это и есть счётчик n / N.
local ASSET_PROPS = {
	MeshPart = { "MeshId", "TextureID" },
	SpecialMesh = { "MeshId", "TextureId" },
	Decal = { "Texture" },
	Texture = { "Texture" },
	Sound = { "SoundId" },
	SurfaceAppearance = { "ColorMap", "NormalMap", "RoughnessMap", "MetalnessMap" },
	ImageLabel = { "Image" },
	ImageButton = { "Image" },
	Animation = { "AnimationId" },
	Sky = { "SkyboxBk", "SkyboxDn", "SkyboxFt", "SkyboxLf", "SkyboxRt", "SkyboxUp" },
}
local seen, ids = {}, {}
for _, root in { workspace, game:GetService("ReplicatedStorage"), game:GetService("SoundService"), game:GetService("Lighting") } do
	for _, d in root:GetDescendants() do
		local props = ASSET_PROPS[d.ClassName]
		if props then
			for _, prop in props do
				local ok, id = pcall(function()
					return d[prop]
				end)
				if ok and type(id) == "string" and id ~= "" and not seen[id] then
					seen[id] = true
					table.insert(ids, id)
				end
			end
		end
	end
end

local total = #ids
local done = 0
setStage("assets", "active", "0 / " .. total)
if total > 0 then
	pcall(ContentProvider.PreloadAsync, ContentProvider, ids, function()
		done += 1
		setStage("assets", "active", done .. " / " .. total)
		setProgress(0.1 + 0.8 * done / total)
	end)
end
setStage("assets", "done", total .. " / " .. total)
setProgress(0.9)

-- ---- 3. Терминал ----
-- Меню собирает себя в StarterPlayerScripts; ждём его не дольше полуминуты, чтобы
-- ошибка в меню не заперла игрока за экраном загрузки навсегда.
setStage("terminal", "active")
local menu = playerGui:WaitForChild("MainMenu", 30)
if menu and not menu.Enabled then
	local deadline = os.clock() + 10
	while not menu.Enabled and os.clock() < deadline do
		task.wait(0.1)
	end
end
setStage("terminal", "done")
setProgress(1)

gui:Destroy()
