-- Толчки физики на КЛИЕНТЕ. Правило автора: «взрыв толкает всё, что не прикреплено».
--
-- Трупы, оторванные куски и видимые тела жуков — клиентские (CorpseFX, EnemyRender), поэтому и
-- толкает их клиент. Серверный Impulse только пересылает сюда взрывы и отдачу
-- (Remotes.EnemyFX). Вздрагивание от попадания делает EnemyRender по падению HP и HitFrom.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Loose = require(ReplicatedStorage:WaitForChild("Loose"))
local PhysicsFX = require(ReplicatedStorage:WaitForChild("PhysicsFX"))
local EnemyGait = require(ReplicatedStorage:WaitForChild("EnemyGait"))
local EnemyBody = require(ReplicatedStorage:WaitForChild("EnemyBody"))

local ImpulseFX = {}

-- Метка, толчок и закрутка — общие, из Loose; оставлены здесь для старых вызовов.
ImpulseFX.Tag = Loose.Tag
ImpulseFX.RandomSpin = Loose.RandomSpin
ImpulseFX.Kick = Loose.Kick

-- Видимые тела жуков (EnemyRender кладёт их в серверную модель под именем Visual).
local function eachVisual(callback)
	local enemies = Workspace:FindFirstChild("Enemies")
	if not enemies then
		return
	end
	for _, enemy in enemies:GetChildren() do
		local visual = enemy:FindFirstChild("Visual")
		if visual then
			callback(visual, enemy)
		end
	end
end

-- Взрыв радиуса radius в точке center; power — дополнительный множитель. Числа — PhysicsFX.blast.
function ImpulseFX.Blast(center, radius, power)
	local reach = Loose.BlastReach(radius)
	Loose.Blast(Loose.Around(center, reach), center, radius, power)

	-- Живые жуки физикой не летают, но ударную волну обязаны почувствовать.
	-- Расстояние — до тела жука (EnemyBody), как у урона: волна, задевшая брюшко, его дёргает.
	eachVisual(function(visual, enemy)
		local distance = EnemyBody.SurfaceDistance(center, enemy)
		if distance < reach then
			EnemyGait.Flinch(visual, center, 1 - distance / reach)
		end
	end)
end

-- Жука сдвинуло на offset (отдача, притяжение, подброс) — лежащее вокруг него летит туда же.
function ImpulseFX.Push(at, offset)
	Loose.Push(Loose.Around(at, PhysicsFX.push.radius), offset)
end

return ImpulseFX
