-- Вкладка «Купить»: окно производителя поверх root
-- Вынесено из CraftingUI.client.luau без изменений кода (задача #240): файл был слишком
-- велик, чтобы агент читал его целиком. deps — локальные основного файла, которые нужны
-- этому куску; возвращается то, что основной файл использует дальше.
return function(deps)
	local Theme = deps.Theme
	local root = deps.root
	local tabFrames = deps.tabFrames
	local ReplicatedStorage = deps.ReplicatedStorage
	local Remotes = deps.Remotes
	local BASE_ORDER = deps.BASE_ORDER
	local Elements = deps.Elements
	local RequestBuyElement = deps.RequestBuyElement
	local inventory = deps.inventory
	local gui = deps.gui
	local InventoryChanged = deps.InventoryChanged

	-- ============ Вкладка "Купить" ============
	-- Производитель — окно во весь экран, как планшет с камерами: сверху только название
	-- и крестик, ниже монитор в тонкой рамке, а на нём один из трёх режимов
	-- (alchemy_td_location_v1.6.md, «Производитель: режимы работы»). Сборка — buildProducer.
	-- Прежний вид — автомат спереди (задачи #201–#202, buildMachineFront) — больше
	-- не собирается: три режима на одной маленькой панели игроки не понимали.
	--
	-- Вкладка лежит прямо на root и сама глухая: закрывает фон окна и его шапку. Движение
	-- окна — барабаны, стрелка, джекпот и отклики — в ProducerShow; оно слушается «Движения».
	local buyFrame = Instance.new("Frame")
	buyFrame.Name = "BuyTab"
	buyFrame.Size = UDim2.new(1, 0, 1, 0)
	buyFrame.BackgroundColor3 = Theme.color.panel
	buyFrame.BackgroundTransparency = 0
	buyFrame.BorderSizePixel = 0
	buyFrame.ClipsDescendants = true
	buyFrame.ZIndex = 2
	buyFrame.Visible = true
	buyFrame.Parent = root
	tabFrames["Купить"] = buyFrame

	local buyCountLabels = {} -- elementKey -> label, обновляется по InventoryChanged

	-- Всё внутри функции: главный кусок скрипта упёрся в потолок Luau — 200 локальных.
	local function buildMachineFront()
		local Skin = require(script.Parent:WaitForChild("ProducerSkin"))
		local Show = require(script.Parent:WaitForChild("ProducerShow"))
		local RouletteConfig = require(ReplicatedStorage:WaitForChild("RouletteConfig"))
		local UpgraderConfig = require(ReplicatedStorage:WaitForChild("UpgraderConfig"))
		local RequestRouletteSpin = Remotes:WaitForChild("RequestRouletteSpin")
		local RequestUpgrade = Remotes:WaitForChild("RequestUpgrade")

		local MARGIN = 1.04
		-- По этим деталям автомат вписывается в окно: крышки колб сверху, корпус по бокам.
		-- Снизу рисунок обрезан чуть ниже панели с кнопками (деталь PanelFace): лоток выдачи
		-- и подставка во вкладке не нужны. Короб и кабель на стене сзади в кадр не просятся.
		local FRAME_PARTS = { CanCap = true, Cabinet = true, CornerGuard = true }
		local CUT_BELOW = 0.12 -- стадов корпуса под панелью с кнопками

		-- Рисунок автомата. Все детали на слое 1: из равных по ZIndex позже рисуется тот, кто
		-- позже в дереве, поэтому детали создаются от дальней к ближней.
		local view = Instance.new("Frame")
		view.Name = "Machine"
		view.Size = UDim2.fromScale(1, 1)
		view.BackgroundTransparency = 1
		view.BorderSizePixel = 0
		view.ZIndex = 1
		view.Parent = buyFrame

		-- Всё, что лежит поверх модели. Пока модели нет (локация ещё не построена), слоя нет тоже.
		local front = Instance.new("Frame")
		front.Name = "Front"
		front.Size = UDim2.fromScale(1, 1)
		front.BackgroundTransparency = 1
		front.ZIndex = 2
		front.Visible = false
		front.Parent = buyFrame

		local source, copy -- copy: Frame с рисунком деталей текущего автомата
		local shapes = {} -- { frame, lo, hi, key } — деталь в осях автомата; key у налитого в колбу
		local shapeOf = {} -- деталь модели -> её запись в shapes
		local shares = {} -- elementKey -> доля налитого в колбе, 0..1
		local lo, hi -- рамка автомата по FRAME_PARTS в его осях
		local cut -- высота обрезки рисунка в осях автомата: ниже неё ничего не рисуется

		local function make(className, name, parent, z)
			local inst = Instance.new(className)
			inst.Name = name
			inst.BorderSizePixel = 0
			inst.BackgroundTransparency = 1
			inst.ZIndex = z
			inst.Parent = parent
			return inst
		end

		local function text(parent, name, str, z)
			local l = make("TextLabel", name, parent, z or 3)
			l.FontFace = Theme.font.strong
			l.TextColor3 = Theme.color.ink
			l.TextScaled = true
			l.Text = str
			local limit = Instance.new("UITextSizeConstraint")
			limit.MinTextSize = 6
			limit.Parent = l
			return l
		end

		-- Клавиша экрана: тёмная, как кнопки самого автомата, без твинов наведения.
		local function key(parent, name, str)
			local b = make("TextButton", name, parent, 3)
			b.BackgroundTransparency = 0
			b.AutoButtonColor = true
			b.FontFace = Theme.font.strong
			b.TextScaled = true
			b.TextColor3 = Color3.new(1, 1, 1)
			b.Text = str
			Theme.Corner(b, Theme.radius.mark)
			local limit = Instance.new("UITextSizeConstraint")
			limit.MinTextSize = 6
			limit.Parent = b
			local pad = Instance.new("UIPadding")
			pad.PaddingLeft = UDim.new(0, 3)
			pad.PaddingRight = UDim.new(0, 3)
			pad.Parent = b
			return b
		end

		-- Неоновая полоса автомата (деталь LogoPlate) с его именем.
		local logo = text(front, "Logo", "ПРОИЗВОДИТЕЛЬ ЭЛЕМЕНТОВ", 2)

		-- Светлый экран автомата (деталь Panel): на нём рулетка и апгрейдер, на нём же их показ.
		local screen = make("Frame", "Screen", front, 2)
		screen.BackgroundTransparency = 0
		Theme.Corner(screen, Theme.radius.mark)

		-- Цена покупки: одна строка на экране. Числа из Elements — те же, по которым платит сервер.
		local priceLine
		do
			local costs, parts, same = {}, {}, true
			for _, k in BASE_ORDER do
				costs[#costs + 1] = Elements[k].cost
				parts[#parts + 1] = Elements[k].name .. " " .. Elements[k].cost
				same = same and Elements[k].cost == costs[1]
			end
			priceLine = text(screen, "Price", same and ("ЦВЕТНАЯ КНОПКА ВНИЗУ — ЭЛЕМЕНТ ЗА " .. costs[1])
				or Theme.Caps(table.concat(parts, " · ")))
		end

		-- Кнопки покупки лежат на цветных кнопках рисунка (их рисует build по кнопкам модели),
		-- кнопка — только место нажатия поверх.
		local buyButtons = {}
		for _, k in BASE_ORDER do
			local b = make("TextButton", "Buy" .. k, front, 2)
			b.AutoButtonColor = false
			b.Text = ""
			b.BackgroundColor3 = Color3.new(1, 1, 1)
			Theme.Corner(b, Theme.radius.mark)
			b.MouseEnter:Connect(function()
				b.BackgroundTransparency = 0.8
			end)
			b.MouseLeave:Connect(function()
				b.BackgroundTransparency = 1
			end)
			b.MouseButton1Click:Connect(function()
				RequestBuyElement:FireServer(k)
			end)
			buyButtons[k] = b

			-- Запас элемента — число прямо на его колбе.
			local count = text(front, "Count" .. k, tostring(inventory[k] or 0), 2)
			count.TextColor3 = Color3.new(1, 1, 1)
			count.TextStrokeTransparency = 0.2
			buyCountLabels[k] = count
		end

		-- ============ Рулетка ============
		-- Второй режим (alchemy_td_location_v1.6.md, «Производитель: режимы работы»): случайный
		-- элемент из четырёх. Потолок прокруток и цена — из RouletteConfig, по нему платит сервер.
		local roulette = { count = 1, buttons = {} }
		roulette.name = text(screen, "RouletteName", "РУЛЕТКА")
		roulette.name.TextXAlignment = Enum.TextXAlignment.Left
		roulette.price = text(screen, "RoulettePrice", "")
		roulette.spin = key(screen, "Spin", "+")
		for n = 1, RouletteConfig.MAX_SPINS do
			local b = key(screen, "Spins" .. n, tostring(n))
			b.MouseButton1Click:Connect(function()
				roulette.count = n
				roulette.refresh()
			end)
			roulette.buttons[n] = b
		end
		roulette.spin.MouseButton1Click:Connect(function()
			-- Сколько прокруток и хватает ли материи — решает сервер; здесь только просьба.
			RequestRouletteSpin:FireServer(roulette.count)
		end)

		-- ============ Апгрейдер ============
		-- Третий режим: элемент вперёд по своей чистокровной ветке. Ветки и шансы — из
		-- UpgraderConfig, по нему сервер и разыгрывает попытку.
		local up = { moves = {}, index = 1 }
		up.src = key(screen, "Source", "")
		up.arrow = text(screen, "Arrow", "→")
		up.dst = key(screen, "Target", "")
		up.go = key(screen, "Upgrade", "+")

		-- 50, 25, 12.5, 6.25 — без лишних нулей и без округления до вранья.
		local function percent(chance)
			local s = string.format("%.2f", chance * 100)
			s = s:gsub("0+$", ""):gsub("%.$", "")
			return s .. "%"
		end

		function up.rebuild(counts)
			local keep = up.moves[up.index]
			up.moves = {}
			for _, spine in UpgraderConfig.SPINES do
				for _, k in spine do
					if (counts[k] or 0) > 0 then
						for _, target in UpgraderConfig.Targets(k) do
							up.moves[#up.moves + 1] = { from = k, to = target.key, chance = target.chance }
						end
					end
				end
			end
			-- Выбор игрока переживает пополнение сумки: иначе каждая покупка сбрасывала бы его.
			up.index = 1
			if keep then
				for i, move in up.moves do
					if move.from == keep.from and move.to == keep.to then
						up.index = i
						break
					end
				end
			end
		end

		-- Кнопка «откуда» перебирает элементы, «куда» — цели внутри выбранного элемента.
		up.src.MouseButton1Click:Connect(function()
			if #up.moves == 0 then
				return
			end
			local from = up.moves[up.index].from
			for step = 1, #up.moves do
				local i = (up.index + step - 1) % #up.moves + 1
				if up.moves[i].from ~= from then
					up.index = i
					break
				end
			end
			up.refresh()
		end)
		up.dst.MouseButton1Click:Connect(function()
			if #up.moves == 0 then
				return
			end
			local from = up.moves[up.index].from
			local nextIndex = up.index + 1
			if not up.moves[nextIndex] or up.moves[nextIndex].from ~= from then
				nextIndex = up.index
				while up.moves[nextIndex - 1] and up.moves[nextIndex - 1].from == from do
					nextIndex -= 1
				end
			end
			up.index = nextIndex
			up.refresh()
		end)
		up.go.MouseButton1Click:Connect(function()
			local pick = up.moves[up.index]
			if pick then
				-- Ветку, шанс и наличие элемента проверяет сервер; здесь только просьба.
				RequestUpgrade:FireServer(pick.from, pick.to)
			end
		end)

		-- ============ Рисунок автомата ============
		local function findSource()
			local location = workspace:FindFirstChild("Location")
			return (location and location:FindFirstChild("ElementProducer", true))
				or workspace:FindFirstChild("ElementProducer", true)
		end

		-- Коробка детали в осях автомата: лицевая сторона смотрит в −X, верх — +Y, ширина — вдоль Z.
		local function bounds(part, pivot)
			local half = part.Size / 2
			local a = Vector3.new(math.huge, math.huge, math.huge)
			local b = -a
			for _, sx in { -1, 1 } do
				for _, sy in { -1, 1 } do
					for _, sz in { -1, 1 } do
						local p = pivot:PointToObjectSpace(part.CFrame:PointToWorldSpace(half * Vector3.new(sx, sy, sz)))
						a = a:Min(p)
						b = b:Max(p)
					end
				end
			end
			return a, b
		end

		-- Локация строится под забег: рисунок снимается при открытии окна и заново — если
		-- автомат в мире сменился.
		local function build()
			local found = findSource()
			if not found or (found == source and copy) then
				return
			end
			source = found
			if copy then
				copy:Destroy()
				copy = nil
			end
			shapes, shapeOf = {}, {}
			local pivot = found:GetPivot()
			lo = Vector3.new(math.huge, math.huge, math.huge)
			hi = -lo
			for _, part in found:GetDescendants() do
				if part:IsA("BasePart") then
					local a, b = bounds(part, pivot)
					if FRAME_PARTS[part.Name] then
						lo = lo:Min(a)
						hi = hi:Max(b)
					end
					-- Невидимое в модели невидимо и на рисунке.
					if part.Transparency < 1 then
						local rec = { part = part, lo = a, hi = b, key = part.Name:match("^Reagent(%a+)$") }
						shapes[#shapes + 1] = rec
						shapeOf[part] = rec
					end
				end
			end
			if lo.X == math.huge then
				return
			end
			local face = source:FindFirstChild("PanelFace", true)
			cut = face and shapeOf[face] and shapeOf[face].lo.Y - CUT_BELOW or lo.Y
			lo = Vector3.new(lo.X, cut, lo.Z)
			-- Ближняя к игроку грань детали — меньший X: дальние детали рисуются первыми.
			table.sort(shapes, function(a, b)
				return a.lo.X > b.lo.X
			end)
			copy = make("Frame", "Parts", view, 1)
			copy.Size = UDim2.fromScale(1, 1)
			for _, rec in shapes do
				local f = make("Frame", rec.part.Name, copy, 1)
				f.BackgroundColor3 = rec.part.Color
				f.BackgroundTransparency = rec.part.Transparency
				rec.frame = f
			end
		end

		-- Сколько налито в колбе — запас этого элемента: полна при Skin.CANISTER_FULL штуках.
		local function fill(counts)
			for _, k in BASE_ORDER do
				shares[k] = math.clamp((counts[k] or 0) / Skin.CANISTER_FULL, 0, 1)
			end
		end

		-- Вид спереди без перспективы: автомат вписан в окно по FRAME_PARTS.
		local scale, ox, oy -- пикселей на стад; где в окне точка автомата Z = 0, Y = 0
		local function fit()
			local w, h = view.AbsoluteSize.X, view.AbsoluteSize.Y
			scale = math.min(w / (hi.Z - lo.Z), h / (hi.Y - lo.Y)) / MARGIN
			ox = w / 2 - (lo.Z + hi.Z) / 2 * scale
			oy = h / 2 + (lo.Y + hi.Y) / 2 * scale
		end

		-- Место коробки в окне: левый верхний угол и размер.
		local function toScreen(a, b)
			return Vector2.new(ox + a.Z * scale, oy - b.Y * scale), Vector2.new((b.Z - a.Z) * scale, (b.Y - a.Y) * scale)
		end

		local function rect(part)
			local rec = shapeOf[part]
			return toScreen(rec.lo, rec.hi)
		end

		-- Деталь автомата по имени, если она есть и видна.
		local function detail(name)
			local part = source and source:FindFirstChild(name, true)
			return part and shapeOf[part] and part
		end

		local function place(inst, x, y, w, h)
			inst.Position = UDim2.fromOffset(math.floor(x + 0.5), math.floor(y + 0.5))
			inst.Size = UDim2.fromOffset(math.max(0, math.floor(w + 0.5)), math.max(0, math.floor(h + 0.5)))
		end

		local function textMax(inst, size)
			inst:FindFirstChildOfClass("UITextSizeConstraint").MaxTextSize = math.max(6, math.floor(size))
		end

		local function layout()
			local w, h = view.AbsoluteSize.X, view.AbsoluteSize.Y
			if not copy or w < 40 or h < 40 then
				return
			end
			fit()
			for _, rec in shapes do
				local a, b = rec.lo, rec.hi
				local shown = b.Y > cut
				if rec.key then
					-- Налитое укорачивается от дна, а не сжимается к середине.
					local share = shares[rec.key] or 0
					b = Vector3.new(b.X, a.Y + (b.Y - a.Y) * share, b.Z)
					shown = shown and share > 0
				end
				a = Vector3.new(a.X, math.max(a.Y, cut), a.Z)
				rec.frame.Visible = shown
				local p, s = toScreen(a, b)
				place(rec.frame, p.X, p.Y, s.X, s.Y)
			end
			local panel = detail("Panel")
			if not panel then
				return
			end
			local pPos, pSize = rect(panel)
			local pps = scale
			place(screen, pPos.X, pPos.Y, pSize.X, pSize.Y)

			local plate = detail("LogoPlate")
			logo.Visible = plate ~= nil
			if plate then
				local p, s = rect(plate)
				place(logo, p.X, p.Y, s.X, s.Y)
				textMax(logo, s.Y * 0.7)
			end

			for _, k in BASE_ORDER do
				local plus = detail("Button" .. k)
				buyButtons[k].Visible = plus ~= nil
				if plus then
					-- Место нажатия шире самого плюса: палец на телефоне больше плюса на экране.
					local p, s = rect(plus)
					local c = p + s / 2
					local bw, bh = pps * 0.72, pps * 0.5
					place(buyButtons[k], c.X - bw / 2, c.Y - bh / 2, bw, bh)
				end
				local glass = detail("Canister" .. k)
				buyCountLabels[k].Visible = glass ~= nil
				if glass then
					local p, s = rect(glass)
					place(buyCountLabels[k], p.X, p.Y + s.Y / 2 - pps * 0.2, s.X, pps * 0.4)
					textMax(buyCountLabels[k], pps * 0.34)
				end
			end

			-- Экран: строка цены и два режима под ней.
			local W, H = pSize.X, pSize.Y
			local pad = math.max(3, math.floor(H * 0.06))
			local gap = math.max(2, math.floor(H * 0.035))
			local inner = H - pad * 2 - gap * 2
			local h1 = inner * 0.2
			local h2 = (inner - h1) / 2
			local y2 = pad + h1 + gap
			local y3 = y2 + h2 + gap
			local right = W - pad

			place(priceLine, pad, pad, W - pad * 2, h1)
			textMax(priceLine, h1 * 0.85)

			-- Рулетка, справа налево: плюс, цена, кнопки числа прокруток, имя.
			local x = right - h2
			place(roulette.spin, x, y2, h2, h2)
			x -= gap + h2 * 1.2
			place(roulette.price, x, y2, h2 * 1.2, h2)
			for n = RouletteConfig.MAX_SPINS, 1, -1 do
				x -= gap + h2 * 0.9
				place(roulette.buttons[n], x, y2, h2 * 0.9, h2)
			end
			place(roulette.name, pad, y2, x - gap - pad, h2)

			-- Апгрейдер: что вложить → что получить с шансом, плюс.
			place(up.go, right - h2, y3, h2, h2)
			local rest = right - h2 - gap - pad
			if up.moves[up.index] then
				local arrowW = h2 * 0.6
				local srcW = (rest - arrowW - gap * 2) * 0.42
				place(up.src, pad, y3, srcW, h2)
				place(up.arrow, pad + srcW + gap, y3, arrowW, h2)
				place(up.dst, pad + srcW + gap * 2 + arrowW, y3, rest - arrowW - gap * 2 - srcW, h2)
			else
				place(up.src, pad, y3, rest, h2)
			end

			for _, inst in { roulette.name, roulette.price, roulette.spin, up.src, up.arrow, up.dst, up.go } do
				textMax(inst, h2 * 0.55)
			end
			for _, b in roulette.buttons do
				textMax(b, h2 * 0.55)
			end
			textMax(roulette.spin, h2 * 0.8)
			textMax(up.go, h2 * 0.8)
		end

		local skin = Skin.Read()

		function roulette.refresh()
			roulette.price.Text = tostring(RouletteConfig.TotalCost(roulette.count))
			for n, b in roulette.buttons do
				local chosen = n == roulette.count
				b.BackgroundColor3 = chosen and skin.logo or skin.dark
				b.TextColor3 = chosen and Theme.color.ink or Color3.new(1, 1, 1)
			end
		end

		function up.refresh()
			local pick = up.moves[up.index]
			-- Кнопка без действия — декорация: когда апгрейдить нечего, цели и плюса нет.
			up.arrow.Visible = pick ~= nil
			up.dst.Visible = pick ~= nil
			up.go.Visible = pick ~= nil
			if pick then
				up.src.Text = Theme.Caps(Elements[pick.from].name)
				up.dst.Text = Theme.Caps(Elements[pick.to].name) .. " " .. percent(pick.chance)
			else
				up.src.Text = "АПГРЕЙДЕР: НЕТ ЭЛЕМЕНТА"
			end
			layout()
		end

		-- Цвета сняты с деталей самой модели (ProducerSkin), не подобраны на глаз.
		local function paint()
			skin = Skin.Read()
			screen.BackgroundColor3 = skin.screen
			for _, b in { roulette.spin, up.src, up.dst, up.go } do
				b.BackgroundColor3 = skin.dark
			end
			roulette.spin.TextColor3 = Theme.color.action
			up.go.TextColor3 = Theme.color.action
			roulette.refresh()
		end

		local function open()
			if not gui.Enabled or not buyFrame.Visible then
				return
			end
			build()
			front.Visible = copy ~= nil
			if copy then
				paint()
				fill(inventory)
				layout()
			end
		end

		gui:GetPropertyChangedSignal("Enabled"):Connect(open)
		buyFrame:GetPropertyChangedSignal("Visible"):Connect(open)
		buyFrame:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
		-- Обработчик ниже по скрипту обновляет inventory позже этого, поэтому запас берётся
		-- из самого события, а не из таблицы.
		InventoryChanged.OnClientEvent:Connect(function(counts)
			fill(counts)
			up.rebuild(counts)
			up.refresh()
		end)

		-- Показ розыгрыша на светлом экране автомата. Сервер уже разыграл итог и держит замок,
		-- пока идёт показ; элементы придут в инвентарь после него. Код показа — в ProducerShow.
		Remotes:WaitForChild("RouletteShow").OnClientEvent:Connect(function(results, time)
			Show.Roulette(screen, Skin.Read(), results, time or RouletteConfig.SHOW_TIME)
		end)
		Remotes:WaitForChild("UpgradeShow").OnClientEvent:Connect(function(result)
			Show.Upgrade(screen, Skin.Read(), result, UpgraderConfig.SHOW_TIME)
		end)

		up.rebuild(inventory)
		paint()
		up.refresh()
		open()
	end

	return {
		-- inventory основной файл заменяет целиком на каждое InventoryChanged (не правит
		-- на месте: производитель сравнивает прежнюю таблицу с новой). Сюда новая
		-- приходит через этот сеттер — ровно в тот же миг, что и раньше.
		setInventory = function(value)
			inventory = value
		end,
		buyFrame = buyFrame,
		buyCountLabels = buyCountLabels,
	}
end
