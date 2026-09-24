-- Трупы и кровь: что остаётся на поле после жука. КЛИЕНТСКАЯ часть.
--
-- Труп — чистый визуал: путь, HP, прицел и проход жуков от него не зависят. Раньше туши,
-- оторванные куски и пятна строил и считал сервер, и каждая их деталь шла по сети. Теперь
-- серверный ServerScriptService.Corpses хранит только логические записи (точка смерти —
-- для Пеликана) и шлёт события по Remotes.EnemyFX, а тушу строит каждый клиент сам из
-- видимого тела жука (EnemyRender). Правила ниже — те же, что были на сервере.
--
-- До этой задачи убитый жук просто исчезал (enemy:Destroy в EnemySpawner), и поле после
-- волны выглядело так же, как до неё. Правила системы (alchemy_td_enemies_buff_design_v2,
-- раздел 3):
--
--   * труп — НЕ преграда: путь, движение и плотность колонны он не меняет, жуки ходят
--     по трупам. Отсюда CanCollide = false и CanQuery = false у всех его частей: он не ловит
--     ни лучи походки, ни курсор стройки;
--   * HP у трупа нет, дебаффы с него снимаются, эффекты на него не действуют — поэтому
--     он живёт в своей папке, а не в Workspace.Enemies: все, кто ищет цели, смотрят именно
--     там, и отдельной проверки «а живой ли» никому дописывать не надо;
--   * трупы живут до конца забега; фиксированного потолка в дизайне нет — его выставляет
--     оптимизация (MAX_CORPSES ниже), и при превышении самые старые растворяются.
--     Единственное требование дизайна: когда труп растворился, в мире не меняется
--     ничего — Гора и зона Землетрясения отработали в момент смерти и от трупа
--     не зависят;
--   * труп оставляют ВСЕ, включая летающих: останки Лицехвата падают вертикально под
--     точку гибели и дальше ведут себя как наземные. Поэтому высота у трупа всегда одна
--     и та же — пол, независимо от того, где жук умер (на лету, на стене, на спине соседа);
--   * Гора поглощает труп (Corpses.Absorb): игрок видит «где упал крупный — там выросла
--     стена», а моделей на поле меньше.
--
-- Модель трупа не собирается заново — это клон самого жука в позе смерти: тот же силуэт,
-- тот же размер, тот же вид — игрок узнаёт, кто здесь лежит. Отличается труп двумя
-- вещами: позой (перевёртыш с поджатыми лапами, см. EnemyGait.DeathPose) и выцветанием.
-- Оба признака обязаны читаться отдельно от любого дебафф-состояния (правило v2,
-- раздел 4): поле из трупов не должно читаться как толпа застывших живых.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local CollectionService = game:GetService("CollectionService")

local Arena = require(ReplicatedStorage:WaitForChild("Arena"))
local EnemyGait = require(ReplicatedStorage:WaitForChild("EnemyGait"))
local PhysicsFX = require(ReplicatedStorage:WaitForChild("PhysicsFX"))
local Impulse = require(ReplicatedStorage:WaitForChild("ImpulseFX"))

-- Группы столкновений (заводит и связывает серверный Corpses, клиенту они реплицируются). Труп обязан ловить толчок от жука, но только его: тело жука
-- анкорнуто и физикой не двигается вовсе, поэтому столкновение здесь одностороннее —
-- сдвигается только труп. Оттого и правило дизайна остаётся в силе: труп не преграда,
-- путь и плотность колонны он не меняет, потому что жука он не тормозит ни на кадр.
local ENEMY_GROUP = "Enemies"
local CORPSE_GROUP = "Corpses"

-- Плотный, но не каменный, с высоким трением и без отскока: сдвинутый труп проезжает
-- полстуда и встаёт, а не укатывается через всю арену от одного задевшего его жука.
local CORPSE_PHYSICS = PhysicalProperties.new(0.4, 0.9, 0, 1, 1)

-- Балласт в брюхе. Невидимая тяжёлая деталь внизу тела — это не фиксатор крена,
-- а центр тяжести там, где ему у жука и место. С ним туша ведёт себя как неваляшка:
-- толкать её можно куда угодно и качнуть тоже, но встать НА НОС у стены и так застыть
-- она больше не может — а именно это выходило при падении со стены (два из трёх
-- трупов замирали стоймя на y = 1.8, то есть на длинном торце).
--
-- Одно число — одна ручка: чем оно меньше, тем охотнее труп остаётся лежать так,
-- как его положило.
local BALLAST_DENSITY = 30

