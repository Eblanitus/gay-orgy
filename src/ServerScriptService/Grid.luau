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

-- Следы построек прямоугольниками в мировых координатах (Grid.Footprints). Тоже ленивый кэш,
-- сбрасывается вместе с картой проходимости.
local footprints = nil

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
	footprints = nil

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

-- Свойства постройки сменились без смены занятости (Пандус, хитин на стене): цена её
-- клеток другая, и поля, посчитанные по старой цене, устарели так же, как после стройки.
function Grid.Touch()
	invalidate()
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

-- Настоящие следы построек — по прямоугольнику на постройку, в мировых осях: minX/maxX/minZ/maxZ
-- (край крайней клетки следа, без запаса на тело) и сама постройка. Нужны толкучке (Crowd):
-- телу жука надо не пускать в след капсулу целиком, а карта проходимости (GetBlocker) и
-- GetOccupant отвечают только про центр: широкий жук, прижатый соседями, въезжал бы в
-- постройку боком и носом, пока его центр не коснётся следа.
-- Таблицу не менять: она общая и живёт до следующей смены занятости.
function Grid.Footprints()
	if footprints then
		return footprints
	end

	footprints = {}
	local half = Arena.cellSize / 2
	for building, at in buildings do
		local centre = Arena.ToWorld(at.x, at.z)
		local span = at.reach * Arena.cellSize + half
		table.insert(footprints, {
			minX = centre.X - span,
			maxX = centre.X + span,
			minZ = centre.Z - span,
			maxZ = centre.Z + span,
			building = building,
		})
	end
	return footprints
end

-- Плоское расстояние от точки до следа постройки (0 — точка в следе) или nil, если постройки
-- нет в сетке. Для всего, что бьёт или чинит постройку «в радиусе»: след крупной постройки
-- (Мортира, Инжектор) — квадрат в двадцать с лишним студов, и по её пивоту взрыв у самого
-- края следа её не задевал.
function Grid.DistanceTo(building, point)
	local at = buildings[building]
	if not at then
		return nil
	end
	local centre = Arena.ToWorld(at.x, at.z)
	local span = at.reach * Arena.cellSize + Arena.cellSize / 2
	local dx = math.max(math.abs(point.X - centre.X) - span, 0)
	local dz = math.max(math.abs(point.Z - centre.Z) - span, 0)
	return math.sqrt(dx * dx + dz * dz)
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
--
-- bodyHeight — высота спины жука над полом (EnemyBody.TopHeight). По ней решается, пролезет ли
-- он под постройкой (подлаз, см. Crossing). 0 — неизвестна: такой жук под постройки не лезет.
local function traversal(profile)
	if type(profile) == "number" then
		return profile, 0, 0, 0
	end
	if not profile then
		return Arena.chewDps, 0, 0, 0
	end
	return profile.chewDps or Arena.chewDps, profile.climbSpeed or 0, profile.climbHeight or 0,
		profile.bodyHeight or 0
end

-- Пролезет ли жук с такой высотой спины под этой постройкой. Просвет — атрибут CrawlGap
-- (ставит TowerBuilder по Towers.crawlGap); нет атрибута — под постройкой не пролезть.
-- Отдельной функцией: то же спрашивает толкучка (Crowd) — не выталкивать из-под постройки
-- того, кто под ней ползёт.
function Grid.FitsUnder(building, bodyHeight)
	if not bodyHeight or bodyHeight <= 0 then
		return false
	end
	local gap = building:GetAttribute("CrawlGap")
	return gap ~= nil and bodyHeight <= gap
end

-- Вертикальный интеллект целиком: как именно этот жук будет преодолевать эту преграду
-- и во сколько ему это обойдётся. Возвращает "climb" или "chew" и цену без шага в клетку.
--
-- Здесь живёт весь выбор из дерева решений. Обход считает сам поиск
-- пути: стоит ли преграда того, чтобы её трогать, видно по тому, какой маршрут выиграл по сумме.
-- А вот «лезть или грызть» — выбор внутри одной клетки, и он обязан быть ОДИН и тот же
-- у цены клетки и у самого жука (см. EnemySpawner): разойдись они — и маршрут был бы посчитан
-- по перелезанию, а жук на месте вставал бы грызть.
--
-- Время подъёма — вверх и вниз (две высоты), плюс постоянный штраф из Arena — точно так же,
-- как у грызни. Обе цены в одних единицах и считаются одинаково — по клетке; это шкала
-- сравнения, а не секундомер, и важно ровно то, что они меряются одной линейкой.
-- Цена клетки тому, кто грызть не умеет вовсе (chewDamage = 0 у Мини, Моли, Спринтера
-- и прочих по вики). Деление на ноль дало бы inf, а inf в поле волн
-- разъедает всю арифметику сравнений (inf < inf ложно, и скатывание перестаёт выбирать
-- соседа вовсе). Большое конечное число даёт тот же смысл — «обходи любой ценой», —
-- но оставляет маршрут сквозь стену крайним вариантом, если другого нет совсем.
local NO_CHEW_COST = 1e6

