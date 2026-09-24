-- Арена и её сетка координат: числа баланса плюс перевод «клетка <-> мир».
-- По ТЗ v2.1 всё, что придётся крутить при балансе лабиринта, лежит здесь таблицей,
-- а не константами внутри кода.
--
-- Занятость клеток и поиск пути — в ServerScriptService.Grid; здесь только геометрия, потому
-- что она нужна и клиенту (подсветка клетки под курсором при постройке), а занятость —
-- серверная правда, которую клиенту знать незачем.
--
-- Геометрия берётся из активной локации — папки Workspace.Location (пол ArenaFloor, стены
-- Walls, маркеры Markers.Entrance/Exit/PlayerSpawn, стол CraftTable). Локацию меняет
-- ServerScriptService.LocationService: он подменяет содержимое папки и зовёт Arena.Rebind,
-- после чего всё, что подписано на Arena.OnChanged, пересчитывает свои границы.
--
-- Сервер пишет размеры пола и позиции входа/выхода атрибутами на Location, клиент читает
-- атрибуты: с StreamingEnabled сами детали у клиента могут ещё не прийти.
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local IS_SERVER = RunService:IsServer()
local location = Workspace:WaitForChild("Location")

local Arena = {
	-- Шаг сетки. Раньше был равен размеру постройки (4) — клетка выходила с игрока ростом,
	-- и лабиринт двигался только крупными ступенями. Теперь клетка в пять раз мельче
	-- постройки: сетка 125 x 75 на том же поле 100 x 60, шаг установки 0.8 студа.
	cellSize = 0.8,

	-- Сторона постройки в студах — она не изменилась. Колба по-прежнему ~2.8 студа
	-- в поперечнике, Стена — блок 3.6. Постройка занимает не клетку, а блок span x span
	-- клеток вокруг своей (см. Arena.span и Grid.Occupy): мельче стала сетка, а не то,
	-- что на ней стоит.
	buildSize = 4,

	-- Цена клетки для поиска пути (см. Grid.CellCost). Пустая клетка стоит 1 шаг; занятая —
	-- шаг плюс время разрушения плюс постоянный штраф.
	--
	-- Штраф нужен, чтобы прогрызание всегда выходило дороже, чем считает арифметика. Без него
	-- игрок ставит одну дешёвую стену приманкой, враги считают её выгодной и идут насквозь
	-- вместо того, чтобы обходить весь лабиринт.
	chewPenalty = 12, -- в шагах сетки

	-- То же самое для перелезания (вертикальный интеллект, см. Grid.Crossing). Без штрафа
	-- арифметика говорит, что перелезть выгоднее почти всегда, и стены перестают гнать
	-- жука в обход вовсе — лабиринт схлопывается в прямую линию поверх построек.
	-- Меньше, чем у грызни, нарочно: перелезть всё же должно быть лучше, чем выгрызать
	-- дыру, иначе вертикальный интеллект не включится никогда.
	climbPenalty = 8, -- в шагах сетки

	-- Справочный урон по постройке в секунду — им считается время разрушения, когда грызущий
	-- неизвестен (проверка цены клетки вне контекста конкретного врага).
	--
	-- У врагов есть свои chewDamage/chewRate в Enemies, и поиск пути берёт именно их:
	-- слабый грызун должен считать стену дороже, чем сильный, и охотнее её обходить.
	chewDps = 10,
}

local CELL = Arena.cellSize

-- Сторона следа постройки в клетках. Нечётная нарочно: у следа есть центральная клетка,
-- и она же — «клетка постройки» из CellX/CellZ. Поэтому ToWorld от неё по-прежнему даёт
-- центр модели, и вся арифметика постройки осталась той же, что была на крупной сетке.
Arena.span = math.floor(Arena.buildSize / CELL + 0.5)
assert(Arena.span % 2 == 1,
	"[Arena] buildSize / cellSize должно быть нечётным: у следа постройки должна быть центральная клетка")

-- От центральной клетки следа до его края.
Arena.reach = (Arena.span - 1) / 2

