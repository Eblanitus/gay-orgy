-- Пресеты качества графики (#412): что ставит Graphics.client на каждом уровне.
--
-- Выбор уровня — настройка graphics в UISettings (вкладка «Графика»). Применяется только
-- на клиенте: Lighting и эффекты меняются у одного игрока и на сервер не уходят.
--
-- Lighting.Technology скрипт поменять не может (у свойства нет доступа из Lua): Future
-- ставится в Studio один раз и сохраняется в месте. Уровни ниже не переключают
-- технологию, а снимают с неё дорогое: тени солнца, тени ламп, постэффекты. Сам Roblox
-- тоже сбрасывает Future до простого света на слабых устройствах и при низком ползунке
-- графики в его меню — так что «Ультра» на телефоне всё равно не станет тяжелее, чем
-- телефон тянет.
--
-- Поля уровня:
--   globalShadows, shadowSoftness, specular, diffuse — свойства Lighting
--     (GlobalShadows, ShadowSoftness, EnvironmentSpecularScale, EnvironmentDiffuseScale);
--   lampShadows — тени ламп карты (Light.Shadows в Workspace.Location): false — выключить
--     все, "map" — как поставлено в месте, true — включить у всех;
--   bloom, sunRays, depthOfField, atmosphere, colorCorrection — таблица свойств эффекта
--     или false (эффект выключен). Bloom со слабым порогом даёт свечение Neon (у жуков
--     материалы *_glow — Neon): Neon в Future ярче единицы, и порог ниже — ореол вокруг него.
local GraphicsPresets = {}

GraphicsPresets.Levels = {
	low = {
		globalShadows = false,
		shadowSoftness = 0.2,
		specular = 0,
		diffuse = 0.5,
		lampShadows = false,
		bloom = false,
		sunRays = false,
		depthOfField = false,
		atmosphere = { Density = 0.3, Haze = 0, Glare = 0 },
		colorCorrection = false,
	},
	medium = {
		globalShadows = true,
		shadowSoftness = 0.2,
		specular = 0.5,
		diffuse = 1,
		lampShadows = false,
		bloom = { Intensity = 0.6, Size = 18, Threshold = 1.4 },
		sunRays = false,
		depthOfField = false,
		atmosphere = { Density = 0.3, Haze = 0, Glare = 0 },
		colorCorrection = { Brightness = 0, Contrast = 0.05, Saturation = 0.05, TintColor = Color3.new(1, 1, 1) },
	},
	high = {
		globalShadows = true,
		shadowSoftness = 0.15,
		specular = 1,
		diffuse = 1,
		lampShadows = "map",
		bloom = { Intensity = 0.8, Size = 28, Threshold = 1.15 },
		sunRays = { Intensity = 0.01, Spread = 0.1 },
		depthOfField = false,
		atmosphere = { Density = 0.32, Haze = 0.5, Glare = 0 },
		colorCorrection = { Brightness = 0, Contrast = 0.1, Saturation = 0.1, TintColor = Color3.new(1, 1, 1) },
	},
	ultra = {
		globalShadows = true,
		shadowSoftness = 0.1,
		specular = 1,
		diffuse = 1,
		lampShadows = true,
		bloom = { Intensity = 1, Size = 40, Threshold = 0.95 },
		sunRays = { Intensity = 0.03, Spread = 0.2 },
		depthOfField = { FarIntensity = 0.1, FocusDistance = 0.05, InFocusRadius = 30, NearIntensity = 0.75 },
		atmosphere = { Density = 0.34, Haze = 1, Glare = 0.2 },
		colorCorrection = {
			Brightness = 0.02,
			Contrast = 0.15,
			Saturation = 0.15,
			TintColor = Color3.fromRGB(245, 250, 255),
		},
	},
}

-- «Авто»: уровень по ползунку графики в меню Roblox (UserGameSettings.SavedQualityLevel,
-- 1–10). Ползунок на «Автоматически» — уровень по устройству: AUTO_TOUCH на сенсорном
-- без клавиатуры (телефон, планшет), AUTO_DESKTOP на остальных.
GraphicsPresets.AutoByQuality = {
	"low", "low", "low", -- 1–3
	"medium", "medium", "medium", -- 4–6
	"high", "high", -- 7–8
	"ultra", "ultra", -- 9–10
}
GraphicsPresets.AUTO_TOUCH = "medium"
GraphicsPresets.AUTO_DESKTOP = "high"

return GraphicsPresets
