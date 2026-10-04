-- Мгновенные эффекты боя: луч выстрела, всплывающая цифра урона, гасимая смерть и отдельно —
-- настоящий пиротехнический взрыв (Порох/Взрыв, см. onExplosion). Сервер только сообщает
-- позиции/числа, вся отрисовка здесь.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
-- Турель на риге узнаётся по таблице (Towers[тип].rig), а не по имени деталей:
-- см. rigDirection ниже.
local Towers = require(ReplicatedStorage:WaitForChild("Towers"))
-- Только ради шрифта цифры урона: она висит над ареной рядом с показаниями HUD,
-- и чужой шрифт там виден сразу.
local Theme = require(script.Parent:WaitForChild("UITheme"))
-- Настройка «Цифры урона» из главного меню — см. onDamageDealt.
local Settings = require(script.Parent:WaitForChild("Settings"))
-- Камни удара в землю — настоящая физика, с общим учётом и растворением.
local Loose = require(ReplicatedStorage:WaitForChild("Loose"))

local function makeAnchor(position)
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.Position = position
	anchor.Parent = Workspace
	return anchor
end

-- Выстрел: короткая вспышка у дула, цветом залитого элемента.
--
-- Сам полёт здесь не рисуется: снаряд теперь настоящий — серверная деталь в Workspace.Projectiles,
-- которая и летит, и считает попадание (см. ServerScriptService.Projectile). Прежний луч от башни
-- до цели врал бы теперь вдвойне: попадание не мгновенное и вообще не гарантировано.
--
-- Эта версия осталась для турелей, у которых нет меша со стволом (Инжектор, Мортира):
-- там единственное, что известно о выстреле, — точка, посчитанная сервером по числам из BARRELS.
local function simpleShot(fromPos, color)
	local flash = Instance.new("Part")
	flash.Shape = Enum.PartType.Ball
	flash.Size = Vector3.new(1.3, 1.3, 1.3)
	flash.Anchored = true
	flash.CanCollide = false
	flash.CanQuery = false
	flash.Material = Enum.Material.Neon
	flash.Color = color
	flash.Position = fromPos
	flash.Parent = Workspace

	TweenService:Create(flash, TweenInfo.new(0.12), {
		Size = Vector3.new(0.2, 0.2, 0.2),
		Transparency = 1,
	}):Play()

	Debris:AddItem(flash, 0.15)
end

-- Выстрел Колбы (задача #69): разряд катушечной пушки — вспышка в самом срезе, кольцо
-- ударной волны поперёк ствола и искры вперёд по его оси. Всё три живут около четверти
-- секунды: темп Колбы — выстрел в секунду, и вспышки не должны накладываться друг на друга
-- даже на разгоне Воздуха.
local function coilgunShot(muzzle, direction, color)
	local anchor = makeAnchor(muzzle)
	-- Верх якоря смотрит вдоль ствола: по нему бьёт EmissionDirection искр.
	anchor.CFrame = CFrame.lookAt(muzzle, muzzle + direction) * CFrame.Angles(-math.pi / 2, 0, 0)

	-- Вспышка: раздувается из среза и гаснет, заливая ствол светом цвета выстрела.
	local flash = Instance.new("Part")
	flash.Shape = Enum.PartType.Ball
	flash.Size = Vector3.new(0.6, 0.6, 0.6)
	flash.Anchored = true
	flash.CanCollide = false
	flash.CanQuery = false
	flash.Material = Enum.Material.Neon
	flash.Color = color
	flash.Position = muzzle
	flash.Parent = anchor

	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 18
	light.Brightness = 6
	light.Shadows = false
	light.Parent = flash

	TweenService:Create(flash, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(2.6, 2.6, 2.6),
		Transparency = 1,
	}):Play()
	TweenService:Create(light, TweenInfo.new(0.2), { Brightness = 0, Range = 6 }):Play()

	-- Кольцо: тонкий диск поперёк ствола, разбегается в стороны. Ось цилиндра-примитива —
	-- всегда локальный X, отсюда +90° по Y к lookAt (см. «Грабли Roblox» в STATE.md).
	local ring = Instance.new("Part")
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.15, 0.8, 0.8)
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.Material = Enum.Material.Neon
	ring.Color = color
	ring.Transparency = 0.25
	ring.CFrame = CFrame.lookAt(muzzle, muzzle + direction) * CFrame.Angles(0, math.rad(90), 0)
	ring.Parent = anchor

	TweenService:Create(ring, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.15, 5, 5),
		Transparency = 1,
	}):Play()

	-- Искры: узкий конус вперёд, чтобы было видно, куда смотрит ствол. Голова искры белая,
	-- хвост — в цвет выстрела: так же, как у самого снаряда (Projectile.dressShot).
	local sparks = Instance.new("ParticleEmitter")
	sparks.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
		ColorSequenceKeypoint.new(0.4, color),
		ColorSequenceKeypoint.new(1, color),
	})
	sparks.LightEmission = 1
	sparks.LightInfluence = 0
	sparks.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.55),
		NumberSequenceKeypoint.new(1, 0),
	})
	sparks.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	sparks.Lifetime = NumberRange.new(0.1, 0.22)
	sparks.Speed = NumberRange.new(22, 45)
	sparks.SpreadAngle = Vector2.new(14, 14)
	sparks.EmissionDirection = Enum.NormalId.Top
	sparks.Drag = 6
	sparks.Rotation = NumberRange.new(0, 360)
	sparks.Rate = 0
	sparks.Parent = anchor
	sparks:Emit(14)

	Debris:AddItem(anchor, 0.6)
