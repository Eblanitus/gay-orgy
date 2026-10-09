-- Габариты тела жука: радиус, полувысота и расстояние до ПОВЕРХНОСТИ тела, а не до точки
-- пивота.
--
-- Правило физики жуков: «габариты (радиус + высота), а не точка». Всё, что спрашивает
-- «кто рядом», «кто в радиусе», «кого накрыло площадью», обязано мерить до тела: толстого
-- жука задеть легче, Мини — труднее. Это осознанная плата АОЕ против мелочи, а не побочный
-- эффект того, что где-то забыли про размер.
--
-- Лежит в ReplicatedStorage, а не рядом с одним из потребителей: мерить одно и то же
-- приходится в трёх местах — снаряд (Projectile), прицеливание и площадь (Targeting),
-- толкучка (Crowd). Три копии одной арифметики разъехались бы при первом же изменении
-- размера модели.
local EnemyBody = {}

-- Если у модели нет PrimaryPart, мерить нечего: числа взяты от обычного жука
-- (тело 2.6 x 1.2 x 3.4), чтобы такой враг не оказался ни бессмертным, ни бесплотным.
local DEFAULT_RADIUS = 1.5
local DEFAULT_HALF_HEIGHT = 0.6

-- Меряет фактический корпус (ThoraxCore + AbdomenCore) детализированного шаблона и кладёт
-- результат в атрибуты BodyRadius/BodyHalfHeight на сам инстанс — один раз при сборке
-- модели (см. EnemySpawner.buildTemplateModel), а не заново каждый кадр АОЕ и толкучкой.
--
-- PrimaryPart шаблонного жука (Root) — служебный якорь для PivotTo, а не тело: его Size
-- не описывает силуэт, и Radius/HalfHeight по нему давали бы хитбокс в разы меньше
-- видимой модели. Настоящий корпус — ThoraxCore и AbdomenCore внутри под-модели body,
-- повёрнутые произвольно относительно Root, поэтому меряются по мировым углам
-- собственного CFrame каждой части, а не по одному Size.
function EnemyBody.Measure(model)
	local thorax = model:FindFirstChild("ThoraxCore", true)
	local abdomen = model:FindFirstChild("AbdomenCore", true)
	if not thorax and not abdomen then
		return
	end

	-- По осям, а не по евклидовой диагонали угла: радиус ниже — это среднее полупротяжённости
	-- по X и Z, а не их максимум: точка угла коробки далеко вперёд от пивота дала бы радиус
	-- вдоль всей длины тела (точно та «max, а не среднее», от которой предостерегает комментарий
	-- к Radius ниже). Высота — по-прежнему максимум по Y: HalfHeight всегда был половиной
	-- полной высоты, а не средним чем-то ещё.
	local pivot = model:GetPivot()
	local maxAbsX, maxAbsZ, maxAbsY = 0, 0, 0
	for _, part in { thorax, abdomen } do
		if part then
			local half = part.Size * 0.5
			for _, sx in { -1, 1 } do
				for _, sy in { -1, 1 } do
					for _, sz in { -1, 1 } do
						local corner = part.CFrame * Vector3.new(half.X * sx, half.Y * sy, half.Z * sz)
						local local_ = pivot:PointToObjectSpace(corner)
						maxAbsX = math.max(maxAbsX, math.abs(local_.X))
						maxAbsZ = math.max(maxAbsZ, math.abs(local_.Z))
						maxAbsY = math.max(maxAbsY, math.abs(local_.Y))
					end
				end
			end
		end
	end

	model:SetAttribute("BodyRadius", (maxAbsX + maxAbsZ) / 2)
	model:SetAttribute("BodyHalfHeight", maxAbsY)
end

