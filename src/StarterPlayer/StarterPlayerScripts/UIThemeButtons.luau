-- Кнопки, образцы и заливка элементов, паттерны, сетки, поле ввода (Theme.Button, Theme.Pattern, Theme.Grid…)
-- Вынесено из UITheme.luau без изменений кода (задача #240): файл был слишком
-- велик, чтобы агент читал его целиком. deps — локальные основного файла, которые нужны
-- этому куску; возвращается то, что основной файл использует дальше.
return function(deps)
	local Theme = deps.Theme
	local Settings = deps.Settings
	local clearDecor = deps.clearDecor
	local hoverTweens = deps.hoverTweens
	local playHoverTween = deps.playHoverTween

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

end