end

-- Настоящий дульный срез меша Колбы и направление ствола, или nil, если у турели его нет.
--
-- Серверная точка выстрела считается по BARRELS от ОСИ турели, а ствол у этого меша сдвинут
-- от оси в сторону (колба слева, пушка справа) — вспышка по серверной точке висела бы рядом
-- со стволом, а не в нём. Поэтому спрашиваем модель: MiniBarrelC — центральный министвол,
-- BreechNew — казённик; вектор между ними и есть ось ствола, уже с учётом клиентского
-- наведения и отдачи (BuildingVisuals переставляет обе детали каждый кадр). Одного среза бы
-- не хватило: собственный поворот импортированного меша произволен и верить его LookVector нельзя.
local MUZZLE_LEAD = 1.2 -- studs от центра министвола до его среза

local function muzzleOf(tower)
	if not tower then
		return nil
	end

	local nose = tower:FindFirstChild("MiniBarrelC", true)
	local breech = tower:FindFirstChild("BreechNew", true)
	if not (nose and breech and nose:IsA("BasePart") and breech:IsA("BasePart")) then
		return nil
	end

	local axis = nose.Position - breech.Position
	if axis.Magnitude < 1e-3 then
		return nil
	end

	local direction = axis.Unit
	return nose.Position + direction * MUZZLE_LEAD, direction
end

-- Направление ствола у турели на риге (Инжектор). Двух деталей-маяков, как у Колбы,
-- у неё нет, зато есть опубликованные сервером углы наведения — те самые, по которым
-- BuildingVisuals ставит пушку, а сервер считает точку пуска. Оттого вспышка и снаряд
-- не могут разойтись: угол один на всех троих.
--
-- Ноль угла — -Z модели (Aiming.AngleTo), отсюда минусы у X и Z.
local function rigDirection(tower)
	if not tower then
		return nil
	end

	local towerData = Towers[tower:GetAttribute("Type") or ""]
	if not (towerData and towerData.rig) then
		return nil
	end

	local yaw = tower:GetAttribute("AimAngle")
	if not yaw then
		return nil -- турель ещё ни разу не целилась: пускай будет простая вспышка
	end

	local pitch = tower:GetAttribute("AimPitch") or 0
	local flat = math.cos(pitch)
	return Vector3.new(-math.sin(yaw) * flat, math.sin(pitch), -math.cos(yaw) * flat)
end

local function onShotFired(fromPos, color, tower)
	color = color or Color3.fromRGB(255, 255, 255)

	local muzzle, direction = muzzleOf(tower)
	if not muzzle then
		-- У турели на риге точка среза с сервера и так настоящая (он считает её
		-- по геометрии меша, TowerBuilder.aimRig) — не хватало только направления,
		-- чтобы выстрел был не голым шариком, а дульным выхлопом вдоль ствола.
		direction = rigDirection(tower)
		muzzle = direction and fromPos or nil
	end

	if muzzle then
		coilgunShot(muzzle, direction, color)
	else
		simpleShot(fromPos, color)
	end
end

-- Урон: всплывающая цифра, белая для базового урона башни, оранжевая для тика эффекта.
-- Отрицательная — лечение постройки (хилер с Жизнью): зелёный плюс.
--
-- Выключается в настройках («Цифры урона»): на куче жуков под огнём нескольких турелей
-- числа идут десятками в секунду и закрывают саму кучу. Отказ стоит в самом начале,
-- до создания якоря: при выключенной настройке не должно рождаться ни одного кадра.
local function onDamageDealt(position, amount, isBase)
	if not Settings.Get("damageNumbers") then
		return
	end

	local jitter = Vector3.new((math.random() - 0.5) * 1.5, 2, (math.random() - 0.5) * 1.5)
	local anchor = makeAnchor(position + jitter)

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.new(3, 0, 1.5, 0)
	gui.AlwaysOnTop = true
	gui.Parent = anchor

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.FontFace = Theme.font.strong
	label.TextScaled = true
	if amount < 0 then
		label.Text = "+" .. tostring(-amount)
		label.TextColor3 = Color3.fromRGB(90, 255, 140)
	else
		label.Text = "-" .. tostring(amount)
		label.TextColor3 = isBase and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(255, 140, 40)
	end
	label.TextStrokeTransparency = 0.2
	label.Parent = gui

	TweenService:Create(gui, TweenInfo.new(0.7, Enum.EasingStyle.Quad), { StudsOffset = Vector3.new(0, 3, 0) }):Play()
	TweenService:Create(label, TweenInfo.new(0.7), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()

	Debris:AddItem(anchor, 0.8)
end

-- Обычная смерть: жук просто гаснет — короткий бесцветный шар без огня, света и ударной
-- волны. Настоящий пиротехнический взрыв (onExplosion ниже) — это не про смерть, а про
-- конкретный источник урона, и на лёд или воду взрываться огнём нечему.
local function onEnemyDied(position)
	local anchor = makeAnchor(position)

	local puff = Instance.new("Part")
	puff.Shape = Enum.PartType.Ball
	puff.Size = Vector3.new(0.6, 0.6, 0.6)
	puff.Anchored = true
	puff.CanCollide = false
	puff.CanQuery = false
	puff.Material = Enum.Material.Neon
	puff.Color = Color3.fromRGB(235, 235, 235)
	puff.Transparency = 0.2
	puff.Position = position
	puff.Parent = anchor

	TweenService:Create(puff, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(2.2, 2.2, 2.2),
		Transparency = 1,
	}):Play()

	Debris:AddItem(anchor, 0.4)
