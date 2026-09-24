-- Сетка проходимости арены и поиск пути по ней (ТЗ v2.1, задача 1). Заменяет Workspace.Path:
-- враги больше не идут по заданному маршруту, а ищут его сами.
--
-- Геометрия сетки (границы, перевод «клетка <-> мир») живёт в ReplicatedStorage.Arena — она нужна
-- и клиенту. Здесь — занятость и поиск пути, то есть чисто серверная правда.
--
-- Занятая клетка не непроходима, а дорогая — это и есть механика грызни из ТЗ: враг выбирает
-- между длинным обходом и коротким проломом, а не между обходом и тупиком.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local Arena = require(ReplicatedStorage:WaitForChild("Arena"))

local DIAGONAL = math.sqrt(2)
-- Размер сетки меняется вместе с локацией (см. Arena.OnChanged внизу) — поэтому не константы.
local cols, rows = Arena.cols, Arena.rows
local CELLS = cols * rows

-- Сторона следа постройки в клетках и половина этой стороны. Клетка теперь мельче
-- постройки в пять раз, и вся занятость считается блоками SPAN x SPAN вокруг центральной
-- клетки, а не одной клеткой.
local SPAN = Arena.span
local REACH = Arena.reach

-- Полуширина тела жука в клетках.
--
-- На крупной сетке этого не требовалось: клетка (4) была как раз с жука (тело 2.6 в ширину),
-- и «клетка свободна» значило «жук туда влезет». На мелкой это уже неправда: между двумя
-- постройками может остаться щель в одну клетку (0.8 студа) — формально проходимая,
-- физически нет. Поиск пути вёл бы в неё всю волну, а толкучка держала бы жуков снаружи:
-- вместо обхода или грызни — куча, топчущаяся у угла.
--
-- Поэтому проходимость считается не по самой клетке, а по телу вокруг неё (blockerMap ниже).
-- Половина следа постройки — ровно тот размер, при котором проходы получаются те же,
-- что были на крупной сетке: жук занимает примерно ту же площадь, что и постройка.
local CLEARANCE = math.floor(SPAN / 2)

local Grid = {}

-- Перевод координат переиспользуется из Arena как есть, а не дублируется: две копии одной
-- и той же арифметики разъехались бы при первом же изменении размера клетки.
Grid.Cols = cols
Grid.Rows = rows
Grid.CellSize = Arena.cellSize
Grid.BuildSize = Arena.buildSize -- сторона постройки в студах: модели строятся по ней, а не по CellSize
Grid.Span = SPAN
Grid.Reach = REACH
Grid.Clearance = CLEARANCE
Grid.InBounds = Arena.InBounds
Grid.ToWorld = Arena.ToWorld
Grid.ToCell = Arena.ToCell
Grid.FitsBuilding = Arena.FitsBuilding
Grid.ClampBuildCell = Arena.ClampBuildCell
-- Радиус следа по фактическому размеру постройки в студах (Towers[key].footprint).
Grid.ReachFor = Arena.ReachFor

-- Пустая клетка — nil, занятая — модель постройки. Ключ плоский числовой, чтобы поиск пути
-- не ходил по вложенным таблицам на каждом соседе. Одна постройка занимает весь свой
-- след — SPAN x SPAN записей, ведущих на одну и ту же модель.
local occupants = {}

-- Постройка -> её центральная клетка. Нужен, чтобы снимать след целиком и чтобы карта
-- проходимости собиралась по постройкам (их десятки), а не по клеткам (их тысячи).
local buildings = {}

local function key(cx, cz)
	return (cz - 1) * cols + cx
end

local function fromKey(cellKey)
	local cz = math.floor((cellKey - 1) / cols) + 1
	return cellKey - (cz - 1) * cols, cz
end

-- Карта проходимости для тела жука: клетка -> постройка, которая мешает в ней стоять.
-- Это тот же occupants, раздутый на CLEARANCE во все стороны.
--
-- Пересобирается лениво — на первый запрос после смены занятости, а не на каждую
-- постройку и не на каждого спросившего: за одну волну её спрашивают десятки тысяч раз.
--
-- Из двух перекрывшихся раздутых следов в клетке остаётся ближний: в него жук и упрётся,
-- его и будет грызть. Иначе выбор был бы «какая постройка записалась последней».
local blockers = nil

