local Effects = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace") -- взрыву и цепочке нужны соседи цели, а не одна она
local Debris = game:GetService("Debris") -- визуал зоны землетрясения сам убирается по своему сроку
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local DamageDealtRemote = Remotes:WaitForChild("DamageDealt")
-- Визуальный взрыв — не любая смерть, а только настоящий взрыв: детонация метки Пороха
-- огненным попаданием (detonate) или прямое попадание турелью с элементом Взрыв
-- (applyExplosion). Раньше CombatFX рисовал его на КАЖДУЮ смерть жука — баг.
local ExplosionRemote = Remotes:WaitForChild("Explosion")

-- Цена элемента считается по дереву рецептов, поэтому модель урона знает про Recipes.
-- Цикла нет: Recipes знает про Elements, Elements не знает ни про кого.
local Elements = require(ReplicatedStorage:WaitForChild("Elements"))
local Recipes = require(ReplicatedStorage:WaitForChild("Recipes"))

-- Только за пол арены (Arena.floorY) — зона землетрясения садится на нём видимым диском.
-- Effects не обратная зависимость: Arena ни о ком не требует, кроме Workspace.
local Arena = require(ReplicatedStorage:WaitForChild("Arena"))

-- effects[target][elementData] = { stacks = { { remaining = сек, damagePerTick = урон }, ... },
--                                  interval = сек между тиками, elapsed = накоплено с прошлого }
-- Стек хранит свои цифры, а не только остаток времени: метка Пыли усиливает то, что легло
-- при ней, и не должна задним числом пересчитывать уже висящие стеки. Интервал общий
-- на все стеки элемента: он свойство вещества, а не отдельного попадания.
-- elementData — всегда одна и та же table-ссылка из модуля Elements, поэтому её
-- можно использовать как ключ без отдельного идентификатора элемента.
local effects = {}

-- slows[target] = { percent = доля, attackPercent = доля замедления грызни, remaining = сек }
-- Замедление живёт отдельно от стеков урона: оно не складывается, а перебивается более
-- сильным, и истекает в том же тик-цикле. Процент бывает дробным (метка Пыли множит
-- его на 1.5) — это множитель скорости, а не HP, округлять его незачем.
local slows = {}

-- marks[target] = { durationScale, powerScale } — метка Пыли. Перманентная: срока у неё нет,
-- снимается только вместе с целью, поэтому и хранится признаком на цели, а не остатком времени.
local marks = {}

-- counters[target][elementData] = { hits = накоплено попаданий, lastHit = os.clock() }
-- Накопление до пробоя (Дым). Счётчик на пару «цель + элемент», а не на цель: два разных
-- накопителя (когда они появятся на старших тирах) копят каждый своё.
local counters = {}

-- ramps[target][elementData] = { hits = сколько попаданий подряд уже учтено }
-- Нарастание урона (Кирпич, Стена). На паре «цель + элемент», как счётчик Дыма:
-- разгон принадлежит жуку, а не башне, поэтому две кирпичные турели разгоняют его вместе,
-- а перенос огня на другого жука начинает разгон заново.
local ramps = {}

-- debuffs[target] = { armorShred, weaken, remaining } — порча самой цели (Кислота).
-- Лежит отдельно от стеков, потому что меняет не состояние эффекта, а свойства самого жука:
-- броню (атрибут ArmorShred читает AfterArmor) и его собственный урон по постройкам
-- (атрибут Weakened читает грызня в EnemySpawner).
local debuffs = {}

-- dryings[target] = { percent, remaining, plan } — засыхание (Глина). Не помещается в slows:
-- там правило «сильное перебивает слабое», а здесь одно и то же попадание раз за разом
-- делает эффект глубже. Наружу уходит сильнейшее из двух (см. refreshSlow).
local dryings = {}

-- primed[target] = { plan, lastBlast, name } — метка Пороха. Перманентная, как метка Пыли,
-- но взводит не эффекты, а взрыв: попадание с уроном по времени детонирует цель.
-- lastBlast — чтобы часто стреляющая турель не взрывала её каждым выстрелом.
local primed = {}

-- growingSlows[target][elementData] = { hits = N } — Песок: сила замедления копится по
-- попаданиям (start + step × hits), без потолка. Отдельно от slows[target], чтобы не путаться
-- с усилением Пыли на итоговом проценте. Живёт, пока жива цель.
local growingSlows = {}

-- blinds[target] = os.clock(), до которого висит Слепота (Песок). Обновляется каждым
-- попаданием, в отличие от growingSlows не копится.
local blinds = {}

-- stunCooldowns[target] = os.clock(), до которого цель нельзя станить снова. Иммунитет после
-- стана обязателен: выстрел раз в секунду со станом в 0.9 сек держал бы жука вечно,
-- и одна башня выключала бы цель из игры совсем.
local stunCooldowns = {}

-- zones = { { position, radius, plan, expires }, ... } — зоны-модификаторы местности на месте
-- смерти (Землетрясение, killZone). Список, а не таблица по цели: зона живёт своим сроком
-- на местности, а не привязана ни к одной цели — в её радиус может зайти кто угодно.
--
-- speedPlan — это damageSpeedScale того элемента, что оставил зону: по v2.2.1 внутри зоны
-- его правило «быстрая цель = больше урона» действует для любой турели, а не только для своей.
--
-- Дерево v4 добавило зоны, которые действуют сами, а не меняют чужой урон: Засуха жжёт,
-- Звезда жжёт всё сильнее со временем, Ураган тормозит, а Смог, Дождь, Снег, Метель,
-- Кислотный дождь и Уголь вешают на зашедшего чужой эффект (spread). Лимита «одна зона
-- на турель» из документа здесь нет: Effects.Apply не знает, какая турель выстрелила —
-- в снаряд кладётся только элемент. Это отдельная задача.
local zones = {}

-- Как часто зона повторно вешает свой эффект на одну и ту же цель. Шаг тик-цикла
-- для этого слишком частый: кислотное облако клало бы четыре стека в секунду.
local ZONE_APPLY_INTERVAL = 1

-- kindMarks[target][kind] = { plan, expires } — метки помимо метки Пыли: Ржавчина ("rust"),
-- Пепел ("ash"), Грунт ("soil"). Отдельно от marks[target]: та одна на цель и означает
-- ровно усиление эффектов, а этих может висеть несколько разом, и каждая значит своё.
local kindMarks = {}

