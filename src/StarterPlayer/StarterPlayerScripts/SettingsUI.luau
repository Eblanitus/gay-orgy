-- Экран настроек главного меню. Строится целиком по ReplicatedStorage.UISettings:
-- сколько там строк, столько здесь переключателей. Новая настройка появляется в меню
-- сама, без правки этого файла.
--
-- Строка положения переключателя печатная («[ ВКЛ ]» / «[ ВЫКЛ ]»), а не рисованный
-- ползунок: язык всего интерфейса — приборный терминал (UITheme, задача #90),
-- а круглый ползунок из мобильных настроек в нём единственный такой на весь экран.
-- У настройки с вариантами (UISettings, options) в той же скобке стоит имя выбранного,
-- а нажатие перебирает их по кругу: второй вид строки вместо второго экрана.
--
-- Строки разложены по вкладкам (UISettings.Tabs, поле tab строки): «Интерфейс» и
-- «Звук». Числовая строка (громкость) — рамка с ползунком во всю ширину, и ползунок
-- этот — приборная шкала из столбиков, а не мобильный кружок. Столбики растут так же,
-- как громкость (UISettings.Gain): ползунок идёт ровно, громкость — по кривой. Справа
-- от черты 100% — красная «гипер»-зона, громче записанного звука.
-- Ползунок тянут пальцем или мышью; нажатие без протяжки ставит его в точку нажатия.
-- Пока тянут, громкость группы меняется сразу, и на каждом десятке положения щёлкает
-- образец этой группы (поле sample). В профиль уходит одно значение — когда ползунок
-- отпустили: звать сервер на каждый кадр протяжки незачем.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local MobileUI = require(script.Parent:WaitForChild("MobileUI"))
local Theme = require(script.Parent:WaitForChild("UITheme"))
local Settings = require(script.Parent:WaitForChild("Settings"))
local UISound = require(script.Parent:WaitForChild("UISound"))
local UISettings = require(ReplicatedStorage:WaitForChild("UISettings"))

local SettingsUI = {}

local ON_TEXT = "[ ВКЛ ]"
local OFF_TEXT = "[ ВЫКЛ ]"

-- Столбиков на шкале громкости, по всей длине ползунка.
local BARS = 30
-- Высота столбика — громкость в степени 0,6: примерно так ухо слышит громкость
-- (закон Стивенса), и глаз видит на шкале то же, что слышит.
local BAR_POWER = 0.6
-- Ползунок трогается, только когда палец ушёл вбок дальше этого. Ушёл раньше вверх
-- или вниз — это прокрутка списка, а не громкость.
local DRAG_SLOP = 6
-- Ближе этого к черте 100% ползунок прилипает к ней: попасть пальцем ровно трудно.
local KNEE_SNAP = 3
-- Пока ползунок тянут, образец звучит на каждом таком шаге положения.
local NOTCH = 10

-- Громкость в процентах для числа над ползунком. Тихий край кривой — меньше процента,
-- но не ноль: там «<1%», чтобы не читалось как выключенный звук.
local function percentText(gain)
	local percent = gain * 100
	if percent > 0 and percent < 0.5 then
		return "<1%"
	end
	return math.floor(percent + 0.5) .. "%"
end

function SettingsUI.Mount(parent)
	local mobile = MobileUI.isMobile
	local ROW_H = mobile and 66 or 62
	local GAP = 8
	local TOGGLE_W = mobile and 88 or 104
	-- Потолок ширины строки. Во всю ширину рамки название настройки и её положение
	-- оказываются в тысяче пикселей друг от друга, и что именно включено — не считывается
	-- взглядом. Та же причина, что у потолка самой рамки меню (MainMenu.FRAME_MAX_W).
	local ROW_MAX_W = mobile and 460 or 640
	-- Вкладки — как в журнале (JournalUI): та же высота и тот же вид кнопок.
	local TAB_H = mobile and 34 or 38
	-- Ползунок громкости: столбики высотой METER_H, под ними полоса и строка подписей.
	-- Строка громкости выше обычной: ползунок лежит под названием и подписью.
	local METER_H = mobile and 26 or 22
	local CAPTION_H = 11
	local SLIDER_H = METER_H + 8 + CAPTION_H
	local VOLUME_ROW_H = mobile and 120 or 112

	local page = Instance.new("Frame")
	page.Name = "SettingsPage"
	page.Size = UDim2.new(1, 0, 1, 0)
	page.BackgroundTransparency = 1
	page.BorderSizePixel = 0
	page.Visible = false
	page.Parent = parent

	local tabsRow = Instance.new("Frame")
	tabsRow.Name = "Tabs"
	tabsRow.Size = UDim2.new(1, -8, 0, TAB_H)
	tabsRow.BackgroundTransparency = 1
	tabsRow.Parent = page

	local tabsLimit = Instance.new("UISizeConstraint")
	tabsLimit.MaxSize = Vector2.new(ROW_MAX_W, TAB_H)
	tabsLimit.Parent = tabsRow

	local tabsLayout = Instance.new("UIListLayout")
	tabsLayout.FillDirection = Enum.FillDirection.Horizontal
	tabsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	tabsLayout.Padding = UDim.new(0, 6)
	tabsLayout.Parent = tabsRow

	-- Свой список на каждую вкладку: переключение только прячет один и показывает другой.
	local lists = {}
	local tabButtons = {}
	local current = UISettings.Tabs[1].key

	local function select(key)
		current = key
		for _, tab in UISettings.Tabs do
			local on = tab.key == key
			Theme.Button(tabButtons[tab.key], on and "active" or "ghost")
			lists[tab.key].Visible = on
		end
	end

	for index, tab in UISettings.Tabs do
		local list = Instance.new("ScrollingFrame")
		list.Name = tab.key
		list.Position = UDim2.new(0, 0, 0, TAB_H + 10)
		list.Size = UDim2.new(1, 0, 1, -(TAB_H + 10))
		list.BackgroundTransparency = 1
		list.BorderSizePixel = 0
		list.ScrollBarThickness = 4
		list.CanvasSize = UDim2.new(0, 0, 0, 0)
		list.AutomaticCanvasSize = Enum.AutomaticSize.Y
		list.Visible = false
		list.Parent = page
		Theme.Scroller(list)
		Theme.DragScroll(list)
		lists[tab.key] = list

		local layout = Instance.new("UIListLayout")
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Padding = UDim.new(0, GAP)
		layout.Parent = list

		local button = Instance.new("TextButton")
		button.Name = tab.key
		button.LayoutOrder = index
		button.Size = UDim2.new(1 / #UISettings.Tabs, -6 * (#UISettings.Tabs - 1) / #UISettings.Tabs, 1, 0)
		button.FontFace = Theme.font.strong
		button.TextSize = mobile and 11 or 13
		button.TextTruncate = Enum.TextTruncate.AtEnd
		button.Text = Theme.Caps(tab.name)
		button.Parent = tabsRow
		Theme.Button(button, "ghost")
		tabButtons[tab.key] = button
		button.MouseButton1Click:Connect(function()
			select(tab.key)
		end)
	end

	-- Каждая строка умеет перерисовать себя по текущему значению: настройки приходят
	-- из профиля ПОСЛЕ того, как экран уже собран (клиентские скрипты стартуют
	-- раньше загрузки профиля), и без этого переключатели остались бы на умолчаниях,
	-- хотя сама игра уже живёт по сохранённым.
	local redraw = {}

	for index, item in UISettings.List do
		local list = lists[item.tab or "view"]
		-- Колонка положения шириной под самый длинный вариант: «[ ЭКСПЕРИМЕНТ ]»
		-- в ширину «[ ВЫКЛ ]» не помещается и обрезается по границе надписи. Считается
		-- по числу букв, а не через TextService: ради одной строки экран ждал бы сервер шрифтов.
		local stateSize = mobile and 14 or 15
		local stateW = TOGGLE_W
		if item.options then
			local longest = 0
			for _, option in item.options do
				longest = math.max(longest, utf8.len(option.label))
			end
			stateW = math.max(stateW, math.ceil((longest + 4) * stateSize * 0.62))
		end
		-- У громкости колонка — только число «[ 300% ]»: сам ползунок лежит под строкой.
		if item.step then
			stateW = math.ceil(8 * stateSize * 0.62)
		end

		-- Строка громкости — рамка в виде кнопки-призрака: нажимать в ней можно только
		-- ползунок, а Theme.Button требует кнопку.
		local row
		if item.step then
			local ghost = Theme.buttonKind.ghost
			row = Instance.new("Frame")
			row.BackgroundColor3 = ghost.bg
			row.BorderSizePixel = 0
			Theme.Corner(row, Theme.radius.control)
			Theme.Stroke(row, ghost.edge, 1, 0)
		else
			row = Instance.new("TextButton")
			row.Text = ""
			row.AutoButtonColor = true
		end
		row.Name = item.key
		row.LayoutOrder = index
		-- Ширина на восемь пикселей меньше полной: полоса прокрутки ложится поверх
		-- содержимого, а не рядом с ним — тот же запас, что у списков в Theme.GridFit.
		row.Size = UDim2.new(1, -8, 0, item.step and VOLUME_ROW_H or ROW_H)
		row.Parent = list
		if not item.step then
			Theme.Button(row, "ghost")
		end

		local rowLimit = Instance.new("UISizeConstraint")
		rowLimit.MaxSize = Vector2.new(ROW_MAX_W, math.huge)
		rowLimit.Parent = row

		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 12)
		pad.PaddingRight = UDim.new(0, 12)
		pad.PaddingTop = UDim.new(0, 9)
		pad.Parent = row

		local nameLabel = Instance.new("TextLabel")
		nameLabel.Size = UDim2.new(1, -(stateW + 10), 0, mobile and 19 or 21)
		nameLabel.Position = UDim2.new(0, 0, 0, 0)
		nameLabel.BackgroundTransparency = 1
		nameLabel.FontFace = Theme.font.strong
		nameLabel.TextSize = mobile and 15 or 17
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.TextColor3 = Theme.color.text
		nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
		nameLabel.Text = Theme.Caps(item.name)
		nameLabel.Parent = row

		local noteLabel = Instance.new("TextLabel")
		noteLabel.Size = UDim2.new(1, -(stateW + 10), 0, mobile and 30 or 26)
		noteLabel.Position = UDim2.new(0, 0, 0, mobile and 21 or 23)
		noteLabel.BackgroundTransparency = 1
		noteLabel.FontFace = Theme.font.body
		noteLabel.TextSize = mobile and 11 or 12
		noteLabel.TextXAlignment = Enum.TextXAlignment.Left
		noteLabel.TextYAlignment = Enum.TextYAlignment.Top
		noteLabel.TextColor3 = Theme.color.textMute
		noteLabel.TextWrapped = true
		noteLabel.Text = item.note
		noteLabel.Parent = row

		local state = Instance.new("TextLabel")
		if item.step then
			-- Число — в одну строку с названием: под ними ползунок во всю ширину.
			state.Name = "Volume"
			state.AnchorPoint = Vector2.new(1, 0)
			state.Position = UDim2.new(1, 0, 0, 0)
			state.Size = UDim2.new(0, stateW, 0, mobile and 19 or 21)
		else
			state.AnchorPoint = Vector2.new(1, 0.5)
			state.Position = UDim2.new(1, 0, 0.5, -4)
			state.Size = UDim2.new(0, stateW, 0, 26)
		end
		state.BackgroundTransparency = 1
		state.FontFace = Theme.font.strong
		state.TextSize = stateSize
		state.TextXAlignment = Enum.TextXAlignment.Right
		state.Parent = row

		-- Громкость рисуется и по профилю (apply), и на ходу, пока ползунок тянут.
		local show
		-- Нажатие, которое сейчас держит ползунок; nil — ползунок никто не держит.
		local held = nil

		if item.step then
			local slider = Instance.new("Frame")
			slider.Name = "Slider"
			slider.AnchorPoint = Vector2.new(0, 1)
			slider.Position = UDim2.new(0, 0, 1, -10)
			slider.Size = UDim2.new(1, 0, 0, SLIDER_H)
			slider.BackgroundTransparency = 1
			slider.Active = true
			slider.Parent = row

			local kneeAt = item.knee / item.max
			local offNormal = Theme.color.hairline
			local offHyper = Theme.color.danger:Lerp(Theme.color.panel, 0.7)

			-- Черта 100%: правее неё звук громче, чем записан.
			local knee = Instance.new("Frame")
			knee.Name = "Knee"
			knee.Position = UDim2.new(kneeAt, -1, 0, 0)
			knee.Size = UDim2.new(0, 1, 0, METER_H + 6)
			knee.BackgroundColor3 = Theme.color.textMute
			knee.BorderSizePixel = 0
			knee.Parent = slider

			-- Столбик стоит на своём отрезке положения и горит, когда ползунок дошёл
			-- до его середины. Высота — громкость в середине отрезка против громкости
			-- на правом краю.
			local top = UISettings.Gain(item.key, item.max)
			local bars = {}
			for i = 1, BARS do
				local center = (i - 0.5) / BARS * item.max
				local height = (UISettings.Gain(item.key, center) / top) ^ BAR_POWER
				local bar = Instance.new("Frame")
				bar.Name = "Bar" .. i
				bar.AnchorPoint = Vector2.new(0, 1)
				bar.Position = UDim2.new((i - 1) / BARS, 1, 0, METER_H)
				bar.Size = UDim2.new(1 / BARS, -2, 0, math.max(2, math.floor(METER_H * height + 0.5)))
				bar.BorderSizePixel = 0
				bar.Parent = slider
				bars[i] = { frame = bar, center = center, hyper = center > item.knee }
			end

			local rail = Instance.new("Frame")
			rail.Name = "Rail"
			rail.Position = UDim2.new(0, 0, 0, METER_H + 3)
			rail.Size = UDim2.new(1, 0, 0, 2)
			rail.BackgroundColor3 = Theme.color.hairline
			rail.BorderSizePixel = 0
			rail.Parent = slider

			local fill = Instance.new("Frame")
			fill.Name = "Fill"
			fill.BackgroundColor3 = Theme.color.accent
			fill.BorderSizePixel = 0
			fill.Parent = rail

			local hyperFill = Instance.new("Frame")
			hyperFill.Name = "HyperFill"
			hyperFill.Position = UDim2.new(kneeAt, 0, 0, 0)
			hyperFill.BackgroundColor3 = Theme.color.danger
			hyperFill.BorderSizePixel = 0
			hyperFill.Parent = rail

			local thumb = Instance.new("Frame")
			thumb.Name = "Thumb"
			thumb.AnchorPoint = Vector2.new(0.5, 0)
			thumb.Size = UDim2.new(0, 3, 0, METER_H + 7)
			thumb.BackgroundColor3 = Theme.color.text
			thumb.BorderSizePixel = 0
			thumb.ZIndex = 2
			thumb.Parent = slider
			Theme.Stroke(thumb, Theme.color.panel, 1, 0)

			local function caption(text, color, x, width, offset, align)
				local label = Instance.new("TextLabel")
				label.Position = UDim2.new(x, offset, 0, METER_H + 8)
				label.Size = UDim2.new(width, -4, 0, CAPTION_H)
				label.BackgroundTransparency = 1
				label.FontFace = Theme.font.strong
				label.TextSize = 10
				label.TextXAlignment = align
				label.TextColor3 = color
				label.Text = text
				label.Parent = slider
			end
			caption("100%", Theme.color.textMute, 0, kneeAt, 0, Enum.TextXAlignment.Right)
			caption("ГИПЕР", Theme.color.danger, kneeAt, 1 - kneeAt, 4, Enum.TextXAlignment.Left)

			show = function(value)
				for _, bar in bars do
					local lit = bar.center <= value
					if bar.hyper then
						bar.frame.BackgroundColor3 = lit and Theme.color.danger or offHyper
					else
						bar.frame.BackgroundColor3 = lit and Theme.color.accent or offNormal
					end
				end
				fill.Size = UDim2.new(math.min(value, item.knee) / item.max, 0, 1, 0)
				hyperFill.Size = UDim2.new(math.max(0, value - item.knee) / item.max, 0, 1, 0)
				thumb.Position = UDim2.new(value / item.max, 0, 0, -1)

				-- Ноль гасит строку, как выключенный переключатель; «гипер» горит красным,
				-- бирюзой — прочий уход от умолчания.
				state.Text = "[ " .. percentText(UISettings.Gain(item.key, value)) .. " ]"
				state.TextColor3 = value == 0 and Theme.color.textMute
					or value > item.knee and Theme.color.danger
					or (value ~= item.default and Theme.color.accent or Theme.color.text)
				nameLabel.TextColor3 = value == 0 and Theme.color.textDim or Theme.color.text
			end

			local moving = false
			local from = nil
			local shown = nil
			local notch = nil

			local function valueAt(x)
				local width = math.max(slider.AbsoluteSize.X, 1)
				local at = math.clamp((x - slider.AbsolutePosition.X) / width, 0, 1)
				local value = item.min + math.floor((at * item.max - item.min) / item.step + 0.5) * item.step
				if math.abs(value - item.knee) <= KNEE_SNAP then
					value = item.knee
				end
				return math.clamp(value, item.min, item.max)
			end

			local function preview(value)
				if value == shown then
					return
				end
				shown = value
				show(value)
				UISound.Preview(item.key, value)
				local step = math.floor(value / NOTCH)
				if step ~= notch then
					notch = step
					UISound.Play(item.sample, 0.2)
				end
			end

			slider.InputBegan:Connect(function(input)
				if input.UserInputType ~= Enum.UserInputType.MouseButton1
					and input.UserInputType ~= Enum.UserInputType.Touch then
					return
				end
				held = input.UserInputType
				moving = false
				from = input.Position
				shown = nil
				notch = math.floor(Settings.Get(item.key) / NOTCH)
			end)

			UserInputService.InputChanged:Connect(function(input)
				if not held then
					return
				end
				local expected = held == Enum.UserInputType.Touch and Enum.UserInputType.Touch
					or Enum.UserInputType.MouseMovement
				if input.UserInputType ~= expected then
					return
				end
				local dx = math.abs(input.Position.X - from.X)
				local dy = math.abs(input.Position.Y - from.Y)
				if not moving then
					if dy > DRAG_SLOP and dy > dx then
						held = nil -- тянут вверх или вниз: это прокрутка списка
						return
					end
					if dx <= DRAG_SLOP then
						return
					end
					moving = true
				end
				preview(valueAt(input.Position.X))
			end)

			UserInputService.InputEnded:Connect(function(input)
				if not held or input.UserInputType ~= held then
					return
				end
				held = nil
				local value = moving and shown or valueAt(input.Position.X)
				show(value)
				UISound.Preview(item.key, value)
				Settings.Set(item.key, value)
				UISound.Play(item.sample)
			end)
		end

		local function apply()
			local value = Settings.Get(item.key)
			if item.step then
				-- Пока ползунок держат, пришедший профиль не дёргает его назад.
				if not held then
					show(value)
				end
				return
			end
			if item.options then
				-- У выбора выключенного положения нет, гасить нечего: ярким горит только
				-- уход от умолчания — так видно, что игрок поменял сам.
				state.Text = "[ " .. (UISettings.Label(item.key, value) or "?") .. " ]"
				state.TextColor3 = value ~= item.default and Theme.color.accent or Theme.color.text
				nameLabel.TextColor3 = Theme.color.text
				return
			end
			local on = value == true
			state.Text = on and ON_TEXT or OFF_TEXT
			state.TextColor3 = on and Theme.color.accent or Theme.color.textMute
			-- Выключенная настройка гасит и свою подпись: иначе список из трёх строк
			-- одинаковой яркости приходится читать целиком, чтобы понять, что выключено.
			nameLabel.TextColor3 = on and Theme.color.text or Theme.color.textDim
		end

		if not item.step then
			row.MouseButton1Click:Connect(function()
				if Theme.WasDragged(list) then
					return -- пролистнули список пальцем, а не нажали на строку
				end
				Settings.Set(item.key, UISettings.Next(item.key, Settings.Get(item.key)))
			end)
		end

		table.insert(redraw, apply)
		apply()
	end

	local function refresh()
		for _, apply in redraw do
			apply()
		end
	end

	Settings.Changed.Event:Connect(refresh)

	return {
		frame = page,
		-- Подсказка в строке состояния внизу меню — её печатает MainMenu, а текст
		-- знает сам экран: так меню не держит список чужих подсказок.
		status = "Настройки сохраняются в профиле и переживают выход из игры",
		Open = function()
			refresh()
			select(current)
			page.Visible = true
		end,
		Close = function()
			page.Visible = false
		end,
	}
end

return SettingsUI