end

-- Радиус, для которого подобраны цифры взрыва ниже — это radius элемента Взрыв
-- (ReplicatedStorage.Elements.Explosion.explosion.radius). Метка Пороха детонирует шире
-- (radius = 10) или уже (explosionScale делает Взрыв до 12.8), и картинка растёт вместе с ней.
local BASE_EXPLOSION_RADIUS = 8

-- Настоящий взрыв: вспышка со светом, ударная волна кольцом и разлёт огня с дымным шлейфом
-- (тоже на встроенных ParticleEmitter, без своих текстур). Срабатывает не на каждую смерть,
-- а только на Remotes.Explosion — детонацию метки Пороха огненным попаданием или прямое
-- попадание турелью с элементом Взрыв (см. ReplicatedStorage.Effects: detonate, applyExplosion).
-- Подрыв дрона — НЕ тот же взрыв, что у Пороха и Взрыва. У дрона микрозаряд, а не фугас:
-- ни огня, ни дыма, ни оранжевого — всё в цвет залитого элемента, резче и короче.
-- Отличать их важно: горящая воронка там, где просто подорвался дрон с Льдом или Водой,
-- врала бы про то, чем его ударило — тот же довод, по которому обычная смерть гаснет бесцветно.
--
-- Оболочка раздувается ровно до радиуса поражения, а не «на глаз»: по ней видно, кого
-- накрыло, и картинка не может разойтись с уроном (splash.radius Станции — 5 studs).
local function droneBlast(position, radius, color)
	radius = radius or 5
	local anchor = makeAnchor(position)

	-- Ядро: белая горячая точка. Белая, а не цветная, — чтобы цветная оболочка
	-- читалась как свечение вокруг вспышки, а не как второй шар.
	local core = Instance.new("Part")
	core.Shape = Enum.PartType.Ball
	core.Size = Vector3.new(0.8, 0.8, 0.8)
	core.Anchored = true
	core.CanCollide = false
	core.CanQuery = false
	core.Material = Enum.Material.Neon
	core.Color = Color3.new(1, 1, 1)
	core.Position = position
	core.Parent = anchor

	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 3 * radius
	light.Brightness = 7
	light.Shadows = false
	light.Parent = core

	TweenService:Create(core, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(1, 1, 1) * radius * 0.7,
		Transparency = 1,
	}):Play()
	TweenService:Create(light, TweenInfo.new(0.22), { Brightness = 0, Range = radius }):Play()

	-- Оболочка: сфера в цвет элемента ровно по радиусу поражения.
	local shell = Instance.new("Part")
	shell.Shape = Enum.PartType.Ball
	shell.Size = Vector3.new(1, 1, 1)
	shell.Anchored = true
	shell.CanCollide = false
	shell.CanQuery = false
	shell.Material = Enum.Material.Neon
	shell.Color = color
	shell.Transparency = 0.55
	shell.Position = position
	shell.Parent = anchor

	TweenService:Create(shell, TweenInfo.new(0.26, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
		Size = Vector3.new(1, 1, 1) * radius * 2,
		Transparency = 1,
	}):Play()

	-- Волна по земле: тонкое кольцо. Ось цилиндра-примитива — всегда локальный X,
	-- отсюда поворот на 90° по Z (см. «Грабли Roblox» в STATE.md).
	local ring = Instance.new("Part")
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.12, 1, 1)
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.Material = Enum.Material.Neon
	ring.Color = color
	ring.Transparency = 0.2
	ring.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = anchor

	TweenService:Create(ring, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.12, radius * 2.4, radius * 2.4),
		Transparency = 1,
	}):Play()

	-- Осколки: быстрый веер, гаснут на месте (Drag), без дымного шлейфа вовсе —
	-- разлет корпуса, а не горение.
	local shards = Instance.new("ParticleEmitter")
	shards.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
		ColorSequenceKeypoint.new(0.3, color),
		ColorSequenceKeypoint.new(1, color),
	})
	shards.LightEmission = 1
	shards.LightInfluence = 0
	shards.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	shards.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.7),
		NumberSequenceKeypoint.new(1, 0),
	})
	shards.Lifetime = NumberRange.new(0.18, 0.34)
	shards.Speed = NumberRange.new(26, 46)
	shards.Drag = 7
	shards.Rotation = NumberRange.new(0, 360)
	shards.RotSpeed = NumberRange.new(-220, 220)
	shards.SpreadAngle = Vector2.new(180, 180)
	shards.Rate = 0
	shards.Parent = anchor
	shards:Emit(math.floor(radius * 6 + 0.5))

	Debris:AddItem(anchor, 0.9)
end

