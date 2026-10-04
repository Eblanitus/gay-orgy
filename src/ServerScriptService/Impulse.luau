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
local Loose = require(ReplicatedStorage:WaitForChild("Loose"))
local Effects = require(ReplicatedStorage:WaitForChild("Effects"))
local Corpses = require(script.Parent:WaitForChild("Corpses"))
local EnemyFXRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("EnemyFX")

local Impulse = {}

-- Та же метка, что у ImpulseFX на клиенте; на сервере её больше никто не ставит.
Impulse.Tag = Loose.Tag

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

-- Взрыв радиуса radius в точке center. power — дополнительный множитель (необязателен).
function Impulse.Blast(center, radius, power)
	EnemyFXRemote:FireAllClients("blast", center, radius, power)

	local reach = Loose.BlastReach(radius)
	Corpses.Touch(center, reach) -- хрупкие трупы лопаются от ударной волны
	-- Незакреплённые серверные сборки; персонажи игроков — нет: ими владеет клиент.
	Loose.Blast(Loose.AroundInBounds(center, reach, isCharacter), center, radius, power)
end

-- Жука сдвинуло на offset (отдача, притяжение, подброс) — лежащее вокруг него летит туда же.
function Impulse.Push(at, offset)
	if Vector3.new(offset.X, 0, offset.Z).Magnitude < 1e-3 then
		return
	end
	EnemyFXRemote:FireAllClients("push", at, offset)
	Loose.Push(Loose.AroundInBounds(at, PhysicsFX.push.radius, isCharacter), offset)
end

-- Попадание в живого жука: вздрагивание рисует клиент (EnemyRender) по HP и HitFrom.
-- Снаряд задел и хрупкий труп под ногами жука — тот лопается.
function Impulse.Hit(enemy, from, fraction)
	if enemy and enemy.Parent then
		Corpses.Touch(enemy:GetPivot().Position, PhysicsFX.brittle.hit)
	end
end

Impulse.Kick = Loose.Kick
Impulse.RandomSpin = Loose.RandomSpin

-- Effects лежит в ReplicatedStorage и серверных модулей не требует — та же схема крючков, что
-- у OnAreaBlast и OnKillBarrier: сервер подключает свою физику сам.
Effects.OnImpulseBlast = Impulse.Blast
Effects.OnImpulsePush = Impulse.Push

return Impulse