-- Закрутка при падении, рад/сек, и только вокруг ВЕРТИКАЛИ. Без неё туша опускается
-- на землю как поставленный реквизит; а вот кувырок по другим осям при падении со стены
-- кладёт жука на спину — тот самый перевёртыш, которого автор отменил (замечено
-- плейтестом: убитый на высоте 3.87 ложился брюхом вверх). Вокруг вертикали плоская
-- туша перевернуться не может физически.
local TUMBLE = 3

local Corpses = {}

-- Физику останков считает этот же клиент: детали локальные, отдавать их некому.
local function giveOwner(root) end

-- Сколько трупов держим на поле одновременно. Цифра не из дизайна — он её нарочно
-- не задаёт и отдаёт оптимизации. 60 трупов по 6 частей — 360 анкорнутых деталей,
-- которые ничего не считают и не двигаются.
local MAX_CORPSES = 60

-- Сколько пятен крови. Их много больше, чем трупов (каждое попадание — капли),
-- но каждое — одна плоская деталь без тени и без запросов.
local MAX_STAINS = 220

local FADE_TIME = 1.2 -- секунд на растворение самого старого

-- Насколько труп выцветает к серому: дешёвый и ясный сигнал «мёртв», который не
-- конфликтует ни с одной меткой индикации (индикация с трупа снята вместе с моделью).
local DEATH_FADE = 0.5
local DEATH_COLOR = Color3.fromRGB(96, 92, 84)

-- Кровь зелёная: гемолимфа, а не кровь млекопитающего. Оттенок каждого пятна
-- чуть свой (BLOOD_SPREAD): один цвет на всё поле читается как краска, а не как следы.
local BLOOD_COLOR = Color3.fromRGB(62, 116, 38)
local BLOOD_SPREAD = 26 -- единиц RGB в обе стороны
local BLOOD_THICKNESS = 0.06 -- studs: пятно плоское, но не нулевое — иначе мерцает с полом
local BLOOD_LIFT = 0.03 -- studs над полом: тот же зазор против z-fighting

-- Живые останки в порядке появления: самый старый — первый в списке.
local corpses = {}
local stains = {}
local pieces = {} -- оторванные конечности (см. detachPieces), свой потолок PhysicsFX.gore.fieldLimit
-- Номер записи серверного Corpses -> туша: по нему Пеликан съедает именно тот труп, у которого стоит.
-- Слабые значения: растворённая по лимиту туша уходит и отсюда сама.
local byId = setmetatable({}, { __mode = "v" })

local function container(name)
	local folder = Workspace:FindFirstChild(name)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = name
		folder.Parent = Workspace
	end
	return folder
end

-- Растворяет и сносит. Не мгновенный Destroy нарочно: труп, пропавший на глазах
-- в один кадр, читается как поломка. На геймплей растворение не влияет никак: Гора
-- и зона Землетрясения сработали в момент смерти и от трупа больше не зависят.
local function dissolve(instance)
	if not instance or not instance.Parent then
		return
	end

	local info = TweenInfo.new(FADE_TIME, Enum.EasingStyle.Linear)
	for _, part in instance:GetDescendants() do
		if part:IsA("BasePart") then
			TweenService:Create(part, info, { Transparency = 1 }):Play()
		end
	end
	if instance:IsA("BasePart") then
		TweenService:Create(instance, info, { Transparency = 1 }):Play()
	end

	task.delay(FADE_TIME, function()
		if instance.Parent then
			instance:Destroy()
		end
	end)
end

-- Общее для трупов и крови: список с потолком, самые старые уходят первыми.
local function remember(list, instance, limit)
	table.insert(list, instance)
	while #list > limit do
		local oldest = table.remove(list, 1)
		dissolve(oldest)
	end
end

