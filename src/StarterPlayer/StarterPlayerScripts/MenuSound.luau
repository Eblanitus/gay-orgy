-- Звуки главного меню и его страниц (журнал, настройки, промокод). Что и как звучит —
-- ReplicatedStorage.SoundBank.Menu, id — SoundIds. Выключатель — SoundBank.MENU_SFX_ENABLED.
--
-- Отдельно от UISound: те звуки живут в месте (SoundService.UISounds) и правятся в Studio,
-- а эти — файлы в «Звуки/», как звуки боя. Группа та же — SoundService.Master.Buttons,
-- так что громкость меню — ползунок «Кнопки и покупка». Звук без id молча не играет.
local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local SoundBank = require(ReplicatedStorage:WaitForChild("SoundBank"))
local SoundIds = require(ReplicatedStorage:WaitForChild("SoundIds"))

local MenuSound = {}

-- Копия убирается не позже, чем через LIFE секунд, даже если Ended не пришёл.
local LIFE = 3

local group = SoundService:WaitForChild("Master"):WaitForChild("Buttons")

-- Образцы заводятся один раз и подгружаются заранее: иначе первое наведение после входа
-- прозвучало бы с задержкой. Играют их копии.
local templates = {}
for name, def in SoundBank.Menu do
	local id = SoundIds[name]
	if id then
		local sound = Instance.new("Sound")
		sound.Name = name
		sound.SoundId = id
		sound.Volume = def.volume
		sound.SoundGroup = group
		templates[name] = sound
	end
end
task.spawn(function()
	local list = {}
	for _, sound in templates do
		table.insert(list, sound)
	end
	ContentProvider:PreloadAsync(list)
end)

local last = {}
local playing = {}

-- Проиграть звук name. speed — PlaybackSpeed (высота), по умолчанию 1.
function MenuSound.Play(name, speed)
	if not SoundBank.MENU_SFX_ENABLED then
		return
	end
	local def = SoundBank.Menu[name]
	local template = templates[name]
	if not def or not template then
		return
	end
	local now = os.clock()
	if last[name] and now - last[name] < (def.gap or 0) then
		return
	end
	if (playing[name] or 0) >= (def.voices or 1) then
		return
	end
	last[name] = now
	playing[name] = (playing[name] or 0) + 1

	local sound = template:Clone()
	sound.PlaybackSpeed = speed or 1
	sound.Parent = SoundService
	local done = false
	local function finish()
		if done then
			return
		end
		done = true
		playing[name] -= 1
		sound:Destroy()
	end
	sound.Ended:Once(finish)
	sound:Play()
	task.delay(LIFE, finish)
end

-- Наведение на пункт index: ступень лада по номеру пункта (SoundBank.MENU_SCALE).
function MenuSound.Hover(index)
	local scale = SoundBank.MENU_SCALE
	local step = scale[((index - 1) % #scale) + 1]
	MenuSound.Play("MenuHover", 2 ^ (step / 12))
end

return MenuSound
