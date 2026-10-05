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
--   exposure, globalShadows, shadowSoftness, specular, diffuse — свойства Lighting
--     (ExposureCompensation, GlobalShadows, ShadowSoftness, EnvironmentSpecularScale,
--     EnvironmentDiffuseScale). Под Future белый пластик под лампой ярче единицы, поэтому
--     на высоких уровнях экспозиция чуть ниже нуля, а порог Bloom не ниже 1,6: с порогом
--     около единицы светились белая одежда, окна и турели (скрин автора, #413);
--   lampShadows — тени ламп карты (Light.Shadows в Workspace.Location): false — выключить
--     все, "map" — как поставлено в месте, true — включить у всех;
--   lampLight, lampGlow — множители к лампам карты: lampLight — к Light.Brightness,
--     lampGlow — к цвету Neon-рассеивателя, на котором висит лампа (яркость свечения Neon
--     идёт от цвета). Белые рассеиватели под LightingStyle Realistic пересвечивались
--     (автор, #414), 1 — как в месте;
--   bloom, sunRays, depthOfField, atmosphere, colorCorrection — таблица свойств эффекта
--     или false (эффект выключен). Bloom даёт свечение Neon (у жуков
--     материалы *_glow — Neon): Neon в Future много ярче освещённых деталей, и порог между ними — ореол только вокруг Neon.
local GraphicsPresets = {}

GraphicsPresets.Levels = {
	low = {
		exposure = 0,
		globalShadows = false,
		shadowSoftness = 0.2,
		specular = 0,
		diffuse = 0.5,
		lampShadows = false,
		lampLight = 0.8,
		lampGlow = 0.5,
		bloom = false,
		sunRays = false,
		depthOfField = false,
		atmosphere = { Density = 0.3, Haze = 0, Glare = 0 },
		colorCorrection = false,
	},
	medium = {
		exposure = 0,
		globalShadows = true,
		shadowSoftness = 0.2,
		specular = 0.5,
		diffuse = 1,
		lampShadows = false,
		lampLight = 0.8,
		lampGlow = 0.5,
		bloom = { Intensity = 0.4, Size = 18, Threshold = 2 },
		sunRays = false,
		depthOfField = false,
		atmosphere = { Density = 0.3, Haze = 0, Glare = 0 },
		colorCorrection = { Brightness = 0, Contrast = 0.05, Saturation = 0.05, TintColor = Color3.new(1, 1, 1) },
	},
	high = {
		exposure = -0.2,
		globalShadows = true,
		shadowSoftness = 0.15,
		specular = 1,
		diffuse = 1,
		lampShadows = "map",
		lampLight = 0.75,
		lampGlow = 0.45,
		bloom = { Intensity = 0.5, Size = 24, Threshold = 1.8 },
		sunRays = { Intensity = 0.01, Spread = 0.1 },
		depthOfField = false,
		atmosphere = { Density = 0.32, Haze = 0.5, Glare = 0 },
		colorCorrection = { Brightness = 0, Contrast = 0.1, Saturation = 0.1, TintColor = Color3.new(1, 1, 1) },
	},
	ultra = {
		exposure = -0.3,
		globalShadows = true,
		shadowSoftness = 0.1,
		specular = 1,
		diffuse = 1,
		lampShadows = true,
		lampLight = 0.75,
		lampGlow = 0.45,
		bloom = { Intensity = 0.6, Size = 28, Threshold = 1.6 },
		sunRays = { Intensity = 0.03, Spread = 0.2 },
		depthOfField = { FarIntensity = 0.1, FocusDistance = 0.05, InFocusRadius = 30, NearIntensity = 0.75 },
		atmosphere = { Density = 0.34, Haze = 1, Glare = 0.2 },
		colorCorrection = {
			Brightness = 0,
			Contrast = 0.1,
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
