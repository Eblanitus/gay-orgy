local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")

local MobileUI = {}

-- Размер вьюпорта читается из камеры, а не из UserInputService: у сервиса свойства
-- ViewportSize нет (это и роняло все клиентские скрипты при require).
--
-- Сразу на старте клиента Camera.ViewportSize иногда ещё не успевает подхватить настоящий
-- размер экрана — особенно заметно с симулятором устройств в Studio: на первом кадре после
-- Play камера держит sentinel (1, 1), а не честный 0x0 (проверено печатью в консоль),
-- и тогда MobileUI.Scale() у всех, кто его использует (CraftingUI, ElementPicker, Hud),
-- давал ширину 0 — окна становились невидимыми. Порог поэтому не "> 0", а "> 100": ни у
-- одного реального устройства ширина вьюпорта меньше не бывает, а sentinel он отсекает.
-- Ждём, пока ViewportSize не станет осмысленным, не дольше пяти кадров, чтобы не зависнуть,
-- если камера почему-то так и не проснётся.
local camera = Workspace.CurrentCamera
for _ = 1, 60 do
	if camera.ViewportSize.X > 100 then
		break
	end
	RunService.Heartbeat:Wait()
end
local viewport = camera.ViewportSize

-- Порядок слоёв (ScreenGui.DisplayOrder). Раньше все ScreenGui оставались на нуле по умолчанию,
-- и кто окажется сверху, решал сам движок по порядку создания: окно Лаборатории то
-- накрывало HUD, то пряталось под ним, а кнопка «Начать волну» просвечивала сквозь окно.
-- Шаг между слоями большой, чтобы новый слой можно было вставить, ничего не переставляя.
MobileUI.Layer = {
	Hud = 10, -- показания забега: волна, материя, прорывы, кнопка волны
	Controls = 20, -- экранные кнопки поверх мира: панель стройки, подсказка режима
	Window = 100, -- модальные окна: Лаборатория, инвентарь, выбор элемента
	-- Главное меню во весь экран. Выше окон — оно их закрывает целиком и иначе открытая
	-- Лаборатория торчала бы поверх меню; но ниже Notify — итог забега и сообщения
	-- сервера должны быть видны в любом случае.
	Menu = 150,
	Notify = 200, -- сообщения сервера и итог забега — видны и поверх открытого окна
}

MobileUI.MIN_TAP = 48

-- Высота полосы Roblox сверху экрана (меню, чат, микрофон): 58 пикселей на ПК, на
-- телефоне больше. Окна во весь экран рисуются ПОД ней (ScreenGui.IgnoreGuiInset),
-- иначе сверху остаётся щель с игрой — её и увидел автор в задаче #105. Но содержимое
-- окна начинается ниже полосы: заголовок, заехавший под кнопки Roblox, не прочесть
-- и не нажать.
--
-- Число не константа: на телефоне полоса выше, а в полноэкранном режиме её может
-- не быть вовсе. Кто на нём строится — подписывается через OnViewportChanged.
local function readTopInset()
	local top = GuiService:GetGuiInset()
	return math.ceil(top.Y)
end

MobileUI.TopInset = readTopInset()

-- Телефон определяется по КОРОТКОЙ стороне вьюпорта, а не по ширине: при повороте
-- ширина с высотой меняются местами, и планшет 1024x768 в портрете считался бы
-- мобильным, а в альбоме — уже нет, то есть весь мобильный макет переключался от поворота.
-- Короткая сторона от ориентации не зависит.
local function computeIsMobile(size)
	return UserInputService.TouchEnabled and math.min(size.X, size.Y) <= 900
end

MobileUI.viewportX = viewport.X
MobileUI.viewportY = viewport.Y
MobileUI.isMobile = computeIsMobile(viewport)

-- Отступ от края экрана у всего, что живёт по углам поверх мира: панель показаний,
-- кнопка промокода, кнопки инвентаря и меню. Раньше каждый скрипт брал своё число —
-- панель стояла в 20 пикселях от левого края, кнопка инвентаря в 20 от правого,
-- а кнопка меню в 12, и правый столбец получался рваным.
MobileUI.EDGE = 20

