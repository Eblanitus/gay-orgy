-- Настройки интерфейса: одна таблица на клиент и на сервер.
--
-- Лежит в ReplicatedStorage, а не в клиенте, потому что значения хранятся в профиле
-- игрока и приходят с сервера — а сервер обязан проверять, что клиент прислал
-- существующий ключ существующего типа, и по чему-то это проверять. Держать список
-- настроек в двух местах значило бы однажды разрешить на сервере ключ, которого
-- в интерфейсе уже нет.
--
-- Сюда попадает ТОЛЬКО то, что действительно на что-то влияет: каждая строка ниже
-- имеет ровно одно место в коде, которое её читает, и оно указано в поле affects.
-- Громкость звука — четыре ползунка на вкладке «Звук». Их читает UISound и ставит
-- громкость групп SoundService.Master (общая) и её дочерних Buttons, Draw и Music
-- по кривой UISettings.Gain.
local UISettings = {}

-- Новая настройка добавляется строкой сюда и одной проверкой Settings.Get там,
-- где она работает. Правка логики не требуется — ни здесь, ни на сервере.
--
-- Строка без options — переключатель со значением true или false. Строка с options —
-- выбор из нескольких вариантов: значение — строка value, в меню видна label,
-- нажатие перебирает варианты по кругу (UISettings.Next). Строка с min, max и step —
-- число: положение ползунка громкости от min до max с шагом step. Само положение ещё
-- не громкость: knee — положение, где громкость ровно как у записанного звука (100 %),
-- а curve и hyper задают кривую по обе стороны от него (UISettings.Gain). sample —
-- звук-образец, который играет, пока ползунок тянут, и когда его отпустили; строка без
-- sample тянется молча.
--
-- tab — вкладка экрана настроек из UISettings.Tabs; строка без tab лежит на «Интерфейсе».
UISettings.List = {
	{
		key = "panelGrid",
		name = "Сетка на панелях",
		note = "Ползущие соты на фоне окон",
		affects = "UITheme.Backdrop",
		default = true,
	},
	{
		key = "uiMotion",
		name = "Движение интерфейса",
		note = "Рост окна, вспышка показания, помехи при смене экрана",
		affects = "UITheme.Open, UITheme.Blink, UITheme.Static",
		default = true,
	},
	{
		key = "damageNumbers",
		name = "Цифры урона",
		note = "Всплывающее число над жуком при попадании",
		affects = "CombatFX.onDamage",
		default = true,
	},
	{
		key = "elementPatterns",
		name = "Узоры элементов",
		note = "Свой узор на фоне ячеек и узлов элемента (Огонь, Жар)",
		affects = "UITheme.Pattern",
		default = true,
	},
	{
		-- «Стандарт» автор выбрал из трёх опытов (#209 → #210); два других оставлены для сравнения.
		key = "buttonStyle",
		name = "Кнопки действий",
		note = "Тёмная бирюза с кантом, покупка в цвет элемента. 1 — без цвета элемента, 2 — только контур",
		affects = "UITheme.Button, CraftingUI (кнопки покупки у производителя)",
		options = {
			{ value = "standard", label = "СТАНДАРТ" },
			{ value = "e1", label = "ЭКСП. 1" },
			{ value = "e2", label = "ЭКСП. 2" },
		},
		default = "standard",
	},
	{
		-- Просьба автора (#227): крупнее весь текст интерфейса разом.
		key = "textScale",
		name = "Размер шрифта",
		note = "Весь текст интерфейса крупнее; рамки окон не растут",
		affects = "TextScale",
		options = {
			{ value = "100", label = "100 %" },
			{ value = "115", label = "115 %" },
			{ value = "130", label = "130 %" },
		},
		default = "100",
	},
	{
		key = "volumeMaster",
		name = "Общая громкость",
		note = "Все звуки игры сразу",
		affects = "UISound (SoundService.Master)",
		tab = "sound",
		min = 0,
		max = 150,
		step = 1,
		knee = 100,
		curve = 3,
		hyper = 3,
		sample = "Click",
		default = 100,
	},
	{
		key = "volumeButtons",
		name = "Кнопки и покупка",
		note = "Щелчок кнопок и смены режима, отклик пришедшего элемента («+n»)",
		affects = "UISound (SoundService.Master.Buttons)",
		tab = "sound",
		min = 0,
		max = 150,
		step = 1,
		knee = 100,
		curve = 3,
		hyper = 3,
		sample = "Click",
		default = 100,
	},
	{
		key = "volumeDraw",
		name = "Рулетка и апгрейдер",
		note = "Ход барабанов и стрелки, треск помехи, удача, неудача, джекпот",
		affects = "UISound (SoundService.Master.Draw)",
		tab = "sound",
		min = 0,
		max = 150,
		step = 1,
		knee = 100,
		curve = 3,
		hyper = 3,
		sample = "Stop",
		default = 100,
	},
	{
		key = "volumeMusic",
		name = "Музыка",
		note = "Фоновая музыка",
		affects = "UISound (SoundService.Master.Music)",
		tab = "sound",
		min = 0,
		max = 150,
		step = 1,
		knee = 100,
		curve = 3,
		hyper = 3,
		-- Без sample: музыки пока нет, образцом ей станет сам трек.
		default = 100,
	},
}

-- Вкладки экрана настроек по порядку. Строка попадает на вкладку по своему полю tab.
UISettings.Tabs = {
	{ key = "view", name = "Интерфейс" },
	{ key = "sound", name = "Звук" },
}

UISettings.ByKey = {}
for _, item in UISettings.List do
	UISettings.ByKey[item.key] = item
end

-- Свежая таблица значений по умолчанию. Именно копия, а не общий экземпляр:
-- её кладут в профиль игрока и потом правят, и один экземпляр на всех означал бы,
-- что настройка одного игрока меняет её у всех остальных на сервере.
function UISettings.Default()
	local values = {}
	for _, item in UISettings.List do
		values[item.key] = item.default
	end
	return values
end

-- Значение настройки с подстановкой умолчания. Профиль старого игрока может не знать
-- о настройке, добавленной позже: Reconcile досыпает только верхний уровень
-- DEFAULT_DATA, а внутрь settings не заглядывает.
function UISettings.Read(values, key)
	local item = UISettings.ByKey[key]
	if not item then
		return nil
	end
	local stored = values and values[key]
	if stored == nil then
		return item.default
	end
	return stored
end

-- Подпись выбранного варианта; nil, если такого варианта у настройки нет. По этому же
-- отличию сверяется и значение, присланное клиентом.
function UISettings.Label(key, value)
	local item = UISettings.ByKey[key]
	if not item or not item.options then
		return nil
	end
	for _, option in item.options do
		if option.value == value then
			return option.label
		end
	end
	return nil
end

-- Следующее значение по кругу. Что значит «нажали на строку», решает список
-- настроек, а не экран: иначе экрану пришлось бы знать, сколько у какой настройки
-- вариантов и в каком они порядке.
function UISettings.Next(key, value)
	local item = UISettings.ByKey[key]
	if not item then
		return nil
	end
	if not item.options then
		return not value
	end
	for i, option in item.options do
		if option.value == value then
			return item.options[i % #item.options + 1].value
		end
	end
	return item.options[1].value
end

-- Громкость по положению ползунка value: множитель для SoundGroup.Volume, 1 — как
-- записан звук. Ползунок идёт ровно, а громкость — по кривой. До knee она растёт как
-- (value / knee) ^ curve: ухо слышит громкость примерно по логарифму, и при прямой
-- вся разница сидела бы у левого края, а правая половина ползунка звучала бы почти
-- одинаково. За knee — «гипер», громче записанного: к max громкость доходит до hyper
-- раз, ровным шагом по децибелам (показательная функция).
function UISettings.Gain(key, value)
	local item = UISettings.ByKey[key]
	if not item or not item.knee then
		return nil
	end
	if value <= item.knee then
		return (value / item.knee) ^ item.curve
	end
	return item.hyper ^ ((value - item.knee) / (item.max - item.knee))
end

-- Годится ли пара «ключ-значение», пришедшая от клиента. У переключателя годится
-- только логическое, у выбора — только одно из его собственных значений, у числа —
-- только кратное шагу в пределах min..max: сервер пишет это в профиль, и что попало
-- туда попадать не должно.
function UISettings.Valid(key, value)
	local item = UISettings.ByKey[key]
	if not item then
		return false
	end
	if item.step then
		return type(value) == "number" and value >= item.min and value <= item.max
			and (value - item.min) % item.step == 0
	end
	if item.options then
		return UISettings.Label(key, value) ~= nil
	end
	return type(value) == "boolean"
end

return UISettings
