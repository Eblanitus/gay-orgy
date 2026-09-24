-- Показ розыгрыша на экране производителя: барабаны рулетки и круг со стрелкой апгрейдера,
-- показ джекпота рулетки и короткие отклики окна (толчок, нажатие, дрожь, вспышка, помеха,
-- «+1», бегущее число, въезд экрана). Автор просит, чтобы производитель двигался (2026-09-23).
-- Толчок — только у круга, числа и кнопок: на ячейке с узором элемента он смотрится плохо
-- (замечание автора), и сменившийся элемент апгрейдера вместо него проходит помехой.
-- Всё, кроме хода барабанов и стрелки, слушается настройки «Движение» (uiMotion):
-- выключена — показания меняются сразу, джекпот стоит неподвижной картинкой.
-- Звуки откликов (UISound) от «Движения» не зависят: их глушит громкость на вкладке
-- «Звук» в настройках.
--
-- Итог уже разыгран сервером: барабаны и стрелка только приходят к нему. Пока крутятся
-- барабаны, экран рулетки закрыт кнопкой-заглушкой: новый запуск всё равно не приняли бы
-- (замок на сервере). Круг апгрейдера стоит на экране и в покое, стрелка крутится прямо на нём.
-- Сколько идёт показ рулетки, решает сервер (RouletteConfig.ShowTime) и шлёт вместе с итогом.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local Theme = require(script.Parent:WaitForChild("UITheme"))
local Settings = require(script.Parent:WaitForChild("Settings"))
local UISound = require(script.Parent:WaitForChild("UISound"))
local Elements = require(ReplicatedStorage:WaitForChild("Elements"))

local Show = {}

-- Слой показа. Глубина в окне общая (ZIndexBehavior Global), а плитки режимов стоят на слое 1
-- и позже экрана в дереве — на том же слое показ ушёл бы под них.
local LAYER = 5
-- Барабаны и стрелка встают чуть раньше конца показа: итог надо успеть прочесть.
local SETTLE = 0.8
local REEL_ORDER = { "Fire", "Water", "Earth", "Air" }
local TICKS = 60
-- Сколько ячеек проезжает лента барабана за секунду хода: скорость у всех барабанов одна.
local CELLS_PER_SECOND = 6

local current

local function part(className, parent, z)
	local inst = Instance.new(className)
	inst.BorderSizePixel = 0
	inst.ZIndex = z or LAYER + 1
	inst.Parent = parent
	return inst
end

local function label(parent, text, size, z)
	local l = part("TextLabel", parent, z)
	l.BackgroundTransparency = 1
	l.FontFace = Theme.font.strong
	l.TextColor3 = Theme.color.ink
	l.TextScaled = false
	l.TextSize = size
	l.TextWrapped = true
	l.Text = text
	return l
end

local function elementColor(skin, key)
	return (skin.button and skin.button[key]) or Elements[key].color
end

local function percent(chance)
	local text = string.format("%.2f", chance * 100)
	text = text:gsub("0+$", ""):gsub("%.$", "")
	return text .. "%"
end

-- ============ Отклики окна ============
local function motion()
	return Settings.Get("uiMotion")
end

