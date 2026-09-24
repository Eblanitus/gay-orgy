-- Связывает игрока с TowerBuilder через RemoteEvent. Сам TowerBuilder об этом ничего не знает —
-- он уже умел строить/заливать до этого (см. TowerBootstrap, прошлые тесты).
-- Решение всегда принимает сервер: клиент только просит через RequestBuildTower/RequestPourElement.
--
-- Площадок с ТЗ v2.1 больше нет: строить можно в любую свободную клетку сетки. Подсказка
-- постройки поэтому убрана — ProximityPrompt на каждую из 9375 клеток не поставишь. Вместо
-- неё клиент шлёт координаты клетки под курсором (см. TowerInteraction). Заливка элемента
-- осталась на ProximityPrompt: она привязана к конкретной башне, к которой игрок и так подходит.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Towers = require(ReplicatedStorage:WaitForChild("Towers"))
local Elements = require(ReplicatedStorage:WaitForChild("Elements"))
local TowerBuilder = require(ServerScriptService:WaitForChild("TowerBuilder"))
local Inventory = require(ServerScriptService:WaitForChild("Inventory"))
local TowerUnlocks = require(ServerScriptService:WaitForChild("TowerUnlocks"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RequestBuildTower = Remotes:WaitForChild("RequestBuildTower")
local RequestPourElement = Remotes:WaitForChild("RequestPourElement")
local Notify = Remotes:WaitForChild("Notify")


local function addPourPrompt(tower)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "PourPrompt"
	prompt.ActionText = "Залить элемент"
	prompt.ObjectText = tower.Name
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.Parent = tower
	return prompt
end

-- Клетка и тип постройки приходят от клиента, поэтому проверяются как чужие данные: числа
-- и целые, тип — существующий ключ таблицы Towers (иначе подделанный запрос уронил бы
-- TowerBuilder.Build на assert). Всё остальное — границы арены, занятость клетки, хватает ли
-- материи — проверяет сам Build, и дублировать его здесь не надо.
RequestBuildTower.OnServerEvent:Connect(function(player, cx, cz, buildingType, turn)
	if typeof(cx) ~= "number" or typeof(cz) ~= "number" then
		return
	end
	if cx ~= math.floor(cx) or cz ~= math.floor(cz) then
		return
	end
	if typeof(buildingType) ~= "string" or not Towers[buildingType] then
		return
	end
	-- Поворот — такая же чужая цифра, как и клетка: целая четверть 0..3 и ничего иного.
	-- Не пришёл вовсе (старый клиент) — ставим без поворота, как ставилось до этого.
	if turn == nil then
		turn = 0
	elseif typeof(turn) ~= "number" or turn ~= math.floor(turn) or turn < 0 or turn > 3 then
		return
	end
	if TowerUnlocks.IsLocked(buildingType) then
		Notify:FireClient(player, ("%s ещё не открыт — нужен промокод"):format(Towers[buildingType].name))
		return
	end

	local ok, result = TowerBuilder.Build(cx, cz, buildingType, turn)
	if ok then
		-- Подсказка заливки нужна только тому, кто элемент принимает.
		if Towers[buildingType].fireRate then
			addPourPrompt(result)
		end
	else
		Notify:FireClient(player, result)
	end
end)

RequestPourElement.OnServerEvent:Connect(function(player, tower, elementKey)
	if typeof(tower) ~= "Instance" or not tower:IsDescendantOf(Workspace) then
		return
	end
	if typeof(elementKey) ~= "string" then
		return
	end

	local prompt = tower:FindFirstChild("PourPrompt")
	if not prompt then
		return -- уже залито или это не башня — игнорируем запрос
	end

	-- Залитый элемент берётся из инвентаря, а не из ниоткуда: «стоит в башне, пока не вынешь» —
	-- значит потрачен из общего запаса, а не создан по требованию. Списываем только после
	-- успешной заливки, чтобы не заводить отдельный откат при отказе TowerBuilder.
	if Inventory.Get(elementKey) < 1 then
		local name = Elements[elementKey] and Elements[elementKey].name or elementKey
		Notify:FireClient(player, ("не хватает: %s"):format(name))
		return
	end

	local ok, result = TowerBuilder.PourElement(tower, elementKey)
	if ok then
		Inventory.Remove(elementKey, 1)
		prompt:Destroy()
	else
		Notify:FireClient(player, result)
	end
end)
