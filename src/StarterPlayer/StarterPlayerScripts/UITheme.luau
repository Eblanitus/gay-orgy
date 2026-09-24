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

-- ============ Панель ============

-- ФОН — соты. Шестигранник в этой игре не украшение: это клетка арены, её рисует
-- подсветка постройки (TowerInteraction.rebuildHexWedges — шесть клиньев через 60°,
-- рёбра по бокам, вершина вверх), и решётка окна собрана из той же фигуры и в той же
-- ориентации.
--
-- Прошлая решётка была двумя семействами прямых под ±60°, и автор назвал её тем, чем
-- она и была: рубашкой игральных карт. Два семейства прямых дают ромбы, а не соты;
-- шестигранник приходится собирать рёбрами — по три на клетку, остальные три у неё
-- общие с соседями (правое вертикальное ребро клетки — это левое ребро соседа справа,
-- верхние наклонные — нижние у верхних соседей). Рисовать все шесть значит провести
-- каждую линию решётки дважды и удвоить ей яркость.
--
-- ГЛУБИНА. У каждой панели своя, по её месту в стопке окон: 0 — самое дальнее
-- (журнал Лаборатории лежит под всем остальным), 1 — самое близкое (карточка
-- подтверждения крафта — поверх всего). Чем ближе, тем клетка мельче, линия светлее
-- и ход быстрее — тот же закон, что у параллакса за окном поезда.
--
-- КРАЙ. Обрезать решётку в Roblox нечем. Что ClipsDescendants не режет повёрнутые
-- кадры — было известно и раньше; но CanvasGroup их не режет ТОЖЕ, хотя рисует детей
-- в собственный буфер. Проверено прямым опытом: две одинаковые наклонные линии, одна
-- в CanvasGroup, другая в обычном фрейме с ClipsDescendants, вышли за свою плашку
-- одинаково — обе через весь экран. До этой проверки решётка панели забега 232x72
-- расписывала полнеба, и это первое, что увидел автор.
--
-- Поэтому решётка режется СЧЁТОМ. У каждого ребра известны центр, единичное направление
-- вдоль длины и половина длины; отрезок пересекается с прямоугольником панели по
-- параметру вдоль самого себя, и ребру, задевшему край, переписываются середина и длина —
-- оно кончается ровно на канте. Целиком вылезшее гасится.
--
-- До задачи #129 рёбра не резались, а гасли к краям, и поле сот растворялось, не доходя
-- до канта. Замечание автора: «фон не заходит за рамки. Это ухудшает атмосферу. Если
-- шестиугольники будут за рамкой, будет ощущение что они бесконечные». Растворение
-- читается как край нарисованной текстуры; срез по канту — как окно в поле, которое
-- продолжается и за окном.
Theme.depth = {
	journal = 0, -- Лаборатория с журналом — самое дно стопки
	window = 0.2, -- инвентарь: тоже окно, но открывается поверх игры
	hud = 0.45, -- панель забега и прочее поверх арены
	dialog = 0.7, -- выбор заливки, карточка плутония, промокод
	top = 1, -- подтверждение крафта — поверх всего
}

-- ОБСТАНОВКА. Решётка была одна на все окна, и любой экран читался одинаково —
-- замечание автора: «сейчас в любом фоне, просто шестиугольники и темнота».
-- Здесь на каждую ситуацию своя: размер клетки, цвет, сила линии, ход и опрос.
-- Это таблица, а не разветвление в коде: новая ситуация добавляется строкой.
--
-- cell — радиус клетки в пикселях (потолок — половина короткой стороны панели);
-- line — сила линии до опроса;
-- tint — цвет рёбер;
-- drift — ход по вертикали в пикселях в секунду, МИНУС значит вверх;
-- driftX — ход по горизонтали, МИНУС значит влево; без него решётка едет только
--   по вертикали, а с ним вместе с drift — по диагонали;
-- pulse — сколько кругов волны опроса в секунду;
-- wave — насколько волна поднимает яркость в самой гуще;
-- sheen — прозрачность перепада яркости стекла в самой сильной точке;
-- at — где этот перепад стоит: 0 — вверху панели, 1 — внизу;
-- far — во сколько раз крупнее клетка дальнего слоя; без него — Theme.BACKDROP_FAR.
Theme.scene = {
	-- Главное меню: самая крупная клетка и медленный ход — за меню нет ничего.
	menu = { cell = 128, line = 0.075, tint = Theme.color.grid, drift = 4, pulse = 0.05, wave = 0.26, sheen = 0.955, at = 0, far = 2.2 },
	-- Журнал: мелкая частая сетка почти без хода — страница записей, а не прибор.
	journal = { cell = 58, line = 0.06, tint = Theme.color.steel, drift = 1.2, pulse = 0.03, wave = 0.12, sheen = 0.965, at = 0 },
	-- Настройки: та же комната, но ход развёрнут вверх и перепад ушёл вниз —
	-- смена страницы видна сразу, ещё до того как прочитан заголовок.
	settings = { cell = 96, line = 0.07, tint = Theme.color.info, drift = -3, pulse = 0.045, wave = 0.2, sheen = 0.96, at = 1 },
	-- Лаборатория: самая крупная и самая спокойная — карта рецептов и так пёстрая.
	lab = { cell = 150, line = 0.055, tint = Theme.color.grid, drift = 2, pulse = 0.035, wave = 0.16, sheen = 0.96, at = 0, far = 2 },
	-- Инвентарь: окно поверх игры, ход заметнее меню.
	inventory = { cell = 84, line = 0.08, tint = Theme.color.steel, drift = 5, pulse = 0.06, wave = 0.24, sheen = 0.955, at = 0 },
	-- Панель забега: мелко, быстро и с сильным опросом — прибор под нагрузкой.
	run = { cell = 46, line = 0.13, tint = Theme.color.accentDim, drift = 12, pulse = 0.13, wave = 0.34, sheen = 0.95, at = 0 },
	-- Диалог поверх игры: карточка плутония, промокод.
	dialog = { cell = 62, line = 0.12, tint = Theme.color.accentDim, drift = 9, pulse = 0.1, wave = 0.3, sheen = 0.95, at = 0 },
	-- Выбор заливки турели: зелень действия — сейчас что-то поставят на поле.
	build = { cell = 54, line = 0.13, tint = Theme.color.action, drift = 10, pulse = 0.12, wave = 0.32, sheen = 0.95, at = 0 },
	-- Подтверждение крафта: янтарь и самый быстрый ход — минута решения.
	confirm = { cell = 40, line = 0.16, tint = Theme.color.energy, drift = 16, pulse = 0.18, wave = 0.38, sheen = 0.94, at = 0 },
	-- Вкладка «Купить»: янтарь — здесь тратится материя, а всё считаемое в игре этого цвета.
	shop = { cell = 76, line = 0.065, tint = Theme.color.energy, drift = 3, pulse = 0.05, wave = 0.2, sheen = 0.955, at = 0 },
	-- Вкладка «Крафт»: зелень действия и ход вверх — из двух элементов собирается третий.
	craft = { cell = 104, line = 0.07, tint = Theme.color.action, drift = -2.5, pulse = 0.055, wave = 0.22, sheen = 0.955, at = 1 },
	-- Редактор волн: служебное окно, синь показаний.
	editor = { cell = 72, line = 0.1, tint = Theme.color.info, drift = 6, pulse = 0.07, wave = 0.26, sheen = 0.955, at = 0 },
}

