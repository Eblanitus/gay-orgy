-- Звуки игры: бой, жуки, забег, фон и музыка. Что звучит и как — таблица
-- ReplicatedStorage.SoundBank, id ассетов — ReplicatedStorage.SoundIds. Здесь только
-- «по какому событию какой звук и где».
--
-- Слушает события, которые сервер и так шлёт ради картинки (CombatFX, EnemyRender):
-- ShotFired, Explosion, EnemyFX, WaveChanged, RunEnded. Своих remote'ов у звука нет.
--
-- Звук в мире висит на Attachment в Terrain в точке события и стихает с расстоянием
-- до камеры (near/far из таблицы). Петли (гул турели, крылья) живут на самой модели
-- и уходят вместе с ней.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Enemies = require(ReplicatedStorage:WaitForChild("Enemies"))
local SoundBank = require(ReplicatedStorage:WaitForChild("SoundBank"))
local SoundIds = require(ReplicatedStorage:WaitForChild("SoundIds"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local master = SoundService:WaitForChild("Master")
local groups = {
	Combat = master:WaitForChild("Combat"),
	Ambient = master:WaitForChild("Ambient"),
	Music = master:WaitForChild("Music"),
}

local last = {} -- имя -> os.clock() последнего запуска
local playing = {} -- имя -> сколько копий звучит сейчас

-- Готовый, но не запущенный Sound по имени из SoundBank; nil — звука нет или он не загружен.
local function make(name, gain)
	local def = SoundBank.Sounds[name]
	local id = SoundIds[name]
	if not def or not id then
		return nil
	end
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = id
	sound.SoundGroup = groups[def.group]
	sound.Volume = def.volume * (gain or 1)
	sound.PlaybackSpeed = def.pitch[1] + math.random() * (def.pitch[2] - def.pitch[1])
	sound.Looped = def.looped == true
	if def.near then
		sound.RollOffMode = Enum.RollOffMode.InverseTapered
		sound.RollOffMinDistance = def.near
		sound.RollOffMaxDistance = def.far
	end
	return sound, def
end

-- Можно ли сейчас запустить ещё одну копию name (gap и voices из таблицы).
local function admit(name, def)
	local now = os.clock()
	if def.gap and last[name] and now - last[name] < def.gap then
		return false
	end
	if def.voices and (playing[name] or 0) >= def.voices then
		return false
	end
	last[name] = now
	playing[name] = (playing[name] or 0) + 1
	return true
end

-- Разовый звук. at — Vector3 (звук в мире) или nil (звук «в ушах»).
local function play(name, at, gain)
	local sound, def = make(name, gain)
	if not sound or not admit(name, def) then
		if sound then
			sound:Destroy()
		end
		return
	end
	local holder = sound
	if at and def.near then
		local attachment = Instance.new("Attachment")
		attachment.Name = "Sound_" .. name
		attachment.WorldPosition = at
		attachment.Parent = Workspace.Terrain
		sound.Parent = attachment
		holder = attachment
	else
		sound.Parent = SoundService
	end
	local done = false
	local function finish()
		if done then
			return
		end
		done = true
		playing[name] = math.max(0, (playing[name] or 1) - 1)
		holder:Destroy()
	end
	sound.Ended:Once(finish)
	sound:Play()
	-- Ended не придёт, если звук не загрузился: страховка по времени.
	task.delay(8, finish)
end

local function positionOf(thing)
	if typeof(thing) == "Vector3" then
		return thing
	elseif typeof(thing) == "Instance" then
		if thing:IsA("BasePart") then
			return thing.Position
		elseif thing:IsA("Attachment") then
			return thing.WorldPosition
		elseif thing:IsA("Model") then
			return thing:GetPivot().Position
		end
	end
	return nil
end

-- ============ Бой ============

Remotes:WaitForChild("ShotFired").OnClientEvent:Connect(function(muzzle, _color, tower)
	local towerType = tower and tower:GetAttribute("Type")
	local name = towerType and SoundBank.Shot[towerType]
	if name then
		play(name, positionOf(muzzle) or positionOf(tower))
	end
end)

Remotes:WaitForChild("Explosion").OnClientEvent:Connect(function(position, radius, droneColor, blast)
	local name = droneColor and SoundBank.Blast.drone or SoundBank.Blast[blast] or SoundBank.Blast.default
	local gain = math.clamp((radius or SoundBank.BLAST_REF_RADIUS) / SoundBank.BLAST_REF_RADIUS,
		SoundBank.BLAST_GAIN[1], SoundBank.BLAST_GAIN[2])
	play(name, positionOf(position), gain)
end)

local function deathSound(scale)
	for _, row in SoundBank.Death do
		if scale <= row.upTo then
			return row.sound
		end
	end
	return nil
end

Remotes:WaitForChild("EnemyFX").OnClientEvent:Connect(function(kind, a, b, c)
	if kind == "death" then
		-- a — модель жука (ещё не удалена), c — hit из Corpses.Leave: scale, remains.
		local at = positionOf(a)
		if not at then
			return
		end
		local hit = c or {}
		local name = deathSound(hit.scale or 3)
		if name then
			play(name, at)
		end
		local extra = hit.remains and SoundBank.Remains[hit.remains]
		if extra then
			play(extra, at)
		end
	elseif kind == "splat" then
		play("Splat", positionOf(a))
	elseif kind == "statue" then
		-- Керамическая статуя: звук ей даст разбивание (shatter), а не появление.
		return
	elseif kind == "shatter" then
		-- По id трупа точки нет; звучит у камеры, чуть тише.
		play("Shatter", nil, 0.7)
	end
end)

-- ============ Петли на моделях ============

-- Петля name на модели model, пока та жива. Высота — pitch (поверх случайной из таблицы).
local function attachLoop(model, name, pitch)
	local sound = make(name)
	if not sound then
		return
	end
	if pitch then
		sound.PlaybackSpeed = pitch
	end
	-- Петли начинаются с разного места, иначе пять одинаковых турелей гудят в унисон.
	sound.TimePosition = math.random() * 2
	-- Детали модели доезжают до клиента позже самой модели: подождать их немного.
	task.spawn(function()
		local part
		for _ = 1, 20 do
			part = model.Parent and (model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true))
			if part or not model.Parent then
				break
			end
			task.wait(0.1)
		end
		if not part then
			sound:Destroy()
			return
		end
		sound.Parent = part
		sound:Play()
	end)
end

-- Обработать модель, как только у неё появится атрибут Type (он может доехать позже модели).
local function withType(model, handle)
	if not model:IsA("Model") then
		return
	end
	if model:GetAttribute("Type") ~= nil then
		handle(model, model:GetAttribute("Type"))
		return
	end
	local conn
	conn = model:GetAttributeChangedSignal("Type"):Connect(function()
		conn:Disconnect()
		handle(model, model:GetAttribute("Type"))
	end)
end

local function onTower(tower, towerType)
	local hum = SoundBank.Hum[towerType]
	if hum then
		attachLoop(tower, hum.sound, hum.pitch)
	end
end

local function onEnemy(enemy, enemyType)
	local data = Enemies[enemyType]
	if (data and data.flying) or enemy:GetAttribute("Flying") then
		attachLoop(enemy, "WingBuzz")
	end
end

local towers = Workspace:WaitForChild("Towers")
towers.ChildAdded:Connect(function(tower)
	withType(tower, onTower)
end)
for _, tower in towers:GetChildren() do
	withType(tower, onTower)
end

local enemiesFolder = Workspace:WaitForChild("Enemies")
enemiesFolder.ChildAdded:Connect(function(enemy)
	withType(enemy, onEnemy)
end)
for _, enemy in enemiesFolder:GetChildren() do
	withType(enemy, onEnemy)
end

-- ============ Забег, фон, музыка ============

local ambient = make(SoundBank.Ambient)
if ambient then
	ambient.Parent = SoundService
	ambient:Play()
end

local music = make(SoundBank.Music)
local musicVolume = music and music.Volume
if music then
	music.Volume = musicVolume * SoundBank.MUSIC_IDLE
	music.Parent = SoundService
	music:Play()
end

local function musicTo(factor)
	if music then
		TweenService:Create(music, TweenInfo.new(SoundBank.MUSIC_FADE), { Volume = musicVolume * factor }):Play()
	end
end

Remotes:WaitForChild("WaveChanged").OnClientEvent:Connect(function()
	play("WaveStart")
	musicTo(1)
end)

Remotes:WaitForChild("RunEnded").OnClientEvent:Connect(function(won)
	play(won and "RunWin" or "RunLose")
	musicTo(SoundBank.MUSIC_IDLE)
end)
