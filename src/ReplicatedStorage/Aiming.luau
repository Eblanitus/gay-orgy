-- Доворот турели: одна формула на сервер и на клиент (задача #70).
--
-- Лежит в ReplicatedStorage по той же причине, что и Arena: считать по ней надо обоим.
-- Сервер решает по ней, успеет ли он навестись на цель и можно ли уже стрелять; клиент
-- по ней же крутит башню в кадре. Формула обязана быть одна: разъедься они, ствол смотрел бы
-- в одну сторону, а выстрел уходил бы в другую.
--
-- Углы везде в радианах и в той же системе, что у модели: 0 — «вперёд», то есть -Z
-- (LookVector в Roblox), поворот по оси Y.
local Aiming = {}

-- Насколько ствол может разойтись с целью и всё-таки выстрелить. Не ноль намеренно:
-- жук идёт, угол на него меняется каждый кадр, и требование «точно в ноль» означало бы, что
-- по движущейся цели турель не стреляет вовсе.
Aiming.TOLERANCE = math.rad(8)

-- Запасные значения для турели, у которой в Towers своих не прописано.
Aiming.DEFAULT_SPEED = 1.8 -- рад/сек
Aiming.DEFAULT_ACCEL = 4 -- рад/сек²

local TAU = 2 * math.pi

-- Угол на точку from -> to или nil, если цель ровно над башней и направления просто нет.
function Aiming.AngleTo(from, to)
	local delta = to - from
	if math.abs(delta.X) < 1e-6 and math.abs(delta.Z) < 1e-6 then
		return nil
	end
	return math.atan2(-delta.X, -delta.Z)
end

-- Угол места на точку (задача #71): вверх — плюс, вниз — минус. Считается от горизонтали,
-- поэтому поворот башни по горизонту на него не влияет вовсе: два угла считаются и едут к цели
-- независимо друг от друга.
function Aiming.PitchTo(from, to)
	local delta = to - from
	local flat = math.sqrt(delta.X * delta.X + delta.Z * delta.Z)
	if flat < 1e-6 then
		return delta.Y >= 0 and math.pi / 2 or -math.pi / 2
	end
	return math.atan2(delta.Y, flat)
end

-- Кратчайшая разница углов, всегда в пределах [-pi, pi]: доворачиваться на 350° влево,
-- когда можно на 10° вправо, турель не должна.
function Aiming.Delta(from, to)
	local diff = (to - from) % TAU
	if diff > math.pi then
		diff -= TAU
	end
	return diff
end

-- Сколько секунд займёт доворот на угол turn. Трапеция: разгон до потолка скорости,
-- полка, торможение. Короткий доворот до полки не доходит вовсе — это треугольник,
-- и время у него другое.
--
-- Считается от нулевой скорости, хотя ствол может уже крутиться: точность здесь нужна не
-- сама по себе, а чтобы отсеять цель, до которой турель заведомо не докрутится.
function Aiming.TurnTime(turn, speed, accel)
	speed = speed or Aiming.DEFAULT_SPEED
	accel = accel or Aiming.DEFAULT_ACCEL
	turn = math.abs(turn)

	local rampUpAndDown = speed * speed / accel
	if turn <= rampUpAndDown then
		return 2 * math.sqrt(turn / accel)
	end
	return 2 * speed / accel + (turn - rampUpAndDown) / speed
end

-- Шаг доворота за dt. Возвращает новый угол и новую угловую скорость.
--
-- Скорость не задаётся рывком: она сама доезжает до нужной с ускорением accel, поэтому
-- башня трогается и останавливается плавно, а не включается на полный ход в один кадр.
-- Потолок скорости у самой цели ограничен ещё и тормозным путём (sqrt(2*a*diff)) — иначе
-- башня проскакивала бы цель и качалась вокруг неё.
--
-- dt подрезан сверху: после просадки кадра или паузы один огромный шаг швырнул бы
-- башню мимо цели рывком — ровно то, чего эта функция избегает.
function Aiming.Step(angle, velocity, target, dt, speed, accel)
	speed = speed or Aiming.DEFAULT_SPEED
	accel = accel or Aiming.DEFAULT_ACCEL
	dt = math.min(dt, 0.1)

	local diff = Aiming.Delta(angle, target)
	local braking = math.sqrt(2 * accel * math.abs(diff))
	local wanted = math.sign(diff) * math.min(speed, braking)

	local step = accel * dt
	velocity += math.clamp(wanted - velocity, -step, step)
	angle += velocity * dt

	-- У самой цели гасим дребезг: без этого ствол вечно качается на сотых долях градуса.
	if math.abs(Aiming.Delta(angle, target)) < 1e-3 and math.abs(velocity) < 1e-2 then
		angle, velocity = target, 0
	end

	return angle % TAU, velocity
end

return Aiming
