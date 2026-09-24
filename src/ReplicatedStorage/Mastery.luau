-- Ступени справочника: что открывается в карточке за число убийств (просьба автора, #263).
-- У элемента считаются жуки, которых он добил (последнее попадание — атрибут LastElement,
-- ставит Effects.HitDamage), у жука — сколько раз убит его тип. Счёт живёт в профиле
-- (PlayerData: elementKills, enemyKills), до клиента доходит событием KillStats.
local Mastery = {}

Mastery.ELEMENT = {
	card = 1, -- имя, описание, «показать на карте»
	stats = 10, -- характеристики, эффекты и особенности
	crafts = 100, -- рецепт и «используется в»
	pattern = 1000, -- узор: в шапке, в сетке, на вкладке «узор»
}

Mastery.ENEMY = {
	card = 1, -- имя, описание, урок
	stats = 10, -- характеристики и особенности
	model = 100, -- модель жука
}

-- Подпись того, что закрыто, — для строки «откроется после N убийств».
Mastery.CAPTION = {
	stats = "характеристики",
	crafts = "рецепты",
	pattern = "узор",
	model = "модель",
}

-- Порядок ступеней — по порогу: общий номер ступени нужен клиенту, чтобы перерисовывать
-- карточку только когда что-то открылось, а не на каждое убийство.
function Mastery.Level(steps, kills)
	local level = 0
	for _, need in steps do
		if (kills or 0) >= need then
			level += 1
		end
	end
	return level
end

-- Ближайшее закрытое: имя ступени и её порог, либо nil — открыто всё.
function Mastery.Next(steps, kills)
	local bestStep, bestNeed = nil, math.huge
	for step, need in steps do
		if (kills or 0) < need and need < bestNeed then
			bestStep, bestNeed = step, need
		end
	end
	return bestStep, bestStep and bestNeed or nil
end

return Mastery