-- Поля волн по паре «профиль преодоления + цель» (см. buildField и fieldFor).
local fields = {}

-- Ключи полей, устаревших после смены занятости, и очередь на пересчёт.
--
-- ДО УВЕЛИЧЕНИЯ КАРТЫ поле считалось за 30 мс, и пересчёт всех полей сразу был незаметен.
-- На поле в 75 тысяч клеток он стоит 115 мс, а профилей на поздних волнах шесть-семь
-- (у каждого вида свой chewDps и своё лазанье). Синхронный пересчёт всех на каждую
-- разрушенную постройку — это секунда заморозки сервера посреди волны.
--
-- Поэтому устаревшее поле НЕ выбрасывается, а помечается и пересчитывается ПО ОДНОМУ
-- ЗА КАДР в фоне. Жуки долю секунды идут по прежнему маршруту — в худшем случае
-- упираются в только что поставленную стену и начинают её грызть, что и так верно.
local stale = {}
local queue = {}
local worker = nil

-- Объявление вперёд: сам buildField определён ниже по файлу (ему нужны Heap и NEIGHBOURS),
-- а фоновый пересчёт зовёт его выше. Без этой строки имя внутри pump ушло бы в
-- глобальную (nil): local виден local только с точки своего объявления и ниже.
local buildField

local function blockerMap()
	if blockers then
		return blockers
	end

	blockers = {}
	local nearest = {}

	for building, at in buildings do
		-- След у каждой постройки свой (у Колбы он втрое шире, чем у Стены), поэтому
		-- раздувается её собственный, а не общий REACH: с общим тело жука пролезало бы
		-- сквозь края крупной постройки, которых блокировка не накрывает.
		local reach = at.reach + CLEARANCE
		for dz = -reach, reach do
			local cz = at.z + dz
			if cz >= 1 and cz <= rows then
				for dx = -reach, reach do
					local cx = at.x + dx
					if cx >= 1 and cx <= cols then
						local cellKey = key(cx, cz)
						local distance = math.max(math.abs(dx), math.abs(dz))
						if not blockers[cellKey] or distance < nearest[cellKey] then
							blockers[cellKey] = building
							nearest[cellKey] = distance
						end
					end
				end
			end
		end
	end

	return blockers
end

-- Срабатывает при любом изменении занятости. Враги по нему помечают свой путь устаревшим
-- и пересчитывают его — но не чаще, чем раз в REPATH_INTERVAL (см. EnemySpawner). Сам Grid про
-- врагов ничего не знает и никого не пересчитывает сам.
Grid.Changed = Instance.new("BindableEvent")

-- Занятость сменилась: карта проходимости и все посчитанные по ней поля больше не годятся.
-- Пересчитывать их здесь же нельзя: за один кадр стройки Occupy зовётся несколько раз,
-- а поле нужно только тому, кто собрался идти.
-- Фоновый пересчёт: одно поле за кадр. Запускается только когда есть что считать и сам
-- себя гасит на пустой очереди: вечный цикл на пустом сервере ни к чему.
local function pump()
	if worker then
		return
	end

	worker = task.spawn(function()
		while #queue > 0 do
			RunService.Heartbeat:Wait()

			local cacheKey = table.remove(queue, 1)
			-- Пока ключ ждал очереди, его могли пересчитать синхронно или снести вместе
			-- со всей ареной (Grid.Reset) — тогда считать его заново незачем.
			local entry = stale[cacheKey]
			if entry then
				stale[cacheKey] = nil
				fields[cacheKey] = buildField(entry.profile, entry.goalKey)
			end
		end
		worker = nil
	end)
end

local function invalidate()
	blockers = nil

	-- Поля остаются на месте устаревшими — по ним жуки идут, пока фон не досчитает новые.
	for cacheKey, field in fields do
		if not stale[cacheKey] then
			stale[cacheKey] = { profile = field.profile, goalKey = field.goalKey }
			table.insert(queue, cacheKey)
		end
	end
	pump()

	Grid.Changed:Fire()
end

function Grid.GetOccupant(cx, cz)
	return occupants[key(cx, cz)]
end

