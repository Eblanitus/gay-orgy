-- Промокод: секретное слово с HUD, дающее разовую прибавку к материи.
-- Сам код знает только сервер и решает исход сам — клиент (Hud) лишь предлагает строку,
-- иначе любой игрок выдавал бы себе материю напрямую через консоль.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RedeemCode = Remotes:WaitForChild("RedeemCode")
local Notify = Remotes:WaitForChild("Notify")

local Matter = require(ServerScriptService:WaitForChild("Matter"))
local Crafting = require(ServerScriptService:WaitForChild("Crafting"))
local TowerUnlocks = require(ServerScriptService:WaitForChild("TowerUnlocks"))
local WaveEditor = require(ServerScriptService:WaitForChild("WaveEditor"))

-- Регистр не важен: "a500" и "A500" — один и тот же код.
-- Смените на свой, если этот где-то засветится.
local SECRET_CODE = "A500"
local REWARD = 500

-- Латиница намеренно: в отличие от кириллицы выше, :upper() её реально приводит к одному
-- регистру, так что "codex"/"Codex"/"CODEX" сработают одинаково.
local REVEAL_CODE = "CODEX"

-- Открывает разом Испаритель/Центрифугу (задача #56, сужено задачей #99): Мортира
-- (Станция FPV-дронов) и Инжектор с задачи #99 доступны без кода — locked снят с них
-- в Towers. Бур в список не входит — он скрыт отдельным, более ранним решением автора
-- (задача #54) и этим промокодом не поднимается.
local UNLOCK_TURRETS_CODE = "TWR"

-- Открывает конструктор волн: панель, в которой игрок сам набирает, какие жуки
-- пойдут в следующей волне и сколько их (см. WaveEditor и WaveEditorUI).
-- Открытие действует на весь сервер до его перезапуска — это инструмент для проверки
-- видов, а не награда, и перевводить код каждый забег было бы мучением.
local WAVE_EDITOR_CODE = "WAVE"

RedeemCode.OnServerEvent:Connect(function(player, code)
	if typeof(code) ~= "string" then
		return
	end

	local upperCode = code:upper()

	if upperCode == REVEAL_CODE then
		local revealed = Crafting.RevealAll()
		if #revealed == 0 then
			Notify:FireClient(player, "Промокод принят: все рецепты уже открыты")
		else
			Notify:FireClient(player, ("Промокод принят: открыто рецептов — %d"):format(#revealed))
		end
		return
	end

	if upperCode == UNLOCK_TURRETS_CODE then
		if TowerUnlocks.UnlockAll() then
			Notify:FireClient(player, "Промокод принят: Испаритель и Центрифуга открыты")
		else
			Notify:FireClient(player, "Промокод принят: турели уже были открыты")
		end
		return
	end

	if upperCode == WAVE_EDITOR_CODE then
		if WaveEditor.Unlock() then
			Notify:FireClient(player, "Промокод принят: конструктор волн открыт — кнопка «Волна» в HUD")
		else
			Notify:FireClient(player, "Промокод принят: конструктор волн уже был открыт")
		end
		return
	end

	if upperCode ~= SECRET_CODE then
		Notify:FireClient(player, "Неверный промокод")
		return
	end

	Matter.Add(REWARD)
	Notify:FireClient(player, ("Промокод принят: +%d материи"):format(REWARD))
end)