-- Останки жука на месте смерти. Зовётся ДО enemy:Destroy() — модель ещё целая
-- и стоит там, где его убили.
--
-- Клон, а не сама модель: цикл движения жука живёт, пока жива его модель
-- (while enemy.Parent в EnemySpawner), и перевешать её в другую папку значило бы оставить
-- труп шагать к выходу. Клон кстати чистый и от клиентской индикации: полоска HP,
-- огонь и обводка собираются на клиенте (EnemyVisuals) и на серверной модели их нет.
-- Корпус столкновения трупа — по РЕАЛЬНЫМ габаритам видимых частей в позе смерти.
--
-- Раньше с полом сталкивался только PrimaryPart. У шаблонного жука это Root — невидимый
-- якорь на высоте пивота, и его нижняя грань выше всего, что под ним: ступни в позе
-- смерти (≈ 0.8 ниже пивота), брюшные пластины (≈ 0.64), а грань Root — 0.5 (в единицах шаблона).
-- Всё ниже грани уходило в пол — жалоба автора «конечности трупов проходят сквозь пол».
-- Коробка, а не коллизии самих лап: тонкие лапы цепляются за всё и дёргают тушу (см. ниже).
-- Конечность ли деталь (лапа, усик, жвала) — по имени её или её предков внутри трупа.
local function isLimb(part, model)
	local node = part
	while node and node ~= model do
		local name = node.Name
		if name:match("^leg_") or name:match("^Leg%d") or name:match("^antenna_") or name:match("^mandible_") then
			return true
		end
		node = node.Parent
	end
	return false
end

-- Полуразмер детали для счёта габарита. У мешей лап геометрия запечена по диагонали
-- (см. EnemyGait.placeModelLeg): голень-палка толщиной 0.4 лежит в коробке 2.25 × 2.13, и угол
-- этой коробки уходит на 1.4 studs ниже самой лапы. Hull по таким углам ставил тушу на
-- невидимую подпорку (тело висело над полом), а оторванная лапа стояла торчком
-- в раздутой коробке — замечено в Аркаде. Потому у конечностей деталь считается кубиком
-- толщины палки вокруг центра; концы палок и так задают шарниры-сферы (там коробка точная).
-- Самая узкая сторона коробки не годится в толщину: у бедра она 1.15 при палке ~0.4 (Scale = 3) —
-- оттого потолок LIMB_THICKNESS в единицах шаблона (голень 0.14, шарниры 0.11–0.17).
local LIMB_THICKNESS = 0.16

local function measureHalf(part, limb, modelScale)
	if limb then
		local thickness = math.min(part.Size.X, part.Size.Y, part.Size.Z, LIMB_THICKNESS * (modelScale or 3))
		return Vector3.one * (thickness * 0.5)
	end
	return part.Size * 0.5
end

local function collider(model, name, shape, size, cframe)
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = shape
	part.Size = size
	part.CFrame = cframe
	part.Transparency = 1
	part.CanCollide = true
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Anchored = true
	part.CollisionGroup = CORPSE_GROUP
	part.CustomPhysicalProperties = CORPSE_PHYSICS
	part.Parent = model
	return part
end

local function buildHull(model, root, modelScale)
	local frame = root.CFrame
	-- Ширина, длина и верх — по туловищу; низ — по самой нижней точке вообще (ступни позы
	-- смерти). По габариту с растопыренными лапами коробка выходила почти кубом
	-- (10.7 × 5.7 × 11 у Стандарта) и устойчиво стояла на любой грани — замерено стендом.
	local low, high, bottom
	local anyLow, anyHigh
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part.Transparency < 1 then
			local limb = isLimb(part, model)
			local half = measureHalf(part, limb, modelScale)
			for _, sx in { -1, 1 } do
				for _, sy in { -1, 1 } do
					for _, sz in { -1, 1 } do
						local corner = frame:PointToObjectSpace(part.CFrame * Vector3.new(half.X * sx, half.Y * sy, half.Z * sz))
						bottom = bottom and math.min(bottom, corner.Y) or corner.Y
						anyLow = anyLow and anyLow:Min(corner) or corner
						anyHigh = anyHigh and anyHigh:Max(corner) or corner
						if not limb then
							low = low and low:Min(corner) or corner
							high = high and high:Max(corner) or corner
						end
					end
				end
			end
		end
	end
	if not anyLow then
		return nil
	end
	-- У примитива без туловища в списке — габарит целиком.
	low = low or anyLow
	high = high or anyHigh
	low = Vector3.new(low.X, bottom, low.Z)

	local size = (high - low):Max(Vector3.one * 0.2)
	local center = (low + high) / 2
	-- Нос и хвост — шары: на торце туше опереться не на что, и упавший со стены носом вниз
	-- заваливается сам, а не стоит столбиком. Плоское брюхо даёт коробка между ними.
	local radius = math.min(size.X, size.Y) / 2
	local core = math.max(size.Z - radius * 2, 0.2)
	local hull = collider(model, "Hull", Enum.PartType.Block, Vector3.new(size.X, size.Y, core), frame * CFrame.new(center))
	if size.Z > radius * 2 then
		for _, side in { -1, 1 } do
			collider(model, "HullEnd", Enum.PartType.Ball, Vector3.one * radius * 2,
				frame * CFrame.new(center + Vector3.new(0, 0, side * (size.Z / 2 - radius))))
		end
	end
	return hull
