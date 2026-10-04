-- Игрок не проходит сквозь жуков: тело жука мягко выталкивает персонажа в сторону.
--
-- Физической коллизии у жука нет (сервер двигает невидимый якорь PivotTo, а видимое тело
-- на клиенте без CanCollide), и включать её нельзя: анкорнутая деталь, которую двигают
-- кадрами, не толкает, а выстреливает персонажа, и он застревает в ней. Поэтому толчок —
-- тем же объёмом, что у толкучки (Crowd): капсула следа FootRadius/FootFront/FootBack по
-- высоте от ступней (пивот минус RideHeight) до спины (пивот плюс BodyHalfHeight).
-- Двигается только свой персонаж: им и так владеет этот клиент.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local enemiesFolder = Workspace:WaitForChild("Enemies")

-- Персонаж как столбик: радиус по плечам.
local PLAYER_RADIUS = 1
-- Какую долю перекрытия снимать за секунду: мягко, без рывка, но жук не проходит насквозь.
local PUSH_RATE = 12
-- Перекрытие по высоте меньше этого — касание, не толчок (персонаж стоит на спине, задел лапы).
local VERTICAL_TOLERANCE = 0.2

RunService.PreSimulation:Connect(function(dt)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.SeatPart or humanoid.Health <= 0 then
		return
	end

	local position = root.Position
	local feet = position.Y - humanoid.HipHeight - root.Size.Y / 2
	local head = position.Y + root.Size.Y / 2 + 1.5
	local pushX, pushZ = 0, 0

	for _, enemy in enemiesFolder:GetChildren() do
		local radius = enemy:GetAttribute("FootRadius")
		if radius and enemy:IsA("Model") then
			local pivot = enemy:GetPivot()
			local top = pivot.Position.Y + (enemy:GetAttribute("BodyHalfHeight") or 0.6)
			local bottom = pivot.Position.Y - (enemy:GetAttribute("RideHeight") or 1.5)
			if feet < top - VERTICAL_TOLERANCE and head > bottom then
				-- Ближайшая точка оси следа. Голова модели по +Z, а пивот развёрнут на 180°
				-- (см. Crowd.Add), поэтому вдоль хода — минус LookVector.
				local look = -pivot.LookVector
				local fx, fz = look.X, look.Z
				local length = math.sqrt(fx * fx + fz * fz)
				if length > 1e-3 then
					fx, fz = fx / length, fz / length
				end
				local dx, dz = position.X - pivot.Position.X, position.Z - pivot.Position.Z
				local along = math.clamp(dx * fx + dz * fz,
					enemy:GetAttribute("FootBack") or 0, enemy:GetAttribute("FootFront") or 0)
				local ax, az = dx - fx * along, dz - fz * along
				local distance = math.sqrt(ax * ax + az * az)
				local overlap = radius + PLAYER_RADIUS - distance
				if overlap > 0 then
					if distance < 1e-3 then
						ax, az, distance = 1, 0, 1
					end
					pushX += ax / distance * overlap
					pushZ += az / distance * overlap
				end
			end
		end
	end

	if pushX ~= 0 or pushZ ~= 0 then
		local share = math.clamp(PUSH_RATE * dt, 0, 1)
		root.CFrame += Vector3.new(pushX * share, 0, pushZ * share)
	end
end)
