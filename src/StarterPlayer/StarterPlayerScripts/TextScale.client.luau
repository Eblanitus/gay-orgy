-- Размер шрифта из настроек (просьба автора, #227): множитель ко всему тексту в PlayerGui.
--
-- Окна сами ставят TextSize при раскладке, и не по одному разу — на каждом изменении
-- экрана. Поэтому множитель не вписан в каждое окно, а навешан снаружи: у каждой
-- надписи помнится «родной» размер, который поставил её скрипт, а на экране стоит
-- родной × множитель. Если скрипт окна поставил новое число, оно и есть новый родной
-- размер; собственную запись отличаем по тому, что число совпало с ожидаемым.
--
-- Растёт только TextSize. Размер вписанного в RichText (<font size>) и рамки окон не
-- меняются — длинная подпись на 130 % может обрезаться.
local Players = game:GetService("Players")

local Settings = require(script.Parent:WaitForChild("Settings"))

local gui = Players.LocalPlayer:WaitForChild("PlayerGui")

local base = setmetatable({}, { __mode = "k" }) -- надпись → родной размер
local shown = setmetatable({}, { __mode = "k" }) -- надпись → что поставили мы
local scale = 1

local function readScale()
	return (tonumber(Settings.Get("textScale")) or 100) / 100
end

local function apply(label)
	local size = math.floor(base[label] * scale + 0.5)
	shown[label] = size
	label.TextSize = size
end

local function track(label)
	if not (label:IsA("TextLabel") or label:IsA("TextButton") or label:IsA("TextBox")) then
		return
	end
	if base[label] then
		return
	end
	base[label] = label.TextSize
	if scale ~= 1 then
		apply(label)
	end
	label:GetPropertyChangedSignal("TextSize"):Connect(function()
		if label.TextSize == shown[label] then
			return
		end
		base[label] = label.TextSize
		if scale ~= 1 then
			apply(label)
		else
			shown[label] = label.TextSize
		end
	end)
end

scale = readScale()
for _, d in gui:GetDescendants() do
	track(d)
end
gui.DescendantAdded:Connect(track)

Settings.Changed.Event:Connect(function(key)
	if key ~= "textScale" then
		return
	end
	scale = readScale()
	for label in base do
		if label.Parent then
			apply(label)
		end
	end
end)
