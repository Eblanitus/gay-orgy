-- Подсказка заливки элемента на турели. Ставят её и игрок-построенным турелям
-- (BuildInteraction), и пустой стартовой Колбе обучения (TowerBootstrap, задача #298).
local PourPrompt = {}

function PourPrompt.Add(tower)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "PourPrompt"
	prompt.ActionText = "Залить элемент"
	prompt.ObjectText = tower.Name
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	-- Подсказка на модели турели встаёт в её корень, а он внутри деталей, твёрдых с #382:
	-- с проверкой видимости турель могла не открываться.
	prompt.RequiresLineOfSight = false
	prompt.Parent = tower
	return prompt
end

return PourPrompt