local function tween(inst, time, props, style)
	local t = TweenService:Create(
		inst,
		TweenInfo.new(time, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		props
	)
	t:Play()
	return t
end

-- Масштаб откликов — свой UIScale «Motion», а не Size: размеры пишет раскладка. Один на
-- предмет: второй UIScale на том же предмете Roblox не применяет.
local function scaler(inst)
	local s = inst:FindFirstChild("Motion")
	if not s then
		s = Instance.new("UIScale")
		s.Name = "Motion"
		s.Parent = inst
	end
	return s
end

-- Толчок: предмет на миг больше на amount и пружинит к своему размеру.
function Show.Pop(inst, amount, time)
	if not motion() then
		return
	end
	local s = scaler(inst)
	s.Scale = 1 + amount
	tween(s, time, { Scale = 1 }, Enum.EasingStyle.Back)
end

-- Нажатие: кнопка проседает, пока её держат, и пружинит обратно. Щелчок — на само нажатие.
function Show.Press(button)
	button.Activated:Connect(function()
		UISound.Play("Click")
	end)
	local held
	button.MouseButton1Down:Connect(function()
		if motion() then
			held = scaler(button)
			tween(held, 0.07, { Scale = 0.93 })
		end
	end)
	local function release()
		if held then
			tween(held, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
			held = nil
		end
	end
	button.MouseButton1Up:Connect(release)
	button.MouseLeave:Connect(release)
	button.Activated:Connect(release)
end

-- Дрожь: предмет трясёт по горизонтали на power пикселей, затухая, и ставит на место.
local shaking = {}
function Show.Shake(inst, power, time)
	if not motion() then
		return
	end
	local base = shaking[inst] or inst.Position
	shaking[inst] = base
	local v = Instance.new("NumberValue")
	v.Changed:Connect(function(x)
		inst.Position = base + UDim2.fromOffset(math.sin(x * math.pi * 10) * power * (1 - x), 0)
	end)
	tween(v, time, { Value = 1 }, Enum.EasingStyle.Linear).Completed:Connect(function()
		inst.Position = base
		shaking[inst] = nil
		v:Destroy()
	end)
end

-- Вспышка: поверх предмета ложится цвет и тает. radius — скругление в пикселях, если у предмета
-- оно не как у ячеек (круглые узлы карты рецептов).
function Show.Flash(inst, color, time, radius)
	if not motion() then
		return
	end
	local f = part("Frame", inst, inst.ZIndex + 6)
	f.Name = "Flash"
	f.Size = UDim2.fromScale(1, 1)
	f.BackgroundColor3 = color
	f.BackgroundTransparency = 0.3
	Theme.Corner(f, radius or Theme.radius.mark)
	tween(f, time, { BackgroundTransparency = 1 }).Completed:Connect(function()
		f:Destroy()
	end)
end

-- Помеха по ячейке: на долю секунды по ней бегут светлые точки, чёрточки развёртки и лёгкая
-- засветка — как помеха смены экрана (Theme.Static), но в пределах одной ячейки и заметнее.
-- Просьба автора: сменившийся элемент апгрейдера проходит помехой (2026-09-23).
-- Точки разбрасываются заново в каждом кадре: застывшая россыпь читается грязью, а не шумом.
-- Повторный вызов посреди помехи начинает её сначала, второй слой не заводит.
local NOISE = {
	time = 0.22, -- секунды
	speck = 0.75, -- сила самой яркой точки в начале (не прозрачность)
	veil = 0.16, -- сила засветки ячейки в начале
	area = 220, -- на сколько квадратных пикселей ячейки одна точка
}
local noisy = {}
-- Виден ли элемент: он сам и все его рамки видимы, и окно включено. Пару апгрейдера
-- пересчитывают и тогда, когда его экран спрятан (пришёл запас в покупке), —
-- помеха и её треск там ни к чему.
local function onScreen(inst)
	local node = inst
	while node do
		if node:IsA("LayerCollector") then
			return node.Enabled
		end
		if node:IsA("GuiObject") and not node.Visible then
			return false
		end
		node = node.Parent
	end
	return false
end
function Show.Noise(inst)
	if not onScreen(inst) then
		return
	end
	-- Треск длиннее помехи — обрывается вместе с ней.
	UISound.Play("Crackle", NOISE.time + 0.05)
	if not motion() then
		return
	end
	local n = noisy[inst]
	if n then
		n.stop = os.clock() + NOISE.time
		return
	end
	local box = part("Frame", inst, inst.ZIndex + 6)
	box.Name = "Noise"
	box.Size = UDim2.fromScale(1, 1)
	box.BackgroundColor3 = Theme.color.text
	box.BackgroundTransparency = 1
	box.ClipsDescendants = true
	Theme.Corner(box, Theme.radius.mark)
	local size = inst.AbsoluteSize
	local specks = {}
	for i = 1, math.clamp(math.floor(size.X * size.Y / NOISE.area), 24, 160) do
		local s = part("Frame", box, box.ZIndex)
		s.BackgroundColor3 = Theme.color.text
		s.BackgroundTransparency = 1
		specks[i] = s
	end
	n = { stop = os.clock() + NOISE.time }
	noisy[inst] = n
	n.conn = RunService.RenderStepped:Connect(function()
		local left = n.stop - os.clock()
		if left <= 0 or not box.Parent then
			n.conn:Disconnect()
			box:Destroy()
			noisy[inst] = nil
			return
		end
		local k = left / NOISE.time
		local w, h = box.AbsoluteSize.X, box.AbsoluteSize.Y
		box.BackgroundTransparency = 1 - NOISE.veil * k
		for _, s in specks do
			-- Каждая пятая — чёрточка строки развёртки, остальные — точки в пиксель-два.
			if math.random() < 0.2 then
				s.Size = UDim2.fromOffset(math.random(6, math.max(6, math.floor(w * 0.3))), 1)
			else
				s.Size = UDim2.fromOffset(math.random(1, 2), math.random(1, 2))
			end
			s.Position = UDim2.fromOffset(math.random() * w, math.random() * h)
			s.BackgroundTransparency = 1 - NOISE.speck * k * math.random()
		end
	end)
end

-- Всплывающая надпись: «+1» над серединой предмета поднимается и тает.
function Show.Float(inst, text, color, size)
	if not motion() then
		return
	end
	local l = label(inst, text, size, inst.ZIndex + 8)
	l.TextColor3 = color
	l.TextWrapped = false
	l.AnchorPoint = Vector2.new(0.5, 0.5)
	l.Position = UDim2.fromScale(0.5, 0.5)
	l.Size = UDim2.fromOffset(size * 4, size + 8)
	local outline = Instance.new("UIStroke")
	outline.Color = Theme.color.ink
	outline.Thickness = 2
	outline.Parent = l
	Show.Pop(l, 0.5, 0.3)
	tween(l, 0.9, { Position = UDim2.new(0.5, 0, 0.5, -size * 2), TextTransparency = 1 })
	tween(outline, 0.9, { Transparency = 1 }).Completed:Connect(function()
		l:Destroy()
	end)
end

-- Бегущее число: write(x, exact) пишет показание; на бегу x дробное, в конце exact = true
-- и x ровно to. Возвращает твин, чтобы новый счёт мог отменить недобежавший.
function Show.Count(from, to, time, write)
	if from == to or not motion() then
		write(to, true)
		return nil
	end
	local done = false
	local v = Instance.new("NumberValue")
	v.Value = from
	v.Changed:Connect(function(x)
		if not done then
			write(x, false)
		end
	end)
	local t = tween(v, time, { Value = to })
	t.Completed:Connect(function(state)
		done = true
		if state == Enum.PlaybackState.Completed then
			write(to, true)
		end
		v:Destroy()
	end)
	return t
end

-- Смена экрана: новый въезжает сбоку на 28 пикселей; dir — с какой стороны (1 — справа).
local sliding = {}
function Show.Slide(inst, dir)
	if not motion() then
		return
	end
	local base = sliding[inst] or inst.Position
	sliding[inst] = base
	inst.Position = base + UDim2.fromOffset(dir * 28, 0)
	tween(inst, 0.2, { Position = base }).Completed:Connect(function(state)
		if state == Enum.PlaybackState.Completed then
			sliding[inst] = nil
		end
	end)
end

-- Заглушка поверх экрана. Кнопка, а не рамка: иначе клики проходили бы к плиткам под ней.
-- Тёмная, как экран под ней.
local function cover(screen, skin, time)
	if current then
		current:Destroy()
	end
	local overlay = part("TextButton", screen, LAYER)
	overlay.Name = "Show"
	overlay.AutoButtonColor = false
	overlay.Text = ""
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.BackgroundColor3 = Theme.color.panelSoft
	Theme.Corner(overlay, Theme.radius.mark)
	current = overlay
	task.delay(time, function()
		if current == overlay then
			current = nil
		end
		overlay:Destroy()
	end)
	return overlay
end

-- Джекпот: все прокрутки выпали одним элементом, и сервер дал ещё в подарок
-- (RouletteConfig.Jackpot). После последнего барабана экран темнеет, барабаны по очереди
-- вспыхивают кантом, экран встряхивает; за крупным «ДЖЕКПОТ» с бликом
-- крутятся лучи цвета элемента, из центра дважды летят искры, под надписью выпадает
-- ячейка подарка. Без «Движения» — та же картинка, но неподвижная. span — сколько идёт показ.
local function jackpotShow(overlay, skin, jackpot, reels, span)
	local color = elementColor(skin, jackpot.key)
	local bright = color:Lerp(Color3.new(1, 1, 1), 0.35)
	local W, H = overlay.AbsoluteSize.X, overlay.AbsoluteSize.Y
	local move = motion()
	local z = LAYER + 8
	local cy = 0.36
	UISound.Play("Jackpot")

	for i, r in reels do
		local function light()
			r.edge.Color = bright
			r.edge.Thickness = 4
		end
		if move then
			task.delay((i - 1) * 0.08, light)
		else
			light()
		end
	end
	Show.Shake(overlay, 7, 0.45)

	-- Слой джекпота. Повёрнутое Roblox не обрезает (ClipsDescendants на него не действует,
	-- а CanvasGroup в Studio рисуется простой рамкой), поэтому лучи и искры сами не длиннее,
	-- чем от центра до ближнего края экрана рулетки.
	local layer = part("CanvasGroup", overlay, z)
	layer.Name = "Jackpot"
	layer.ClipsDescendants = true
	layer.Size = UDim2.fromScale(1, 1)
	layer.BackgroundColor3 = Theme.color.ink
	layer.BackgroundTransparency = 0.3
	Theme.Corner(layer, Theme.radius.mark)
	if move then
		layer.GroupTransparency = 1
		tween(layer, 0.15, { GroupTransparency = 0 })
	end

	-- Лучи: шесть полос через центр — двенадцать лучей, яркие у центра и тающие к краю.
	local burst = part("Frame", layer, z + 1)
	burst.BackgroundTransparency = 1
	burst.AnchorPoint = Vector2.new(0.5, 0.5)
	burst.Position = UDim2.fromScale(0.5, cy)
	local room = math.min(W / 2, H * cy, H * (1 - cy)) - 4
	local reach = room * 2
	burst.Size = UDim2.fromOffset(reach, reach)
	local rayW = math.max(math.floor(H * 0.08), 6)
	for n = 0, 5 do
		local ray = part("Frame", burst, z + 1)
		ray.BackgroundColor3 = color
		ray.AnchorPoint = Vector2.new(0.5, 0.5)
		ray.Position = UDim2.fromScale(0.5, 0.5)
		ray.Size = UDim2.new(1, 0, 0, rayW)
		ray.Rotation = n * 30
		local fade = Instance.new("UIGradient")
		fade.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0.4),
			NumberSequenceKeypoint.new(1, 1),
		})
		fade.Parent = ray
	end
	if move then
		local s = scaler(burst)
		s.Scale = 0
		tween(s, 0.45, { Scale = 1 }, Enum.EasingStyle.Back)
		tween(burst, span, { Rotation = 60 }, Enum.EasingStyle.Linear)
	end

	-- Искры: квадратики цвета элемента и белые разлетаются из центра, крутясь и тая.
	local function sparks(count, delay)
		task.delay(delay, function()
			if not layer.Parent then
				return
			end
			for s = 1, count do
				local spark = part("Frame", layer, z + 2)
				spark.BackgroundColor3 = s % 3 == 0 and Color3.new(1, 1, 1) or bright
				spark.AnchorPoint = Vector2.new(0.5, 0.5)
				spark.Position = UDim2.fromScale(0.5, cy)
				local side = math.random(5, 10)
				spark.Size = UDim2.fromOffset(side, side)
				spark.Rotation = math.random(0, 90)
				local a = math.random() * math.pi * 2
				local f = 0.4 + math.random() * 0.55
				local life = 0.6 + math.random() * 0.5
				tween(spark, life, {
					Position = UDim2.new(
						0.5,
						math.cos(a) * (W / 2 - 12) * f,
						cy,
						math.sin(a) * (math.min(H * cy, H * (1 - cy)) - 12) * f
					),
					Rotation = spark.Rotation + math.random(-270, 270),
					BackgroundTransparency = 1,
				}).Completed:Connect(function()
					spark:Destroy()
				end)
			end
		end)
	end
	if move then
		sparks(30, 0)
		sparks(22, 0.9)
	end

	local titleSize = math.clamp(math.floor(H * 0.24), 22, 72)
	local title = label(layer, "ДЖЕКПОТ", titleSize, z + 4)
	title.TextColor3 = Color3.new(1, 1, 1)
	title.TextWrapped = false
	title.AnchorPoint = Vector2.new(0.5, 0.5)
	title.Position = UDim2.fromScale(0.5, cy)
	title.Size = UDim2.fromOffset(W, math.floor(titleSize * 1.3))
	local outline = Instance.new("UIStroke")
	outline.Color = Theme.Shadowed(color, 0.55)
	outline.Thickness = math.max(2, math.floor(titleSize / 14))
	outline.Parent = title
	-- Блик: светлая полоса раз за разом проходит по буквам.
	local shine = Instance.new("UIGradient")
	shine.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, bright),
		ColorSequenceKeypoint.new(0.42, bright),
		ColorSequenceKeypoint.new(0.5, Color3.new(1, 1, 1)),
		ColorSequenceKeypoint.new(0.58, bright),
		ColorSequenceKeypoint.new(1, bright),
	})
	shine.Parent = title
	if move then
		local s = scaler(title)
		s.Scale = 0
		tween(s, 0.5, { Scale = 1 }, Enum.EasingStyle.Back)
		title.Rotation = -8
		tween(title, 0.5, { Rotation = 0 }, Enum.EasingStyle.Back)
		shine.Offset = Vector2.new(-1, 0)
		TweenService:Create(
			shine,
			TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, false, 0.25),
			{ Offset = Vector2.new(1, 0) }
		):Play()
	end

	-- Подарок: ячейка элемента с «+1» выпадает под надпись.
	local cellH = math.clamp(math.floor(H * 0.2), 28, 64)
	local cellW = math.clamp(math.floor(W * 0.3), 120, 280)
	local gift = part("Frame", layer, z + 3)
	gift.AnchorPoint = Vector2.new(0.5, 0.5)
	gift.Position = UDim2.fromScale(0.5, 0.68)
	gift.Size = UDim2.fromOffset(cellW, cellH)
	Theme.ElementFill(gift, color, { element = jackpot.key })
	local name = label(
		gift,
		("+%d %s"):format(jackpot.amount, Theme.Caps(Elements[jackpot.key].name)),
		math.clamp(math.floor(cellH * 0.45), 12, 26),
		z + 4
	)
	name.Size = UDim2.fromScale(1, 1)
	name.TextColor3 = Theme.color.text
	if move then
		local s = scaler(gift)
		s.Scale = 0
		gift.Rotation = -10
		task.delay(0.35, function()
			tween(s, 0.45, { Scale = 1 }, Enum.EasingStyle.Back)
			tween(gift, 0.45, { Rotation = 0 }, Enum.EasingStyle.Back)
		end)
	end

	-- Правило под подарком — только на экране, где ему есть место.
	if H >= 140 then
		local capSize = math.clamp(math.floor(H * 0.055), 11, 16)
		local caption = label(
			layer,
			("%d ОДИНАКОВЫХ — ЕЩЁ %d В ПОДАРОК"):format(jackpot.count, jackpot.amount),
			capSize,
			z + 4
		)
		caption.FontFace = Theme.font.body
		caption.TextColor3 = Theme.color.text
		caption.AnchorPoint = Vector2.new(0.5, 0)
		caption.Position = UDim2.new(0.5, 0, 0.68, math.floor(cellH / 2) + 8)
		caption.Size = UDim2.fromOffset(W - 16, capSize + 6)
		if move then
			caption.TextTransparency = 1
			task.delay(0.6, function()
				tween(caption, 0.3, { TextTransparency = 0 })
			end)
		end
	end
