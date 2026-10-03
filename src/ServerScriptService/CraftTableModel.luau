-- Модель лабораторного стола — авторский меш «Алхимический хер.glb» (лежит в корне репозитория).
--
-- Шаблон — ServerStorage.CraftTableTemplate, собран в месте из .glb и уже покрашен по стилю вики:
-- тёмный металл, голубое стекло, без латуни. Import 3D этот файл
-- ломает: в .glb есть анимация, импорт делает из сцены риг и теряет вложенные узлы — половина
-- деталей встаёт в одну точку. Поэтому позиции деталей сняты из самого .glb, а материал — по
-- материалу .glb (атрибут GlbMaterial): Steel_Dark — тёмный, Steel_Cylinder — средний,
-- Brass_Fitting — светлый металл, Glass_Capsule — стекло, Glow_Core — неон (атрибут Accent).
-- Сырой импорт со всеми станциями файла — ServerStorage.Import_AlchemyStations.
--
-- Модуль ставит копию шаблона в стол локации вместо старых деталей: длина как у старого стола,
-- центр над Root, низ на полу. Root и Top стола остаются: на них держатся LabTable, подсказка
-- крафта и полоска прочности. Top становится невидимым и встаёт на столешницу (деталь Worktop).
--
-- Зовётся из Arena.bind (сервер) до того, как тот меряет стол: габарит стола (TableHalf)
-- должен считаться уже по новой модели. Нет шаблона — стол остаётся старым.
local ServerStorage = game:GetService("ServerStorage")

local TEMPLATE_NAME = "CraftTableTemplate"

-- Длина старого стола по X. От неё LabTable.REACH и запрет стройки вокруг стола.
local TABLE_LENGTH = 7

local CraftTableModel = {}

-- Верх детали в мире: у повёрнутой детали Size.Y — не высота.
local function topOf(part)
	local cf, s = part.CFrame, part.Size
	local halfY = (math.abs(cf.RightVector.Y) * s.X + math.abs(cf.UpVector.Y) * s.Y + math.abs(cf.LookVector.Y) * s.Z) / 2
	return part.Position.Y + halfY
end

function CraftTableModel.Apply(craftTable)
	if craftTable:GetAttribute("AuthorModel") then
		return
	end
	local tpl = ServerStorage:FindFirstChild(TEMPLATE_NAME)
	local root = craftTable:FindFirstChild("Root")
	local top = craftTable:FindFirstChild("Top")
	if not (tpl and root and top) then
		warn(if tpl
			then "[Стол] у CraftTable нет Root или Top — модель не поставлена"
			else "[Стол] нет ServerStorage." .. TEMPLATE_NAME .. " — стол старый")
		return
	end

	-- Пол — низ старых деталей стола (ножки). Старые детали после этого не нужны.
	local floorY = math.huge
	for _, c in craftTable:GetChildren() do
		if c ~= root and c ~= top and not c:IsA("BaseScript") then
			for _, p in { c, table.unpack(c:GetDescendants()) } do
				if p:IsA("BasePart") then
					floorY = math.min(floorY, p.Position.Y - p.Size.Y / 2)
				end
			end
			c:Destroy()
		end
	end
	if floorY == math.huge then
		floorY = root.Position.Y - 2.6
	end

	local build = tpl:Clone()
	build.Name = "Build"
	build.Parent = craftTable

	local _, size = build:GetBoundingBox()
	build:ScaleTo(build:GetScale() * TABLE_LENGTH / math.max(size.X, size.Z))
	if size.Z > size.X then
		build:PivotTo(build:GetPivot() * CFrame.Angles(0, math.rad(90), 0))
	end
	local cf, s = build:GetBoundingBox()
	local rootPos = root.Position
	build:PivotTo(build:GetPivot() + Vector3.new(rootPos.X - cf.X, floorY - (cf.Y - s.Y / 2), rootPos.Z - cf.Z))

	-- Top — невидимая столешница: на ней подсказка крафта и полоска прочности.
	local worktop = build:FindFirstChild("Worktop", true)
	local topY = if worktop and worktop:IsA("BasePart")
		then topOf(worktop)
		else floorY + s.Y / 2
	top.Size = Vector3.new(s.X, 0.4, s.Z)
	top.CFrame = CFrame.new(rootPos.X, topY - 0.2, rootPos.Z)
	top.Transparency = 1
	top:SetAttribute("BaseTransparency", 1)

	craftTable:SetAttribute("AuthorModel", true)
	print(("[Стол] новый стол поставлен, размер %s"):format(tostring(s)))
end

return CraftTableModel