local function onPyroExplosion(position, radius)
	local scale = math.clamp((radius or BASE_EXPLOSION_RADIUS) / BASE_EXPLOSION_RADIUS, 0.6, 2.5)
	local anchor = makeAnchor(position)

	-- Вспышка: яркий шар, за долю секунды раздувается и гаснет, заливая всё вокруг светом.
	local flash = Instance.new("Part")
	flash.Shape = Enum.PartType.Ball
	flash.Size = Vector3.new(1, 1, 1)
	flash.Anchored = true
	flash.CanCollide = false
	flash.CanQuery = false
	flash.Material = Enum.Material.Neon
	flash.Color = Color3.fromRGB(255, 230, 150)
	flash.Position = position
	flash.Parent = anchor

	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 170, 80)
	light.Range = 16 * scale
	light.Brightness = 6
	light.Parent = flash

	TweenService:Create(flash, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(4.5, 4.5, 4.5) * scale,
		Transparency = 1,
	}):Play()
	TweenService:Create(light, TweenInfo.new(0.25), { Brightness = 0, Range = 4 * scale }):Play()

	-- Ударная волна: плоское кольцо разбегается в стороны и растворяется.
	local ring = Instance.new("Part")
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.2, 1, 1)
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.Material = Enum.Material.Neon
	ring.Color = Color3.fromRGB(255, 140, 60)
	ring.Transparency = 0.3
	ring.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = anchor

	TweenService:Create(ring, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.2, 9, 9) * scale,
		Transparency = 1,
	}):Play()

	-- Огонь: быстрые яркие частицы во все стороны, от жёлтого к тёмно-красному.
	local fire = Instance.new("ParticleEmitter")
	fire.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 240, 180)),
		ColorSequenceKeypoint.new(0.4, Color3.fromRGB(255, 120, 40)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(120, 30, 20)),
	})
	fire.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	fire.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.1),
		NumberSequenceKeypoint.new(1, 0.2),
	})
	fire.Lifetime = NumberRange.new(0.35, 0.6)
	fire.Speed = NumberRange.new(14, 26)
	fire.Rotation = NumberRange.new(0, 360)
	fire.RotSpeed = NumberRange.new(-180, 180)
	fire.SpreadAngle = Vector2.new(180, 180)
	fire.Rate = 0
	fire.Parent = anchor
	fire:Emit(math.floor(40 * scale + 0.5))

	-- Дым: медленный, тёмный, растёт и висит дольше огня — тянет взрыв во времени.
	local smoke = Instance.new("ParticleEmitter")
	smoke.Color = ColorSequence.new(Color3.fromRGB(60, 55, 50))
	smoke.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	smoke.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(1, 3.5),
	})
	smoke.Lifetime = NumberRange.new(0.6, 1)
	smoke.Speed = NumberRange.new(4, 9)
	smoke.Rotation = NumberRange.new(0, 360)
	smoke.SpreadAngle = Vector2.new(180, 180)
	smoke.Rate = 0
	smoke.Parent = anchor
	smoke:Emit(math.floor(18 * scale + 0.5))

	Debris:AddItem(anchor, 1.2)
end

-- Облачный взрыв (Облако, Дождь, Снег при смерти жука): облако лопается, а не горит.
-- Ни вспышки, ни огня, ни тёмного дыма — мягкий шар пара раздувается до радиуса удара,
-- клубы разлетаются и тают, пар поднимается вверх. Оттенок — свой у каждого облака
-- (blastColor в Elements), а из дождевого и снежного ещё падает осадок: облака
-- различаются и цветом, и тем, что из них сыплется.
local PUFF_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"

