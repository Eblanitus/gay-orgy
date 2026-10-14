-- Биореактор на клиенте: всё, что в нём двигается, и контейнеры с винтами дронов-носильщиков.
-- Сервер ставит только атрибуты (Processing на реакторе — Bioreactor, Loaded на дроне —
-- Carriers) и двигает дрона целиком;
-- гонять CFrame каждой детали с сервера значило бы реплицировать их каждый кадр ради картинки
-- (тот же довод, что у BuildingVisuals).
--
-- Детали реактора с атрибутами (ставит BioreactorModel):
--   Slide, SlideWrap, SlideDir, SlidePhase — едут по прямой и возвращаются (планки ленты, пузыри);
--   Roll, RollAxis, RollDir — крутятся вокруг своей оси (валец, валы шредера, шнек).
-- Пока реактор перерабатывает груз (Processing > 0), всё идёт быстрее.
-- Дрон сдал груз (Loaded стал false) — контейнер опрокидывается и опускается обратно.
-- Винты дрона крутятся всё время, контейнер качается на подвесе (на ходу — сильнее).
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local towersFolder = Workspace:WaitForChild("Towers")
local carriersFolder = Workspace:WaitForChild("Carriers")

local GRIND_ROLL = 2.6 -- во сколько раз быстрее крутится, когда мелет
local GRIND_SLIDE = 1.6 -- во сколько раз быстрее лента и пузыри
local TIP_TIME = 0.5 -- сек на подъём кузова
local TIP_HOLD = 1.1 -- сек от сдачи груза до команды «опустить»
local WAIT_ANCHOR = 15
local ROTOR_SPIN = 20 -- рад/с: винты крутятся, даже когда дрон висит у туши
local SWAY = 0.05 -- рад: качание контейнера на подвесе
local SWAY_PER_SPEED = 0.004 -- рад на студ/с: на ходу контейнер качается сильнее

local reactors = {} -- [model] = { anchor, leaves = { [part] = leaf } }
local drones = {} -- [model] = { root, hinge, hingeBase, tip, rotors = { { joint, base, angle, spin } }, phase, last }

local function addLeaf(entry, part)
	if not part:IsA("BasePart") or entry.leaves[part] then
		return
	end
	local roll, slide = part:GetAttribute("Roll"), part:GetAttribute("Slide")
	if not roll and not slide then
		return
	end
	local pivot = entry.anchor.CFrame
	local leaf = { part = part, rest = pivot:ToObjectSpace(part.CFrame), phase = 0 }
	if roll then
		leaf.roll = math.rad(roll)
		local point = part:GetAttribute("RollAxis") or Vector3.zero
		local dir = part:GetAttribute("RollDir") or Vector3.xAxis
		-- Ось вращения как CFrame в осях модели: начало — точка оси, X — направление оси.
		leaf.axis = CFrame.lookAt(point, point + dir) * CFrame.Angles(0, math.rad(90), 0)
	end
	if slide then
		leaf.slide = slide
		leaf.wrap = part:GetAttribute("SlideWrap") or 1
		leaf.dir = part:GetAttribute("SlideDir") or Vector3.zAxis
		leaf.phase = part:GetAttribute("SlidePhase") or 0
		leaf.rest = leaf.rest - leaf.dir * leaf.phase
	end
	entry.leaves[part] = leaf
end

local function attachReactor(model)
	if reactors[model] or not model:IsA("Model") then
		return
	end
	task.spawn(function()
		local deadline = os.clock() + WAIT_ANCHOR
		while model.Parent and not model:GetAttribute("Type") and os.clock() < deadline do
			task.wait(0.1)
		end
		if model:GetAttribute("Type") ~= "Bioreactor" then
			return
		end
		local anchor = model.PrimaryPart or model:WaitForChild("Root", WAIT_ANCHOR)
		if not anchor or not model.Parent then
			return
		end
		local entry = { anchor = anchor, leaves = {} }
		reactors[model] = entry
		for _, part in model:GetDescendants() do
			addLeaf(entry, part)
		end
		model.DescendantAdded:Connect(function(part)
			addLeaf(entry, part)
		end)
	end)
end