-- Числовая глубина из Theme.depth (вызовы, которые ещё не назвали свою ситуацию)
-- превращается в обстановку теми же формулами, что стояли внутри Theme.Backdrop
-- до задачи #129: ни одно такое окно вида не меняет.
-- ГЛУБИНА ФОНА (просьба автора, #221): «дальше от игрока — больше, тусклее и
-- непримечательнее, ближе — примечательнее». Это закон для всех окон сразу, а не
-- своя решётка на каждое: под сотами обстановки лежит тот же рисунок, крупнее во
-- столько-то раз, бледнее и медленнее. Заметен ближний слой, дальний только даёт
-- ощущение, что поле уходит вглубь. Плашке, на которой крупной клетке негде
-- поместиться целиком, дальний слой не даётся: он совпал бы с ближним.
Theme.BACKDROP_FAR = 2.2 -- во сколько раз крупнее клетка дальнего слоя
Theme.BACKDROP_FAR_LINE = 0.45 -- доля силы линии и волны опроса
Theme.BACKDROP_FAR_SPEED = 0.5 -- доля хода: дальнее едет медленнее, как за окном поезда

local function sceneOf(name)
	if type(name) == "table" then
		return name
	end
	if type(name) == "string" then
		return Theme.scene[name] or Theme.scene.menu
	end
	local depth = math.clamp(tonumber(name) or Theme.depth.window, 0, 1)
	return {
		cell = 130 - 86 * depth,
		line = 0.05 + 0.13 * depth,
		tint = Theme.color.grid,
		drift = 1.5 + 13 * depth,
		pulse = 0.055 + 0.075 * depth,
		wave = 0.3,
		sheen = 0.955,
		at = 0,
	}
end

-- Все решётки игры ведёт одна подписка на Heartbeat: свой цикл на каждое окно — это
-- пять циклов ради одного числа.
local layers = {}

-- Настройка «Сетка на панелях». Уже построенные решётки гасятся, а не перестают
-- строиться: к моменту переключения они висят во всех уже собранных окнах,
-- и «не строить новые» на экране не изменило бы ничего.
local gridEnabled = Settings.Get("panelGrid")

Settings.Changed.Event:Connect(function(key, value)
	if key ~= "panelGrid" then
		return
	end
	gridEnabled = value
	for holder in layers do
		holder.Visible = value
	end
end)

-- Волна опроса, идущая по сотам сверху вниз. Ни одного нового кадра не заводит: это
-- слагаемое к яркости тех же рёбер, что и так пересчитываются каждый кадр. Без неё
-- решётка ровно одной и той же яркости по всей панели и читается как напечатанная
-- текстура; с ней поле сот выглядит опрашиваемым, а не нарисованным.
--
-- Ширина и сила взяты так, чтобы волна была заметна краем глаза и никогда не спорила
-- с текстом поверх неё: даже в самой гуще ребро остаётся прозрачнее половины.
local PULSE_SPAN = 0.26 -- полуширина волны в долях высоты панели

RunService.Heartbeat:Connect(function(dt)
	for holder, state in layers do
		if not holder.Parent then
			layers[holder] = nil -- окно снесли — слой уходит из списка сам
		-- Снятая настройка отключает счёт, но не уборку снесённых слоёв выше:
		-- иначе за время с выключенной сеткой в списке копились бы мёртвые записи.
		elseif gridEnabled and state.frame.Visible then
			-- Ход замыкается на 3R — это вертикальный период сот: соседние строки клеток
			-- сдвинуты по горизонтали на полклетки, и рисунок повторяет себя только через
			-- две строки. Замкни его на 1.5R — решётка прыгала бы вбок на каждом круге.
			--
			-- Ход вверх — это отрицательная скорость, и никакой отдельной ветки ему
			-- не нужно: остаток от деления в Luau всегда неотрицателен, поэтому фаза
			-- при убывании перескакивает через тот же самый период.
			state.phase = (state.phase + dt * state.speed) % state.period
			local offset = state.phase - state.period
			-- Вбок ход замыкается на ширину клетки 2·R·cos 30°: через неё ряд повторяет себя.
			local slide = state.speedX ~= 0
			local offsetX = 0
			if slide then
				state.phaseX = (state.phaseX + dt * state.speedX) % state.periodX
				offsetX = state.phaseX - state.periodX
			end
			holder.Position = UDim2.new(0, offsetX, 0, offset)
			local width = state.width

			local height = state.height
			-- Волна заходит выше панели и уходит ниже неё, чтобы не зарождаться
			-- и не гаснуть прямо на виду.
			state.pulse = (state.pulse + dt * state.pulseSpeed) % 1
			local pulseAt = (state.pulse * (1 + PULSE_SPAN * 2) - PULSE_SPAN) * height
			local pulseHalf = height * PULSE_SPAN
			local gain = state.wave

			for i, seg in state.segs do
				-- ---- срез по верхнему и нижнему краю ----
				-- Слева и справа края не двигаются, и там всё посчитано при сборке
				-- (tx0..tx1). Сверху и снизу решётка едет, и пересечение считается
				-- каждый кадр — по тому же параметру вдоль отрезка.
				local uy = state.uy[i]
				local cy = state.cy[i] + offset
				local t0, t1 = state.tx0[i], state.tx1[i]
				local ya, yb = (0 - cy) / uy, (height - cy) / uy
				if ya > yb then
					ya, yb = yb, ya
				end
				if ya > t0 then
					t0 = ya
				end
				if yb < t1 then
					t1 = yb
				end
				-- Решётка, едущая вбок, режется и по боковым краям — каждый кадр,
				-- так же как по верхнему и нижнему.
				if slide then
					local ux = state.ux[i]
					local cx = state.cx[i] + offsetX
					if ux ~= 0 then
						local xa, xb = (0 - cx) / ux, (width - cx) / ux
						if xa > xb then
							xa, xb = xb, xa
						end
						if xa > t0 then
							t0 = xa
						end
						if xb < t1 then
							t1 = xb
						end
					elseif cx < 0 or cx > width then
						t1 = t0
					end
				end

				if t1 - t0 < 1 then
					-- Ребро целиком за краем панели: гасим и больше о нём не думаем.
					if state.shown[i] then
						state.shown[i] = false
						seg.Visible = false
					end
				else
					if not state.shown[i] then
						state.shown[i] = true
						seg.Visible = true
					end
					-- Целое ребро возвращается к своей исходной геометрии одним
					-- присваиванием, а не пересчётом: у краёв панели урезанных рёбер
					-- меньшинство, а в середине целы почти все.
					if t0 <= state.tx0[i] + 0.01 and t1 >= state.tx1[i] - 0.01 then
						if state.cut[i] then
							state.cut[i] = false
							seg.Position = state.pos[i]
							seg.Size = state.size[i]
						end
					else
						state.cut[i] = true
						local mid = (t0 + t1) / 2
						local len = t1 - t0
						-- Середина считается в координатах слоя, а не панели: сам сдвиг
						-- слоя уже стоит в holder.Position, и прибавить его второй раз
						-- значило бы услать урезанное ребро вдвое дальше.
						seg.Position = UDim2.new(
							0, state.cx[i] + state.ux[i] * mid,
							0, state.cy[i] + uy * mid
						)
						seg.Size = state.tall[i] and UDim2.fromOffset(1, len) or UDim2.fromOffset(len, 1)
					end

					local off = math.abs(cy - pulseAt)
					local wave = off < pulseHalf and (1 - off / pulseHalf) or 0
					local t = 1 - math.min(state.base[i] + gain * wave * wave, 0.55)
					-- Пишем только изменившимся: вне волны прозрачность постоянна,
					-- а таких рёбер большая часть.
					if math.abs(t - state.last[i]) > 0.004 then
						state.last[i] = t
						seg.BackgroundTransparency = t
					end
				end
			end
		end
	end
end)

-- Обстановка каждой панели лежит при самой панели: Theme.SetScene меняет её у уже
-- собранной, не зная, кто и с какими параметрами эту панель собирал. Ключи слабые —
-- снесённое окно эти таблицы в памяти не держат.
local sceneAt = setmetatable({}, { __mode = "k" })
local builtAt = setmetatable({}, { __mode = "k" })

-- Потолок рёбер на один слой. Клетка мельче допустимой укрупняется: мелкая сота,
-- заданная обстановке плашки, на окне во весь экран стоила бы тысяч кадров.
local LATTICE_MAX = 2400

-- Цвет стекла, к которому подмешивается тон обстановки: чистый цвет рёбер в подсветке
-- дал бы цветное пятно во всю панель, а не перепад яркости.
local SHEEN_BASE = Color3.fromRGB(122, 156, 176)

function Theme.Backdrop(frame, name)
	-- Панель, которая сама растёт по содержимому, решётки не получает: слой размером
	-- в панель для AutomaticSize — это содержимое размером в панель, и панель тянется
	-- за ним по кругу. Замерено на карточке плутония: высота 211004 пикселя за пару секунд.
	if frame.AutomaticSize ~= Enum.AutomaticSize.None then
		return nil
	end
	local scene = sceneOf(name)
	sceneAt[frame] = scene

	local root = frame:FindFirstChild("Backdrop")
	if not root then
		root = Instance.new("Frame")
		root.Name = "Backdrop"
		root.BackgroundTransparency = 1
		root.BorderSizePixel = 0
		root.ZIndex = frame.ZIndex
		root.Parent = frame
	end
	-- Решётка доходит до настоящего края панели, под самый кант, а не до края её
	-- внутреннего отступа: иначе у окна с отступом по периметру оставалась пустая рамка.
	Theme.Bleed(root, UDim2.new(0, 0, 0, 0), UDim2.new(1, 0, 1, 0))

	-- Мерка масштаба. Рёбра стоят в пикселях до масштаба, а AbsoluteSize — уже после
	-- него, и во время открытия окна (Theme.Open, UIScale 0.96 → 1) панель меряется
	-- на 4% меньше, чем она есть. Решётка, срезанная по такой мерке, так и осталась бы
	-- с пустой полосой у правого и нижнего канта. Кадр в сто пикселей показывает
	-- настоящий масштаб всей цепочки предков.
	local probe = root:FindFirstChild("Probe")
	if not probe then
		probe = Instance.new("Frame")
		probe.Name = "Probe"
		probe.BackgroundTransparency = 1
		probe.BorderSizePixel = 0
		probe.Size = UDim2.fromOffset(100, 100)
		probe.Parent = root
	end

	-- Один слой сот. cellScale, lineScale и speedScale — доли от обстановки: дальний
	-- слой крупнее, бледнее и медленнее ближнего (Theme.BACKDROP_FAR).
	local function build(width, height, cellScale, lineScale, speedScale)
		-- Потолок от короткой стороны панели: клетка втрое мельче панели стоила плашке
		-- забега 232x72 ста двадцати четырёхпиксельных кадров — шероховатость вместо сот.
		local radius = math.min(scene.cell * cellScale, math.min(width, height) / 2)
		if radius < 14 then
			return -- на плашку меньше сорока пикселей высотой соты не положить
		end
		-- Три ребра на клетку; строк — на высоту панели и ещё на период хода.
		local estimate = 3 * (width / (radius * 1.732) + 2) * ((height + radius * 3) / (radius * 1.5) + 3)
		if estimate > LATTICE_MAX then
			radius *= math.sqrt(estimate / LATTICE_MAX)
		end
		local across = radius * 0.8660254 -- половина ширины клетки: R * cos(30°)
		local pitch = radius * 1.5 -- шаг строк: строки сот заходят друг в друга на четверть клетки
		local period = radius * 3
		local line = scene.line * lineScale
		local speedX = (scene.driftX or 0) * speedScale
		local slide = speedX ~= 0

		local holder = Instance.new("Frame")
		holder.Name = "Lattice"
		holder.BackgroundTransparency = 1
		holder.Size = UDim2.new(1, 0, 1, 0)
		holder.Position = UDim2.new(0, slide and -across * 2 or 0, 0, -period)
		holder.ZIndex = root.ZIndex
		-- Окно могли открыть уже после того, как сетку выключили
		holder.Visible = gridEnabled

		local state = {
			frame = frame,
			phase = 0,
			-- Фаза волны стартует со случайного места: два окна рядом, опрашиваемые
			-- в один такт, читаются как одна мигающая плашка, а не как два прибора.
			pulse = math.random(),
			pulseSpeed = scene.pulse,
			wave = scene.wave * lineScale,
			speed = scene.drift * speedScale,
			period = period,
			speedX = speedX,
			periodX = across * 2,
			phaseX = 0,
			width = width,
			height = height,
			segs = {}, cx = {}, cy = {}, ux = {}, uy = {}, tx0 = {}, tx1 = {},
			pos = {}, size = {}, tall = {}, shown = {}, cut = {}, base = {}, last = {},
		}

		-- Слева и справа край панели не двигается, и срез по нему считается здесь,
		-- один раз: ребру, целиком ушедшему за боковой край, незачем и рождаться.
		-- Сверху и снизу решётка едет, и тот срез считает Heartbeat выше.
		local function edge(x, y, angle)
			local tall = angle == 90
			local ux = tall and 0 or math.cos(math.rad(angle))
			local uy = tall and 1 or math.sin(math.rad(angle))
			local t0, t1 = -radius / 2, radius / 2
			if slide then
				-- Едущая вбок решётка режется по бокам в Heartbeat: здесь ребро целое.
			elseif ux ~= 0 then
				local a, b = -x / ux, (width - x) / ux
				if a > b then
					a, b = b, a
				end
				t0, t1 = math.max(t0, a), math.min(t1, b)
			elseif x < 0 or x > width then
				return
			end
			if t1 - t0 < 1 then
				return
			end
			local mid, len = (t0 + t1) / 2, t1 - t0
			local pos = UDim2.new(0, x + ux * mid, 0, y + uy * mid)
			local size = tall and UDim2.fromOffset(1, len) or UDim2.fromOffset(len, 1)

			local seg = Instance.new("Frame")
			seg.BorderSizePixel = 0
			seg.BackgroundColor3 = scene.tint
			seg.BackgroundTransparency = 1
			seg.AnchorPoint = Vector2.new(0.5, 0.5)
			seg.Position = pos
			seg.Size = size
			-- Вертикальное ребро — не повёрнутый кадр, а просто узкий: поворот на 90°
			-- дал бы ту же линию дороже.
			seg.Rotation = tall and 0 or angle
			seg.ZIndex = root.ZIndex
			seg.Parent = holder

			local i = #state.segs + 1
			state.segs[i] = seg
			state.cx[i], state.cy[i] = x, y
			state.ux[i], state.uy[i] = ux, uy
			state.tx0[i], state.tx1[i] = t0, t1
			state.pos[i], state.size[i] = pos, size
			state.tall[i] = tall
			state.shown[i], state.cut[i] = true, false
			state.base[i] = line
			state.last[i] = 1
		end

		-- Клетка вершиной вверх: два верхних ребра под ±30° к горизонту и правое
		-- вертикальное. Слой поднят на период хода и едет в пределах одного периода,
		-- поэтому строки нужны на всю высоту панели и ещё на период ниже.
		local rows = math.ceil((height + period + radius * 2) / pitch)
		-- Едущей вбок решётке нужна ещё одна колонка справа: слой сдвинут влево
		-- на ширину клетки и едет в её пределах.
		local cols = math.ceil(width / (across * 2)) + (slide and 2 or 1)
		for row = 0, rows do
			local y = row * pitch - radius
			local shift = (row % 2 == 1) and across or 0
			for col = -1, cols do
				local x = shift + col * across * 2
				local top = y - radius * 0.75
				edge(x - across / 2, top, -30)
				edge(x + across / 2, top, 30)
				edge(x + across, y, 90)
			end
		end

		holder.Parent = root
		layers[holder] = state
	end

	-- Решётка пересобирается на любое изменение размера, а не на огрублённое до сорока
	-- пикселей, как при гаснущих краях: срезу по канту нужен точный размер. Панель
	-- стала шире постройки — у правого канта пустая полоса; уже — повёрнутые рёбра
	-- вылезают за неё, а их ClipsDescendants не режет.
	local function rebuild()
		local current = sceneAt[frame]
		local k = probe.AbsoluteSize.X / 100
		if not current or k <= 0 then
			return -- окно ещё не отрисовано
		end
		local size = frame.AbsoluteSize
		local width, height = size.X / k, size.Y / k
		if width < 40 or height < 20 then
			return
		end
		local built = builtAt[root]
		if built and built.scene == current and math.abs(built.w - width) < 1.5 and math.abs(built.h - height) < 1.5 then
			return
		end
		builtAt[root] = { scene = current, w = width, h = height }
		-- Сносится только сама решётка: рядом в том же корне лежат подсветка стекла
		-- и мерка масштаба.
		for _, child in root:GetChildren() do
			if child.Name == "Lattice" then
				layers[child] = nil
				child:Destroy()
			end
		end
		scene = current
		local far = scene.far or Theme.BACKDROP_FAR
		if scene.cell * far <= math.min(width, height) / 2 then
			build(width, height, far, Theme.BACKDROP_FAR_LINE, Theme.BACKDROP_FAR_SPEED)
		end
		build(width, height, 1, 1, 1)
	end

	-- Подсветка стекла. Не ореол и не свечение (их в этом языке нет), а перепад
	-- яркости самого стекла: без него плашка во весь экран — ровный чёрный
	-- прямоугольник без верха и низа, и глазу не за что зацепиться. Тон подмешан
	-- от обстановки, сторона берётся из неё же: темнота у каждой ситуации своя.
	local sheen = root:FindFirstChild("Sheen")
	if not sheen then
		sheen = Instance.new("Frame")
		sheen.Name = "Sheen"
		sheen.BorderSizePixel = 0
		sheen.BackgroundTransparency = 0
		sheen.ZIndex = root.ZIndex
		sheen.Parent = root
		Instance.new("UIGradient").Parent = sheen
	end
	sheen.AnchorPoint = Vector2.new(0, scene.at)
	sheen.Position = UDim2.new(0, 0, scene.at, 0)
	sheen.Size = UDim2.new(1, 0, 0.5, 0)
	sheen.BackgroundColor3 = SHEEN_BASE:Lerp(scene.tint, 0.5)
	sheen.Visible = scene.sheen < 1
	local fade = sheen:FindFirstChildOfClass("UIGradient")
	-- Градиент гаснет ОТ своей стороны: у подсветки внизу он развёрнут.
	fade.Rotation = scene.at == 1 and -90 or 90
	fade.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, math.clamp(scene.sheen, 0, 1)),
		NumberSequenceKeypoint.new(1, 1),
	})

	rebuild()
	-- Одна подписка на панель, даже если сборщик позвали повторно (SetScene).
	-- Пересборка отложена на десятую долю секунды: окно, меняющее размер плавно,
	-- иначе пересобирало бы решётку в каждом кадре. Мерка слушается тоже: у только что
	-- заведённой панели она получает размер кадром позже самой панели.
	if not frame:GetAttribute("BackdropWatch") then
		frame:SetAttribute("BackdropWatch", true)
		local pending = false
		local function later()
			if pending then
				return
			end
			pending = true
			task.delay(0.1, function()
				pending = false
				rebuild()
			end)
		end
		frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(later)
		probe:GetPropertyChangedSignal("AbsoluteSize"):Connect(later)
	end
	frame.ClipsDescendants = true
	return root