end

-- Все BasePart одной оторванной части (сама деталь-нога примитива или детали модели-лапы).
local function partsOf(instance)
	if instance:IsA("BasePart") then
		return { instance }
	end
	local list = {}
	for _, part in instance:GetDescendants() do
		if part:IsA("BasePart") then
			table.insert(list, part)
		end
	end
	return list
end

-- Какие части оторвать. Список групп: голова отлетает ВМЕСТЕ с усиками и жвалами —
-- у шаблона это отдельные модели, и без этого усики оставались бы висеть над пустым местом.
local function chooseLimbs(corpse, fraction)
	local plan = PhysicsFX.gore
	if fraction < plan.minFraction then
		return {}
	end
	local count = math.min(plan.maxPieces, 1 + math.floor((fraction - plan.minFraction) / plan.perPiece))

	local groups = {}
	local taken = {}
	local head = corpse:FindFirstChild("head", true)
	if head and fraction >= plan.headFraction and math.random() < plan.headChance then
		local group = { head }
		taken[head] = true
		for _, name in { "antenna_left", "antenna_right", "mandible_left", "mandible_right" } do
			local extra = corpse:FindFirstChild(name, true)
			if extra then
				table.insert(group, extra)
				taken[extra] = true
			end
		end
		table.insert(groups, group)
		count -= 1
	end

	local pool, total = {}, 0
	for _, instance in corpse:GetDescendants() do
		if not taken[instance] and (instance:IsA("Model") or instance:IsA("BasePart")) then
			local name = instance.Name
			local weight = (name:match("^antenna_") and plan.weights.antenna)
				or (name:match("^mandible_") and plan.weights.mandible)
				or ((name:match("^leg_") or name:match("^Leg%d")) and plan.weights.leg)
			if weight then
				table.insert(pool, { instance = instance, weight = weight })
				total += weight
			end
		end
	end

	while count > 0 and #pool > 0 do
		local roll = math.random() * total
		local index = #pool
		for i, entry in pool do
			roll -= entry.weight
			if roll <= 0 then
				index = i
				break
			end
		end
		local entry = table.remove(pool, index)
		total -= entry.weight
		table.insert(groups, { entry.instance })
		count -= 1
	end
	return groups
end

-- Отрывает группу частей от трупа: отдельная физическая сборка в папке Debris, улетает
-- от удара и от тела, на месте отрыва — пятно. Не в папке Corpses нарочно: там ищут трупы
-- целиком (Пеликан ест трупы), а оторванная лапа трупом не является.
local function detachPiece(corpse, group, bodyCenter, from, fraction, scale, floorY, carry)
	local plan = PhysicsFX.gore
	local piece = Instance.new("Model")
	piece.Name = corpse.Name .. " — " .. group[1].Name

	local parts = {}
	for _, instance in group do
		for _, part in partsOf(instance) do
			table.insert(parts, part)
		end
		instance.Parent = piece
	end
	if #parts == 0 then
		piece:Destroy()
		return
	end

	-- Физика части — невидимая коробка по её габариту, а видимые детали — невесомое
	-- оформление на сварке. У мешей лап и усиков масса практически ноль (0.000–0.08),
	-- и сборка из них самих на первом же касании разгонялась до бесконечности — замерено стендом.
	-- Габарит — по measureHalf, а не GetBoundingBox: тот берёт раздутые коробки мешей.
	local low, high
	for _, part in parts do
		local half = measureHalf(part, true, scale * 3)
		for _, sx in { -1, 1 } do
			for _, sy in { -1, 1 } do
				for _, sz in { -1, 1 } do
					local corner = part.CFrame * Vector3.new(half.X * sx, half.Y * sy, half.Z * sz)
					low = low and low:Min(corner) or corner
					high = high and high:Max(corner) or corner
				end
			end
		end
	end
	local boxFrame, boxSize = CFrame.new((low + high) / 2), high - low
	local root = collider(piece, "Hull", Enum.PartType.Block, boxSize:Max(Vector3.one * 0.3), boxFrame)
	piece.PrimaryPart = root
	table.insert(parts, root)

	for _, part in parts do
		if part ~= root then
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.Massless = true
			part.CollisionGroup = CORPSE_GROUP
		end
		if part ~= root then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = root
			weld.Part1 = part
			weld.Parent = root
		end
	end
	for _, part in parts do
		part.Anchored = false
	end
	piece.Parent = container("Debris")
	CollectionService:AddTag(piece, Impulse.Tag)
	giveOwner(root)

	-- Летит от удара и от тела сразу: только «от удара» сбило бы все куски в одну кучу,
	-- только «от тела» — потеряло бы направление выстрела.
	local outward = root.Position - bodyCenter
	outward = Vector3.new(outward.X, 0, outward.Z)
	outward = outward.Magnitude > 1e-3 and outward.Unit or Vector3.zero
	local away = Vector3.zero
	if from then
		away = bodyCenter - from
		away = Vector3.new(away.X, 0, away.Z)
		away = away.Magnitude > 1e-3 and away.Unit or Vector3.zero
	end
	local direction = away * 0.6 + outward * 0.4
	if direction.Magnitude < 1e-3 then
		local angle = math.random() * math.pi * 2
		direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
	end
	direction = (direction.Unit + Vector3.yAxis * plan.lift).Unit
	local speed = plan.speedMin + (plan.speed - plan.speedMin) * math.clamp(fraction, 0, 1.5)
	Impulse.Kick(root, direction * speed + (carry or Vector3.zero), Impulse.RandomSpin(plan.spin))
	giveOwner(root) -- Kick забирает сборку серверу: вернуть тому, кто её считает

	Corpses.Splat(root.Position, plan.splatSize * scale, 1, floorY)
	remember(pieces, piece, plan.fieldLimit)
