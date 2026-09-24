-- HP-полоска над постройками — и над турелями, и над стенами, и над лабораторным
-- столом (см. низ файла). Чисто клиентская
-- визуализация: читает атрибуты HP/MaxHP, которые сервер ставит на модель и которые
-- реплицируются сами — отдельный RemoteEvent для этого не нужен.
--
-- Полоска показывается только у повреждённой постройки. У целой её нет намеренно:
-- лабиринт из полусотни стен с полной полоской над каждой перестаёт читаться, а «цела» —
-- это и так состояние по умолчанию. Понадобится показывать всегда — убрать условие у gui.Enabled.
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local towersFolder = Workspace:WaitForChild("Towers")
local Towers = require(ReplicatedStorage:WaitForChild("Towers"))
-- Доворот башни считается той же формулой, что и на сервере (задача #70).
local Aiming = require(ReplicatedStorage:WaitForChild("Aiming"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local ShotFiredRemote = Remotes:WaitForChild("ShotFired") -- отдача турели: см. recoilFrame ниже

-- Вращающиеся детали турелей (задача #53): лопасти Испарителя, сверло Бура, головка
-- Центрифуги с форсунками. Атрибут Spin на детали — сколько градусов в секунду; ставит его
-- сервер при сборке модели (см. TowerBuilder), а крутит клиент: деталь анкорнута, и гонять её
-- CFrame с сервера значило бы реплицировать каждый кадр каждой турели ради одной картинки.
--
-- Вращение идёт вокруг вертикальной оси МОДЕЛИ, а не вокруг центра самой детали: форсунки
-- Центрифуги смещены от оси и должны ходить по кругу, а не крутиться на месте.
--
-- Угол считается от часов, а не накапливается по деталям: тогда деталь, приехавшая клиенту
-- позже остальных, встаёт в ту же фазу, а не отстаёт от них навсегда.
local spinning = {}
local spinConnection = nil

local function spinStep()
	local now = os.clock()
	for index = #spinning, 1, -1 do
		local entry = spinning[index]
		if entry.part.Parent then
			entry.part.CFrame = entry.pivot * CFrame.Angles(0, (now * entry.speed) % (2 * math.pi), 0) * entry.origin
		else
			table.remove(spinning, index) -- постройку снесли
		end
	end

	-- На арене нет ни одной вращающейся турели — цикл не крутится вхолостую
	-- (тот же приём, что у Projectile на сервере).
	if #spinning == 0 and spinConnection then
		spinConnection:Disconnect()
		spinConnection = nil
	end
end

local function addSpinner(anchor, part)
	local speed = part:IsA("BasePart") and part:GetAttribute("Spin")
	if not speed then
		return
	end

	-- Пивот берётся с уже подтверждённого anchor (Root/RootPart), а не Model:GetPivot():
	-- при Workspace.StreamingEnabled=true PrimaryPart — отдельное свойство модели, которое
	-- может реплицироваться позже, чем сам Root уже появился ребёнком. GetPivot() в этом
	-- окне отдавал вращение вокруг неверной точки и запоминал её однократно — то самое
	-- «то крутится, то нет» из задачи #71, только для лопастей/сверла/форсунок, а не
	-- для ствола.
	local pivot = anchor.CFrame
	table.insert(spinning, {
		part = part,
		pivot = pivot,
		origin = pivot:Inverse() * part.CFrame,
		speed = math.rad(speed),
	})

	if not spinConnection then
		spinConnection = RunService.RenderStepped:Connect(spinStep)
	end
end

-- Люк Станции FPV-дронов (изменение 3.1 вики). Сервер решает только «есть ли цель
-- в радиусе» и ставит на модель атрибут HatchOpen (см. TowerBuilder.fireMortar), а саму
-- створку ведёт клиент по своим часам — тот же довод, что у Spin выше и у наведения ниже.
--
-- Угол и ось не выдуманы: крышка откидывается на штыре петли (HatchHingePin) на 100° —
-- ровно так, как в авторской анимации из Blender (KeyframeSequence в ServerStorage.RBX_ANIMSAVES:
-- 0 → 100° за 1.62 сек). Самой анимацией она не играется: детали шаблона анкорнуты и Motor6D
-- в нём ни одного (как и у меша Колбы), а CFrame считается тем же способом, что и отдача.
local HATCH_ANGLE = math.rad(100)
-- Секунд на полный ход створки. У автора в Blender 1.62 — взято быстрее: люк открывается
-- на ту же цель, по которой станция уже стреляет, и полторы секунды «открываюсь» при темпе
-- выстрел в 2.5 секунды читались бы как задержка самой станции.
local HATCH_TIME = 0.9
local hatches = {}
local hatchConnection = nil

local function hatchStep(dt)
	for index = #hatches, 1, -1 do
		local entry = hatches[index]
		if entry.model.Parent then
			local target = entry.model:GetAttribute("HatchOpen") and 1 or 0
			if entry.progress ~= target then
				local step = dt / HATCH_TIME
				entry.progress = target > entry.progress
					and math.min(entry.progress + step, 1)
					or math.max(entry.progress - step, 0)

				-- Плавный старт и остановка: ровный ход тяжёлой гермокрышки читается как рывок.
				local eased = entry.progress * entry.progress * (3 - 2 * entry.progress)
				local turn = CFrame.new(entry.hinge)
					* CFrame.fromAxisAngle(entry.axis, HATCH_ANGLE * eased)
					* CFrame.new(-entry.hinge)
				for _, leaf in entry.leaves do
					leaf.part.CFrame = turn * leaf.closed
				end
			end
		else
			table.remove(hatches, index) -- станцию снесли
		end
	end

	-- На арене нет ни одной станции — цикл не крутится вхолостую, как и у вращения выше.
	if #hatches == 0 and hatchConnection then
		hatchConnection:Disconnect()
		hatchConnection = nil
	end
end

local function addHatch(building)
	local folder = building:FindFirstChild("Hatch")
	local pin = building:FindFirstChild("HatchHingePin", true)
	if not folder or not pin or #folder:GetChildren() == 0 then
		return false -- у остальных построек люка нет вовсе, и это не ошибка
	end

	-- Ось петли — самая длинная сторона штыря, а не вписанная в код ось: какая из локальных
	-- осей окажется длинной после очередного импорта, заранее не известно, а вот то, что штырь
	-- петли длинный вдоль своей оси — свойство самой детали.
	local size = pin.Size
	local axis = pin.CFrame.RightVector
	if size.Y > size.X and size.Y >= size.Z then
		axis = pin.CFrame.UpVector
	elseif size.Z > size.X and size.Z > size.Y then
		axis = pin.CFrame.LookVector
	end

	local entry = { model = building, hinge = pin.Position, axis = axis, progress = 0, leaves = {} }
	local function addLeaf(part)
		if part:IsA("BasePart") then
			table.insert(entry.leaves, { part = part, closed = part.CFrame })
		end
	end
	for _, part in folder:GetChildren() do
		addLeaf(part)
	end
	-- Модель приезжает клиенту по частям: отдельная деталь створки вполне может
	-- доехать позже самой станции — тогда она приедет закрытой и поедет со следующим ходом.
	folder.ChildAdded:Connect(addLeaf)

	table.insert(hatches, entry)
	if not hatchConnection then
		hatchConnection = RunService.RenderStepped:Connect(hatchStep)
	end
	return true
end

-- Антенна Станции FPV-дронов (задача #77): тарелка смотрит на ту цель, по которой
-- станция бьёт. Куда смотреть, решает сервер (атрибут AimAngle — тот же мировой угол
-- Aiming.AngleTo, что и у Колбы, см. TowerBuilder.fireDrone), здесь — только поворот в кадре:
-- тот же довод, что у створки люка и у Spin.
--
-- Крутится верхний узел на поворотном круге: сам круг (AddSensorRotor) и всё, что
-- на нём стоит. Плита, пьедестал, поручни и стойки остаются на месте — это основание.
-- Имена списком: своей папки у узла в шаблоне нет (в отличие от Hatch), а по «всё выше
-- такой-то высоты» пришлось бы гадать.
local ANTENNA_PIVOT = "AddSensorRotor" -- сам поворотный круг: через него и идёт ось
local ANTENNA_PARTS = {
	ANTENNA_PIVOT, "AddSensorMast", "AddSensorJoint", "AddSensorDish", "AddSensorFeed",
	"AddSensorTip", "AddSensorStrut0", "AddSensorStrut1", "AddSensorStrut2",
}
-- Тарелка ворочается медленнее ствола: это радар, а не пушка, и его ход ничего
-- не задерживает: станция стреляет независимо от того, довернулась ли антенна.
local ANTENNA_SPEED = 1.1 -- рад/сек
local ANTENNA_ACCEL = 2.2 -- рад/сек²
local TAU = 2 * math.pi
local antennas = {}
local antennaConnection = nil

local function antennaStep(dt)
	for index = #antennas, 1, -1 do
		local entry = antennas[index]
		if entry.model.Parent then
			-- Нет атрибута (станция ещё никого не видела или цели кончились) — держим
			-- текущий пеленг, а не отматываемся в ноль: то же правило, что у ствола Колбы.
			-- Из мирового угла вычитается собственный поворот станции: тарелка крутится
			-- ОТНОСИТЕЛЬНО модели, а повернуть станцию при стройке можно (задача #76).
			local published = entry.model:GetAttribute("AimAngle")
			local wanted = published and ((published - entry.restYaw) % TAU) or entry.angle

			-- Доехала и стоит — не переписываем девять CFrame каждый кадр ни за чем
			-- (тот же приём, что у створки с её progress ~= target).
			if entry.angle ~= wanted or entry.velocity ~= 0 then
				entry.angle, entry.velocity = Aiming.Step(entry.angle, entry.velocity, wanted, dt,
					ANTENNA_SPEED, ANTENNA_ACCEL)

				local turn = CFrame.new(entry.axis)
					* CFrame.Angles(0, entry.angle, 0)
					* CFrame.new(-entry.axis)
				for _, leaf in entry.parts do
					leaf.part.CFrame = turn * leaf.rest
				end
			end
		else
			table.remove(antennas, index) -- станцию снесли
		end
	end

	if #antennas == 0 and antennaConnection then
		antennaConnection:Disconnect()
		antennaConnection = nil
	end
end

local function addAntenna(building)
	local parts = {}
	for _, name in ANTENNA_PARTS do
		local part = building:FindFirstChild(name, true)
		if not (part and part:IsA("BasePart")) then
			-- Либо это не Станция (антенны нет вовсе, и это не ошибка), либо модель ещё
			-- не доехала целиком — попытку повторит watchFor. Берём все девять или ни одной:
			-- половина узла, крутящаяся без остальной, — хуже, чем неподвижная антенна.
			return false
		end
		table.insert(parts, { part = part, rest = part.CFrame })
	end

	if not building.PrimaryPart then
		return false -- без пивота не посчитать собственный поворот станции
	end

	-- Собственный угол модели в той же системе, что и Aiming.AngleTo: ноль — это -Z модели.
	local look = building:GetPivot().LookVector
	table.insert(antennas, {
		model = building,
		-- Вертикальная ось поворотного круга — берётся с самой детали, а не числом:
		-- станция может быть повёрнута и перемасштабирована.
		axis = building:FindFirstChild(ANTENNA_PIVOT, true).Position,
		restYaw = math.atan2(-look.X, -look.Z),
		angle = 0,
		velocity = 0,
		parts = parts,
	})

	if not antennaConnection then
		antennaConnection = RunService.RenderStepped:Connect(antennaStep)
	end
	return true
end

-- Наведение башни турелей (Колба): плавно поворачивает башню туда, куда велел сервер.
-- Сервер ставит на модель атрибут AimAngle — угол на ту точку, в которую он собрался
-- стрелять (см. TowerBuilder.publishAim), а сам поворот в кадре рисует клиент. До задачи #70
-- клиент искал ближайшего врага сам и вполне мог крутить ствол не на того, в кого уходит
-- выстрел: выбор цели был в двух местах сразу.
--
-- Серверный aimBarrel для Колбы по-прежнему не трогает CFrame ствола (geometry.clientTracked).
local tracking = {}
local trackConnection = nil

-- Жидкость внутри Колбы (Liquid в TurretHead импортированного меша, см.
-- TowerBuilder.buildTowerModelMesh): скрыта, пока турель пуста, и поднимается от дна, когда
-- элемент залит (TowerBuilder.PourElement). Крышка (FlaskCap) неподвижна — раньше она
-- ещё ездила вверх-вниз при заливке, но это только сбивало с толку (задача #66) — теперь
-- анимируется только жидкость. fillLevel идёт по той же схеме плавного шага за кадр,
-- что и currentAngle выше, только 0..1 вместо угла.
local FILL_SPEED = 3 -- 1/сек: полный подъём жидкости — треть секунды

-- Отдача Колбы (задача #69). Своей анимации у меша нет вовсе: все 70 деталей анкорнуты,
-- Motor6D в шаблоне ни одного, а CFrame каждой детали и так переписывает trackStep каждый
-- кадр под наведение. Поэтому выстрел — это ещё одно слагаемое в той же формуле кадра,
-- а не Animation/AnimationController поверх: два хозяина у одного CFrame подрались бы.
--
-- Что двигается: пушка на цапфах (всё под узлом Pivot_Pitch — ствол, катушки, казённик,
-- дуло) уезжает назад вдоль своей оси и задирает дуло. Что стоит: люлька (кольца Leg*/
-- ArmHydLower, они держат ствол и по смыслу неподвижны), колба с жидкостью, стойки,
-- поворотный круг и нога. Ствол буквально проезжает сквозь кольца люльки — так и должно
-- выглядеть орудие на откате.
local RECOIL_BACK = 0.8 -- studs назад на полном ходу отдачи (ствол ~14 studs длиной)
local RECOIL_PITCH = math.rad(3) -- насколько задирается дуло на том же ходу
local RECOIL_TIME = 0.35 -- сек на весь цикл: темп Колбы — выстрел в секунду, запас есть
local RECOIL_PUNCH = 0.18 -- доля времени на рывок назад, остальное — возврат

-- Цапфы: точка, вокруг которой пушка задирается. Локальные координаты от пивота турели —
-- центр колец люльки. X не нужен: ось вращения идёт вдоль X целиком.
--
-- Числа берутся из Towers.Ballista.gun, а не вписаны здесь (задача #77): по ним же
-- сервер считает точку пуска снаряда (TowerBuilder.meshMuzzle). Две копии одних и тех же
-- цапф разошлись бы при первой же правке, и вспышка снова уехала бы от снаряда.
local GUN = Towers.Ballista.gun
local TRUNNION = CFrame.new(GUN.trunnion)
local TRUNNION_INV = TRUNNION:Inverse()

-- Вертикальная наводка (задача #71). Сервер шлёт атрибут AimPitch — абсолютный угол
-- места на точку прицела от горизонтали; качается на цапфах вся пушка целиком (узел
-- Pivot_Pitch — он ровно для этого в меше и назван), вместе с люлькой: люлька и есть то,
-- что качается на цапфах. Отдача поверх этого двигает только сам ствол, сквозь люльку.
--
-- Ствол у меша от рождения смотрит вниз (замерено по MiniBarrelC и BreechNew), а AimPitch
-- считается от горизонтали — поэтому прикладывается разница, а не сам угол: иначе ствол
-- целился бы на эти же градусы ниже точки прицела. Здесь и пределы хода — из той же
-- таблицы Towers.Ballista.gun, что и цапфы выше.
local REST_PITCH = math.rad(GUN.restPitch)
local PITCH_MIN, PITCH_MAX = math.rad(GUN.pitchMin), math.rad(GUN.pitchMax)

-- Детали люльки: они держат ствол и с ним назад не едут. Имена — узлы верхнего уровня
-- под Pivot_Pitch (см. ServerStorage.ColbaTurretTemplate). Ошибиться тут не страшно:
-- граница косметическая, лишний узел просто поедет вместе со стволом.
local CRADLE_NODES = {
	ArmHydLower = true,
	LegBottomRib = true,
	LegLeftRib = true,
	LegRightRib = true,
	LegRightRib_Cap = true,
	LegTopRib = true,
}

-- Разряд по катушкам: шесть катушек на стволе вспыхивают Neon по очереди от казённика
-- к дулу — модель нарисована катушечной пушкой, и выстрел должен читаться как разряд,
-- прокатившийся по стволу. Цвет не трогается: катушки уже покрашены сервером в цвет
-- залитого элемента (или в нейтральный белый у пустой турели), Neon только зажигает их.
local COIL_COUNT = 6
local COIL_FLASH = 0.16 -- сек: сколько горит одна катушка
local COIL_STEP = 0.025 -- сек: задержка между соседними катушками

-- Форма отдачи: короткий рывок назад и плавный возврат. Перелёта вперёд нет намеренно —
-- пружина, выбрасывающая ствол дальше исходного, читалась бы как удар ПО башне, а не как
-- её выстрел.
local function recoilCurve(t)
	if t < RECOIL_PUNCH then
		local k = t / RECOIL_PUNCH
		return 1 - (1 - k) * (1 - k)
	end
	local k = (t - RECOIL_PUNCH) / (1 - RECOIL_PUNCH)
	return (1 - k) * (1 - k)
end

-- Смещение пушки на этот кадр или nil, если отдачи сейчас нет вовсе. nil, а не единичный
-- CFrame: у неотстрелявшейся башни лишнего умножения на каждую деталь каждый кадр быть
-- не должно, деталей у меша 70.
local function recoilFrame(elapsed)
	if elapsed < 0 or elapsed >= RECOIL_TIME then
		return nil
	end
	local amount = recoilCurve(elapsed / RECOIL_TIME)
	return TRUNNION * CFrame.Angles(RECOIL_PITCH * amount, 0, 0) * TRUNNION_INV
		* CFrame.new(0, 0, RECOIL_BACK * amount)
end

-- Вспышка одной катушки. Материал переключается только на смене состояния, а не каждый
-- кадр: присваивание в цикле по всем деталям всех турелей — это уже заметная работа.
local function pulseStep(partInfo, elapsed)
	if not partInfo.pulseDelay then
		return
	end

	local t = elapsed - partInfo.pulseDelay
	local lit = t >= 0 and t <= COIL_FLASH
	if lit ~= partInfo.lit then
		partInfo.lit = lit
		partInfo.part.Material = lit and Enum.Material.Neon or partInfo.material
	end
end

local function trackStep(dt)
	local now = os.clock()
	for index = #tracking, 1, -1 do
		local entry = tracking[index]
		if not entry.model.Parent then
			table.remove(tracking, index)
		else
			-- Только ПОЛОЖЕНИЕ пивота, без его собственного поворота. AimAngle с сервера — угол
			-- МИРОВОЙ (Aiming.AngleTo), а собственный поворот постройки (его выбирает игрок при
			-- стройке, см. TowerInteraction) уже сидит в origin каждой детали. Умножай мы на полный
			-- пивот, поворот считался бы дважды, и повёрнутая Колба целилась бы мимо на этот же угол.
			local pivot = CFrame.new(entry.model:GetPivot().Position)

			-- Куда смотреть, решает сервер. Нет атрибута (турель ещё никого не выбрала,
			-- или цели кончились) — держим текущий угол, а не отматываемся в ноль: орудие,
			-- каждый раз возвращающееся в исходное между целями, только зря крутится.
			local targetAngle = entry.model:GetAttribute("AimAngle") or entry.currentAngle

			-- Разгон и торможение — той же формулой Aiming, что и на сервере: разъедься они,
			-- ствол смотрел бы в одну сторону, а выстрел уходил бы в другую.
			entry.currentAngle, entry.angularVelocity = Aiming.Step(entry.currentAngle,
				entry.angularVelocity, targetAngle, dt, entry.turnSpeed, entry.turnAccel)

			-- Вертикаль едет точно так же и тем же темпом, но своим углом: горизонтальный
			-- доворот и подъём ствола — две независимые оси, и ждать одна другую им незачем.
			local publishedPitch = entry.model:GetAttribute("AimPitch")
			local targetPitch = publishedPitch
				and math.clamp(publishedPitch - REST_PITCH, PITCH_MIN, PITCH_MAX)
				or entry.currentPitch
			entry.currentPitch, entry.pitchVelocity = Aiming.Step(entry.currentPitch,
				entry.pitchVelocity, targetPitch, dt, entry.turnSpeed, entry.turnAccel)

			-- Уровень жидкости в Колбе плавно едет к пустому/полному по текущему Element:
			-- атрибут меняет сервер (TowerBuilder.PourElement), сюда он приходит репликацией.
			local targetFillLevel = entry.model:GetAttribute("Element") == nil and 0 or 1
			local fillStep = FILL_SPEED * dt
			if entry.fillLevel < targetFillLevel then
				entry.fillLevel = math.min(targetFillLevel, entry.fillLevel + fillStep)
			elseif entry.fillLevel > targetFillLevel then
				entry.fillLevel = math.max(targetFillLevel, entry.fillLevel - fillStep)
			end

			-- Поворот всех деталей башни вокруг пивота турели; жидкость сверх этого ещё растёт
			-- от дна Колбы вверх по fillLevel (масштаб Size.Y вместо сдвига CFrame), а пушка —
			-- отъезжает назад по отдаче (partInfo.recoils, задача #69).
			local aimed = pivot * CFrame.Angles(0, entry.currentAngle, 0)
			-- На цапфах качается вся пушка (Pivot_Pitch), отдача поверх неё двигает только ствол.
			-- Оба поворота идут вокруг одной точки и поэтому складываются как есть.
			local pitched = aimed * TRUNNION * CFrame.Angles(entry.currentPitch, 0, 0) * TRUNNION_INV
			local elapsed = now - entry.shotClock
			local recoil = recoilFrame(elapsed)
			local kicked = recoil and (pitched * recoil) or pitched

			for _, partInfo in entry.parts do
				if partInfo.part.Parent then
					local frame = aimed
					if partInfo.recoils then
						frame = kicked
					elseif partInfo.inGun then
						frame = pitched
					end
					if partInfo.isLiquid then
						local height = math.max(partInfo.fullSize.Y * entry.fillLevel, 0.02)
						partInfo.part.Size = Vector3.new(partInfo.fullSize.X, height, partInfo.fullSize.Z)
						partInfo.part.CFrame = frame * partInfo.origin * CFrame.new(0, -(partInfo.fullSize.Y - height) / 2, 0)
					else
						partInfo.part.CFrame = frame * partInfo.origin
					end
					pulseStep(partInfo, elapsed)
				end
			end
		end
	end

	if #tracking == 0 and trackConnection then
		trackConnection:Disconnect()
		trackConnection = nil
	end
end

-- Турели, у которых трекер уже заведён. Попытка завести его делается не один раз
-- (см. watchFor), и без этого набора одна и та же башня попала бы в tracking дважды
-- и каждый кадр считалась бы два раза. Ключи слабые: снесённая постройка уходит из набора
-- сама, иначе за забег тут накопились бы все построенные когда-либо турели.
local tracked = setmetatable({}, { __mode = "k" })

-- Возвращает true, если трекер заведён (или был заведён раньше), false — если модель
-- ещё не доехала целиком и попытку надо повторить.
local function addTracker(building)
	if tracked[building] then
		return true
	end

	-- Пивот берётся из PrimaryPart. Пока тот не доехал, GetPivot() отдаёт центр габаритов
	-- недособранной модели, и origin у всех деталей посчитался бы от чужой точки —
	-- башню собрало бы со смещением от первого же кадра.
	if not building.PrimaryPart then
		return false
	end

	local headFolder = building:FindFirstChild("TurretHead", true)
	if not headFolder then
		return false
	end

	local towerType = building:GetAttribute("Type")
	local towerData = Towers[towerType]

	-- Пивот берётся ПОЛНЫЙ, с поворотом постройки: origin детали — это её место
	-- в СОБСТВЕННОЙ системе координат башни, без того, куда её повернули при стройке.
	-- Наведение этот поворот ЗАМЕНЯЕТ, а не дополняет (угол с сервера мировой, см. trackStep).
	local pivot = building:GetPivot()
	local parts = {}

	-- Узел самой пушки в меше Колбы. У остальных турелей его нет вовсе — тогда отдачи
	-- просто не будет, а наведение работает как работало.
	local gun = headFolder:FindFirstChild("Pivot_Pitch", true)

	-- Едет ли деталь назад вместе со стволом. Решается по узлу верхнего уровня под Pivot_Pitch,
	-- а не по имени самой детали: имена мешей после импорта идут с хвостами вроде "_Mesh.003",
	-- а имена узлов чистые и совпадают с тем, что видно в Explorer.
	local function recoilsWithGun(part)
		if not gun or not part:IsDescendantOf(gun) then
			return false
		end
		local node = part
		while node.Parent and node.Parent ~= gun do
			node = node.Parent
		end
		return not CRADLE_NODES[node.Name]
	end

	local function addPart(part)
		if part:IsA("BasePart") then
			-- Катушки горят по очереди от казённика (Coil6) к дулу (Coil1), жидкость в колбе —
			-- первой: заряд идёт из колбы в ствол, а не наоборот.
			local coil = tonumber(string.match(part.Name, "^Coil(%d+)$"))
			local isLiquid = part.Name == "Liquid"
			local pulseDelay = nil
			if coil then
				pulseDelay = (COIL_COUNT - coil) * COIL_STEP
			elseif isLiquid then
				pulseDelay = 0
			end

			table.insert(parts, {
				part = part,
				origin = pivot:Inverse() * part.CFrame,
				isLiquid = isLiquid,
				fullSize = part.Size,
				-- Качается на цапфах всё, что под Pivot_Pitch, включая люльку; назад по отдаче
				-- едет только сам ствол (задача #71).
				inGun = gun ~= nil and part:IsDescendantOf(gun),
				recoils = recoilsWithGun(part),
				pulseDelay = pulseDelay,
				material = part.Material, -- куда вернуть деталь после вспышки
				lit = false,
			})
		end
	end

	-- Глубокий поиск, а не только прямые дети: в меше из Workspace.ColbaTower (задача #63)
	-- TurretHead — это вложенный риг (FlaskCap_Node/Pivot_Pitch/...), а не плоская папка
	-- с мешами напрямую, как было в прежнем шаблоне.
	for _, part in headFolder:GetDescendants() do
		addPart(part)
	end
	headFolder.DescendantAdded:Connect(addPart)

	table.insert(tracking, {
		model = building,
		parts = parts,
		-- Скорость доворота — из таблицы башни, а не из константы здесь: по ним же
		-- сервер решает, успеет ли он навестись на цель.
		turnSpeed = towerData and towerData.turnSpeed,
		turnAccel = towerData and towerData.turnAccel,
		-- Если сервер уже куда-то целится (модель доехала к клиенту позже первого
		-- выстрела), башня сразу стоит где надо, а не докручивается туда на глазах.
		currentAngle = building:GetAttribute("AimAngle") or 0,
		angularVelocity = 0,
		currentPitch = 0,
		pitchVelocity = 0,
		-- Стартует без анимации «заливки»: если элемент уже залит (стартовая турель,
		-- см. TowerBootstrap.PourElement), жидкость обязана быть полной с первого кадра.
		fillLevel = building:GetAttribute("Element") == nil and 0 or 1,
		-- Выстрела ещё не было: любое elapsed отсюда заведомо больше RECOIL_TIME.
		shotClock = -math.huge,
	})

	if not trackConnection then
		trackConnection = RunService.RenderStepped:Connect(trackStep)
	end

	tracked[building] = true
	return true
end

-- Модель приезжает клиенту ПО ЧАСТЯМ, и порядок частей ничем не гарантирован: в один заход
-- PrimaryPart и TurretHead уже на месте, в другой — ещё нет. Прежний код пробовал ровно
-- один раз, на ChildAdded, и при неудачном порядке турель молча оставалась без наведения
-- до конца забега — причём у каждого игрока своя лотерея: у одного крутится одна башня,
-- у второго другая (задача #71). Поэтому попытка повторяется, пока не выйдет или пока не
-- станет ясно, что этого узла у постройки нет вовсе (башни — у Стены, люка и антенны —
-- у всех, кроме Станции).
--
-- Опрос раз в десятую секунды, а не подписка на DescendantAdded: ждать приходится две
-- разные вещи сразу (деталь и СВОЙСТВО PrimaryPart), и событие на второе не придёт.
--
-- Одна функция на все три узла (башня, створка, антенна): правило ожидания одно и то же,
-- и три его копии разошлись бы на четвёртом.
-- ===== Турель на риге (Инжектор) =====
--
-- Свой трекер, а не ветка в трекере Колбы выше: у Колбы пушка на цапфах с люлькой,
-- жидкость в колбе и разряд по катушкам, а тут — пушка целиком на поворотном круге,
-- откат ствола и шаг револьверного барабана. Общий трекер пришлось бы разветвлять
-- в полдесятка мест, а он и так пережил три задачи правок (#70, #71, #77).
--
-- Геометрия — из Towers[тип].rig, а не вписана здесь: по тем же числам сервер считает
-- точку пуска снаряда (TowerBuilder.aimRig). Две копии разошлись бы, и снаряд снова
-- вылетал бы мимо ствола — ровно та болезнь, что лечилась у Колбы в задаче #77.
--
-- Доворот плавный, той же формулой Aiming.Step и теми же числами из Towers[тип],
-- какими считает доворот сервер (задача #70): сервер присылает ЖЕЛАЕМЫЙ угол
-- и стреляет только когда ствол до него доехал, а сам путь рисуется здесь.
-- Разъедься формулы — ствол смотрел бы в одну сторону, а выстрел уходил бы в другую.
local RIG_RECOIL_TIME = 0.4 -- сек на весь цикл отката; темп Инжектора — выстрел в 5 сек, запас огромный
local RIG_RECOIL_PUNCH = 0.2 -- доля времени на рывок назад, остальное — возврат
local RIG_DRUM_TIME = 0.5 -- сек на проворот барабана на одну камору
-- Поршень в корме (rig.rammerNode): толкает иглу вперёд в камору и возвращается.
-- Ход вперёд дольше рывка отдачи: поршень давит, а не отскакивает.
local RIG_RAM_TIME = 0.45 -- сек на весь цикл «вперёд и обратно»
local RIG_RAM_PUNCH = 0.35 -- доля времени на ход вперёд

local rigs = {}
local rigConnection = nil
local rigTracked = setmetatable({}, { __mode = "k" })

-- Форма отката: короткий рывок назад и плавный возврат, без перелёта вперёд —
-- та же кривая и по той же причине, что у Колбы (recoilCurve выше): пружина,
-- выбрасывающая ствол дальше исходного, читалась бы как удар ПО турели.
local function rigRecoilAmount(elapsed)
	if elapsed < 0 or elapsed >= RIG_RECOIL_TIME then
		return nil -- отдачи сейчас нет вовсе: nil, а не ноль — чтобы не умножать ни за чем
	end
	local t = elapsed / RIG_RECOIL_TIME
	if t < RIG_RECOIL_PUNCH then
		local k = t / RIG_RECOIL_PUNCH
		return 1 - (1 - k) * (1 - k)
	end
	local k = (t - RIG_RECOIL_PUNCH) / (1 - RIG_RECOIL_PUNCH)
	return (1 - k) * (1 - k)
end

-- Ход поршня: та же форма, что у отдачи, только медленнее на выходе и в другую
-- сторону: поршень досылает иглу в камору, а не отпрыгивает от выстрела.
local function rigRamAmount(elapsed)
	if elapsed < 0 or elapsed >= RIG_RAM_TIME then
		return nil
	end
	local t = elapsed / RIG_RAM_TIME
	if t < RIG_RAM_PUNCH then
		local k = t / RIG_RAM_PUNCH
		return 1 - (1 - k) * (1 - k)
	end
	local k = (t - RIG_RAM_PUNCH) / (1 - RIG_RAM_PUNCH)
	return (1 - k) * (1 - k)
end

local function rigStep(dt)
	local now = os.clock()
	for index = #rigs, 1, -1 do
		local entry = rigs[index]
		if not entry.model.Parent then
			entry.partAdded:Disconnect()
			table.remove(rigs, index) -- турель снесли
		else
			local elapsed = now - entry.shotClock
			local recoil = rigRecoilAmount(elapsed)
			local ram = rigRamAmount(elapsed)
			local drumProgress = math.clamp(elapsed / RIG_DRUM_TIME, 0, 1)

			-- Куда смотреть, решает сервер (сектор уже учтён там, TowerBuilder.clampArc).
			-- Нет атрибута (турель ещё никого не видела) — держим фронт самой постройки,
			-- а не мировой ноль: повернуть её можно (задача #76), и сервер стартует оттуда же.
			local wantedYaw = entry.model:GetAttribute("AimAngle") or entry.restYaw
			local wantedPitch = entry.model:GetAttribute("AimPitch") or 0

			-- Разгон и торможение — той же формулой Aiming, что и на сервере.
			-- Горизонталь и вертикаль — две независимые оси, ждать одна другую им незачем.
			entry.angle, entry.angularVelocity = Aiming.Step(entry.angle, entry.angularVelocity,
				wantedYaw, dt, entry.turnSpeed, entry.turnAccel)
			entry.pitch, entry.pitchVelocity = Aiming.Step(entry.pitch, entry.pitchVelocity,
				wantedPitch, dt, entry.turnSpeed, entry.turnAccel)

			-- Доехала и стоит, выстрел отыгран — не переписываем сорок CFrame каждый кадр
			-- ни за чем (тот же приём, что у тарелки антенны выше).
			--
			-- Сравниваем через Aiming.Delta, а не прямым ~=: Aiming.Step возвращает угол
			-- в [0, 2pi), а с сервера приезжает обычный угол, вполне отрицательный —
			-- доехавшая турель при прямом сравнении вечно числилась бы едущей.
			local moving = entry.angularVelocity ~= 0 or entry.pitchVelocity ~= 0
				or math.abs(Aiming.Delta(entry.angle, wantedYaw)) > 1e-4
				or math.abs(Aiming.Delta(entry.pitch, wantedPitch)) > 1e-4
				or recoil ~= nil or ram ~= nil or drumProgress < 1
			if moving or not entry.posed then
				entry.posed = true

				-- Всё, что на поворотном круге (включая задний упор, на котором
				-- стоит пушка), крутится по горизонтали.
				local base = CFrame.new(entry.model:GetPivot().Position) * CFrame.Angles(0, entry.angle, 0)
				-- По вертикали качается только ствол, вокруг цапфы: корпус с барабаном
				-- и баллонами остаётся стоять на упоре, а ствол ходит сквозь него.
				local gun = base * entry.trunnion * CFrame.Angles(entry.pitch, 0, 0) * entry.trunnionInverse

				-- Откат: ствол едет назад вдоль своей оси поверх собственного наклона.
				-- Ствол смотрит в -Z модели, значит назад — это +Z в системе самой пушки.
				local kicked = recoil and (gun * CFrame.new(0, 0, entry.recoil * recoil)) or gun

				-- Барабан: шаг на одну камору за выстрел, вокруг своей оси (она же
				-- цапфа, идёт вдоль ствола). Считается от base, а не от gun: барабан в корпусе
				-- и вместе со стволом не качается. Угол накапливается: барабан крутится
				-- дальше от выстрела к выстрелу, а не отматывается обратно.
				local eased = drumProgress * drumProgress * (3 - 2 * drumProgress)
				local drumAngle = entry.drumFrom + (entry.drumTo - entry.drumFrom) * eased
				local spun = base * entry.trunnion * CFrame.Angles(0, 0, drumAngle) * entry.trunnionInverse

				-- Поршень: едет ВПЕРЁД, то есть в -Z модели — противоходом стволу,
				-- который в этот же момент уходит назад. От base, а не от gun: механизм
				-- в корме корпуса и со стволом не качается.
				local rammed = ram and (base * CFrame.new(0, 0, -entry.rammer * ram)) or base

				for _, info in entry.parts do
					if info.part.Parent then
						local frame = base
						if info.recoils then
							frame = kicked
						elseif info.pitches then
							frame = gun
						elseif info.rams then
							frame = rammed
						elseif info.drums then
							frame = spun
						end
						info.part.CFrame = frame * info.origin
					end
				end
			end
		end
	end

	if #rigs == 0 and rigConnection then
		rigConnection:Disconnect()
		rigConnection = nil
	end
end

local function addRigTracker(building)
	if rigTracked[building] then
		return true
	end

	local towerData = Towers[building:GetAttribute("Type") or ""]
	local rig = towerData and towerData.rig
	if not rig then
		-- У остальных построек рига нет вовсе, и это не ошибка — повторять попытку
		-- нечего. Атрибут Type ставится до того, как модель попадает в Towers
		-- (см. TowerBuilder.placeTower), поэтому отсутствие типа — тоже ответ.
		return true
	end

	-- Пивот берётся из PrimaryPart: пока тот не доехал, GetPivot() отдаёт центр габаритов
	-- недособранной модели, и вся пушка собралась бы со смещением от первого кадра.
	if not building.PrimaryPart then
		return false
	end

	local yawNode = building:FindFirstChild(rig.yawNode, true)
	if not yawNode then
		return false -- модель ещё не доехала целиком: попытку повторит watchFor
	end

	-- Пивот берётся ПОЛНЫЙ, с поворотом постройки: origin детали — это её место
	-- в СОБСТВЕННОЙ системе турели. Наведение этот поворот ЗАМЕНЯЕТ (угол с сервера
	-- мировой), поэтому в кадре умножаем на позицию пивота без его вращения —
	-- иначе поворот считался бы дважды.
	local pivot = building:GetPivot()
	local parts = {}
	local known = {}
	local entry

	-- Лежит ли деталь под узлом с этим именем — подъёмом по предкам до yawNode,
	-- а не заранее найденным узлом: узел (тот же MainBarrel) мог доехать позже круга,
	-- и найденный один раз nil навсегда оставил бы ствол без отката и наклона.
	-- Предок у детали есть всегда: ребёнок не приходит клиенту раньше родителя.
	local function under(part, name)
		if not name then
			return false
		end
		local node = part.Parent
		while node and node ~= yawNode do
			if node.Name == name then
				return true
			end
			node = node.Parent
		end
		return false
	end

	-- Модель доезжает по частям (см. watchFor выше): деталь, пришедшая после того, как
	-- появился yawNode, раньше в список не попадала и стояла на месте до конца забега —
	-- та самая редкая «половина Инжектора не анимируется». Поэтому, как у Колбы,
	-- слушается и DescendantAdded. known — чтобы деталь, выгруженная стримингом
	-- и приехавшая снова, не встала в список дважды.
	local function addPart(part)
		if not part:IsA("BasePart") or known[part] then
			return
		end
		known[part] = true
		table.insert(parts, {
			part = part,
			-- Сервер риг не двигает (крутит его только этот клиент), поэтому CFrame
			-- опоздавшей детали — всё та же поза покоя, и origin из неё верный.
			origin = pivot:Inverse() * part.CFrame,
			-- Порядок проверок в кадре: откат -> наклон -> барабан -> просто круг.
			-- Ствол попадает и в recoils, и в pitches — откат считается поверх наклона
			-- и его включает в себя.
			pitches = under(part, rig.pitchNode),
			recoils = under(part, rig.recoilNode),
			rams = under(part, rig.rammerNode),
			drums = under(part, rig.drumNode),
		})
		if entry then
			-- Стоящую турель rigStep не перерисовывает: без этого опоздавшая деталь
			-- осталась бы в позе покоя до следующего доворота или выстрела.
			entry.posed = false
		end
	end

	for _, part in yawNode:GetDescendants() do
		addPart(part)
	end

	local look = pivot.LookVector
	local trunnion = CFrame.new(rig.trunnion)
	entry = {
		model = building,
		parts = parts,
		trunnion = trunnion,
		trunnionInverse = trunnion:Inverse(),
		recoil = rig.recoil or 0,
		rammer = rig.rammer or 0,
		chamberStep = 2 * math.pi / (rig.chambers or 6),
		-- Собственный угол модели в той же системе, что и Aiming.AngleTo: ноль — это -Z.
		restYaw = math.atan2(-look.X, -look.Z),
		-- Скорость доворота — из таблицы башни, а не из константы здесь: по ним же
		-- сервер решает, довернулся ли ствол и можно ли уже стрелять.
		turnSpeed = towerData.turnSpeed,
		turnAccel = towerData.turnAccel,
		-- Если сервер уже куда-то целится (модель доехала к клиенту позже первого
		-- выстрела), ствол сразу стоит где надо, а не докручивается туда на глазах.
		angle = building:GetAttribute("AimAngle") or math.atan2(-look.X, -look.Z),
		angularVelocity = 0,
		pitch = building:GetAttribute("AimPitch") or 0,
		pitchVelocity = 0,
		drumFrom = 0,
		drumTo = 0,
		-- Выстрела ещё не было: любое elapsed отсюда заведомо больше всех сроков.
		shotClock = -math.huge,
		partAdded = yawNode.DescendantAdded:Connect(addPart),
	}
	table.insert(rigs, entry)

	if not rigConnection then
		rigConnection = RunService.RenderStepped:Connect(rigStep)
	end

	rigTracked[building] = true
	return true
end

local ATTACH_TIMEOUT = 15

local function watchFor(building, attach)
	if attach(building) then
		return
	end

	task.spawn(function()
		local deadline = os.clock() + ATTACH_TIMEOUT
		while building.Parent and os.clock() < deadline do
			task.wait(0.1)
			if attach(building) then
				return
			end
		end
	end)
end

-- Выстрел (задача #69): сервер шлёт третьим аргументом ShotFired саму турель — остальное
-- (когда началась отдача, где сейчас ствол) считает клиент по своим часам. Гонять CFrame
-- ствола с сервера значило бы реплицировать каждый кадр каждой турели ради одной картинки —
-- тот же довод, что у вращения Spin и у наведения выше.
local function onShotFired(_muzzlePosition, _color, tower)
	if not tower then
		return -- выстрел без указания башни: отдачу играть некому
	end

	for _, entry in tracking do
		if entry.model == tower then
			entry.shotClock = os.clock()
			return
		end
	end

	-- Турель на риге (Инжектор): та же точка отсчёта на откат, плюс шаг барабана
	-- на камору. Шаг считается от ТЕКУЩЕГО угла, а не от целевого: выстрел
	-- посреди недокрутившегося барабана не должен дёргать его вперёд рывком.
	for _, entry in rigs do
		if entry.model == tower then
			local elapsed = os.clock() - entry.shotClock
			local progress = math.clamp(elapsed / RIG_DRUM_TIME, 0, 1)
			local eased = progress * progress * (3 - 2 * progress)
			entry.drumFrom = entry.drumFrom + (entry.drumTo - entry.drumFrom) * eased
			entry.drumTo = entry.drumFrom + entry.chamberStep
			entry.shotClock = os.clock()
			return
		end
	end
end

ShotFiredRemote.OnClientEvent:Connect(onShotFired)

-- Якорь полоски HP — он же пивот постройки. У процедурных построек это Root, у меша Колбы —
-- RootPart. Прежний код ждал ровно имя "Root", которого у меша нет вовсе: стоило
-- PrimaryPart не доехать к первому кадру — и весь attachVisuals выходил через пять секунд
-- ни с чем (задача #71).
local function waitForAnchor(building)
	local deadline = os.clock() + ATTACH_TIMEOUT
	while building.Parent do
		local anchor = building.PrimaryPart
			or building:FindFirstChild("Root")
			or building:FindFirstChild("RootPart")
		if anchor then
			return anchor
		end
		if os.clock() > deadline then
			return nil
		end
		task.wait(0.1)
	end
	return nil
end

-- Полоска HP над моделью. Вынесена из attachVisuals отдельной функцией: такая же полоска
-- нужна лабораторному столу (см. низ файла), а он не постройка и лежит не в Towers:
-- всё остальное из attachVisuals (наведение, люк, антенна, вращение) ему ни к чему.
local function addHealthBar(model, anchor)
	local gui = Instance.new("BillboardGui")
	gui.Name = "HealthBar"
	gui.Size = UDim2.new(3, 0, 0.4, 0)
	gui.AlwaysOnTop = true
	gui.Adornee = anchor
	gui.Enabled = false
	gui.Parent = anchor

	local back = Instance.new("Frame")
	back.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
	back.BorderSizePixel = 0
	back.Size = UDim2.new(1, 0, 1, 0)
	back.Parent = gui

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BorderSizePixel = 0
	fill.Size = UDim2.new(1, 0, 1, 0)
	fill.BackgroundColor3 = Color3.fromRGB(80, 220, 80)
	fill.Parent = back

	local offsetApplied = false

	local function updateHealth()
		local hp = model:GetAttribute("HP") or 0
		local maxHp = model:GetAttribute("MaxHP") or hp
		local fraction = maxHp > 0 and math.clamp(hp / maxHp, 0, 1) or 0

		gui.Enabled = fraction < 1

		-- Высота считается из габаритов модели, а не задаётся числом: Колба и Стена
		-- разной высоты. Считаем в момент первого показа — к этому времени модель заведомо
		-- доехала целиком, а на ChildAdded в ней мог быть один корень и полоска села бы внутрь.
		if gui.Enabled and not offsetApplied then
			local boundsCFrame, boundsSize = model:GetBoundingBox()
			local top = boundsCFrame.Position.Y + boundsSize.Y / 2
			gui.StudsOffset = Vector3.new(0, top - model:GetPivot().Position.Y + 0.8, 0)
			offsetApplied = true
		end

		fill.Size = UDim2.new(fraction, 0, 1, 0)
		fill.BackgroundColor3 = Color3.fromRGB(220, 60, 60):Lerp(Color3.fromRGB(80, 220, 80), fraction)
	end

	updateHealth()
	model:GetAttributeChangedSignal("HP"):Connect(updateHealth)
	return updateHealth
end

local function attachVisuals(building)
	if not building:IsA("Model") then
		return
	end

	-- Наведение заводится ПЕРВЫМ и ни от чего больше не зависит. Раньше оно стояло после
	-- ожидания якоря, и любая заминка с якорем уносила вместе с полоской HP ещё и поворот
	-- башни.
	watchFor(building, addTracker)
	watchFor(building, addHatch)
	watchFor(building, addAntenna)
	watchFor(building, addRigTracker)

	local anchor = waitForAnchor(building)
	if not anchor or not building.Parent then
		return
	end

	-- Модель приезжает клиенту по частям, поэтому кроме разового обхода слушается и
	-- DescendantAdded: детали вполне могут доехать после самой модели. Заведён после
	-- waitForAnchor, а не до него: без готового anchor пивот считать не от чего.
	for _, part in building:GetDescendants() do
		addSpinner(anchor, part)
	end
	building.DescendantAdded:Connect(function(part)
		addSpinner(anchor, part)
	end)

	addHealthBar(building, anchor)
end

for _, building in towersFolder:GetChildren() do
	task.spawn(attachVisuals, building)
end
towersFolder.ChildAdded:Connect(function(building)
	task.spawn(attachVisuals, building)
end)

-- Лабораторный стол (design: alchemy_td_enemies.md, раздел «Лабораторный стол»): у него
-- есть прочность, и её надо видеть. Без полоски грызня стола читалась как бесконечная:
-- HP убывало правильно, но на экране ничего не менялось вплоть до отказа крафта.
--
-- Якорем берётся столешница, а не Root: Root — это невидимый кубик 0.2 в центре
-- стола, и полоска от него всё равно встанет по габаритам модели, но столешница надёжнее
-- доезжает клиенту — именно на неё уже вешается ProximityPrompt крафта.
-- Стол берётся из активной локации и заново — при её смене: старый стол уходит с клиента
-- вместе со своей полоской.
local ArenaGeometry = require(ReplicatedStorage:WaitForChild("Arena"))
local function watchCraftTable()
	local craftTable = ArenaGeometry.Location():WaitForChild("CraftTable", 30)
	if not craftTable then
		return
	end
	local anchor = craftTable:WaitForChild("Top", 10) or craftTable.PrimaryPart
	if anchor then
		addHealthBar(craftTable, anchor)
	end
end
task.spawn(watchCraftTable)
ArenaGeometry.OnChanged(function()
	task.spawn(watchCraftTable)
end)

-- Справочник и производитель элементов (вики, «Начальное помещение»): у них тоже есть
-- прочность (сервер ведёт её в LabStations), и её надо видеть так же, как у стола.
-- Якорь — та деталь, на которой висит подсказка взаимодействия.
local STATION_ANCHORS = {
	ReferenceBoard = "Screen",
	ElementProducer = "Panel",
}
local function watchStation(name, anchorName)
	local station = ArenaGeometry.Location():WaitForChild(name, 30)
	if not station then
		return
	end
	local anchor = station:WaitForChild(anchorName, 10) or station.PrimaryPart
	if anchor then
		addHealthBar(station, anchor)
	end
end
local function watchStations()
	for name, anchorName in STATION_ANCHORS do
		task.spawn(watchStation, name, anchorName)
	end
end
watchStations()
ArenaGeometry.OnChanged(watchStations)