local function cloudBlast(position, radius, color, kind)
	radius = radius or BASE_EXPLOSION_RADIUS
	color = color or Color3.fromRGB(225, 230, 240)
	local scale = math.clamp(radius / BASE_EXPLOSION_RADIUS, 0.6, 2.5)
	local anchor = makeAnchor(position)
	local white = Color3.fromRGB(245, 248, 252)

	-- Шар пара: светлый, плотный в начале, раздувается ровно до радиуса и тает.
	-- Медленнее огненной вспышки — облако лопается мягко.
	local puff = Instance.new("Part")
	puff.Shape = Enum.PartType.Ball
	puff.Size = Vector3.new(1, 1, 1) * radius * 0.4
	puff.Anchored = true
	puff.CanCollide = false
	puff.CanQuery = false
	puff.CastShadow = false
	puff.Material = Enum.Material.SmoothPlastic
	puff.Color = color
	puff.Transparency = 0.35
	puff.Position = position
	puff.Parent = anchor

	TweenService:Create(puff, TweenInfo.new(0.55, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
		Size = Vector3.new(1, 1, 1) * radius * 2,
		Transparency = 1,
	}):Play()

	-- Волна по земле: широкое бледное кольцо, без неона — не огонь.
	local ring = Instance.new("Part")
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.15, 1, 1)
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CastShadow = false
	ring.Material = Enum.Material.SmoothPlastic
	ring.Color = color
	ring.Transparency = 0.45
	ring.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = anchor

	TweenService:Create(ring, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.15, radius * 2.2, radius * 2.2),
		Transparency = 1,
	}):Play()

	-- Клубы: крупные, разлетаются до края радиуса, тормозят и тают на месте.
	local clouds = Instance.new("ParticleEmitter")
	clouds.Texture = PUFF_TEXTURE
	clouds.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, white:Lerp(color, 0.6)),
		ColorSequenceKeypoint.new(1, color),
	})
	clouds.LightInfluence = 0.6
	clouds.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(0.6, 0.45),
		NumberSequenceKeypoint.new(1, 1),
	})
	clouds.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.5 * scale),
		NumberSequenceKeypoint.new(1, 4.5 * scale),
	})
	clouds.Lifetime = NumberRange.new(0.8, 1.3)
	clouds.Speed = NumberRange.new(radius * 1.6, radius * 2.6)
	clouds.Drag = 3
	clouds.Rotation = NumberRange.new(0, 360)
	clouds.RotSpeed = NumberRange.new(-40, 40)
	clouds.SpreadAngle = Vector2.new(180, 180)
	clouds.Rate = 0
	clouds.Parent = anchor
	clouds:Emit(math.floor(22 * scale + 0.5))

	-- Пар: тонкие струйки поднимаются над местом смерти и висят дольше клубов.
	local steam = Instance.new("ParticleEmitter")
	steam.Texture = PUFF_TEXTURE
	steam.Color = ColorSequence.new(white:Lerp(color, 0.5))
	steam.LightInfluence = 0.6
	steam.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.5),
		NumberSequenceKeypoint.new(1, 1),
	})
	steam.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.8 * scale),
		NumberSequenceKeypoint.new(1, 2.5 * scale),
	})
	steam.Lifetime = NumberRange.new(1.2, 1.8)
	steam.Speed = NumberRange.new(2, 5)
	steam.Acceleration = Vector3.new(0, 4, 0)
	steam.Rotation = NumberRange.new(0, 360)
	steam.SpreadAngle = Vector2.new(60, 60)
	steam.EmissionDirection = Enum.NormalId.Top
	steam.Rate = 0
	steam.Parent = anchor
	steam:Emit(math.floor(12 * scale + 0.5))

	-- Осадок: сыплется с плоской «тучи» над местом смерти на весь радиус удара.
	-- Частицы летят из нижней грани плашки, поэтому падают по всей площади, а не из точки.
	if kind == "rain" or kind == "snow" then
		local sky = Instance.new("Part")
		sky.Anchored = true
		sky.CanCollide = false
		sky.CanQuery = false
		sky.Transparency = 1
		sky.Size = Vector3.new(radius * 1.6, 0.2, radius * 1.6)
		sky.Position = position + Vector3.new(0, 5, 0)
		sky.Parent = anchor

		local fall = Instance.new("ParticleEmitter")
		fall.EmissionDirection = Enum.NormalId.Bottom
		fall.SpreadAngle = Vector2.new(4, 4)
		fall.Rate = 0
		if kind == "rain" then
			-- Капли: мелкие, быстрые, вытянуты по полёту.
			fall.Color = ColorSequence.new(Color3.fromRGB(150, 185, 230))
			fall.LightEmission = 0.3
			fall.Orientation = Enum.ParticleOrientation.VelocityParallel
			fall.Size = NumberSequence.new(0.12)
			fall.Transparency = NumberSequence.new(0.2)
			fall.Lifetime = NumberRange.new(0.25, 0.35)
			fall.Speed = NumberRange.new(18, 24)
			fall.Parent = sky
			fall:Emit(math.floor(60 * scale + 0.5))
		else
			-- Хлопья: белые, медленные, кружатся и тают у земли.
			fall.Texture = PUFF_TEXTURE
			fall.Color = ColorSequence.new(Color3.fromRGB(250, 252, 255))
			fall.LightEmission = 0.4
			fall.Size = NumberSequence.new(0.35)
			fall.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.1),
				NumberSequenceKeypoint.new(0.8, 0.3),
				NumberSequenceKeypoint.new(1, 1),
			})
			fall.Lifetime = NumberRange.new(1.4, 2)
			fall.Speed = NumberRange.new(2, 3.5)
			fall.Rotation = NumberRange.new(0, 360)
			fall.RotSpeed = NumberRange.new(-90, 90)
			fall.Parent = sky
			fall:Emit(math.floor(40 * scale + 0.5))
		end
	end

	Debris:AddItem(anchor, 2.5)
end

-- Земля под точкой взрыва: удар считается от середины жука, а пыль, трещины и лужа
-- ложатся на пол — с ямами и вздутиями рельефа (Loose.FloorAt).
local function groundUnder(position)
	return Vector3.new(position.X, Loose.FloorAt(position.X, position.Z, position.Y - 1.5), position.Z)
end

-- Плоский круг на полу (кольцо волны, пятно, лужа): цилиндр лёжа.
local function floorDisc(anchor, ground, diameter, color, material, transparency)
	local disc = Instance.new("Part")
	disc.Shape = Enum.PartType.Cylinder
	disc.Size = Vector3.new(0.12, diameter, diameter)
	disc.Anchored = true
	disc.CanCollide = false
	disc.CanQuery = false
	disc.CanTouch = false
	disc.CastShadow = false
	disc.Material = material or Enum.Material.SmoothPlastic
	disc.Color = color
	disc.Transparency = transparency or 0
	disc.CFrame = CFrame.new(ground + Vector3.new(0, 0.07, 0)) * CFrame.Angles(0, 0, math.rad(90))
	disc.Parent = anchor
	return disc
