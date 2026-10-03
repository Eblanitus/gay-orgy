-- Рост персонажа. Рядом с обычным игроком зал, мебель и турели выглядели игрушечными;
-- мир увеличен не масштабом карты, а уменьшением игрока — картинка та же, а дальности,
-- скорости жуков, клетки и разметка остались в прежних студах.
--
-- Model:ScaleTo масштабирует и WalkSpeed с JumpHeight. Их возвращаем: скорость — чтобы
-- переход через зал занимал прежнее время, прыжок — потому что глубина окопа подогнана
-- под него (ConcreteFloor.MAX_DEPTH), и низкий прыжок запер бы игрока в яме.

local Players = game:GetService("Players")

local SCALE = 0.55

local function apply(player: Player, character: Model)
	-- Аксессуары догружаются после появления персонажа; ScaleTo их не догонит, поэтому
	-- ждём внешность целиком.
	if not player:HasAppearanceLoaded() then
		player.CharacterAppearanceLoaded:Wait()
	end
	if player.Character ~= character or not character.Parent then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local walkSpeed, jumpHeight, jumpPower = humanoid.WalkSpeed, humanoid.JumpHeight, humanoid.JumpPower
	character:ScaleTo(SCALE)
	humanoid.WalkSpeed = walkSpeed
	humanoid.JumpHeight = jumpHeight
	humanoid.JumpPower = jumpPower
end

local function watch(player: Player)
	player.CharacterAdded:Connect(function(character)
		apply(player, character)
	end)
	if player.Character then
		task.spawn(apply, player, player.Character)
	end
end

Players.PlayerAdded:Connect(watch)
for _, player in Players:GetPlayers() do
	watch(player)
end
