-- Останки без тела (по вики): давит, плавит, растворяет, рвёт, уничтожает. КЛИЕНТСКАЯ часть.
--
-- Вид решает сервер (Effects.RemainsOf) и присылает в hit.remains; CorpseFX.Leave отдаёт сюда
-- всё, что не тело. Записи на сервере у этих видов нет — Пеликану есть нечего, и туши в списке
-- трупов тоже нет. Что остаётся на полу (лепёшка, лужица, пятно), входит в общий лимит пятен.
-- Числа — PhysicsFX.remains.
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

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

	-- ДАВИТ: расплющенное тёмное пятно в форме жука и пара отлетевших кусков.
	-- Каждая видимая деталь ложится на пол там же, где была (чуть шире — раздавленное
	-- расползается), своей самой вертикальной осью вверх, и сплющивается по ней. Силуэт
	-- с растопыренными лапами остаётся узнаваемым: видно, кого раздавило.
	local function crush(enemy, hit, scale, floorY)
		local p = plan.crush
		local clone = bodyClone(enemy)
		local center = enemy:GetPivot().Position

		-- Куски — до сплющивания: улетают целыми.
		for _, group in chooseLimbs(clone, p.pieceFraction) do
			detachPiece(clone, group, center, hit.from, p.pieceFraction, scale, hit.floorY, hit.carry)
		end

		for _, part in clone:GetDescendants() do
			if part:IsA("BasePart") and part.Transparency < 1 then
				local cf = part.CFrame
				local cols = { cf.RightVector, cf.UpVector, cf.LookVector }
				local b = 1
				for i = 2, 3 do
					if math.abs(cols[i].Y) > math.abs(cols[b].Y) then
						b = i
					end
				end
				-- b — ось, что ближе всех к вертикали, a и c — следующие по кругу (b × a = c).
				local a = b % 3 + 1
				local c = a % 3 + 1
				local flat = cols[a] * Vector3.new(1, 0, 1)
				flat = flat.Magnitude > 1e-3 and flat.Unit or Vector3.xAxis
				local m = {}
				m[b] = Vector3.yAxis * (cols[b].Y >= 0 and 1 or -1)
				m[a] = flat
				m[c] = m[b]:Cross(m[a])

				local size = part.Size
				local thin = math.max(size[AXES[b]] * p.squash, p.minThickness)
				local dims = { size.X, size.Y, size.Z }
				dims[b] = thin

				-- Что было выше, ложится поверх: без этого детали мерцают друг с другом.
				local layer = math.clamp(cf.Position.Y - floorY, 0, 20) * p.layer
				local rel = cf.Position - center
				local position = Vector3.new(center.X + rel.X * p.spread, floorY + LIFT + thin / 2 + layer,
					center.Z + rel.Z * p.spread)

				part.Size = Vector3.new(dims[1], dims[2], dims[3])
				part.CFrame = CFrame.fromMatrix(position, m[1], m[2], m[3])
				part.Color = part.Color:Lerp(p.color, p.darken)
				part.CastShadow = false
			end
		end

		clone.Name = enemy.Name .. " (раздавлен)"
		clone.Parent = container("Blood")
		remember(stains, clone, maxStains)
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
		local spots = puddle(pool, center, floorY, width * p.size, p.glow, Enum.Material.Neon, p.sinkTime)
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
					part.Anchored = false
					part.AssemblyLinearVelocity = (out + Vector3.yAxis * p.lift) * p.fragmentSpeed * (0.6 + math.random() * 0.8)
					part.AssemblyAngularVelocity = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 20
					TweenService:Create(part, fade, { Transparency = 1, Size = part.Size * 0.4 }):Play()
				end
			end
		end
		Debris:AddItem(clone, p.fragmentTime + 0.1)
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

	return {
		crush = crush,
		melt = melt,
		dissolve = dissolveBody,
		gib = gib,
		destroy = destroy,
	}
end
