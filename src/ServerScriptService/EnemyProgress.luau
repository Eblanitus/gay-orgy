-- Остаток пути жука до выхода (studs). Раньше это был атрибут DistanceToExit, который
-- переписывался каждый кадр у каждого жука и реплицировался всем клиентам, хотя читает
-- его только сервер (Targeting — приоритет «ближайший к выходу»). Теперь — серверная таблица.
local EnemyProgress = {}

local distances = setmetatable({}, { __mode = "k" })

function EnemyProgress.Set(enemy, distance)
	distances[enemy] = distance
end

-- nil, если жук не ведётся EnemySpawner (например, ещё не заспавнен).
function EnemyProgress.Get(enemy)
	return distances[enemy]
end

return EnemyProgress