end

-- Тряска камеры от удара в землю: тем слабее, чем дальше игрок. Смещение вешается
-- поверх камеры каждый кадр и гаснет само — управление камерой не перехватывается.
local shakeLeft, shakeStrength = 0, 0
local function shakeCamera(position, strength, reach)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local distance = (camera.Focus.Position - position).Magnitude
	if distance > reach then
		return
	end
	local felt = strength * (1 - distance / reach)
	if felt <= shakeStrength * shakeLeft / 0.35 then
		return
	end
	shakeStrength, shakeLeft = felt, 0.35
end

RunService:BindToRenderStep("KillBlastShake", Enum.RenderPriority.Camera.Value + 1, function(dt)
	if shakeLeft <= 0 then
		return
	end
	shakeLeft = math.max(0, shakeLeft - dt)
	local amount = shakeStrength * shakeLeft / 0.35
	local camera = Workspace.CurrentCamera
	if camera then
		camera.CFrame *= CFrame.new((math.random() - 0.5) * amount, (math.random() - 0.5) * amount, 0)
	end
end)

-- Удар в землю (Континент — "quake") и разлом (Литосфера — "rift") при смерти жука.
-- Не огонь и не облако: тяжёлое бьёт в пол. Пыль стелется низко по полу до радиуса удара,
-- от места смерти расходятся трещины, вверх летят камни и падают обратно. power (0..1) —
-- сила удара от величины убитого (Effects.applyKillDamage): по вики «чем больше жук — тем
-- сильнее удар», и рой должен давать хлопок, а танк — воронку.
--
-- Разлом Литосферы — тот же удар, но глубже: волна идёт тремя кольцами одно за другим,
-- трещин больше и в них светятся недра, посередине провал, камни крупнее и выше.
-- Ландшафт под этим поднимает или опускает сам Lithosphere — здесь только удар.
local function earthBlast(position, radius, color, power, kind)
	radius = radius or BASE_EXPLOSION_RADIUS
	color = color or Color3.fromRGB(140, 125, 90)
	power = math.clamp(power or 1, 0, 1)
	local rift = kind == "rift"
	local scale = math.clamp(radius / BASE_EXPLOSION_RADIUS, 0.6, 2.5)
	local force = 0.45 + 0.55 * power
	local ground = groundUnder(position)
	local anchor = makeAnchor(ground)
	local dust = Color3.fromRGB(200, 185, 150):Lerp(color, 0.35)
	local dark = color:Lerp(Color3.new(0, 0, 0), 0.6)
	local magma = Color3.fromRGB(255, 110, 35)

	-- Волна по полу: пыльное кольцо до радиуса удара. У разлома — три подряд.
	for wave = 0, rift and 2 or 0 do
		task.delay(wave * 0.16, function()
			local ring = floorDisc(anchor, ground, 1, dust, Enum.Material.Sand, 0.25)
			TweenService:Create(ring, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Size = Vector3.new(0.12, radius * 2.1, radius * 2.1),
				Transparency = 1,
			}):Play()
		end)
	end

	-- Вмятина: тёмное пятно под местом смерти; у разлома посередине светится провал.
	local dent = floorDisc(anchor, ground, radius * 0.5 * force, dark, Enum.Material.Slate, 0.15)
	if rift then
		local glow = floorDisc(anchor, ground + Vector3.new(0, 0.02, 0), radius * 0.22 * force, magma, Enum.Material.Neon, 0.1)
		-- Сразу за ударом Lithosphere двигает пол (яма или вздутие), и плиты едут не мгновенно:
		-- пятно и провал едут вместе с полом под местом смерти, а не висят на старой высоте.
		task.spawn(function()
			local lastY = ground.Y
			local started = os.clock()
			while dent.Parent and os.clock() - started < 2.6 do
				task.wait(0.05)
				local y = Loose.FloorAt(ground.X, ground.Z, lastY)
				if math.abs(y - lastY) > 1e-3 then
					local shift = CFrame.new(0, y - lastY, 0)
					dent.CFrame = shift * dent.CFrame
					glow.CFrame = shift * glow.CFrame
					lastY = y
				end
			end
		end)
		local light = Instance.new("PointLight")
		light.Color = magma
		light.Range = radius * 0.9
		light.Brightness = 3
		light.Shadows = false
		light.Parent = glow
		TweenService:Create(light, TweenInfo.new(2.2), { Brightness = 0 }):Play()
		TweenService:Create(glow, TweenInfo.new(1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 1), {
			Transparency = 1,
		}):Play()
	end
	TweenService:Create(dent, TweenInfo.new(1, Enum.EasingStyle.Linear, Enum.EasingDirection.In, 0, false, 1.4), {
		Transparency = 1,
	}):Play()

	-- Трещины: тонкие клинья по полу из места смерти, вытягиваются за доли секунды.
	local cracks = rift and 9 or 6
	for i = 1, cracks do
		local angle = (i / cracks + (math.random() - 0.5) * 0.08) * math.pi * 2
		local length = radius * (rift and 0.75 or 0.55) * force * (0.7 + math.random() * 0.4)
		local width = (rift and 0.45 or 0.3) * (0.7 + math.random() * 0.5)
		local base = CFrame.new(ground + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, angle, 0)
		local crack = Instance.new("Part")
		crack.Anchored = true
		crack.CanCollide = false
		crack.CanQuery = false
		crack.CanTouch = false
		crack.CastShadow = false
		crack.Material = rift and Enum.Material.Neon or Enum.Material.Slate
		crack.Color = rift and magma or dark
		crack.Size = Vector3.new(width, 0.08, 0.1)
		crack.CFrame = base * CFrame.new(0, 0, -0.05)
		crack.Parent = anchor
		TweenService:Create(crack, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = Vector3.new(width, 0.08, length),
			CFrame = base * CFrame.new(0, 0, -length / 2),
		}):Play()
		-- Трещины разлома гаснут раньше пятна: пол под ними сейчас поедет, а они лежат по старому.
		TweenService:Create(crack, TweenInfo.new(rift and 0.6 or 1, Enum.EasingStyle.Linear, Enum.EasingDirection.In, 0, false, rift and 0.5 or 1.2), {
			Transparency = 1,
		}):Play()
	end

	-- Пыль: низко по полу во все стороны до края удара, тормозит и висит.
	local cloud = Instance.new("ParticleEmitter")
	cloud.Texture = PUFF_TEXTURE
	cloud.Color = ColorSequence.new(dust)
	cloud.LightInfluence = 0.8
	cloud.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(0.6, 0.5),
		NumberSequenceKeypoint.new(1, 1),
	})
	cloud.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.2 * scale),
		NumberSequenceKeypoint.new(1, 3.8 * scale),
	})
	cloud.Lifetime = NumberRange.new(0.9, 1.5)
	cloud.Speed = NumberRange.new(radius * 1.4, radius * 2.4)
	cloud.Drag = 3.5
	cloud.Rotation = NumberRange.new(0, 360)
	cloud.RotSpeed = NumberRange.new(-30, 30)
	cloud.EmissionDirection = Enum.NormalId.Top
	cloud.SpreadAngle = Vector2.new(80, 80)
	cloud.Acceleration = Vector3.new(0, -2, 0)
	cloud.Rate = 0
	cloud.Parent = anchor
	cloud:Emit(math.floor((rift and 30 or 18) * force * scale + 0.5))

	-- Камни: настоящие детали в физике — вылетают, падают и раскатываются по полу,
	-- потом растворяются. Учёт и потолок — общий (Loose.Track, вид "rock").
	local rocks = math.floor((rift and 8 or 4) + (rift and 8 or 6) * power + 0.5)
	local rockColor = color:Lerp(Color3.fromRGB(70, 65, 60), 0.4)
	for _ = 1, rocks do
		local size = (rift and 0.7 or 0.45) + math.random() * (rift and 0.8 or 0.5)
		local rock = Instance.new("Part")
		rock.Size = Vector3.new(size, size * (0.6 + math.random() * 0.4), size * (0.7 + math.random() * 0.5))
		rock.Material = Enum.Material.Slate
		rock.Color = rockColor:Lerp(dark, math.random() * 0.5)
		rock.CanQuery = false
		rock.CanTouch = false
		rock.CFrame = CFrame.new(ground + Vector3.new(0, size, 0)) * CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6)
		rock.Parent = anchor
		local angle = math.random() * math.pi * 2
		local out = Vector3.new(math.cos(angle), 0, math.sin(angle)) * (6 + math.random() * 8) * force
		local up = Vector3.new(0, (rift and 26 or 18) + math.random() * 12, 0) * force
		Loose.Spawn(rock, { folder = "Debris", tag = false, velocity = out + up, spin = Loose.RandomSpin(10) })
		Loose.Track(rock, "rock")
		task.delay(1.8 + math.random() * 0.8, function()
			Loose.Dissolve(rock, 0.8)
		end)
	end

	shakeCamera(ground, (rift and 0.9 or 0.45) * force, radius * 4)
	Debris:AddItem(anchor, rift and 3.2 or 2.6)
