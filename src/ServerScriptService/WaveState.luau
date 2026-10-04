-- Флаг «волна идёт прямо сейчас». Отдельный модуль, а не локальная переменная в WaveRunner:
-- WaveRunner — Script, а не ModuleScript, и TowerBuilder не может его require'ить напрямую.
--
-- stopped — волну оборвал промокод STOP (PromoCode): недосланные группы больше не спавнятся.
-- Сбрасывается сам при старте следующей волны.
local WaveState = {
	active = false,
	stopped = false,
}

function WaveState.IsActive()
	return WaveState.active
end

function WaveState.SetActive(value)
	WaveState.active = value
	if value then
		WaveState.stopped = false
	end
end

function WaveState.Stop()
	WaveState.stopped = true
end

function WaveState.IsStopped()
	return WaveState.stopped
end

return WaveState