-- Что мешает ЖУКУ стоять в этой клетке: постройка, накрывающая её следом или стоящая
-- к ней ближе, чем полуширина жука. По этой карте ищется путь, по ней же жук понимает,
-- во что он упёрся и что грызть (см. EnemySpawner), и по ней же толкучка не вдавливает
-- жука в постройку (см. Crowd).
--
-- GetOccupant отвечает на другой вопрос — «что тут реально стоит», и нужен стройке.
function Grid.GetBlocker(cx, cz)
	return blockerMap()[key(cx, cz)]
end

-- Свободно ли место под постройку с центром в этой клетке: весь след должен помещаться
-- на поле и не пересекать чужие. Проверять одну клетку, как раньше, больше нельзя:
-- постройка крупнее клетки в пять раз.
-- reach — радиус следа ИМЕННО ЭТОЙ постройки (Grid.ReachFor по её footprint). Без него
-- проверка шла общим REACH, то есть по следу 4 студа при реальной платформе Колбы
-- в 10.2 — и вторая Колба спокойно вставала внутрь первой. Встречное направление
-- проверять не надо: каждая уже стоящая постройка записала в occupants весь свой след,
-- поэтому пересечение ловится с любой стороны.
function Grid.IsFree(cx, cz, reach)
	reach = reach or REACH
	if not Arena.FitsBuilding(cx, cz, reach) then
		return false
	end

	for dz = -reach, reach do
		for dx = -reach, reach do
			if occupants[key(cx + dx, cz + dz)] then
				return false
			end
		end
	end

	return true
end

-- Занимает весь след постройки, а не одну клетку. cx/cz — центральная клетка:
-- та самая, что лежит в CellX/CellZ и по которой ставится сама модель.
function Grid.Occupy(cx, cz, building, reach)
	reach = reach or REACH
	-- Радиус запоминается рядом с клеткой: снимать след (Grid.Free) и раздувать его под
	-- тело жука (blockerMap) надо ровно тем же радиусом, каким он записан. Иначе от снесённой
	-- Колбы осталось бы кольцо навсегда занятых клеток, в которые уже никто не построит.
	buildings[building] = { x = cx, z = cz, reach = reach }

	for dz = -reach, reach do
		for dx = -reach, reach do
			if Grid.InBounds(cx + dx, cz + dz) then
				occupants[key(cx + dx, cz + dz)] = building
			end
		end
	end

	invalidate()
end

-- Снимает след постройки, стоящей в этой клетке. След чистится по запомненному центру
-- постройки, а не по переданной клетке: так след снимается целиком даже если Free
-- позовут по краевой клетке, а не по центру — иначе от постройки остался бы огрызок
-- занятых клеток, в которые уже никто не построит и сквозь которые никто не пройдёт.
function Grid.Free(cx, cz)
	local building = occupants[key(cx, cz)]
	local at = building and buildings[building]
	local ax, az = at and at.x or cx, at and at.z or cz
	local reach = at and at.reach or REACH

	for dz = -reach, reach do
		for dx = -reach, reach do
			if Grid.InBounds(ax + dx, az + dz) then
				occupants[key(ax + dx, az + dz)] = nil
			end
		end
	end

	if building then
		buildings[building] = nil
	end

	invalidate()
end

-- Очищает занятость целиком — для рестарта забега, когда арена разбирается полностью.
--
-- Собирать сетку обратно по Free на каждую сносимую постройку — лишний источник рассинхрона:
-- одна пропущенная или лишняя Free — и сетка больше не соответствует тому, что реально стоит
-- на арене, и враги начинают ходить сквозь башни или упираться в пустое место.
function Grid.Reset()
	occupants = {}
	buildings = {}
	-- Арена разбирается целиком — тут поля именно выбрасываются, а не устаревают:
	-- в новом забеге старый маршрут не просто устарел, он бессмыслен.
	table.clear(fields)
	table.clear(stale)
	table.clear(queue)
	invalidate()
end