-- Кнопки в правом верхнем углу растут вниз одним столбцом. Размер у всех один:
-- столбец из кнопок разной ширины, прижатых к одному краю, читается как случайно
-- сошедшиеся кнопки, а не как одна панель. Высота на телефоне — MIN_TAP (кнопка
-- меню была 32, палец накрывает её целиком), на ПК 34 — как у кнопки инвентаря.
-- Ширина — по самой длинной надписи столбца («ИНВЕНТАРЬ (I)»).
MobileUI.CORNER_H = MobileUI.isMobile and MobileUI.MIN_TAP or 34
MobileUI.CORNER_W = MobileUI.isMobile and 84 or 150
MobileUI.CORNER_GAP = 8

-- Ставит кнопку в правый верхний угол на место с номером slot (0 — самая верхняя).
-- Номера раздаются вручную и живут здесь же, рядом со слоями: скрипты собираются
-- независимо друг от друга, и вычислить порядок в момент сборки неоткуда.
-- При slot = 1 кнопка меню налезала на квадратную кнопку инвентаря на телефоне
-- (48 высоты против отступа 46) — теперь зазор считается от общей высоты.
MobileUI.CornerSlot = {
	Inventory = 0,
	Menu = 1,
	WaveEditor = 2, -- открывается промокодом, потому самый нижний: у большинства его нет вовсе
}

function MobileUI.TopRight(gui, slot)
	gui.AnchorPoint = Vector2.new(1, 0)
	gui.Size = UDim2.fromOffset(MobileUI.CORNER_W, MobileUI.CORNER_H)
	gui.Position = UDim2.new(
		1,
		-MobileUI.EDGE,
		0,
		MobileUI.EDGE + slot * (MobileUI.CORNER_H + MobileUI.CORNER_GAP)
	)
	return gui
end

-- Размер вьюпорта теперь не заморожен на момент загрузки. Именно это ломало вёрстку
-- после поворота: окна считали пиксельную ширину и отступ центрирования один раз,
-- и после смены ориентации эти числа описывали уже другой экран — окно уезжало из
-- центра и оказывалось выше экрана. Размеры в долях (Scale) движок пересчитывает сам,
-- а тем, кому нужно число (потолок высоты окна), служит OnViewportChanged.
local listeners = {}

local function refresh()
	local size = camera.ViewportSize
	if size.X <= 100 then
		return -- тот же sentinel (1, 1), что и на старте: пересчитать по нему — обнулить вёрстку
	end
	MobileUI.viewportX = size.X
	MobileUI.viewportY = size.Y
	MobileUI.isMobile = computeIsMobile(size)
	MobileUI.TopInset = readTopInset()
	for _, fn in listeners do
		task.spawn(fn, size)
	end
end

local viewportConn = nil

local function watchCamera(cam)
	if viewportConn then
		viewportConn:Disconnect()
	end
	camera = cam
	viewportConn = cam:GetPropertyChangedSignal("ViewportSize"):Connect(refresh)
	refresh()
end

watchCamera(camera)

-- Полоса Roblox сверху меняется и без смены размера экрана: на первых кадрах клиента
-- GetGuiInset ещё отдаёт ноль, а в полноэкранном режиме полоса уезжает совсем. Подписка
-- в pcall: TopbarInset появился в API не сразу, и на старом клиенте обращение к нему
-- уронило бы весь MobileUI, а с ним и весь клиентский интерфейс.
pcall(function()
	GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(refresh)
end)

-- Камера пересоздаётся (например, при респауне) — иначе подписка осталась бы на старой.
Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	if Workspace.CurrentCamera then
		watchCamera(Workspace.CurrentCamera)
	end
end)

function MobileUI.Scale(percent)
	return math.floor(MobileUI.viewportX * percent)
end

-- Подписка на смену размера экрана (поворот телефона, изменение окна на ПК).
-- Колбэк вызывается сразу же — чтобы у вызывающего не было отдельной ветки «посчитать в первый раз».
function MobileUI.OnViewportChanged(fn)
	table.insert(listeners, fn)
	fn(camera.ViewportSize)
end

return MobileUI