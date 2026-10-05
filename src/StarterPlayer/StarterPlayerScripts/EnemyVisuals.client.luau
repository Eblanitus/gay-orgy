-- HP-полоска и метки эффектов над каждым врагом. Чисто клиентская визуализация —
-- читает атрибуты HP/MaxHP, состояния стихий (Burning, SlowPercent, Wet, Stunned и т.д.),
-- которые сервер уже ставит на врага и которые реплицируются автоматически —
-- отдельный RemoteEvent для этого не нужен. Метку Пороха (атрибут Primed) красит
-- EnemyRender — он же строит видимое тело.
--
-- Всё крепится к видимому телу (модель Visual внутри жука, см. EnemyRender), а не к
-- серверному якорю: якорь приходит рывками, и полоска дрожала бы над плавным телом.
--
-- Состояния стихий (#285) — у каждого свой почерк из частиц (таблица AURAS ниже): горение —
-- языки пламени с углями и копотью, кровотечение — капли, кислота — шипящие пузыри, яд и
-- анти-реген — ядовитая испарина, ошпаривание — пар, Плавление — капли лавы, Мокрый — капель,
-- замедление — снежинки и холодный туман, засыхание Глины — осыпь сухой глины, Туман —
-- клубы вокруг головы, слепота Песка — песчаный вихрь, болотная зараза — тина и мошкара,
-- метки Ржавчины, Пепла, Почвы и Пыли — свои хлопья. Стан — общая обводка (лёд или глина по
-- источнику) и разовый выброс осколков. Излучатели на жука собираются только при первом
-- его состоянии: целая толпа без эффектов не держит ни одного лишнего объекта.
-- Урон по времени любого рода сервер метит одним атрибутом Burning, а почерк выбирается
-- по уточняющим (Scorched, Bleeding, Molten, ArmorShred, RegenScale).
--
-- Метки при смерти (атрибут DeathMarks) — ряд квадратиков цвета элементов над полоской:
-- их может висеть несколько разом, и игрок должен видеть, чем жук станет после смерти.
--
-- Отклик на урон (#418): вспышка тела при попадании — та же общая обводка EffectMark
-- (новых Highlight нет: движок рисует не больше 31 обводки разом, и толпа съела бы лимит),
-- полоска HP появляется только после первого урона (целая толпа не рябит плашками), а
-- снятый кусок полоски ещё миг висит светлым «следом» и потом съезжает — видно, сколько
-- сняло этим ударом. Смерть — короткий хлопок пыли и искр из одного общего излучателя
-- на клиенте (Remotes.EnemyDied): сколько бы жуков ни умерло разом, деталей не прибавится.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")

local Elements = require(ReplicatedStorage:WaitForChild("Elements"))
-- Цвета полоски HP — из общей палитры интерфейса.
local Theme = require(script.Parent:WaitForChild("UITheme"))

local enemiesFolder = Workspace:WaitForChild("Enemies")
local EnemyDiedRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("EnemyDied")

-- Вспышка при попадании. Сила — доля макс. HP, снятая ударом: тики горения дают едва
-- заметное мигание, тяжёлый удар — почти белое тело. FLASH_FULL — доля, с которой
-- вспышка уже полная.
local FLASH_TIME = 0.1
local FLASH_COLOR = Color3.new(1, 1, 1)
local FLASH_FAINT = 0.75 -- FillTransparency самой слабой вспышки
local FLASH_STRONG = 0.2 -- FillTransparency полной вспышки
local FLASH_FULL = 0.2

-- След урона на полоске: сколько висит и за сколько съезжает к новому HP.
local TRAIL_HOLD = 0.25
local TRAIL_SLIDE = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TRAIL_COLOR = Color3.fromRGB(255, 235, 200)

-- Почерки стихий. Встроенные текстуры частиц движка — своих ассетов не грузим.
local TEX_FIRE = "rbxasset://textures/particles/fire_main.dds"
local TEX_SPARK = "rbxasset://textures/particles/sparkles_main.dds"
local TEX_SMOKE = "rbxasset://textures/particles/smoke_main.dds"

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

local function fade(from, to)
	return NumberSequence.new({
		NumberSequenceKeypoint.new(0, from),
		NumberSequenceKeypoint.new(1, to or 1),
	})
end

-- Проявиться, подержаться, исчезнуть: частицы не выскакивают из ниоткуда.
local function pulse(peak)
	return NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.15, peak),
		NumberSequenceKeypoint.new(0.7, peak),
		NumberSequenceKeypoint.new(1, 1),
	})
end

