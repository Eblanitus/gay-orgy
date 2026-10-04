-- Лоток результата на алхимическом столе (#297: «на этом фоне он выглядит слишком голым»).
-- Пока под прессом лежит результат: уголки вокруг него цветом элемента, от голов поршней
-- к нему — пунктирные направляющие, над левой подпись «ГОТОВО», над правой обратный отсчёт
-- «В ЗАПАС 3», под результатом полоса таймера тает. Отсчёт кончился — стол забирает сам.
--
-- Tray.Mount(page, result) — result — кнопка результата. Возвращает:
--   layout(left, right) — внутренние кромки голов (TablePress.layout), result уже размещён;
--   show(color, time)   — показать, отсчёт time секунд;
--   hide().
local RunService = game:GetService("RunService")

local Theme = require(script.Parent:WaitForChild("UITheme"))

local Tray = {}

local TUNING = {
	inset = 5, -- уголки отступают от результата на столько пикселей
	arm = 12, -- длина уголка, пиксели
	dash = 4, -- штрих направляющей, пиксели
	gapDash = 4, -- промежуток между штрихами, пиксели
	gap = 8, -- направляющая не доходит до головы и до уголков на столько пикселей
	bar = 2, -- толщина полосы таймера, пиксели
	text = Theme.MIN_TEXT, -- кегль подписей
}

local function frame(name, parent, z)
	local f = Instance.new("Frame")
	f.Name = name
	f.BorderSizePixel = 0
	f.BackgroundTransparency = 1
	f.ZIndex = z
	f.Parent = parent
	return f
end

local function label(parent, z, align)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.FontFace = Theme.font.strong
	l.TextSize = TUNING.text
	l.TextXAlignment = align
	l.TextYAlignment = Enum.TextYAlignment.Bottom
	l.TextColor3 = Theme.color.textMute
	l.ZIndex = z
	l.Parent = parent
	return l
end

function Tray.Mount(page, result)
	local z = result.ZIndex + 1
	local holder = frame("ResultTray", page, z)
	holder.Size = UDim2.fromScale(1, 1)
	holder.Visible = false

	local corners = {}
	for _, c in { Vector2.new(0, 0), Vector2.new(1, 0), Vector2.new(0, 1), Vector2.new(1, 1) } do
		for axis = 1, 2 do
			local bar = frame("Corner", holder, z)
			bar.AnchorPoint = c
			bar.Size = axis == 1 and UDim2.fromOffset(TUNING.arm, 1) or UDim2.fromOffset(1, TUNING.arm)
			bar.BackgroundTransparency = 0
			table.insert(corners, { bar = bar, c = c })
		end
	end

	local rails = { frame("RailL", holder, z), frame("RailR", holder, z) }
	local dashes = {}
	local ready = label(holder, z, Enum.TextXAlignment.Left)
	ready.Text = "ГОТОВО"
	local count = label(holder, z, Enum.TextXAlignment.Right)
	local timer = frame("Timer", holder, z)
	timer.BackgroundTransparency = 0

	local edgeL, edgeR = 0, 0
	local color = Theme.color.accent
	local started, length = 0, 1

	local function layout()
		local p, s = result.Position, result.Size
		local x, y, w, h = p.X.Offset, p.Y.Offset, s.X.Offset, s.Y.Offset
		local i = TUNING.inset
		for _, e in corners do
			e.bar.Position = UDim2.fromOffset(
				e.c.X == 0 and x - i or x + w + i,
				e.c.Y == 0 and y - i or y + h + i
			)
		end
		-- Направляющие на середине высоты: от головы до уголка.
		for _, d in dashes do
			d:Destroy()
		end
		table.clear(dashes)
		local cy = math.floor(y + h / 2)
		local spans = {
			{ edgeL + TUNING.gap, x - i - TUNING.gap },
			{ x + w + i + TUNING.gap, edgeR - TUNING.gap },
		}
		for side, span in spans do
			local rail = rails[side]
			local len = math.max(0, span[2] - span[1])
			rail.Position = UDim2.fromOffset(span[1], cy)
			rail.Size = UDim2.fromOffset(len, 1)
			local step = TUNING.dash + TUNING.gapDash
			for k = 0, math.floor(len / step) - 1 do
				local d = frame("Dash", rail, z)
				d.Position = UDim2.fromOffset(side == 1 and k * step or len - k * step - TUNING.dash, 0)
				d.Size = UDim2.fromOffset(TUNING.dash, 1)
				d.BackgroundTransparency = 0.35
				d.BackgroundColor3 = color
				table.insert(dashes, d)
			end
			local text = side == 1 and ready or count
			text.Position = UDim2.fromOffset(span[1], cy - 4 - TUNING.text)
			text.Size = UDim2.fromOffset(len, TUNING.text)
			text.Visible = len >= 60
		end
		timer.Position = UDim2.fromOffset(x, y + h + i - TUNING.bar)
	end
	result:GetPropertyChangedSignal("Position"):Connect(layout)
	result:GetPropertyChangedSignal("Size"):Connect(layout)

	RunService.Heartbeat:Connect(function()
		if not holder.Visible then
			return
		end
		local left = math.max(0, length - (os.clock() - started))
		timer.Size = UDim2.fromOffset(math.floor(result.Size.X.Offset * left / length), TUNING.bar)
		count.Text = "В ЗАПАС " .. math.ceil(left)
	end)

	local self = {}

	function self.layout(left, right)
		edgeL, edgeR = left, right
		layout()
	end

	function self.show(c, time)
		color = Theme.Legible(c)
		for _, e in corners do
			e.bar.BackgroundColor3 = color
		end
		for _, d in dashes do
			d.BackgroundColor3 = color
		end
		timer.BackgroundColor3 = color
		started, length = os.clock(), math.max(0.1, time)
		holder.Visible = true
	end

	function self.hide()
		holder.Visible = false
	end

	return self
end

return Tray