-- Подлаз — третий способ, кроме «перелезть» и «прогрызть»: мелкий жук проползает под
-- платформой, большой туда не влезает и грызёт. Если пролезает — это всегда дешевле обоих:
-- он не останавливается, только ползёт медленнее (Arena.crawlSpeed). Цена — сколько
-- лишнего времени займёт клетка под постройкой по сравнению с обычным шагом.
local CRAWL_COST = 1 / Arena.crawlSpeed - 1

-- Как жук лезет именно на эту постройку. Обычно — своими climbSpeed/climbHeight. Но к стене
-- с Пандусом Строителя или покрытой хитином Архитектора забегают все: «по пандусу жуки
-- забегают на стену и спрыгивают за ней. Мелкие проходят быстро, крупные теряют скорость».
-- scale — масштаб жука; нет его (поле волн считает на всех сразу) — скорость Стандарта.
-- Своя скорость лучше пандусной — остаётся своя: альпинисту пандус не мешает.
-- Отрицательная climbSpeed — «не лазает вовсе» (Хмурый брон): ему и пандус не лестница.
function Grid.ClimbFor(building, climbSpeed, climbHeight, scale)
	if climbSpeed >= 0 and (building:GetAttribute("Ramped") or building:GetAttribute("Chitin")) then
		local factor = 1
		if scale and scale > 0 then
			local clamp = Arena.rampScaleClamp
			factor = math.clamp(Arena.rampRefScale / scale, clamp[1], clamp[2])
		end
		return math.max(climbSpeed, Arena.rampSpeed * factor), math.huge
	end
	return climbSpeed, climbHeight
end