-- То же самое, но для конкретного размера следа в студах, а не для Arena.buildSize:
-- у каждой постройки свой footprint (см. ReplicatedStorage.Towers), и Колба (10.2) не влезает
-- в тот же блок клеток, что Стена (3.6) — с общим Arena.reach вторая Колба вставала прямо
-- в первую: сетка занятости проверяла клетку по чужому, слишком маленькому следу (не по
-- реальному размеру постройки). Округление вверх (ceil), а не к ближайшему: занятая площадь
-- обязана накрывать весь реальный меш постройки целиком, а не обрезать его по центру клетки.
--
-- Пола в Arena.reach больше нет: он навязывал мелким постройкам (Центрифуга — 2.2) чужой,
-- вдвое крупнее реального след (5 клеток вместо 3), и вторая такая же постройка не могла
-- встать вплотную — между ними всегда оставалась пустая клетка. Теперь след каждой постройки
-- зависит только от её собственного footprint, и вплотную можно ставить что угодно.
function Arena.ReachFor(footprint)
	local span = math.ceil((footprint or Arena.buildSize) / CELL)
	if span % 2 == 0 then
		span += 1 -- у следа обязана быть центральная клетка, как и у Arena.span
	end
	return (span - 1) / 2
end

-- Границы берутся из ArenaFloor активной локации, а не из констант: подвинули или растянули
-- пол — сетка поехала за ним, править ничего не надо.
local minX, minZ, topY = 0, 0, 0

local WALL_SINK = 1.0

-- Сторож. ArenaFloor невидимый, но в окне Studio он выделяется и таскается мышью, а за ним
-- едет ВСЁ: сетка путей, бетонный пол, высота жуков, высота турелей. Его сбивали мышью уже
-- дважды: сначала на 18 студов вниз (вся арена ушла под грунт), потом на 9 студов вбок —
-- пол вылез из-под западной стены и не достал до восточной, между ним и полом коридора
-- выхода открылась щель в 9 студов, а красная площадка выхода со столом повисла над ней.
-- Код при этом был прав в каждой строчке: он честно считает границы по этой детали.
-- Возвращать её на место молча нельзя (пол нарочно задан геометрией, а не константой),
-- поэтому — крик в вывод. Ориентир — стены арены: пол обязан ровно заполнять их внутренний
-- прямоугольник, а низ стен утоплен в него на WALL_SINK.
local function checkWalls(floorSize)
	local wallsFolder = location:FindFirstChild("Walls")
	if not wallsFolder then
		return
	end
	-- Внутренний прямоугольник стен. Западные стены дают левый край, восточные — правый;
	-- части коридоров (EntranceFloor, ExitSideA и прочие) под эти имена не попадают.
	local innerX0, innerX1 = -math.huge, math.huge
	local innerZ0, innerZ1 = -math.huge, math.huge
	local bottom = math.huge
	for _, d in wallsFolder:GetDescendants() do
		if d:IsA("BasePart") then
			bottom = math.min(bottom, d.Position.Y - d.Size.Y / 2)
			if d.Name:match("^West") then
				innerX0 = math.max(innerX0, d.Position.X + d.Size.X / 2)
			elseif d.Name:match("^East") then
				innerX1 = math.min(innerX1, d.Position.X - d.Size.X / 2)
			elseif d.Name == "South" then
				innerZ0 = math.max(innerZ0, d.Position.Z + d.Size.Z / 2)
			elseif d.Name == "North" then
				innerZ1 = math.min(innerZ1, d.Position.Z - d.Size.Z / 2)
			end
		end
	end

	-- Лаборатория (alchemy_td_location_v1.6.md): между полом и стеной может лежать
	-- служебная полоса (папка Service, детали North/South/East/West) — на ней стоит
	-- обстановка, и в сетку она не входит. Тогда пол обязан упираться уже не в
	-- стену, а в внутренний край полосы — сторож проверяет так же точно.
	local service = location:FindFirstChild("Service")
	if service then
		for _, d in service:GetChildren() do
			if d:IsA("BasePart") then
				if d.Name == "West" then
					innerX0 = d.Position.X + d.Size.X / 2
				elseif d.Name == "East" then
					innerX1 = d.Position.X - d.Size.X / 2
				elseif d.Name == "South" then
					innerZ0 = d.Position.Z + d.Size.Z / 2
				elseif d.Name == "North" then
					innerZ1 = d.Position.Z - d.Size.Z / 2
				end
			end
		end
	end

	if innerX0 > -math.huge and innerX1 < math.huge and innerZ0 > -math.huge and innerZ1 < math.huge then
		local maxX = minX + floorSize.X
		local maxZ = minZ + floorSize.Z
		local drift = math.max(
			math.abs(minX - innerX0), math.abs(maxX - innerX1),
			math.abs(minZ - innerZ0), math.abs(maxZ - innerZ1))
		if drift > 0.1 then
			warn(string.format(
				"Arena: пол лежит X %.1f..%.1f, Z %.1f..%.1f, а стены изнутри дают X %.1f..%.1f, Z %.1f..%.1f. ArenaFloor сдвинули?",
				minX, maxX, minZ, maxZ, innerX0, innerX1, innerZ0, innerZ1))
		end
	end

	if bottom < math.huge and math.abs(topY - (bottom + WALL_SINK)) > 0.1 then
		warn(string.format(
			"Arena: верх пола %.2f, а стены стоят так, будто он на %.2f. ArenaFloor сдвинули?",
			topY, bottom + WALL_SINK))
	end
