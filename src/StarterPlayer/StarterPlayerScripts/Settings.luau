-- Текущие значения настроек интерфейса на клиенте. Список самих настроек — общий,
-- в ReplicatedStorage.UISettings; здесь только «что выбрал этот игрок» и оповещение тех, кто на них смотрит.
--
-- Зачем отдельный модуль, а не поля в SettingsUI: настройки читают UITheme и CombatFX,
-- а экран настроек — часть главного меню, которое само собрано на UITheme. Лежи значения
-- в экране, получился бы круг в require.
--
-- Значение применяется сразу и не ждёт ответа сервера: переключатель, который срабатывает
-- через круг до сервера и обратно, читается как сломанный. Серверу оно уходит только
-- чтобы пережить выход из игры, и там же проверяется (SettingsService).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UISettings = require(ReplicatedStorage:WaitForChild("UISettings"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RequestSetSettingRemote = Remotes:WaitForChild("RequestSetSetting")
local ProfileSyncedRemote = Remotes:WaitForChild("ProfileSynced")

local Settings = {}

-- До первого ProfileSynced игра идёт на умолчаниях: клиентские скрипты стартуют
-- раньше, чем грузится профиль, и ждать его ради цвета фона значило бы держать весь
-- интерфейс несобранным.
local values = UISettings.Default()

-- Кто применяет настройку — подписывается сюда. Опрос в Heartbeat не годится: сетка на
-- панелях уже построена к моменту переключения, её надо погасить, а не перестать строить.
Settings.Changed = Instance.new("BindableEvent")

function Settings.Get(key)
	return UISettings.Read(values, key)
end

function Settings.Set(key, value)
	if not UISettings.Valid(key, value) or values[key] == value then
		return
	end
	values[key] = value
	RequestSetSettingRemote:FireServer(key, value)
	Settings.Changed:Fire(key, value)
end

-- Профиль с сервера. Событие общее на весь профиль, и настройки в нём — пятый аргумент;
-- остальное читают LobbyUI и JournalUI, каждый своё.
ProfileSyncedRemote.OnClientEvent:Connect(function(_plutonium, _levels, _recipes, _killedTypes, stored)
	if type(stored) ~= "table" then
		return
	end
	for _, item in UISettings.List do
		local saved = stored[item.key]
		-- Не трогаем настройки, которой в профиле нет: у старого игрока там лежит только то,
		-- что он менял руками, а остальное должно остаться на умолчании. Значение сверяется
		-- тем же UISettings.Valid, что и на сервере: в профиле может лежать вариант,
		-- которого в списке уже нет.
		if UISettings.Valid(item.key, saved) and saved ~= values[item.key] then
			values[item.key] = saved
			Settings.Changed:Fire(item.key, saved)
		end
	end
end)

return Settings
