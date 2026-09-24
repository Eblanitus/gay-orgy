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
	return radius, front, back
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

-- Расстояние от точки до поверхности тела и до его центра — оба сразу, потому что нужны
-- оба и считаются из одной разности.
--
-- Поверхность — капсула по габаритам: по горизонтали снимается радиус, по вертикали —
-- полувысота. Точка внутри тела даёт ноль, а не отрицательное число: «внутри» и «ровно
-- на поверхности» для всех проверок радиуса — одно и то же.
--
-- Центр остаётся нужен для оценок и наведения: доворот ствола и упреждение целятся
-- в жука, а не в его край.
function EnemyBody.SurfaceDistance(from, enemy)
	local center = enemy:GetPivot().Position
	local delta = center - from

	local horizontal = math.max(math.sqrt(delta.X * delta.X + delta.Z * delta.Z) - EnemyBody.Radius(enemy), 0)
	local vertical = math.max(math.abs(delta.Y) - EnemyBody.HalfHeight(enemy), 0)

	return math.sqrt(horizontal * horizontal + vertical * vertical), delta.Magnitude
end

return EnemyBody