function Grid.Crossing(building, profile)
	local chewDps, climbSpeed, climbHeight, bodyHeight = traversal(profile)
	climbSpeed, climbHeight = Grid.ClimbFor(building, climbSpeed, climbHeight, nil)
	if Grid.FitsUnder(building, bodyHeight) then
		return "under", CRAWL_COST, building:GetAttribute("CrawlGap")
	end
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
-- maxNodes — потолок раскрытых клеток. Точечные цели одного жука (укрытие, место за
-- вожаком, засада) ищутся этим A* на ходу и часто: недостижимая точка без потолка
-- обходила бы всю сетку в 75 тысяч клеток на каждый вызов. Упёрлись в потолок — пути нет.
function Grid.FindPath(startX, startZ, goalX, goalZ, profile, maxNodes)
	if not Grid.InBounds(startX, startZ) or not Grid.InBounds(goalX, goalZ) then
		return nil
	end

	local blocked = blockerMap()
	-- Цена прохода постройки — один раз на постройку за поиск, а не на каждую её клетку:
	-- Crossing читает атрибуты, а клеток у постройки десятки (то же, что в buildField).
	local crossing = {}
	local function cellCost(nx, nz)
		local blocker = blocked[key(nx, nz)]
		if not blocker then
			return 1
		end
		local seconds = crossing[blocker]
		if not seconds then
			local _, s = Grid.Crossing(blocker, profile)
			seconds = s
			crossing[blocker] = seconds
		end
		return 1 + seconds
	end
	local expanded = 0
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
			expanded += 1
			if maxNodes and expanded > maxNodes then
				return nil
			end
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
						local tentative = gScore[current] + cellCost(nx, nz) * step[3]
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
-- целей стало две: выход и лабораторный стол. Обе общие
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
	local chewDps, climbSpeed, climbHeight, bodyHeight = traversal(profile)
	-- Высота спины — только «пролезает ли под каждой постройкой»: жуки разной высоты, которые
	-- пролезают под одними и теми же постройками, делят одно поле. Иначе Мини со случайным
	-- масштабом заводили бы по полю на каждого.
	-- Пролезает он ровно под теми, у кого просвет не ниже его спины, — и этот набор целиком
	-- задаётся самым низким из таких просветов. Он и идёт в ключ.
	local under = 0
	if bodyHeight > 0 then
		under = math.huge
		for building in buildings do
			local gap = building:GetAttribute("CrawlGap")
			if gap and gap >= bodyHeight and gap < under then
				under = gap
			end
		end
		if under == math.huge then
			under = 0
		end
	end
	local cacheKey = string.format("%g|%g|%g|%g|%d", chewDps, climbSpeed, climbHeight, under, goalKey)

	local field = fields[cacheKey]
	if not field then
		-- Первый запрос этого профиля и цели — считаем сразу: отдавать жуку нечего,
		-- а без маршрута он просто стоит на месте.
		-- Поле считается и хранится по профилю КЛЮЧА, а не по профилю спросившего: высота
		-- спины в нём — тот самый просвет из ключа. Иначе фоновый пересчёт после новой
		-- постройки считал бы его по росту первого спросившего, а делят поле жуки разного роста.
		field = buildField({
			chewDps = chewDps, climbSpeed = climbSpeed, climbHeight = climbHeight, bodyHeight = under,
		}, goalKey)
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
--
-- wander — блуждание (по вики: разведчик «блуждает по полу», «десять солдат идут десятью
-- разными путями»). Поле при этом то же самое, общее на всю волну, — меняется только
-- скатывание: на части шагов жук берёт не лучшего соседа, а соседа в свою сторону
-- (side), если тот всё ещё строго ближе к цели и дороже лучшего не больше чем на budget.
-- Строгое убывание остатка сохраняется, поэтому маршрут по-прежнему конечен и приходит
-- в цель, а дорогая клетка (стена) в сторону не выбирается — её цена не влезает в budget.
--   chance — доля шагов со сворачиванием; flip — через сколько клеток сменить сторону
--   (петляние разведчика); seed — свой у жука: маршрут повторяется, пока мир не изменится.
function Grid.GetRouteTo(fromX, fromZ, profile, goalX, goalZ, wander)
	if not Grid.InBounds(fromX, fromZ) or not Grid.InBounds(goalX, goalZ) then
		return nil
	end
	local rng = wander and Random.new(wander.seed or 1)
	local side = wander and (wander.side or 1) or 1
	local sinceFlip = 0

	local field = fieldFor(profile, key(goalX, goalZ))
	local dist, cost, blocked = field.dist, field.cost, field.blocked

	local cx, cz = fromX, fromZ
	if dist[key(cx, cz)] == math.huge then
		return nil
	end

	local path = { { x = cx, z = cz } }

	while key(cx, cz) ~= field.goalKey do
		local bestX, bestZ, bestScore = nil, nil, math.huge
		local here = dist[key(cx, cz)]
		local candidates = wander and {}

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
					if candidates and dist[neighbourKey] < here then
						table.insert(candidates, { x = nx, z = nz, dx = step[1], dz = step[2], score = score })
					end
				end
			end
		end

		if not bestX or #path > CELLS then
			return nil -- страховка: скатывание строго убывает, сюда попасть не должно
		end

		-- Блуждание: сосед в свою сторону от лучшего направления. Сторона — знак
		-- векторного произведения «лучший шаг × шаг кандидата».
		if candidates and rng:NextNumber() < (wander.chance or 1) then
			local bdx, bdz = bestX - cx, bestZ - cz
			local pick, pickTurn = nil, 0
			for _, candidate in candidates do
				if candidate.score <= bestScore + (wander.budget or 1) then
					local turn = (bdx * candidate.dz - bdz * candidate.dx) * side
					if turn > pickTurn or (turn == pickTurn and pick and candidate.score < pick.score) then
						pick, pickTurn = candidate, turn
					end
				end
			end
			if pick then
				bestX, bestZ = pick.x, pick.z
			end
			if wander.flip then
				sinceFlip += 1
				if sinceFlip >= wander.flip then
					sinceFlip = 0
					side = -side
				end
			end
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

-- Видна ли клетка b из клетки a по прямой для тела жука: каждая клетка, которую задевает
-- отрезок между их центрами, свободна. Карта проходимости уже раздута на полуширину тела
-- (blockerMap), поэтому «центр прошёл по свободным клеткам» и значит «жук пролез».
-- Отрезок через угол двух клеток требует свободными обе — тот же запрет щели между углами,
-- что у диагонального шага в поиске пути.
local function clearLine(blocked, ax, az, bx, bz)
	local dx, dz = bx - ax, bz - az
	local nx, nz = math.abs(dx), math.abs(dz)
	local sx, sz = dx > 0 and 1 or -1, dz > 0 and 1 or -1
	local x, z = ax, az
	local ix, iz = 0, 0
	while ix < nx or iz < nz do
		-- Какую грань клетки отрезок пересекает раньше: вертикальную (шаг по x) или
		-- горизонтальную (по z). Сравнение в целых числах — без накопления ошибки.
		local decision = (1 + 2 * ix) * nz - (1 + 2 * iz) * nx
		if decision == 0 then
			if blocked[key(x + sx, z)] or blocked[key(x, z + sz)] then
				return false
			end
			x += sx
			z += sz
			ix += 1
			iz += 1
		elseif decision < 0 then
			x += sx
			ix += 1
		else
			z += sz
			iz += 1
		end
		if blocked[key(x, z)] then
			return false
		end
	end
	return true
