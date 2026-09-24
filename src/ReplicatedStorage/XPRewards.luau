-- Размеры наград опытом (alchemy_td_currencies.md, alchemy_td_location_v1.6.md: «Прохождение
-- этажа даёт XP», только первое — повтор ничего не даёт). Начисляет Plutonium.AwardLevelClear —
-- здесь только числа. Трат опыта пока нет, так что число ни на что не откалибровано.
local XPRewards = {
	levelClear = 100, -- первое прохождение этажа (уровня), разово
}

return XPRewards