-- Цена входа в клетку, в шагах. Формула из ТЗ: пустая — 1, занятая — шаг плюс время
-- разрушения плюс постоянный штраф из таблицы Arena.
--
-- С вертикальным интеллектом занятая клетка стоит дешёвле из двух способов её пройти —
-- прогрызть или перелезть (см. Grid.Crossing).
--
-- profile — кто идёт: chewDps (chewDamage * chewRate из
-- Enemies) плюс climbSpeed и climbHeight оттуда же. Они разные у разных врагов — именно
-- поэтому одна и та же стена для роя почти непроходима, для танка дешёва, а для шустрого
-- альпиниста — вообще не стена, а ступенька. Нет профиля — берётся справочный грызун
-- из Arena, который не лезет.
function Grid.CellCost(cx, cz, profile)
	-- Считается по карте проходимости, а не по самой клетке: чтобы встать в клетку
	-- вплотную к постройке, жуку надо её сломать ровно так же, как и чтобы встать в её собственную.
	local blocker = blockerMap()[key(cx, cz)]
	if not blocker then
		return 1
	end
	local _, seconds = Grid.Crossing(blocker, profile)
	return 1 + seconds
end

-- Сколько урона надо вложить в постройку, чтобы её сломать. Обычно это просто её HP,
-- но стойкость к грызне (атрибут ChewResist у Бура, задача #53) — это ровно то же самое,
-- что лишнее HP: укус срезан вдвое — грызть вдвое дольше. Без этой поправки маршрут
-- считал бы Бур вдвое дешевле, чем он есть, и жуки лезли бы сквозь него охотнее, чем стоит.
--
-- Отдельной функцией, а не арифметикой по месту: то же число нужно и полю волн (buildField),
-- а две копии одной формулы разошлись бы, а вместе с ними разошлись бы и маршруты A* и поля.
function Grid.ChewTime(building)
	local hp = building:GetAttribute("HP") or 0
	local resist = math.clamp(building:GetAttribute("ChewResist") or 0, 0, 0.9)
	return hp / (1 - resist)
end

-- Профиль преодоления: чем жук грызёт и как лезет. Один и тот же набор нужен цене клетки,
-- полю волн и самому жуку в момент, когда он упёрся — поэтому разбирается в одном месте.
-- Число вместо таблицы — старый вызов с одним chewDps: такой жук не лезет вовсе.
local function traversal(profile)
	if type(profile) == "number" then
		return profile, 0, 0
	end
	if not profile then
		return Arena.chewDps, 0, 0
	end
	return profile.chewDps or Arena.chewDps, profile.climbSpeed or 0, profile.climbHeight or 0
end

-- Вертикальный интеллект целиком: как именно этот жук будет преодолевать эту преграду
-- и во сколько ему это обойдётся. Возвращает "climb" или "chew" и цену без шага в клетку.
--
-- Здесь живёт весь выбор из дерева решений (дизайн, раздел 1.1). Обход считает сам поиск
-- пути: стоит ли преграда того, чтобы её трогать, видно по тому, какой маршрут выиграл по сумме.
-- А вот «лезть или грызть» — выбор внутри одной клетки, и он обязан быть ОДИН и тот же
-- у цены клетки и у самого жука (см. EnemySpawner): разойдись они — и маршрут был бы посчитан
-- по перелезанию, а жук на месте вставал бы грызть.
--
-- Время подъёма — вверх и вниз (две высоты), плюс постоянный штраф из Arena — точно так же,
-- как у грызни. Обе цены в одних единицах и считаются одинаково — по клетке; это шкала
-- сравнения, а не секундомер, и важно ровно то, что они меряются одной линейкой.
-- Цена клетки тому, кто грызть не умеет вовсе (chewDamage = 0 у Мини, Моли, Спринтера
-- и прочих по design: alchemy_td_enemies.md). Деление на ноль дало бы inf, а inf в поле волн
-- разъедает всю арифметику сравнений (inf < inf ложно, и скатывание перестаёт выбирать
-- соседа вовсе). Большое конечное число даёт тот же смысл — «обходи любой ценой», —
-- но оставляет маршрут сквозь стену крайним вариантом, если другого нет совсем.
local NO_CHEW_COST = 1e6

function Grid.Crossing(building, profile)
	local chewDps, climbSpeed, climbHeight = traversal(profile)
	local chew = chewDps > 0
		and (Grid.ChewTime(building) / chewDps + Arena.chewPenalty)
		or NO_CHEW_COST

	-- Нет атрибута высоты (тип без climbHeight в Towers) — постройка непреодолима сверху,
	-- её только грызут. Так же ведёт себя жук без climbSpeed: весь вертикальный интеллект
	-- выключается отсутствием поля, а не флагом.
	local height = building:GetAttribute("Height")
	if height and climbSpeed > 0 and climbHeight >= height then
		local climb = 2 * height / climbSpeed + Arena.climbPenalty
		if climb < chew then
			return "climb", climb, height
		end
	end

	return "chew", chew, height
end

-- Двоичная куча для открытого списка A*. Перебор списка вместо неё дал бы квадрат,
-- а путь пересчитывается на каждую постройку для каждого живого врага сразу.
local Heap = {}
Heap.__index = Heap

function Heap.new()
	return setmetatable({ nodes = {}, priorities = {}, size = 0 }, Heap)
end

function Heap:swap(a, b)
	self.nodes[a], self.nodes[b] = self.nodes[b], self.nodes[a]
	self.priorities[a], self.priorities[b] = self.priorities[b], self.priorities[a]
end

function Heap:push(node, priority)
	self.size += 1
	self.nodes[self.size] = node
	self.priorities[self.size] = priority

	local i = self.size
	while i > 1 do
		local parent = math.floor(i / 2)
		if self.priorities[parent] <= self.priorities[i] then
			break
		end
		self:swap(parent, i)
		i = parent
	end
end

function Heap:pop()
	if self.size == 0 then
		return nil
	end

	local top = self.nodes[1]
	self:swap(1, self.size)
	self.nodes[self.size] = nil
	self.priorities[self.size] = nil
	self.size -= 1

	local i = 1
	while true do
		local left, right = i * 2, i * 2 + 1
		local smallest = i
		if left <= self.size and self.priorities[left] < self.priorities[smallest] then
			smallest = left
		end
		if right <= self.size and self.priorities[right] < self.priorities[smallest] then
			smallest = right
		end
		if smallest == i then
			break
		end
		self:swap(smallest, i)
		i = smallest
	end

	return top
end

-- Восемь соседей: по четырём жуки ходили бы ступеньками с прямыми углами.
local NEIGHBOURS = {
	{ 1, 0, 1 },
	{ -1, 0, 1 },
	{ 0, 1, 1 },
	{ 0, -1, 1 },
	{ 1, 1, DIAGONAL },
	{ 1, -1, DIAGONAL },
	{ -1, 1, DIAGONAL },
	{ -1, -1, DIAGONAL },
}

-- Октильная оценка: никогда не завышает остаток при восьми соседях и минимальной цене 1,
-- поэтому A* остаётся точным.
local function heuristic(ax, az, bx, bz)
	local dx, dz = math.abs(ax - bx), math.abs(az - bz)
	return (dx + dz) + (DIAGONAL - 2) * math.min(dx, dz)
end

-- Ищет самый дешёвый маршрут от клетки к клетке. Возвращает список { {x, z}, ... },
-- включая стартовую и конечную клетки, либо nil, если пути нет совсем.
--
-- Маршрут к выходу ищется не этим, а GetRoute по полю волн: на мелкой сетке отдельный
-- A* на каждого жука стоит в тридцать раз дороже, чем стоил на крупной. Здесь остался
-- случай произвольной цели — фолбэк «идти к ближайшей постройке» и проверки вручную.
-- Цена и проходимость у обоих общие (blockerMap и CellCost), иначе они разошлись бы.
function Grid.FindPath(startX, startZ, goalX, goalZ, profile)
	if not Grid.InBounds(startX, startZ) or not Grid.InBounds(goalX, goalZ) then
		return nil
	end

	local blocked = blockerMap()
	local startKey, goalKey = key(startX, startZ), key(goalX, goalZ)
	local cameFrom = {}
	local gScore = { [startKey] = 0 }
	local closed = {}

	local open = Heap.new()
	open:push(startKey, heuristic(startX, startZ, goalX, goalZ))

	while true do
		local current = open:pop()
		if not current then
			break
		end

		if current == goalKey then
			local path = {}
			local node = current
			while node do
				local cx, cz = fromKey(node)
				table.insert(path, 1, { x = cx, z = cz })
				node = cameFrom[node]
			end
			return path
		end

		if not closed[current] then
			closed[current] = true
			local cx, cz = fromKey(current)

			for _, step in NEIGHBOURS do
				local nx, nz = cx + step[1], cz + step[2]
				if Grid.InBounds(nx, nz) then
					-- По диагонали можно только когда обе смежные клетки свободны: иначе жук
					-- просачивается в щель между углами двух построек, не тронув ни одну, и
					-- любая стена по диагонали перестаёт быть стеной.
					local straight = step[1] == 0 or step[2] == 0
					local passable = straight
						or (blocked[key(cx + step[1], cz)] == nil and blocked[key(cx, cz + step[2])] == nil)

					if passable then
						local neighbourKey = key(nx, nz)
						local tentative = gScore[current] + Grid.CellCost(nx, nz, profile) * step[3]
						if tentative < (gScore[neighbourKey] or math.huge) then
							gScore[neighbourKey] = tentative
							cameFrom[neighbourKey] = current
							open:push(neighbourKey, tentative + heuristic(nx, nz, goalX, goalZ))
						end
					end
				end
			end
		end
	end

	return nil
end

-- Поле волн: одна Дейкстра от выхода даёт остаток пути сразу для ВСЕХ клеток — то есть
-- маршрут любому жуку с таким chewDps, вместо отдельного A* на каждого.
--
-- На крупной сетке (375 клеток) поиск на жука стоил 0.7 мс, и двадцать поисков на каждую
-- поставленную башню были незаметны. На мелкой (9375 клеток) тот же поиск стоит уже 23 мс,
-- а двадцать штук — это полсекунды заморозки сервера на каждую постройку. Поле же
-- считается один раз на смену занятости, а жук потом только скатывается по нему вниз
-- (GetRoute), а это доли миллисекунды.
--
-- Полей столько, сколько разных профилей преодоления среди живых врагов (обычно два-три):
-- цена клетки зависит от того, как быстро грызёт и как высоко лезет тот, для кого ищется путь. Поле строится лениво:
-- класс, которого нет на арене, не стоит ничего.
-- goalKey — клетка, к которой считается поле. Раньше это всегда был выход; с кастами
-- (design: alchemy_td_enemies.md) целей стало две: выход и лабораторный стол. Обе общие
-- для всех жуков сразу, поэтому обе остаются полями — по одному на цель и профиль,
-- а не по полю на жука.
--
-- Точечные цели одного жука (турель, труп, светящаяся турель у Моли) полем не считаются
-- никогда: поле на 75 тысяч клеток стоит около 120 мс, и заводить его под каждую турель
-- значило бы вешать сервер на каждую смену цели. Такие цели ведутся либо прямым ходом
-- (летающие), либо разовым A* (Grid.FindPath) — их единицы, а не вся волна.
function buildField(profile, goalKey)
	local blocked = blockerMap()

	-- Способ преодоления и его цена снимаются один раз на постройку, а не читаются атрибутами на каждой
	-- клетке: GetAttribute — самая дорогая операция в этом цикле, а построек десятки
	-- против тысяч клеток.
	local crossing = {}
	for building in buildings do
		local _, seconds = Grid.Crossing(building, profile)
		crossing[building] = seconds
	end

	-- Цена входа в клетку — плоским массивом на всю сетку: по ней будет 75 тысяч
	-- чтений за один пересчёт, и словарь на тех же чтениях заметно дороже.
	local cost = table.create(CELLS, 1)
	for cellKey, building in blocked do
		cost[cellKey] = 1 + (crossing[building] or 0)
	end

	local dist = table.create(CELLS, math.huge)
	local closed = table.create(CELLS, false)

	dist[goalKey] = 0

	local open = Heap.new()
	open:push(goalKey, 0)

	while true do
		local current = open:pop()
		if not current then
			break
		end

		if not closed[current] then
			closed[current] = true
			local cx, cz = fromKey(current)

			-- Поиск идёт от выхода назад, а шаг жук делает вперёд — поэтому шаг
			-- «сосед -> текущая» стоит цену входа в ТЕКУЩУЮ, а не в соседнюю.
			-- Перепутать здесь стороны — значит посчитать грызню стены на один шаг раньше,
			-- чем она случится, и маршруты разошлись бы с A*.
			local stepCost = cost[current]
			local base = dist[current]

			for _, step in NEIGHBOURS do
				local nx, nz = cx + step[1], cz + step[2]
				if nx >= 1 and nx <= cols and nz >= 1 and nz <= rows then
					-- Тот же запрет диагонали между двумя углами, что и в A*: пара клеток
					-- между соседом и текущей одна и та же в обе стороны, поэтому проверка
					-- симметрична и в обратном поиске читается так же.
					local straight = step[1] == 0 or step[2] == 0
					if straight
						or (blocked[key(cx + step[1], cz)] == nil and blocked[key(cx, cz + step[2])] == nil) then
						local neighbourKey = key(nx, nz)
						local tentative = base + stepCost * step[3]
						if tentative < dist[neighbourKey] then
							dist[neighbourKey] = tentative
							open:push(neighbourKey, tentative)
						end
					end
				end
			end
		end
	end

	-- Профиль и цель хранятся вместе с полем: фоновому пересчёту надо знать, что именно
	-- он пересчитывает, а восстанавливать это разбором строкового ключа было бы глупо.
	return { dist = dist, cost = cost, blocked = blocked, goalKey = goalKey, profile = profile }
end

-- Ключ поля — весь профиль, а не один chewDps: цена клетки теперь зависит ещё и от того,
-- как жук лезет. Полей по-прежнему столько, сколько разных видов на арене (обычно два-три).
local function fieldFor(profile, goalKey)
	local chewDps, climbSpeed, climbHeight = traversal(profile)
	local cacheKey = string.format("%g|%g|%g|%d", chewDps, climbSpeed, climbHeight, goalKey)

	local field = fields[cacheKey]
	if not field then
		-- Первый запрос этого профиля и цели — считаем сразу: отдавать жуку нечего,
		-- а без маршрута он просто стоит на месте.
		field = buildField(profile, goalKey)
		fields[cacheKey] = field
		-- Если этот же ключ ждал в очереди, считать его второй раз незачем.
		stale[cacheKey] = nil
	end
	return field
end

-- Маршрут жука к выходу: скатывание по полю волн от его клетки. Формат тот же, что у FindPath:
-- список { {x, z}, ... }, включая стартовую и конечную клетки.
--
-- Маршрут получается ровно тот же, что дал бы A* с тем же chewDps: шаг всегда в соседа
-- с минимальным «войти в него плюс его остаток», а это и есть то, по чему поле считалось.
-- Поэтому остаток строго убывает на каждом шаге и зациклиться скатывание не может.
-- Маршрут к произвольной ОБЩЕЙ цели (выход, лабораторный стол). Цель — клетка, а не
-- враг: поле считается один раз на всю волну и годится каждому жуку с тем же профилем.
function Grid.GetRouteTo(fromX, fromZ, profile, goalX, goalZ)
	if not Grid.InBounds(fromX, fromZ) or not Grid.InBounds(goalX, goalZ) then
		return nil
	end

	local field = fieldFor(profile, key(goalX, goalZ))
	local dist, cost, blocked = field.dist, field.cost, field.blocked

	local cx, cz = fromX, fromZ
	if dist[key(cx, cz)] == math.huge then
		return nil
	end

	local path = { { x = cx, z = cz } }

	while key(cx, cz) ~= field.goalKey do
		local bestX, bestZ, bestScore = nil, nil, math.huge

		for _, step in NEIGHBOURS do
			local nx, nz = cx + step[1], cz + step[2]
			if nx >= 1 and nx <= cols and nz >= 1 and nz <= rows then
				local straight = step[1] == 0 or step[2] == 0
				if straight
					or (blocked[key(cx + step[1], cz)] == nil and blocked[key(cx, cz + step[2])] == nil) then
					local neighbourKey = key(nx, nz)
					-- Остаток пути через соседа: вход в него плюс его собственный остаток.
					local score = dist[neighbourKey] + cost[neighbourKey] * step[3]
					if score < bestScore then
						bestX, bestZ, bestScore = nx, nz, score
					end
				end
			end
		end

		if not bestX or #path > CELLS then
			return nil -- страховка: скатывание строго убывает, сюда попасть не должно
		end

		cx, cz = bestX, bestZ
		table.insert(path, { x = cx, z = cz })
	end

	return path
end

-- Маршрут к выходу — частный случай GetRouteTo. Оставлен отдельной функцией: так зовут
-- его те, кому цель выбирать не надо (прежнее поведение до появления каст).
function Grid.GetRoute(fromX, fromZ, profile)
	local exitX, exitZ = Grid.GetExitCell()
	return Grid.GetRouteTo(fromX, fromZ, profile, exitX, exitZ)
end

-- Схлопывает подряд идущие клетки одного направления в одну точку излома. Маршрут по мелкой
-- сетке — это три сотни клеток, из которых почти все лежат на прямой; жуку нужны только
-- точки поворота, а лишние — это Vector3 на каждую клетку каждого жука на каждый пересчёт.
--
-- Клетка, на которой меняется помеха, остаётся точкой всегда: по ней жук останавливается
-- и начинает грызть (см. EnemySpawner). Схлопни её в прямой отрезок — и он бы ехал сквозь
-- постройку вместо того, чтобы её грызть.
function Grid.Simplify(path)
	if not path or #path < 3 then
		return path
	end

	local blocked = blockerMap()
	local simplified = { path[1] }

	for i = 2, #path - 1 do
		local previous, cell, following = path[i - 1], path[i], path[i + 1]
		local turn = (cell.x - previous.x) ~= (following.x - cell.x)
			or (cell.z - previous.z) ~= (following.z - cell.z)
		local here = blocked[key(cell.x, cell.z)]
		local edge = here ~= blocked[key(previous.x, previous.z)]
			or here ~= blocked[key(following.x, following.z)]

		if turn or edge then
			table.insert(simplified, cell)
		end
	end

	table.insert(simplified, path[#path])
	return simplified
end

-- Фолбэк из ТЗ на случай, когда пути нет совсем: враг идёт к ближайшей постройке.
--
-- Сейчас сработать не должен никогда: занятая клетка дорогая, но проходимая, поэтому
-- маршрут есть всегда. Правило всё равно реализовано: любое будущее изменение, делающее
-- часть клеток непроходимыми, иначе молча подвесит всю волну насмерть.
function Grid.FindNearestBuilding(fromX, fromZ)
	local bestCell, bestDistance = nil, math.huge
	-- По постройкам, а не по занятым клеткам: клеток у каждой теперь 25, и перебор
	-- по ним дал бы тот же ответ за двадцать пять проходов по одной и той же постройке.
	for _, at in buildings do
		local distance = heuristic(fromX, fromZ, at.x, at.z)
		if distance < bestDistance then
			bestCell, bestDistance = { x = at.x, z = at.z }, distance
		end
	end
	return bestCell
end

function Grid.GetEntranceCell()
	return Grid.ToCell(Arena.entrance)
end

-- В клетке пролома строить нельзя. Формально она свободна, но враги появляются ровно в ней:
-- башня там — это затычка в горлышке, которая ставится один раз и отменяет весь лабиринт.
function Grid.IsEntranceCell(cx, cz, reach)
	reach = reach or REACH
	local entranceX, entranceZ = Grid.GetEntranceCell()
	-- Проверяется весь след постройки, а не её центр: запрет всё тот же — нельзя
	-- накрыть клетку пролома, — но накрывает её теперь любая из 25 клеток следа.
	return math.abs(cx - entranceX) <= reach and math.abs(cz - entranceZ) <= reach
end

function Grid.GetExitCell()
	return Grid.ToCell(Arena.exit)
end

-- На клетке выхода строить тоже нельзя — та же вырожденная затычка, что и с проломом:
-- формально клетка свободна, но башня ровно на ней — вырожденная затычка в горлышке,
-- просто с другой стороны лабиринта. До задачи #25 этот запрет был только у пролома.
function Grid.IsExitCell(cx, cz, reach)
	reach = reach or REACH
	local exitX, exitZ = Grid.GetExitCell()
	return math.abs(cx - exitX) <= reach and math.abs(cz - exitZ) <= reach
end

-- На клетке лабораторного стола строить нельзя. До лаборатории v1.6 стол стоял на
-- выходе, и этот запрет давал IsExitCell; теперь выход — дверь, а стол стоит отдельно,
-- и без своей проверки турель вставала бы прямо в столешницу.
-- Проверяется весь габарит стола, а не его центр (см. Arena.IsTableCell).
function Grid.IsTableCell(cx, cz, reach)
	return Arena.IsTableCell(cx, cz, reach or REACH)
end

-- Сменилась локация — у сетки другой размер, а старая занятость и маршруты к новой
-- геометрии отношения не имеют.
Arena.OnChanged(function()
	cols, rows = Arena.cols, Arena.rows
	CELLS = cols * rows
	Grid.Cols = cols
	Grid.Rows = rows
	Grid.Reset()
end)

return Grid