end

-- Сменить обстановку уже собранной панели: страница главного меню, вкладка Лаборатории.
-- Панель, собранная без решётки (depth = false), без неё и остаётся.
function Theme.SetScene(frame, name)
	if frame:FindFirstChild("Backdrop") then
		Theme.Backdrop(frame, name)
	end
end
-- Сетка точек — фон окна, отличный от сот вокруг него (#223): рисунок другой формы,
-- а не те же соты темнее. Неподвижная; пересобирается, только когда меняется размер.
-- Кадр сетки выносится под кант окна (Theme.Bleed): внутренний отступ окна её не сужает.
--
-- opts: step — шаг сетки, size — сторона точки, transparency — прозрачность точки,
-- keep — доля позиций, на которых точка стоит (1 — на всех), zIndex.
-- Какие позиции пустуют, решает посев, а не случай на каждой пересборке: при смене
-- размера окна рисунок иначе перетасовывался бы у игрока на глазах.
--
-- Где стоят точки, сетка пишет в атрибуты своего кадра Dots: OriginX, OriginY — левый
-- верхний угол первой точки, Step и Size. По ним стекло над сеткой рисует на тех же
-- местах размытые точки (CraftingUI, glass).
--
-- Возвращает paint(w, h): размер передаёт сборщик окна, в пикселях до масштаба.
-- AbsoluteSize для этого не годится — во время Theme.Open окно меряется на 4% меньше.
function Theme.Dots(frame, opts)
	opts = opts or {}
	local step = opts.step or 28
	local size = opts.size or 2
	local transparency = opts.transparency or 0.3
	local keep = opts.keep or 1

	local dots = Instance.new("Frame")
	dots.Name = "Dots"
	dots.BackgroundTransparency = 1
	dots.BorderSizePixel = 0
	dots.ZIndex = opts.zIndex or frame.ZIndex
	dots.Parent = frame
	Theme.Bleed(dots, UDim2.new(0, 0, 0, 0), UDim2.new(1, 0, 1, 0))

	local paintedFor
	return function(w, h)
		w, h = math.floor(w), math.floor(h)
		local key = w .. "x" .. h
		if paintedFor == key then
			return
		end
		paintedFor = key
		dots:ClearAllChildren()
		local rng = Random.new(1)
		local cols, rows = math.floor(w / step), math.floor(h / step)
		local ox = math.floor((w - (cols - 1) * step - size) / 2)
		local oy = math.floor((h - (rows - 1) * step - size) / 2)
		dots:SetAttribute("Step", step)
		dots:SetAttribute("Size", size)
		dots:SetAttribute("OriginX", ox)
		dots:SetAttribute("OriginY", oy)
		for r = 0, rows - 1 do
			for c = 0, cols - 1 do
				if keep >= 1 or rng:NextNumber() < keep then
					local d = Instance.new("Frame")
					d.BorderSizePixel = 0
					d.BackgroundColor3 = Theme.color.grid
					d.BackgroundTransparency = transparency
					d.Size = UDim2.fromOffset(size, size)
					d.Position = UDim2.fromOffset(ox + c * step, oy + r * step)
					d.ZIndex = dots.ZIndex
					d.Parent = dots
				end
			end
		end
	end
end


-- Угловые засечки: по две линии в пиксель в каждом углу окна — визир прибора.
--
-- Зачем они при том, что у панели уже есть кант: окна игры открываются во весь экран,
-- и кант по самому краю там либо не виден вовсе, либо частично уезжает за скруглённые
-- углы экрана телефона. Засечка, отступившая внутрь, видна всегда.
--
-- Геометрию окна не трогают — лежат внутри его собственных границ, как и остальные
-- сборщики темы (см. шапку файла).
--
-- ВНУТРЕННИЙ ОТСТУП ОКНА компенсируется нарочно. UIPadding сдвигает всех детей
-- без исключения, и засечка «в семи пикселях от края» у окна с отступом в двадцать
-- оказывается не у края, а поверх заголовка — ровно так и вышло с первого раза.
-- Короткая и прижатая к углу: длинная засечка дотягивалась до строки состояния
-- в подвале окна и подчёркивала её первое слово.
--
-- Сам отступ берётся ЗАМЕРОМ, а не чтением UIPadding в момент вызова: сборщик
-- часто зовут сразу за Corner и Stroke, то есть ДО того, как окну поставили отступ
-- (так и было в MainMenu: засечки легли на подвал и на кнопку — замерено: черта
-- на 1480,689 внутри кнопки 1337..1487). Прочитанные в тот момент нули замирали
-- навсегда. Разница между краем окна и краем собственного кадра засечек — это
-- и есть отступ, каким бы он ни стал потом.
Theme.BRACKET = { inset = 6, arm = 14 }

local BRACKET_CORNERS = { Vector2.new(0, 0), Vector2.new(1, 0), Vector2.new(0, 1), Vector2.new(1, 1) }

function Theme.Brackets(frame, color)
	local holder = frame:FindFirstChild("Brackets")
	if not holder then
		holder = Instance.new("Frame")
		holder.Name = "Brackets"
		holder.BackgroundTransparency = 1
		holder.BorderSizePixel = 0
		holder.Size = UDim2.new(1, 0, 1, 0)
		holder.Parent = frame
	end
	holder.ZIndex = frame.ZIndex + 1

	local tint = color or Theme.color.accentDim
	local inset, arm = Theme.BRACKET.inset, Theme.BRACKET.arm

	local bars = {}
	for index, corner in BRACKET_CORNERS do
		for axis = 1, 2 do
			local name = ("Mark%d_%d"):format(index, axis)
			local bar = holder:FindFirstChild(name)
			if not bar then
				bar = Instance.new("Frame")
				bar.Name = name
				bar.BorderSizePixel = 0
				bar.Parent = holder
			end
			bar.BackgroundColor3 = tint
			bar.BackgroundTransparency = 0
			bar.AnchorPoint = corner
			-- Первая линия угла горизонтальная, вторая вертикальная — вместе они дают «L».
			bar.Size = axis == 1 and UDim2.fromOffset(arm, 1) or UDim2.fromOffset(1, arm)
			bar.ZIndex = holder.ZIndex
			table.insert(bars, { bar = bar, corner = corner })
		end
	end

	local function place()
		local fp, fs = frame.AbsolutePosition, frame.AbsoluteSize
		local hp, hs = holder.AbsolutePosition, holder.AbsoluteSize
		if hs.X <= 0 or hs.Y <= 0 then
			return -- окно ещё не отрисовано или весь ScreenGui выключен
		end
		local padL = hp.X - fp.X
		local padT = hp.Y - fp.Y
		local padR = (fp.X + fs.X) - (hp.X + hs.X)
		local padB = (fp.Y + fs.Y) - (hp.Y + hs.Y)
		for _, entry in bars do
			local corner = entry.corner
			entry.bar.Position = UDim2.new(
				corner.X, corner.X == 0 and (inset - padL) or (padR - inset),
				corner.Y, corner.Y == 0 and (inset - padT) or (padB - inset)
			)
		end
	end

	place()
	-- Одна подписка на окно, даже если сборщик позвали повторно (тот же приём,
	-- что у BackdropWatch выше).
	if not frame:GetAttribute("BracketWatch") then
		frame:SetAttribute("BracketWatch", true)
		holder:GetPropertyChangedSignal("AbsoluteSize"):Connect(place)
		holder:GetPropertyChangedSignal("AbsolutePosition"):Connect(place)
	end

	return holder
end

-- Списки листаются перетаскиванием, а не только колесом: колеса на телефоне нет вовсе,
-- а на ПК тянуть журнал рукой быстрее, чем крутить его по три строки.
--
-- Нажатие ловится через UserInputService, а не на самом списке: его строки — кнопки,
-- они забирают нажатие себе, и до фрейма оно не доходит вовсе.
--
-- Пока тянули больше порога, на списке стоит атрибут Dragged — обработчики нажатий
-- его проверяют (Theme.WasDragged) и молчат: иначе отпускание пальца над строкой
-- уходило бы кликом по ней — пролистал список и заодно положил элемент в слот.
local DRAG_SLOP = 6

local function isShown(inst)
	while inst and inst ~= game do
		if inst:IsA("GuiObject") and not inst.Visible then
			return false
		end
		if inst:IsA("ScreenGui") and not inst.Enabled then
			return false
		end
		inst = inst.Parent
	end
	return true
end

function Theme.WasDragged(frame)
	return frame:GetAttribute("Dragged") == true
end

function Theme.DragScroll(frame)
	if frame:GetAttribute("DragScroll") then
		return frame
	end
	frame:SetAttribute("DragScroll", true)

	local dragging = false
	local lastY = 0
	local travelled = 0

	local function pressed(input)
		return input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
	end

	UserInputService.InputBegan:Connect(function(input)
		if not pressed(input) or not isShown(frame) then
			return
		end
		local pos, size = frame.AbsolutePosition, frame.AbsoluteSize
		if input.Position.X < pos.X or input.Position.X > pos.X + size.X
			or input.Position.Y < pos.Y or input.Position.Y > pos.Y + size.Y then
			return
		end
		dragging = true
		travelled = 0
		lastY = input.Position.Y
		frame:SetAttribute("Dragged", false)
	end)

	UserInputService.InputChanged:Connect(function(input)
		if not dragging then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.MouseMovement
			and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		local dy = input.Position.Y - lastY
		lastY = input.Position.Y
		travelled += math.abs(dy)
		if travelled > DRAG_SLOP then
			frame:SetAttribute("Dragged", true)
		end
		local limit = math.max(0, frame.AbsoluteCanvasSize.Y - frame.AbsoluteSize.Y)
		frame.CanvasPosition = Vector2.new(
			frame.CanvasPosition.X,
			math.clamp(frame.CanvasPosition.Y - dy, 0, limit)
		)
	end)

	UserInputService.InputEnded:Connect(function(input)
		if not pressed(input) then
			return
		end
		dragging = false
		-- Флаг снимается чуть позже: клик кнопки приходит в том же кадре, что и InputEnded,
		-- и порядок между ними не закреплён.
		task.delay(0.05, function()
			frame:SetAttribute("Dragged", false)
		end)
	end)

	return frame
end

-- Окно: почти чёрная плашка с ползущей сеткой, обведённая приглушённой бирюзой.
-- opts.color — своя заливка, opts.transparency — если сквозь панель нужно видеть арену,
-- opts.edge — свой цвет канта, opts.depth — глубина решётки (см. Theme.depth),
-- opts.depth = false — без решётки вовсе.
function Theme.Panel(frame, opts)
	opts = opts or {}
	frame.BackgroundColor3 = opts.color or Theme.color.panel
	frame.BackgroundTransparency = opts.transparency or 0
	frame.BorderSizePixel = 0
	Theme.Corner(frame, Theme.radius.panel)
	Theme.Stroke(frame, opts.edge or Theme.color.frame, 1, 0)
	-- opts.scene — обстановка из Theme.scene; opts.depth — прежняя числовая глубина
	-- у панелей, которые свою обстановку не назвали. false в любом из двух — без решётки.
	if opts.depth ~= false and opts.scene ~= false then
		Theme.Backdrop(frame, opts.scene or opts.depth)
	end
	return frame
end

-- ============ Кнопки ============

-- У каждой кнопки теперь три числа, а не два: заливка, краска текста и цвет канта.
-- Кант — главное отличие от прежнего языка: на почти чёрном фоне кнопка без границы
-- перестаёт читаться как кнопка вовсе — это просто надпись на чуть другом чёрном.
Theme.buttonKind = {
	-- Действие, ради которого окно и открыли: купить, скрестить, применить, начать волну.
	-- Тёмная бирюза, яркий кант по краю и светлая надпись. Прежняя сплошная яркая бирюза
	-- (30,190,168) резала глаз: на экране покупки таких заливок было пять. Вид выбран
	-- автором из опытов настройки «Кнопки действий» (#209 → #210). Кнопку выделяет кант,
	-- а не яркость заливки: тёмная заливка без канта терялась рядом с вкладкой.
	action = { bg = Color3.fromRGB(14, 66, 60), text = Color3.fromRGB(196, 248, 240), edge = Color3.fromRGB(80, 220, 200), border = true },
	-- Нейтральная: вкладки, переключатели, «Инвентарь (I)», кнопки построек.
	ghost = { bg = Color3.fromRGB(16, 20, 25), text = Color3.fromRGB(188, 202, 216), edge = Color3.fromRGB(46, 55, 66) },
	-- Выбранная вкладка и пункт меню: тёмная плашка, бирюзой горят кант по краю и надпись.
	-- Две почти чёрные заливки без канта не различались вовсе — выбор держит кант.
	-- Прежняя сплошная светлая бирюза (96,214,200) убрана вместе с яркой кнопкой действия (#210).
	active = { bg = Color3.fromRGB(18, 38, 40), text = Color3.fromRGB(120, 226, 212), edge = Color3.fromRGB(96, 214, 200), border = true },
	-- Отмена и закрытие: видно, но взгляд не тянет.
	-- Заливка и кант подняты против прежних (13,16,20)/(50,60,72): те стояли в одном шаге
	-- от Theme.color.panel (10,12,15) и на нём не читались вовсе — «Назад» и «Свернуть»
	-- выглядели отключёнными кнопками, а не действием. Видно, но взгляд не тянет — тот же
	-- замысел, просто с контрастом, который его выполняет.
	quiet = { bg = Color3.fromRGB(24, 30, 37), text = Color3.fromRGB(198, 210, 222), edge = Color3.fromRGB(94, 108, 122) },
	-- Нажимать нечего: кнопка на месте, но не готова (пустые слоты крафта).
	-- Заливка светлее самого окна, а не вровень с ним: пустой слот стал большим
	-- (стол крафта занимает четверть вкладки), и плашка цвета фона с одним волоском
	-- по краю читалась как дыра в окне, а не как место, куда кладут элемент.
	muted = { bg = Color3.fromRGB(20, 24, 30), text = Color3.fromRGB(112, 126, 142), edge = Color3.fromRGB(60, 70, 82) },
	danger = { bg = Color3.fromRGB(58, 20, 26), text = Color3.fromRGB(255, 208, 214), edge = Color3.fromRGB(214, 84, 96) },
}

-- Опытные краски кнопки действия и выбранной вкладки — настройка «Кнопки действий»
-- (UISettings.buttonStyle). «Стандарт» и «Эксп. 1» — Theme.buttonKind как есть; у «Стандарта»
-- кнопки покупки у производителя ещё и в цвет своего элемента (докрашивает CraftingUI).
-- «Эксп. 2» заменяет только action и active: остальные виды кнопок и так тёмные.
Theme.buttonStyles = {
	-- 2: только контур — заливка почти как у нейтральной кнопки, бирюзовые кант и надпись.
	-- Вкладка отличается от действия светлой надписью.
	e2 = {
		action = { bg = Color3.fromRGB(14, 22, 24), text = Color3.fromRGB(96, 226, 208), edge = Color3.fromRGB(40, 196, 176), border = true },
		active = { bg = Color3.fromRGB(24, 30, 36), text = Color3.fromRGB(236, 242, 248), edge = Color3.fromRGB(96, 214, 200), border = true },
	},
}

-- Уже построенные кнопки перекрашиваются при смене настройки: сборщик рассчитан на
-- повторный вызов на том же объекте. Таблица слабая — удалённая кнопка уходит из неё сама.
local buttonStyle = Settings.Get("buttonStyle")
local themedButtons = setmetatable({}, { __mode = "k" })

Settings.Changed.Event:Connect(function(key, value)
	if key ~= "buttonStyle" then
		return
	end
	buttonStyle = value
	for button, kind in themedButtons do
		if kind == "action" or kind == "active" then
			Theme.Button(button, kind)
		end
	end
end)

-- kind — ключ из Theme.buttonKind. Цветом элемента кнопки красит не этот сборщик,
-- а Theme.ElementButton ниже: сплошная заливка в полную силу для них не годится.
function Theme.Button(button, kind)
	local style = Theme.buttonStyles[buttonStyle]
	local spec = (style and style[kind]) or Theme.buttonKind[kind] or Theme.buttonKind.ghost
	local base = spec.bg
	themedButtons[button] = kind

	clearDecor(button)
	button.BackgroundColor3 = base
	button.BackgroundTransparency = 0
	button.BorderSizePixel = 0
	button.TextColor3 = spec.text
	button.AutoButtonColor = true
	Theme.Corner(button, Theme.radius.control)
	local stroke = Theme.Stroke(button, spec.edge, 1, 0)
	-- У текстовой кнопки обводка по умолчанию ложится на буквы, а не на край. Кнопки
	-- действия и выбора держатся на канте, поэтому кладут его по краю (border).
	if spec.border then
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	end

	-- Наведение осветляет саму заливку, а не зажигает обводку. Базовый цвет хранится
	-- атрибутом, потому что сборщик зовётся повторно на том же объекте (вкладка меняет
	-- вид при каждом переключении) и «куда возвращаться» к этому моменту уже другое.
	button:SetAttribute("ThemeBase", base)
	-- Стиль могли переназначить, пока наведение ещё играет свой твин — главное меню
	-- зовёт Theme.Button на каждый MouseEnter чужого пункта, чтобы погасить прежний выбор.
	-- Без отмены старый твин с MouseLeave доигрывал поверх этого прямого сброса и возвращал
	-- кнопку к старому (подсвеченному) цвету уже после того, как она должна была погаснуть.
	local existing = hoverTweens[button]
	if existing then
		existing:Cancel()
		hoverTweens[button] = nil
	end
	if not button:GetAttribute("ThemeHover") then
		button:SetAttribute("ThemeHover", true)
		button.MouseEnter:Connect(function()
			local from = button:GetAttribute("ThemeBase")
			if from then
				playHoverTween(button, from:Lerp(Color3.new(1, 1, 1), 0.14))
			end
		end)
		button.MouseLeave:Connect(function()
			local from = button:GetAttribute("ThemeBase")
			if from then
				playHoverTween(button, from)
			end
		end)
	end
	return button
end

-- Затемнённая версия цвета элемента — подложка под надписью на залитой им ячейке.
-- Не чёрный на всех подряд: подложка читается как часть своей ячейки, а не как дырка
-- в ней. И не фиксированная яркость: доля от самого цвета темнее заливки всегда,
-- а постоянная слилась бы с ней у тёмных элементов (Обсидиан 35,30,40).
--
-- amount — насколько глубоко гасить. По умолчанию — как красится начинка ячейки; больше —
-- для того, что должно уйти глубже самой начинки (кнопка покупки во вкладке «Купить»).
function Theme.Shadowed(color, amount)
	return color:Lerp(Color3.new(0, 0, 0), amount or 0.78)
end

-- Цветной блок по левому краю ячейки: цвет сущности в полную силу. Полоски в три пикселя
-- (так было в #101–#102) для опознания элемента мало: цвет должен занимать место,
-- а не намекать на себя с краю (решение автора, задача #103).
--
-- Номера строк на блоке были и убраны в #104: автор спросил, что они значат, —
-- а они не значили ничего, кроме порядка в списке, который и так виден. Цена
-- и запас у строки свои столбики, больше на блоке писать нечего.
--
-- Где места нет вовсе (квадратные кнопки панели стройки), блок сжимается в полоску.
--
-- right — блок у правого края вместо левого. Нужен слотам крафта: там два слота стоят
-- по бокам от «+», и полоска левого слота смотрела от плюса наружу. Цвет должен
-- смотреть в сторону скрещивания — решение автора, задача #105.
Theme.EDGE_W = 3
Theme.SWATCH_W = 34

function Theme.Swatch(inst, color, wide, right)
	local swatch = inst:FindFirstChild("Swatch")
	if not swatch then
		swatch = Instance.new("Frame")
		swatch.Name = "Swatch"
		swatch.BorderSizePixel = 0
		swatch.Parent = inst
	end
	swatch.AnchorPoint = Vector2.new(right and 1 or 0, 0)
	-- Засечка стоит у настоящего края ячейки, а не у края её отступа (см. Theme.Bleed).
	Theme.Bleed(
		swatch,
		UDim2.new(right and 1 or 0, 0, 0, 0),
		UDim2.new(0, wide and Theme.SWATCH_W or Theme.EDGE_W, 1, 0)
	)
	swatch.BackgroundColor3 = color
	swatch.BackgroundTransparency = 0
	swatch.ZIndex = inst.ZIndex
	return swatch
end

-- Цветная дымка поверх корпуса, гаснущая к правому краю. Один блок слева опознаёт
-- элемент, но строка от этого цветной не становится; дымка возвращает цвет во всю
-- строку, не превращая её обратно в сплошную заливку из #88.
function Theme.Wash(inst, color, dim, right)
	local wash = inst:FindFirstChild("Wash")
	if not wash then
		wash = Instance.new("Frame")
		wash.Name = "Wash"
		wash.BorderSizePixel = 0
		wash.Parent = inst
	end
	-- Дымка — во всю ячейку, вместе с её отступом (см. Theme.Bleed).
	Theme.Bleed(wash, UDim2.new(0, 0, 0, 0), UDim2.new(1, 0, 1, 0))
	wash.BackgroundColor3 = color
	wash.BackgroundTransparency = 0
	wash.ZIndex = inst.ZIndex

	local gradient = wash:FindFirstChildOfClass("UIGradient")
	if not gradient then
		gradient = Instance.new("UIGradient")
		gradient.Parent = wash
	end
	-- Дымка всегда гуще у своего цветного блока и гаснет от него: развернули блок вправо —
	-- разворачивается и она, иначе цвет копился бы у пустого края.
	gradient.Rotation = right and 180 or 0
	gradient.Transparency = dim
		and NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.9),
			NumberSequenceKeypoint.new(0.5, 0.97),
			NumberSequenceKeypoint.new(1, 1),
		})
		or NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.74),
			NumberSequenceKeypoint.new(0.5, 0.92),
			NumberSequenceKeypoint.new(1, 1),
		})
	return wash
