-- Толчки физики. Правило автора: «взрыв толкает всё, что не прикреплено. Любая отдача
-- в игре толкает то, что имеет физику».
--
-- Трупы, оторванные куски и видимые тела жуков теперь живут на клиенте (CorpseFX, EnemyRender),
-- поэтому толкает их клиентский ReplicatedStorage.ImpulseFX. Здесь остаётся:
--   * пересылка взрывов и отдачи всем клиентам (Remotes.EnemyFX: "blast" / "push");
--   * толчок незакреплённых СЕРВЕРНЫХ сборок в радиусе — их клиент толкнуть не может.
-- Hit (вздрагивание от попадания) клиент делает сам по падению HP и атрибуту HitFrom —
-- отдельного сообщения на каждое попадание не нужно.
--
-- Жуки физикой не двигаются (их ведёт маршрут) — смещение от отдачи по-прежнему делает
-- EnemySpawner через атрибут Push. Персонажи игроков не толкаются: ими владеет клиент.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local PhysicsFX = require(ReplicatedStorage:WaitForChild("PhysicsFX"))
local Effects = require(ReplicatedStorage:WaitForChild("Effects"))
local EnemyFXRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("EnemyFX")

local Impulse = {}

-- Та же метка, что у ImpulseFX на клиенте; на сервере её больше никто не ставит.
Impulse.Tag = "Loose"

local function isCharacter(part)
	local node = part.Parent
	while node and node ~= Workspace do
		if node:IsA("Model") and Players:GetPlayerFromCharacter(node) then
			return true
		end
		node = node.Parent
	end
	return false
end

-- Корни незакреплённых серверных сборок в радиусе. По корню, а не по деталям: сваренную
-- сборку из двадцати деталей иначе толкнуло бы вдвадцатеро сильнее.
local function looseAround(center, radius)
	local roots, list = {}, {}
	for _, part in Workspace:GetPartBoundsInRadius(center, radius) do
		local root = not part.Anchored and part.AssemblyRootPart
		if root and not root.Anchored and roots[root] == nil then
			roots[root] = true
			if not isCharacter(root) then
				table.insert(list, { root = root, distance = (root.Position - center).Magnitude })
			end
		end
	end
	return list
end

local function randomSpin(amount)
	return Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 2 * amount
end

local function kick(root, velocity, spin)
	-- Сервер в хозяевах: иначе толчок уйдёт в симуляцию, которую ведёт не он.
	pcall(function()
		root:SetNetworkOwner(nil)
	end)
	root.AssemblyLinearVelocity += velocity
	root.AssemblyAngularVelocity += spin
end

-- Взрыв радиуса radius в точке center. power — дополнительный множитель (необязателен).
function Impulse.Blast(center, radius, power)
	EnemyFXRemote:FireAllClients("blast", center, radius, power)

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
		kick(found.root, direction * strength * falloff, randomSpin(plan.spin * falloff))
	end
end

-- Жука сдвинуло на offset (отдача, притяжение, подброс) — лежащее вокруг него летит туда же.
function Impulse.Push(at, offset)
	local plan = PhysicsFX.push
	local flat = Vector3.new(offset.X, 0, offset.Z)
	local amount = flat.Magnitude
	if amount < 1e-3 then
		return
	end
	EnemyFXRemote:FireAllClients("push", at, offset)

	local speed = math.min(amount * plan.speedPerStud, plan.speedMax)
	local direction = (flat.Unit + Vector3.yAxis * plan.lift).Unit
	for _, found in looseAround(at, plan.radius) do
		local falloff = 1 - found.distance / plan.radius
		kick(found.root, direction * speed * falloff, randomSpin(speed * 0.2 * falloff))
	end
end

-- Попадание в живого жука: вздрагивание рисует клиент (EnemyRender) по HP и HitFrom.
function Impulse.Hit(enemy, from, fraction) end

Impulse.Kick = kick
Impulse.RandomSpin = randomSpin

-- Effects лежит в ReplicatedStorage и серверных модулей не требует — та же схема крючков, что
-- у OnAreaBlast и OnKillBarrier: сервер подключает свою физику сам.
Effects.OnImpulseBlast = Impulse.Blast
Effects.OnImpulsePush = Impulse.Push

return Impulse
