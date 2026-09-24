-- Экранный HUD: номер волны, материя, прочность лабораторного стола. Состояние только на сервере,
-- этот скрипт лишь отображает то, что пришло через RemoteEvent.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local MobileUI = require(script.Parent:WaitForChild("MobileUI"))
local Theme = require(script.Parent:WaitForChild("UITheme"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "GameHud"
screenGui.ResetOnSpawn = false
screenGui.DisplayOrder = MobileUI.Layer.Hud
screenGui.Parent = playerGui

-- Итог забега живёт отдельным ScreenGui поверх окон, а не вместе с остальным HUD:
-- победу и поражение надо видеть, даже если в этот момент открыта Лаборатория.
local resultGui = Instance.new("ScreenGui")
resultGui.Name = "GameResult"
resultGui.ResetOnSpawn = false
resultGui.DisplayOrder = MobileUI.Layer.Notify
resultGui.Parent = playerGui

-- Показания стояли тремя строками в столбик и занимали 110 пикселей высоты. Теперь
-- это три колонки в одну полосу: подпись мелким и под ней крупное число. Три числа
-- рядом считываются одним взглядом, а панель перестала занимать четверть высоты экрана
-- на телефоне.
local STAT_W = 66
local STAT_GAP = 6

-- Ширина панели вынесена в имя: по ней равняется кнопка промокода под ней.
-- Прежде кнопка была 130 при панели в 232, и левый столбец шёл уступом.
local PANEL_W = 232

local frame = Instance.new("Frame")
frame.Size = UDim2.new(0, PANEL_W, 0, 72)
frame.Position = UDim2.new(0, MobileUI.EDGE, 0, MobileUI.EDGE)
frame.BorderSizePixel = 0
frame.Parent = screenGui
-- Панель волны/материи/прочности стола имеет смысл только во время забега — скрыта, пока игрок
-- в лобби, появляется на WaveReady/WaveChanged, прячется обратно на RunEnded.
frame.Visible = false

-- Весь внешний вид панели — в UITheme: плотная тёмная плашка со скруглением
-- и нейтральной границей. Геометрию (220x110 в углу) сборщик не трогает — она
-- выверена замерами мобильного экрана (задача #78).
Theme.Panel(frame, { scene = "run" })

-- Колонка показания: подпись сверху мелким, число под ней крупным. Возвращается только
-- число: подпись ставится один раз и больше не меняется.
local statOrder = 0

local function makeStat(caption)
	local x = 14 + statOrder * (STAT_W + STAT_GAP)
	statOrder += 1

	local cap = Instance.new("TextLabel")
	cap.Size = UDim2.new(0, STAT_W, 0, 12)
	cap.Position = UDim2.new(0, x, 0, 10)
	cap.TextSize = 10
	cap.TextXAlignment = Enum.TextXAlignment.Left
	cap.Text = caption
	cap.Parent = frame
	Theme.StatCaption(cap)

	local value = Instance.new("TextLabel")
	value.Size = UDim2.new(0, STAT_W, 0, 26)
	value.Position = UDim2.new(0, x, 0, 22)
	value.BackgroundTransparency = 1
	value.TextSize = 22
	value.TextColor3 = Theme.color.text
	value.TextXAlignment = Enum.TextXAlignment.Left
	value.TextTruncate = Enum.TextTruncate.AtEnd
	value.Parent = frame
	-- Приборный шрифт только у числа: подпись живёт обычным начертанием (Theme.StatCaption).
	Theme.Display(value)
	return value
end

-- Цвет Прочности считается от ДОЛИ оставшегося, а не от числа: максимум у стола
-- свой (LabTable.MAX_HP), и порог в долях проще менять баланс в одном месте, а не здесь.
local function hpColor(hp, limit)
	local share = limit > 0 and hp / limit or 0
	if share > 0.6 then
		return Theme.color.accent
	elseif share > 0.3 then
		return Theme.color.warn
	end
	return Theme.color.danger
end

local waveLabel = makeStat("ВОЛНА")
waveLabel.Text = "-/-"
waveLabel.TextColor3 = Theme.color.accent

local matterLabel = makeStat("МАТЕРИЯ")
matterLabel.Text = "0"
matterLabel.TextColor3 = Theme.color.energy

local hpLabel = makeStat("ПРОЧНОСТЬ")
hpLabel.Text = "-"
hpLabel.TextColor3 = Theme.color.accent

-- Шкала прочности: одна заливка по доле оставшегося HP, а не ячейки: прочность стола
-- (alchemy_td_enemies_v1.1.md, «Лабораторный стол») считается сотнями очков (LabTable.MAX_HP),
-- по очку на ячейку панель не построишь.
local hpBar = Instance.new("Frame")
hpBar.Size = UDim2.new(1, -28, 0, 6)
hpBar.Position = UDim2.new(0, 14, 0, 54)
hpBar.BackgroundColor3 = Theme.color.danger:Lerp(Theme.color.panel, 0.72)
hpBar.BackgroundTransparency = 0
hpBar.BorderSizePixel = 0
hpBar.Parent = frame
Theme.Corner(hpBar, 2)

local hpFill = Instance.new("Frame")
hpFill.BorderSizePixel = 0
hpFill.Parent = hpBar
Theme.Corner(hpFill, 2)

-- Прочность читается с атрибутов Workspace.CraftTable напрямую (см. ниже), а не через ремоут:
-- стол — обычный Instance в Workspace и реплицируется всем клиентам сам по себе.
local function renderHpBar(hp, limit)
	local share = limit > 0 and math.clamp(hp / limit, 0, 1) or 0
	hpFill.Size = UDim2.new(share, 0, 1, 0)
	hpFill.BackgroundColor3 = hpColor(hp, limit)
end

-- Промокод: свёрнутая кнопка под инфо-панелью, разворачивает поле ввода и кнопку применения.
-- Сама проверка кода — на сервере (см. ServerScriptService.PromoCode), клиент лишь отправляет строку.
-- Высота элементов промокода на телефоне — MobileUI.MIN_TAP: прежние 28/30 пикселей
-- палец накрывает целиком, попасть в них не глядя нельзя (тот же порог, что у
-- InventoryUI.ROW_H и CraftingUI.BUY_ROW_H).
local PROMO_FIELD_H = MobileUI.isMobile and MobileUI.MIN_TAP or 30

local promoButton = Instance.new("TextButton")
-- Шириной в панель над ней. y = 104 подходит обоим состояниям левого угла:
-- в забеге под панелью показаний (20 + 72), в лобби — под иконкой плутония
-- (20 + 76, см. LobbyUI.PANEL_SIZE).
promoButton.Size = UDim2.new(0, PANEL_W, 0, MobileUI.isMobile and MobileUI.MIN_TAP or 28)
promoButton.Position = UDim2.new(0, MobileUI.EDGE, 0, 104)
promoButton.FontFace = Theme.font.strong
promoButton.TextSize = 14
promoButton.Text = "ПРОМОКОД"
promoButton.Parent = screenGui

Theme.Button(promoButton, "ghost")

local promoFrame = Instance.new("Frame")
-- На телефоне панель не висит под кнопкой, а встаёт по центру экрана. Под кнопкой она
-- упиралась в панель стройки в левом нижнем углу (замерено: пересечение 220x6 ещё при
-- полях в 30px), а с полями в MIN_TAP высотой налезала бы на неё целиком.
promoFrame.AnchorPoint = MobileUI.isMobile and Vector2.new(0.5, 0.5) or Vector2.new(0, 0)
promoFrame.Size = UDim2.new(0, MobileUI.isMobile and 260 or PANEL_W, 0, PROMO_FIELD_H * 2 + 20)
promoFrame.Position = MobileUI.isMobile and UDim2.new(0.5, 0, 0.5, 0) or UDim2.new(0, MobileUI.EDGE, 0, 140)
promoFrame.Visible = false
promoFrame.Parent = screenGui

local promoPadding = Instance.new("UIPadding")
promoPadding.PaddingTop = UDim.new(0, 10)
promoPadding.PaddingLeft = UDim.new(0, 10)
promoPadding.PaddingRight = UDim.new(0, 10)
promoPadding.Parent = promoFrame

Theme.Panel(promoFrame, { scene = "dialog" })

local promoInput = Instance.new("TextBox")
promoInput.Size = UDim2.new(1, 0, 0, PROMO_FIELD_H)
promoInput.FontFace = Theme.font.body
promoInput.TextSize = 16
promoInput.PlaceholderText = "Введите код…"
promoInput.ClearTextOnFocus = false
promoInput.Text = ""
promoInput.Parent = promoFrame

Theme.Field(promoInput)

local promoApply = Instance.new("TextButton")
promoApply.Size = UDim2.new(1, 0, 0, PROMO_FIELD_H)
promoApply.Position = UDim2.new(0, 0, 0, PROMO_FIELD_H + 10)
promoApply.FontFace = Theme.font.strong
promoApply.TextSize = 16
promoApply.Text = "ПРИМЕНИТЬ"
promoApply.Parent = promoFrame

Theme.Button(promoApply, "action")

promoButton.MouseButton1Click:Connect(function()
	promoFrame.Visible = not promoFrame.Visible
	if promoFrame.Visible then
		promoInput:CaptureFocus()
	end
end)

local function submitPromoCode()
	local code = promoInput.Text
	if code == "" then
		return
	end
	Remotes.RedeemCode:FireServer(code)
	promoInput.Text = ""
end

promoApply.MouseButton1Click:Connect(submitPromoCode)
promoInput.FocusLost:Connect(function(enterPressed)
	if enterPressed then
		submitPromoCode()
	end
end)

-- Итог забега собран той же ячейкой, что и строки списков: тёмный корпус в цвете исхода
-- (зелёный — победа, красный — поражение), кант и засечка. Раньше это была голая
-- надпись с чёрной обводкой поверх арены — единственный элемент интерфейса без своей плашки.
local resultFrame = Instance.new("Frame")
resultFrame.Visible = false
resultFrame.Parent = resultGui

local resultLabel = Instance.new("TextLabel")
-- Ширина долей экрана и центрирование через AnchorPoint. Прежний ручной отступ -resultW/2
-- считался один раз при загрузке: после поворота телефона ширина вьюпорта уже другая,
-- а отступ оставался от старой, и баннер уезжал из центра. AnchorPoint от размера не зависит.
-- На телефоне баннер опущен под панель лобби и стал ниже. Он висит до следующего
-- забега, а на низком альбомном экране 0.25 высоты — это ровно строка уровня
-- в панели лобби (замерено на 750x322: баннер 37,80..712,170 против панели
-- 20,20..485,128 — перекрытие 447x47). Строка уровня — кнопка выбора, её надо и
-- читать, и нажимать сразу после поражения.
resultFrame.AnchorPoint = Vector2.new(0.5, 0)
resultFrame.Size = MobileUI.isMobile and UDim2.new(0.9, 0, 0, 56) or UDim2.new(0, 500, 0, 90)
resultFrame.Position = MobileUI.isMobile and UDim2.new(0.5, 0, 0.59, 0) or UDim2.new(0.5, 0, 0.25, 0)
resultLabel.TextWrapped = true
resultLabel.TextSize = MobileUI.isMobile and 40 or 52
resultLabel.TextStrokeTransparency = 1
resultLabel.Text = ""
resultLabel.Parent = resultFrame

-- Тот же приборный шрифт, что у показаний: итог забега — самая крупная надпись в игре,
-- и Gotham Black рядом с остальным интерфейсом читался как чужая игра.
Theme.Display(resultLabel)

-- Мелкая подпись над словом — тот же строй, что у чисел в списках: сначала что это
-- за показание, потом само значение. Только на ПК: на телефоне баннер всего 56px
-- высотой, и сорокапиксельное слово по центру накрыло бы её целиком.
local resultCaption = nil
if not MobileUI.isMobile then
	resultCaption = Instance.new("TextLabel")
	resultCaption.Size = UDim2.new(1, -28, 0, 12)
	resultCaption.Position = UDim2.new(0, 14, 0, 9)
	resultCaption.TextSize = 11
	resultCaption.ZIndex = resultLabel.ZIndex + 1
	resultCaption.Parent = resultFrame

	Theme.StatCaption(resultCaption)
	resultCaption.TextXAlignment = Enum.TextXAlignment.Left

	-- Слово центрируется в остатке высоты, а не во всём баннере — иначе оно наезжает
	-- на подпись верхними выносными элементами букв.
	local resultPad = Instance.new("UIPadding")
	resultPad.PaddingTop = UDim.new(0, 16)
	resultPad.Parent = resultLabel
end

-- Кнопка вызова волны. Волны не идут сами: сервер сообщает по WaveReady, что готов следующую,
-- и ждёт нажатия — в maze лабиринт строится до волны, и таймер не знает, сколько на это нужно.
local startWaveButton = Instance.new("TextButton")
-- На мобильном кнопка ушла к правому краю и стала уже: внизу теперь панель стройки
-- (TowerInteraction) и родные кнопки Roblox, а прежние 90% ширины по центру накрывали панель целиком.
startWaveButton.AnchorPoint = MobileUI.isMobile and Vector2.new(1, 1) or Vector2.new(0.5, 1)
startWaveButton.Size = MobileUI.isMobile and UDim2.new(0.32, 0, 0, 56) or UDim2.new(0, 280, 0, 52)
-- Кнопка поднята над зоной родной кнопки прыжка Roblox. Та занимает правый нижний угол
-- (замерено на вьюпорте 750x322: JumpButton 655,232..725,302 — 95px от правого края,
-- 90px от нижнего), и в прежнем положении «1, -12» кнопка волны накрывала её целиком:
-- прыжок на телефоне не работал вовсе, а правая треть самой кнопки волны стояла над
-- чужим элементом. Доля 0.7 по высоте, а не пиксельный отступ снизу: на планшете
-- Roblox рисует кнопку прыжка крупнее (120px против 70), и фиксированный отступ,
-- подобранный по телефону, там снова дал бы пересечение.
startWaveButton.Position = MobileUI.isMobile and UDim2.new(1, -12, 0.7, 0) or UDim2.new(0.5, 0, 1, -18)
startWaveButton.AutoButtonColor = true
startWaveButton.FontFace = Theme.font.strong
startWaveButton.TextSize = MobileUI.isMobile and 18 or 24
startWaveButton.TextColor3 = Theme.buttonKind.action.text
startWaveButton.TextTruncate = Enum.TextTruncate.AtEnd
startWaveButton.Text = MobileUI.isMobile and "ВОЛНА ▶" or "НАЧАТЬ ВОЛНУ"
startWaveButton.Visible = false
startWaveButton.Parent = screenGui

-- Пульсирующей обводки здесь больше нет: что игра ждёт именно этого нажатия, говорит
-- само появление кнопки — она видна только между волнами, по WaveReady.
Theme.Button(startWaveButton, "action")

local startSize = Instance.new("UISizeConstraint")
startSize.MaxSize = Vector2.new(240, 56)
startSize.Parent = startWaveButton

-- Волна вызывается не кликом, а удержанием секунду (прямое требование автора). Причина та же,
-- по которой удержанием ставится постройка (TowerInteraction.BUILD_HOLD_TIME): кнопка стоит
-- в той части экрана, где палец и так елозит по камере, и случайный тап запускал волну
-- посреди недостроенного лабиринта — отменить это нечем, волна уже вышла.
local WAVE_HOLD_TIME = 1 -- секунд удержания кнопки перед RequestStartWave

-- Полоска прогресса — узкая планка по низу самой кнопки, а не заливка на всю её площадь:
-- текст кнопки принадлежит самой кнопке и рисуется её ZIndex'ом, любой дочерний кадр того же
-- ZIndex лёг бы поверх надписи и закрыл её.
local holdBar = Instance.new("Frame")
holdBar.Name = "HoldProgress"
holdBar.AnchorPoint = Vector2.new(0, 1)
holdBar.Position = UDim2.new(0, 6, 1, -6)
holdBar.Size = UDim2.new(0, 0, 0, 6)
holdBar.BackgroundColor3 = Theme.color.accent
holdBar.BorderSizePixel = 0
holdBar.Parent = startWaveButton

Theme.Corner(holdBar, 3)

local holdingWave = false
local waveHoldStart = 0
local waveHoldConn = nil

local function cancelWaveHold()
	holdingWave = false
	if waveHoldConn then
		waveHoldConn:Disconnect()
		waveHoldConn = nil
	end
	holdBar.Size = UDim2.new(0, 0, 0, 6)
end

local function startWaveHold()
	if holdingWave or not startWaveButton.Visible then
		return
	end
	holdingWave = true
	waveHoldStart = os.clock()
	-- Heartbeat, а не RenderStepped: на RenderStepped висит вся анимация построек, и в
	-- Play-сессии Studio он не идёт вовсе (STATE.md, «Открытые проблемы», задача #77) —
	-- полоска бы стояла, а волна не начиналась никогда. Heartbeat тикает штатные 60/сек.
	waveHoldConn = RunService.Heartbeat:Connect(function()
		if not holdingWave then
			return
		end
		local progress = math.clamp((os.clock() - waveHoldStart) / WAVE_HOLD_TIME, 0, 1)
		holdBar.Size = UDim2.new(progress, -12, 0, 6)
		if progress >= 1 then
			cancelWaveHold()
			startWaveButton.Visible = false -- чтобы второе удержание не ушло в следующую волну
			Remotes.RequestStartWave:FireServer()
		end
	end)
end

-- InputBegan самой кнопки, а не MouseButton1Click: клик приходит уже по отпусканию, то есть
-- ровно тем событием, от которого удержание и должно защищать. Touch здесь тоже нужен явно —
-- на телефоне мыши нет.
startWaveButton.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		startWaveHold()
	end
end)

-- Отпускание ловится и на кнопке, и глобально: палец может уйти с кнопки до отпускания,
-- и тогда её собственный InputEnded не придёт вовсе, а удержание осталось бы висеть.
startWaveButton.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		cancelWaveHold()
	end
end)

startWaveButton.MouseLeave:Connect(cancelWaveHold)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		cancelWaveHold()
	end
end)

Remotes.WaveReady.OnClientEvent:Connect(function(waveNumber, totalWaves)
	frame.Visible = true
	-- Готовность отмечена цветом числа, а не словом «готова»: под текст в панели есть
	-- 186 пикселей, а полная строка с подписью занимает 187 (замерено GetTextBoundsAsync).
	waveLabel.Text = ("%d/%d"):format(waveNumber, totalWaves)
	waveLabel.TextColor3 = Theme.color.action
	Theme.Blink(waveLabel)
	-- На узкой мобильной кнопке полная надпись не помещается и обрезалась бы посередине слова.
	startWaveButton.Text = MobileUI.isMobile and ("ВОЛНА %d ▶"):format(waveNumber)
		or ("НАЧАТЬ ВОЛНУ %d"):format(waveNumber)
	startWaveButton.Visible = true

	-- Готовность волны 1 приходит и после входа в уровень из лобби. Без сброса здесь баннер
	-- победы/поражения предыдущего забега висел бы поверх новой попытки до первого нажатия волны.
	resultFrame.Visible = false
end)

Remotes.WaveChanged.OnClientEvent:Connect(function(waveNumber, totalWaves)
	frame.Visible = true
	waveLabel.Text = ("%d/%d"):format(waveNumber, totalWaves)
	waveLabel.TextColor3 = Theme.color.accent
	Theme.Blink(waveLabel)

	-- Началась волна — значит забег идёт, и итоговый баннер убирается сам.
	-- Отдельное событие «забег начался» для этого заводить не нужно.
	resultFrame.Visible = false
	startWaveButton.Visible = false
	cancelWaveHold()
end)

Remotes.MatterChanged.OnClientEvent:Connect(function(amount)
	matterLabel.Text = tostring(amount)
	Theme.Blink(matterLabel)
end)

-- Стол активной локации; при смене локации подписка переезжает на новый стол.
local Arena = require(ReplicatedStorage:WaitForChild("Arena"))
local craftTable = Arena.Location():WaitForChild("CraftTable")
local tableConnections = {}

local function updateTableHp()
	local hp = craftTable:GetAttribute("HP") or 0
	local maxHp = craftTable:GetAttribute("MaxHP") or hp
	hpLabel.Text = tostring(math.floor(hp))
	hpLabel.TextColor3 = hpColor(hp, maxHp)
	Theme.Blink(hpLabel)
	renderHpBar(hp, maxHp)
end

local function watchTable()
	for _, connection in tableConnections do
		connection:Disconnect()
	end
	tableConnections = {
		craftTable:GetAttributeChangedSignal("HP"):Connect(updateTableHp),
		craftTable:GetAttributeChangedSignal("MaxHP"):Connect(updateTableHp),
	}
	updateTableHp()
end
watchTable()

Arena.OnChanged(function()
	craftTable = Arena.Location():WaitForChild("CraftTable")
	watchTable()
end)

Remotes.RunEnded.OnClientEvent:Connect(function(won)
	local tone = won and Theme.color.action or Theme.color.danger
	resultLabel.Text = won and "ПОБЕДА" or "ПОРАЖЕНИЕ"
	-- Корпус и начинка — теми же сборщиками, что и ячейки элементов.
	Theme.ElementFill(resultFrame, tone)
	Theme.Inner(resultLabel)
	resultLabel.TextColor3 = Theme.Legible(tone)
	if resultCaption then
		resultCaption.Text = won and "ЗАБЕГ ОКОНЧЕН  //  прочность стола сохранена"
			or "ЗАБЕГ ОКОНЧЕН  //  лаборатория прорвана"
	end
	resultFrame.Visible = true
	Theme.Open(resultFrame)
	Theme.Static()
	startWaveButton.Visible = false
	cancelWaveHold()
	-- Сервер тут же возвращает игрока в лобби (alchemy_td_lobby.md, шаг 3) — панель забега прячем,
	-- баннер остаётся висеть поверх лобби до следующего WaveReady/WaveChanged.
	frame.Visible = false
end)
