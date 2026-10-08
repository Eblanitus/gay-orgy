-- Уровень 2 «Бункер»: только каста разведчиков (Normal, Mini, Armored, Sprinter; Моль — отдельно,
-- см. ниже), только Колбы и элементы до тира 1 (правила уровня — поле rules в Levels,
-- проверки — в Tutorial). Уровень учит летунам (Моль готовит к Лицехвату) и крафту тира 1.
--
-- Моли в волнах нет: она прилетает сама по одной, и между волнами, и во время них
-- (поле moths в Levels, спавн — WaveRunner). Пачкой она смотрелась ненатурально (просьба автора).
--
-- HP у всех жуков Бункера ×1.5 к базовому значению типа из Enemies (просьба автора «всем
-- увеличить хп, кроме Моли»): поле hp группы, так что другие уровни это не трогает.
-- Жуков в волнах меньше, чем было: тяжелее каждый, а не толпа больше.
--
-- Волны тематические, нагрузка нарочно скачет: всплески (5, 8, 11, 13, 15) чередуются
-- с передышками (6, 10). Стол грызёт Обычный, Спринтер бьёт его с разбега (breachBite);
-- у Мини chewDamage = 0, Броня ходит по периметру, поэтому в толпу Мини и в броню
-- подмешаны Обычные — иначе такую волну нельзя проиграть.
--
-- hint — строка в журнал, когда волна ждёт старта (WaveRunner): игрок читает её до волны.
-- Подсказки про крафт стоят перед волнами, где элемент тира 1 заметно выгоднее базового
-- (офлайн-симулятор).
local Waves = {
	-- 1. Знакомство: обычные и мелкие.
	{ number = 1, groups = {
		{ enemyType = "Normal",   count = 4, hp = 45 },
		{ enemyType = "Mini",     count = 2, hp = 21 },
	} },
	-- 2. Броня: бронированные идут по периметру и ломают всё на пути.
	{ number = 2, groups = {
		{ enemyType = "Armored",  count = 3, hp = 63 },
		{ enemyType = "Normal",   count = 2, hp = 45 },
	} },
	-- 3. Первые Спринтеры. С этой волны начинает прилетать Моль.
	{ number = 3, groups = {
		{ enemyType = "Sprinter", count = 3, hp = 27 },
		{ enemyType = "Normal",   count = 3, hp = 45 },
	}, hint = "ПОДСКАЗКА: Спринтер бежит к столу и бьёт его с разбега. А на свет турелей с элементом теперь прилетает Моль: она отвлекает турели, Колба бьёт и по воздуху" },
	-- 4. Толпа мелких, в ней прячутся обычные: Колба бьёт ближайшего.
	{ number = 4, groups = {
		{ enemyType = "Mini",     count = 15, hp = 21 },
		{ enemyType = "Normal",   count = 4, hp = 45 },
	}, hint = "ПОДСКАЗКА: скрести два базовых элемента на крафт-столе, выйдет элемент сильнее. Вода + Вода = Лужа: бьёт чаще и замедляет толпу" },
	-- 5. Смесь, первый всплеск.
	{ number = 5, groups = {
		{ enemyType = "Normal",   count = 8, hp = 45 },
		{ enemyType = "Mini",     count = 6, hp = 21 },
		{ enemyType = "Armored",  count = 2, hp = 63 },
		{ enemyType = "Sprinter", count = 2, hp = 27 },
	} },
	-- 6. Передышка.
	{ number = 6, groups = {
		{ enemyType = "Normal",   count = 5, hp = 45 },
	} },
	-- 7. Стена брони.
	{ number = 7, groups = {
		{ enemyType = "Armored",  count = 8, hp = 63 },
		{ enemyType = "Normal",   count = 3, hp = 45 },
	}, hint = "ПОДСКАЗКА: Земля + Земля = Грунт. Бьёт вдвое сильнее Земли, броня его почти не держит" },
	-- 8. Большая толпа, всплеск.
	{ number = 8, groups = {
		{ enemyType = "Mini",     count = 24, hp = 21 },
		{ enemyType = "Normal",   count = 6, hp = 45 },
	} },
	-- 9. Рывок Спринтеров.
	{ number = 9, groups = {
		{ enemyType = "Sprinter", count = 8, hp = 27 },
		{ enemyType = "Normal",   count = 2, hp = 45 },
	} },
	-- 10. Передышка.
	{ number = 10, groups = {
		{ enemyType = "Normal",   count = 6, hp = 45 },
		{ enemyType = "Armored",  count = 4, hp = 63 },
	} },
	-- 11. Большой всплеск: все сразу.
	{ number = 11, groups = {
		{ enemyType = "Normal",   count = 12, hp = 45 },
		{ enemyType = "Mini",     count = 16, hp = 21 },
		{ enemyType = "Armored",  count = 6, hp = 63 },
		{ enemyType = "Sprinter", count = 4, hp = 27 },
	} },
	-- 12. Броня, за ней Спринтеры.
	{ number = 12, groups = {
		{ enemyType = "Armored",  count = 12, hp = 63 },
		{ enemyType = "Sprinter", count = 4, hp = 27 },
		{ enemyType = "Normal",   count = 4, hp = 45 },
	} },
	-- 13. Лавина мелких.
	{ number = 13, groups = {
		{ enemyType = "Mini",     count = 36, hp = 21 },
		{ enemyType = "Normal",   count = 8, hp = 45 },
	} },
	-- 14. Спринтеры волной.
	{ number = 14, groups = {
		{ enemyType = "Sprinter", count = 12, hp = 27 },
		{ enemyType = "Normal",   count = 6, hp = 45 },
	} },
	-- 15. Финал.
	{ number = 15, groups = {
		{ enemyType = "Normal",   count = 18, hp = 45 },
		{ enemyType = "Mini",     count = 24, hp = 21 },
		{ enemyType = "Armored",  count = 12, hp = 63 },
		{ enemyType = "Sprinter", count = 8, hp = 27 },
	} },
}

-- БОЛЬШЕ НЕ ИСПОЛЬЗУЕТСЯ: с задачи #22 каждую волну зовёт игрок кнопкой, а не таймер.
-- Поле оставлено: если вернёмся к автоматическим волнам или добавим таймер-подсказку, число уже есть.
Waves.pauseBetweenWaves = 15 -- сек

return Waves
