-- Качество графики (#412): ставит свет и постэффекты по настройке graphics.
--
-- Что ставится на каждом уровне — таблица ReplicatedStorage.GraphicsPresets; здесь только
-- «прочитать уровень и разложить его по Lighting». Правка с клиента остаётся у этого
-- игрока: сервер Lighting не трогает, и у других игроков всё как у них в настройках.
--
-- Эффекты ищутся в Lighting по классу, а не по имени: в месте они стоят под своими
-- именами (Bloom, SunRays, Atmosphere, DepthOfField). Нет нужного — создаётся свой
-- (ColorCorrection в месте нет). Атмосферу нельзя выключить свойством Enabled, поэтому у
-- неё уровень меняет только плотность и дымку.
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Settings = require(script.Parent:WaitForChild("Settings"))
local GraphicsPresets = require(ReplicatedStorage:WaitForChild("GraphicsPresets"))

local gameSettings = UserSettings():GetService("UserGameSettings")

local function effect(className)
	local found = Lighting:FindFirstChildOfClass(className)
	if found then
		return found
	end
	local made = Instance.new(className)
	made.Name = className
	made.Parent = Lighting
	return made
end

local function level()
	local chosen = Settings.Get("graphics")
	if chosen ~= "auto" and GraphicsPresets.Levels[chosen] then
		return chosen
	end
	local quality = gameSettings.SavedQualityLevel.Value -- 0 — «Автоматически»
	local byQuality = GraphicsPresets.AutoByQuality[quality]
	if byQuality then
		return byQuality
	end
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		return GraphicsPresets.AUTO_TOUCH
	end
	return GraphicsPresets.AUTO_DESKTOP
end

-- Тени ламп карты. Как стоит в месте, запоминается при первой встрече с лампой: уровни
-- «Низкая» и «Средняя» тени выключают, а «Высокая» должна вернуть именно то, что
-- поставлено в Studio, а не «включить у всех».
-- Так же запоминаются яркость лампы и цвет её Neon-рассеивателя: множители уровня
-- (lampLight, lampGlow) считаются от места, а не от уже убавленного.
-- Лампы карты — только SurfaceLight: вспышки и снаряды светят PointLight, у них яркость
-- своя и её не трогаем.
local mapShadows = setmetatable({}, { __mode = "k" })
local mapBrightness = setmetatable({}, { __mode = "k" })
local mapGlow = setmetatable({}, { __mode = "k" })
local lampMode = "map"
local lampLight = 1
local lampGlow = 1

-- Общая заливка места, от неё считается множитель ambient уровня.
local mapLighting = {
	Ambient = Lighting.Ambient,
	OutdoorAmbient = Lighting.OutdoorAmbient,
	Brightness = Lighting.Brightness,
}

local function scaled(c, k)
	return Color3.new(c.R * k, c.G * k, c.B * k)
end

local function applyLamp(light)
	if mapShadows[light] == nil then
		mapShadows[light] = light.Shadows
		mapBrightness[light] = light.Brightness
	end
	if lampMode == "map" then
		light.Shadows = mapShadows[light]
	else
		light.Shadows = lampMode
	end
	light.Brightness = mapBrightness[light] * lampLight

	local diffuser = light.Parent
	if diffuser and diffuser:IsA("BasePart") and diffuser.Material == Enum.Material.Neon then
		if mapGlow[diffuser] == nil then
			mapGlow[diffuser] = diffuser.Color
		end
		local c = mapGlow[diffuser]
		diffuser.Color = scaled(c, lampGlow)
	end
end

local function eachLamp(fn)
	local location = workspace:FindFirstChild("Location")
	if not location then
		return
	end
	for _, d in location:GetDescendants() do
		if d:IsA("SurfaceLight") then
			fn(d)
		end
	end
end

local function setEffect(className, props)
	local e = effect(className)
	if props == false then
		e.Enabled = false
		return
	end
	for name, value in props do
		e[name] = value
	end
	e.Enabled = true
end

local function apply()
	local p = GraphicsPresets.Levels[level()]
	Lighting.ExposureCompensation = p.exposure
	Lighting.Ambient = scaled(mapLighting.Ambient, p.ambient)
	Lighting.OutdoorAmbient = scaled(mapLighting.OutdoorAmbient, p.ambient)
	Lighting.Brightness = mapLighting.Brightness * p.ambient
	Lighting.GlobalShadows = p.globalShadows
	Lighting.ShadowSoftness = p.shadowSoftness
	Lighting.EnvironmentSpecularScale = p.specular
	Lighting.EnvironmentDiffuseScale = p.diffuse

	setEffect("BloomEffect", p.bloom)
	setEffect("SunRaysEffect", p.sunRays)
	setEffect("DepthOfFieldEffect", p.depthOfField)
	setEffect("ColorCorrectionEffect", p.colorCorrection)
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere then
		for name, value in p.atmosphere do
			atmosphere[name] = value
		end
	end

	lampMode = p.lampShadows
	lampLight = p.lampLight
	lampGlow = p.lampGlow
	eachLamp(applyLamp)
end

-- StreamingEnabled: лампы карты приезжают позже, чем стартует скрипт, — каждую новую
-- выставляем по текущему уровню.
local function watchLocation(location)
	location.DescendantAdded:Connect(function(d)
		if d:IsA("SurfaceLight") then
			applyLamp(d)
		end
	end)
end

local location = workspace:FindFirstChild("Location")
if location then
	watchLocation(location)
else
	task.spawn(function()
		watchLocation(workspace:WaitForChild("Location"))
		apply()
	end)
end

Settings.Changed.Event:Connect(function(key)
	if key == "graphics" then
		apply()
	end
end)

-- «Авто» следит за ползунком графики в меню Roblox: игрок сдвинул его — уровень следом.
gameSettings:GetPropertyChangedSignal("SavedQualityLevel"):Connect(function()
	if Settings.Get("graphics") == "auto" then
		apply()
	end
end)

apply()
