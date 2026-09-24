-- Толчки физики на КЛИЕНТЕ. Правило автора: «взрыв толкает всё, что не прикреплено».
--
-- Трупы, оторванные куски и видимые тела жуков — клиентские (CorpseFX, EnemyRender), поэтому и
-- толкает их клиент. Серверный Impulse только пересылает сюда взрывы и отдачу
-- (Remotes.EnemyFX). Вздрагивание от попадания делает EnemyRender по падению HP и HitFrom.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local PhysicsFX = require(ReplicatedStorage:WaitForChild("PhysicsFX"))
local EnemyGait = require(ReplicatedStorage:WaitForChild("EnemyGait"))

local ImpulseFX = {}

-- Метка «физический объект, толкать»: у трупов и кусков CanQuery = false, пространственный
-- запрос их не видит. Толкается только помеченное: серверные сборки толкает сервер.
ImpulseFX.Tag = "Loose"

local function looseAround(center, radius)
	local list, seen = {}, {}
	for _, tagged in CollectionService:GetTagged(ImpulseFX.Tag) do
		local part = tagged:IsA("Model") and tagged.PrimaryPart or tagged
		local root = part and part:IsA("BasePart") and part.AssemblyRootPart
		if root and not root.Anchored and not seen[root] and tagged:IsDescendantOf(Workspace) then
			seen[root] = true
			local distance = (root.Position - center).Magnitude
			if distance <= radius then
				table.insert(list, { root = root, distance = distance })
			end
		end
	end
	return list
end

function ImpulseFX.RandomSpin(amount)
	return Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 2 * amount
end

function ImpulseFX.Kick(root, velocity, spin)
	root.AssemblyLinearVelocity += velocity
	root.AssemblyAngularVelocity += spin
end

-- Видимые тела жуков (EnemyRender кладёт их в серверную модель под именем Visual).
local function eachVisual(callback)
	local enemies = Workspace:FindFirstChild("Enemies")
	if not enemies then
		return
	end
	for _, enemy in enemies:GetChildren() do
		local visual = enemy:FindFirstChild("Visual")
		if visual then
			callback(visual)
		end
	end
end

-- Взрыв радиуса radius в точке center; power — дополнительный множитель. Числа — PhysicsFX.blast.
function ImpulseFX.Blast(center, radius, power)
	local plan = PhysicsFX.blast
	radius = math.max(radius or plan.referenceRadius, 1)
	local reach = radius * plan.reach
	local strength = plan.speed
		* math.clamp(radius / plan.referenceRadius, plan.powerMin, plan.powerMax)
		* (power or 1)

	for _, found in looseAround(center, reach) do
		local falloff = 1 - found.distance / reach
		local away = found.root.Position - center
		away = Vector3.new(away.X, 0, away.Z)
		if away.Magnitude < 1e-3 then
			local angle = math.random() * math.pi * 2
			away = Vector3.new(math.cos(angle), 0, math.sin(angle))
		end
		local direction = (away.Unit + Vector3.yAxis * plan.lift).Unit
		ImpulseFX.Kick(found.root, direction * strength * falloff, ImpulseFX.RandomSpin(plan.spin * falloff))
	end

	-- Живые жуки физикой не летают, но ударную волну обязаны почувствовать.
	eachVisual(function(visual)
		local distance = (visual:GetPivot().Position - center).Magnitude
		if distance < reach then
			EnemyGait.Flinch(visual, center, 1 - distance / reach)
		end
	end)
end

-- Жука сдвинуло на offset (отдача, притяжение, подброс) — лежащее вокруг него летит туда же.
function ImpulseFX.Push(at, offset)
	local plan = PhysicsFX.push
	local flat = Vector3.new(offset.X, 0, offset.Z)
	local amount = flat.Magnitude
	if amount < 1e-3 then
		return
	end
	local speed = math.min(amount * plan.speedPerStud, plan.speedMax)
	local direction = (flat.Unit + Vector3.yAxis * plan.lift).Unit
	for _, found in looseAround(at, plan.radius) do
		local falloff = 1 - found.distance / plan.radius
		ImpulseFX.Kick(found.root, direction * speed * falloff, ImpulseFX.RandomSpin(speed * 0.2 * falloff))
	end
end

return ImpulseFX