end

-- enemy — ВИДИМОЕ тело жука (модель EnemyRender). hit — чем убили (присылает сервер):
-- { scorched = умер под Горением/Плавлением, fraction = доля макс. HP добивающего удара,
-- from = откуда прилетело или nil, floorY = высота пола под пятна, если не арена,
-- carry = скорость того, кто задавил, или nil: туша и куски уезжают вместе с ударом, а не остаются под ним,
-- scale = масштаб жука }. По нему отрываются конечности и отлетает сама туша.
-- id — номер логической записи трупа на сервере (для Corpses.Eat).
function Corpses.Leave(enemy, hit, id)
	if not enemy.PrimaryPart then
		return nil
	end

	-- Убитый под Горением или Плавлением обугливается (атрибут Scorched ставит Effects на
	-- серверной модели; сервер кладёт его в hit, чтобы не зависеть от порядка репликации).
	local charred = hit and hit.scorched == true
	local fadeColor = charred and PhysicsFX.char.color or DEATH_COLOR
	local fade = charred and PhysicsFX.char.fade or DEATH_FADE
	local scale = (hit and hit.scale or enemy:GetAttribute("Scale") or 3) / 3

	local corpse = enemy:Clone()
	corpse.Name = enemy.Name .. " (труп)"
	-- Индикация живого (полоска HP, огонь, обводка — EnemyVisuals) висит на видимом теле и уехала
	-- бы вместе с клоном.
	for _, item in corpse:GetDescendants() do
		if item:IsA("BillboardGui") or item:IsA("Fire") or item:IsA("Sparkles") or item:IsA("Smoke")
			or item:IsA("Highlight") then
			item:Destroy()
		end
	end

	-- Атрибуты снимаются все без разбора: у трупа нет ни HP, ни дебаффов, ни скорости,
	-- и оставленный атрибут рано или поздно прочтёт тот, кто ищет живых по атрибутам.
	-- Кроме служебных RBX_* (RBX_ReimportId на импортированной модели): их может писать только
	-- CoreScript, SetAttribute бросает ошибку, и enemy:Destroy() после Leave уже не случался —
	-- убитый жук оставался на поле с HP 0 (см. CHANGELOG #165).
	for name in corpse:GetAttributes() do
		if name:sub(1, 4) ~= "RBX_" then
			corpse:SetAttribute(name, nil)
		end
	end

	local root = corpse.PrimaryPart
	for _, part in corpse:GetDescendants() do
		if part:IsA("BasePart") then
			part.CanQuery = false -- труп не ловит ни лучи походки, ни курсор стройки
			part.CanTouch = false
			-- Тень туша отбрасывает как живой жук: без неё труп в момент смерти вспыхивал светлее — замечено автором.
			part.CollisionGroup = CORPSE_GROUP
			part.CustomPhysicalProperties = CORPSE_PHYSICS
			-- Своей коллизии у деталей нет: тонкие лапы цеплялись бы за всё подряд и дёргали
			-- труп на ровном месте. С полом сталкивается один Hull по габаритам позы смерти
			-- (см. buildHull).
			part.CanCollide = false
			part.Color = part.Color:Lerp(fadeColor, fade)
		end
	end

	-- Жук не переворачивается — он падает (решение автора). Труп встаёт ровно там и так,
	-- как стоял живой: та же точка, тот же разворот. Дальше его роняет и укладывает физика.
	--
	-- Отдельное правило «высота всегда пол» больше не нужно: убитый на стене сваливается
	-- с неё сам, а останки Лицехвата падают под точку гибели — ровно то, чего требует
	-- дизайн, только теперь это делает гравитация, а не арифметика.
	corpse:PivotTo(enemy:GetPivot())

	EnemyGait.DeathPose(corpse, enemy)
	corpse.Parent = container("Corpses")

	-- Отрыв — после позы (лапы улетают уже подогнутыми) и до сборки Hull и сварки:
	-- тело не должно ни быть габаритнее из-за улетевшей лапы, ни быть приварено к ней.
	local fraction = hit and hit.fraction or 0
	local from = hit and hit.from or nil
	local bodyCenter = corpse:GetBoundingBox().Position
	for _, group in chooseLimbs(corpse, fraction) do
		detachPiece(corpse, group, bodyCenter, from, fraction, scale, hit and hit.floorY, hit and hit.carry)
	end

	local hull = buildHull(corpse, root, scale * 3)

	-- Физика включается ПОСЛЕ позы: сварка запоминает взаимное положение частей в момент
	-- своего создания, и собери мы тушу до того — она застыла бы в позе живого.
	for _, part in corpse:GetDescendants() do
		if part:IsA("BasePart") and part ~= root then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = root
			weld.Part1 = part
			weld.Parent = root
		end
	end
	for _, part in corpse:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = false
		end
	end

	-- Центр тяжести в брюхе (см. BALLAST_DENSITY). Ставится последним и сваривается с корпусом
	-- так же, как остальные части.
	local ballast = Instance.new("Part")
	ballast.Name = "Ballast"
	ballast.Size = root.Size * Vector3.new(0.5, 0.35, 0.5)
	-- Глубже, чем половина толщины тела, то есть НАРУЖУ (деталь невидимая и не
	-- сталкивается, так что торчать ей не мешает). Именно это делает стойку на торце
	-- НЕУСТОЙЧИВОЙ: центр тяжести выходит за опорную площадку торца (половина толщины
	-- тела), и туша валится на брюхо сама. С неглубоким балластом (0.45) центр ещё
	-- попадал в эту площадку, и труп так и стоял на носу — замерено.
	ballast.CFrame = root.CFrame * CFrame.new(0, -root.Size.Y * 0.95, 0)
	ballast.Transparency = 1
	ballast.CanCollide = false
	ballast.CanQuery = false
	ballast.CanTouch = false
	ballast.CastShadow = false
	ballast.CollisionGroup = CORPSE_GROUP
	ballast.CustomPhysicalProperties = PhysicalProperties.new(BALLAST_DENSITY, 0.9, 0, 1, 1)
	ballast.Anchored = false
	ballast.Parent = corpse

	local ballastWeld = Instance.new("WeldConstraint")
	ballastWeld.Part0 = root
	ballastWeld.Part1 = ballast
	ballastWeld.Parent = root

	-- Лёгкий кувырок при падении. Толкают тушу видимые тела жуков и машина Аркады —
	-- все на этом же клиенте, поэтому симуляция одна.
	root.AssemblyAngularVelocity = Vector3.new(0, (math.random() - 0.5) * 2 * TUMBLE, 0)
	if hit and hit.carry then
		root.AssemblyLinearVelocity += hit.carry
	end

	-- Добивающий удар толкает и саму тушу — тем сильнее, чем больше доля урона.
	if from and fraction > 0 then
		local away = bodyCenter - from
		away = Vector3.new(away.X, 0, away.Z)
		if away.Magnitude > 1e-3 then
			root.AssemblyLinearVelocity += (away.Unit + Vector3.yAxis * 0.3).Unit
				* PhysicsFX.hit.speed * math.min(fraction, 1.5)
		end
	end

	if charred then
		local plan = PhysicsFX.char
		local smoke = Instance.new("ParticleEmitter")
		smoke.Name = "CharSmoke"
		smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
		smoke.Color = ColorSequence.new(Color3.fromRGB(70, 66, 62), Color3.fromRGB(150, 146, 140))
		smoke.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.55),
			NumberSequenceKeypoint.new(1, 1),
		})
		smoke.Size = NumberSequence.new(0.5 * scale, 2 * scale)
		smoke.Lifetime = NumberRange.new(1.2, 2)
		smoke.Speed = NumberRange.new(1.5, 3.5)
		smoke.SpreadAngle = Vector2.new(20, 20)
		smoke.Acceleration = Vector3.new(0, 1.5, 0)
		smoke.Rate = plan.smokeRate
		smoke.EmissionDirection = Enum.NormalId.Top
		smoke.Parent = hull or root
		task.delay(plan.smokeTime, function()
			smoke.Enabled = false
		end)
	end

	-- Досадка на брюхо — общий цикл перед Corpses.Splat, для всех трупов сразу.

	CollectionService:AddTag(corpse, Impulse.Tag)
	remember(corpses, corpse, MAX_CORPSES)
	if id then
		byId[id] = corpse
	end
	return corpse
