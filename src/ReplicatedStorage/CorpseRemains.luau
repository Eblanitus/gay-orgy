-- Останки без тела (по вики): давит, плавит, растворяет, рвёт, уничтожает. КЛИЕНТСКАЯ часть.
-- И то, что потом случается с телом: обугленный труп осыпается, хрупкий лопается от касания.
--
-- Вид решает сервер (Effects.RemainsOf) и присылает в hit.remains; CorpseFX.Leave отдаёт сюда
-- всё, что не тело. Записи на сервере у этих видов нет — Пеликану есть нечего, и туши в списке
-- трупов тоже нет. Что остаётся на полу (лепёшка, лужица, пятно), входит в общий лимит пятен.
-- Числа — PhysicsFX.remains.
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Elements = require(ReplicatedStorage:WaitForChild("Elements"))
local Loose = require(ReplicatedStorage:WaitForChild("Loose"))
local CollectionService = game:GetService("CollectionService")

return function(deps)
	local PhysicsFX = deps.PhysicsFX
	local container = deps.container
	local remember = deps.remember
	local stains = deps.stains
	local maxStains = deps.maxStains
	local chooseLimbs = deps.chooseLimbs
	local detachPiece = deps.detachPiece
	local LIFT = deps.bloodLift
	local THICKNESS = deps.bloodThickness
	local CORPSE_GROUP = deps.corpseGroup
	local forget = deps.forget -- убрать тушу из списка трупов (она уходит не по лимиту)
	local EnemyGait = deps.EnemyGait

	local plan = PhysicsFX.remains

	-- Клон видимого тела без индикации живого (полоска HP, огонь, частицы, свет), весь на якоре.
	-- parts — только видимые детали: невидимые якоря и коробки в эффектах не участвуют.
	local STRIP = { "BillboardGui", "Fire", "Sparkles", "Smoke", "Highlight", "ParticleEmitter", "Beam", "Trail", "Light" }

	local function bodyClone(enemy)
		local clone = enemy:Clone()
		for _, item in clone:GetDescendants() do
			for _, class in STRIP do
				if item:IsA(class) then
					item:Destroy()
					break
				end
			end
		end
		local parts = {}
		for _, part in clone:GetDescendants() do
			if part:IsA("BasePart") then
				part.Anchored = true
				part.CanCollide = false
				part.CanQuery = false
				part.CanTouch = false
				if part.Transparency < 1 then
					table.insert(parts, part)
				end
			end
		end
		return clone, parts
	end

	local function plainPart(name, parent)
		local part = Instance.new("Part")
		part.Name = name
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Parent = parent
		return part
	end

	-- Плоский овал на полу — как пятно крови (Corpses.Splat): цилиндр плашмя.
	local function disc(parent, at, floorY, diameter, color, material)
		local part = plainPart("Spot", parent)
		part.Shape = Enum.PartType.Cylinder
		part.Material = material or Enum.Material.SmoothPlastic
		part.Color = color
		part.Size = Vector3.new(THICKNESS, diameter, diameter * (0.75 + math.random() * 0.5))
		part.CFrame = CFrame.new(at.X, floorY + LIFT, at.Z)
			* CFrame.Angles(0, math.random() * math.pi * 2, 0)
			* CFrame.Angles(0, 0, math.rad(90))
		return part
	end

	-- Лужа из нескольких овалов (основной и наплывы по краям): один круг читается штампом.
	-- Овалы растут из точки за growTime.
	local function puddle(parent, center, floorY, diameter, color, material, growTime)
		local spots = { disc(parent, center, floorY, diameter, color, material) }
		for _ = 1, 3 do
			local angle = math.random() * math.pi * 2
			local distance = diameter * (0.3 + math.random() * 0.15)
			local at = center + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
			table.insert(spots, disc(parent, at, floorY, diameter * (0.35 + math.random() * 0.2), color, material))
		end
		local info = TweenInfo.new(growTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		for _, spot in spots do
			local size = spot.Size
			spot.Size = Vector3.new(THICKNESS, 0.2, 0.2)
			TweenService:Create(spot, info, { Size = size }):Play()
		end
		return spots
	end

	-- Пятно гаснет и уходит.
	local function fadeAway(model, spots, delay, time)
		task.delay(delay, function()
			if not model.Parent then
				return
			end
			local info = TweenInfo.new(time, Enum.EasingStyle.Linear)
			for _, spot in spots do
				TweenService:Create(spot, info, { Transparency = 1 }):Play()
			end
			Debris:AddItem(model, time + 0.1)
		end)
	end

	-- Струйки над местом: пар над лавой, пена над кислотой.
	local function emitter(parent, at, floorY, width, props)
		local plate = plainPart("Emitter", parent)
		plate.Transparency = 1
		plate.Size = Vector3.new(width, 0.1, width)
		plate.CFrame = CFrame.new(at.X, floorY + 0.1, at.Z)
		local fx = Instance.new("ParticleEmitter")
		fx.EmissionDirection = Enum.NormalId.Top
		for key, value in props do
			fx[key] = value
		end
		fx.Parent = plate
		return fx
	end

	local function footprint(enemy)
		local _, size = enemy:GetBoundingBox()
		return math.max(size.X, size.Z), size.Y
	end

	local AXES = { "X", "Y", "Z" }

	-- Стены, о которые плющит отброшенного: стены локации и поле Аркады (как у походки).
	local function wallParams()
		local include = {}
		local location = Workspace:FindFirstChild("Location")
		local arcade = Workspace:FindFirstChild("Arcade")
		for _, node in {
			location and location:FindFirstChild("Walls"),
			arcade and arcade:FindFirstChild("Field"),
		} do
			table.insert(include, node)
		end
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = include
		params.IgnoreWater = true
		return params
	end

	-- Куда отбросило раздавленного: от турели на силу отдачи элемента, машиной — вместе с ней.
	-- Без отдачи (Обсидиан, Стена, Литосфера сверху без выстрела) — nil, давит на месте.
	local function throwOf(hit, center, scale)
		local p = plan.crush
		local direction, distance
		if hit.carry and hit.carry.Magnitude > 1 then
			direction = hit.carry
			distance = hit.carry.Magnitude * p.carryTime
		elseif hit.from and hit.throw then
			direction = center - hit.from
			distance = (p.throwBase + hit.throw * p.throwPerStud) * scale
		end
		if not direction then
			return nil
		end
		direction = Vector3.new(direction.X, 0, direction.Z)
		if direction.Magnitude < 1e-3 then
			return nil
		end
		return direction.Unit, distance
	end

	-- ДАВИТ: расплющенное тёмное пятно в форме жука и пара отлетевших кусков.
	-- Отдача отбрасывает жука от турели: он летит и плющится там, где упал, а встретил
	-- стену — плющится о стену. Каждая видимая деталь ложится на эту плоскость (пол или стену)
	-- там же, где была (чуть шире — раздавленное расползается), той своей осью, что ближе
	-- всех к нормали плоскости, и сплющивается по ней. Силуэт с растопыренными лапами
	-- остаётся узнаваемым: видно, кого раздавило.
	-- Лепёшки на полу: где лежат и докуда поднимаются. Новая ложится ПОВЕРХ тех, что уже под ней,
	-- а не на ту же высоту пола: на одной высоте лепёшки резали друг друга (плейтест).
	local pancakes = {} -- { clone, at, radius, top }
	local function pileUnder(at, radius)
		local top = 0
		for index = #pancakes, 1, -1 do
			local cake = pancakes[index]
			if not cake.clone.Parent then
				table.remove(pancakes, index)
			else
				local flat = Vector3.new(at.X - cake.at.X, 0, at.Z - cake.at.Z)
				if flat.Magnitude < radius + cake.radius then
					top = math.max(top, cake.top)
				end
			end
		end
		return top
	end

	local function crush(enemy, hit, scale, floorY)
		local p = plan.crush
		local clone = bodyClone(enemy)
		local center = enemy:GetPivot().Position
		local width = footprint(enemy)

		-- Куски — до сплющивания: улетают целыми.
		for _, group in chooseLimbs(clone, p.pieceFraction) do
			detachPiece(clone, group, center, hit.from, p.pieceFraction, scale, hit.floorY, hit.carry)
		end

		-- Плоскость лепёшки: пол под жуком, пол там, куда отбросило, или стена на пути.
		local planePoint, normal = Vector3.new(center.X, floorY, center.Z), Vector3.yAxis
		local travel = Vector3.zero
		local direction, distance = throwOf(hit, center, scale)
		if direction then
			local reach = width / 2
			local result = Workspace:Raycast(center, direction * (distance + reach), wallParams())
			if result and math.abs(result.Normal.Y) < p.wallSlope then
				normal = Vector3.new(result.Normal.X, 0, result.Normal.Z).Unit
				planePoint = result.Position
				travel = direction * math.max(result.Distance - reach, 0)
			else
				travel = direction * distance
				planePoint += travel
			end
		end
		local onWall = normal.Y < 0.5
		local base = center + travel
		local contact = base - normal * (base - planePoint):Dot(normal)
		local radius = width / 2 * p.spread
		local pile = onWall and 0 or pileUnder(contact, radius)
		contact += normal * pile
		local cakeTop = pile

		-- Что дальше от плоскости, ложится поверх: без этого детали мерцают друг с другом.
		local items, lowest = {}, math.huge
		for _, part in clone:GetDescendants() do
			if part:IsA("BasePart") and part.Transparency < 1 then
				local height = (part.Position + travel - planePoint):Dot(normal)
				lowest = math.min(lowest, height)
				table.insert(items, { part = part, height = height })
			end
		end

		-- Как деталь ложится на плоскость с нормалью n: ось детали, что ближе всех к нормали,
		-- сплющивается вдоль неё, остальные две ложатся в плоскость.
		local function flatten(part, n)
			local fallback = math.abs(n.Y) < 0.5 and n:Cross(Vector3.yAxis).Unit or Vector3.xAxis
			local cf = part.CFrame
			local cols = { cf.RightVector, cf.UpVector, cf.LookVector }
			local b = 1
			for i = 2, 3 do
				if math.abs(cols[i]:Dot(n)) > math.abs(cols[b]:Dot(n)) then
					b = i
				end
			end
			-- b — ось, что ближе всех к нормали, a и c — следующие по кругу (b × a = c).
			local a = b % 3 + 1
			local c = a % 3 + 1
			local flat = cols[a] - n * cols[a]:Dot(n)
			flat = flat.Magnitude > 1e-3 and flat.Unit or fallback
			local m = {}
			m[b] = n * (cols[b]:Dot(n) >= 0 and 1 or -1)
			m[a] = flat
			m[c] = m[b]:Cross(m[a])

			local size = part.Size
			local thin = math.max(size[AXES[b]] * p.squash, p.minThickness)
			local dims = { size.X, size.Y, size.Z }
			dims[b] = thin
			return m, dims, thin
		end

		-- Угол. Лепёшка ложится на одну грань, а то, что вылезло за её край, загибается на
		-- соседнюю, а не торчит в воздух пластиной (плейтест: жук влетел в угол проёма).
		--   * внутренний угол (стена у пола, две стены) — деталь упирается во вторую грань и
		--     ползёт по ней вверх на остаток пути;
		--   * внешний угол (торец стены, косяк проёма) — за краем грани стены нет, деталь
		--     огибает ребро и ложится на боковую грань на ту же глубину за ребром.
		-- Не нашлось, куда загнуть, — деталь прячется: лучше без кусочка, чем пластина в воздухе.
		local walls = wallParams()
		local function backed(point, n)
			return Workspace:Raycast(point + n * 0.4, -n * 0.8, walls) ~= nil
		end
		local function fold(offset, n)
			local length = offset.Magnitude
			if length < 1e-3 then
				return nil
			end
			local u = offset / length
			local from = contact + n * (LIFT + 0.05)
			local wall = Workspace:Raycast(from, offset, walls)
			if wall and math.abs(wall.Normal:Dot(n)) < 0.5 then
				local rise = n - wall.Normal * n:Dot(wall.Normal)
				rise = rise.Magnitude > 1e-3 and rise.Unit or n
				return wall.Position + rise * (length - wall.Distance), wall.Normal
			end
			if not onWall or backed(contact + offset, n) then
				return nil
			end
			-- Край грани: последняя точка, за которой ещё есть стена.
			local inside, outside = 0, length
			for _ = 1, 6 do
				local mid = (inside + outside) / 2
				if backed(contact + u * mid, n) then
					inside = mid
				else
					outside = mid
				end
			end
			local edge = contact + u * inside
			local past = length - inside
			local probe = edge - n * past + u * 0.5
			local side = Workspace:Raycast(probe, -u * 1, walls)
			if side and math.abs(side.Normal:Dot(n)) < 0.5 then
				return side.Position, side.Normal
			end
			return false
		end

		for _, item in items do
			local part = item.part
			local m, dims, thin = flatten(part, normal)

			local layer = math.clamp(item.height - lowest, 0, 20) * p.layer
			local rel = part.Position + travel - contact
			rel -= normal * rel:Dot(normal)
			local offset = rel * p.spread
			local position = contact + offset + normal * (LIFT + thin / 2 + layer)

			local folded, foldNormal = fold(offset, normal)
			if folded == false then
				item.hide = true
			elseif folded then
				m, dims, thin = flatten(part, foldNormal)
				position = folded + foldNormal * (LIFT + thin / 2 + layer)
			elseif onWall then
				-- На стене деталь не уходит в пол: низ — не ниже пола.
				local half = (math.abs(m[1].Y) * dims[1] + math.abs(m[2].Y) * dims[2] + math.abs(m[3].Y) * dims[3]) / 2
				position = Vector3.new(position.X, math.max(position.Y, floorY + half), position.Z)
			end
			item.size = Vector3.new(dims[1], dims[2], dims[3])
			item.cframe = CFrame.fromMatrix(position, m[1], m[2], m[3])
			part.CastShadow = false
			if not folded then
				cakeTop = math.max(cakeTop, pile + LIFT + thin + layer)
			end
		end
		if not onWall then
			table.insert(pancakes, { clone = clone, at = contact, radius = radius, top = cakeTop })
		end

		clone.Name = enemy.Name .. " (раздавлен)"
		clone.Parent = container("Blood")
		remember(stains, clone, maxStains)

		-- Летит, потом плющится. На месте — только плющится.
		local flight = travel.Magnitude > 0.5 and travel.Magnitude / p.throwSpeed or 0
		local splat = TweenInfo.new(p.splatTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		for _, item in items do
			local part = item.part
			if flight > 0 then
				TweenService:Create(part, TweenInfo.new(flight, Enum.EasingStyle.Linear), { CFrame = part.CFrame + travel }):Play()
			end
			task.delay(flight, function()
				if part.Parent then
					TweenService:Create(part, splat, {
						Size = item.size,
						CFrame = item.cframe,
						Color = part.Color:Lerp(p.color, p.darken),
						Transparency = item.hide and 1 or part.Transparency,
					}):Play()
				end
			end)
		end

		-- След волочения по полу — от места смерти до лепёшки (или до стены).
		local skid = travel.Magnitude
		if skid > 1 then
			task.delay(flight, function()
				if not clone.Parent then
					return
				end
				local streak = plainPart("Streak", clone)
				streak.Material = Enum.Material.SmoothPlastic
				streak.Color = p.color
				streak.Transparency = 0.25
				streak.Size = Vector3.new(width * p.streak, THICKNESS, skid)
				local from = Vector3.new(center.X, floorY + LIFT, center.Z)
				streak.CFrame = CFrame.lookAt(from + travel / 2, from + travel)
			end)
		end
	end

	-- ПЛАВИТ: жук раскаляется и оплывает в лужицу, лужица остывает в тёмную корку и тает.
	local function melt(enemy, hit, scale, floorY)
		local p = plan.melt
		local clone, parts = bodyClone(enemy)
		local center = enemy:GetPivot().Position
		local width, height = footprint(enemy)

		clone.Parent = container("Debris")
		local sink = TweenInfo.new(p.sinkTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		for _, part in parts do
			part.Material = Enum.Material.Neon
			part.CastShadow = false
			part.Color = part.Color:Lerp(p.glow, 0.5)
			TweenService:Create(part, sink, {
				CFrame = part.CFrame - Vector3.new(0, height + 1, 0),
				Color = p.glow,
			}):Play()
		end
		Debris:AddItem(clone, p.sinkTime + 0.1)

		local pool = Instance.new("Model")
		pool.Name = enemy.Name .. " (лужица)"
		local spots = puddle(pool, center, floorY, width * p.size, p.pool, Enum.Material.Neon, p.sinkTime)
		local steam = emitter(pool, center, floorY, width * 0.6, {
			Texture = "rbxasset://textures/particles/smoke_main.dds",
			Color = ColorSequence.new(Color3.fromRGB(120, 110, 100), Color3.fromRGB(200, 196, 190)),
			Transparency = NumberSequence.new(0.6, 1),
			Size = NumberSequence.new(0.6 * scale, 2 * scale),
			Lifetime = NumberRange.new(1, 1.6),
			Speed = NumberRange.new(1.5, 3),
			Rate = p.steamRate,
		})
		pool.Parent = container("Blood")
		remember(stains, pool, maxStains)

		-- Остывает: свечение гаснет, лужа темнеет в корку.
		task.delay(p.sinkTime + p.glowTime, function()
			if not pool.Parent then
				return
			end
			local info = TweenInfo.new(p.coolTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			for _, spot in spots do
				spot.Material = Enum.Material.SmoothPlastic
				TweenService:Create(spot, info, { Color = p.crust }):Play()
			end
			task.delay(p.coolTime, function()
				steam.Enabled = false
			end)
		end)
		fadeAway(pool, spots, p.sinkTime + p.glowTime + p.coolTime + p.crustTime, p.fadeTime)
	end

	-- РАСТВОРЯЕТ: жук оседает и тает в шипящей пене, остаётся тающее пятно.
	local function dissolveBody(enemy, hit, scale, floorY)
		local p = plan.dissolve
		local clone, parts = bodyClone(enemy)
		local center = enemy:GetPivot().Position
		local width, height = footprint(enemy)

		clone.Parent = container("Debris")
		local sink = TweenInfo.new(p.sinkTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		for _, part in parts do
			part.CastShadow = false
			TweenService:Create(part, sink, {
				CFrame = part.CFrame - Vector3.new(0, height * 0.7, 0),
				Color = part.Color:Lerp(p.acid, 0.7),
				Transparency = 1,
			}):Play()
		end
		Debris:AddItem(clone, p.sinkTime + 0.1)

		local spot = Instance.new("Model")
		spot.Name = enemy.Name .. " (пятно кислоты)"
		local spots = puddle(spot, center, floorY, width * p.size, p.spot, Enum.Material.SmoothPlastic, p.sinkTime)
		for _, part in spots do
			part.Transparency = 0.3
		end
		local foam = emitter(spot, center, floorY, width * 0.7, {
			Texture = "rbxasset://textures/particles/smoke_main.dds",
			Color = ColorSequence.new(Color3.fromRGB(246, 250, 225), p.acid),
			LightEmission = 0.3,
			Transparency = NumberSequence.new(0.15, 1),
			Size = NumberSequence.new(0.35 * scale, 0.7 * scale),
			Lifetime = NumberRange.new(0.5, 0.9),
			Speed = NumberRange.new(0.8, 1.8),
			SpreadAngle = Vector2.new(35, 35),
			Rate = p.foamRate,
		})
		task.delay(p.foamTime, function()
			foam.Enabled = false
		end)
		spot.Parent = container("Blood")
		remember(stains, spot, maxStains)
		fadeAway(spot, spots, p.sinkTime, p.spotTime)
	end

	-- Лапа ли это верхнего уровня (не деталь внутри другой лапы).
	local function isLeg(name)
		return name:match("^leg_") ~= nil or name:match("^Leg%d") ~= nil
	end

	-- РВЁТ: тело разлетается, остаются только лапы.
	-- Лапы отлетают целыми кусками (как отрыв при сильном ударе) и лежат на поле, остальное
	-- брызжет осколками и тает в полёте.
	local function gib(enemy, hit, scale, floorY)
		local p = plan.gib
		local clone = bodyClone(enemy)
		local center = enemy:GetPivot().Position
		-- Лапы поджаты до отрыва: так летят и так ложатся, а не стоят торчком.
		EnemyGait.DeathPose(clone, enemy, p.curlSplay, p.curlDrop)

		local legs = {}
		for _, item in clone:GetDescendants() do
			if (item:IsA("Model") or item:IsA("BasePart")) and isLeg(item.Name) then
				local node, nested = item.Parent, false
				while node and node ~= clone do
					if isLeg(node.Name) then
						nested = true
						break
					end
					node = node.Parent
				end
				if not nested then
					table.insert(legs, item)
				end
			end
		end
		for _, leg in legs do
			detachPiece(clone, { leg }, center, hit.from, p.fraction, scale, hit.floorY, hit.carry)
		end

		-- Остальное — осколки: без сварки, каждый своим полётом.
		for _, item in clone:GetDescendants() do
			if item:IsA("JointInstance") or item:IsA("WeldConstraint") or item:IsA("Motor6D") then
				item:Destroy()
			end
		end
		clone.Parent = container("Debris")
		local fade = TweenInfo.new(p.fragmentTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		for _, part in clone:GetDescendants() do
			if part:IsA("BasePart") then
				if part.Transparency < 1 then
					local out = part.Position - center
					out = Vector3.new(out.X, 0, out.Z)
					out = out.Magnitude > 1e-3 and out.Unit or Vector3.new(math.random() - 0.5, 0, math.random() - 0.5).Unit
					Loose.Spawn(part, {
						group = "Corpses",
						tag = false, -- метка — на всём разлёте ниже, не на каждом осколке
						velocity = (out + Vector3.yAxis * p.lift) * p.fragmentSpeed * (0.6 + math.random() * 0.8),
						spin = Loose.RandomSpin(10),
					})
					TweenService:Create(part, fade, { Transparency = 1, Size = part.Size * 0.4 }):Play()
				end
			end
		end
		Debris:AddItem(clone, p.fragmentTime + 0.1)
		CollectionService:AddTag(clone, Loose.Tag)
		Loose.Track(clone, "burst")
	end

	-- УНИЧТОЖАЕТ (Звезда): жук сгорает в свет без следа. Зону Звезды ставит сервер.
	local function destroy(enemy, hit, scale, floorY)
		local p = plan.destroy
		local clone, parts = bodyClone(enemy)
		clone.Parent = container("Debris")

		local info = TweenInfo.new(p.time, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		for _, part in parts do
			part.Material = Enum.Material.Neon
			part.Color = p.color
			part.CastShadow = false
			TweenService:Create(part, info, {
				Transparency = 1,
				CFrame = part.CFrame + Vector3.new(0, p.rise * scale, 0),
			}):Play()
		end

		local holder = clone.PrimaryPart or parts[1]
		if holder then
			local light = Instance.new("PointLight")
			light.Color = p.color
			light.Brightness = p.brightness
			light.Range = p.range * scale
			light.Parent = holder
			TweenService:Create(light, TweenInfo.new(p.time * 2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Brightness = 0 }):Play()

			local sparks = Instance.new("ParticleEmitter")
			sparks.Color = ColorSequence.new(p.color)
			sparks.LightEmission = 1
			sparks.Size = NumberSequence.new(0.4 * scale, 0)
			sparks.Lifetime = NumberRange.new(0.6, 1)
			sparks.Speed = NumberRange.new(3, 7)
			sparks.SpreadAngle = Vector2.new(180, 180)
			sparks.Acceleration = Vector3.new(0, 6, 0)
			sparks.Rate = 0
			sparks.Parent = holder
			sparks:Emit(math.floor(24 * scale + 0.5))
		end
		Debris:AddItem(clone, p.time * 2 + 0.2)
	end

	-- ============ Обугленный труп осыпается ============
	-- Не в пыль и не сразу (по вики): дымит, потом по одной отваливаются лапы и усики,
	-- каждая падает и раскалывается о пол на угольки, тело проседает и трескается на куски,
	-- остаётся кучка углей, она гаснет. Запись на сервере живёт столько же (Corpses.Leave).

	local function visibleParts(instance)
		local list = {}
		local all = instance:IsA("BasePart") and { instance } or instance:GetDescendants()
		for _, part in all do
			if part:IsA("BasePart") and part.Transparency < 1 then
				table.insert(list, part)
			end
		end
		return list
	end

	local function isLimbName(name)
		return name:match("^leg_") ~= nil or name:match("^Leg%d") ~= nil
			or name:match("^antenna_") ~= nil or name:match("^mandible_") ~= nil
	end

	-- Верхние узлы конечностей (лапа целиком, а не её голень отдельно).
	local function limbsOf(model)
		local list = {}
		for _, item in model:GetDescendants() do
			if (item:IsA("Model") or item:IsA("BasePart")) and isLimbName(item.Name) then
				local node, nested = item.Parent, false
				while node and node ~= model do
					if isLimbName(node.Name) then
						nested = true
						break
					end
					node = node.Parent
				end
				if not nested then
					table.insert(list, item)
				end
			end
		end
		return list
	end

	-- Угольки на полу: тлеют и гаснут.
	local function embers(at, floorY, scale, count, size)
		local p = PhysicsFX.char
		local folder = container("Debris")
		for _ = 1, count do
			local bit = plainPart("Ember", folder)
			local edge = size * scale * (0.6 + math.random() * 0.6)
			bit.Size = Vector3.new(edge, edge * 0.6, edge * (0.7 + math.random() * 0.5))
			local angle = math.random() * math.pi * 2
			local distance = size * scale * math.random()
			bit.CFrame = CFrame.new(at.X + math.cos(angle) * distance, floorY + bit.Size.Y / 2, at.Z + math.sin(angle) * distance)
				* CFrame.Angles(0, math.random() * math.pi * 2, (math.random() - 0.5) * 0.6)
			bit.Material = Enum.Material.Neon
			bit.Color = p.ember
			TweenService:Create(bit, TweenInfo.new(p.emberTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Color = p.color }):Play()
			-- Погас — чёрный уголь ещё лежит, потом исчезает.
			task.delay(p.emberTime, function()
				if bit.Parent then
					bit.Material = Enum.Material.Slate
				end
			end)
			task.delay(p.emberTime + p.coalTime, function()
				if bit.Parent then
					TweenService:Create(bit, TweenInfo.new(p.fadeTime), { Transparency = 1 }):Play()
					Debris:AddItem(bit, p.fadeTime + 0.1)
				end
			end)
		end
	end

	-- Снять сварку деталей с корпуса трупа (все сварки висят на корне, см. CorpseFX.Leave).
	local function unweld(corpse, parts)
		local set = {}
		for _, part in parts do
			set[part] = true
		end
		for _, item in corpse:GetDescendants() do
			if item:IsA("WeldConstraint") and (set[item.Part0] or set[item.Part1]) then
				item:Destroy()
			end
		end
	end

	-- Лапа отваливается: падает на пол, раскалывается на угольки и гаснет.
	local function dropLimb(corpse, limb, floorY, scale)
		local p = PhysicsFX.char
		local parts = visibleParts(limb)
		unweld(corpse, parts)
		for _, part in limb:IsA("BasePart") and { limb } or limb:GetDescendants() do
			if part:IsA("BasePart") then
				part.Anchored = true
			end
		end
		limb.Parent = container("Debris")
		if #parts == 0 then
			limb:Destroy()
			return
		end

		local low, center = math.huge, Vector3.zero
		for _, part in parts do
			low = math.min(low, part.Position.Y - math.min(part.Size.X, part.Size.Y, part.Size.Z) / 2)
			center += part.Position
		end
		center /= #parts
		local drop = math.max(low - floorY, 0)
		local tilt = CFrame.Angles((math.random() - 0.5) * 0.8, 0, (math.random() - 0.5) * 0.8)
		local fall = TweenInfo.new(p.fallTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		for _, part in parts do
			local offset = part.Position - center
			local target = CFrame.new(center - Vector3.new(0, drop, 0)) * tilt * CFrame.new(offset)
				* (part.CFrame - part.Position)
			TweenService:Create(part, fall, { CFrame = target }):Play()
		end
		task.delay(p.fallTime, function()
			embers(Vector3.new(center.X, floorY, center.Z), floorY, scale, 2, p.emberSize)
			local fade = TweenInfo.new(p.fadeTime)
			for _, part in parts do
				TweenService:Create(part, fade, { Transparency = 1 }):Play()
			end
			Debris:AddItem(limb, p.fadeTime + 0.1)
		end)
	end

	-- Тело проседает, трескается на крупные куски и рассыпается кучкой углей.
	local function collapse(corpse, floorY, scale)
		local p = PhysicsFX.char
		forget(corpse)
		local parts = visibleParts(corpse)
		for _, item in corpse:GetDescendants() do
			if item:IsA("BasePart") then
				item.Anchored = true
				if item.Transparency >= 1 then
					item.CanCollide = false
				end
			elseif item:IsA("WeldConstraint") then
				item:Destroy()
			end
		end
		if #parts == 0 then
			corpse:Destroy()
			return
		end
		local center = corpse:GetBoundingBox().Position

		-- Проседает: всё ближе к полу, брюхо садится.
		local sink = TweenInfo.new(p.sinkTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		for _, part in parts do
			local height = part.Position.Y - floorY
			TweenService:Create(part, sink, {
				CFrame = part.CFrame - Vector3.new(0, height * (1 - p.sinkKeep), 0),
			}):Play()
		end

		-- Трескается: куски чуть расходятся и заваливаются кто куда.
		task.delay(p.sinkTime, function()
			if not corpse.Parent then
				return
			end
			local crack = TweenInfo.new(p.crackTime, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
			for _, part in parts do
				local out = part.Position - center
				out = Vector3.new(out.X, 0, out.Z)
				out = out.Magnitude > 1e-3 and out.Unit or Vector3.zero
				local turn = CFrame.Angles((math.random() - 0.5) * 0.7, (math.random() - 0.5) * 0.7, (math.random() - 0.5) * 0.7)
				TweenService:Create(part, crack, {
					CFrame = (part.CFrame + out * p.crackSpread * scale) * turn,
				}):Play()
			end
			task.delay(p.crackTime, function()
				if not corpse.Parent then
					return
				end
				embers(Vector3.new(center.X, floorY, center.Z), floorY, scale, p.heap, p.emberSize * 1.5)
				local fade = TweenInfo.new(p.fadeTime)
				for _, part in parts do
					TweenService:Create(part, fade, { Transparency = 1 }):Play()
				end
				Debris:AddItem(corpse, p.fadeTime + 0.1)
			end)
		end)
	end

	local function shuffle(list)
		for i = #list, 2, -1 do
			local j = math.random(i)
			list[i], list[j] = list[j], list[i]
		end
		return list
	end

	local function crumble(corpse, scale, floorY)
		local p = PhysicsFX.char
		task.delay(p.smokeTime, function()
			local limbs = shuffle(limbsOf(corpse))
			local gap = p.limbsTime / math.max(#limbs, 1)
			for _, limb in limbs do
				if not corpse.Parent then
					return
				end
				dropLimb(corpse, limb, floorY, scale)
				task.wait(gap)
			end
			if corpse.Parent then
				collapse(corpse, floorY, scale)
			end
		end)
	end

	-- ============ Хрупкий труп (холодная ветка) ============
	-- Заиндевевший, бледно-голубой, стеклянный. Лопается от касания — решает сервер
	-- (Corpses.Touch), сюда приходит уже «лопни».

	local function frost(corpse)
		local p = PhysicsFX.brittle
		for _, part in visibleParts(corpse) do
			part.Color = part.Color:Lerp(p.color, p.tint)
			part.Material = Enum.Material.Glass
			part.Reflectance = p.reflectance
			part.Transparency = math.max(part.Transparency, p.transparency)
		end
	end

	-- Лопнул: туша колется на свои же детали — они разлетаются и ложатся на пол кусками
	-- льда, поверх брызжут мелкие осколки и снежная пыль. Полежав, всё тает в лужицу.
	local function shatter(corpse, scale)
		local p = PhysicsFX.brittle
		local box, size = corpse:GetBoundingBox()
		local center = box.Position
		local floorY = center.Y - size.Y / 2
		local folder = container("Debris")
		local melt = TweenInfo.new(p.meltTime, Enum.EasingStyle.Linear)

		-- Куски туши: без сварки и физики, долетают твином и ложатся на пол.
		local parts = visibleParts(corpse)
		for _, item in corpse:GetDescendants() do
			if item:IsA("BasePart") then
				item.Anchored = true
				item.CanCollide = false
			elseif item:IsA("WeldConstraint") or item:IsA("ParticleEmitter") then
				item:Destroy()
			end
		end
		corpse.Name = corpse.Name .. " (лопнул)"
		corpse.Parent = folder
		local fly = TweenInfo.new(p.flyTime, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out)
		for _, part in parts do
			part.Material = Enum.Material.Ice
			part.Transparency = math.min(part.Transparency, 0.1)
			local out = part.Position - center
			out = Vector3.new(out.X, 0, out.Z)
			out = out.Magnitude > 1e-3 and out.Unit or Vector3.new(math.random() - 0.5, 0, math.random() - 0.5).Unit
			local land = part.Position + out * p.scatter * scale * (0.3 + math.random())
			local low = math.min(part.Size.X, part.Size.Y, part.Size.Z) / 2
			local turn = CFrame.Angles((math.random() - 0.5) * 1.2, (math.random() - 0.5) * 2, (math.random() - 0.5) * 1.2)
			TweenService:Create(part, fly, {
				CFrame = CFrame.new(land.X, floorY + low, land.Z) * turn * (part.CFrame - part.Position),
			}):Play()
		end
		task.delay(p.flyTime + p.lieTime, function()
			for _, part in parts do
				if part.Parent then
					TweenService:Create(part, melt, { Transparency = 1, Size = part.Size * 0.5 }):Play()
				end
			end
			Debris:AddItem(corpse, p.meltTime + 0.1)
		end)

		-- Мелкие осколки — физические, скачут по полу.
		local count = math.max(4, math.floor(p.shards * scale + 0.5))
		for _ = 1, count do
			local shard = plainPart("IceShard", folder)
			local edge = p.shardSize * scale * (0.5 + math.random())
			shard.Size = Vector3.new(edge * 0.5, edge, edge * 0.8)
			shard.CFrame = box * CFrame.new((math.random() - 0.5) * size.X, (math.random() - 0.5) * size.Y,
				(math.random() - 0.5) * size.Z) * CFrame.Angles(math.random() * 6.3, math.random() * 6.3, 0)
			shard.Material = Enum.Material.Ice
			shard.Color = p.color
			shard.Transparency = 0.1
			shard.CanCollide = true
			local out = shard.Position - center
			out = Vector3.new(out.X, 0, out.Z)
			out = out.Magnitude > 1e-3 and out.Unit or Vector3.xAxis
			Loose.Spawn(shard, {
				group = "Corpses",
				velocity = (out + Vector3.yAxis * p.lift) * p.speed * (0.5 + math.random()),
				spin = Loose.RandomSpin(8),
			})
			Loose.Track(shard, "shard")
			task.delay(p.lieTime, function()
				if shard.Parent then
					TweenService:Create(shard, melt, { Transparency = 1, Size = shard.Size * 0.3 }):Play()
					Debris:AddItem(shard, p.meltTime + 0.1)
				end
			end)
		end

		-- Снежная пыль в момент удара.
		local dust = plainPart("FrostDust", folder)
		dust.Transparency = 1
		dust.Size = Vector3.one
		dust.CFrame = CFrame.new(center)
		local puff = Instance.new("ParticleEmitter")
		puff.Texture = "rbxasset://textures/particles/smoke_main.dds"
		puff.Color = ColorSequence.new(Color3.fromRGB(240, 248, 255), p.color)
		puff.Transparency = NumberSequence.new(0.2, 1)
		puff.Size = NumberSequence.new(0.6 * scale, 2.2 * scale)
		puff.Lifetime = NumberRange.new(0.5, 0.9)
		puff.Speed = NumberRange.new(4, 9)
		puff.SpreadAngle = Vector2.new(180, 60)
		puff.Drag = 4
		puff.Rate = 0
		puff.Parent = dust
		puff:Emit(p.puff)
		Debris:AddItem(dust, 1.2)

		-- Талая лужица там, где лежат куски.
		local water = Instance.new("Model")
		water.Name = "Талая вода"
		local spots = puddle(water, center, floorY, size.X * 0.9, p.water, Enum.Material.SmoothPlastic, p.flyTime + p.lieTime)
		for _, spot in spots do
			spot.Transparency = 0.45
		end
		water.Parent = container("Blood")
		remember(stains, water, maxStains)
		fadeAway(water, spots, p.flyTime + p.lieTime + p.meltTime, p.waterTime)
	end

	-- ============ Болотный труп ============
	-- Умер Болотным — труп заражает прошедших (решает сервер, вокруг точки смерти).
	-- Игрок видит это так: туша зеленеет, под ней болотная лужа ровно в радиус заразы,
	-- в луже вздуваются и лопаются пузыри. Труп ушёл (съеден, лимит) — лужа сохнет.
	local function swampy(corpse, scale, at, floorY)
		local p = PhysicsFX.swampy
		for _, part in visibleParts(corpse) do
			part.Color = part.Color:Lerp(p.color, p.tint)
		end

		local radius = Elements.Swamp.contagion.radius
		local pool = Instance.new("Model")
		pool.Name = corpse.Name .. " (болото)"
		local spots = puddle(pool, at, floorY, radius * 2, p.pool, Enum.Material.SmoothPlastic, 0.6)
		for _, spot in spots do
			spot.Transparency = p.poolTransparency
		end
		pool.Parent = container("Blood")

		local folder = corpse.Parent
		task.spawn(function()
			local grow = TweenInfo.new(p.bubbleTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			local pop = TweenInfo.new(0.12, Enum.EasingStyle.Linear)
			while corpse.Parent == folder and pool.Parent do
				local angle = math.random() * math.pi * 2
				local distance = radius * 0.8 * math.sqrt(math.random())
				local size = p.bubbleSize * scale * (0.6 + math.random() * 0.8)
				local bubble = plainPart("Bubble", pool)
				bubble.Shape = Enum.PartType.Ball
				bubble.Material = Enum.Material.SmoothPlastic
				bubble.Color = p.bubble
				bubble.Transparency = 0.25
				bubble.Size = Vector3.one * 0.05
				bubble.CFrame = CFrame.new(at.X + math.cos(angle) * distance, floorY + LIFT, at.Z + math.sin(angle) * distance)
				TweenService:Create(bubble, grow, { Size = Vector3.one * size }):Play()
				task.delay(p.bubbleTime, function()
					if bubble.Parent then
						TweenService:Create(bubble, pop, { Size = Vector3.one * size * 1.4, Transparency = 1 }):Play()
						Debris:AddItem(bubble, 0.15)
					end
				end)
				task.wait(1 / p.rate)
			end
			fadeAway(pool, spots, 0, p.fadeTime)
		end)
	end

	return {
		swampy = swampy,
		crush = crush,
		melt = melt,
		dissolve = dissolveBody,
		gib = gib,
		destroy = destroy,
		crumble = crumble,
		frost = frost,
		shatter = shatter,
	}
end