end

-- Узор элемента: у элемента один узор на все его фоны — ячейки списков, слоты крафта,
-- справочник и узел карты. Узор задан на тип элемента, а не на экземпляр.
--
-- Текстура белая на прозрачном и красится цветом элемента. Из неё вырезается окно
-- ImageRectOffset/ImageRectSize размером с саму ячейку, поэтому обрезка родителем не нужна:
-- узел карты лежит в повёрнутом слое, где ClipsDescendants не работает.
-- offset — какое место текстуры достаётся элементу. size — размер текстуры в пикселях.
-- minRect — сколько пикселей текстуры по высоте видно в ячейке любой высоты: в низкой
-- строке узор мелеет, а не превращается в одно неузнаваемое пятно.
-- color — свой цвет узора вместо цвета элемента, transparency — своя прозрачность.
Theme.patterns = {
	-- Тонкий контур, сплошняком залит фон между языками, сами языки тёмные (решение автора).
	Fire = {
		image = "rbxassetid://119088562860698",
		size = Vector2.new(1024, 724),
		offset = Vector2.new(80, 120),
		minRect = 230,
		transparency = 0.45,
	},
	-- В стиле Огня: контур и залитый фон, языки тёмные; цвет ближе к красному исходного
	-- узора (решение автора). Текстура — 3×3 плитки: мелкая 7×7 рябила в больших ячейках.
	Heat = {
		image = "rbxassetid://116091801403839",
		size = Vector2.new(1014, 1024),
		offset = Vector2.new(0, 0),
		density = 1.4,
		minRect = 200,
		color = Color3.fromRGB(225, 62, 40), -- как Elements.Heat.color
		transparency = 0.2,
	},
	-- Остальные узоры адаптированы из папки автора в стиле Огня: контур, залитый фон, тёмные объекты.
	Ocean = { image = "rbxassetid://82108288169440", size = Vector2.new(1024, 1024), offset = Vector2.new(0, 0), minRect = 230, transparency = 0.45 },
	Rain = { image = "rbxassetid://99435703775612", size = Vector2.new(1024, 1024), offset = Vector2.new(0, 0), minRect = 230, transparency = 0.45 },
	Flare = { image = "rbxassetid://87109341594435", size = Vector2.new(1024, 1024), offset = Vector2.new(0, 0), minRect = 230, transparency = 0.45 },
	Water = { image = "rbxassetid://82618165518917", size = Vector2.new(1024, 1024), offset = Vector2.new(0, 0), minRect = 230, transparency = 0.45 },
	Wind = { image = "rbxassetid://90975203503814", size = Vector2.new(1024, 1024), offset = Vector2.new(0, 0), minRect = 230, transparency = 0.45 },
	Earth = { image = "rbxassetid://78842444665286", size = Vector2.new(1024, 1024), offset = Vector2.new(0, 0), minRect = 230, transparency = 0.45 },
	Puddle = { image = "rbxassetid://104534370219814", size = Vector2.new(1024, 1024), offset = Vector2.new(0, 0), minRect = 230, transparency = 0.45 },
	Pond = { image = "rbxassetid://123586441239017", size = Vector2.new(1024, 1024), offset = Vector2.new(0, 0), minRect = 230, transparency = 0.45 },
	Lightning = { image = "rbxassetid://77093506656138", size = Vector2.new(1024, 1024), offset = Vector2.new(0, 0), minRect = 230, transparency = 0, color = Color3.fromRGB(125, 100, 255) },
	Cloud = { image = "rbxassetid://114469872606814", size = Vector2.new(1024, 1024), offset = Vector2.new(0, 0), minRect = 230, transparency = 0.45 },
	Steam = { image = "rbxassetid://108165904951816", size = Vector2.new(1024, 1024), offset = Vector2.new(0, 0), minRect = 230, transparency = 0.45 },
	Air = { image = "rbxassetid://117280729810056", size = Vector2.new(1024, 1024), offset = Vector2.new(0, 0), minRect = 230, transparency = 0.45 },
	Soil = { image = "rbxassetid://88107535656248", size = Vector2.new(1024, 1024), offset = Vector2.new(0, 0), minRect = 230, transparency = 0.45 },
	Pressure = { image = "rbxassetid://129824274473310", size = Vector2.new(1024, 1024), offset = Vector2.new(0, 0), minRect = 230, transparency = 0.45 },
	Continent = { image = "rbxassetid://105085352604879", size = Vector2.new(1024, 1024), offset = Vector2.new(0, 0), minRect = 230, transparency = 0.45 },
	Land = { image = "rbxassetid://79018938944102", size = Vector2.new(1024, 1024), offset = Vector2.new(0, 0), minRect = 230, transparency = 0.45 },
	Hurricane = { image = "rbxassetid://132658543532380", size = Vector2.new(1024, 1024), offset = Vector2.new(0, 0), minRect = 230, transparency = 0.45 },
	Energy = { image = "rbxassetid://85978428610371", size = Vector2.new(1024, 1024), offset = Vector2.new(0, 0), minRect = 230, transparency = 0.45 },
	Electricity = { image = "rbxassetid://98373118933740", size = Vector2.new(1024, 1024), offset = Vector2.new(0, 0), minRect = 230, transparency = 0.45 },
	Mist = { image = "rbxassetid://104402193432785", size = Vector2.new(1024, 1024), offset = Vector2.new(0, 0), minRect = 230, transparency = 0.45 },
	Smoke = { image = "rbxassetid://126246838660519", size = Vector2.new(1024, 1024), offset = Vector2.new(0, 0), minRect = 230, transparency = 0.45 },
	Sand = { image = "rbxassetid://88737258631529", size = Vector2.new(1024, 1024), offset = Vector2.new(0, 0), minRect = 230, transparency = 0.45 },
	Dust = { image = "rbxassetid://92491988259015", size = Vector2.new(1024, 1024), offset = Vector2.new(0, 0), minRect = 230, transparency = 0.45 },
	Lava = { image = "rbxassetid://97998220890377", size = Vector2.new(1024, 1024), offset = Vector2.new(0, 0), minRect = 230, transparency = 0.45 },
	Volcano = { image = "rbxassetid://115978401678384", size = Vector2.new(1024, 1024), offset = Vector2.new(0, 0), minRect = 230, transparency = 0.45 },
	Eruption = { image = "rbxassetid://84230734832700", size = Vector2.new(1024, 1024), offset = Vector2.new(0, 0), minRect = 230, transparency = 0.45 },
	Gunpowder = { image = "rbxassetid://127920865810601", size = Vector2.new(1024, 1024), offset = Vector2.new(0, 0), minRect = 230, transparency = 0.45 },
	Stone = { image = "rbxassetid://75807970631826", size = Vector2.new(1024, 1024), offset = Vector2.new(0, 0), minRect = 230, transparency = 0.45 },
	Obsidian = { image = "rbxassetid://102167949227302", size = Vector2.new(1024, 1024), offset = Vector2.new(0, 0), minRect = 230, transparency = 0.45 },
	Clay = { image = "rbxassetid://109457451808302", size = Vector2.new(1024, 1024), offset = Vector2.new(0, 0), minRect = 230, transparency = 0.45 },
	Mud = { image = "rbxassetid://80852625909932", size = Vector2.new(1024, 1024), offset = Vector2.new(0, 0), minRect = 230, transparency = 0.45 },
	Oxygen = { image = "rbxassetid://111452302204388", size = Vector2.new(1024, 1024), offset = Vector2.new(0, 0), minRect = 230, transparency = 0.45 },
	Swamp = { image = "rbxassetid://70645369351699", size = Vector2.new(1024, 1024), offset = Vector2.new(0, 0), minRect = 230, transparency = 0.45 },
	Life = { image = "rbxassetid://113335873777451", size = Vector2.new(1024, 1024), offset = Vector2.new(0, 0), minRect = 230, transparency = 0.45 },
	Plant = { image = "rbxassetid://90252585546334", size = Vector2.new(1024, 1024), offset = Vector2.new(0, 0), minRect = 230, transparency = 0.45 },
	Tree = { image = "rbxassetid://111457070653085", size = Vector2.new(1024, 1024), offset = Vector2.new(0, 0), minRect = 230, transparency = 0.45 },
	Island = { image = "rbxassetid://76694454854485", size = Vector2.new(1024, 1024), offset = Vector2.new(0, 0), minRect = 230, transparency = 0.45 },
	Metal = { image = "rbxassetid://76981284569717", size = Vector2.new(1024, 1024), offset = Vector2.new(0, 0), minRect = 230, transparency = 0.45 },
	Coal = { image = "rbxassetid://96173022069120", size = Vector2.new(1024, 1024), offset = Vector2.new(0, 0), minRect = 230, transparency = 0.45 },
	Diamond = { image = "rbxassetid://98047222340324", size = Vector2.new(1024, 1024), offset = Vector2.new(0, 0), minRect = 230, transparency = 0.45 },
	Smog = { image = "rbxassetid://70622572542904", size = Vector2.new(1024, 1024), offset = Vector2.new(0, 0), minRect = 230, transparency = 0.45 },
	Explosion = { image = "rbxassetid://132753710528840", size = Vector2.new(1024, 1024), offset = Vector2.new(0, 0), minRect = 230, transparency = 0.45 },
	Earthquake = { image = "rbxassetid://96272691072896", size = Vector2.new(1024, 1024), offset = Vector2.new(0, 0), minRect = 230, transparency = 0.45, color = Color3.fromRGB(200, 184, 162) },
	Sound = { image = "rbxassetid://120034132800683", size = Vector2.new(1024, 1024), offset = Vector2.new(0, 0), minRect = 230, transparency = 0.45 },
	Ash = { image = "rbxassetid://76401224209587", size = Vector2.new(1024, 1024), offset = Vector2.new(0, 0), minRect = 230, transparency = 0.45 },
	Rust = { image = "rbxassetid://130796700577705", size = Vector2.new(1024, 1024), offset = Vector2.new(0, 0), minRect = 230, transparency = 0.45 },
	Antimatter = { image = "rbxassetid://113527093948284", size = Vector2.new(1024, 1024), offset = Vector2.new(0, 0), minRect = 230, transparency = 0.45 },
	Poison = { image = "rbxassetid://111783088527287", size = Vector2.new(1024, 1024), offset = Vector2.new(0, 0), minRect = 230, transparency = 0.45 },
	Frost = { image = "rbxassetid://91697496399287", size = Vector2.new(1024, 1024), offset = Vector2.new(0, 0), minRect = 230, transparency = 0.45 },
	BrickWall = { image = "rbxassetid://124431338199449", size = Vector2.new(1024, 1024), offset = Vector2.new(0, 0), minRect = 230, transparency = 0.45 },
	Ice = { image = "rbxassetid://108825731398089", size = Vector2.new(1024, 1024), offset = Vector2.new(0, 0), minRect = 230, transparency = 0.45 },
	Glass = { image = "rbxassetid://112823841382226", size = Vector2.new(1024, 1024), offset = Vector2.new(0, 0), minRect = 230, transparency = 0.45 },
	Mountain = { image = "rbxassetid://114342886669027", size = Vector2.new(1024, 1024), offset = Vector2.new(0, 0), minRect = 230, transparency = 0.45 },
	Snow = { image = "rbxassetid://109131001964410", size = Vector2.new(1024, 1024), offset = Vector2.new(0, 0), minRect = 230, transparency = 0.45 },
	Steel = { image = "rbxassetid://80813987320074", size = Vector2.new(1024, 1024), offset = Vector2.new(0, 0), minRect = 230, transparency = 0.45 },
	Geyser = { image = "rbxassetid://129498909854311", size = Vector2.new(1024, 1024), offset = Vector2.new(0, 0), minRect = 230, transparency = 0.45 },
	Brick = { image = "rbxassetid://79719523126852", size = Vector2.new(1024, 1024), offset = Vector2.new(0, 0), minRect = 230, transparency = 0.45 },
	Blizzard = { image = "rbxassetid://73104568045976", size = Vector2.new(1024, 1024), offset = Vector2.new(0, 0), minRect = 230, transparency = 0.45 },
	AcidRain = { image = "rbxassetid://82711063683949", size = Vector2.new(1024, 1024), offset = Vector2.new(0, 0), minRect = 230, transparency = 0.45 },
	Cold = { image = "rbxassetid://126276121265263", size = Vector2.new(1024, 1024), offset = Vector2.new(0, 0), minRect = 230, transparency = 0.45 },
	Acid = { image = "rbxassetid://86881899607417", size = Vector2.new(1024, 1024), offset = Vector2.new(0, 0), minRect = 230, transparency = 0.45 },
	Soap = { image = "rbxassetid://118664083608632", size = Vector2.new(1024, 1024), offset = Vector2.new(0, 0), minRect = 230, transparency = 0.45 },
	Plasma = { image = "rbxassetid://116215688501175", size = Vector2.new(1024, 1024), offset = Vector2.new(0, 0), minRect = 230, transparency = 0.45 },
	Drought = { image = "rbxassetid://111339321904599", size = Vector2.new(1024, 1024), offset = Vector2.new(0, 0), minRect = 230, transparency = 0.45 },
	Tornado = { image = "rbxassetid://97194759902934", size = Vector2.new(1024, 1024), offset = Vector2.new(0, 0), minRect = 230, transparency = 0.45 },
}
-- Пикселей текстуры на пиксель экрана в больших ячейках: больше — узор мельче.
Theme.PATTERN_DENSITY = 2.5