end

-- Пеликан съел труп (решает сервер): туша растворяется.
function Corpses.Eat(id)
	local corpse = byId[id]
	byId[id] = nil
	if not corpse then
		return
	end
	local index = table.find(corpses, corpse)
	if index then
		table.remove(corpses, index)
	end
	dissolve(corpse)
end

-- Досадка на брюхо. Коробка Hull устойчива на любой грани, и убитый на стене (носом
-- вверх или вниз ровно на 90°) так и оставался стоять торчком — замерено стендом. Балласта
-- для идеального равновесия мало: замершую не на брюхе тушу доворачиваем верхом к небу.
--
-- Один цикл на все трупы и без срока, а не «4 секунды после смерти» у каждого: тушу
-- сбивает на бок и позже — жук или машина Аркады, и лежать бы ей так до конца, с лапами
-- на 2.5–3 studs сквозь пол (Hull считан по туловищу, лапы в него не входят) — замерено в Аркаде.
-- Замершие на брюхе туши стоят два чтения свойства раз в check секунд.
--
-- Сначала — толчок вращением. Но у крупной туши (жуки Аркады, масса ~230) Hull почти
-- квадратный в сечении (4.8 × 5.7), на боку он устойчив, и толчок лишь покачивает его —
-- замерено. Если за flipAfter проверок подряд туша так и не легла, её плавно
-- перекатывают на брюхо вручную (анкор на flipTime) и отпускают — дальше её укладывает физика.
local stuckChecks = setmetatable({}, { __mode = "k" }) -- [corpse] = проверок подряд не на брюхе