end

-- Подписчики смены локации. Обычный список функций, а не BindableEvent: пересчёт должен
-- закончиться до того, как LocationService вернёт управление и забег продолжится.
local listeners = {}

function Arena.Location()
	return location
end

function Arena.OnChanged(fn)
	table.insert(listeners, fn)
end

-- Позиции входа и выхода. Клетки из них считает Grid (сервер) и TowerInteraction (клиент).
-- В лаборатории (alchemy_td_location_v1.6.md) это одна и та же герметичная дверь: через
-- неё волны приходят и через неё же уходят. Стол — отдельная точка (Arena.table): раньше
-- он стоял на выходе и запрет стройки «на выходе» заодно берёг и его.
Arena.entrance = Vector3.zero
Arena.exit = Vector3.zero
Arena.table = Vector3.zero
-- Половина габарита стола по мировым X/Z. Запрет стройки на столе (Arena.IsTableCell) раньше
-- смотрел только на его центральную клетку, и турель вставала в край столешницы.
Arena.tableHalf = Vector3.zero

-- Габарит модели в мировых осях: стол может стоять повёрнутым.
local function worldHalf(model)
	local cf, size = model:GetBoundingBox()
	local half = size / 2
	local function axis(v)
		return math.abs(v.X) * half.X + math.abs(v.Y) * half.Y + math.abs(v.Z) * half.Z
	end
	local r = cf.RightVector
	local u = cf.UpVector
	local b = -cf.LookVector
	return Vector3.new(
		axis(Vector3.new(r.X, u.X, b.X)),
		axis(Vector3.new(r.Y, u.Y, b.Y)),
		axis(Vector3.new(r.Z, u.Z, b.Z)))
end

local function bind()
	if IS_SERVER then
		local floor = location:WaitForChild("ArenaFloor")
		local markers = location:WaitForChild("Markers")
		location:SetAttribute("FloorPosition", floor.Position)
		location:SetAttribute("FloorSize", floor.Size)
		location:SetAttribute("Entrance", markers:WaitForChild("Entrance").Position)
		location:SetAttribute("Exit", markers:WaitForChild("Exit").Position)
		local craftTable = location:WaitForChild("CraftTable")
		location:SetAttribute("Table", craftTable:GetPivot().Position)
		location:SetAttribute("TableHalf", worldHalf(craftTable))
	else
		while location:GetAttribute("FloorSize") == nil or location:GetAttribute("Exit") == nil
			or location:GetAttribute("Table") == nil or location:GetAttribute("TableHalf") == nil do
			location.AttributeChanged:Wait()
		end
	end

	local floorPosition = location:GetAttribute("FloorPosition")
	local floorSize = location:GetAttribute("FloorSize")
	minX = floorPosition.X - floorSize.X / 2
	minZ = floorPosition.Z - floorSize.Z / 2
	topY = floorPosition.Y + floorSize.Y / 2

	-- Клетки нумеруются с 1: cx вдоль X (запад → восток), cz вдоль Z (юг → север).
	Arena.cols = math.floor(floorSize.X / CELL)
	Arena.rows = math.floor(floorSize.Z / CELL)

	-- Верх пола — та же высота, на которую садятся центры клеток. Отдельным полем — чтобы
	-- тому, кому нужна только земля (снаряд по ней понимает, что промазал и вткнулся, см. Projectile),
	-- не приходилось заново считать её по ArenaFloor вторым местом в коде.
	Arena.floorY = topY
	Arena.entrance = location:GetAttribute("Entrance")
	Arena.exit = location:GetAttribute("Exit")
	Arena.table = location:GetAttribute("Table")
	Arena.tableHalf = location:GetAttribute("TableHalf")

	if IS_SERVER then
		checkWalls(floorSize)
	end
