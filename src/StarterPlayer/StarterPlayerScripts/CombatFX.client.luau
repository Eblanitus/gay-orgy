-- Мгновенные эффекты боя: луч выстрела, всплывающая цифра урона, гасимая смерть и отдельно —
-- настоящий пиротехнический взрыв (Порох/Взрыв, см. onExplosion). Сервер только сообщает
-- позиции/числа, вся отрисовка здесь.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
-- Турель на риге узнаётся по таблице (Towers[тип].rig), а не по имени деталей:
-- см. rigDirection ниже.
local Towers = require(ReplicatedStorage:WaitForChild("Towers"))
-- Только ради шрифта цифры урона: она висит над ареной рядом с показаниями HUD,
-- и чужой шрифт там виден сразу.
local Theme = require(script.Parent:WaitForChild("UITheme"))
-- Настройка «Цифры урона» из главного меню — см. onDamageDealt.
local Settings = require(script.Parent:WaitForChild("Settings"))

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
	label.Text = "-" .. tostring(amount)
	label.TextColor3 = isBase and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(255, 140, 40)
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

-- Развилка по третьему аргументу: цвет шлёт только подрыв дрона (Projectile.burst),
-- Порох и Взрыв (Effects) шлют два аргумента, как и шлали.
local function onExplosion(position, radius, droneColor)
	if droneColor then
		droneBlast(position, radius, droneColor)
	else
		onPyroExplosion(position, radius)
	end
end

Remotes.ShotFired.OnClientEvent:Connect(onShotFired)
Remotes.DamageDealt.OnClientEvent:Connect(onDamageDealt)
Remotes.EnemyDied.OnClientEvent:Connect(onEnemyDied)
Remotes.Explosion.OnClientEvent:Connect(onExplosion)