-- След тела на полу — капсула вдоль хода: радиус по ширине корпуса и два центра торцов
-- (front/back) по локальной оси Z модели (голова шаблона смотрит в +Z). Нужна толкучке
-- (Crowd): шар по ширине пускал голову соседа внутрь брюшка, шар по длине разводил бы
-- жуков боком на всю длину. Меряются все видимые детали, кроме ног и усиков: они тонкие,
-- переступают и в непроницаемость не входят. Считается один раз и кладётся в атрибуты.
function EnemyBody.Footprint(model)
	local cached = model:GetAttribute("FootRadius")
	if cached then
		return cached, model:GetAttribute("FootFront"), model:GetAttribute("FootBack")
	end

	local pivot = model:GetPivot()
	local maxAbsX, minZ, maxZ = 0, math.huge, -math.huge
	local minY, maxY = math.huge, -math.huge
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part.Transparency < 1 then
			local limb = false
			local node = part
			while node and node ~= model do
				local name = string.lower(node.Name)
				if string.find(name, "^leg") or string.find(name, "^antenna") then
					limb = true
					break
				end
				node = node.Parent
			end
			if not limb then
				local half = part.Size * 0.5
				for _, sx in { -1, 1 } do
					for _, sy in { -1, 1 } do
						for _, sz in { -1, 1 } do
							local corner = pivot:PointToObjectSpace(part.CFrame * Vector3.new(half.X * sx, half.Y * sy, half.Z * sz))
							maxAbsX = math.max(maxAbsX, math.abs(corner.X))
							minZ = math.min(minZ, corner.Z)
							maxZ = math.max(maxZ, corner.Z)
							minY = math.min(minY, corner.Y)
							maxY = math.max(maxY, corner.Y)
						end
					end
				end
			end
		end
	end

	local radius, front, back = DEFAULT_RADIUS, 0, 0
	if maxAbsX > 0 then
		radius = maxAbsX
		local middle = (minZ + maxZ) / 2
		front = math.max(maxZ - radius, middle)
		back = math.min(minZ + radius, middle)
	end

	model:SetAttribute("FootRadius", radius)
	model:SetAttribute("FootFront", front)
	model:SetAttribute("FootBack", back)
	-- Верх панциря и низ брюха от пивота — по тем же видимым деталям: на спину соседа лапы
	-- встают по ним (BackHeight), а не по полувысоте ядер, которая ниже видимого панциря.
	if maxY > minY then
		model:SetAttribute("ShellTop", maxY)
		model:SetAttribute("ShellBottom", -minY)
	end
	return radius, front, back
end

-- Верх панциря и низ брюха относительно пивота (оба — положительные расстояния).
function EnemyBody.Shell(model)
	local halfHeight = EnemyBody.HalfHeight(model)
	return model:GetAttribute("ShellTop") or halfHeight, model:GetAttribute("ShellBottom") or halfHeight
end

-- Высота спины над пивотом жука в точке (dx, dz от его пивота) или nil, если точка не над
-- ним. Спина — купол над следом-капсулой (fx, fz — ход, front/back — торцы, radius — ширина),
-- верх купола на top. margin — толщина ступни: задевшая борт ступня ложится на край спины,
-- а не проваливается мимо. Общая формула для толкучки (Crowd, где лапы держат тело) и для
-- лап на клиенте (EnemyGait), чтобы ступни стояли ровно там, где их держит сервер.
function EnemyBody.BackHeight(dx, dz, fx, fz, radius, front, back, top, margin)
	local along = math.clamp(dx * fx + dz * fz, back, front)
	local px, pz = dx - fx * along, dz - fz * along
	local across = math.sqrt(px * px + pz * pz)
	if across >= radius + (margin or 0) then
		return nil
	end
	return top * math.sqrt(math.max(0, 1 - (across / radius) ^ 2))
end

-- Радиус хитбокса — шар по горизонтальным габаритам тела: жук 2.6 x 1.2 x 3.4 даёт 1.5.
-- Среднее ширины и длины, а не максимум: жук вытянут вдоль хода, и шар по длине торчал бы
-- из его боков. Ровно эта формула и жила до сих пор в Projectile — она здесь не новая,
-- а переехавшая в общее место. Шаблонная модель меряна геометрией (Measure выше) и несёт
-- готовое число в атрибуте — читаем его первым, формула остаётся только для примитива.
function EnemyBody.Radius(enemy)
	local radius = enemy:GetAttribute("BodyRadius")
	if radius then
		return radius
	end
	local part = enemy.PrimaryPart
	if not part then
		return DEFAULT_RADIUS
	end
	return (part.Size.X + part.Size.Z) / 4
end

-- Половина высоты тела. Отдельно от радиуса, потому что жук приплюснут: считать его шаром
-- по одному радиусу значило бы задевать облаком Испарителя того, кто на полголовы ниже
-- облака. Как и в Radius, шаблонная модель отдаёт готовое число из атрибута.
function EnemyBody.HalfHeight(enemy)
	local halfHeight = enemy:GetAttribute("BodyHalfHeight")
	if halfHeight then
		return halfHeight
	end
	local part = enemy.PrimaryPart
	if not part then
		return DEFAULT_HALF_HEIGHT
	end
	return part.Size.Y / 2
end

-- Высота спины над полом: пивот едет на RideHeight, тело торчит над ним на полувысоту.
-- По ней решается, пролезет ли жук под постройкой (Grid.FitsUnder, Towers.crawlGap).
function EnemyBody.TopHeight(enemy)
	return (enemy:GetAttribute("RideHeight") or 0) + EnemyBody.HalfHeight(enemy)
end

