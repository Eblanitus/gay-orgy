-- Лабораторный стол.
--
-- «Стол — объект в лаборатории, в котором игрок комбинирует элементы. Имеет прочность.
-- Разведчики ищут лабораторию. Нашли — грызут стол. Если стол уничтожен —
-- комбинирование невозможно или ограничено.»
--
-- Стол — НЕ постройка из Towers и не занимает клетки сетки. Это сознательно:
-- займи он клетки, жуки начали бы его ОБХОДИТЬ как преграду по дороге к выходу —
-- ровно наоборот тому, чего требует документ. Он цель, а не препятствие.
--
-- Грызут его не общей грызнёй построек (та идёт через Grid.GetBlocker), а отдельной
-- веткой в EnemySpawner: жук дошёл до клетки стола и встал грызть.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Arena = require(ReplicatedStorage:WaitForChild("Arena"))
local Grid = require(ServerScriptService:WaitForChild("Grid"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local DamageDealtRemote = Remotes:WaitForChild("DamageDealt")

-- Стол активной локации. Сменилась локация — ссылка перебирается (см. низ файла).
local craftTable = Arena.Location():WaitForChild("CraftTable")

local LabTable = {}

-- Прочность стола. Число баланса, поэтому живёт таблицей здесь, а не в вики.
-- Стандарт грызёт на 5 в секунду: пятеро разведчиков съедают стол за минуту —
-- достаточно долго, чтобы игрок успел их снять, и достаточно быстро, чтобы он это делал.
LabTable.MAX_HP = 1500

-- Запасной радиус стола, пока его габарит (Arena.tableHalf) не мерян. «Дошёл и грызёт»
-- решает зазор тела до края стола (LabTable.BodyGap), а не этот круг.
LabTable.REACH = 5

local destroyedListeners = {}

function LabTable.Model()
	return craftTable
end

function LabTable.Position()
	return craftTable:GetPivot().Position
end

-- Плоское расстояние от точки до края стола (0 — над столешницей). Взрыв у торца стола
-- задевает стол, хотя до его середины дальше радиуса: стол 7 студов в длину.
-- Габарит — тот же, о который толкучка упирает тела (Arena.tableHalf, мировые оси).
function LabTable.DistanceTo(point)
	local centre = LabTable.Position()
	local half = Arena.tableHalf or Vector3.zero
	local dx = math.max(math.abs(point.X - centre.X) - half.X, 0)
	local dz = math.max(math.abs(point.Z - centre.Z) - half.Z, 0)
	return math.sqrt(dx * dx + dz * dz)
end

-- Зазор, на котором жук уже грызёт стол: толкучка держит его тело в BODY_CLEARANCE от
-- столешницы (Crowd.outOfTable), и вплотную подошедший стоит в ~0.1 от края.
LabTable.BITE_GAP = 0.6

local BODY_SAMPLES = 5 -- точек вдоль оси тела, от брюшка до головы (как в толкучке)

-- Зазор между телом жука и краем стола (0 — касается) и ближайшая к телу точка края.
-- position — где стоит пивот (по умолчанию — где он сейчас), ход — по пивоту жука.
-- Раньше «дошёл до стола» был круг REACH + 1.7 × масштаб от середины стола: стол
-- 7 × 4, и с длинной стороны жук вставал грызть в трёх студах от столешницы.
function LabTable.BodyGap(enemy, position)
	local pivot = enemy:GetPivot()
	position = position or pivot.Position
	-- Голова модели по +Z пивота (см. Crowd.Add).
	local facing = Vector3.new(pivot.ZVector.X, 0, pivot.ZVector.Z)
	facing = if facing.Magnitude > 1e-3 then facing.Unit else Vector3.zAxis
	local radius = enemy:GetAttribute("FootRadius") or 1.5
	local front = enemy:GetAttribute("FootFront") or 0
	local back = enemy:GetAttribute("FootBack") or 0

	local centre = LabTable.Position()
	local half = Arena.tableHalf or Vector3.zero
	if half.X <= 0 and half.Z <= 0 then
		-- Стол не мерян: круг REACH, как раньше.
		half = Vector3.new(LabTable.REACH, 0, LabTable.REACH)
	end

	local best, bestPoint = math.huge, centre
	for i = 0, BODY_SAMPLES - 1 do
		local along = back + (front - back) * i / (BODY_SAMPLES - 1)
		local px, pz = position.X + facing.X * along, position.Z + facing.Z * along
		local qx = math.clamp(px, centre.X - half.X, centre.X + half.X)
		local qz = math.clamp(pz, centre.Z - half.Z, centre.Z + half.Z)
		local gap = math.sqrt((px - qx) ^ 2 + (pz - qz) ^ 2) - radius
		if gap < best then
			best, bestPoint = gap, Vector3.new(qx, position.Y, qz)
		end
	end
	return math.max(best, 0), bestPoint
end

-- Клетка стола — цель поля волн для всех, у кого goal = "table". Считается каждый раз,
-- а не кэшируется: стол можно подвинуть в Studio руками, как и весь остальной уровень.
function LabTable.Cell()
	return Grid.ToCell(LabTable.Position())
end

function LabTable.HP()
	return craftTable:GetAttribute("HP") or 0
end

function LabTable.IsAlive()
	return LabTable.HP() > 0
end

-- Возвращает стол в целое состояние. Зовётся на каждый новый забег (WaveRunner):
-- стол — часть арены, а арена разбирается целиком.
function LabTable.Reset()
	LabTable.SetGuarded(false)
	craftTable:SetAttribute("MaxHP", LabTable.MAX_HP)
	craftTable:SetAttribute("HP", LabTable.MAX_HP)

	for _, part in craftTable:GetDescendants() do
		if part:IsA("BasePart") then
			part.Transparency = part:GetAttribute("BaseTransparency") or part.Transparency
		end
	end
end

-- Защита стола (обучение, первые волны): здоровье не опускается ниже 1 — стол тает,
-- но не ломается, и волна идёт до конца. Ставит WaveRunner на каждую волну.
local guarded = false

function LabTable.SetGuarded(value)
	guarded = value == true
end

-- Грызня стола. Возвращает, сколько урона реально прошло (0, если стол уже разбит).
function LabTable.Bite(amount)
	local hp = LabTable.HP()
	if hp <= 0 or amount <= 0 then
		return 0
	end

	local dealt = math.min(guarded and hp - 1 or hp, amount)
	if dealt <= 0 then
		return 0
	end
	local left = hp - dealt
	craftTable:SetAttribute("HP", left)
	DamageDealtRemote:FireAllClients(LabTable.Position(), dealt, false)

	-- Стол тает на глазах: без этого игрок узнаёт о потере только в момент, когда
	-- крафт уже отказал. Исходная прозрачность запоминается один раз: второй забег иначе
	-- считал бы её от уже помутневшего стола и тот никогда бы не вернулся к прежнему виду.
	local share = left / LabTable.MAX_HP
	for _, part in craftTable:GetDescendants() do
		if part:IsA("BasePart") then
			if part:GetAttribute("BaseTransparency") == nil then
				part:SetAttribute("BaseTransparency", part.Transparency)
			end
			local base = part:GetAttribute("BaseTransparency")
			part.Transparency = base + (1 - base) * (1 - share) * 0.6
		end
	end

	if left <= 0 then
		-- Стол — та самая «мебель» из описания Строителя («ест обломки стены или
		-- мебели»): разгрызенный стол оставляет руину, из которой колония строит.
		-- Зависимость поздняя (через require внутри ветки), а не в шапке: EnemyStructures
		-- требует Grid, Grid — Arena, а LabTable требуется из EnemyBehavior раньше них обоих.
		local EnemyStructures = require(ServerScriptService:WaitForChild("EnemyStructures"))
		EnemyStructures.Ruin(LabTable.Position(), LabTable.MAX_HP)
		print("[Стол] лабораторный стол уничтожен — комбинирование невозможно, на месте стола руина")
		for _, fn in destroyedListeners do
			task.spawn(fn)
		end
	end

	return dealt
end

-- Колбек на уничтожение. Нужен тем, кто должен отреагировать разово (показать
-- сообщение игроку), а не спрашивать IsAlive каждый кадр.
function LabTable.OnDestroyed(fn)
	table.insert(destroyedListeners, fn)
end

LabTable.Reset()

-- Слушатели смены стола: подсказке крафта надо переехать на новый стол.
local changedListeners = {}

function LabTable.OnChanged(fn)
	table.insert(changedListeners, fn)
end

Arena.OnChanged(function()
	craftTable = Arena.Location():WaitForChild("CraftTable")
	LabTable.Reset()
	for _, fn in changedListeners do
		fn(craftTable)
	end
end)

return LabTable