end

bind()

-- Пересчитать геометрию под текущее содержимое Location и оповестить подписчиков.
-- На сервере зовёт LocationService после подмены локации; клиент ловит смену Version сам.
function Arena.Rebind()
	bind()
	for _, fn in listeners do
		fn()
	end
end

if IS_SERVER then
	location:SetAttribute("Version", location:GetAttribute("Version") or 0)
else
	location:GetAttributeChangedSignal("Version"):Connect(function()
		task.defer(Arena.Rebind)
	end)
end

function Arena.InBounds(cx, cz)
	return cx >= 1 and cx <= Arena.cols and cz >= 1 and cz <= Arena.rows
end

-- Центр клетки на уровне пола.
function Arena.ToWorld(cx, cz)
	return Vector3.new(minX + (cx - 0.5) * CELL, topY, minZ + (cz - 0.5) * CELL)
end

-- Всегда возвращает клетку внутри сетки: точка чуть за краем пола (маркер входа в самом
-- проломе, курсор у самой стены) должна давать крайнюю клетку, а не ошибку.
function Arena.ToCell(position)
	local cx = math.floor((position.X - minX) / CELL) + 1
	local cz = math.floor((position.Z - minZ) / CELL) + 1
	return math.clamp(cx, 1, Arena.cols), math.clamp(cz, 1, Arena.rows)
end

-- Помещается ли след постройки целиком на пол. Раньше эту роль играла InBounds: постройка
-- была ровно клеткой, и «клетка на поле» значило «постройка на поле». Теперь у следа есть
-- ширина, и у самого края поля центральная клетка свободна, а постройка свисала бы за край.
--
-- Поле для стройки от этого не уменьшилось: крайняя допустимая клетка (3) — это ровно
-- центр бывшей крупной клетки 1.
-- Накрывает ли след постройки с центром в этой клетке хоть кусок стола. Одна функция
-- на сервер (Grid.IsTableCell) и клиент (подсветка в TowerInteraction): две копии разошлись бы,
-- и рамка показывала бы «можно» там, где сервер откажет.
function Arena.IsTableCell(cx, cz, reach)
	reach = reach or Arena.reach
	local tableX, tableZ = Arena.ToCell(Arena.table)
	local half = Arena.tableHalf or Vector3.zero
	local spanX = math.ceil(half.X / CELL)
	local spanZ = math.ceil(half.Z / CELL)
	return math.abs(cx - tableX) <= reach + spanX and math.abs(cz - tableZ) <= reach + spanZ
end

function Arena.FitsBuilding(cx, cz, reach)
	reach = reach or Arena.reach
	return cx - reach >= 1 and cx + reach <= Arena.cols
		and cz - reach >= 1 and cz + reach <= Arena.rows
end

-- Ближайшая клетка, в которой след помещается целиком. Клиент двигает подсветку по ней,
-- чтобы у края поля рамка показывала ту клетку, куда постройка реально встанет,
-- а не ту, в которой курсор.
function Arena.ClampBuildCell(cx, cz, reach)
	reach = reach or Arena.reach
	return math.clamp(cx, 1 + reach, Arena.cols - reach),
		math.clamp(cz, 1 + reach, Arena.rows - reach)
end

return Arena
