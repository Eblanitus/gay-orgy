-- Флаг «волна идёт прямо сейчас». Отдельный модуль, а не локальная переменная в WaveRunner:
-- WaveRunner — Script, а не ModuleScript, и TowerBuilder не может его require'ить напрямую.
local WaveState = {
	active = false,
}

function WaveState.IsActive()
	return WaveState.active
end

function WaveState.SetActive(value)
	WaveState.active = value
end

return WaveState