local function flipUpright(corpse, root)
	local plan = PhysicsFX.settle
	local from = root.CFrame
	-- Куда смотреть после переворота: куда смотрел нос лежащей туши (в горизонтали).
	local flat = from.LookVector * Vector3.new(1, 0, 1)
	if flat.Magnitude < 0.1 then
		flat = from.UpVector * Vector3.new(1, 0, 1)
	end
	if flat.Magnitude < 0.1 then
		flat = Vector3.zAxis
	end
	local _, size = corpse:GetBoundingBox()
	local lifted = from.Position + Vector3.yAxis * math.max(size.X, size.Y, size.Z) * plan.flipLift
	local to = CFrame.lookAt(lifted, lifted + flat.Unit)

	root.Anchored = true
	local started = os.clock()
	while root.Parent do
		local t = math.min((os.clock() - started) / plan.flipTime, 1)
		root.CFrame = from:Lerp(to, t * t * (3 - 2 * t))
		if t >= 1 then
			break
		end
		RunService.Heartbeat:Wait()
	end
	if root.Parent then
		root.Anchored = false
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
		giveOwner(root)
	end
end

task.spawn(function()
	local plan = PhysicsFX.settle
	while true do
		task.wait(plan.check)
		for _, corpse in corpses do
			local root = corpse.Parent and corpse.PrimaryPart
			if root and not root.Anchored then
				local up = root.CFrame.UpVector
				if up.Y < plan.upright and root.AssemblyLinearVelocity.Magnitude < plan.still then
					local count = (stuckChecks[corpse] or 0) + 1
					if count >= plan.flipAfter then
						stuckChecks[corpse] = nil
						task.spawn(flipUpright, corpse, root)
					else
						stuckChecks[corpse] = count
						local axis = up:Cross(Vector3.yAxis)
						if axis.Magnitude < 1e-3 then
							axis = root.CFrame.LookVector
						end
						root.AssemblyAngularVelocity = axis.Unit * plan.spin
						root.AssemblyLinearVelocity += Vector3.yAxis * plan.spin * 0.3
					end
				else
					stuckChecks[corpse] = nil
				end
			end
		end
	end
end)

