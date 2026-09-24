-- HP-полоска и метки эффектов над каждым врагом. Чисто клиентская визуализация —
-- читает атрибуты HP/MaxHP/Burning/SlowPercent/Confused/Amplified/Stunned,
-- которые сервер уже ставит на врага и которые реплицируются автоматически —
-- отдельный RemoteEvent для этого не нужен. Метку Пороха (атрибут Primed) красит
-- EnemyRender — он же строит видимое тело.
--
-- Всё крепится к видимому телу (модель Visual внутри жука, см. EnemyRender), а не к
-- серверному якорю: якорь приходит рывками, и полоска дрожала бы над плавным телом.
--
-- Каждое остальное свойство — свой встроенный примитив, вкл/выкл по атрибуту: горение —
-- Fire, замедление — Sparkles, запутывание — Smoke, метка Пыли и стан — общий Highlight
-- (почему общий — см. EffectMark ниже); своих частиц по-прежнему ни для кого не собирается.
-- Урон по времени любого рода (горение, кровотечение, кислота) рисуется одним и тем же
-- огнём: атрибут Burning у них общий.
local Workspace = game:GetService("Workspace")

local enemiesFolder = Workspace:WaitForChild("Enemies")

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

	-- Встроенный объект Fire — готовая визуализация огня, без частиц вручную
	local fire = Instance.new("Fire")
	fire.Name = "BurnMark"
	fire.Size = 4
	fire.Heat = 6
	fire.Enabled = false
	fire.Parent = anchor

	-- SlowPercent уже был серверной правдой и реплицировался, но ничего его не рисовало —
	-- игрок видел замедление только по тому, что враг стал тащиться медленнее. Sparkles — такой же
	-- встроенный примитив, как и Fire выше, по тому же принципу вкл/выкл.
	local slowMark = Instance.new("Sparkles")
	slowMark.Name = "SlowMark"
	slowMark.SparkleColor = Color3.fromRGB(120, 200, 255)
	slowMark.Enabled = false
	slowMark.Parent = anchor

	-- Запутывание (Туман): без метки жук, идущий не в ту сторону, читался бы как поломка
	-- поиска пути, а не как эффект. Атрибут булевый специально: срок живёт в ConfusedUntil
	-- по шкале os.clock() сервера, и клиенту это число ничего не значит.
	local confusionMark = Instance.new("Smoke")
	confusionMark.Name = "ConfusionMark"
	confusionMark.Color = Color3.fromRGB(200, 215, 225)
	confusionMark.Size = 1.5
	confusionMark.Opacity = 0.4
	confusionMark.RiseVelocity = 3
	confusionMark.Enabled = false
	confusionMark.Parent = anchor

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
	}

	local function updateHealth()
		local hp = enemy:GetAttribute("HP") or 0
		local maxHp = enemy:GetAttribute("MaxHP") or hp
		local fraction = maxHp > 0 and math.clamp(hp / maxHp, 0, 1) or 0
		fill.Size = UDim2.new(fraction, 0, 1, 0)
		fill.BackgroundColor3 = Color3.fromRGB(220, 60, 60):Lerp(Color3.fromRGB(80, 220, 80), fraction)
	end

	local function updateBurning()
		fire.Enabled = enemy:GetAttribute("Burning") == true
	end

	-- Замедление не булевое: при истечении Effects явно ставит SlowPercent = 0
	-- (не убирает атрибут), поэтому сравнение с 0 достаточно надёжно.
	local function updateSlow()
		slowMark.Enabled = (enemy:GetAttribute("SlowPercent") or 0) > 0
	end

	local function updateConfusion()
		confusionMark.Enabled = enemy:GetAttribute("Confused") == true
	end

	-- Одна обводка на оба эффекта, поэтому и обновление одно: перебирает markStyles
	-- по порядку и берёт первый активный. Ни один не активен — обводки нет.
	-- Стан булевый отдельно от срока (StunnedUntil): срок считается по os.clock()
	-- сервера, и клиенту это число ничего не значит — тот же расклад, что у запутывания.
	local function updateMark()
		for _, style in markStyles do
			if enemy:GetAttribute(style.attribute) == true then
				effectMark.FillColor = style.fillColor
				effectMark.FillTransparency = style.fillTransparency
				effectMark.OutlineColor = style.outlineColor
				effectMark.Enabled = true
				return
			end
		end
		effectMark.Enabled = false
	end

	updateHealth()
	updateBurning()
	updateSlow()
	updateConfusion()
	updateMark()

	enemy:GetAttributeChangedSignal("HP"):Connect(updateHealth)
	enemy:GetAttributeChangedSignal("Burning"):Connect(updateBurning)
	enemy:GetAttributeChangedSignal("SlowPercent"):Connect(updateSlow)
	enemy:GetAttributeChangedSignal("Confused"):Connect(updateConfusion)
	enemy:GetAttributeChangedSignal("Amplified"):Connect(updateMark)
	enemy:GetAttributeChangedSignal("Stunned"):Connect(updateMark)
end

for _, enemy in enemiesFolder:GetChildren() do
	attachVisuals(enemy)
end
enemiesFolder.ChildAdded:Connect(attachVisuals)