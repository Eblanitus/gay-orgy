-- Разметка и плоский декор пола лаборатории (alchemy_td_location_v1.6.md: «Пол: разметка и
-- напольный декор»). Данные лежат в самой локации: сменилась локация — сменилась
-- и разметка. Рисует её ServerScriptService.ConcreteFloor поверх плит: плиты ездят
-- по высоте, и разметка едет вместе с ними.
--
-- Всё плоское: клетки стройки, линию огня и путь жуков не трогает.
-- Координаты — мировые, в студах; прямоугольники режутся по плитам сами.

local YELLOW = Color3.fromHex("d9a520")
local BLACK = Color3.fromHex("2e3034")
local DARK = Color3.fromHex("60646a")
local VDARK = Color3.fromHex("1e2023")
local LIGHT = Color3.fromHex("afb3b8")

local rects = {}
local function rect(x0, z0, x1, z1, color, material, transparency)
	table.insert(rects, {
		x0 = math.min(x0, x1), z0 = math.min(z0, z1),
		x1 = math.max(x0, x1), z1 = math.max(z0, z1),
		color = color, material = material, transparency = transparency,
	})
end

-- Рамка из четырёх полос.
local function outline(x0, z0, x1, z1, width, color)
	rect(x0, z0, x1, z0 + width, color)
	rect(x0, z1 - width, x1, z1, color)
	rect(x0, z0 + width, x0 + width, z1 - width, color)
	rect(x1 - width, z0 + width, x1, z1 - width, color)
end

-- Полоса «зеброй» жёлтый/чёрный вдоль Z.
local function hazardAlongZ(x0, x1, z0, z1, step)
	local z, i = z0, 0
	while z < z1 - 1e-3 do
		local zn = math.min(z + step, z1)
		rect(x0, z, x1, zn, i % 2 == 0 and YELLOW or BLACK)
		z, i = zn, i + 1
	end
end

-- Гермодверь (проём в западной стене, z -30..-14): предупредительная полоса поперёк прохода.
hazardAlongZ(-57.2, -55.6, -30, -14, 1)

-- Лабораторный стол (габарит x 49.6..56.8, z 19.9..24.1): жёлтая рамка с запасом.
outline(48.4, 18.7, 57.2, 25.3, 0.3, YELLOW)

-- Дренажные решётки: тёмная рама, внутри прорези (верхний слой — см. layer).
local grates = {}
local function grate(cx, cz)
	local h = 1.1
	rect(cx - h, cz - h, cx + h, cz + h, DARK, Enum.Material.DiamondPlate)
	for i = -2, 2 do
		table.insert(grates, {
			x0 = cx + i * 0.4 - 0.1, x1 = cx + i * 0.4 + 0.1,
			z0 = cz - h + 0.25, z1 = cz + h - 0.25,
			color = VDARK, layer = 2,
		})
	end
end
grate(-21, 9)
grate(18, -15)

for _, g in grates do
	table.insert(rects, g)
end

return {
	-- Швы между плитами: тонкая тёмная рамка по краю каждой.
	seam = { color = BLACK, width = 0.06, transparency = 0.35 },
	rects = rects,
	-- Пятна реагентов у стола и у производителя — цвета базовых элементов.
	discs = {
		{ x = 46.8, z = 21.5, r = 0.9, color = Color3.new(0.157, 0.431, 1), transparency = 0.55 },
		{ x = 51.5, z = 16.9, r = 0.6, color = Color3.new(1, 0.549, 0), transparency = 0.55 },
		{ x = 54.4, z = -9.6, r = 0.8, color = Color3.new(0.545, 0.353, 0.169), transparency = 0.5 },
		{ x = 53.3, z = -14.2, r = 0.5, color = LIGHT, transparency = 0.6 },
	},
}