-- Пятно крови на полу. size — диаметр основного пятна в studs; drops — сколько вокруг
-- него брызг. Капля всегда ложится на пол арены, а не на ту высоту, где шла кровь:
-- следы боя нужны на карте, а не в воздухе над ней.
--
-- Плоский цилиндр, а не декаль с картинкой: текстура потребовала бы залитого
-- ассета, а форма пятна собирается из нескольких кругов разного размера не хуже.
-- floorY переопределяет высоту пола для вызововшего (по умолчанию Arena.floorY) —
-- нужен тем, чьё поле живёт не на арене (например, Аркада).
function Corpses.Splat(position, size, drops, floorY)
	local folder = container("Blood")
	local y = (floorY or Arena.floorY) + BLOOD_LIFT

	local function drop(at, diameter)
		local stain = Instance.new("Part")
		stain.Name = "Blood"
		stain.Shape = Enum.PartType.Cylinder
		-- Цилиндр в Roblox вытянут вдоль своей X, поэтому толщина — это X, а поворот
		-- на 90° по Z кладёт его плашмя. Овал вместо круга (Y и Z разные) — чтобы
		-- пятна не читались одинаковыми штампами.
		stain.Size = Vector3.new(BLOOD_THICKNESS, diameter, diameter * (0.75 + math.random() * 0.5))
		stain.CFrame = CFrame.new(at.X, y, at.Z)
			* CFrame.Angles(0, math.random() * math.pi * 2, 0)
			* CFrame.Angles(0, 0, math.rad(90))
		stain.Anchored = true
		stain.CanCollide = false
		stain.CanQuery = false
		stain.CanTouch = false
		stain.CastShadow = false
		stain.Material = Enum.Material.SmoothPlastic
		-- Не вплотную: глухое пятно на светлом полу читается как зелёная наклейка,
		-- а не как след — замечено на плейтесте.
		stain.Transparency = 0.22
		local shade = (math.random() - 0.5) * 2 * BLOOD_SPREAD / 255
		stain.Color = Color3.new(
			math.clamp(BLOOD_COLOR.R + shade, 0, 1),
			math.clamp(BLOOD_COLOR.G + shade, 0, 1),
			math.clamp(BLOOD_COLOR.B + shade, 0, 1)
		)
		stain.Parent = folder
		remember(stains, stain, MAX_STAINS)
	end

	drop(position, size)

	for _ = 1, drops or 0 do
		local angle = math.random() * math.pi * 2
		local distance = size * (0.5 + math.random())
		drop(position + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance),
			size * (0.25 + math.random() * 0.3))
	end
end

-- Гора поглощает труп (подтверждённое решение автора): выросшая преграда забирает
-- останки в своём следу, а не вырастает сквозь них. Кровь остаётся: она на полу, а
-- гора стоит поверх него.
function Corpses.Absorb(position, radius)
	for index = #corpses, 1, -1 do
		local corpse = corpses[index]
		if not corpse.Parent then
			table.remove(corpses, index)
		else
			local delta = corpse:GetPivot().Position - position
			if math.abs(delta.X) <= radius and math.abs(delta.Z) <= radius then
				table.remove(corpses, index)
				dissolve(corpse)
			end
		end
	end
end

-- Забег кончился — поле чистое. Сносится сразу, без растворения: арена разбирается
-- целиком, и таящие останки прошлого забега в новом — мусор, а не история карты.
function Corpses.Clear()
	for _, corpse in corpses do
		if corpse.Parent then
			corpse:Destroy()
		end
	end
	for _, stain in stains do
		if stain.Parent then
			stain:Destroy()
		end
	end
	for _, piece in pieces do
		if piece.Parent then
			piece:Destroy()
		end
	end
	table.clear(corpses)
	table.clear(stains)
	table.clear(pieces)
	table.clear(byId)
end

return Corpses
