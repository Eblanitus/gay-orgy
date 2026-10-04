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
--
-- Заодно здесь пол: мельче Theme.MIN_TEXT на экране не бывает ничего, даже если окно
-- поставило меньше (запрет автора на мелкий текст). Это страховка — окна сами ставят
-- не меньше минимума и считают под него раскладку.
local Players = game:GetService("Players")

local Settings = require(script.Parent:WaitForChild("Settings"))
local Theme = require(script.Parent:WaitForChild("UITheme"))

local gui = Players.LocalPlayer:WaitForChild("PlayerGui")

local base = setmetatable({}, { __mode = "k" }) -- надпись → родной размер
local shown = setmetatable({}, { __mode = "k" }) -- надпись → что поставили мы
local scale = 1

local function readScale()
	return (tonumber(Settings.Get("textScale")) or 100) / 100
end

local function apply(label)
	local size = math.max(Theme.MIN_TEXT, math.floor(base[label] * scale + 0.5))
	shown[label] = size
	label.TextSize = size
end

-- Нужно ли своё число на экране: множитель не единица или родной размер ниже пола.
local function needs(label)
	return scale ~= 1 or base[label] < Theme.MIN_TEXT
end

local function track(label)
	if not (label:IsA("TextLabel") or label:IsA("TextButton") or label:IsA("TextBox")) then
		return
	end
	if base[label] then
		return
	end
	base[label] = label.TextSize
	if needs(label) then
		apply(label)
	end
	label:GetPropertyChangedSignal("TextSize"):Connect(function()
		if label.TextSize == shown[label] then
			return
		end
		base[label] = label.TextSize
		if needs(label) then
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
