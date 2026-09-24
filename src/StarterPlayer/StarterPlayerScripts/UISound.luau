-- Звуки интерфейса. Играют только у этого игрока: клиентский Sound при
-- SoundService.RespectFilteringEnabled другим не слышен.
--
-- Сами звуки лежат в SoundService.UISounds, по одному Sound на отклик. Громкость,
-- высоту и сам звук отдельного отклика правят прямо там: в Studio его можно
-- прослушать, и код трогать не нужно. Каждый Sound привязан к группе:
--   SoundService.Master          — «Общая громкость» (volumeMaster)
--   SoundService.Master.Buttons  — «Кнопки и покупка» (volumeButtons)
--   SoundService.Master.Draw     — «Рулетка и апгрейдер» (volumeDraw)
--   SoundService.Master.Music    — «Музыка» (volumeMusic); музыка будет — её Sound ставить в эту группу
-- Группы Buttons, Draw и Music лежат внутри Master, поэтому их громкость умножается на общую.
-- Громкость групп — из настроек (UISettings) по кривой UISettings.Gain и меняется сразу.
-- Правее 100% на ползунке группа громче записанного звука (Volume больше 1).
local ContentProvider = game:GetService("ContentProvider")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Settings = require(script.Parent:WaitForChild("Settings"))
local UISettings = require(ReplicatedStorage:WaitForChild("UISettings"))

local UISound = {}

-- Один и тот же звук не звучит чаще, чем раз в GAP секунд: тики барабанов и стрелки
-- на разгоне идут чаще кадра и без этого слиплись бы в гул.
local GAP = 0.045
-- Копия звука убирается не позже, чем через LIFE секунд, даже если Ended не пришёл
-- (звук не загрузился). Самый длинный отклик короче.
local LIFE = 5

local master = SoundService:WaitForChild("Master")
local groups = {
	volumeMaster = master,
	volumeButtons = master:WaitForChild("Buttons"),
	volumeDraw = master:WaitForChild("Draw"),
	volumeMusic = master:WaitForChild("Music"),
}
local folder = SoundService:WaitForChild("UISounds")
local last = {}

local function setVolume(key, value)
	local group = groups[key]
	if group then
		group.Volume = UISettings.Gain(key, value)
	end
end

local function apply(key)
	setVolume(key, Settings.Get(key))
end

for key in groups do
	apply(key)
end
-- Сохранённые громкости приходят из профиля позже старта (Settings шлёт Changed
-- по каждой), поэтому одной начальной установки мало.
Settings.Changed.Event:Connect(apply)

-- Подгрузить заранее: иначе первый щелчок после входа в игру прозвучал бы с задержкой.
task.spawn(function()
	ContentProvider:PreloadAsync(folder:GetChildren())
end)

-- Проиграть копию звука name из SoundService.UISounds. cut — оборвать через cut
-- секунд (треск помехи длиннее самой помехи). Неизвестное имя или nil (строка настроек
-- без sample) молча пропускается.
function UISound.Play(name, cut)
	if not name then
		return
	end
	local source = folder:FindFirstChild(name)
	if not source then
		return
	end
	local now = os.clock()
	if last[name] and now - last[name] < GAP then
		return
	end
	last[name] = now
	local sound = source:Clone()
	sound.Parent = SoundService
	sound.Ended:Once(function()
		sound:Destroy()
	end)
	sound:Play()
	Debris:AddItem(sound, cut or LIFE)
end

-- Громкость группы key по положению ползунка value, мимо настроек: ползунок зовёт это
-- на каждом шаге протяжки, а в Settings (и на сервер) кладёт одно значение, когда
-- его отпустили.
function UISound.Preview(key, value)
	setVolume(key, value)
end

return UISound