end

-- Рулетка: столько барабанов, сколько прокруток. Каждый — лента стихий в окне: выпавшее
-- встаёт посередине, соседние ячейки выглядывают сверху и снизу под тёмной пеленой.
-- Ход ленты: короткий замах назад, разгон, долгое торможение с проскоком чуть дальше
-- выпавшего и откат на него. Барабаны трогаются почти разом, а встают по очереди,
-- слева направо; вставший обводит окно цветом выпавшего.
-- jackpot — { key, amount, count, time }, если сервер дал подарок: его показ идёт после барабанов.
function Show.Roulette(screen, skin, results, time, jackpot)
	local overlay = cover(screen, skin, time + (jackpot and jackpot.time or 0))
	local reels = {}
	local size = screen.AbsoluteSize
	local pad, gap = 8, 8
	local count = #results
	local reelW = math.min(math.floor((size.X - pad * 2 - gap * (count - 1)) / count), 360)
	local reelH = math.max(size.Y - pad * 2, 20)
	local left = math.floor((size.X - reelW * count - gap * (count - 1)) / 2)
	-- Соседям место только в высоком окне; в низком барабан показывает одну ячейку.
	local peek = reelH >= 90 and math.floor(reelH * 0.18) or 0
	local cellH = reelH - peek * 2
	local textSize = (cellH >= 110 and reelW >= 100) and 30 or cellH >= 55 and 20 or 14

	for i, result in results do
		local reel = part("Frame", overlay)
		reel.Name = "Reel" .. i
		reel.ClipsDescendants = true
		reel.BackgroundColor3 = skin.dark
		reel.Position = UDim2.fromOffset(left + (i - 1) * (reelW + gap), pad)
		reel.Size = UDim2.fromOffset(reelW, reelH)
		Theme.Corner(reel, Theme.radius.mark)

		-- Трогается чуть позже соседа слева, встаёт к своей доле показа: последний — к SETTLE.
		local start = (i - 1) * 0.06
		local stop = time * SETTLE * (0.55 + 0.45 * i / count)
		-- Лента: сосед сверху, пробег, выпавшее и сосед снизу (он же запас на проскок).
		-- Пробег растёт со временем хода, поэтому скорость у всех барабанов одна.
		local target = 2 + math.max(6, math.floor((stop - start) * CELLS_PER_SECOND))
		local cells = target + 1
		local strip = part("Frame", reel, LAYER + 2)
		strip.BackgroundTransparency = 1
		strip.Size = UDim2.fromOffset(reelW, cellH * cells)
		local prev
		for c = 1, cells do
			local key = result
			if c ~= target then
				-- Соседние ячейки не повторяются: иначе на ходу лента кажется стоящей.
				repeat
					key = REEL_ORDER[math.random(#REEL_ORDER)]
				until key ~= prev and not (c == target - 1 and key == result)
			end
			prev = key
			-- Ячейка — как плитки под барабанами и все ячейки элементов в игре: тёмный корпус
			-- его цвета с узором (Theme.ElementFill). Подпись создана после слоёв и лежит поверх.
			local cell = part("Frame", strip, LAYER + 3)
			cell.Position = UDim2.fromOffset(3, (c - 1) * cellH + 3)
			cell.Size = UDim2.fromOffset(reelW - 6, cellH - 6)
			Theme.ElementFill(cell, elementColor(skin, key), { element = key })
			local name = label(cell, Theme.Caps(Elements[key].name), textSize, LAYER + 4)
			name.Size = UDim2.fromScale(1, 1)
			name.TextColor3 = Theme.color.text
		end

		-- Окно выпавшего посередине. Соседей сверху и снизу глушит пелена цвета барабана.
		if peek > 0 then
			for _, y in { 0, peek + cellH } do
				local shade = part("Frame", reel, LAYER + 7)
				shade.BackgroundColor3 = skin.dark
				shade.BackgroundTransparency = 0.35
				shade.Position = UDim2.fromOffset(0, y)
				shade.Size = UDim2.fromOffset(reelW, peek)
			end
		end
		local window = part("Frame", reel, LAYER + 7)
		window.BackgroundTransparency = 1
		window.Position = UDim2.fromOffset(2, peek + 2)
		window.Size = UDim2.fromOffset(reelW - 4, cellH - 4)
		Theme.Corner(window, Theme.radius.mark)
		local edge = Theme.Stroke(window, Theme.color.frame, 1, 0)
		reels[i] = { reel = reel, edge = edge }

		-- Ход: замах вниз на четверть ячейки, разгон вверх с торможением до проскока на
		-- пятую часть ячейки за выпавшее, откат на него. Встал — кант окна в цвет выпавшего.
		local function at(c)
			return peek - (c - 1) * cellH
		end
		local wind = math.min(0.2, stop * 0.1)
		local back = math.min(0.3, stop * 0.15)
		local steps = {
			{ wind, Enum.EasingStyle.Sine, at(2) + cellH * 0.25 },
			{ stop - start - wind - back, Enum.EasingStyle.Cubic, at(target) - cellH * 0.2 },
			{ back, Enum.EasingStyle.Quad, at(target) },
		}
		strip.Position = UDim2.fromOffset(0, at(2))
		-- Щелчок на каждую ячейку, прошедшую через окно; стук — когда барабан встал.
		local shown = 2
		strip:GetPropertyChangedSignal("Position"):Connect(function()
			local c = math.floor((peek - strip.Position.Y.Offset) / cellH + 0.5) + 1
			if c ~= shown then
				shown = c
				UISound.Play("Tick")
			end
		end)
		local function play(n)
			local step = steps[n]
			if not step then
				edge.Color = elementColor(skin, result)
				edge.Thickness = 2
				UISound.Play("Stop")
				return
			end
			local tween = TweenService:Create(
				strip,
				TweenInfo.new(step[1], step[2], Enum.EasingDirection.Out),
				{ Position = UDim2.fromOffset(0, step[3]) }
			)
			tween.Completed:Connect(function(state)
				if state == Enum.PlaybackState.Completed then
					play(n + 1)
				end
			end)
			tween:Play()
		end
		task.delay(start, play, 1)
	end

	-- Джекпот — после последнего вставшего барабана и до конца показа.
	if jackpot then
		task.delay(time * SETTLE + 0.05, function()
			if current == overlay then
				jackpotShow(overlay, skin, jackpot, reels, time * (1 - SETTLE) + jackpot.time)
			end
		end)
	end
end

-- Круги на экране: по рамке круга — его сегменты, число и стрелка. Ключи сильные:
-- слабый ключ-Instance сборщик мусора снимает, пока круг ещё на экране. Снесённый круг
-- убирает свою запись сам (Destroying).
local dials = {}
-- За сколько секунд число в ступице добегает до нового шанса.
local COUNT_TIME = 0.35

local function greenOf(chance)
	return math.max(1, math.floor(chance * TICKS + 0.5))
end

-- Круг показывает шанс x: число в ступице (на бегу — целыми процентами, в конце — точно)
-- и дуга; перекрашиваются только сегменты между прежней и новой границей.
local function paint(d, x, exact)
	d.shown = x
	d.value.Text = exact and percent(x) or (math.floor(x * 100 + 0.5) .. "%")
	local g = greenOf(x)
	for t = math.min(g, d.green) + 1, math.max(g, d.green) do
		d.shades[t].Color = t <= g and d.on or d.off
	end
	d.green = g
end

-- Тот же круг, другой шанс: число бежит к новому, дуга растёт или тает вместе с ним,
-- стрелка возвращается наверх.
local function retune(d, chance)
	if d.count then
		d.count:Cancel()
	end
	if d.shown ~= chance then
		Show.Pop(d.value, 0.15, 0.3)
	end
	d.count = Show.Count(d.shown, chance, COUNT_TIME, function(x, exact)
		paint(d, x, exact)
	end)
	local rot = d.arrow.Rotation % 360
	d.arrow.Rotation = rot
	if rot ~= 0 then
		if motion() then
			tween(d.arrow, COUNT_TIME, { Rotation = rot > 180 and 360 or 0 })
		else
			d.arrow.Rotation = 0
		end
	end
	return d.arrow, greenOf(chance)
end

-- Круг апгрейдера — шкала прибора. Дуга из толстых сегментов по кругу от верха по часовой:
-- зелёных столько же, сколько шанс от целого круга, но хотя бы один — 6,25% тоже должны
-- быть видны. Остальные тёмно-красные: при неудаче элемент сгорает. Дуга лежит между двумя
-- тонкими кольцами, в середине — ступица с шансом. Стрелка стоит вверху: стержень от
-- ступицы с наконечником и метка поперёк дуги — видно, на каком сегменте встала. Круг
-- рисуется и в покое (шанс выбранной пары), и в показе. Возвращает стрелку и число зелёных.
function Show.Dial(holder, chance, dial, z)
	dial = math.max(dial, 30)
	local old = holder:FindFirstChild("Ring")
	local known = old and dials[old]
	if known and known.dial == dial then
		return retune(known, chance)
	end
	if old then
		old:Destroy()
	end
	local ring = part("Frame", holder, z)
	ring.Name = "Ring"
	ring.BackgroundTransparency = 1
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromScale(0.5, 0.5)
	ring.Size = UDim2.fromOffset(dial, dial)

	local radius = dial / 2
	local band = math.max(math.floor(dial * 0.085), 5)
	local outer = radius - 5
	local inner = outer - band
	local mid = (outer + inner) / 2
	local hub = math.floor(radius * 0.46)

	local function round(inst, corner)
		local c = Instance.new("UICorner")
		c.CornerRadius = corner
		c.Parent = inst
	end
	-- Кольцо с кантом по центру круга; с заливкой — ступица.
	local function circle(r, fill)
		local c = part("Frame", ring, z)
		c.AnchorPoint = Vector2.new(0.5, 0.5)
		c.Position = UDim2.fromScale(0.5, 0.5)
		c.Size = UDim2.fromOffset(r * 2, r * 2)
		c.BackgroundColor3 = fill or Theme.color.panel
		c.BackgroundTransparency = fill and 0 or 1
		round(c, UDim.new(0.5, 0))
		Theme.Stroke(c, Theme.color.hairline, 1, 0)
	end
	circle(radius - 1)
	circle(math.max(inner - 4, 1))
	circle(hub, Theme.color.panelSoft)

	-- Сегменты: светлее к внешнему краю, чтобы дуга читалась лентой, а не плоскими палками.
	local green = greenOf(chance)
	local width = math.max(math.floor(2 * math.pi * mid / TICKS * 0.7), 2)
	local burn = Theme.Shadowed(Theme.color.danger, 0.6)
	local on = ColorSequence.new(Theme.color.action, Theme.Shadowed(Theme.color.action, 0.35))
	local off = ColorSequence.new(burn, Theme.Shadowed(burn, 0.35))
	local shades = {}
	for t = 0, TICKS - 1 do
		local angle = (t + 0.5) / TICKS * 360
		local rad = math.rad(angle)
		local seg = part("Frame", ring, z)
		seg.BackgroundColor3 = Color3.new(1, 1, 1)
		seg.AnchorPoint = Vector2.new(0.5, 0.5)
		seg.Position = UDim2.new(0.5, math.sin(rad) * mid, 0.5, -math.cos(rad) * mid)
		seg.Size = UDim2.fromOffset(width, band)
		seg.Rotation = angle
		round(seg, UDim.new(0, 2))
		local shade = Instance.new("UIGradient")
		shade.Rotation = 90
		shade.Color = t < green and on or off
		shade.Parent = seg
		shades[t + 1] = shade
	end

	local size = dial >= 300 and 44 or dial >= 200 and 30 or dial >= 80 and 16 or 11
	local value = label(ring, percent(chance), size, z + 2)
	value.TextColor3 = Theme.color.action
	value.AnchorPoint = Vector2.new(0.5, 0.5)
	value.Position = UDim2.fromScale(0.5, 0.5)
	value.Size = UDim2.fromOffset(hub * 1.8, size * 1.4)
	-- На большом круге над числом подпись: что это за число.
	if dial >= 200 then
		local cap = label(ring, "ШАНС", dial >= 300 and 13 or 11, z + 2)
		cap.FontFace = Theme.font.body
		cap.TextColor3 = Theme.color.textDim
		cap.AnchorPoint = Vector2.new(0.5, 1)
		cap.Position = UDim2.new(0.5, 0, 0.5, -math.floor(size * 0.6))
		cap.Size = UDim2.fromOffset(hub * 1.4, 16)
	end

	-- Стрелка — прозрачная рамка во весь круг: рамка крутится вокруг своего центра, и всё
	-- на ней ходит по кругу, как по циферблату. Стержень начинается за ступицей, чтобы не
	-- закрывать шанс; метка поперёк дуги обведена тёмным, чтобы читаться и на зелёном.
	local arrow = part("Frame", ring, z + 1)
	arrow.BackgroundTransparency = 1
	arrow.Size = UDim2.fromScale(1, 1)
	local shaft = math.max(inner - 8 - hub, 4)
	local hand = part("Frame", arrow, z + 3)
	hand.BackgroundColor3 = Theme.color.text
	hand.AnchorPoint = Vector2.new(0.5, 1)
	hand.Position = UDim2.new(0.5, 0, 0.5, -(hub + 4))
	hand.Size = UDim2.fromOffset(3, shaft)
	local tip = part("Frame", arrow, z + 3)
	tip.BackgroundColor3 = Theme.color.text
	tip.AnchorPoint = Vector2.new(0.5, 0.5)
	tip.Position = UDim2.new(0.5, 0, 0.5, -(hub + 4 + shaft))
	local tipSize = math.max(math.floor(dial * 0.022), 5)
	tip.Size = UDim2.fromOffset(tipSize, tipSize)
	tip.Rotation = 45
	local mark = part("Frame", arrow, z + 3)
	mark.BackgroundColor3 = Theme.color.text
	mark.AnchorPoint = Vector2.new(0.5, 0.5)
	mark.Position = UDim2.new(0.5, 0, 0.5, -mid)
	mark.Size = UDim2.fromOffset(4, band + 8)
	Theme.Stroke(mark, Theme.color.ink, 1, 0)
	ring.Destroying:Connect(function()
		dials[ring] = nil
	end)
	dials[ring] = {
		dial = dial,
		shades = shades,
		on = on,
		off = off,
		value = value,
		arrow = arrow,
		green = green,
		shown = chance,
	}
	return arrow, green
end

-- Где встать: внутри зелёной дуги или вне её, с запасом от границы, чтобы
-- стрелка не стояла на стыке и итог читался сразу.
local function spin(arrow, green, won, time, onLand)
	local edge = green / TICKS * 360
	local margin = math.min(4, edge / 4)
	local final
	if won then
		final = margin + math.random() * (edge - margin * 2)
	else
		final = edge + 4 + math.random() * (360 - edge - 8)
	end
	-- Стрелка трогается оттуда, где стоит (круг теперь не пересобирается), и делает
	-- четыре с лишним оборота.
	arrow.Rotation = arrow.Rotation % 360
	local turn = TweenService:Create(
		arrow,
		TweenInfo.new(time * SETTLE, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
		{ Rotation = 360 * 4 + final }
	)
	-- Щелчок на каждые 30° хода стрелки: частый на разгоне, редкий под конец.
	local notch = math.floor(arrow.Rotation / 30)
	local ticking = arrow:GetPropertyChangedSignal("Rotation"):Connect(function()
		local n = math.floor(arrow.Rotation / 30)
		if n ~= notch then
			notch = n
			UISound.Play("Tick")
		end
	end)
	-- Встала: удача — круг вздрагивает, неудача — круг трясёт.
	turn.Completed:Connect(function(state)
		ticking:Disconnect()
		if state ~= Enum.PlaybackState.Completed then
			return
		end
		if won then
			Show.Pop(arrow.Parent, 0.06, 0.4)
		else
			Show.Shake(arrow.Parent, 8, 0.45)
		end
		if onLand then
			onLand(won)
		end
	end)
	turn:Play()
end

-- Попытка апгрейда прямо на круге: круг перерисован под разыгранную пару, стрелка
-- делает несколько оборотов и встаёт в зелёном при удаче и в тёмном при неудаче.
-- onLand(won) — когда стрелка встала: окну пора ответить на итог.
function Show.SpinDial(holder, result, time, dial, z, onLand)
	local arrow, green = Show.Dial(holder, result.chance or 0, dial, z)
	spin(arrow, green, result.won, time, onLand)
end

-- Прежний показ апгрейда поверх экрана: слева вложенное, справа цель, между ними круг.
function Show.Upgrade(screen, skin, result, time)
	local overlay = cover(screen, skin, time)
	local size = screen.AbsoluteSize
	local pad = 8
	local dial = math.max(math.min(size.Y - pad * 2, math.floor(size.X * 0.4)), 30)
	local sideW = math.min(math.floor((size.X - dial - pad * 4) / 2), 360)
	local textSize = sideW >= 200 and 26 or sideW >= 110 and 18 or 13

	for side, key in { result.from, result.to } do
		local box = part("Frame", overlay)
		box.BackgroundColor3 = elementColor(skin, key)
		-- Плашки прижаты к кругу, а не к краям: на широком экране тройка читается одной строкой.
		local shift = dial / 2 + pad
		box.AnchorPoint = Vector2.new(side == 1 and 1 or 0, 0.5)
		box.Position = UDim2.new(0.5, side == 1 and -shift or shift, 0.5, 0)
		box.Size = UDim2.fromOffset(sideW, math.min(dial, 120))
		Theme.Corner(box, Theme.radius.mark)
		local name = label(box, Theme.Caps(Elements[key].name), textSize, LAYER + 2)
		name.Size = UDim2.fromScale(1, 1)
	end

	local holder = part("Frame", overlay)
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromScale(1, 1)
	Show.SpinDial(holder, result, time, dial, LAYER + 1)
end

return Show
