-- Окно справочника — как у производителя (просьба автора, #269): своя рамка-монитор с
-- сеткой точек, шапка с названием, поиском и крестиком, разделы пунктами в подвале.
-- Раскладка повторяет CraftingProducer.layout, только без потолка высоты: карте нужен
-- весь экран. Содержимое разделов кладёт CraftingReference в screen.
local GuiService = game:GetService("GuiService")

local Theme = require(script.Parent:WaitForChild("UITheme"))
local MobileUI = require(script.Parent:WaitForChild("MobileUI"))
local Show = require(script.Parent:WaitForChild("ProducerShow"))
local Glass = require(script.Parent:WaitForChild("MonitorGlass"))

local Frame = {}

local function make(className, name, parent, z)
	local inst = Instance.new(className)
	inst.Name = name
	inst.BorderSizePixel = 0
	inst.BackgroundTransparency = 1
	inst.ZIndex = z
	inst.Parent = parent
	return inst
end

local function place(inst, x, y, w, h)
	inst.Position = UDim2.fromOffset(math.floor(x + 0.5), math.floor(y + 0.5))
	inst.Size = UDim2.fromOffset(math.max(0, math.floor(w + 0.5)), math.max(0, math.floor(h + 0.5)))
end

-- root — окно лаборатории, gui — его ScreenGui, modes — { id, name } по порядку подвала.
function Frame.Build(root, gui, modes)
	-- Вкладка лежит прямо на root и сама глухая, как у производителя: закрывает фон окна
	-- и его шапку. Слой 1 — как у содержимого карты: при общей глубине окна (Global)
	-- ребёнок ниже рамки лёг бы под неё.
	local bookFrame = make("Frame", "BookTab", root, 1)
	bookFrame.Size = UDim2.fromScale(1, 1)
	bookFrame.BackgroundColor3 = Theme.color.panel
	bookFrame.BackgroundTransparency = 0
	bookFrame.ClipsDescendants = true
	bookFrame.Visible = false

	-- Решётка лаборатории вокруг окна, едущая медленно, как соты производителя.
	local drifting = table.clone(Theme.scene.lab)
	drifting.pulse, drifting.wave = 0, 0
	Theme.Backdrop(bookFrame, drifting)

	local mon = make("Frame", "Monitor", bookFrame, 1)
	mon.BackgroundColor3 = Theme.color.ink
	mon.BackgroundTransparency = 0
	Theme.Corner(mon, Theme.radius.panel)
	Theme.Stroke(mon, Theme.color.frame, 1, 0)
	Theme.Brackets(mon)
	-- Фон окна — редкие тусклые звёзды (Theme.Stars, #270, #271): свой узор у каждого
	-- окна. Первым ребёнком рамки, под всем содержимым.
	local paintDots = Theme.Stars(mon, { zIndex = 1 })
	local glass = Glass.Mount(mon)

	local head = make("TextLabel", "Title", mon, 3)
	head.FontFace = Theme.font.strong
	head.TextXAlignment = Enum.TextXAlignment.Left
	head.TextTruncate = Enum.TextTruncate.AtEnd
	head.Text = "СПРАВОЧНИК"
	Theme.Display(head)
	head.TextColor3 = Theme.color.accent

	-- Поиск — в шапке, на месте материи производителя: слева от крестика. Выделен
	-- (просьба автора, #270): кант цвета акцента, подпись «ПОИСК» в самом поле; пока
	-- в поле пишут, кант горит в полную силу.
	local searchBox = make("TextBox", "Search", mon, 3)
	searchBox.ClearTextOnFocus = false
	searchBox.PlaceholderText = "элемент или жук…"
	searchBox.Text = ""
	searchBox.FontFace = Theme.font.body
	searchBox.TextXAlignment = Enum.TextXAlignment.Left
	searchBox.TextTruncate = Enum.TextTruncate.AtEnd
	Theme.Field(searchBox)
	searchBox.PlaceholderColor3 = Theme.color.textMute:Lerp(Theme.color.ink, 0.35) -- тише текста
	-- Кант — по рамке поля: у текстового объекта UIStroke по умолчанию обводит буквы.
	local searchEdge = Theme.Stroke(searchBox, Theme.color.accent, 1, 0.35)
	searchEdge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	local searchPad = Instance.new("UIPadding")
	searchPad.PaddingRight = UDim.new(0, 10)
	searchPad.Parent = searchBox
	-- Подпись — не ребёнок поля: отступ поля сдвинул бы и её. Нажатия она не держит,
	-- они проходят в поле под ней.
	local searchCaption = make("TextLabel", "SearchCaption", mon, 4)
	searchCaption.FontFace = Theme.font.strong
	searchCaption.TextColor3 = Theme.color.accent
	searchCaption.TextXAlignment = Enum.TextXAlignment.Left
	searchCaption.Text = "ПОИСК"
	-- Черта между подписью и текстом, как у плашки материи производителя.
	local searchRule = make("Frame", "SearchRule", mon, 4)
	searchRule.BackgroundColor3 = Theme.color.text
	searchRule.BackgroundTransparency = 0.85
	searchBox.Focused:Connect(function()
		searchEdge.Thickness, searchEdge.Transparency = 2, 0
	end)
	searchBox.FocusLost:Connect(function()
		searchEdge.Thickness, searchEdge.Transparency = 1, 0.35
	end)

	local close = make("TextButton", "Close", mon, 3)
	Show.Press(close)
	Theme.CloseButton(close)
	close.MouseButton1Click:Connect(function()
		gui.Enabled = false
	end)

	-- Поле разделов. Страницы — его дети во весь размер.
	local screen = make("Frame", "Screen", mon, 1)

	-- Подвал: разделы пунктами, как режимы производителя.
	local map = make("Frame", "ModeMap", mon, 3)
	local modeButtons = {}
	for _, m in modes do
		local b = make("TextButton", "Mode_" .. m.id, map, 4)
		Show.Press(b)
		b.FontFace = Theme.font.strong
		b.TextXAlignment = Enum.TextXAlignment.Left
		b.Text = Theme.Caps(m.name)
		local bp = Instance.new("UIPadding")
		bp.Name = "Pad"
		bp.Parent = b
		modeButtons[m.id] = b
	end

	local function layout()
		local W, H = bookFrame.AbsoluteSize.X, bookFrame.AbsoluteSize.Y
		if W < 100 or H < 100 then
			return
		end
		local compact = MobileUI.isMobile or H < 520 or W < 1024
		local function by(phone, pc)
			return compact and phone or pc
		end

		local strip = math.max(MobileUI.TopInset, GuiService.TopbarInset.Height)
		local margin = by(14, 26)
		local top = strip + by(8, 12)
		local AW, AH = W - margin * 2, H - top - by(10, 14)
		local px, pt, pb = by(12, 20), by(10, 14), by(8, 12)
		local g = by(6, 16)
		local titleH = by(34, 44)
		local rowH = by(44, 50)
		local footGap = by(6, 10)

		local CY = pt + titleH + g
		local below = g + footGap + rowH + pb
		local CW = math.min(AW - px * 2, 2400)
		local CH = AH - CY - below
		local MW, MH = CW + px * 2, CY + CH + below
		place(mon, margin + math.floor((AW - MW) / 2), top + math.floor((AH - MH) / 2), MW, MH)
		paintDots(math.floor(MW), math.floor(MH))

		local closeW, closeH = by(52, 44), by(34, 44)
		local closeY = pt + math.max(0, math.floor((titleH - closeH) / 2))
		place(close, MW - px - closeW, closeY, closeW, closeH)
		local searchW = math.min(by(170, 320), math.floor((MW - px * 2 - closeW - g) / 2))
		local searchX = MW - px - closeW - g - searchW
		place(searchBox, searchX, closeY, searchW, closeH)
		searchBox.TextSize = by(13, 15)
		local capGap, capW = by(10, 14), by(42, 52)
		searchCaption.TextSize = by(11, 13)
		place(searchCaption, searchX + capGap, closeY, capW, closeH)
		local ruleX = searchX + capGap + capW
		place(searchRule, ruleX, closeY + closeH * 0.25, 1, closeH * 0.5)
		searchPad.PaddingLeft = UDim.new(0, capGap + capW + 10)
		head.TextSize = by(20, 32)
		place(head, px, pt, MW - px * 2 - closeW - searchW - g * 2, titleH)

		local footY = MH - pb - rowH
		local tabGap = by(6, 10)
		local tabW = math.min(by(120, 220), (MW - px * 2 - tabGap * (#modes - 1)) / #modes)
		place(map, px, footY, tabW * #modes + tabGap * (#modes - 1), rowH)
		for i, m in modes do
			local b = modeButtons[m.id]
			b.TextSize = by(13, 18)
			b.Pad.PaddingLeft = UDim.new(0, by(10, 16))
			place(b, (i - 1) * (tabW + tabGap), 0, tabW, rowH)
		end

		place(screen, px, CY, CW, CH)
	end

	local function open()
		if not (gui.Enabled and bookFrame.Visible) then
			return
		end
		layout()
		Theme.Open(mon)
	end

	gui:GetPropertyChangedSignal("Enabled"):Connect(open)
	bookFrame:GetPropertyChangedSignal("Visible"):Connect(open)
	bookFrame:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
	GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(layout)
	MobileUI.OnViewportChanged(layout)

	return {
		bookFrame = bookFrame,
		screen = screen,
		modeButtons = modeButtons,
		searchBox = searchBox,
		glass = glass,
	}
end

return Frame