-- Фоновая подгрузка узоров: без неё текстура качается при первом показе элемента,
-- и ячейка секунду висит пустой. По одной текстуре за раз и с паузой, чтобы не забить
-- канал и очередь загрузки на старте игры.
task.defer(function()
	local ContentProvider = game:GetService("ContentProvider")
	for _, spec in Theme.patterns do
		pcall(ContentProvider.PreloadAsync, ContentProvider, { spec.image })
		task.wait(0.1)
	end
end)

-- Настройка «Узоры элементов». Уже построенные узоры гасятся, как решётка панелей.
local patternsEnabled = Settings.Get("elementPatterns")
local patternLabels = setmetatable({}, { __mode = "k" })

Settings.Changed.Event:Connect(function(key, value)
	if key ~= "elementPatterns" then
		return
	end
	patternsEnabled = value
	for label in patternLabels do
		label.Visible = value
	end
end)

local function fitPattern(label)
	local spec = Theme.patterns[label:GetAttribute("Element")]
	local inst = label.Parent
	if not spec or not inst then
		return
	end
	local abs = inst.AbsoluteSize
	if abs.Y < 1 then
		return
	end
	local want = abs * math.max(spec.density or Theme.PATTERN_DENSITY, (spec.minRect or 0) / abs.Y)
	if want.X < 1 or want.Y < 1 then
		return
	end
	-- Ячейка шире текстуры — окно ужимается целиком, с сохранением пропорций.
	local k = math.min(1, spec.size.X / want.X, spec.size.Y / want.Y)
	local rect = want * k
	-- Не меньше нуля: при rect == size округление давало -1e-14, и clamp падал, пока
	-- ячейка меняла размер (раскрытие окна, толчок производителя).
	local free = spec.size - rect
	label.ImageRectSize = rect
	label.ImageRectOffset = Vector2.new(
		math.clamp(spec.offset.X, 0, math.max(free.X, 0)),
		math.clamp(spec.offset.Y, 0, math.max(free.Y, 0))
	)