-- Имя атрибута на самой цели под каждую метку — для клиента и для тех, кому нужен
-- сам факт метки, а не её цифры.
local MARK_ATTRIBUTE = { rust = "Rusted", ash = "Ashed", soil = "Soiled" }

-- pulls[target][elementData] = сколько раз этот элемент уже стягивал эту цель. Пара
-- «цель + элемент», а не просто цель: притянутого Воздухом всё ещё может стянуть Давление.
local pulls = {}

-- catalysts[target] = burnCatalyst Кислорода. Не эффект сам по себе: меняет то, как тикает
-- чужое горение, поэтому читается в момент, когда стек ложится.
local catalysts = {}

-- infections[target] = { plan, name } — Болотный. Отдельно от slows: он расходится сам —
-- тик-цикл ищет соседей каждого заражённого и заражает их тем же планом.
local infections = {}

-- regens[target] = { scale, remaining, permanent } — что с регенерацией цели. Наружу уходит
-- атрибутом RegenScale, который читает EnemySpawner: про сам реген Effects не знает,
-- как не знает про грызню (Weakened) и про броню (ArmorShred).
local regens = {}

-- Множитель от метки указанного рода. Лежит здесь, а не рядом с остальными метками:
-- его читает AfterArmor выше по файлу, а локальная функция должна быть объявлена до него.
local function markScale(target, kind, field)
	local byKind = kindMarks[target]
	local entry = byKind and byKind[kind]
	if not entry then
		return 1
	end
	return entry.plan[field] or 1
end

-- Назначается снаружи (TowerBuilder), чтобы Гора могла оставить физическую преграду на месте
-- смерти жука (killBarrier). Effects не умеет строить сам: TowerBuilder уже требует Effects,
-- и обратный require зациклил бы модули — колбек вместо этого, как EnemySpawner.OnBreach.
Effects.OnKillBarrier = nil -- function(position: Vector3, hp: number, scale: number)

