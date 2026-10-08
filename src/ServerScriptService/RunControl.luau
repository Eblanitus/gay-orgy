-- Мост к запуску забега из других серверных скриптов (задача #435).
-- Сам забег живёт в WaveRunner (его состояние — локальные переменные скрипта), поэтому
-- WaveRunner кладёт сюда функцию при старте, а PromoCode её вызывает.
local RunControl = {}

-- function(levelNumber): начинает забег уровня с нуля, даже если другой забег идёт.
-- Проставляет WaveRunner; до его запуска nil.
RunControl.StartLevel = nil

return RunControl