end

-- У слишком тёмного элемента узор его же цветом тонул в тёмном корпусе, поэтому узор
-- осветляется в сторону белого, сохраняя оттенок (решение автора). Порог низкий:
-- Земля и подобные средне-тёмные цвета остаются своим цветом.
Theme.PATTERN_DARK_V = 0.5
Theme.PATTERN_LIGHTEN = 0.55

function Theme.PatternTint(color)
	local _, _, v = color:ToHSV()
	if v >= Theme.PATTERN_DARK_V then
		return color
	end
	return color:Lerp(Color3.new(1, 1, 1), Theme.PATTERN_LIGHTEN)
end

-- key — ключ элемента из Elements; nil или элемент без узора снимает узор с ячейки.
function Theme.Pattern(inst, key, color, dim)
	local spec = key and Theme.patterns[key]
	local label = inst:FindFirstChild("Pattern")
	if not spec then
		if label then
			label:Destroy()
		end
		return nil
	end
	-- Слой узора создаётся один раз и встаёт под всеми остальными детьми ячейки.
	-- При равном ZIndex поздний ребёнок рисуется поверх: узор, созданный последним,
	-- закрывал засечку и надписи. Остальные дети перевешиваются в конец списка.
	if not label then
		label = Instance.new("ImageLabel")
		label.Name = "Pattern"
		label.BackgroundTransparency = 1
		label.BorderSizePixel = 0
		label.ScaleType = Enum.ScaleType.Stretch
		label.Parent = inst
		inst:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			if label.Parent == inst then
				fitPattern(label)
			end
		end)
		patternLabels[label] = true
		for _, child in inst:GetChildren() do
			if child ~= label and child:IsA("GuiObject") then
				child.Parent = nil
				child.Parent = inst
			end
		end
	end
	Theme.Bleed(label, UDim2.new(0, 0, 0, 0), UDim2.new(1, 0, 1, 0))
	local corner = inst:FindFirstChildOfClass("UICorner")
	if corner then
		Theme.Corner(label, corner.CornerRadius.Scale == 0 and corner.CornerRadius.Offset or 999)
	end
	label:SetAttribute("Element", key)
	label.Image = spec.image
	label.ImageColor3 = spec.color or Theme.PatternTint(color)
	local base = spec.transparency or 0.7
	label.ImageTransparency = dim and base + (1 - base) * 0.6 or base
	label.ZIndex = inst.ZIndex
	label.Visible = patternsEnabled
	fitPattern(label)
	return label
