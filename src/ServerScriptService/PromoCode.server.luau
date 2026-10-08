-- Промокод: секретное слово с HUD, дающее разовую прибавку к материи.
-- Сам код знает только сервер и решает исход сам — клиент (Hud) лишь предлагает строку,
-- иначе любой игрок выдавал бы себе материю напрямую через консоль.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RedeemCode = Remotes:WaitForChild("RedeemCode")
local Notify = Remotes:WaitForChild("Notify")
local EnemiesRevealed = Remotes:WaitForChild("EnemiesRevealed")

local Matter = require(ServerScriptService:WaitForChild("Matter"))
local Crafting = require(ServerScriptService:WaitForChild("Crafting"))
local TowerUnlocks = require(ServerScriptService:WaitForChild("TowerUnlocks"))
local WaveEditor = require(ServerScriptService:WaitForChild("WaveEditor"))
local WaveState = require(ServerScriptService:WaitForChild("WaveState"))
local Crowd = require(ServerScriptService:WaitForChild("Crowd"))
local Tutorial = require(ServerScriptService:WaitForChild("Tutorial"))
local RunControl = require(ServerScriptService:WaitForChild("RunControl"))
local Levels = require(ReplicatedStorage:WaitForChild("Levels"))

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

-- Обрывает идущую волну: все жуки на поле исчезают, недосланные группы не выходят.
-- Жуки убираются тихо, без смерти: смерть дала бы материю и плутоний за каждого, а
-- Сплиттер, Носитель и Подрывник ещё и наплодили бы осколков и взрывов. Волна после
-- этого засчитывается как зачищенная — иначе забег встал бы.
local STOP_WAVE_CODE = "STOP"
local enemiesFolder = game:GetService("Workspace"):WaitForChild("Enemies")

-- Код для проверки (задача #298): разом всё, что открывают коды выше, плюс снимает
-- ограничения обучения (Tutorial) и даёт материю. Материя — в текущий кошелёк: вход
-- в уровень сбрасывает её к стартовой, поэтому вводить код надо уже на уровне.
local TEST_CODE = "TEST"
local TEST_REWARD = 4242

-- Запускает обучение с нуля для проверки (задача #435): забег уровня-обучения начинается
-- сразу, а ограничения, снятые кодом TEST, возвращаются — игрок видит обучение как новичок.
-- Работает в любой момент, в том числе посреди другого забега и после прохождения обучения:
-- чтобы пройти заново, достаточно ввести код ещё раз. Награды за уровень выдаются только
-- в первый раз (Plutonium.AwardLevelClear), так что повтор прогресс профиля не трогает.
local TUTORIAL_CODE = "TUTOR"

RedeemCode.OnServerEvent:Connect(function(player, code)
	if typeof(code) ~= "string" then
		return
	end

	local upperCode = code:upper()

	if upperCode == REVEAL_CODE then
		local revealed = Crafting.RevealAll()
		-- Жуки и ступени карточек (Mastery) открываются только на экране и до выхода из игры:
		-- в профиль (killedTypes, счёт убийств) их не пишем — за первое убийство нового жука
		-- начисляется плутоний (Plutonium.AwardEnemyKill), промокод съел бы награду.
		EnemiesRevealed:FireClient(player)
		if #revealed == 0 then
			Notify:FireClient(player, "Промокод принят: справочник открыт целиком")
		else
			Notify:FireClient(player, ("Промокод принят: справочник открыт целиком, рецептов — %d"):format(#revealed))
		end
		return
	end

	if upperCode == TUTORIAL_CODE then
		local levelNumber
		for number, level in Levels do
			if level.tutorial == true then
				levelNumber = number
				break
			end
		end
		if levelNumber == nil or RunControl.StartLevel == nil then
			Notify:FireClient(player, "Промокод принят, но обучение сейчас запустить нельзя")
			return
		end
		-- Rearm до запуска: Tutorial.Start в startRun публикует состояние уже без снятых ограничений.
		Tutorial.Rearm()
		if not RunControl.StartLevel(levelNumber) then
			Notify:FireClient(player, "Промокод принят, но обучение сейчас запустить нельзя")
			return
		end
		Notify:FireClient(player, "Промокод принят: обучение запущено. Пройди его до конца, а потом введи код снова, чтобы начать заново")
		return
	end

	if upperCode == TEST_CODE then
		Tutorial.UnlockAll()
		TowerUnlocks.UnlockAll()
		WaveEditor.Unlock()
		Crafting.RevealAll()
		EnemiesRevealed:FireClient(player)
		Matter.Add(TEST_REWARD)
		Notify:FireClient(player, ("Промокод принят: всё открыто, +%d материи"):format(TEST_REWARD))
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

	if upperCode == STOP_WAVE_CODE then
		if not WaveState.IsActive() then
			Notify:FireClient(player, "Промокод принят, но волна сейчас не идёт")
			return
		end
		WaveState.Stop()
		-- Жуки волны, уже ждущие места у пролома, вышли бы на поле после зачистки.
		Crowd.CancelPending()
		local count = 0
		for _, enemy in enemiesFolder:GetChildren() do
			enemy:Destroy()
			count += 1
		end
		print(("[Промокод] STOP: волна оборвана, убрано жуков — %d"):format(count))
		Notify:FireClient(player, ("Промокод принят: волна остановлена, жуков убрано — %d"):format(count))
		return
	end

	if upperCode ~= SECRET_CODE then
		Notify:FireClient(player, "Неверный промокод")
		return
	end

	Matter.Add(REWARD)
	Notify:FireClient(player, ("Промокод принят: +%d материи"):format(REWARD))
end)
