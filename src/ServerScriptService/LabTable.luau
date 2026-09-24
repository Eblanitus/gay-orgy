-- Лабораторный стол (design: alchemy_td_enemies.md, раздел «Лабораторный стол»).
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

-- На каком расстоянии от центра стола жук считается «дошёл и грызёт». Стол — 7 студов
-- в длину, поэтому чуть больше его половины: жук грызёт край, а не влезает в середину.
LabTable.REACH = 5

local destroyedListeners = {}

function LabTable.Model()
	return craftTable
end

function LabTable.Position()
	return craftTable:GetPivot().Position
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
	craftTable:SetAttribute("MaxHP", LabTable.MAX_HP)
	craftTable:SetAttribute("HP", LabTable.MAX_HP)

	for _, part in craftTable:GetDescendants() do
		if part:IsA("BasePart") then
			part.Transparency = part:GetAttribute("BaseTransparency") or part.Transparency
		end
	end
end

-- Грызня стола. Возвращает, сколько урона реально прошло (0, если стол уже разбит).
function LabTable.Bite(amount)
	local hp = LabTable.HP()
	if hp <= 0 or amount <= 0 then
		return 0
	end

	local dealt = math.min(hp, amount)
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
