-- Волны уровня 1 «Обучение» (задача #298): только разведчики тира 0 — Стандарт и Мини,
-- толпа растёт от волны к волне. hp равно базовому значению типа из Enemies, как и в Waves.
local TutorialWaves = {
	{ number = 1, groups = {
		{ enemyType = "Normal", count = 3, hp = 30 },
	} },
	{ number = 2, groups = {
		{ enemyType = "Normal", count = 5, hp = 30 },
		{ enemyType = "Mini",   count = 3, hp = 14 },
	} },
	{ number = 3, groups = {
		{ enemyType = "Normal", count = 6, hp = 30 },
		{ enemyType = "Mini",   count = 6, hp = 14 },
	} },
	{ number = 4, groups = {
		{ enemyType = "Normal", count = 8,  hp = 30 },
		{ enemyType = "Mini",   count = 10, hp = 14 },
	} },
	{ number = 5, groups = {
		{ enemyType = "Normal", count = 10, hp = 30 },
		{ enemyType = "Mini",   count = 15, hp = 14 },
	} },
}

return TutorialWaves
