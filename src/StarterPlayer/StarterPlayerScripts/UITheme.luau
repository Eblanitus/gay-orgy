-- UITheme — единый визуальный язык клиентского интерфейса: палитра, скругления, шрифты
-- и сборщики «панель / кнопка / строка списка».
--
-- Заведён вместо копий одних и тех же чисел: фон, кант и краска текста были выписаны
-- отдельно в Hud, LobbyUI, InventoryUI, CraftingUI и TowerInteraction — пять одинаковых
-- правок на любое изменение стиля, и по дороге они уже разошлись (фон одной и той же
-- по смыслу кнопки был то 45,45,52, то 60,60,68, то 60,60,65). Правило проекта
-- «данные — в таблицах, а не в коде» здесь ровно про это.
--
-- ЯЗЫК ФОРМЫ — приборный терминал (задача #90, по референсу автора). Почти чёрный фон,
-- кант в один пиксель по краю каждой плашки, моноширинный шрифт, заголовки заглавными
-- с печатной скобкой «>». Скругления почти нет: угол в 2 пикселя читается как срез
-- фаски, а не как мягкая кнопка.
--
-- Цвет сущности больше не заливает ячейку в полную силу (так было до задачи #90):
-- он ушёл в глубоко затемнённый корпус ячейки, в её кант и в вертикальную засечку
-- слева. Опознание цветом осталось прежним, но пропала витринная яркость, из-за которой
-- список элементов читался как набор наклеек, а не как строки показаний. Заодно снялся
-- вопрос краски текста: под надписью теперь всегда темно, какого бы цвета ни был элемент —
-- от Обсидиана (35,30,40) до Воздуха (255,255,255).
--
-- Свечения нет по-прежнему нигде: кант — плотная линия в пиксель, а не ореол. Выбранное
-- состояние показывается яркостью корпуса и засечки (dim у ElementFill), а не обводкой —
-- обведено здесь и так всё.
--
-- Чего сборщики НЕ делают: не трогают Size, Position, AnchorPoint и TextSize. Мобильная
-- раскладка выверена замерами в эмуляторе устройств (STATE.md, задачи #78 и #79) —
-- стиль не имеет права её двигать, иначе кнопка волны снова уедет на родную кнопку
-- прыжка Roblox, а список покупки — за нижний край экрана.
local TweenService = game:GetService("TweenService")
local TextService = game:GetService("TextService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")

-- Настройки из главного меню: сетку на панелях и движение окон можно выключить.
-- Модуль на UITheme не смотрит вовсе — иначе require замкнулся бы в круг.
local Settings = require(script.Parent:WaitForChild("Settings"))

local Theme = {}

-- Холодная сине-серая гамма. Цвет несёт смысл и не смешивается: бирюза — интерфейс
-- и показания, янтарь — всё считаемое (материя, плутоний), красный — отказ и потери,
-- сталь — постройки без выстрела. Оттенки приглушены против первой версии: насыщенный
-- неон рядом с цветами элементов (от Обсидиана до Воздуха) спорил с ними за внимание.
--
-- Фон опущен почти в чёрный против прежних 18,22,30: кант в один пиксель виден только
-- на глубоком фоне, на сером он сливается с плашкой и вся сетка рамок пропадает.
Theme.color = {
	panel = Color3.fromRGB(10, 12, 15), -- фон окна, непрозрачный
	panelSoft = Color3.fromRGB(17, 20, 25), -- вложенная карточка (подтверждение крафта)
	row = Color3.fromRGB(15, 18, 23), -- строка списка
	field = Color3.fromRGB(6, 8, 10), -- поле ввода: глубже фона, чтобы читалось как углубление
	hairline = Color3.fromRGB(46, 55, 66), -- нейтральная граница внутренних плашек
	grid = Color3.fromRGB(72, 104, 112), -- ползущая сетка на фоне панелей
	frame = Color3.fromRGB(56, 104, 100), -- кант окна: приглушённый бирюзовый, не ореол
	accent = Color3.fromRGB(96, 214, 200),
	accentDim = Color3.fromRGB(58, 100, 104),
	action = Color3.fromRGB(64, 190, 148),
	energy = Color3.fromRGB(240, 186, 110),
	danger = Color3.fromRGB(232, 104, 116),
	warn = Color3.fromRGB(236, 172, 92),
	steel = Color3.fromRGB(146, 158, 174),
	info = Color3.fromRGB(124, 162, 236),
	text = Color3.fromRGB(228, 236, 244),
	-- Подписи светлее на 15–20% (просьба автора #219): мелкие «ЗАТРАТЫ», «ШАНС», «МАТЕРИЯ»
	-- терялись на тёмном. Было 146,162,180 и 104,120,138.
	textDim = Color3.fromRGB(168, 186, 207),
	textMute = Color3.fromRGB(125, 144, 166),
	ink = Color3.fromRGB(12, 16, 22), -- текст поверх светлой заливки элемента
}

-- Три размера скругления, а не один на всё: одинаковый радиус у окна и у кнопки внутри
-- него делает вложенность нечитаемой — внутреннее должно быть скруглено слабее внешнего.
-- Все три ужаты почти до угла (было 12/8/3): круглые плашки — язык витрины, а не прибора,
-- и на кнопке с кантом в пиксель крупный радиус первым делом рвёт сам кант в лесенку.
Theme.radius = {
	panel = 4,
	control = 2,
	mark = 2,
}

-- Весь интерфейс — на одном моноширинном шрифте: показания прибора должны стоять
-- в колонку, а у пропорционального Gotham «11/12» и «7/12» разной ширины, и число
-- в HUD дёргалось при каждой волне.
--
-- RobotoMono, а не Code: у Code кириллицы нет вовсе, и русские подписи в нём уходят
-- в подмену пропорциональным шрифтом (замерено: 'ШШШ' 42px против 'ггг' 21px при
-- одинаковых 30px у латиницы — то есть моноширинность на русском теряется целиком).
-- У RobotoMono все четыре замера дают 30 — кириллица своя.
--
-- Разница «жирный / обычный» задаётся начертанием семейства, поэтому оба поля здесь —
-- объекты Font, а не значения Enum.Font, и присваивать их надо в FontFace, не в Font.
local MONO = "rbxasset://fonts/families/RobotoMono.json"
local displayFont = Font.new(MONO, Enum.FontWeight.Bold)

Theme.font = {
	strong = Font.new(MONO, Enum.FontWeight.Bold),
	body = Font.new(MONO, Enum.FontWeight.Regular),
}

local HOVER = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- Твин, который сейчас красит заливку кнопки по наведению — по кнопке, слабая таблица
-- (не атрибут: Tween атрибутом не положить). Без этого старый твин с MouseLeave
-- продолжает играть после того, как paintItems (главное меню) уже перекрасил кнопку
-- в новый цвет напрямую (она зовёт Theme.Button на каждое наведение, чтобы погасить прежнюю
-- выбранную строку), и доиграв поверх заливает прямой сброс обратно в старый цвет
-- — так безобидная подсветка оставалась прилипшей даже после того, как курсор ушёл.
local hoverTweens = setmetatable({}, { __mode = "k" })

local function playHoverTween(button, color)
	local existing = hoverTweens[button]
	if existing then
		existing:Cancel()
	end
	local tween = TweenService:Create(button, HOVER, { BackgroundColor3 = color })
	hoverTweens[button] = tween
	tween:Play()
end

-- ============ Мелочи ============

-- Цвет в вид, который понимает RichText: показания собираются одной строкой, где подпись
-- приглушена, а число светлее, — и это дешевле, чем два TextLabel на каждую строку HUD.
function Theme.Hex(color)
	return ("#%02X%02X%02X"):format(
		math.round(color.R * 255),
		math.round(color.G * 255),
		math.round(color.B * 255)
	)
end

-- Заглавные, включая кириллицу: string.upper в Luau знает только латиницу, и «Огонь»
-- остался бы «Огонь». Сдвигом кодов, а не таблицей: русские строчные лежат в юникоде
-- ровно на 0x20 выше заглавных, как и латиница; исключение одно — «ё».
function Theme.Caps(text)
	local out = {}
	for _, code in utf8.codes(text) do
		if (code >= 97 and code <= 122) or (code >= 0x430 and code <= 0x44F) then
			code -= 32
		elseif code == 0x451 then -- ё
			code = 0x401
		end
		table.insert(out, utf8.char(code))
	end
	return table.concat(out)
end

-- Читаемая версия цвета элемента — для тонких деталей на тёмном: засечки, канта, цифры.
-- Обсидиан (35,30,40) сам по себе на почти чёрном фоне не виден вовсе, а разбавлять
-- все цвета подряд нельзя — Воздух (255,255,255) стал бы белее белого. Поднимается
-- только то, что темнее половины яркости, и ровно настолько, насколько не дотягивает.
function Theme.Legible(color)
	local lum = 0.299 * color.R + 0.587 * color.G + 0.114 * color.B
	if lum >= 0.5 then
		return color
	end
	return color:Lerp(Color3.new(1, 1, 1), (0.5 - lum) * 1.25)
end

-- Скругление. Существующий UICorner переиспользуется, а не добавляется вторым: сборщики
-- зовутся повторно (слот крафта перекрашивается на каждый выбор элемента), и без этого
-- на одном объекте копились бы дубликаты.
function Theme.Corner(inst, radius)
	local corner = inst:FindFirstChildOfClass("UICorner")
	if not corner then
		corner = Instance.new("UICorner")
		corner.Parent = inst
	end
	corner.CornerRadius = UDim.new(0, radius or Theme.radius.control)
	return corner
end

function Theme.Stroke(inst, color, thickness, transparency)
	local stroke = inst:FindFirstChildOfClass("UIStroke")
	if not stroke then
		stroke = Instance.new("UIStroke")
		stroke.Parent = inst
	end
	stroke.Color = color
	stroke.Thickness = thickness
	stroke.Transparency = transparency
	return stroke
end

-- Нейтральный волосок по краю: показывает границу плашки, ничего не подсвечивая.
function Theme.Hairline(inst, transparency)
	return Theme.Stroke(inst, Theme.color.hairline, 1, transparency or 0.4)
end

local function clearDecor(inst)
	local stroke = inst:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke:Destroy()
	end
	local gradient = inst:FindFirstChildOfClass("UIGradient")
	if gradient then
		gradient:Destroy()
	end
end

-- ============ Выход за внутренний отступ ============

-- UIPadding сдвигает ВСЕХ детей без исключения — в том числе те кадры, которым положено
-- доходить до настоящего края окна: фон-решётку, цветную дымку и засечку элемента.
-- Замерено на подсказке стройки: сама строка 659,12 размером 596x28, а её дымка и засечка —
-- 669,12 и 576 в ширину. То есть по обоим концам плашки оставались тёмные полоски
-- в десять пикселей, а засечка висела не у края, а поверх первого слова.
--
-- Отступ читается ЗАНОВО при каждом пересчёте, а не в момент вызова: сборщики темы
-- зовут сразу за Corner и Stroke, то есть ДО того, как окну поставили UIPadding
-- (в TowerInteraction ElementFill стоит на шесть строк раньше самого отступа).
-- Прочитанные в тот момент нули замерли бы навсегда.
--
-- pos и size — то, чем кадр должен быть относительно ПОЛНОГО окна. Их передаёт сборщик,
-- а не читает отсюда сам кадр: собственные Position и Size к этому времени уже могут
-- нести поправку с прошлого раза, и она удвоилась бы.
local bleedBase = setmetatable({}, { __mode = "k" })

function Theme.Bleed(child, pos, size)
	local parent = child.Parent
	if not parent or not parent:IsA("GuiObject") then
		return child
	end

	local base = bleedBase[child]
	if not base then
		base = { pos = pos or child.Position, size = size or child.Size }
		bleedBase[child] = base
	else
		base.pos = pos or base.pos
		base.size = size or base.size
	end

	local function place()
		local ps = parent.AbsoluteSize
		local pad = parent:FindFirstChildOfClass("UIPadding")
		local l, t, r, b = 0, 0, 0, 0
		if pad then
			l = pad.PaddingLeft.Scale * ps.X + pad.PaddingLeft.Offset
			r = pad.PaddingRight.Scale * ps.X + pad.PaddingRight.Offset
			t = pad.PaddingTop.Scale * ps.Y + pad.PaddingTop.Offset
			b = pad.PaddingBottom.Scale * ps.Y + pad.PaddingBottom.Offset
		end
		-- Внутренняя коробка уже полной на (l+r) по ширине, и доля, отсчитанная от неё,
		-- даёт не то место: к доле добавляется её же часть от разницы, а начало кадра
		-- сдвигается назад на левый отступ. Для доли 0 это ровно «минус отступ»,
		-- для доли 1 — «плюс правый отступ», то есть оба края встают на место сами.
		-- У панели, растущей по содержимому (AutomaticSize), по растущей оси кадр не
		-- расширяется и за правый/нижний отступ не выносится: и то и другое — доля от размера
		-- самой панели, панель растёт за кадром, кадр за панелью, и так по кругу (тот же круг,
		-- что у решётки на карточке плутония, см. Theme.Backdrop). Сдвиг к левому и верхнему
		-- краю остаётся — он в пикселях и размера панели не трогает.
		local auto = parent.AutomaticSize
		local autoX = auto == Enum.AutomaticSize.X or auto == Enum.AutomaticSize.XY
		local autoY = auto == Enum.AutomaticSize.Y or auto == Enum.AutomaticSize.XY
		local bp, bs = base.pos, base.size
		local wide = autoX and 0 or l + r
		local tall = autoY and 0 or t + b
		local shiftX = autoX and l * (1 - bp.X.Scale) or l
		local shiftY = autoY and t * (1 - bp.Y.Scale) or t
		local np = UDim2.new(
			bp.X.Scale, bp.X.Offset + bp.X.Scale * wide - shiftX,
			bp.Y.Scale, bp.Y.Offset + bp.Y.Scale * tall - shiftY
		)
		local ns = UDim2.new(
			bs.X.Scale, bs.X.Offset + bs.X.Scale * wide,
			bs.Y.Scale, bs.Y.Offset + bs.Y.Scale * tall
		)
		if child.Position ~= np then
			child.Position = np
		end
		if child.Size ~= ns then
			child.Size = ns
		end
	end

	place()
	task.defer(place) -- отступ могли поставить в той же строке кода, что и сам кадр
	if not child:GetAttribute("BleedWatch") then
		child:SetAttribute("BleedWatch", true)
		parent:GetPropertyChangedSignal("AbsoluteSize"):Connect(place)
		parent:GetPropertyChangedSignal("AutomaticSize"):Connect(place)
		parent.ChildAdded:Connect(function(inst)
			if inst:IsA("UIPadding") then
				place()
			end
		end)
	end
	return child
end

-- Панель: фон-соты и сцены, точки, скобки, перетаскивание списков, Theme.Panel — в модуле UIThemePanel.
require(script.Parent:WaitForChild("UIThemePanel"))({Theme = Theme, Settings = Settings, RunService = RunService, UserInputService = UserInputService})
-- Кнопки, образцы и заливка элементов, паттерны, сетки, поле ввода (Theme.Button, Theme.Pattern, Theme.Grid…) — в модуле UIThemeButtons.
require(script.Parent:WaitForChild("UIThemeButtons"))({Theme = Theme, Settings = Settings, clearDecor = clearDecor, hoverTweens = hoverTweens, playHoverTween = playHoverTween})
-- ============ Текст ============

-- Приборный шрифт без прочих украшений — для показаний HUD и баннера итога.
function Theme.Display(textObject)
	textObject.FontFace = displayFont
	return textObject
end

-- Заголовок окна: заглавными и с печатной скобкой «>» — строка приглашения, а не название
-- раздела. Прежняя вертикальная засечка-Frame слева сносится: маркер теперь печатный
-- знак внутри самой строки, и два маркера подряд читались бы как мусор.
-- У центрированного заголовка скобки нет: она отмечает начало строки, а не середину.
function Theme.Title(label, color)
	Theme.Display(label)
	label.TextColor3 = color or Theme.color.text
	local mark = label:FindFirstChild("Mark")
	if mark then
		mark:Destroy()
	end
	local text = Theme.Caps(label.Text)
	if label.TextXAlignment == Enum.TextXAlignment.Left and text:sub(1, 1) ~= ">" then
		text = "> " .. text
	end
	label.Text = text
	return label
end

-- Показание прибора одной строкой. Подпись не просто приглушена, а напечатана
-- вдвое мельче числа: в референсе подпись у числа почти не видна, и первым
-- читается значение, а не то, как оно называется. Размер задан в самом теге,
-- потому что второго TextLabel ради двух кеглей заводить ни к чему.
-- Требует label.RichText = true у вызывающего.
function Theme.Readout(caption, value, valueColor, captionSize)
	return ('<font size="%d" color="%s">%s</font>  <font color="%s">%s</font>'):format(
		captionSize or 11,
		Theme.Hex(Theme.color.textMute),
		Theme.Caps(caption),
		Theme.Hex(valueColor or Theme.color.accent),
		value
	)
end

-- Подпись раздела: «ЭЛЕМЕНТЫ // 3» мелкими заглавными, а дальше до правого края —
-- тонкая линия. Линия начинается по замеру текста, а не по угаданному отступу:
-- число в подписи меняется (рецептов открыто 0 или 35), и фиксированный отступ
-- то рвал бы линию по тексту, то оставлял дыру.
--
-- Замер через Enum.Font.RobotoMono, а не через FontFace: GetTextSize другого не принимает,
-- а шаг у моноширинного шрифта один и тот же у любого начертания.
function Theme.Section(label, caption, note)
	label.FontFace = Theme.font.body
	label.BackgroundTransparency = 1
	label.TextColor3 = Theme.color.textMute
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = note ~= nil
		and ("%s  //  %s"):format(Theme.Caps(caption), Theme.Caps(tostring(note)))
		or Theme.Caps(caption)

	local rule = label:FindFirstChild("Rule")
	if not rule then
		rule = Instance.new("Frame")
		rule.Name = "Rule"
		rule.BorderSizePixel = 0
		rule.AnchorPoint = Vector2.new(0, 0.5)
		rule.Parent = label
	end
	local width = TextService:GetTextSize(
		label.Text, label.TextSize, Enum.Font.RobotoMono, Vector2.new(9999, 100)
	).X
	rule.BackgroundColor3 = Theme.color.hairline
	rule.BackgroundTransparency = 0.3
	rule.Position = UDim2.new(0, width + 10, 0.5, 1)
	rule.Size = UDim2.new(1, -(width + 10), 0, 1)
	rule.ZIndex = label.ZIndex
	return label
end

-- Подпись над числом в столбике («ЦЕНА» над «10») и само число. Геометрию задаёт
-- вызывающий — высоты строк выверены под каждый список отдельно.
function Theme.StatCaption(label)
	label.FontFace = Theme.font.body
	label.BackgroundTransparency = 1
	label.TextColor3 = Theme.color.textMute
	label.TextTruncate = Enum.TextTruncate.AtEnd
	return label
end

function Theme.StatValue(label, color)
	label.FontFace = Theme.font.strong
	label.BackgroundTransparency = 1
	label.TextColor3 = color or Theme.color.text
	label.TextTruncate = Enum.TextTruncate.AtEnd
	return label
end

-- Горизонтальная линия в пиксель — тем же волоском, что и канты. Отделяет шапку
-- окна от содержимого и содержимое от статусной строки внизу.
function Theme.Rule(frame)
	frame.BackgroundColor3 = Theme.color.hairline
	frame.BackgroundTransparency = 0.3
	frame.BorderSizePixel = 0
	return frame
end

-- Статусная строка по низу окна: слева — раздел заглавными, через «//» — то, что
-- сейчас можно сделать. Подсказки раньше стояли внутри вкладок и отъедали высоту
-- у списков; в одной строке внизу они ещё и находятся всегда на одном месте.
function Theme.Status(label, section, detail)
	label.FontFace = Theme.font.body
	label.BackgroundTransparency = 1
	label.RichText = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextColor3 = Theme.color.textMute
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Text = ('<font color="%s">%s  //</font>  %s'):format(
		Theme.Hex(Theme.color.accentDim),
		Theme.Caps(section),
		detail
	)
	return label
end

-- ============ Движение ============

-- Окно не появляется рывком, а вырастает из 96% за одну шестую секунды. Масштаб берётся
-- UIScale, а не правкой Size: высоту окон считают их собственные applyHeight по числу
-- строк, и анимация размера дралась бы с ними за одно и то же свойство.
function Theme.Open(frame)
	if not Settings.Get("uiMotion") then
		-- Окно открывается сразу в полный размер. Масштаб всё равно возвращается к единице:
		-- выключив движение посреди анимации, иначе можно оставить окно навсегда чуть меньше нужного.
		local kept = frame:FindFirstChild("OpenScale")
		if kept then
			kept.Scale = 1
		end
		return
	end

	local scale = frame:FindFirstChild("OpenScale")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Name = "OpenScale"
		scale.Parent = frame
	end
	scale.Scale = 0.96
	TweenService:Create(scale, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Scale = 1,
	}):Play()
end

-- Короткая вспышка строки, когда её число изменилось: на панели забега три показания,
-- и без этого прирост материи проходит мимо взгляда. Через прозрачность, а не через цвет —
-- цвет внутри строки задаёт сам RichText, и перекрасить её целиком нечем.
function Theme.Blink(label)
	if not Settings.Get("uiMotion") then
		label.TextTransparency = 0 -- без вспышки, но и не полупрозрачным навсегда
		return
	end
	label.TextTransparency = 0.55
	TweenService:Create(label, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		TextTransparency = 0,
	}):Play()
end

-- ============ Помеха при смене экрана ============

-- Просьба автора: «оооочень небольшой эффект шума на весь планшет — после того как
-- меняешь экран». Экран не перещёлкивается молча, а проходит короткой помехой: на долю
-- секунды поверх всего интерфейса — россыпь светлых точек и чёрточек развёртки и едва
-- заметная засветка, гаснущие к концу вспышки.
--
-- Точки разбрасываются заново в каждом кадре: застывшая россыпь читается как грязь
-- на стекле, а не как шум. Кадров постоянное число, они заводятся один раз и живут
-- в своём ScreenGui, выключенном между вспышками.
--
-- При снятой настройке «Движение интерфейса» (uiMotion) помехи нет вовсе.
local STATIC = {
	order = 10000, -- поверх всех слоёв MobileUI.Layer (самый верхний из них — 200)
	specks = 240,
	time = 0.16, -- секунды
	speck = 0.16, -- сила самой яркой точки в начале вспышки (не прозрачность)
	veil = 0.03, -- сила засветки всего экрана в начале вспышки
}

local staticGui, staticVeil, staticSpecks, staticConn
local staticUntil = 0

function Theme.Static()
	if not Settings.Get("uiMotion") then
		return
	end
	local player = game:GetService("Players").LocalPlayer
	local playerGui = player and player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return
	end

	if not staticGui or not staticGui.Parent then
		staticGui = Instance.new("ScreenGui")
		staticGui.Name = "ThemeStatic"
		staticGui.IgnoreGuiInset = true
		staticGui.ResetOnSpawn = false
		staticGui.DisplayOrder = STATIC.order
		staticGui.Enabled = false
		staticGui.Parent = playerGui

		-- Active у всех кадров остаётся false (так у Frame по умолчанию): помеха лежит
		-- поверх кнопок и не должна съедать по ним нажатие.
		staticVeil = Instance.new("Frame")
		staticVeil.Name = "Veil"
		staticVeil.BorderSizePixel = 0
		staticVeil.Size = UDim2.new(1, 0, 1, 0)
		staticVeil.BackgroundColor3 = Theme.color.accent
		staticVeil.BackgroundTransparency = 1
		staticVeil.Parent = staticGui

		staticSpecks = {}
		for i = 1, STATIC.specks do
			local speck = Instance.new("Frame")
			speck.BorderSizePixel = 0
			speck.BackgroundColor3 = Theme.color.text
			speck.BackgroundTransparency = 1
			speck.Parent = staticGui
			staticSpecks[i] = speck
		end
	end

	-- Повторный вызов посреди вспышки не заводит второй счёт, а начинает ту же вспышку
	-- сначала: главное меню при открытии и открывает окно, и показывает страницу.
	staticUntil = os.clock() + STATIC.time
	staticGui.Enabled = true
	if staticConn then
		return
	end
	staticConn = RunService.RenderStepped:Connect(function()
		local left = staticUntil - os.clock()
		if left <= 0 then
			staticConn:Disconnect()
			staticConn = nil
			staticGui.Enabled = false
			return
		end
		local k = left / STATIC.time
		local view = staticGui.AbsoluteSize
		staticVeil.BackgroundTransparency = 1 - STATIC.veil * k
		for _, speck in staticSpecks do
			-- Каждая пятая — чёрточка строки развёртки, остальные — точки в пиксель-два.
			if math.random() < 0.2 then
				speck.Size = UDim2.fromOffset(math.random(6, 28), 1)
			else
				speck.Size = UDim2.fromOffset(math.random(1, 2), math.random(1, 2))
			end
			speck.Position = UDim2.fromOffset(math.random() * view.X, math.random() * view.Y)
			speck.BackgroundTransparency = 1 - STATIC.speck * k * math.random()
		end
	end)
end

-- ============ Крестик ============

-- Крестик закрытия — две линии накрест, а не буква. Латинская X моноширинного шрифта
-- темы — толстые штрихи с засечками, и на кнопке она читалась надписью из другого
-- интерфейса (замечание автора: «не вписывается будто в терминал наш»). Знака ✕ в наборе
-- шрифта нет вовсе: он рисовался пустым прямоугольником (см. WaveEditorUI).
--
-- Цвет — отказ, как и прежде: на телефоне крестик — единственный выход из окна, и тихая
-- кнопка там читалась как буква в воздухе. Но не сплошной красной плашкой, а языком
-- ячеек: тёмный корпус этого цвета, кант потемнее и сам знак в полную силу.
function Theme.CloseButton(button)
	Theme.Button(button, "quiet")
	local body = Theme.Shadowed(Theme.color.danger, 0.84)
	button.BackgroundColor3 = body
	button:SetAttribute("ThemeBase", body)
	button.Text = ""
	local edge = button:FindFirstChildOfClass("UIStroke")
	if edge then
		edge.Color = Theme.Shadowed(Theme.color.danger, 0.4)
	end

	local cross = button:FindFirstChild("Cross")
	if not cross then
		cross = Instance.new("Frame")
		cross.Name = "Cross"
		cross.BackgroundTransparency = 1
		cross.BorderSizePixel = 0
		cross.Size = UDim2.new(1, 0, 1, 0)
		cross.Parent = button
	end
	-- Знак на слой выше кнопки: в окнах с ZIndexBehavior.Global ребёнок с меньшим ZIndex
	-- рисуется ПОД родителем, и крестик в Лаборатории пропадал целиком.
	cross.ZIndex = button.ZIndex + 1

	local bars = {}
	for index, rotation in { 45, -45 } do
		local bar = cross:FindFirstChild("Bar" .. index)
		if not bar then
			bar = Instance.new("Frame")
			bar.Name = "Bar" .. index
			bar.BorderSizePixel = 0
			bar.Parent = cross
		end
		bar.AnchorPoint = Vector2.new(0.5, 0.5)
		bar.Position = UDim2.new(0.5, 0, 0.5, 0)
		bar.Rotation = rotation
		bar.BackgroundColor3 = Theme.color.danger
		bar.BackgroundTransparency = 0
		bar.ZIndex = cross.ZIndex
		bars[index] = bar
	end

	-- Размер знака — от стороны кнопки в пикселях до масштаба (Size, а не AbsoluteSize):
	-- окна открываются через UIScale, и замер посреди открытия дал бы знак мельче.
	-- Толщина в два пикселя — только у пальцевой кнопки телефона: линия в пиксель
	-- на экране высокой плотности там пропадает.
	local function place()
		local size = button.Size
		local side = math.min(size.X.Offset, size.Y.Offset)
		if size.X.Scale ~= 0 or size.Y.Scale ~= 0 then
			local abs = button.AbsoluteSize
			side = math.min(abs.X, abs.Y)
		end
		local arm = math.floor(side * 0.52 + 0.5)
		local thick = side >= 40 and 2 or 1
		for _, bar in bars do
			bar.Size = UDim2.fromOffset(arm, thick)
		end
	end
	place()
	if not button:GetAttribute("CrossWatch") then
		button:SetAttribute("CrossWatch", true)
		button:GetPropertyChangedSignal("Size"):Connect(place)
		-- ZIndex кнопке окна часто ставят уже после оформления — знак идёт следом.
		button:GetPropertyChangedSignal("ZIndex"):Connect(function()
			cross.ZIndex = button.ZIndex + 1
			for _, bar in bars do
				bar.ZIndex = cross.ZIndex
			end
		end)
		-- Наведение зажигает и сам знак, а не только заливку (её осветляет Theme.Button).
		local lit = Theme.color.danger:Lerp(Color3.new(1, 1, 1), 0.4)
		button.MouseEnter:Connect(function()
			for _, bar in bars do
				TweenService:Create(bar, HOVER, { BackgroundColor3 = lit }):Play()
			end
		end)
		button.MouseLeave:Connect(function()
			for _, bar in bars do
				TweenService:Create(bar, HOVER, { BackgroundColor3 = Theme.color.danger }):Play()
			end
		end)
	end
	return button
end

return Theme