end

-- Насколько далеко клетка c отходит от отрезка a–b, в клетках.
local function offLine(a, b, c)
	local abx, abz = b.x - a.x, b.z - a.z
	local acx, acz = c.x - a.x, c.z - a.z
	local length2 = abx * abx + abz * abz
	local t = length2 > 0 and math.clamp((acx * abx + acz * abz) / length2, 0, 1) or 0
	local px, pz = acx - abx * t, acz - abz * t
	return math.sqrt(px * px + pz * pz)
end

-- Насколько блуждающий маршрут можно спрямлять (см. Simplify), в клетках. Мелкая дрожь
-- (шаг вбок на клетку) срезается, а сам рисунок блуждания — петли разведчика на десяток
-- клеток, свой бок у солдата — остаётся.
local WANDER_TOLERANCE = 2

-- Превращает маршрут по клеткам в точки, между которыми жук идёт по прямой.
--
-- Маршрут по сетке ходит только в восемь сторон: по прямой и под 45°. Цель под другим углом
-- он берёт ступенькой — сначала прямо, потом наискосок, — а блуждание солдата дробило его
-- на изломы через каждую клетку-две. Схлопывать только подряд идущие клетки одного
-- направления (как было раньше) — значит оставить каждый такой излом точкой, и жук шёл
-- зигзагом от точки к точке. Поэтому на свободном полу точки ставятся по прямой видимости:
-- из точки — сразу в самую дальнюю клетку маршрута, до которой по прямой ничего не мешает.
-- Отрезок не длиннее того куска маршрута, который он заменяет, — путь только короче.
--
-- Клетка, на которой меняется помеха, остаётся точкой всегда: по ней жук останавливается
-- и начинает грызть (см. EnemySpawner). Схлопни её в прямой отрезок — и он бы ехал сквозь
-- постройку вместо того, чтобы её грызть. Внутри постройки (лезет, ползёт) — как раньше,
-- точка на каждом повороте.
--
-- keepShape — маршрут блуждающий (GetRouteTo с wander): спрямляется только там, где
-- клетки маршрута отходят от прямой не дальше WANDER_TOLERANCE, иначе прямая видимость
-- стёрла бы само блуждание.
function Grid.Simplify(path, keepShape)
	if not path or #path < 3 then
		return path
	end

	local blocked = blockerMap()
	local count = #path

	local function blockerAt(i)
		local cell = path[i]
		return blocked[key(cell.x, cell.z)]
	end

	-- Обязательные точки: концы, смена помехи и повороты по постройке.
	local hard = { [1] = true, [count] = true }
	for i = 2, count - 1 do
		local previous, cell, following = path[i - 1], path[i], path[i + 1]
		local here = blockerAt(i)
		local edge = here ~= blockerAt(i - 1) or here ~= blockerAt(i + 1)
		local turn = (cell.x - previous.x) ~= (following.x - cell.x)
			or (cell.z - previous.z) ~= (following.z - cell.z)
		if edge or (here and turn) then
			hard[i] = true
		end
	end

	-- Можно ли идти из a прямо в b, минуя клетки маршрута между ними.
	local function straight(a, b)
		local from, to = path[a], path[b]
		if not clearLine(blocked, from.x, from.z, to.x, to.z) then
			return false
		end
		if keepShape then
			for i = a + 1, b - 1 do
				if offLine(from, to, path[i]) > WANDER_TOLERANCE then
					return false
				end
			end
		end
		return true
	end

	local simplified = { path[1] }
	local anchor = 1
	while anchor < count do
		local stop = anchor + 1
		while not hard[stop] do
			stop += 1
		end

		if blockerAt(anchor + 1) ~= nil then
			-- Внутри постройки: следующая обязательная точка, без спрямления.
			table.insert(simplified, path[stop])
			anchor = stop
		else
			-- Свободный пол до stop. Самая дальняя видимая клетка ищется удвоением шага,
			-- потом делением пополам: проверка прямой стоит её длину, и перебор каждой
			-- клетки подряд дал бы квадрат от длины маршрута на каждого жука.
			local good, bad = anchor + 1, nil
			local probe = 2
			while true do
				local j = anchor + probe
				if j >= stop then
					if straight(anchor, stop) then
						good = stop
					else
						bad = stop
					end
					break
				end
				if straight(anchor, j) then
					good = j
					probe *= 2
				else
					bad = j
					break
				end
			end
			while bad and bad - good > 1 do
				local middle = math.floor((good + bad) / 2)
				if straight(anchor, middle) then
					good = middle
				else
					bad = middle
				end
			end
			table.insert(simplified, path[good])
			anchor = good
		end
	end

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
