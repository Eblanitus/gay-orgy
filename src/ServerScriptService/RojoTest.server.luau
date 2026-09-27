-- ВРЕМЕННО: проверка, что Rojo доносит код до Studio. Удалить после проверки.
print("[ROJO ТЕСТ] ======== Rojo работает: код из src/ дошёл до игры ========")
local p = Instance.new("Part")
p.Name = "ROJO_TEST_CUBE"
p.Anchored = true
p.CanCollide = false
p.Size = Vector3.new(40, 40, 40)
p.Material = Enum.Material.Neon
p.Color = Color3.fromRGB(255, 0, 0)
p.Position = Vector3.new(50, 60, 30)
p.Parent = workspace
