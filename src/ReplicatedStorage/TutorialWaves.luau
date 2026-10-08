-- Волны уровня 1 «Обучение» (задача #432). Три волны:
--   1 — игрок смотрит, как стартовая Колба у стола бьёт жуков;
--   2 — после неё он ставит свою Колбу (обязательный шаг), волна чуть плотнее;
--   3 — жёстче, с бронёй: сам решает, нужны ли ещё Колбы. Проигрыш здесь обучение
--       не отменяет — оно засчитано после волны 2 (TutorialConfig.completeAfterWave).
-- Числа подобраны офлайн-симулятором: 4 жука первой волны — ровно столько, чтобы
-- материи (12 за жуков + 20 за волну) хватило на Колбу; на волнах 1–2 стол не ломается
-- (TutorialConfig.guardedWaves). hp равно базовому значению типа из Enemies, как и в Waves.
local TutorialWaves = {
	{ number = 1, groups = {
		{ enemyType = "Normal", count = 4, hp = 30 },
	} },
	{ number = 2, groups = {
		{ enemyType = "Normal", count = 8, hp = 30 },
		{ enemyType = "Mini",   count = 6, hp = 14 },
	} },
	{ number = 3, groups = {
		{ enemyType = "Normal",  count = 14, hp = 30 },
		{ enemyType = "Mini",    count = 15, hp = 14 },
		{ enemyType = "Armored", count = 5,  hp = 42 },
	} },
}

return TutorialWaves