end

-- Водный взрыв (Океан — "wave") при смерти жука: не горит и не клубится, а плещет.
-- Из места смерти бьёт столб воды и опадает, брызги летят дугой и падают, по полу
-- разбегается пенное кольцо до радиуса удара — по нему видно, кого намочило (по вики
-- задетые получают Мокрость). Остаётся лужа и медленно высыхает.
local function waveBlast(position, radius, color)
	radius = radius or BASE_EXPLOSION_RADIUS
	color = color or Color3.fromRGB(0, 165, 155)
	local scale = math.clamp(radius / BASE_EXPLOSION_RADIUS, 0.6, 2.5)
	local ground = groundUnder(position)
	local anchor = makeAnchor(ground)
	local foam = Color3.fromRGB(235, 250, 250)
	local light = color:Lerp(foam, 0.45)

	-- Купол: прозрачный шар воды раздувается и лопается.
	local dome = Instance.new("Part")
	dome.Shape = Enum.PartType.Ball
	dome.Size = Vector3.new(1, 1, 1) * radius * 0.3
	dome.Anchored = true
	dome.CanCollide = false
	dome.CanQuery = false
	dome.CanTouch = false
	dome.CastShadow = false
	dome.Material = Enum.Material.Glass
	dome.Color = light
	dome.Transparency = 0.35
	dome.Position = ground + Vector3.new(0, radius * 0.1, 0)
	dome.Parent = anchor
	TweenService:Create(dome, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(1, 1, 1) * radius * 1.4,
		Transparency = 1,
	}):Play()

	-- Столб: вода бьёт вверх и опадает обратно.
	local height = radius * 0.9
	local column = Instance.new("Part")
	column.Shape = Enum.PartType.Cylinder
	column.Anchored = true
	column.CanCollide = false
	column.CanQuery = false
	column.CanTouch = false
	column.CastShadow = false
	column.Material = Enum.Material.Glass
	column.Color = color
	column.Transparency = 0.3
	column.Size = Vector3.new(0.2, radius * 0.25, radius * 0.25)
	column.CFrame = CFrame.new(ground + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.rad(90))
	column.Parent = anchor
	local rise = TweenService:Create(column, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(height, radius * 0.4, radius * 0.4),
		CFrame = CFrame.new(ground + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
	})
	rise.Completed:Once(function()
		TweenService:Create(column, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Size = Vector3.new(0.2, radius * 0.6, radius * 0.6),
			CFrame = CFrame.new(ground + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			Transparency = 0.9,
		}):Play()
	end)
	rise:Play()

	-- Пенное кольцо и за ним второе, водяное: волна до радиуса удара.
	for wave, tint in { foam, light } do
		task.delay((wave - 1) * 0.12, function()
			local ring = floorDisc(anchor, ground, 1, tint, Enum.Material.SmoothPlastic, 0.3)
			TweenService:Create(ring, TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Size = Vector3.new(0.12, radius * 2.1, radius * 2.1),
				Transparency = 1,
			}):Play()
		end)
	end

	-- Брызги: капли дугой вверх и в стороны, падают под тяжестью.
	local spray = Instance.new("ParticleEmitter")
	spray.Color = ColorSequence.new(light, color)
	spray.LightEmission = 0.25
	spray.Orientation = Enum.ParticleOrientation.VelocityParallel
	spray.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3),
		NumberSequenceKeypoint.new(1, 0.12),
	})
	spray.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(0.8, 0.3),
		NumberSequenceKeypoint.new(1, 1),
	})
	spray.Lifetime = NumberRange.new(0.8, 1.2)
	spray.Speed = NumberRange.new(radius * 2, radius * 3.2)
	spray.Acceleration = Vector3.new(0, -60, 0)
	spray.EmissionDirection = Enum.NormalId.Top
	spray.SpreadAngle = Vector2.new(55, 55)
	spray.Rate = 0
	spray.Parent = anchor
	spray:Emit(math.floor(70 * scale + 0.5))

	-- Водяная пыль: низко над полом, светлая, тает.
	local mist = Instance.new("ParticleEmitter")
	mist.Texture = PUFF_TEXTURE
	mist.Color = ColorSequence.new(foam:Lerp(color, 0.25))
	mist.LightInfluence = 0.6
	mist.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.45),
		NumberSequenceKeypoint.new(1, 1),
	})
	mist.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1 * scale),
		NumberSequenceKeypoint.new(1, 3 * scale),
	})
	mist.Lifetime = NumberRange.new(0.7, 1.1)
	mist.Speed = NumberRange.new(radius * 1.2, radius * 2)
	mist.Drag = 4
	mist.EmissionDirection = Enum.NormalId.Top
	mist.SpreadAngle = Vector2.new(85, 85)
	mist.Rate = 0
	mist.Parent = anchor
	mist:Emit(math.floor(14 * scale + 0.5))

	-- Лужа: блестящее пятно воды на полу, сохнет и сжимается.
	local puddle = floorDisc(anchor, ground, radius * 1.3, color, Enum.Material.Glass, 0.45)
	puddle.Reflectance = 0.25
	TweenService:Create(puddle, TweenInfo.new(1.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 1.2), {
		Size = Vector3.new(0.12, radius * 0.6, radius * 0.6),
		Transparency = 1,
	}):Play()

	Debris:AddItem(anchor, 3.2)
end

-- Развилка по аргументам: цвет третьим шлёт только подрыв дрона (Projectile.burst),
-- вид взрыва четвёртым — удар по области при смерти (Effects.applyKillDamage, поле blast).
-- Шестой — сила удара (0..1) у ударов от величины жука. Порох и Взрыв шлют два
-- аргумента, как и шлали.
local function onExplosion(position, radius, droneColor, blast, color, power)
	if droneColor then
		droneBlast(position, radius, droneColor)
	elseif blast == "cloud" or blast == "rain" or blast == "snow" then
		cloudBlast(position, radius, color, blast)
	elseif blast == "quake" or blast == "rift" then
		earthBlast(position, radius, color, power, blast)
	elseif blast == "wave" then
		waveBlast(position, radius, color)
	else
		onPyroExplosion(position, radius)
	end
end

Remotes.ShotFired.OnClientEvent:Connect(onShotFired)
Remotes.DamageDealt.OnClientEvent:Connect(onDamageDealt)
Remotes.EnemyDied.OnClientEvent:Connect(onEnemyDied)
Remotes.Explosion.OnClientEvent:Connect(onExplosion)