local function grade(...)
	local colors = { ... }
	if #colors == 1 then
		return ColorSequence.new(colors[1])
	end
	local keys = {}
	for i, color in colors do
		table.insert(keys, ColorSequenceKeypoint.new((i - 1) / (#colors - 1), color))
	end
	return ColorSequence.new(keys)
end

local function num(attribute)
	return function(enemy)
		local value = enemy:GetAttribute(attribute)
		return type(value) == "number" and value or 0
	end
end
local slowOf = num("SlowPercent")
local regenOf = function(enemy)
	local value = enemy:GetAttribute("RegenScale")
	return type(value) == "number" and value or 1
end
local function corroded(enemy)
	return num("ArmorShred")(enemy) > 0 or num("Weakened")(enemy) > 0
end
local function on(enemy, attribute)
	return enemy:GetAttribute(attribute) == true
end

-- Каждая запись: attributes — на что подписаться, active(enemy) — включён ли почерк,
-- rate(enemy) — необязательная сила (по глубине эффекта), emitters — частицы. Size у частиц
-- задан для жука масштаба 1 и умножается на масштаб конкретного клона.
local AURAS = {
	{
		name = "Burn", -- Горение: пламя, искры-угли вверх, копоть
		attributes = { "Burning", "Scorched", "Molten" },
		active = function(e)
			return on(e, "Burning") and on(e, "Scorched") and not on(e, "Molten")
		end,
		emitters = {
			{
				Texture = TEX_FIRE,
				Color = grade(rgb(255, 240, 150), rgb(255, 150, 40), rgb(200, 50, 20)),
				LightEmission = 0.9,
				Size = { 1.1, 0.2 },
				Transparency = fade(0.15),
				Lifetime = NumberRange.new(0.35, 0.6),
				Speed = NumberRange.new(1.5, 3),
				Acceleration = Vector3.new(0, 7, 0),
				Rotation = NumberRange.new(0, 360),
				RotSpeed = NumberRange.new(-120, 120),
				Rate = 16,
			},
			{
				Texture = TEX_SPARK,
				Color = grade(rgb(255, 220, 120), rgb(255, 90, 20)),
				LightEmission = 1,
				Size = { 0.22, 0 },
				Lifetime = NumberRange.new(0.7, 1.1),
				Speed = NumberRange.new(2, 5),
				SpreadAngle = Vector2.new(35, 35),
				EmissionDirection = Enum.NormalId.Top,
				Acceleration = Vector3.new(0, 3, 0),
				Drag = 1.5,
				Rate = 5,
			},
			{
				Texture = TEX_SMOKE,
				Color = grade(rgb(60, 50, 45)),
				Size = { 0.8, 2.2 },
				Transparency = pulse(0.65),
				Lifetime = NumberRange.new(0.9, 1.3),
				Speed = NumberRange.new(1, 2),
				Acceleration = Vector3.new(0, 4, 0),
				Rotation = NumberRange.new(0, 360),
				RotSpeed = NumberRange.new(-40, 40),
				Rate = 2.5,
			},
		},
	},
	{
		name = "Melt", -- Плавление (Лава, Вулкан): тяжёлые светящиеся капли лавы и жар
		attributes = { "Molten" },
		active = function(e)
			return on(e, "Molten")
		end,
		emitters = {
			{
				Texture = TEX_SMOKE,
				Color = grade(rgb(255, 210, 90), rgb(255, 90, 10), rgb(120, 25, 10)),
				LightEmission = 1,
				Size = { 0.45, 0.2 },
				Transparency = fade(0, 0.3),
				Lifetime = NumberRange.new(0.5, 0.8),
				Speed = NumberRange.new(0.5, 1.5),
				SpreadAngle = Vector2.new(25, 25),
				EmissionDirection = Enum.NormalId.Bottom,
				Acceleration = Vector3.new(0, -28, 0),
				Rate = 9,
			},
			{
				Texture = TEX_FIRE,
				Color = grade(rgb(255, 120, 30), rgb(150, 30, 10)),
				LightEmission = 0.7,
				Size = { 0.9, 1.6 },
				Transparency = pulse(0.7),
				Lifetime = NumberRange.new(0.5, 0.8),
				Speed = NumberRange.new(0.5, 1),
				Acceleration = Vector3.new(0, 4, 0),
				Rotation = NumberRange.new(0, 360),
				Rate = 5,
			},
		},
	},
	{
		name = "Bleed", -- Кровотечение (Металл): тёмные капли, падают под жука
		attributes = { "Burning", "Bleeding" },
		active = function(e)
			return on(e, "Burning") and on(e, "Bleeding")
		end,
		emitters = {
			{
				Texture = TEX_SMOKE,
				Color = grade(rgb(170, 20, 25), rgb(90, 5, 10)),
				Size = { 0.3, 0.18 },
				Transparency = fade(0, 0.2),
				Lifetime = NumberRange.new(0.45, 0.7),
				Speed = NumberRange.new(1, 2.5),
				SpreadAngle = Vector2.new(60, 60),
				EmissionDirection = Enum.NormalId.Top,
				Acceleration = Vector3.new(0, -35, 0),
				Rate = 10,
			},
		},
	},
	{
		name = "Acid", -- Кислота: шипящие едко-зелёные пузырьки и дымок разъедания
		attributes = { "ArmorShred", "Weakened" },
		active = corroded,
		rate = function(e)
			return 0.5 + math.clamp(num("ArmorShred")(e), 0, 1)
		end,
		emitters = {
			{
				Texture = TEX_SPARK,
				Color = grade(rgb(220, 255, 90), rgb(120, 220, 40)),
				LightEmission = 0.6,
				Size = { 0.12, 0.35 },
				Transparency = pulse(0.15),
				Lifetime = NumberRange.new(0.35, 0.6),
				Speed = NumberRange.new(0.5, 1.5),
				SpreadAngle = Vector2.new(180, 180),
				Acceleration = Vector3.new(0, 5, 0),
				Rate = 14,
			},
			{
				Texture = TEX_SMOKE,
				Color = grade(rgb(190, 230, 110)),
				Size = { 0.6, 1.6 },
				Transparency = pulse(0.75),
				Lifetime = NumberRange.new(0.7, 1),
				Speed = NumberRange.new(0.5, 1.5),
				Acceleration = Vector3.new(0, 3, 0),
				Rotation = NumberRange.new(0, 360),
				Rate = 3,
			},
		},
	},
	{
		name = "Toxin", -- Яд и прочий анти-реген: густая фиолетово-зелёная испарина
		attributes = { "RegenScale" },
		active = function(e)
			return regenOf(e) < 1
		end,
		rate = function(e)
			return 0.4 + (1 - math.clamp(regenOf(e), 0, 1))
		end,
		emitters = {
			{
				Texture = TEX_SMOKE,
				Color = grade(rgb(150, 80, 190), rgb(90, 160, 70)),
				Size = { 0.5, 1.4 },
				Transparency = pulse(0.6),
				Lifetime = NumberRange.new(0.8, 1.2),
				Speed = NumberRange.new(0.3, 0.8),
				SpreadAngle = Vector2.new(180, 180),
				Acceleration = Vector3.new(0, 1.5, 0),
				Rotation = NumberRange.new(0, 360),
				RotSpeed = NumberRange.new(-30, 30),
				Rate = 5,
			},
			{
				Texture = TEX_SPARK,
				Color = grade(rgb(200, 120, 255)),
				LightEmission = 0.5,
				Size = { 0.15, 0 },
				Lifetime = NumberRange.new(0.6, 0.9),
				Speed = NumberRange.new(0.5, 1),
				SpreadAngle = Vector2.new(180, 180),
				Acceleration = Vector3.new(0, 2, 0),
				Rate = 4,
			},
		},
	},
	{
		name = "Scald", -- Ошпаривание (Гейзер) и прочий урон по времени без своего почерка: пар
		attributes = { "Burning", "Scorched", "Bleeding", "Molten", "ArmorShred", "Weakened", "RegenScale" },
		active = function(e)
			return on(e, "Burning") and not on(e, "Scorched") and not on(e, "Bleeding")
				and not on(e, "Molten") and not corroded(e) and regenOf(e) >= 1
		end,
		emitters = {
			{
				Texture = TEX_SMOKE,
				Color = grade(rgb(245, 250, 255)),
				Size = { 0.6, 2 },
				Transparency = pulse(0.5),
				Lifetime = NumberRange.new(0.6, 0.9),
				Speed = NumberRange.new(2, 3.5),
				SpreadAngle = Vector2.new(20, 20),
				EmissionDirection = Enum.NormalId.Top,
				Rotation = NumberRange.new(0, 360),
				RotSpeed = NumberRange.new(-60, 60),
				Drag = 1,
				Rate = 8,
			},
		},
	},
	{
		name = "Wet", -- Мокрый: редкая капель и блестящие брызги
		attributes = { "Wet" },
		active = function(e)
			return on(e, "Wet")
		end,
		emitters = {
			{
				Texture = TEX_SMOKE,
				Color = grade(rgb(150, 210, 255), rgb(70, 150, 230)),
				LightEmission = 0.3,
				Size = { 0.22, 0.12 },
				Transparency = fade(0.1, 0.4),
				Lifetime = NumberRange.new(0.4, 0.6),
				Speed = NumberRange.new(0, 0.5),
				Acceleration = Vector3.new(0, -30, 0),
				Rate = 7,
			},
			{
				Texture = TEX_SPARK,
				Color = grade(rgb(220, 240, 255)),
				LightEmission = 0.8,
				Size = { 0.2, 0 },
				Lifetime = NumberRange.new(0.2, 0.35),
				Speed = NumberRange.new(0, 0.3),
				Rate = 3,
			},
		},
	},
	{
		name = "Frost", -- Замедление: снежинки и стелющийся холодный туман, гуще при сильном
		attributes = { "SlowPercent", "Blinded" },
		active = function(e)
			-- Песок замедляет своей слепотой: у него свой вихрь, снег там был бы чужим.
			return slowOf(e) > 0 and not on(e, "Blinded")
		end,
		rate = function(e)
			return 0.4 + math.clamp(slowOf(e), 0, 1) * 1.6
		end,
		emitters = {
			{
				Texture = TEX_SPARK,
				Color = grade(rgb(235, 250, 255), rgb(150, 210, 255)),
				LightEmission = 0.7,
				Size = { 0.28, 0.1 },
				Transparency = pulse(0.1),
				Lifetime = NumberRange.new(0.8, 1.2),
				Speed = NumberRange.new(0.5, 1.5),
				SpreadAngle = Vector2.new(180, 180),
				Acceleration = Vector3.new(0, -3, 0),
				Rotation = NumberRange.new(0, 360),
				RotSpeed = NumberRange.new(-90, 90),
				Rate = 6,
			},
			{
				Texture = TEX_SMOKE,
				Color = grade(rgb(200, 235, 255)),
				Size = { 1, 2.4 },
				Transparency = pulse(0.75),
				Lifetime = NumberRange.new(0.8, 1.1),
				Speed = NumberRange.new(0.3, 0.8),
				SpreadAngle = Vector2.new(180, 30),
				Acceleration = Vector3.new(0, -2, 0),
				Rotation = NumberRange.new(0, 360),
				Rate = 2,
			},
		},
	},
	{
		name = "Clay", -- Засыхание Глины: осыпаются сухие комочки и пыль глины
		attributes = { "Drying" },
		active = function(e)
			return on(e, "Drying")
		end,
		emitters = {
			{
				Texture = TEX_SMOKE,
				Color = grade(rgb(200, 140, 90), rgb(150, 95, 60)),
				Size = { 0.25, 0.2 },
				Transparency = fade(0, 0.3),
				Lifetime = NumberRange.new(0.4, 0.6),
				Speed = NumberRange.new(0.5, 1.5),
				SpreadAngle = Vector2.new(70, 70),
				EmissionDirection = Enum.NormalId.Top,
				Acceleration = Vector3.new(0, -30, 0),
				Rate = 6,
			},
			{
				Texture = TEX_SMOKE,
				Color = grade(rgb(215, 175, 130)),
				Size = { 0.6, 1.4 },
				Transparency = pulse(0.75),
				Lifetime = NumberRange.new(0.5, 0.8),
				Speed = NumberRange.new(0.3, 0.8),
				SpreadAngle = Vector2.new(180, 180),
				Rotation = NumberRange.new(0, 360),
				Rate = 2,
			},
		},
	},
	{
		name = "Fog", -- Запутывание Тумана: серо-сиреневые клубы, вьются над головой
		attributes = { "Confused", "Blinded" },
		active = function(e)
			return on(e, "Confused") and not on(e, "Blinded")
		end,
		emitters = {
			{
				Texture = TEX_SMOKE,
				Color = grade(rgb(215, 215, 235), rgb(170, 160, 200)),
				Size = { 0.8, 1.8 },
				Transparency = pulse(0.5),
				Lifetime = NumberRange.new(1, 1.4),
				Speed = NumberRange.new(1, 2),
				SpreadAngle = Vector2.new(180, 20),
				EmissionDirection = Enum.NormalId.Top,
				Acceleration = Vector3.new(0, -1, 0),
				Rotation = NumberRange.new(0, 360),
				RotSpeed = NumberRange.new(-150, 150),
				Drag = 1.5,
				Rate = 6,
			},
		},
	},
	{
		name = "Sand", -- Слепота Песка: песчинки вихрем и пыльное облачко
		attributes = { "Blinded" },
		active = function(e)
			return on(e, "Blinded")
		end,
		emitters = {
			{
				Texture = TEX_SPARK,
				Color = grade(rgb(240, 210, 140), rgb(200, 160, 90)),
				Size = { 0.16, 0.08 },
				Lifetime = NumberRange.new(0.4, 0.7),
				Speed = NumberRange.new(3, 5),
				SpreadAngle = Vector2.new(180, 40),
				Acceleration = Vector3.new(0, -6, 0),
				Drag = 2,
				Rate = 18,
			},
			{
				Texture = TEX_SMOKE,
				Color = grade(rgb(225, 195, 140)),
				Size = { 0.8, 2 },
				Transparency = pulse(0.65),
				Lifetime = NumberRange.new(0.6, 0.9),
				Speed = NumberRange.new(1, 2),
				SpreadAngle = Vector2.new(180, 30),
				Rotation = NumberRange.new(0, 360),
				RotSpeed = NumberRange.new(-120, 120),
				Rate = 3,
			},
		},
	},
	{
		name = "Swamp", -- Болотная зараза: тина пузырями и вьющаяся мошкара
		attributes = { "Infected" },
		active = function(e)
			return on(e, "Infected")
		end,
		emitters = {
			{
				Texture = TEX_SMOKE,
				Color = grade(rgb(110, 140, 60), rgb(70, 90, 40)),
				Size = { 0.2, 0.45 },
				Transparency = pulse(0.25),
				Lifetime = NumberRange.new(0.5, 0.8),
				Speed = NumberRange.new(0.3, 0.8),
				SpreadAngle = Vector2.new(180, 180),
				Acceleration = Vector3.new(0, 2, 0),
				Rate = 5,
			},
			{
				Texture = TEX_SPARK,
				Color = grade(rgb(40, 45, 30)),
				Size = { 0.1, 0.1 },
				Lifetime = NumberRange.new(0.8, 1.2),
				Speed = NumberRange.new(1.5, 3),
				SpreadAngle = Vector2.new(180, 180),
				Drag = 3,
				Rate = 4,
			},
		},
	},
	{
		name = "Rust", -- метка Ржавчины: рыжая окалина отслаивается и падает
		attributes = { "Rusted" },
		active = function(e)
			return on(e, "Rusted")
		end,
		emitters = {
			{
				Texture = TEX_SPARK,
				Color = grade(rgb(200, 100, 40), rgb(130, 60, 30)),
				Size = { 0.2, 0.15 },
				Lifetime = NumberRange.new(0.6, 0.9),
				Speed = NumberRange.new(0.5, 1),
				SpreadAngle = Vector2.new(180, 180),
				Acceleration = Vector3.new(0, -8, 0),
				Rotation = NumberRange.new(0, 360),
				RotSpeed = NumberRange.new(-200, 200),
				Rate = 5,
			},
		},
	},
	{
		name = "Ash", -- метка Пепла: серые хлопья медленно кружат вверх
		attributes = { "Ashed" },
		active = function(e)
			return on(e, "Ashed")
		end,
		emitters = {
			{
				Texture = TEX_SPARK,
				Color = grade(rgb(170, 170, 170), rgb(90, 90, 90)),
				Size = { 0.22, 0.1 },
				Transparency = pulse(0.2),
				Lifetime = NumberRange.new(1, 1.5),
				Speed = NumberRange.new(0.5, 1),
				SpreadAngle = Vector2.new(180, 180),
				Acceleration = Vector3.new(0, 1.5, 0),
				Rotation = NumberRange.new(0, 360),
				RotSpeed = NumberRange.new(-60, 60),
				Rate = 5,
			},
		},
	},
	{
		name = "Soil", -- метка Почвы: комья земли сыплются с панциря
		attributes = { "Soiled" },
		active = function(e)
			return on(e, "Soiled")
		end,
		emitters = {
			{
				Texture = TEX_SMOKE,
				Color = grade(rgb(110, 80, 50), rgb(70, 50, 30)),
				Size = { 0.3, 0.2 },
				Lifetime = NumberRange.new(0.4, 0.6),
				Speed = NumberRange.new(0.5, 1.5),
				SpreadAngle = Vector2.new(60, 60),
				EmissionDirection = Enum.NormalId.Top,
				Acceleration = Vector3.new(0, -30, 0),
				Rate = 5,
			},
		},
	},
	{
		name = "Dust", -- метка Пыли: светлые пылинки висят вокруг (к своей обводке в придачу)
		attributes = { "Amplified" },
		active = function(e)
			return on(e, "Amplified")
		end,
		emitters = {
			{
				Texture = TEX_SPARK,
				Color = grade(rgb(235, 220, 190)),
				LightEmission = 0.4,
				Size = { 0.14, 0.06 },
				Transparency = pulse(0.3),
				Lifetime = NumberRange.new(1, 1.6),
				Speed = NumberRange.new(0.3, 0.8),
				SpreadAngle = Vector2.new(180, 180),
				Drag = 1,
				Rate = 4,
			},
		},
	},
}

-- Разовый выброс при начале стана: лёд колется осколками, засохшая глина трескается крошкой.
local STUN_BURST = 12
local STUN_SHARDS = {
	Texture = TEX_SPARK,
	LightEmission = 0.8,
	Size = { 0.35, 0.05 },
	Lifetime = NumberRange.new(0.35, 0.55),
	Speed = NumberRange.new(6, 10),
	SpreadAngle = Vector2.new(180, 180),
	Acceleration = Vector3.new(0, -30, 0),
	Rotation = NumberRange.new(0, 360),
	RotSpeed = NumberRange.new(-300, 300),
	Drag = 2,
	Rate = 0,
}
local ICE_SHARDS = grade(rgb(240, 252, 255), rgb(140, 210, 255))
local CLAY_SHARDS = grade(rgb(215, 160, 110), rgb(140, 90, 55))

local function buildEmitter(spec, scale, parent)
	local emitter = Instance.new("ParticleEmitter")
	for key, value in spec do
		if key == "Size" then
			emitter.Size = fade(value[1] * scale, value[2] * scale)
		else
			emitter[key] = value
		end
	end
	if spec.Transparency == nil then
		emitter.Transparency = fade(0)
	end
	emitter.Enabled = false
	emitter.Parent = parent
	return emitter
end

local function attachVisuals(enemy)
	if not enemy:IsA("Model") then
		return
	end

	-- Видимое тело собирает EnemyRender чуть позже ChildAdded. Не дождались — крепим
	-- к якорю: без полоски враг оставаться не должен.
	local visual = enemy:WaitForChild("Visual", 5)
	local anchor = visual and visual.PrimaryPart or enemy.PrimaryPart
	if not anchor then
		return
	end

	local gui = Instance.new("BillboardGui")
	gui.Name = "HealthBar"
	gui.Size = UDim2.new(3, 0, 0.4, 0)
	-- Отступ над тушей растёт с масштабом вида (гигант ×3.0 иначе прячет плашку в тело).
	-- Атрибут Scale — фактический масштаб ЭТОГО клона (EnemySpawner.buildTemplateModel/
	-- buildEnemyModel): у Мини он случайный по scaleRange, и общего scale на весь тип для
	-- него не существует, поэтому таблица Enemies тут не годится.
	local enemyScale = enemy:GetAttribute("Scale") or 1
	gui.StudsOffset = Vector3.new(0, 2.2 * enemyScale, 0)
	gui.AlwaysOnTop = true
	gui.Adornee = anchor
	gui.Parent = anchor

	local back = Instance.new("Frame")
	back.BackgroundColor3 = Theme.color.hpBack
	back.BorderSizePixel = 0
	back.Size = UDim2.new(1, 0, 1, 0)
	back.Parent = gui

	-- Тёмный кант: на светлом полу и на светлом жуке полоска без него терялась.
	local edge = Instance.new("UIStroke")
	edge.Color = Theme.color.hpBack
	edge.Thickness = 1.5
	edge.Parent = back

	-- След урона — под заливкой: снятый кусок миг светится и съезжает (см. TRAIL_*).
	local trail = Instance.new("Frame")
	trail.Name = "Trail"
	trail.BorderSizePixel = 0
	trail.Size = UDim2.new(1, 0, 1, 0)
	trail.BackgroundColor3 = TRAIL_COLOR
	trail.Parent = back

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BorderSizePixel = 0
	fill.Size = UDim2.new(1, 0, 1, 0)
	fill.BackgroundColor3 = Theme.color.hpFull
	fill.Parent = back

	-- Метки при смерти — отдельная плашка чуть выше полоски HP, квадратик на метку.
	local markRow = Instance.new("BillboardGui")
	markRow.Name = "DeathMarks"
	markRow.Size = UDim2.new(3, 0, 0.35, 0)
	markRow.StudsOffset = Vector3.new(0, 2.2 * enemyScale + 0.5, 0)
	markRow.AlwaysOnTop = true
	markRow.Adornee = anchor
	markRow.Enabled = false
	markRow.Parent = anchor

	local markLayout = Instance.new("UIListLayout")
	markLayout.FillDirection = Enum.FillDirection.Horizontal
	markLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	markLayout.SortOrder = Enum.SortOrder.LayoutOrder
	markLayout.Padding = UDim.new(0.03, 0)
	markLayout.Parent = markRow

	-- Метка Пыли и стан — ОДИН Highlight на врага, а не два. Движок рисует только одну
	-- обводку на Adornee: два экземпляра на одной модели гасят друг друга, причём побеждал
	-- выключенный stunMark — метка Пыли не рисовалась вовсе, хотя Enabled у неё стоял,
	-- и Пыль выглядела как полностью неработающий элемент. Поэтому обводка одна, а какой
	-- ей быть, решает приоритет в updateMark.
	-- Occluded, а не AlwaysOnTop: обводка сквозь стены показывала бы жуков за пределами видимости.
	local effectMark = Instance.new("Highlight")
	effectMark.Name = "EffectMark"
	effectMark.Adornee = enemy
	effectMark.DepthMode = Enum.HighlightDepthMode.Occluded
	effectMark.Enabled = false
	effectMark.Parent = anchor

	-- Порядок = приоритет: побеждает первый подошедший стиль.
	-- Стан (Лёд, засыхание Глины) впереди: стоящий жук без метки читался бы как зависший
	-- поиск пути — та же беда, что с запутыванием, — и заливка у него плотнее, поэтому
	-- когда активны оба, виден стан. Метка Пыли перманентна, поэтому её форма не мигает
	-- и читается сразу: игрок должен видеть, по кому вторая турель работает вдвое.
	local markStyles = {
		-- Стан засохшей Глины — терракотовый: Лёд и Глина станят одинаково, но по-разному
		-- снимаются (Глину огонь обжигает в статую), и игроку надо их различать.
		{
			attribute = "Stunned",
			also = "Drying",
			fillColor = Color3.fromRGB(205, 140, 90),
			fillTransparency = 0.3,
			outlineColor = Color3.fromRGB(240, 190, 140),
		},
		{
			attribute = "Stunned",
			fillColor = Color3.fromRGB(190, 235, 255),
			fillTransparency = 0.35,
			outlineColor = Color3.fromRGB(235, 250, 255),
		},
		{
			attribute = "Amplified",
			fillColor = Color3.fromRGB(180, 165, 140),
			fillTransparency = 0.8,
			outlineColor = Color3.fromRGB(180, 165, 140),
		},
		-- Очищенный Мылом: последний в списке — эффектов на нём не бывает, и обводка
		-- у него постоянная. Зелёная, чтобы своего в общей свалке было видно сразу.
		{
			attribute = "Ally",
			fillColor = Color3.fromRGB(120, 230, 140),
			fillTransparency = 0.7,
			outlineColor = Color3.fromRGB(150, 255, 170),
		},
	}

	-- Полоска с первого урона: до него жук целый, и плашка над каждым из толпы — шум.
	-- Потом она остаётся до смерти, даже если реген дотянул HP до полного.
	-- Уже раненым приходит очищенный Мылом: тело и полоска у него собираются заново.
	local lastHp = enemy:GetAttribute("HP")
	local damaged = lastHp ~= nil and lastHp < (enemy:GetAttribute("MaxHP") or lastHp)
	local trailTween = nil
	local trailToken = 0
	local flashUntil = 0

	local function updateBar()
		gui.Enabled = damaged and not enemy:GetAttribute("Disguise")
	end

	-- Вспышка забирает общую обводку на FLASH_TIME, потом updateMark возвращает ту метку,
	-- что положена по атрибутам. Удары подряд продлевают вспышку, а не копят задержки.
	local function updateMark()
		if os.clock() < flashUntil then
			return
		end
		for _, style in markStyles do
			if enemy:GetAttribute(style.attribute) == true
				and (style.also == nil or enemy:GetAttribute(style.also) == true) then
				effectMark.FillColor = style.fillColor
				effectMark.FillTransparency = style.fillTransparency
				effectMark.OutlineColor = style.outlineColor
				effectMark.Enabled = true
				return
			end
		end
		effectMark.Enabled = false
	end

	local function flash(share)
		local strength = math.clamp(share / FLASH_FULL, 0, 1)
		effectMark.FillColor = FLASH_COLOR
		effectMark.FillTransparency = FLASH_FAINT + (FLASH_STRONG - FLASH_FAINT) * strength
		effectMark.OutlineColor = FLASH_COLOR
		effectMark.Enabled = true
		local untilAt = os.clock() + FLASH_TIME
		flashUntil = untilAt
		task.delay(FLASH_TIME, function()
			if flashUntil == untilAt and effectMark.Parent then
				flashUntil = 0
				updateMark()
			end
		end)
	end

	local function updateHealth()
		local hp = enemy:GetAttribute("HP") or 0
		local maxHp = enemy:GetAttribute("MaxHP") or hp
		local fraction = maxHp > 0 and math.clamp(hp / maxHp, 0, 1) or 0
		fill.Size = UDim2.new(fraction, 0, 1, 0)
		fill.BackgroundColor3 = Theme.color.hpLow:Lerp(Theme.color.hpFull, fraction)

		local last = lastHp
		lastHp = hp
		if last and hp < last then
			if not damaged then
				damaged = true
				updateBar()
			end
			if hp > 0 and maxHp > 0 and not enemy:GetAttribute("Disguise") then
				flash((last - hp) / maxHp)
			end
			-- След стоит на старом HP и съезжает после паузы; новый удар во время паузы
			-- переносит её, и след догоняет уже итог серии.
			trailToken += 1
			local token = trailToken
			if trailTween then
				trailTween:Cancel()
				trailTween = nil
			end
			task.delay(TRAIL_HOLD, function()
				if token ~= trailToken or not trail.Parent then
					return
				end
				trailTween = TweenService:Create(trail, TRAIL_SLIDE, { Size = fill.Size })
				trailTween:Play()
			end)
		else
			-- Реген и первый показ: следу нечего показывать.
			trailToken += 1
			if trailTween then
				trailTween:Cancel()
				trailTween = nil
			end
			trail.Size = fill.Size
		end
	end

	-- Почерки стихий: излучатели жука собираются при первом включении почерка и дальше
	-- только гасятся и зажигаются. Сила (rate) масштабирует табличный Rate каждого.
	local built = {}
	local function updateAura(aura)
		local active = aura.active(enemy)
		local emitters = built[aura]
		if not emitters then
			if not active then
				return
			end
			emitters = {}
			for _, spec in aura.emitters do
				table.insert(emitters, buildEmitter(spec, enemyScale, anchor))
			end
			built[aura] = emitters
		end
		local strength = active and aura.rate and aura.rate(enemy) or 1
		for i, emitter in emitters do
			emitter.Rate = aura.emitters[i].Rate * strength
			emitter.Enabled = active
		end
	end

	local shards = nil
	local wasStunned = enemy:GetAttribute("Stunned") == true
	local function updateStun()
		local stunned = enemy:GetAttribute("Stunned") == true
		if stunned and not wasStunned then
			shards = shards or buildEmitter(STUN_SHARDS, enemyScale, anchor)
			shards.Color = enemy:GetAttribute("Drying") == true and CLAY_SHARDS or ICE_SHARDS
			shards:Emit(STUN_BURST)
		end
		wasStunned = stunned
		updateMark()
	end

	-- Одна обводка на все метки, поэтому и обновление одно (updateMark выше, рядом со
	-- вспышкой): перебирает markStyles по порядку и берёт первый активный. Ни один не
	-- активен — обводки нет. Стан булевый отдельно от срока (StunnedUntil): срок считается
	-- по os.clock() сервера, и клиенту это число ничего не значит — тот же расклад, что
	-- у запутывания.

	-- Атрибут — ключи элементов через запятую (Effects.putDeathMark). Ряд пересобирается
	-- целиком: меток единицы, и меняются они редко — только новой меткой.
	local function updateDeathMarks()
		for _, child in markRow:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
		local list = enemy:GetAttribute("DeathMarks")
		local count = 0
		for key in string.gmatch(typeof(list) == "string" and list or "", "[^,]+") do
			local data = Elements[key]
			if data then
				count += 1
				local pip = Instance.new("Frame")
				pip.LayoutOrder = count
				pip.Size = UDim2.fromScale(1, 1)
				pip.BackgroundColor3 = data.color
				pip.BorderSizePixel = 0
				local square = Instance.new("UIAspectRatioConstraint")
				square.AspectRatio = 1
				square.DominantAxis = Enum.DominantAxis.Height
				square.Parent = pip
				local stroke = Instance.new("UIStroke")
				stroke.Color = Theme.color.hpBack
				stroke.Thickness = 1
				stroke.Parent = pip
				pip.Parent = markRow
			end
		end
		markRow.Enabled = count > 0 and not enemy:GetAttribute("Disguise")
	end

	-- Замаскированный Мимик полоской выдал бы себя: мешок с HP — не мешок.
	local function updateDisguise()
		updateBar()
		updateDeathMarks()
	end

	updateHealth()
	updateDisguise()
	for _, aura in AURAS do
		updateAura(aura)
	end
	updateMark()

	enemy:GetAttributeChangedSignal("HP"):Connect(updateHealth)
	enemy:GetAttributeChangedSignal("DeathMarks"):Connect(updateDeathMarks)
	enemy:GetAttributeChangedSignal("Disguise"):Connect(updateDisguise)
	-- Подписка по атрибутам, а не по почеркам: один атрибут (Burning, Blinded) решает сразу
	-- за несколько почерков, и каждому нужен свой пересчёт.
	local byAttribute = {}
	for _, aura in AURAS do
		for _, attribute in aura.attributes do
			byAttribute[attribute] = byAttribute[attribute] or {}
			table.insert(byAttribute[attribute], aura)
		end
	end
	for attribute, auras in byAttribute do
		enemy:GetAttributeChangedSignal(attribute):Connect(function()
			for _, aura in auras do
				updateAura(aura)
			end
		end)
	end
	enemy:GetAttributeChangedSignal("Amplified"):Connect(updateMark)
	enemy:GetAttributeChangedSignal("Stunned"):Connect(updateStun)
	enemy:GetAttributeChangedSignal("Drying"):Connect(updateMark)
	enemy:GetAttributeChangedSignal("Ally"):Connect(updateMark)
end

for _, enemy in enemiesFolder:GetChildren() do
	attachVisuals(enemy)
end
enemiesFolder.ChildAdded:Connect(attachVisuals)

-- Очищенные Мылом живут в своей папке (см. EnemySpawner). Переезд пересобирает тело
-- (EnemyRender), поэтому полоска и метки вешаются заново — на новое.
task.spawn(function()
	local alliesFolder = Workspace:WaitForChild("Allies")
	for _, ally in alliesFolder:GetChildren() do
		task.spawn(attachVisuals, ally)
	end
	alliesFolder.ChildAdded:Connect(attachVisuals)
end)

-- Хлопок смерти: пыль и искры в точке гибели. Излучатели одни на весь клиент и висят на
-- точке-Attachment в Terrain: на каждую смерть точка переезжает и выпускает горсть частиц
-- (Emit) — ни деталей, ни излучателей на жука. Сервер не шлёт EnemyDied застывшим статуей
-- Глины: у них смерти нет.
local POP_LIFT = 1 -- над серверной точкой жука: пыль из пола не видно
local POP_DUST = 6
local POP_SPARKS = 10
-- Потолок хлопков за короткое окно: взрыв по толпе кладёт десятки жуков в один кадр,
-- и частиц хватит с первых POP_BURST — остальные смерти и так видны трупами.
local POP_WINDOW = 0.1
local POP_BURST = 12

local popPoint = Instance.new("Attachment")
popPoint.Name = "DeathPop"
popPoint.Parent = Workspace.Terrain

local popDust = Instance.new("ParticleEmitter")
popDust.Name = "Dust"
popDust.Texture = "rbxasset://textures/particles/smoke_main.dds"
popDust.Color = ColorSequence.new(Color3.fromRGB(200, 195, 180), Color3.fromRGB(150, 145, 135))
popDust.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.35),
	NumberSequenceKeypoint.new(1, 1),
})
popDust.Size = NumberSequence.new(1, 2.6)
popDust.Lifetime = NumberRange.new(0.35, 0.55)
popDust.Speed = NumberRange.new(3, 6)
popDust.SpreadAngle = Vector2.new(180, 180)
popDust.Drag = 6
popDust.Rotation = NumberRange.new(0, 360)
popDust.RotSpeed = NumberRange.new(-90, 90)
popDust.Rate = 0
popDust.Parent = popPoint

