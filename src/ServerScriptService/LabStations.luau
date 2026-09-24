-- Справочник и производитель базовых элементов (design: alchemy_td_location_v1.6.md,
-- «Начальное помещение»).
--
-- «Справочник — электронная доска на стене: дерево крафта. Имеет прочность, хрупкая.»
-- «Производитель базовых элементов — автомат, где покупаются базовые элементы за материю.
-- Имеет прочность, крепче стола. Разрушен — элементы получать негде.»
-- «Урон по справочнику и производителю проходит, но жуки не выбирают их целью.»
--
-- Устроено как LabTable: модели в папке локации, прочность — атрибуты HP/MaxHP на модели
-- (клиент читает их для полоски), урон — Bite. В отличие от стола, станции не цель поля
-- волн и не оставляют руину: документ этого не говорит.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Arena = require(ReplicatedStorage:WaitForChild("Arena"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local DamageDealtRemote = Remotes:WaitForChild("DamageDealt")

local LabStations = {}

-- Прочность. Доска хрупкая, автомат крепче стола (LabTable.MAX_HP = 1500).
LabStations.MAX_HP = {
	ReferenceBoard = 500,
	ElementProducer = 2500,
}

-- Деталь, у которой стоит подсказка и полоска прочности.
LabStations.ANCHOR = {
	ReferenceBoard = "Screen",
	ElementProducer = "Panel",
}

local destroyedListeners = {}
local changedListeners = {}

-- Модель станции в активной локации или nil (на других уровнях станций может не быть).
function LabStations.Model(name)
	return Arena.Location():FindFirstChild(name)
end

function LabStations.Anchor(name)
	local model = LabStations.Model(name)
	return model and model:FindFirstChild(LabStations.ANCHOR[name])
end

function LabStations.HP(name)
	local model = LabStations.Model(name)
	return model and model:GetAttribute("HP") or 0
end

function LabStations.IsAlive(name)
	return LabStations.HP(name) > 0
end

local function fade(model, share)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			if part:GetAttribute("BaseTransparency") == nil then
				part:SetAttribute("BaseTransparency", part.Transparency)
			end
			local base = part:GetAttribute("BaseTransparency")
			part.Transparency = base + (1 - base) * (1 - share) * 0.6
		end
	end
end

-- Все станции целые. Зовётся на каждый новый забег (WaveRunner) рядом с LabTable.Reset.
function LabStations.Reset()
	for name, maxHp in LabStations.MAX_HP do
		local model = LabStations.Model(name)
		if model then
			model:SetAttribute("MaxHP", maxHp)
			model:SetAttribute("HP", maxHp)
			fade(model, 1)
		end
	end
	for _, fn in changedListeners do
		task.spawn(fn)
	end
end

-- Урон по станции. Возвращает, сколько реально прошло (0, если станция уже разбита).
function LabStations.Bite(name, amount)
	local model = LabStations.Model(name)
	local hp = LabStations.HP(name)
	if not model or hp <= 0 or amount <= 0 then
		return 0
	end

	local dealt = math.min(hp, amount)
	local left = hp - dealt
	model:SetAttribute("HP", left)
	DamageDealtRemote:FireAllClients(model:GetPivot().Position, dealt, false)
	fade(model, left / LabStations.MAX_HP[name])

	if left <= 0 then
		print("[Станции] " .. name .. " разрушен")
		for _, fn in destroyedListeners do
			task.spawn(fn, name)
		end
	end
	return dealt
end

-- Урон по площади (взрывы Подрывника и Разносчика): бьёт каждую станцию в радиусе.
-- Жуки станции целью не выбирают, но взрыв рядом задевает их, как и стол.
-- Возвращает число задетых станций.
function LabStations.Blast(at, radius, amount)
	local hits = 0
	for name in LabStations.MAX_HP do
		local anchor = LabStations.Anchor(name)
		if anchor and LabStations.IsAlive(name) then
			local d = anchor.Position - at
			if Vector3.new(d.X, 0, d.Z).Magnitude <= radius then
				LabStations.Bite(name, amount)
				hits += 1
			end
		end
	end
	return hits
end

-- Колбек на разрушение станции: fn(name).
function LabStations.OnDestroyed(fn)
	table.insert(destroyedListeners, fn)
end

-- Колбек на Reset и смену локации: станции снова целые, подсказки надо поставить заново.
function LabStations.OnChanged(fn)
	table.insert(changedListeners, fn)
end

LabStations.Reset()

Arena.OnChanged(function()
	LabStations.Reset()
end)

return LabStations