local function attachDrone(model)
	if drones[model] or not model:IsA("Model") then
		return
	end
	task.spawn(function()
		local root = model:WaitForChild("Root", WAIT_ANCHOR)
		local hinge = root and root:WaitForChild("BinHinge", WAIT_ANCHOR)
		if not hinge or not model.Parent then
			return
		end
		local entry = {
			root = root,
			hinge = hinge,
			hingeBase = hinge.C0,
			tipAngle = math.rad(hinge:GetAttribute("TipAngle") or 45),
			tip = 0,
			tipUntil = 0,
			loaded = model:GetAttribute("Loaded") == true,
			rotors = {},
			phase = math.random() * 2 * math.pi, -- у каждого дрона качание не в такт
			last = root.Position,
		}
		local function addRotor(joint)
			if joint:IsA("Motor6D") and joint.Name == "RotorJoint" then
				table.insert(entry.rotors, { joint = joint, base = joint.C0, angle = 0, spin = joint:GetAttribute("Spin") or 1 })
			end
		end
		for _, joint in root:GetChildren() do
			addRotor(joint)
		end
		root.ChildAdded:Connect(addRotor)
		drones[model] = entry
	end)
end

local function smooth(t)
	return t * t * (3 - 2 * t)
end

RunService.RenderStepped:Connect(function(dt)
	local now = os.clock()
	for model, entry in reactors do
		if not model.Parent then
			reactors[model] = nil
		else
			local grinding = (model:GetAttribute("Processing") or 0) > 0
			local pivot = entry.anchor.CFrame
			for part, leaf in entry.leaves do
				if not part.Parent then
					entry.leaves[part] = nil
				else
					local frame = leaf.rest
					if leaf.roll then
						leaf.phase = (leaf.phase + leaf.roll * dt * (grinding and GRIND_ROLL or 1)) % (2 * math.pi)
						frame = leaf.axis * CFrame.Angles(leaf.phase, 0, 0) * leaf.axis:Inverse() * frame
					elseif leaf.slide then
						leaf.phase = (leaf.phase + leaf.slide * dt * (grinding and GRIND_SLIDE or 1)) % leaf.wrap
						frame = leaf.rest + leaf.dir * leaf.phase
					end
					part.CFrame = pivot * frame
				end
			end
		end
	end

	for model, entry in drones do
		if not model.Parent or not entry.root.Parent then
			drones[model] = nil
		else
			-- Контейнер: груз сдан — поднимается, держится и опускается обратно.
			local loaded = model:GetAttribute("Loaded") == true
			if entry.loaded and not loaded then
				entry.tipUntil = now + TIP_HOLD
			end
			entry.loaded = loaded
			local want = now < entry.tipUntil and 1 or 0
			if entry.tip ~= want then
				local step = dt / TIP_TIME
				entry.tip = want > entry.tip and math.min(entry.tip + step, 1) or math.max(entry.tip - step, 0)
			end
			-- Качание на подвесе: на ходу амплитуда больше (скорость — по смещению за кадр).
			local position = entry.root.Position
			local speed = (position - entry.last).Magnitude / math.max(dt, 1e-3)
			entry.last = position
			entry.phase += dt
			local swing = SWAY + math.min(speed, 16) * SWAY_PER_SPEED
			local pitch = swing * math.sin(entry.phase * 2.6)
			local roll = swing * 0.6 * math.sin(entry.phase * 1.9 + 1)
			entry.hinge.C0 = entry.hingeBase * CFrame.Angles(entry.tipAngle * smooth(entry.tip) + pitch, 0, roll)
			-- Винты крутятся сами, даже когда дрон стоит.
			for _, rotor in entry.rotors do
				rotor.angle = (rotor.angle + rotor.spin * ROTOR_SPIN * dt) % (2 * math.pi)
				rotor.joint.C0 = rotor.base * CFrame.Angles(rotor.angle, 0, 0)
			end
		end
	end
end)

for _, model in towersFolder:GetChildren() do
	attachReactor(model)
end
towersFolder.ChildAdded:Connect(attachReactor)
for _, model in carriersFolder:GetChildren() do
	attachDrone(model)
end
carriersFolder.ChildAdded:Connect(attachDrone)