-- Броня — число на самой цели (Enemies[...].armor → атрибут Armor), а не процент,
-- зашитый в модель урона (задача #44, по alchemy_td_enemy_mechanics.md). Раньше здесь жил
-- ARMOR_DAMAGE_REDUCTION (плоские −30% урона турели, только для прямого попадания) — теперь
-- остался только минимальный процент, который проходит всегда, сколько бы брони ни было.
Effects.ARMOR_MIN_SHARE = 0.1

-- Сколько базовых элементов в составе каждого: базовый — один, составной — сумма родителей.
-- Это и есть цена элемента в покупках, и именно по ней растёт урон снаряда (v2.1).
--
-- Считается один раз при загрузке и по самому дереву, а не проставляется руками в Elements:
-- тридцать девять чисел, выписанных вторым списком, разошлись бы с деревом на первом же
-- новом рецепте. Ключ таблицы — сама запись элемента, как и у эффектов на цели:
-- ShotDamage получает запись, а не ключ, и искать ключ обратным перебором было бы глупо.
local basicsByData = {}
do
	local parents = {}
	for _, recipe in Recipes.List do
		parents[recipe.result] = recipe
	end

	local basicsByKey = {}
	local function basicsOf(key)
		local known = basicsByKey[key]
		if known then
			return known
		end

		-- Помечаем единицей до спуска в родителей: если в дерево когда-нибудь попадёт
		-- цикл, рекурсия остановится на нём, а не повесит загрузку плейса насмерть.
		basicsByKey[key] = 1

		local recipe = parents[key]
		local count = recipe and (basicsOf(recipe.a) + basicsOf(recipe.b)) or 1
		basicsByKey[key] = count
		return count
	end

	for key, data in Elements do
		basicsByData[data] = basicsOf(key)
	end
end

-- Из скольких базовых собран элемент. Нужно не только урону, но и тому, кто захочет
-- показать цену игроку (справочник): число считается в одном месте, а не в каждом окне заново.
function Effects.Basics(elementData)
	return basicsByData[elementData] or 1
end

-- Шаг единого тик-цикла. Была секунда, стала четверть: у урона по времени появился
-- свой tickInterval (горение тикает раз в секунду, кровотечение Металла вдвое чаще,
-- Кислота и Стекло — вчетверо), и общий цикл должен быть достаточно мелким, чтобы
-- это отмерять. Сроки эффектов считаются в секундах, а не в тиках, поэтому цифры
-- в Elements от шага не зависят.
Effects.TICK_STEP = 0.25

-- Чистое вычитание брони: плоское число, не процент. Броня 10, урон 15 → проходит 5,
-- но не меньше ARMOR_MIN_SHARE от исходного (иначе крупная броня на слабом попадании
-- обнуляла бы его целиком). Отдельный math.max(1, ...) поверх — чтобы округление не
-- превратило маленький процент в буквальный ноль.
--
-- Броню режут с двух сторон, и это разные вещи: `armorPierce` — свойство самого элемента
-- (Обсидиан и Кислота бьют мимо брони целиком, Металл — вполовину), `ArmorShred` — порча
-- на самой цели от Кислоты, которая работает для всех башен сразу, не только для своей. Складываются
-- и обрезаются единицей — оба разом не пробивают больше, чем на 100%.
--
-- Общая для удара и урона по времени: зовётся и из AfterArmor ниже (прямое попадание,
-- взрыв, цепочка), и напрямую из единого тик-цикла и applyBreakthrough — по документу
-- горение, плавление и Дым броню не пробивают — это не привилегия снаряда.
-- Сколько урона за забег нанёс каждый элемент (ключ — elementData.name, он у элементов
-- уникален). По нему Эволюционер понимает, какое оружие у игрока самое эффективное
-- (design: alchemy_td_enemies.md, каста 3). Считается здесь, а не у самого Эволюционера:
-- «самое эффективное оружие игрока» — это про весь забег, а не про то, что досталось одному жуку.
Effects.ElementUsage = {}

-- Обнуляется на новый забег (WaveRunner.clearArena): привычка колонии не должна
-- переезжать из прошлой попытки в следующую.
function Effects.ResetElementUsage()
	table.clear(Effects.ElementUsage)
end

-- Взрыв по площади наружу: по нему сносятся конструкции жуков («уничтожаются
-- тяжёлым снарядом и горят»). Effects про EnemyStructures знать не может — он в
-- ReplicatedStorage, а тот серверный; колбек — тот же приём, что и у OnKillBarrier.
Effects.OnAreaBlast = nil

-- Жук впитал элемент (Разносчик). Тот же колбек-мост в серверный EnemyBehavior.
Effects.OnAbsorb = nil

-- Изменение рельефа на месте смерти (Литосфера). Тот же приём, что и у Горы
-- через OnKillBarrier: Effects считает только числа элемента, а бетон двигает серверный
-- ConcreteFloor — он в ServerScriptService, а этот модуль общий.
Effects.OnTerrain = nil

-- Сколько урона срезают свойства самого жука до того, как считается броня
-- (design: alchemy_td_enemies.md, касты 2 и 3). Три источника, все читаются атрибутами:
--
--   Щит Щитоносца — только в лоб. Откуда ударили, говорит атрибут HitFrom, который
--   ставит тот, кто наносит урон (снаряд, площадная турель). Именно поэтому
--   «перекрёстный огонь обходит щит» сам собой: вторая турель стоит под другим углом.
--   Нет HitFrom — щит не срабатывает вовсе (горение, яд, зоны — щитом не закрыть).
--   Прикрытие за чужим щитом — CoveredUntil/CoverReduction, ставит сам Щитоносец.
--   Привычка Эволюционера — ResistElement/ResistShare.
local function mitigate(target, damage, elementData)
	local now = os.clock()

	local shieldArc = target:GetAttribute("ShieldArc")
	if shieldArc then
		local from = target:GetAttribute("HitFrom")
		if from then
			local pivot = target:GetPivot()
			-- Голова модели смотрит по -LookVector: кадр жука довёрнут на 180°
			-- (см. EnemySpawner), и без этого знака щит закрывал бы спину.
			local facing = -pivot.LookVector
			local toShooter = from - pivot.Position
			local a = Vector3.new(facing.X, 0, facing.Z)
			local b = Vector3.new(toShooter.X, 0, toShooter.Z)
			if a.Magnitude > 1e-3 and b.Magnitude > 1e-3 then
				local angle = math.deg(math.acos(math.clamp(a.Unit:Dot(b.Unit), -1, 1)))
				if angle <= shieldArc then
					damage *= 1 - math.clamp(target:GetAttribute("ShieldReduction") or 0, 0, 0.95)
				end
			end
		end
	end

	if now < (target:GetAttribute("CoveredUntil") or 0) then
		damage *= 1 - math.clamp(target:GetAttribute("CoverReduction") or 0, 0, 0.95)
	end

	local resist = target:GetAttribute("ResistElement")
	if resist and elementData and elementData.name == resist then
		damage *= 1 - math.clamp(target:GetAttribute("ResistShare") or 0, 0, 0.95)
	end

	return damage
end

function Effects.ApplyArmor(target, damage, elementData)
	if damage <= 0 then
		return 0
	end

	-- Свойства самого жука — ДО брони: щит и привычка гасят удар до того, как он дошёл
	-- до тела, а броня — это уже само тело. Порядок важен: минимум ARMOR_MIN_SHARE
	-- считается от уже срезанного урона, а не от исходного.
	damage = mitigate(target, damage, elementData)
	if damage <= 0 then
		return 0
	end

	local armorValue = target:GetAttribute("Armor")
	if not armorValue or armorValue <= 0 then
		return math.floor(damage + 0.5)
	end

	local pierce = (elementData and elementData.armorPierce or 0) + (target:GetAttribute("ArmorShred") or 0)
	local effectiveArmor = armorValue * (1 - math.clamp(pierce, 0, 1))
	local floor = damage * Effects.ARMOR_MIN_SHARE
	return math.max(1, math.floor(math.max(damage - effectiveArmor, floor) + 0.5))
end

-- Урон прямого попадания (снаряд, взрыв, цепочка) с учётом местности и брони цели.
function Effects.AfterArmor(target, damage, elementData)
	if damage <= 0 then
		return 0
	end

	-- Зона Землетрясения (v2.2.1) распространяет своё правило скорости на любой прямой удар
	-- по цели внутри неё — снаряд, взрыв, цепочку: всё, что идёт через AfterArmor. Урон
	-- по времени её не видит: у него свой путь через ApplyArmor напрямую, минуя эту обёртку —
	-- зона осталась модификатором именно удара, как и раньше.
	--
	-- У кого своё damageSpeedScale уже есть (Землетрясение, Гора), тому зона ничего не даёт:
	-- его скорость уже посчитана в HitDamage, и второй множитель был бы двойным начислением.
	-- Зона раздаёт правило тем, у кого его нет, а не удваивает своё.
	if not (elementData and elementData.damageSpeedScale) then
		damage *= Effects.ZoneMultiplier(target)
	end

	-- Ржавчина усиливает именно удар и только его: у урона по времени свой путь через
	-- ApplyArmor мимо этой обёртки, и туда метка не заходит. Этим она и противоположна
	-- метке Пыли, которая усиливает только эффекты и не трогает удар.
	damage *= markScale(target, "rust", "damageScale")

	return Effects.ApplyArmor(target, damage, elementData)
end

-- Урон снаряда с залитым элементом: базовый урон башни × число базовых элементов
-- в составе, дальше — множитель свойства (damageMultiplier: Земля ×3, Пыль ×0.2).
-- Пустая колба бьёт базовым уроном башни.
--
-- **Не по тиру** (переведено задачей #36 по документу v2.1): тир — это глубина дерева
-- и порядок открытия, а не цена. Внутри одного тира цена разная (Торнадо — 6 базовых,
-- Взрыв — 4, а тир у обоих третий), а тиры 3 и 4 вообще перекрываются: Стекло стоит
-- столько же, сколько Извержение. Урон по тиру делал бы часть элементов выгодной сделкой,
-- часть невыгодной, и игрок ходил бы только выгодными путями.
--
-- Считается в момент выстрела, а не попадания: снаряд несёт готовое число, поэтому
-- вынутый в полёте элемент меняет следующие выстрелы, а не уже сделанный.
function Effects.ShotDamage(baseDamage, elementData)
	if not elementData then
		return baseDamage
	end

	local multiplier = elementData.damageMultiplier or 1
	if multiplier == 0 then
		-- Плазма: урона от снаряда нет вовсе, весь урон идёт через эффект. Ноль здесь надо
		-- вернуть раньше округления: math.max(1, ...) ниже превратил бы его в единицу.
		return 0
	end

	-- Разброс Камня катится в момент выстрела, а не попадания: снаряд несёт готовое
	-- число, и промах стоит именно того выстрела, который выпал.
	if elementData.damageRandom then
		local spread = elementData.damageRandom
		multiplier *= spread.min + math.random() * (spread.max - spread.min)
	end

	local costed = baseDamage * Effects.Basics(elementData)
	return math.max(1, math.floor(costed * multiplier + 0.5))
end

-- Метка Пыли: пока висит, всё, что ложится на цель, ложится дольше и сильнее. Читается
-- в момент наложения эффекта, а не в момент тика: стек считает свои цифры один раз.
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
function Effects.HitDamage(target, elementData, damage)
	if damage <= 0 then
		return 0
	end

	if elementData and elementData.damageRamp then
		damage *= rampMultiplier(target, elementData)
	end

	if elementData and elementData.damageSpeedScale then
		damage *= speedScaledValue(target, elementData.damageSpeedScale)
	end

	return Effects.AfterArmor(target, damage, elementData)
end

-- Метка Пороха. Однократная и перманентная, как метка Пыли: вторая пороховая турель
-- по той же цели ничего не даёт, а любая огненная рядом становится вдвое полезнее.
--
-- Перекрашивает жука клиент (StarterPlayerScripts.EnemyRender) по атрибуту Primed: видимое тело
-- живёт только у клиента, на сервере от жука остался невидимый якорь. Basalt вместо сгенерированного
-- материала нарочно: встроенная текстура движка не требует загрузки и всегда отрисовывается —
-- кастомный MaterialVariant (первый вариант) прижился только в той же сессии Studio, где был
-- сгенерирован, а после перезапуска рендерился как плоский исходный цвет без пятен.
-- Пёстрый каменный рисунок Basalt даёт ту же пятнистость, а затемнение исходного цвета наполовину
-- к чёрному держит его тёмным, даже если исходная шкура жука светлая.
local function applyPrimer(target, elementData)
	if primed[target] then
		return
	end

	primed[target] = { plan = elementData.primer, lastBlast = 0, name = elementData.name }
	target:SetAttribute("Primed", true) -- по нему клиент красит жука (Basalt, цвет наполовину к чёрному)

	print(("[Эффект] %s метит %s под взрыв до конца жизни цели")
		:format(elementData.name, target.Name))
end

-- Детонация метки Пороха. «Огненная турель» — это любой элемент с уроном по времени:
-- порох поджигает и горение, и кровотечение, и кислота. Сама помеченная цель и есть заряд,
-- поэтому взрыв бьёт и по ней тоже. У Плазмы урона снаряда нет вовсе, и метку она
-- не подрывает: детонирует удар, а не отрава.
local function detonate(target, damage)
	local mark = primed[target]
	local now = os.clock()
	if now - mark.lastBlast < mark.plan.interval then
		return
	end
	mark.lastBlast = now

	local blast = math.max(1, math.floor(damage * mark.plan.damageShare + 0.5))
	local position = target:GetPivot().Position
	local hits = damageAround(position, mark.plan.radius, blast, nil, nil, nil, mark.name)
	ExplosionRemote:FireAllClients(position, mark.plan.radius)
	if Effects.OnImpulseBlast then
		Effects.OnImpulseBlast(position, mark.plan.radius)
	end
	print(("[Эффект] %s детонирует на %s: %d урона по %d целям в радиусе %d")
		:format(mark.name, target.Name, blast, hits, mark.plan.radius))
end

-- Взрыв — единственное свойство, у которого есть своя площадь: обычно радиус принадлежит
-- турели, а не тому, чем она залита. По помеченной Порохом цели радиус шире — это и есть
-- заявленная в документе связка «Порох + Взрыв».
local function applyExplosion(target, elementData, damage)
	local plan = elementData.explosion
	local mark = primed[target]
	local radius = plan.radius * (mark and mark.plan.explosionScale or 1)
	local share = math.max(1, math.floor(damage * plan.damageShare + 0.5))

	local position = target:GetPivot().Position
	local hits = damageAround(position, radius, share, target, nil, elementData, elementData.name)
	ExplosionRemote:FireAllClients(position, radius)
	if Effects.OnImpulseBlast then
		Effects.OnImpulseBlast(position, radius)
	end
	-- Тот же взрыв сносит и конструкции жуков, а огонь их ещё и поджигает:
	-- «уничтожаются тяжёлым снарядом и горят» (alchemy_td_enemies.md, Строитель).
	if Effects.OnAreaBlast then
		Effects.OnAreaBlast(target:GetPivot().Position, radius, share, elementData)
	end

	if hits > 0 then
		print(("[Эффект] %s взрывается на %s: %d урона по %d соседям в радиусе %.0f")
			:format(elementData.name, target.Name, share, hits, radius))
	end
end

-- Цепочка: разряд перескакивает на ближайших соседей цели. Ограничена и числом целей,
-- и радиусом — иначе на плотной волне один выстрел бил бы по всей арене.
local function applyChain(target, elementData, damage)
	local plan = elementData.chain
	local share = math.max(1, math.floor(damage * plan.damageShare + 0.5))

	-- Свой обход вместо damageAround: в v4 у цепочки появились условия на каждую цель.
	-- Проводимость — это Мокрый или Плавление: ток проводят и вода, и лава.
	local hits = 0
	for _, found in enemiesAround(target:GetPivot().Position, plan.radius, target) do
		if hits >= plan.targets then
			break
		end

		local enemy = found.enemy
		local wet = enemy:GetAttribute("Wet")
		-- Молния бьёт только по мокрым, Электричество — всегда: в этом вся разница.
		if wet or not plan.requiresWet then
			local dealt = Effects.AfterArmor(enemy, share, elementData)
			local hp = math.max(0, (enemy:GetAttribute("HP") or 0) - dealt)
			enemy:SetAttribute("HP", hp)
			DamageDealtRemote:FireAllClients(enemy:GetPivot().Position, dealt, true)
			hits += 1

			-- Электронность: стан только проводящим. Сухая и не расплавленная цель
			-- получает урон цепочки, но не стан.
			if plan.stun and (wet or enemy:GetAttribute("Molten")) then
				applyStun(enemy, plan.stun.duration, plan.stun.cooldown, elementData.name)
			end
		end
	end

	if hits > 0 then
		print(("[Эффект] %s перескакивает с %s на %d сосед(ей) по %d урона")
			:format(elementData.name, target.Name, hits, share))
	end
end

-- Зона-модификатор местности на месте смерти (Землетрясение, v2.2.1). Радиус — по габариту
-- трупа, а не по таблице: форма зоны — свойство того, кто умер.
-- Светящийся диск (spawnZoneVisual) — чисто картинка поверх той же записи: без него
-- игрок не видит, где зона и что она вообще появилась.
local function applyKillZone(target, elementData)
	local plan = elementData.killZone
	local radius = plan.radius or corpseRadius(target) * (plan.radiusScale or 1)
	local position = target:GetPivot().Position

	-- Звезда: «каждое убийство продлевает время жизни и размер зоны» — вторая зона
	-- рядом не заводится, а кормит первую. Именно поэтому её урон и растёт без потолка:
	-- поток жуков через одно место кормит одну и ту же звезду.
	if plan.extendOnKill then
		for _, zone in zones do
			if zone.element == elementData and (position - zone.position).Magnitude <= zone.radius then
				zone.expires += plan.extendOnKill
				zone.radius += plan.radiusOnKill or 0
				print(("[Эффект] %s кормит свою зону смертью %s: +%.1f сек, радиус %.1f")
					:format(elementData.name, target.Name, plan.extendOnKill, zone.radius))
				return
			end
		end
	end

	-- Зона без своих чисел переиспользует damageSpeedScale элемента (Землетрясение,
	-- v2.2.1). Если нет ни его, ни своих свойств — зона ничего не делает, и это опечатка
	-- в таблице, а не замысел. Ловим здесь, а не тишиной в разгар боя.
	assert(plan.damagePerSecond or plan.spreadElement or plan.slowPercent or elementData.damageSpeedScale,
		("[Effects] у %s есть killZone, но она ничего не делает"):format(elementData.name))

	spawnZone(position, radius, plan, elementData)
	print(("[Эффект] %s оставляет зону на месте смерти %s: радиус %.1f на %.1f сек")
		:format(elementData.name, target.Name, radius, plan.duration))
end

-- Удар по области в момент смерти (Континент, Океан, Облако, Дождь, Снег, Литосфера).
-- Отличается от Взрыва тем, что срабатывает не от попадания, а от смерти, и считается
-- не от урона выстрела, а от того, кто умер.
local function applyKillDamage(target, elementData)
	local plan = elementData.killDamage
	local position = target:GetPivot().Position

	local amount = plan.damage
	if plan.damagePerMaxHp then
		amount = math.clamp((target:GetAttribute("MaxHP") or 0) * plan.damagePerMaxHp,
			plan.minDamage or 1, plan.maxDamage or math.huge)
	end

	local hits = damageAround(position, plan.radius, amount, target, nil, elementData, elementData.name)

	-- Задетые получают чужой эффект по ключу (Океан — Мокрость, Облако и Дождь —
	-- Ошпаривание Пара): урон 0, потому что бить второй раз не надо — нужны только эффекты.
	local spread = plan.spreadElement and Elements[plan.spreadElement] or nil
	if spread then
		for _, found in enemiesAround(position, plan.radius, target) do
			Effects.Apply(found.enemy, spread, 0)
		end
	end

	ExplosionRemote:FireAllClients(position, plan.radius)
	if Effects.OnImpulseBlast then
		Effects.OnImpulseBlast(position, plan.radius)
	end
	print(("[Эффект] %s бьёт по области на смерти %s: %d урона по %d целям в радиусе %.0f")
		:format(elementData.name, target.Name, amount, hits, plan.radius))
end

-- Лечение построек плодом (Растение, Дерево, Жизнь). Приоритет — «чем ниже HP
-- постройки, тем выше», и считается он от доли, а не от абсолютного числа: стена на 60 из 400
-- в большей беде, чем колба на 40 из 60. Effects лечит постройки напрямую, как и бьёт
-- жуков: это атрибуты на моделях в Workspace, а не чужой модуль.
local function applyKillHeal(target, elementData)
	local plan = elementData.killHeal
	local folder = Workspace:FindFirstChild("Towers")
	if not folder then
		return
	end

	-- Метка Пепла на убитом усиливает лечебные свойства растения (документ v4).
	local amount = math.floor(plan.amount * markScale(target, "ash", "healScale") + 0.5)

	for _ = 1, plan.fruits or 1 do
		-- Каждый плод ищет постройку заново: первый уже подлечил ту, что была худшей.
		local best, bestRatio
		for _, building in folder:GetChildren() do
			local hp = building:GetAttribute("HP")
			local maxHp = building:GetAttribute("MaxHP")
			if hp and maxHp and maxHp > 0 and hp > 0 and (hp < maxHp or plan.overheal) then
				local ratio = hp / maxHp
				if not bestRatio or ratio < bestRatio then
					best, bestRatio = building, ratio
				end
			end
		end

		if not best then
			return
		end

		local hp = best:GetAttribute("HP")
		local maxHp = best:GetAttribute("MaxHP")
		local healed = math.min(maxHp - hp, amount)
		local overflow = amount - healed
		if overflow > 0 and plan.overheal then
			-- Дерево: перехил идёт в прочность, и потолка у неё нет — так в документе.
			best:SetAttribute("MaxHP", maxHp + overflow)
			healed += overflow
		end
		best:SetAttribute("HP", hp + healed)

		print(("[Эффект] %s лечит %s на %d (было %d из %d)")
			:format(elementData.name, best.Name, healed, hp, maxHp))
	end
end

-- Физическая преграда на месте смерти (Гора, v2.2). Effects сам ничего не строит — только
-- считает HP и масштаб из HP убитого и передаёт их наружу через OnKillBarrier (см. его
-- объявление в начале файла); строит и занимает клетку уже TowerBuilder.
local function applyKillBarrier(target, elementData)
	if not Effects.OnKillBarrier then
		return
	end

	local plan = elementData.killBarrier
	local maxHp = target:GetAttribute("MaxHP") or 0
	local hp = math.clamp(maxHp * plan.hpPerMaxHp, plan.minHp, plan.maxHp)
	local ratio = (hp - plan.minHp) / math.max(1, plan.maxHp - plan.minHp)
	local scale = plan.sizeMin + (plan.sizeMax - plan.sizeMin) * ratio

	print(("[Эффект] %s оставляет преграду на месте смерти %s: %d HP, масштаб %.2f")
		:format(elementData.name, target.Name, hp, scale))
	Effects.OnKillBarrier(target:GetPivot().Position, hp, scale)
end

-- Навешивает на цель всё, что даёт элемент поверх урона снаряда (его списывает сам
-- снаряд в момент попадания, см. Projectile). damage — сколько этот выстрел реально снял:
-- от него считаются доли взрыва, цепочки и детонации.
--
-- Свойства независимы: элемент может и жечь, и замедлять одновременно (Пар), а Гейзер
-- делает три вещи сразу. Новое свойство — это ветка здесь плюс поле в таблице Elements,
-- а не правка вызывающего кода.
-- source — откуда пришёл выстрел (позиция ствола). Нужен только притяжению: оно
-- тянет к стреляющей турели, а отдача и подброс считают направление по самой цели.
-- Необязателен: без него притяжение просто не срабатывает, а не падает.
function Effects.Apply(target, elementData, damage, source)
	damage = damage or 0

	-- Счёт оружия игрока и впитывание Разносчика — здесь, в единственном месте, через
	-- которое проходит ЛЮБОЕ попадание элементом — снаряд, площадь, взрыв, цепочка.
	if elementData and damage > 0 then
		Effects.ElementUsage[elementData.name] = (Effects.ElementUsage[elementData.name] or 0) + damage
		if Effects.OnAbsorb and target:GetAttribute("Absorbs") then
			Effects.OnAbsorb(target, elementData.name, damage)
		end
	end

	-- Площадь и цепочка — первыми и без проверки на живучесть цели: бомба срабатывает
	-- и в тот момент, когда её носитель умирает от этого же выстрела. Иначе добитый жук
	-- гасил бы взрыв, и Взрыв работал бы тем хуже, чем сильнее турель.
	if elementData.explosion and damage > 0 then
		applyExplosion(target, elementData, damage)
	end

	if elementData.chain and damage > 0 then
		applyChain(target, elementData, damage)
	end

	if primed[target] and damage > 0 and elementData.damageType == "overtime" then
		detonate(target, damage)
	end

	-- Круговая отдача — тоже до проверки на живучесть, по той же причине, что и взрыв:
	-- она бьёт по соседям, а не по тому, кто её получил.
	if elementData.knockback and elementData.knockback.radial then
		applyRadialKnockback(target, elementData)
	end

	-- Дальше — эффекты на самой цели, а мёртвой они ни к чему. Но если цель умерла именно от
	-- этого попадания, у элемента может быть последействие на месте смерти — зона (Землетрясение)
	-- или преграда (Гора). damage > 0 отсекает случай, когда Apply зовут на уже мёртвой
	-- цели без нового урона (взрыв/цепочка после добивающего попадания).
	if not target.Parent or (target:GetAttribute("HP") or 0) <= 0 then
		if target.Parent and damage > 0 then
			-- Удар по области — первым: он считается от HP трупа, а зона и преграда
			-- ставятся на его место уже после.
			if elementData.killDamage then
				applyKillDamage(target, elementData)
			end
			if elementData.killHeal then
				applyKillHeal(target, elementData)
			end
			if elementData.killZone then
				applyKillZone(target, elementData)
			end
			if elementData.killBarrier then
				applyKillBarrier(target, elementData)
			end
			-- Ландшафт Литосферы — последним из последействий смерти: удар по области
			-- считается по ещё ровному полу и по тем, кто на нём стоял.
			if elementData.terrain and Effects.OnTerrain then
				Effects.OnTerrain(target:GetPivot().Position, elementData.terrain, elementData)
			end
		end
		return
	end

	-- Метка — первой: если элемент когда-нибудь будет и метить, и жечь, то жжёт он уже
	-- по своей же метке. У Пыли других свойств нет, поэтому сейчас порядок ни на что не влияет.
	if elementData.amplifier then
		applyMark(target, elementData)
	end

	if elementData.primer then
		applyPrimer(target, elementData)
	end

	-- Метки v4 и смывка чужих — рядом с остальными метками и до всего прочего:
	-- если элемент и метит, и бьёт, то бьёт он уже по своей же метке.
	if elementData.mark then
		applyKindMark(target, elementData)
	end

	if elementData.washes then
		washMark(target, elementData.washes)
	end

	-- Мокрый делает цель проводящей (Молния, Электронность) и смывает Пепел —
	-- оба правила из документа дебаффов v2, и оба про любой источник Мокрого.
	if elementData.wet then
		target:SetAttribute("Wet", true)
		washMark(target, "ash")
	end

	-- Плавление (Лава, Вулкан): второй способ сделать цель проводящей. Снимается
	-- вместе с последним стеком самого Плавления (см. тик-цикл ниже).
	if elementData.conductive then
		target:SetAttribute("Molten", true)
	end

	-- Физические силы. Складываются через результирующую, поэтому никакого «или»
	-- между ними нет: элемент может и толкать, и тянуть — жук поедет туда, куда сильнее.
	if elementData.knockback and not elementData.knockback.radial then
		applyKnockback(target, elementData, damage)
	end

	if elementData.pull then
		applyPull(target, elementData, source)
	end

	if elementData.toss then
		applyToss(target, elementData)
	end

	if elementData.slowPercent or elementData.slowSpeedScale or elementData.slowGrowth then
		applySlow(target, elementData)
	end

	if elementData.blind then
		applyBlind(target, elementData)
	end

	if elementData.slowRamp then
		applyDrying(target, elementData)
	end

	if elementData.stun then
		-- Метка Пыли удлиняет и стан: срок — тот же род величины, что и у горения с замедлением.
		local durationScale = amplifier(target)
		applyStun(target, elementData.stun.duration * durationScale, elementData.stun.cooldown, elementData.name)
	end

	if elementData.debuff then
		applyDebuff(target, elementData)
	end

	if elementData.confusion then
		applyConfusion(target, elementData)
	end

	if elementData.breakthrough then
		applyBreakthrough(target, elementData)
	end

	if elementData.damageType == "overtime" then
		applyOvertime(target, elementData)
	end

	if elementData.scald then
		applyScald(target, elementData)
	end

	-- Катализатор — после своего горения, а не до: если элемент когда-нибудь и жжёт,
	-- и разгоняет, то его собственный стек ложится по прежним правилам, а разгон
	-- достаётся следующим — и своим, и чужим.
	if elementData.burnCatalyst then
		applyCatalyst(target, elementData)
	end

	if elementData.regen then
		applyRegen(target, elementData)
	end

	if elementData.contagion then
		applyInfection(target, elementData)
	end
end

-- Единый цикл тиков на весь модуль: раз в Effects.TICK_STEP обходит все активные эффекты
-- всех целей, вместо отдельной корутины на каждый стек. Он же ведёт засыхание Глины
-- и чистит то, что висит на цели без стеков: метки Пыли и Пороха, счётчики Дыма,
-- разгоны Кирпича, кулдауны стана. Запутывания и самого стана здесь нет — их сроки
-- короче тика, и гасит их тот, кто ведёт жука каждый кадр (EnemySpawner).
task.spawn(function()
	while true do
		local step = Effects.TICK_STEP
		task.wait(step)

		-- Зоны — списком, а не по цели: зона не принадлежит никому персонально.
		-- Зона Землетрясения здесь только чистится — она работает в момент удара
		-- (ZoneMultiplier). Зоны v4 действуют сами, и именно здесь это и происходит.
		local now = os.clock()
		for i = #zones, 1, -1 do
			local zone = zones[i]
			if now >= zone.expires or (zone.charges and zone.charges <= 0) then
				table.remove(zones, i)
			elseif zone.damagePerSecond or zone.spread or zone.slowElement or zone.dries then
				-- Урон зоны идёт мимо брони — это огонь на земле, а не удар снаряда,
				-- и растёт от возраста зоны (Звезда), поэтому считается каждый тик заново.
				local perSecond = zone.damagePerSecond
					and (zone.damagePerSecond + (zone.growth or 0) * (now - zone.born))
					or nil

				for _, found in enemiesAround(zone.position, zone.radius, nil) do
					local enemy = found.enemy

					if perSecond then
						local dealt = math.max(1, math.floor(perSecond * step + 0.5))
						local hp = math.max(0, (enemy:GetAttribute("HP") or 0) - dealt)
						enemy:SetAttribute("HP", hp)
						DamageDealtRemote:FireAllClients(enemy:GetPivot().Position, dealt, false)
					end

					-- Засуха: «эффект мокрости исчезает в ней».
					local slow = slows[enemy]
					if zone.dries and slow and slow.wet then
						slows[enemy] = nil
						enemy:SetAttribute("Wet", false)
						refreshSlow(enemy)
					end

					-- Чужой эффект зона вешает раз в секунду, а не каждый тик: иначе
					-- кислотное облако клало бы по четыре стека в секунду.
					if (zone.spread or zone.slowElement)
						and now - (zone.applied[enemy] or 0) >= ZONE_APPLY_INTERVAL
					then
						-- Зона пепла (Уголь) метит ограниченное число жуков и исчезает,
						-- когда метки кончились, а не по таймеру: повторно одного и того
						-- же жука она не трогает и заряд на него не тратит.
						local charged = not zone.charges or zone.applied[enemy] == nil
						if charged then
							if zone.charges then
								zone.charges -= 1
							end
							zone.applied[enemy] = now
							if zone.spread then
								Effects.Apply(enemy, zone.spread, 0)
							end
							if zone.slowElement then
								applySlow(enemy, zone.slowElement)
							end
						end
					end
				end
			end
		end

		-- истечение замедлений — в том же цикле, без отдельной корутины на каждую цель
		for target, slow in pairs(slows) do
			if not target.Parent or (target:GetAttribute("HP") or 0) <= 0 then
				slows[target] = nil
			else
				slow.remaining -= step
				if slow.remaining <= 0 then
					slows[target] = nil
					-- Вместе с Мокрым уходит и проводимость: высохшая цель больше не цепь
					-- для Молнии и не ловит Электронность.
					if slow.wet then
						target:SetAttribute("Wet", false)
					end
					refreshSlow(target)
					print(("[Эффект] замедление на %s спало"):format(target.Name))
				end
			end
		end

		-- Слепота Песка — чистый таймер, без отдельной силы: истёк — сняли атрибут.
		for target, until_ in pairs(blinds) do
			if not target.Parent or (target:GetAttribute("HP") or 0) <= 0 or os.clock() >= until_ then
				blinds[target] = nil
				if target.Parent then
					target:SetAttribute("Blinded", false)
				end
			end
		end

		-- Засыхание (Глина): глубина растёт сама, пока цель под эффектом. Дошло до потолка —
		-- жук засох (стан), и нарастание начинается заново: иначе одна глиняная турель
		-- держала бы цель в стане до конца забега.
		for target, drying in pairs(dryings) do
			if not target.Parent or (target:GetAttribute("HP") or 0) <= 0 then
				dryings[target] = nil
			else
				local plan = drying.plan
				drying.remaining -= step

				if drying.remaining <= 0 then
					dryings[target] = nil
					refreshSlow(target)
					print(("[Эффект] %s на %s: засыхание спало"):format(drying.name, target.Name))
				elseif drying.percent < plan.max then
					drying.percent = math.min(plan.max, drying.percent + plan.step * step)
					refreshSlow(target)

					if drying.percent >= plan.max then
						applyStun(target, plan.freezeDuration, 0, drying.name)
						drying.percent = plan.start
						refreshSlow(target)
					end
				end
			end
		end

		-- Порча Кислоты живёт своим сроком: броня и урон цели возвращаются к своим,
		-- даже если кислотная турель к тому времени уже снесена.
		for target, debuff in pairs(debuffs) do
			if not target.Parent or (target:GetAttribute("HP") or 0) <= 0 then
				debuffs[target] = nil
			else
				debuff.remaining -= step
				if debuff.remaining <= 0 then
					debuffs[target] = nil
					target:SetAttribute("ArmorShred", 0)
					target:SetAttribute("Weakened", 0)
					print(("[Эффект] порча на %s спала"):format(target.Name))
				end
			end
		end

		-- Анти-реген и разгон регена живут своим сроком — кроме Яда, который необратим
		-- и снимается только вместе с самим жуком.
		for target, regen in pairs(regens) do
			if not target.Parent or (target:GetAttribute("HP") or 0) <= 0 then
				regens[target] = nil
			elseif not regen.permanent then
				regen.remaining -= step
				if regen.remaining <= 0 then
					regens[target] = nil
					target:SetAttribute("RegenScale", 1)
				end
			end
		end

		-- Метка Грунта единственная со сроком; Ржавчина и Пепел висят до смерти или до смывки.
		for target, byKind in pairs(kindMarks) do
			if not target.Parent or (target:GetAttribute("HP") or 0) <= 0 then
				kindMarks[target] = nil
			else
				for kind, entry in pairs(byKind) do
					if entry.expires and os.clock() >= entry.expires then
						byKind[kind] = nil
						target:SetAttribute(MARK_ATTRIBUTE[kind], false)
					end
				end
			end
		end

		-- Болотный расходится сам: каждый заражённый заражает соседей по контакту,
		-- и те передают дальше без затухания — цепочка бесконечная. Переданный эффект
		-- слабее исходного (свой slowPercent в contagion), но заразный так же.
		for target, infection in pairs(infections) do
			if not target.Parent or (target:GetAttribute("HP") or 0) <= 0 then
				infections[target] = nil
			else
				local carrier = {
					name = infection.name,
					slowPercent = infection.plan.slowPercent,
					slowDuration = infection.plan.duration,
					contagion = infection.plan,
				}
				for _, found in enemiesAround(target:GetPivot().Position, infection.plan.radius, target) do
					if not infections[found.enemy] then
						applySlow(found.enemy, carrier)
						applyInfection(found.enemy, carrier)
					end
				end
			end
		end

		-- Метки Пыли и Пороха срока не имеют и снимаются только вместе с целью, разгон
		-- Кирпича и кулдаун стана — тоже: здесь только уборка, иначе таблицы держали бы
		-- ссылки на всех убитых жуков забега. Счётчики притяжения и катализаторы — туда же.
		for _, byTarget in { marks, primed, ramps, stunCooldowns, growingSlows, pulls, catalysts } do
			for target in pairs(byTarget) do
				if not target.Parent or (target:GetAttribute("HP") or 0) <= 0 then
					byTarget[target] = nil
				end
			end
		end

		-- Накопление Дыма слетает медленно и незаметно: только если цель долго живёт,
		-- не получая попаданий дымом. Секундной точности для порога в несколько секунд довольно.
		for target, byElement in pairs(counters) do
			if not target.Parent or (target:GetAttribute("HP") or 0) <= 0 then
				counters[target] = nil
			else
				for elementData, entry in pairs(byElement) do
					if os.clock() - entry.lastHit >= elementData.breakthrough.resetAfter then
						print(("[Эффект] %s на %s: накопление слетело (было %d из %d)")
							:format(elementData.name, target.Name, entry.hits, elementData.breakthrough.hits))
						byElement[elementData] = nil
					end
				end
				if next(byElement) == nil then
					counters[target] = nil
				end
			end
		end

		for target, byElement in pairs(effects) do
			local hp = target.Parent and (target:GetAttribute("HP") or 0) or 0

			if hp <= 0 then
				-- цель умерла не от тика (например, добита в упор) — снимаем всё, что на ней горело
				for elementData, entry in pairs(byElement) do
					print(("[Эффект] %s на %s: цель недоступна (умерла или пропала), снимаю %d активных стек(ов)")
						:format(elementData.name, target.Name, #entry.stacks))
				end
				if target.Parent then
					target:SetAttribute("Burning", false)
				end
				effects[target] = nil
			else
				for elementData, entry in pairs(byElement) do
					local stacks = entry.stacks

					-- Стек тикает не каждый шаг цикла, а раз в свой entry.interval: горение — раз
					-- в секунду, кровотечение и кислота чаще. Остаток накопленного времени
					-- не обнуляется, а вычитается: иначе интервал, не кратный шагу, медленно уезжал бы.
					entry.elapsed += step
					if entry.elapsed >= entry.interval and #stacks > 0 then
						entry.elapsed -= entry.interval

						-- Сумма по стекам, а не количество × цифра из таблицы: стеки, легшие под
						-- меткой Пыли, тикают сильнее тех, что легли до неё. Броня режет сумму
						-- целиком, один раз за тик каждого элемента, а не каждый стек по отдельности.
						local totalDamage = 0
						for _, stack in stacks do
							totalDamage += stack.damagePerTick
						end
						totalDamage = Effects.ApplyArmor(target, totalDamage, elementData)

						hp = math.max(0, hp - totalDamage)
						target:SetAttribute("HP", hp)
						DamageDealtRemote:FireAllClients(target:GetPivot().Position, totalDamage, false)
						print(("[Эффект] %s тикает на %s: %d стек(ов), суммарно %d урона, осталось %d HP")
							:format(elementData.name, target.Name, #stacks, totalDamage, hp))
					end

					for i = #stacks, 1, -1 do
						stacks[i].remaining -= step
						if stacks[i].remaining <= 0 then
							table.remove(stacks, i)
						end
					end

					if #stacks == 0 then
						byElement[elementData] = nil
						-- Плавление кончилось — цель больше не проводит ток.
						if elementData.conductive then
							target:SetAttribute("Molten", false)
						end
						if next(byElement) == nil then
							target:SetAttribute("Burning", false)
						end
						-- Обугливание и кровь снимаются, только когда не осталось ни одного такого элемента.
						if elementData.chars or elementData.bleeds then
							local chars, bleeds = false, false
							for other in pairs(byElement) do
								chars = chars or other.chars == true
								bleeds = bleeds or other.bleeds == true
							end
							target:SetAttribute("Scorched", chars or nil)
							target:SetAttribute("Bleeding", bleeds or nil)
						end
					end

					if hp <= 0 then
						print(("[Эффект] %s: цель %s умерла во время горения, снимаю оставшиеся эффекты")
							:format(elementData.name, target.Name))
						break
					end
				end

				if hp <= 0 or next(byElement) == nil then
					effects[target] = nil
				end
			end
		end
	end
end)

return Effects
