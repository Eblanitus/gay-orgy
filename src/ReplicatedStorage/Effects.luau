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

-- Таблица элемента -> его ключ: турели передают в HitDamage саму таблицу (Elements[key]).
local elementKeys = {}
for key, data in Elements do
	if type(data) == "table" then
		elementKeys[data] = key
	end
end
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
-- Наложение эффектов на жука: зоны, метки, замедление, оглушение, ослепление, дебаффы, урон по времени, отбрасывание и притяжение — в модуле EffectsDebuffs.
local EffectsDebuffsExports = require(script.Parent:WaitForChild("EffectsDebuffs"))({Effects = Effects, marks = marks, Arena = Arena, Debris = Debris, Elements = Elements, ZONE_APPLY_INTERVAL = ZONE_APPLY_INTERVAL, zones = zones, kindMarks = kindMarks, MARK_ATTRIBUTE = MARK_ATTRIBUTE, catalysts = catalysts, effects = effects, regens = regens, infections = infections, slows = slows, dryings = dryings, stunCooldowns = stunCooldowns, blinds = blinds, growingSlows = growingSlows, debuffs = debuffs, counters = counters, DamageDealtRemote = DamageDealtRemote, pulls = pulls, ramps = ramps})
local rampMultiplier = EffectsDebuffsExports.rampMultiplier
local speedScaledValue = EffectsDebuffsExports.speedScaledValue
local damageAround = EffectsDebuffsExports.damageAround
local enemiesAround = EffectsDebuffsExports.enemiesAround
local applyStun = EffectsDebuffsExports.applyStun
local corpseRadius = EffectsDebuffsExports.corpseRadius
local spawnZone = EffectsDebuffsExports.spawnZone
local applyRadialKnockback = EffectsDebuffsExports.applyRadialKnockback
local applyMark = EffectsDebuffsExports.applyMark
local applyKindMark = EffectsDebuffsExports.applyKindMark
local washMark = EffectsDebuffsExports.washMark
local applyKnockback = EffectsDebuffsExports.applyKnockback
local applyPull = EffectsDebuffsExports.applyPull
local applyToss = EffectsDebuffsExports.applyToss
local applySlow = EffectsDebuffsExports.applySlow
local applyBlind = EffectsDebuffsExports.applyBlind
local applyDrying = EffectsDebuffsExports.applyDrying
local amplifier = EffectsDebuffsExports.amplifier
local applyDebuff = EffectsDebuffsExports.applyDebuff
local applyConfusion = EffectsDebuffsExports.applyConfusion
local applyBreakthrough = EffectsDebuffsExports.applyBreakthrough
local applyOvertime = EffectsDebuffsExports.applyOvertime
local applyScald = EffectsDebuffsExports.applyScald
local applyCatalyst = EffectsDebuffsExports.applyCatalyst
local applyRegen = EffectsDebuffsExports.applyRegen
local applyInfection = EffectsDebuffsExports.applyInfection
local refreshSlow = EffectsDebuffsExports.refreshSlow
function Effects.HitDamage(target, elementData, damage)
	-- Кто попал последним — тому и убийство в счёт справочника (KillStats, Mastery).
	-- Отсюда, а не из каждой турели: через HitDamage проходит любое попадание снаряда и зоны.
	local elementKey = elementData and elementKeys[elementData]
	if elementKey then
		target:SetAttribute("LastElement", elementKey)
	end
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
