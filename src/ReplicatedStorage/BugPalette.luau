-- Единая раскраска жуков. Раньше у каждого вида был свой случайный RGB, и на поле рядом
-- стояли серые, рыжие, салатовые и сиреневые жуки — ни касты, ни веса по цвету не прочесть.
--
-- Правило теперь одно:
--   * цвет панциря задаёт КАСТА (одно семейство на касту) — роль видно издалека;
--   * тон (поле tone вида, -1..1) — вес: мелкие и быстрые светлее, тяжёлые темнее;
--   * лапы и суставы у всех одной тёмной смолой — силуэт ног читается одинаково;
--   * голова темнее панциря — видно, куда жук смотрит;
--   * панцирь матовый: блеск и свечение оставлены статусам (горение, холод, порох и т.д.),
--     иначе метка статуса тонет среди «красивых» жуков.
-- Оттенки подобраны к арене: светло-серый пол и белые стены с синей отделкой. Тёплые
-- приглушённые тона против холодного синего не сливаются ни с полом, ни со стенами.
--
-- Красит только жуков со своей моделью (поле model в Enemies); примитивы-заглушки — своим color.
-- Исключения по смыслу вида задаёт поле family (семейство вместо кастового).
local BugPalette = {}

local function hex(value)
	return Color3.fromHex(value)
end

BugPalette.Colors = {
	olive = hex("#66703F"), -- каста 0: разведчики
	ochre = hex("#9A7238"), -- каста 1: работяги
	brick = hex("#8C3B2A"), -- каста 2: солдаты
	plum = hex("#5B3F63"), -- каста 3: особые
	bone = hex("#D3C7A6"), -- светлое: бледные и летучие (Моль, Личинка), мимикрия
	tar = hex("#2A2522"), -- лапы, суставы, Тень
}

BugPalette.ByCaste = { [0] = "olive", [1] = "ochre", [2] = "brick", [3] = "plum" }

-- Кровь (гемолимфа) и выцветание трупа — из той же палитры: тёмная олива, а не салатовая
-- краска поверх светлого пола.
BugPalette.Blood = hex("#4F5A2C")
BugPalette.Dead = hex("#6E665A")

-- Насколько тон сдвигает панцирь: к кости (светлее) и к смоле (темнее).
local LIGHTEN = 0.4
local DARKEN = 0.5
local ELYTRA_DARKEN = 0.12 -- надкрылья чуть темнее панциря: спина не сливается в одно пятно
local HEAD_DARKEN = 0.32
local LEG_TINT = 0.18 -- доля цвета панциря в лапах: смола, но своя у каждой касты

-- Заполняет color / elytraColor / headColor / legColor записи вида по касте и тону.
-- Явно заданные поля не трогает — так можно точечно поправить один вид.
function BugPalette.Paint(data)
	local family = data.family or BugPalette.ByCaste[data.caste or 0] or "olive"
	local base = BugPalette.Colors[family]
	assert(base, ("[BugPalette] нет семейства %s"):format(tostring(family)))
	local tone = math.clamp(data.tone or 0, -1, 1)
	local shell = tone >= 0 and base:Lerp(BugPalette.Colors.bone, tone * LIGHTEN)
		or base:Lerp(BugPalette.Colors.tar, -tone * DARKEN)
	data.color = data.color or shell
	data.elytraColor = data.elytraColor or shell:Lerp(BugPalette.Colors.tar, ELYTRA_DARKEN)
	data.headColor = data.headColor or shell:Lerp(BugPalette.Colors.tar, HEAD_DARKEN)
	data.legColor = data.legColor or BugPalette.Colors.tar:Lerp(shell, LEG_TINT)
end

return BugPalette
