-- Уровень 2 «Бункер»: только каста разведчиков (Normal, Mini, Armored, Moth), только Колбы
-- и элементы до тира 1 (правила уровня — поле rules в Levels, проверки — в Tutorial).
-- Уровень учит двум вещам: летунам (Моль готовит к Лицехвату) и крафту тира 1.
--
-- Волны тематические, нагрузка нарочно скачет: всплески (5, 8, 11, 13, 15) чередуются
-- с передышками (6, 9, 10). Стол грызёт только Обычный (у Мини chewDamage = 0, Броня
-- ходит по периметру), поэтому в толпу Мини и в броню подмешано немного Обычных — иначе
-- такую волну нельзя проиграть.
--
-- hint — строка в журнал, когда волна ждёт кнопки (WaveRunner): игрок читает её до старта.
-- Подсказки про крафт стоят перед волнами, где элемент тира 1 заметно выгоднее базового
-- (офлайн-симулятор: на волне 4 Луже хватает одной Колбы, Земле нужно четыре).
--
-- hp везде равно базовому значению типа из Enemies — выписано явно для читаемости.
local Waves = {
	-- 1. Знакомство: обычные и мелкие.
	{ number = 1, groups = {
		{ enemyType = "Normal",  count = 4, hp = 30 },
		{ enemyType = "Mini",    count = 3, hp = 14 },
	} },
	-- 2. Броня: бронированные идут по периметру и ломают всё на пути.
	{ number = 2, groups = {
		{ enemyType = "Armored", count = 4, hp = 42 },
		{ enemyType = "Normal",  count = 3, hp = 30 },
	} },
	-- 3. Только Моль: первые летуны.
	{ number = 3, groups = {
		{ enemyType = "Moth",    count = 8, hp = 10 },
	}, hint = "ПОДСКАЗКА: летучие жуки! Колба бьёт и по воздуху. Моль летит на свет турелей с элементом" },
	-- 4. Толпа мелких, в ней прячутся обычные: Колба бьёт ближайшего.
	{ number = 4, groups = {
		{ enemyType = "Mini",    count = 25, hp = 14 },
		{ enemyType = "Normal",  count = 5, hp = 30 },
	}, hint = "ПОДСКАЗКА: скрести два базовых элемента на крафт-столе, выйдет элемент сильнее. Вода + Вода = Лужа: бьёт чаще и замедляет толпу" },
	-- 5. Смесь всех четырёх, первый всплеск.
	{ number = 5, groups = {
		{ enemyType = "Normal",  count = 10, hp = 30 },
		{ enemyType = "Mini",    count = 10, hp = 14 },
		{ enemyType = "Armored", count = 3, hp = 42 },
		{ enemyType = "Moth",    count = 4, hp = 10 },
	} },
	-- 6. Передышка.
	{ number = 6, groups = {
		{ enemyType = "Normal",  count = 6, hp = 30 },
		{ enemyType = "Moth",    count = 6, hp = 10 },
	} },
	-- 7. Стена брони.
	{ number = 7, groups = {
		{ enemyType = "Armored", count = 12, hp = 42 },
		{ enemyType = "Normal",  count = 4, hp = 30 },
	}, hint = "ПОДСКАЗКА: Земля + Земля = Грунт. Бьёт вдвое сильнее Земли, броня его почти не держит" },
	-- 8. Большая толпа, всплеск.
	{ number = 8, groups = {
		{ enemyType = "Mini",    count = 40, hp = 14 },
		{ enemyType = "Normal",  count = 10, hp = 30 },
	} },
	-- 9. Рой Моли.
	{ number = 9, groups = {
		{ enemyType = "Moth",    count = 20, hp = 10 },
	} },
	-- 10. Передышка.
	{ number = 10, groups = {
		{ enemyType = "Normal",  count = 8, hp = 30 },
		{ enemyType = "Armored", count = 6, hp = 42 },
	} },
	-- 11. Большой всплеск: все сразу.
	{ number = 11, groups = {
		{ enemyType = "Normal",  count = 20, hp = 30 },
		{ enemyType = "Mini",    count = 30, hp = 14 },
		{ enemyType = "Armored", count = 10, hp = 42 },
		{ enemyType = "Moth",    count = 10, hp = 10 },
	} },
	-- 12. Броня с летунами.
	{ number = 12, groups = {
		{ enemyType = "Armored", count = 20, hp = 42 },
		{ enemyType = "Moth",    count = 10, hp = 10 },
		{ enemyType = "Normal",  count = 6, hp = 30 },
	} },
	-- 13. Лавина мелких.
	{ number = 13, groups = {
		{ enemyType = "Mini",    count = 60, hp = 14 },
		{ enemyType = "Normal",  count = 12, hp = 30 },
	} },
	-- 14. Рой Моли с прикрытием.
	{ number = 14, groups = {
		{ enemyType = "Moth",    count = 30, hp = 10 },
		{ enemyType = "Normal",  count = 10, hp = 30 },
	} },
	-- 15. Финал.
	{ number = 15, groups = {
		{ enemyType = "Normal",  count = 30, hp = 30 },
		{ enemyType = "Mini",    count = 40, hp = 14 },
		{ enemyType = "Armored", count = 20, hp = 42 },
		{ enemyType = "Moth",    count = 20, hp = 10 },
	} },
}

-- БОЛЬШЕ НЕ ИСПОЛЬЗУЕТСЯ: с задачи #22 каждую волну зовёт игрок кнопкой, а не таймер.
-- Поле оставлено: если вернёмся к автоматическим волнам или добавим таймер-подсказку, число уже есть.
Waves.pauseBetweenWaves = 15 -- сек

return Waves
