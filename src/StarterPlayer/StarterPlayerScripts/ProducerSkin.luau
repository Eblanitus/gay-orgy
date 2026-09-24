-- Цвета лицевой панели автомата выдачи элементов (задача #199).
--
-- Берутся с самой модели ElementProducer: экран — деталь Panel, стальная лицевая
-- часть — PanelFace, неоновая полоса — LogoPlate, кнопки — ButtonFire/Water/Earth/Air,
-- стекло колб — Canister*. Перекрасят модель — переоденется и окно магазина, подбирать
-- цвета на глаз второй раз не придётся.
--
-- Числа ниже — не подбор, а снимок тех же деталей на случай, когда автомата рядом нет:
-- окно собирается вместе с клиентом, а локация под забег строится позже.
local Skin = {}

-- При скольки элементах колба в плитке налита доверху. Это про показ, а не про баланс:
-- цену и шансы держат RouletteConfig и UpgraderConfig.
Skin.CANISTER_FULL = 10

local FALLBACK = {
	screen = Color3.fromRGB(226, 229, 231),
	face = Color3.fromRGB(163, 162, 165),
	logo = Color3.fromRGB(80, 200, 255),
	cabinet = Color3.fromRGB(95, 100, 110),
	dark = Color3.fromRGB(45, 48, 55),
	glass = Color3.fromRGB(225, 240, 245),
}

local BUTTONS = {
	Fire = Color3.fromRGB(255, 138, 0),
	Water = Color3.fromRGB(40, 109, 255),
	Earth = Color3.fromRGB(137, 89, 42),
	Air = Color3.fromRGB(255, 255, 255),
}

-- Какая деталь модели отвечает за какое поле.
local PART = {
	screen = "Panel",
	face = "PanelFace",
	logo = "LogoPlate",
	cabinet = "Cabinet",
	dark = "Plinth",
	glass = "CanisterFire",
}

local function producer()
	local location = workspace:FindFirstChild("Location")
	local found = location and location:FindFirstChild("ElementProducer")
	if found then
		return found
	end
	return workspace:FindFirstChild("ElementProducer", true)
end

-- Снимок цветов на сейчас. Зовётся на каждом открытии окна, а не один раз при входе:
-- модели в этот момент может ещё не быть.
function Skin.Read()
	local out = { button = {} }
	for field, color in FALLBACK do
		out[field] = color
	end
	for key, color in BUTTONS do
		out.button[key] = color
	end

	local model = producer()
	if not model then
		return out
	end
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			for field, name in PART do
				if part.Name == name then
					out[field] = part.Color
				end
			end
			local key = part.Name:match("^Button(%a+)$")
			if key and out.button[key] then
				out.button[key] = part.Color
			end
		end
	end
	return out
end

return Skin