end

-- Ячейка сущности: глубоко затемнённый корпус её цвета, кант в пиксель и засечка
-- слева. До задачи #90 цвет заливал всю ячейку в полную силу, а надписи лежали на
-- тёмной начинке внутри; строка читалась как ярлык, а десяток таких ярлыков подряд —
-- как витрина. Теперь тёмная сама ячейка, и отдельная подложка под текст не нужна вовсе.
--
-- dim — невыбранное состояние (кнопки панели стройки): корпус уходит глубже, засечка
-- и кант гаснут. Приглушать сам цвет на входе (Lerp к фону) больше нельзя: от затемнённого
-- второй раз цвета не осталось бы вовсе — выбор передаётся флагом.
function Theme.ElementFill(inst, color, opts)
	opts = opts or {}
	local dim = opts.dim

	if inst:IsA("GuiButton") then
		Theme.Button(inst, "ghost") -- скругление, снятая декорация и осветление по наведению
	else
		clearDecor(inst)
		inst.BorderSizePixel = 0
	end

	local lit = Theme.Legible(color)
	-- Корпус ушёл глубже (0.9 против 0.86): цвет теперь несёт дымка поверх него,
	-- и два цветных слоя один на другом дали бы ту же витринную яркость.
	local body = Theme.Shadowed(color, dim and 0.95 or 0.9)
	inst.BackgroundColor3 = body
	inst.BackgroundTransparency = 0
	inst:SetAttribute("ThemeBase", body)
	Theme.Corner(inst, Theme.radius.control)
	Theme.Stroke(inst, Theme.Shadowed(lit, dim and 0.74 or 0.45), 1, 0)
	Theme.Wash(inst, color, dim, opts.right)
	Theme.Swatch(inst, dim and Theme.Shadowed(lit, 0.45) or color, opts.wide, opts.right)
	-- opts.element — ключ элемента, если ячейка про элемент: у него может быть свой узор.
	Theme.Pattern(inst, opts.element, lit, dim)
	-- Длинное имя обрезается краем ячейки, а не вылезает за неё.
	inst.ClipsDescendants = true
	return inst