-- Расстояние от точки до капсулы следа (Footprint): ось вдоль хода от брюшка (FootBack) до
-- головы (FootFront) в осях пивота, радиус — полширины корпуса, по вертикали — панцирь (Shell).
-- nil — следа не меряли (примитив без атрибутов). pivot передаётся, чтобы не брать его дважды.
local function capsuleGap(pivot, from, enemy, flat)
	local radius = enemy:GetAttribute("FootRadius")
	if not radius then
		return nil
	end
	local p = pivot:PointToObjectSpace(from)
	local along = math.clamp(p.Z, enemy:GetAttribute("FootBack") or 0, enemy:GetAttribute("FootFront") or 0)
	local dz = p.Z - along
	local horizontal = math.max(math.sqrt(p.X * p.X + dz * dz) - radius, 0)
	if flat then
		return horizontal
	end
	local top, bottom = EnemyBody.Shell(enemy)
	local vertical = if p.Y >= 0 then math.max(p.Y - top, 0) else math.max(-p.Y - bottom, 0)
	return math.sqrt(horizontal * horizontal + vertical * vertical)
end

-- Расстояние от точки до поверхности тела и до его центра — оба сразу, потому что нужны
-- оба и считаются из одной разности.
--
-- Поверхность — шар по ядру (Radius по горизонтали, HalfHeight по вертикали), объединённый
-- с капсулой следа. Одного шара мало: он стоит на пивоте, а тело вытянуто вдоль хода и
-- пивот не посередине — у обычного жука хвост торчит из шара на полмасштаба, у крупных
-- (масштаб 3–6) на студы, и взрыв, накрывший брюшко, жука «не задевал». Капсула добирает
-- нос и брюшко; шар остаётся, чтобы бока (с лапами, которых в капсуле нет) не стали уже,
-- чем были. Точка внутри тела даёт ноль, а не отрицательное число: «внутри» и «ровно
-- на поверхности» для всех проверок радиуса — одно и то же.
--
-- flat — только по горизонтали (зоны на полу, шипы, плита): высота точки не важна.
--
-- Центр остаётся нужен для оценок и наведения: доворот ствола и упреждение целятся
-- в жука, а не в его край.
function EnemyBody.SurfaceDistance(from, enemy, flat)
	local pivot = enemy:GetPivot()
	local center = pivot.Position
	local delta = center - from
	local across = math.sqrt(delta.X * delta.X + delta.Z * delta.Z)

	local horizontal = math.max(across - EnemyBody.Radius(enemy), 0)
	local vertical = if flat then 0 else math.max(math.abs(delta.Y) - EnemyBody.HalfHeight(enemy), 0)
	local surface = math.sqrt(horizontal * horizontal + vertical * vertical)

	if surface > 0 then
		local gap = capsuleGap(pivot, from, enemy, flat)
		if gap and gap < surface then
			surface = gap
		end
	end

	return surface, if flat then across else delta.Magnitude
end

-- Ближайшие точки двух отрезков [p1, q1] и [p2, q2]: доли s и t вдоль каждого.
local function closestSegments(p1, q1, p2, q2)
	local d1, d2, r = q1 - p1, q2 - p2, p1 - p2
	local a, e, f = d1:Dot(d1), d2:Dot(d2), d2:Dot(r)
	if a <= 1e-6 then
		return 0, if e > 1e-6 then math.clamp(f / e, 0, 1) else 0
	end
	local c = d1:Dot(r)
	if e <= 1e-6 then
		return math.clamp(-c / a, 0, 1), 0
	end
	local b = d1:Dot(d2)
	local denom = a * e - b * b
	local s = if denom > 1e-6 then math.clamp((b * f - c * e) / denom, 0, 1) else 0
	local t = (b * s + f) / e
	if t < 0 then
		return math.clamp(-c / a, 0, 1), 0
	elseif t > 1 then
		return math.clamp((b - c) / a, 0, 1), 1
	end
	return s, t
end

-- Задевает ли отрезок пути снаряда [from, to] (толщиной radius) тело жука. Возвращает долю
-- отрезка, где снаряд ближе всего к телу (0 — начало, 1 — конец), или nil — мимо.
-- Тот же шар по ядру, что и раньше, плюс капсула следа: снаряд, прошедший над брюшком
-- или перед носом длинного жука, раньше пролетал сквозь него.
function EnemyBody.SegmentHit(from, to, enemy, radius)
	local pivot = enemy:GetPivot()
	local center = pivot.Position
	local best = nil

	local segment = to - from
	local lengthSquared = segment:Dot(segment)
	local along = if lengthSquared > 1e-6 then math.clamp((center - from):Dot(segment) / lengthSquared, 0, 1) else 0
	if (center - from:Lerp(to, along)).Magnitude <= radius + EnemyBody.Radius(enemy) then
		best = along
	end

	if enemy:GetAttribute("FootRadius") then
		local back = Vector3.new(0, 0, enemy:GetAttribute("FootBack") or 0)
		local front = Vector3.new(0, 0, enemy:GetAttribute("FootFront") or 0)
		local s = closestSegments(pivot:PointToObjectSpace(from), pivot:PointToObjectSpace(to), back, front)
		if (not best or s < best) and capsuleGap(pivot, from:Lerp(to, s), enemy) <= radius then
			best = s
		end
	end

	return best
end

return EnemyBody
