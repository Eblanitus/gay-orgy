-- Ставит большую гермодверь и портал входа в активную локацию (см. EntranceGate).
-- На каждую смену локации — заново: у другой карты свой вход. Ошибка сборки двери игру не роняет:
-- остаётся прежний проём и старая створка.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Arena = require(ReplicatedStorage:WaitForChild("Arena"))
local EntranceGate = require(script.Parent:WaitForChild("EntranceGate"))

local function build()
	local location = Arena.Location()
	if not location then
		return
	end
	local ok, model, reason = pcall(EntranceGate.Build, location)
	if not ok then
		warn("[Дверь] сборка упала: " .. tostring(model))
	elseif not model then
		warn("[Дверь] не поставлена: " .. tostring(reason))
	end
end

build()
Arena.OnChanged(build)