end

-- Начинка ячейки — теперь только геометрия: прямоугольник внутри ячейки, отступивший
-- от канта на inset, а слева — ещё и на ширину засечки, чтобы текст на неё не налезал.
-- Своего фона у неё больше нет: тёмная теперь сама ячейка, и вторая плашка поверх неё
-- была бы прямоугольником того же цвета — виден только шов.
--
-- Надписи в строках с несколькими полями кладутся ВНУТРЬ начинки-Frame, а не получают
-- каждая свою: так отступ от края считается один раз.
Theme.CELL_INSET = 5

function Theme.Inner(inst, inset)
	inset = inset or Theme.CELL_INSET
	-- Отступ слева берётся у самого блока, а не задан числом: блок бывает то широким
	-- (строка списка с номером), то полоской (квадратная кнопка), и число разошлось бы.
	local swatch = inst.Parent and inst.Parent:FindFirstChild("Swatch")
	local bar = swatch and swatch.Size.X.Offset or Theme.EDGE_W
	-- С какой стороны стоит блок, начинка узнаёт у него самого (AnchorPoint), а не из
	-- отдельного аргумента: сборщик ячейки и так знает сторону, и второе такое же число
	-- рядом однажды разошлось бы с первым.
	local onRight = swatch ~= nil and swatch.AnchorPoint.X == 1
	inst.BackgroundTransparency = 1
	inst.BorderSizePixel = 0
	inst.AnchorPoint = Vector2.new(0, 0)
	inst.Position = UDim2.new(0, inset + (onRight and 0 or bar), 0, inset)
	inst.Size = UDim2.new(1, -(inset * 2 + bar), 1, -inset * 2)

	if inst:IsA("TextLabel") or inst:IsA("TextButton") then
		inst.TextColor3 = Theme.color.text
		-- Размер задан ячейкой, и обрезка длинного имени работает:
		-- с AutomaticSize она не действует вовсе.
		inst.AutomaticSize = Enum.AutomaticSize.None
		inst.TextTruncate = Enum.TextTruncate.AtEnd
	end
	return inst
end

-- Ячейка-кнопка сущности со своим цветом: элемента (списки инвентаря, слоты крафта,
-- заливка в башню) или постройки (мобильная панель стройки).
--
-- Текст переехал с самой кнопки на дочернюю надпись: собственный текст кнопки
-- рисуется ПОД её детьми, и засечка накрыла бы его. Вызывающие по-прежнему пишут
-- button.Text — сборщик сам переносит написанное на надпись и гасит текст кнопки.
-- Менять его потом — только через Theme.SetCellText: прямая запись в button.Text ничего не покажет.
--
-- color = nil — пустой слот: ячейка гаснет до muted, цвета нет — показывать нечего.
-- opts — то же, что у ElementFill: dim (не выбрана) и wide (широкий цветной блок).
function Theme.ElementButton(button, color, opts)
	-- Образец цвета слева больше не нужен: его место заняла засечка ячейки.
	local chip = button:FindFirstChild("Chip")
	if chip then
		chip:Destroy()
	end

	local caption = button:FindFirstChild("Caption")
	if not caption then
		caption = Instance.new("TextLabel")
		caption.Name = "Caption"
		caption.AnchorPoint = Vector2.new(0, 0)
		caption.Position = UDim2.new(0, 0, 0, 0)
		caption.Size = UDim2.new(1, 0, 1, 0)
		caption.BackgroundTransparency = 1
		caption.Parent = button
	end
	caption.ZIndex = button.ZIndex
	-- FontFace, а не Font: шрифт теперь задан начертанием семейства (Theme.font), а у такого
	-- шрифта свойство Font читается как Unknown — копия через него сбросила бы надпись
	-- в шрифт по умолчанию.
	caption.FontFace = button.FontFace
	caption.TextSize = button.TextSize
	-- Разметка тоже переезжает: ячейка списка пишет имя и число разным кеглем
	-- в одной строке (Theme.Readout), а без этого теги печатались бы как текст.
	caption.RichText = button.RichText
	-- И выравнивание: строка списка прижата влево, квадратная кнопка панели
	-- стройки — по центру; решает вызывающий, а не сборщик.
	caption.TextXAlignment = button.TextXAlignment
	caption.TextYAlignment = button.TextYAlignment
	-- Перенос по словам тоже переезжает на надпись: без него «Центрифуга» в квадратной
	-- кнопке панели стройки просто обрезалась бы.
	caption.TextWrapped = button.TextWrapped
	if button.Text ~= "" then
		caption.Text = button.Text
		button.Text = ""
	end

	if color == nil then
		Theme.Button(button, "muted")
		button.ClipsDescendants = false
		-- Блок и дымка сносятся вместе с цветом: слот чистят тем же сборщиком, и оставшийся
		-- цвет прежнего элемента читался бы как «слот всё ещё занят».
		for _, name in { "Swatch", "Wash", "Pattern" } do
			local part = button:FindFirstChild(name)
			if part then
				part:Destroy()
			end
		end
		caption.BackgroundTransparency = 1
		caption.TextColor3 = Theme.buttonKind.muted.text
		caption.AnchorPoint = Vector2.new(0, 0)
		caption.Position = UDim2.new(0, 0, 0, 0)
		caption.Size = UDim2.new(1, 0, 1, 0)
		return button
	end

	Theme.ElementFill(button, color, opts)
	Theme.Inner(caption)
	caption.TextColor3 = opts and opts.dim and Theme.color.textDim or Theme.color.text
	return button
end

-- Поменять надпись уже собранной ячейки. Прямая запись в button.Text бесполезна: текст самой
-- кнопки погашен и накрыт подложкой (кнопка поворота меняет подпись на каждом нажатии).
function Theme.SetCellText(button, text)
	local caption = button:FindFirstChild("Caption")
	if caption then
		caption.Text = text
	else
		button.Text = text
	end
	return button
end

-- Полоса прокрутки. По умолчанию Roblox рисует её почти белой, и на приглушённом
-- интерфейсе она оказывается самым ярким пятном на экране — ярче любых данных.
function Theme.Scroller(frame)
	frame.ScrollBarImageColor3 = Theme.color.hairline
	frame.ScrollBarImageTransparency = 0.2
	frame.BorderSizePixel = 0
	return frame
end

-- Сетка ячеек вместо одной колонки. Окна теперь во весь экран, а список из строк во всю
-- ширину — это полоса в полтора метра с двумя словами по краям и чёрнотой под ней.
-- Колонок столько, сколько влезает по целевой ширине ячейки; остаток они делят поровну,
-- поэтому правый край сетки всегда вровень с краем списка, каким бы ни был экран.
-- Числа живут атрибутами на самой раскладке: список пересобирается через ClearAllChildren,
-- и держать их в замыкании значило бы заводить по копии на каждую пересборку.
function Theme.GridFit(layout)
	local parent = layout and layout.Parent
	if not parent then
		return 1
	end
	local gap = layout:GetAttribute("Gap") or 8
	local targetW = layout:GetAttribute("TargetW") or 320
	local cellH = layout:GetAttribute("CellH") or 48
	-- Те же восемь пикселей запаса, что и у строк: полоса прокрутки ложится поверх
	-- содержимого, а не рядом с ним.
	local width = parent.AbsoluteSize.X - 8
	if width < 40 then
		return 1 -- до первой отрисовки размера ещё нет, посчитаем на AbsoluteSize
	end
	local cols = math.max(1, math.floor((width + gap) / (targetW + gap)))
	layout.CellSize = UDim2.fromOffset(math.floor((width - gap * (cols - 1)) / cols), cellH)
	layout.FillDirectionMaxCells = cols
	return cols
end

-- Создаёт (или находит) раскладку-сетку в списке и сразу подгоняет её под текущую ширину.
function Theme.Grid(parent, cellH, targetW, gap)
	gap = gap or 8
	local layout = parent:FindFirstChildOfClass("UIGridLayout")
	if not layout then
		layout = Instance.new("UIGridLayout")
		layout.Parent = parent
	end
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.CellPadding = UDim2.fromOffset(gap, gap)
	layout:SetAttribute("Gap", gap)
	layout:SetAttribute("TargetW", targetW)
	layout:SetAttribute("CellH", cellH)
	Theme.GridFit(layout)
	return layout
end

-- Содержимое уже своего поля (дерево справочника — ровно 708 пикселей) ставится
-- по центру, а не прижимается влево: иначе на широком экране справа остаётся полэкрана
-- черноты, а рисунок выглядит съехавшим, а не поставленным.
function Theme.CenterCanvas(scroll, canvasW)
	local pad = scroll:FindFirstChildOfClass("UIPadding")
	if not pad then
		pad = Instance.new("UIPadding")
		pad.Parent = scroll
	end
	pad.PaddingLeft = UDim.new(0, math.max(0, math.floor((scroll.AbsoluteSize.X - canvasW) / 2)))
	return pad
end

function Theme.Field(box)
	box.BackgroundColor3 = Theme.color.field
	box.BackgroundTransparency = 0
	box.BorderSizePixel = 0
	box.TextColor3 = Theme.color.text
	box.PlaceholderColor3 = Theme.color.textMute
	Theme.Corner(box, Theme.radius.control)
	Theme.Hairline(box, 0.35)
	return box
end

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
