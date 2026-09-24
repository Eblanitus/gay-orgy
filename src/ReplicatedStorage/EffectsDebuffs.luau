-- Наложение эффектов на жука: зоны, метки, замедление, оглушение, ослепление, дебаффы, урон по времени, отбрасывание и притяжение
-- Вынесено из Effects.luau без изменений кода (задача #203): файл был слишком
-- велик, чтобы агент читал его целиком. deps — локальные основного файла, которые нужны
-- этому куску; возвращается то, что основной файл использует дальше.
return function(deps)
	local Effects = deps.Effects
	local marks = deps.marks
	local Arena = deps.Arena
	local Debris = deps.Debris
	local Elements = deps.Elements
	local ZONE_APPLY_INTERVAL = deps.ZONE_APPLY_INTERVAL
	local zones = deps.zones
	local kindMarks = deps.kindMarks
	local MARK_ATTRIBUTE = deps.MARK_ATTRIBUTE
	local catalysts = deps.catalysts
	local effects = deps.effects
	local regens = deps.regens
	local infections = deps.infections
	local slows = deps.slows
	local dryings = deps.dryings
	local stunCooldowns = deps.stunCooldowns
	local blinds = deps.blinds
	local growingSlows = deps.growingSlows
	local debuffs = deps.debuffs
	local counters = deps.counters
	local DamageDealtRemote = deps.DamageDealtRemote
	local pulls = deps.pulls
	local ramps = deps.ramps

	local function amplifier(target)
		local mark = marks[target]
		if not mark then
			return 1, 1
		end
		return mark.durationScale, mark.powerScale
	end

	-- Урон округляется до целого: HP цели — целое число, и дробный тик шёл бы в лог и в цифру
	-- над жуком мусором вида 4.5.
	local function scaled(amount, factor)
		return math.max(1, math.floor(amount * factor + 0.5))
	end

	-- Доля хода цели относительно незамедленного: 1 — полная скорость, 0 — под максимальным
	-- замедлением. Берётся из SlowPercent, а не из атрибута Velocity: остановленный грызней
	-- или запутанный жук на деле не «медленный» в этом смысле — Velocity в такие кадры падает
	-- до ноля искусственно, а здесь нужна именно скорость хода, которую отнимает Вода.
	local function speedRatio(target)
		return 1 - math.clamp(target:GetAttribute("SlowPercent") or 0, 0, 1)
	end

	-- Линейная интерполяция между .min (цель под максимальным замедлением) и .max (цель на полном
	-- ходу) по speedRatio. Общая для урона Землетрясения и Горы и замедления Гейзера — v2.2
	-- сажает все три на одну и ту же скорость цели, просто с разными числами по краям (см. документ:
	-- «Пара работает как Камень с Кирпичом: одна логика, разные следствия»).
	local function speedScaledValue(target, plan)
		return plan.min + (plan.max - plan.min) * speedRatio(target)
	end

	-- Радиус трупа для зоны Землетрясения — тот же принцип, что у хитбокса снаряда в Projectile
	-- (Size.X + Size.Z) / 4, но продублирован здесь: Effects требовать Projectile не может,
	-- тот уже требует Effects.
	local function corpseRadius(target)
		local part = target.PrimaryPart
		if not part then
			return 1.5
		end
		return (part.Size.X + part.Size.Z) / 4
	end

	-- Папка для видимых зон на арене — заводится на лету, как Workspace.Projectiles у
	-- Projectile: зона живёт секунды, хранить под неё пустой контейнер в плейсе незачем.
	local function zonesFolder()
		local folder = Workspace:FindFirstChild("Zones")
		if not folder then
			folder = Instance.new("Folder")
			folder.Name = "Zones"
			folder.Parent = Workspace
		end
		return folder
	end

	-- Видимый диск на месте зоны усиления — чисто декоративная деталь, без её игрок не видит, что
	-- зона вообще появилась — ZoneMultiplier работает чисто по геометрии и без картинки ничего не
	-- ломает. Короткий цилиндр, поставленный на ребро (тот же приём, что у круглой базы Колбы в
	-- TowerBuilder.buildTowerModel), читается как плоский светящийся диск на земле. Живёт ровно столько,
	-- сколько сама зона (Debris вместо отдельного task.delay — очистка переживёт даже рестарт
	-- забега, так как не зависит от живого цикла этого модуля).
	local function spawnZoneVisual(position, radius, duration, color)
		local disc = Instance.new("Part")
		disc.Name = "Zone"
		disc.Shape = Enum.PartType.Cylinder
		disc.Size = Vector3.new(0.2, radius * 2, radius * 2)
		disc.Anchored = true
		disc.CanCollide = false
		disc.CanQuery = false
		disc.CanTouch = false
		disc.Material = Enum.Material.Neon
		disc.Color = color
		disc.Transparency = 0.3
		disc.CFrame = CFrame.new(position.X, Arena.floorY + 0.15, position.Z) * CFrame.Angles(0, 0, math.rad(90))
		disc.Parent = zonesFolder()
		Debris:AddItem(disc, duration)
	end

	-- Заводит зону на карте по общему описанию (те же поля, что у killZone в Elements).
	-- Одна функция на всех, потому что источников зон теперь два: смерть цели
	-- (killZone) и пробой Смога (breakthrough.zone), а тик-цикл ниже их не различает.
	local function spawnZone(position, radius, plan, elementData)
		local spread = plan.spreadElement and Elements[plan.spreadElement] or nil
		assert(not plan.spreadElement or spread,
			("[Effects] зона %s ссылается на несуществующий элемент %s")
				:format(elementData.name, tostring(plan.spreadElement)))

		local now = os.clock()
		local zone = {
			position = position,
			radius = radius,
			born = now,
			expires = now + plan.duration,
			element = elementData,
			-- Зона Землетрясения (v2.2.1): своих чисел у неё нет, она раздаёт
			-- damageSpeedScale своего элемента любой турели, попавшей по цели внутри.
			speedPlan = elementData.damageSpeedScale,
			damagePerSecond = plan.damagePerSecond,
			growth = plan.growth,
			charges = plan.charges,
			dries = plan.dries,
			spread = spread,
			applied = {}, -- кому и когда зона в последний раз вешала свой эффект
		}

		-- Замедление внутри зоны (Ураган, Гидросфера) идёт тем же путём, что и обычное:
		-- зоне заводится одна синтетическая запись элемента, а не вторая ветка в applySlow.
		if plan.slowPercent then
			zone.slowElement = {
				name = elementData.name .. " (зона)",
				slowPercent = plan.slowPercent,
				slowDuration = ZONE_APPLY_INTERVAL * 2,
			}
		end

		table.insert(zones, zone)
		spawnZoneVisual(position, radius, plan.duration, elementData.color)
		return zone
	end

	-- Множитель урона от зоны Землетрясения для цели, стоящей в ней (v2.2.1). Зона не плоская
	-- надбавка: она распространяет правило «быстрая цель = больше урона» на любую турель,
	-- поэтому множитель считается той же speedScaledValue от скорости самой цели: медленный
	-- жук в зоне не получает ничего, резвый огребает по полной — даже от пустой колбы.
	--
	-- Сильнейшая из перекрывающихся зон, а не сумма — иначе три смерти подряд в одном углу
	-- превращали бы следующую турель в читерскую. Считает, а не чистит: устаревшие зоны
	-- убирает тик-цикл ниже.
	function Effects.ZoneMultiplier(target)
		local position = target:GetPivot().Position
		local now = os.clock()
		local best = 1
		for _, zone in zones do
			if zone.speedPlan and now < zone.expires and (position - zone.position).Magnitude <= zone.radius then
				best = math.max(best, speedScaledValue(target, zone.speedPlan))
			end
		end
		return best
	end

	-- Метка Пыли (amplifier). Накладывается однократно и держится до смерти цели: повторные
	-- попадания пылью ничего не дают, поэтому вторая пыльная турель рядом бесполезна,
	-- а любая другая — вдвое полезнее.
	local function applyMark(target, elementData)
		if marks[target] then
			return
		end

		marks[target] = elementData.amplifier
		target:SetAttribute("Amplified", true) -- визуальная метка для клиента (см. EnemyVisuals)
		print(("[Эффект] %s метит %s: длительность x%.1f, сила x%.1f до конца жизни цели")
			:format(elementData.name, target.Name, elementData.amplifier.durationScale,
				elementData.amplifier.powerScale))
	end

	-- Метки v4 (Ржавчина, Пепел, Грунт). В отличие от метки Пыли они не одноразовые:
	-- повторное попадание обновляет срок тем, у кого он есть (Грунт), а вечным оно ничего
	-- не меняет. Сама метка ничего не делает — её читают те, кому она адресована: AfterArmor
	-- (Ржавчина) и applyKillHeal (Пепел).
	local function applyKindMark(target, elementData)
		local plan = elementData.mark
		local durationScale = amplifier(target)

		kindMarks[target] = kindMarks[target] or {}
		kindMarks[target][plan.kind] = {
			plan = plan,
			expires = plan.duration and (os.clock() + plan.duration * durationScale) or nil,
		}
		target:SetAttribute(MARK_ATTRIBUTE[plan.kind], true)
		print(("[Эффект] %s кладёт метку «%s» на %s%s")
			:format(elementData.name, plan.kind, target.Name,
				plan.duration and (" на %.1f сек"):format(plan.duration * durationScale) or " до смерти"))
	end

	-- Смывка метки: Кислота смывает Ржавчину, любая Мокрость — Пепел. Два усилителя
	-- разных веток на одной цели не держатся — это и есть цена смешивания башен.
	local function washMark(target, kind)
		local byKind = kindMarks[target]
		if not byKind or not byKind[kind] then
			return
		end

		byKind[kind] = nil
		target:SetAttribute(MARK_ATTRIBUTE[kind], false)
		print(("[Эффект] метка «%s» смыта с %s"):format(kind, target.Name))
	end

	-- Катализатор горения (Кислород). Уже висящие записи пересчитываются тут же:
	-- иначе кислородная турель разгоняла бы только то горение, которое ляжет после неё.
	-- Счёт идёт от табличного tickInterval, а не от текущего, поэтому второй Кислород
	-- ничего не ускоряет второй раз.
	local function applyCatalyst(target, elementData)
		local plan = elementData.burnCatalyst
		catalysts[target] = plan

		local byElement = effects[target]
		if byElement then
			for data, entry in pairs(byElement) do
				local base = data.tickInterval or (data.scald and data.scald.tickInterval) or 1
				entry.interval = base * plan.intervalScale
			end
		end
		print(("[Эффект] %s разгоняет горение на %s: тики x%.2f чаще, сила x%.2f")
			:format(elementData.name, target.Name, 1 / plan.intervalScale, plan.powerScale))
	end

	-- Что элемент делает с регенерацией цели. Три уровня из документа: вечная блокировка
	-- (Яд), временная (Кислота) и замедление (ветка холода). Лёд при этом единственный,
	-- кто реген разгоняет (after > 1).
	local function applyRegen(target, elementData)
		local plan = elementData.regen
		local current = regens[target]

		-- Яд необратим: «сам яд спадает, но реген к жуку не возвращается».
		if current and current.permanent then
			return
		end

		local scale = plan.after or (plan.block and 0) or plan.slow or 1
		local duration = plan.permanent and math.huge or (plan.duration or 0)

		-- Более тяжёлая блокировка перебивает лёгкую, а разгон Льда ложится только на ту цель,
		-- на которой ничего хуже не висит — иначе ледяная турель снимала бы чужой анти-реген.
		if current and current.scale < scale and current.remaining > 0 then
			return
		end

		regens[target] = { scale = scale, remaining = duration, permanent = plan.permanent }
		target:SetAttribute("RegenScale", scale)
		print(("[Эффект] %s меняет реген %s: x%.2f%s")
			:format(elementData.name, target.Name, scale, plan.permanent and " навсегда" or ""))
	end

	-- Болотный: сама зараза вешается здесь, а разносит её тик-цикл ниже: контакт
	-- жука с жуком — это геометрия каждого момента, а не попадание.
	local function applyInfection(target, elementData)
		if infections[target] then
			return
		end

		infections[target] = { plan = elementData.contagion, name = elementData.name }
		target:SetAttribute("Infected", true)
		print(("[Эффект] %s заражает %s Болотным"):format(elementData.name, target.Name))
	end

	-- Замедление приходит из двух источников — обычного (slows) и нарастающего (dryings
	-- у Глины). Наружу уходит сильнейшее, а не сумма: атрибут один, и складывать два
	-- замедления значило бы останавливать цель насмерть парой обычных турелей — а полная
	-- остановка это стан, и он принадлежит Льду и Глине.
	local function refreshSlow(target)
		local percent, attackPercent = 0, 0

		local slow = slows[target]
		if slow then
			percent = math.max(percent, slow.percent)
			attackPercent = math.max(attackPercent, slow.attackPercent or 0)
		end

		-- Глина после v4 копит только стан и скорость цели не трогает (hidden): шкала
		-- растёт так же, но наружу больше не выходит.
		local drying = dryings[target]
		if drying and not drying.plan.hidden then
			percent = math.max(percent, drying.percent)
		end

		target:SetAttribute("SlowPercent", percent)
		target:SetAttribute("AttackSlowPercent", attackPercent)
	end

	-- Стан (Лёд, засыхание Глины). Здесь ставится только срок, а держит жука на месте
	-- EnemySpawner — по той же причине, по которой там же живёт запутывание: сроки короче тика,
	-- а ведёт жука каждый кадр тот, кто его двигает.
	--
	-- Кулдаун считается от конца стана, а не от начала: иначе достаточно частая турель
	-- снова склеивала бы станы в один сплошной.
	local function applyStun(target, duration, cooldown, sourceName)
		local now = os.clock()
		if now < (stunCooldowns[target] or 0) then
			return false
		end

		target:SetAttribute("StunnedUntil", now + duration)
		target:SetAttribute("Stunned", true) -- визуальная метка для клиента (см. EnemyVisuals)
		stunCooldowns[target] = now + duration + (cooldown or 0)
		print(("[Эффект] %s станит %s на %.1f сек (следующий стан не раньше чем через %.1f сек)")
			:format(sourceName, target.Name, duration, duration + (cooldown or 0)))
		return true
	end

	-- Слепота (Песок). Чисто атрибут/таймер: никакой игровой логики (патхфиндинг/цели,
	-- визуал в EnemyVisuals) пока не привязано — только то, что явно было просите: срок
	-- обновляется каждым попаданием, в отличие от растущего замедления того же Песка.
	-- До документа дебаффов v2 слепота была чистым атрибутом без игровой логики. Теперь она
	-- определена: «цель теряет направление и ходит в случайные стороны» — то же самое,
	-- что делает Туман, поэтому выставляются те же атрибуты блуждания (ведёт их EnemySpawner
	-- каждый кадр), а не заводится второй такой же механизм. Атрибут Blinded остаётся:
	-- по нему картинка отличает слепоту от запутывания.
	local function applyBlind(target, elementData)
		local plan = elementData.blind
		local durationScale = amplifier(target)
		local duration = plan.duration * durationScale

		blinds[target] = os.clock() + duration
		target:SetAttribute("Blinded", true)

		local angle = math.random() * 2 * math.pi
		target:SetAttribute("ConfusedDirection", Vector3.new(math.cos(angle), 0, math.sin(angle)))
		target:SetAttribute("ConfusedUntil",
			math.max(target:GetAttribute("ConfusedUntil") or 0, os.clock() + duration))
		target:SetAttribute("Confused", true)
	end

	-- Замедление. Не складывается: более сильное перебивает более слабое, равное или своё же
	-- просто обновляет таймер. Скорость читает EnemySpawner каждый кадр.
	--
	-- Замедление грызни (Холод) едет вместе с ним одной записью, а не своей таблицей: это
	-- одно свойство одного элемента, и разъехаться в сроках они не должны.
	local function applySlow(target, elementData)
		local durationScale, powerScale = amplifier(target)
		local basePercent
		if elementData.slowGrowth then
			-- Песок: сила копится по попаданиям, а не по времени — отдельный счётчик,
			-- не сам slows[target], чтобы не путаться с усилением Пыли на проценте.
			local plan = elementData.slowGrowth
			growingSlows[target] = growingSlows[target] or {}
			local entry = growingSlows[target][elementData] or { hits = 0 }
			growingSlows[target][elementData] = entry
			basePercent = plan.start + plan.step * entry.hits
			entry.hits += 1
		elseif elementData.slowSpeedScale then
			-- Гейзер считает процент от текущей скорости цели вместо плоского slowPercent.
			basePercent = speedScaledValue(target, elementData.slowSpeedScale)
		else
			basePercent = elementData.slowPercent
		end
		local percent = basePercent * powerScale
		local duration = elementData.slowDuration * durationScale
		local attackPercent = (elementData.attackSlowPercent or 0) * powerScale

		local current = slows[target]

		-- Мокрый (Вода, Лужа, Пруд, Грязь): попадание не обновляет срок, а добавляет к уже
		-- висящему остатку — «мокрый удар по мокрому» копит время, не саму силу. Работает
		-- только поверх уже висящего Мокрого же: если сейчас держит что-то чужое и сильнее
		-- (Холод, Лёд), Мокрый удар идёт по обычному правилу ниже.
		if elementData.wet and current and current.wet then
			slows[target] = {
				percent = math.max(current.percent, percent),
				attackPercent = math.max(current.attackPercent, attackPercent),
				remaining = current.remaining + duration,
				wet = true,
			}
			refreshSlow(target)
			print(("[Эффект] %s копит Мокрый на %s: %.0f%%, +%.1f сек (всего %.1f сек)")
				:format(elementData.name, target.Name, slows[target].percent * 100, duration, slows[target].remaining))
			return
		end

		-- Сравниваются оба числа, а не одно замедление хода: в v4 появилась ветка холода
		-- без замедления хода вовсе (Снег, Метель: slowPercent = 0, зато грызня вдвое медленнее).
		-- По старому правилу любое висящее замедление молча съедало бы их единственное свойство.
		if current and current.percent > percent and (current.attackPercent or 0) >= attackPercent then
			return
		end

		slows[target] = {
			percent = math.max(percent, current and current.percent or 0),
			attackPercent = math.max(attackPercent, current and current.attackPercent or 0),
			remaining = duration,
			wet = elementData.wet or nil,
		}
		refreshSlow(target)
		if attackPercent > 0 then
			print(("[Эффект] %s замедляет %s на %.0f%% и его грызню на %.0f%% на %.1f сек")
				:format(elementData.name, target.Name, percent * 100, attackPercent * 100, duration))
		else
			print(("[Эффект] %s замедляет %s на %.0f%% на %.1f сек")
				:format(elementData.name, target.Name, percent * 100, duration))
		end
	end

	-- Засыхание (Глина): замедление, которое растёт само в тик-цикле. Попадание не углубляет
	-- эффект само, а только продлевает его: глубина — это время под обстрелом, а не число
	-- попаданий, иначе быстрая турель засушивала бы цель вчетверо быстрее обычной.
	local function applyDrying(target, elementData)
		local plan = elementData.slowRamp
		local durationScale = amplifier(target)

		local entry = dryings[target]
		if not entry or entry.plan ~= plan then
			entry = { percent = plan.start, plan = plan, name = elementData.name }
			dryings[target] = entry
			print(("[Эффект] %s начинает сушить %s: %.0f%% и глубже каждую секунду")
				:format(elementData.name, target.Name, plan.start * 100))
		end
		entry.remaining = plan.duration * durationScale

		refreshSlow(target)
	end

	-- Порча цели (Кислота): броня работает хуже против всех башен сразу, а сама цель слабее
	-- грызёт постройки. Повторное попадание обновляет срок и не складывает глубину: две кислотные
	-- турели держат порчу дольше, а не снимают броню вдвойне.
	local function applyDebuff(target, elementData)
		local plan = elementData.debuff
		local durationScale, powerScale = amplifier(target)
		local armorShred = math.min(1, plan.armorShred * powerScale)
		local weaken = math.min(0.9, plan.weaken * powerScale)

		-- v4: «накопительно снижает броню цели». Срок по-прежнему обновляется, а откус
		-- теперь растёт с каждым попаданием до своего потолка: одна кислотная турель за
		-- несколько секунд растворяет броню танка почти целиком — для всех башен сразу.
		local current = debuffs[target]
		if plan.stackShred and current then
			armorShred = math.min(plan.stackMax or 1, current.armorShred + plan.stackShred * powerScale)
		end

		debuffs[target] = {
			armorShred = armorShred,
			weaken = weaken,
			remaining = plan.duration * durationScale,
		}
		target:SetAttribute("ArmorShred", armorShred)
		target:SetAttribute("Weakened", weaken)
		print(("[Эффект] %s разъедает %s: броня −%.0f%%, свой урон −%.0f%% на %.1f сек")
			:format(elementData.name, target.Name, armorShred * 100, weaken * 100,
				plan.duration * durationScale))
	end

	-- Урон по времени: горение, кровотечение Металла, кислота. Повторное попадание даёт новый
	-- независимый стек, пока их меньше лимита из elementData.maxStacks. После лимита новое
	-- попадание замещает самый старый (наименьший остаток) стек целиком, а не только его
	-- таймер: у нового могут быть свои цифры — например, метка Пыли легла между двумя выстрелами.
	--
	-- Цифра в таблице всегда в секунду (`damagePerSecond`), а тикает стек раз в `tickInterval`.
	-- Поэтому кровотечение и кислота читаются в таблице тем же числом, что и горение,
	-- и сравнивать их можно прямо. Урон тика округляется до целого и не бывает меньше единицы
	-- (HP целое), поэтому слишком частый тик у слабого элемента оказывается выгоднее табличного.
	-- Общая часть горения, кровотечения, кислоты и ошпаривания: заводит запись на цель (если
	-- её ещё нет) и кладёт новый стек, либо — на лимите — замещает старейший. Вынесено отдельно,
	-- потому что v2.2 добавил второй источник таких стеков (ошпаривание Гейзера), у которого
	-- срок стека считается иначе, а тикает он в том же общем цикле ниже.
	local function pushOvertimeStack(target, elementData, duration, damagePerTick, interval, maxStacks)
		-- Катализатор (Кислород) читается здесь, а не в тик-цикле: стек считает свои цифры
		-- один раз в момент, когда ложится — точно так же, как метка Пыли.
		local catalyst = catalysts[target]
		if catalyst then
			interval *= catalyst.intervalScale
			damagePerTick = math.max(1, math.floor(damagePerTick * catalyst.powerScale + 0.5))
		end

		local stack = { remaining = duration, damagePerTick = damagePerTick }

		effects[target] = effects[target] or {}
		local entry = effects[target][elementData]
		if not entry then
			entry = { stacks = {}, interval = interval, elapsed = 0 }
			effects[target][elementData] = entry
			target:SetAttribute("Burning", true) -- визуальная метка для клиента (см. EnemyVisuals)
			-- Burning стоит на ЛЮБОМ уроне по времени, а трупу и следу нужно именно что:
			-- обугливает только Горение и Плавление, капает — только Кровотечение (см. PhysicsFX).
			if elementData.chars then
				target:SetAttribute("Scorched", true)
			end
			if elementData.bleeds then
				target:SetAttribute("Bleeding", true)
			end
		end

		if #entry.stacks < maxStacks then
			table.insert(entry.stacks, stack)
		else
			local oldestIndex = 1
			for i, existing in ipairs(entry.stacks) do
				if existing.remaining < entry.stacks[oldestIndex].remaining then
					oldestIndex = i
				end
			end
			entry.stacks[oldestIndex] = stack
			print(("[Эффект] %s на %s: лимит стеков (%d) достигнут, старейший заменён новым")
				:format(elementData.name, target.Name, maxStacks))
		end
	end

	local function applyOvertime(target, elementData)
		local durationScale, powerScale = amplifier(target)
		local interval = elementData.tickInterval or 1
		pushOvertimeStack(target, elementData,
			elementData.duration * durationScale,
			scaled(elementData.damagePerSecond * interval, powerScale),
			interval, elementData.maxStacks or 1)
	end

	-- Ошпаривание (Гейзер, v2.2): урон по времени, у которого сам срок зависит от скорости
	-- цели — резвая держится дольше, уже заторможенная короче, той же логикой, что и урон
	-- Землетрясения (см. speedScaledValue). Стеки лежат в той же effects[target][elementData],
	-- что и обычное горение — общий тик-цикл ниже их не различает.
	local function applyScald(target, elementData)
		local plan = elementData.scald
		local durationScale, powerScale = amplifier(target)
		local interval = plan.tickInterval or 1
		pushOvertimeStack(target, elementData,
			speedScaledValue(target, plan.durationSpeedScale) * durationScale,
			scaled(plan.damagePerSecond * interval, powerScale),
			interval, plan.maxStacks or 1)
	end

	-- Запутывание (Туман). Здесь ставится только срок и сторона, а пьяную походку ведёт
	-- EnemySpawner: он двигает жука каждый кадр, а тик-цикл ниже идёт раз в четверть секунды
	-- и для окна 0.5–0.8 сек всё равно слишком груб. Сторона выбирается каждым попаданием заново — именно поэтому
	-- жук «ходит в случайные стороны», а не убегает по прямой.
	--
	-- Стакается без потолка: сроки складываются. ConfusedUntil — в шкале os.clock() сервера,
	-- поэтому клиенту он бесполезен и для картинки есть отдельный булевый Confused.
	local function applyConfusion(target, elementData)
		local plan = elementData.confusion
		local durationScale = amplifier(target)
		local window = plan.minDuration + math.random() * (plan.maxDuration - plan.minDuration)
		local duration = window * durationScale

		local now = os.clock()
		local untilClock = math.max(target:GetAttribute("ConfusedUntil") or 0, now) + duration
		local angle = math.random() * 2 * math.pi

		target:SetAttribute("ConfusedDirection", Vector3.new(math.cos(angle), 0, math.sin(angle)))
		target:SetAttribute("ConfusedUntil", untilClock)
		target:SetAttribute("Confused", true) -- визуальная метка для клиента (см. EnemyVisuals)
		print(("[Эффект] %s запутывает %s на %.2f сек (всего блуждать %.2f сек)")
			:format(elementData.name, target.Name, duration, untilClock - now))
	end

	-- Накопление до пробоя (Дым). Попадания молча копятся, и на hits-м приходит разовый
	-- большой урон. Броню он игнорирует: это отравление, а не удар — тот же принцип, что
	-- у горения.
	local function applyBreakthrough(target, elementData)
		local plan = elementData.breakthrough

		counters[target] = counters[target] or {}
		local entry = counters[target][elementData] or { hits = 0 }
		counters[target][elementData] = entry

		entry.hits += 1
		entry.lastHit = os.clock()

		if entry.hits < plan.hits then
			print(("[Эффект] %s накапливается на %s: %d из %d")
				:format(elementData.name, target.Name, entry.hits, plan.hits))
			return
		end

		entry.hits = 0

		-- Смог: вокруг пробоя остаётся зона слепоты. Заводится до проверки HP ниже:
		-- взрыв случился, даже если его носитель к этому моменту уже мёртв.
		if plan.zone then
			spawnZone(target:GetPivot().Position, plan.zone.radius, plan.zone, elementData)
		end

		local hp = target:GetAttribute("HP") or 0
		if hp <= 0 then
			return
		end

		local _, powerScale = amplifier(target)
		local damage = scaled(plan.damage, powerScale)
		hp = math.max(0, hp - damage)
		target:SetAttribute("HP", hp)
		DamageDealtRemote:FireAllClients(target:GetPivot().Position, damage, false)
		print(("[Эффект] %s пробивает %s: %d урона мимо брони, осталось %d HP")
			:format(elementData.name, target.Name, damage, hp))
	end

	-- Живые враги вокруг точки, ближние первыми. Взрыв и цепочка — единственные свойства,
	-- которым нужна не одна цель, а её окрестность, поэтому папка ищется здесь, а не хранится
	-- модулем: Apply зовётся только на сервере, а там Workspace.Enemies есть всегда.
	local function enemiesAround(center, radius, exclude)
		local folder = Workspace:FindFirstChild("Enemies")
		local found = {}
		if not folder then
			return found
		end

		for _, enemy in folder:GetChildren() do
			if enemy ~= exclude and enemy:IsA("Model") and enemy.PrimaryPart and (enemy:GetAttribute("HP") or 0) > 0 then
				local distance = (enemy:GetPivot().Position - center).Magnitude
				if distance <= radius then
					table.insert(found, { enemy = enemy, distance = distance })
				end
			end
		end

		-- Ближние первыми: у цепочки есть лимит целей, и брать их в порядке папки значило бы,
		-- что разряд перескакивает через соседа к дальнему.
		table.sort(found, function(a, b)
			return a.distance < b.distance
		end)

		return found
	end

	-- Урон по площади. Броня работает как против обычного попадания — это удар, а не отравление;
	-- пробитие самого элемента при этом учитывается. Возвращает, скольких задело.
	local function damageAround(center, radius, amount, exclude, limit, elementData, sourceName)
		if amount <= 0 then
			return 0
		end

		local hits = 0
		for _, found in enemiesAround(center, radius, exclude) do
			if limit and hits >= limit then
				break
			end

			local enemy = found.enemy
			local damage = Effects.AfterArmor(enemy, amount, elementData)
			local hp = math.max(0, (enemy:GetAttribute("HP") or 0) - damage)
			enemy:SetAttribute("HP", hp)
			DamageDealtRemote:FireAllClients(enemy:GetPivot().Position, damage, true)
			hits += 1
			print(("[Эффект] %s задевает %s на %d, осталось %d HP"):format(sourceName, enemy.Name, damage, hp))
		end

		return hits
	end

	-- Физические силы (v4): отдача, притяжение, подброс. Все три — одно и то же смещение,
	-- разница только в направлении, поэтому и копятся они в один вектор на цели: документ
	-- требует именно результирующую — «действуют одновременно, в разные стороны, с разной силой».
	-- Само смещение выполняет EnemySpawner (атрибут Push) — по той же причине, по которой
	-- здесь же только ставится срок стана: жука ведёт каждый кадр тот, кто его двигает.
	local function addPush(target, offset)
		local current = target:GetAttribute("Push") or Vector3.zero
		target:SetAttribute("Push", current + Vector3.new(offset.X, 0, offset.Z))
		-- Любая отдача толкает и то, что лежит рядом и имеет физику (см. ServerScriptService.Impulse).
		if Effects.OnImpulsePush then
			Effects.OnImpulsePush(target:GetPivot().Position, offset)
		end
	end

	-- Скользящее среднее урона по элементу. Нужно только отдаче, которая у Камня и Кирпича
	-- «зависит от того, насколько сильный камень попался». Абсолютной шкалы у такой силы быть
	-- не может: урон выстрела зависит от башни, а Effects про башни не знает и знать не должен.
	-- Поэтому сила считается относительно того, как этот же элемент бьёт обычно.
	local hitAverages = {}
	local function relativeHit(elementData, damage)
		local average = hitAverages[elementData]
		if not average then
			hitAverages[elementData] = damage
			return 1
		end

		hitAverages[elementData] = average * 0.9 + damage * 0.1
		return math.clamp(damage / math.max(1, average), 0.25, 4)
	end

	-- Отдача: толкает назад по пути. Модель жука развёрнута на 180° (см. EnemySpawner:
	-- голова по +Z), поэтому её LookVector смотрит ровно назад — туда, куда бьёт отдача.
	local function applyKnockback(target, elementData, damage)
		local plan = elementData.knockback

		-- «Не работает по грызущим (держатся за стену жвалами)» — прямое требование документа.
		if target:GetAttribute("Chewing") then
			return
		end

		local distance = plan.distance
		if plan.scaleWithDamage then
			distance *= relativeHit(elementData, damage)
		end

		addPush(target, target:GetPivot().LookVector * distance)
	end

	-- Круговая отдача (Взрыв, Звук): расталкивает от точки попадания всех, кого задело,
	-- а не одну цель назад по пути. Сама цель тоже в радиусе: она в эпицентре,
	-- и направление ей берётся по её же пути, иначе вектор вышел бы нулевой.
	local function applyRadialKnockback(target, elementData)
		local plan = elementData.knockback
		local center = target:GetPivot().Position

		for _, found in enemiesAround(center, plan.radius or 8, nil) do
			local enemy = found.enemy
			if not enemy:GetAttribute("Chewing") then
				local away = enemy:GetPivot().Position - center
				away = Vector3.new(away.X, 0, away.Z)
				if away.Magnitude < 1e-3 then
					away = enemy:GetPivot().LookVector
				end
				addPush(enemy, away.Unit * plan.distance)
			end
		end
	end

	-- Притяжение к стреляющей турели. Счётчик на паре «цель + элемент», а не на цели:
	-- «притянутого врага нельзя больше стянуть этим же элементом, но можно другим».
	-- Без известного места выстрела тянуть некуда — такое попадание просто не тянет.
	local function applyPull(target, elementData, source)
		if not source then
			return
		end

		local plan = elementData.pull
		pulls[target] = pulls[target] or {}
		local used = pulls[target][elementData] or 0
		if used >= (plan.shots or 1) then
			return
		end
		pulls[target][elementData] = used + 1

		local toSource = source - target:GetPivot().Position
		toSource = Vector3.new(toSource.X, 0, toSource.Z)
		local gap = toSource.Magnitude
		if gap < 1e-3 then
			return
		end

		-- Не ближе, чем вплотную к самой турели: притяжение подтаскивает, а не затаскивает жука
		-- внутрь постройки — иначе воздушная турель сама подводила бы к себе грызунов.
		addPush(target, toSource.Unit * math.min(plan.distance, math.max(0, gap - 4)))
	end

	-- Подброс (Атмосфера): сторона и расстояние случайные, поэтому жук иногда
	-- оказывается ближе к выходу, чем был. Так в документе и задумано.
	local function applyToss(target, elementData)
		local plan = elementData.toss
		local angle = math.random() * 2 * math.pi
		local distance = plan.min + math.random() * (plan.max - plan.min)
		addPush(target, Vector3.new(math.cos(angle), 0, math.sin(angle)) * distance)
	end

	-- Нарастание урона (Кирпич, Стена): множитель растёт за каждое попадание по одной и той
	-- же цели и сбрасывается после plan.hits ступеней. Первый выстрел всегда обычный —
	-- это награда за долгую цель, а не бесплатная прибавка к каждому выстрелу.
	local function rampMultiplier(target, elementData)
		local plan = elementData.damageRamp

		ramps[target] = ramps[target] or {}
		local entry = ramps[target][elementData] or { hits = 0 }
		ramps[target][elementData] = entry

		local multiplier = 1 + plan.step * entry.hits
		entry.hits += 1
		if entry.hits > plan.hits then
			entry.hits = 0
		end

		return multiplier
	end

	-- Урон попадания: всё, что зависит от того, в кого именно прилетел снаряд — разгон Кирпича
	-- и броня. Отдельная функция, а не арифметика в Projectile, по той же причине, по которой
	-- там же лежит ShotDamage: модель урона целиком в одном файле, а снаряд решает только
	-- «долетел или нет».

	return {
		rampMultiplier = rampMultiplier,
		speedScaledValue = speedScaledValue,
		damageAround = damageAround,
		enemiesAround = enemiesAround,
		applyStun = applyStun,
		corpseRadius = corpseRadius,
		spawnZone = spawnZone,
		applyRadialKnockback = applyRadialKnockback,
		applyMark = applyMark,
		applyKindMark = applyKindMark,
		washMark = washMark,
		applyKnockback = applyKnockback,
		applyPull = applyPull,
		applyToss = applyToss,
		applySlow = applySlow,
		applyBlind = applyBlind,
		applyDrying = applyDrying,
		amplifier = amplifier,
		applyDebuff = applyDebuff,
		applyConfusion = applyConfusion,
		applyBreakthrough = applyBreakthrough,
		applyOvertime = applyOvertime,
		applyScald = applyScald,
		applyCatalyst = applyCatalyst,
		applyRegen = applyRegen,
		applyInfection = applyInfection,
		refreshSlow = refreshSlow,
	}
end