local popSparks = Instance.new("ParticleEmitter")
popSparks.Name = "Sparks"
popSparks.Color = ColorSequence.new(Color3.fromRGB(255, 250, 230), Color3.fromRGB(255, 200, 120))
popSparks.LightEmission = 1
popSparks.Size = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.3),
	NumberSequenceKeypoint.new(1, 0),
})
popSparks.Lifetime = NumberRange.new(0.2, 0.35)
popSparks.Speed = NumberRange.new(9, 15)
popSparks.SpreadAngle = Vector2.new(70, 70)
popSparks.EmissionDirection = Enum.NormalId.Top
popSparks.Acceleration = Vector3.new(0, -40, 0)
popSparks.Drag = 3
popSparks.Rate = 0
popSparks.Parent = popPoint

local popWindowStart = 0
local popCount = 0

EnemyDiedRemote.OnClientEvent:Connect(function(position)
	if typeof(position) ~= "Vector3" then
		return
	end
	local now = os.clock()
	if now - popWindowStart > POP_WINDOW then
		popWindowStart = now
		popCount = 0
	end
	if popCount >= POP_BURST then
		return
	end
	popCount += 1
	popPoint.WorldPosition = position + Vector3.new(0, POP_LIFT, 0)
	popDust:Emit(POP_DUST)
	popSparks:Emit(POP_SPARKS)
end)
