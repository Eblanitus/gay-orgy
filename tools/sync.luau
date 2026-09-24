-- Синхронизация place/game.rbxl <-> src/.
--   lune run tools/sync extract  — достать скрипты из place/game.rbxl в src/
--   lune run tools/sync build    — записать скрипты из src/ обратно в place/game.rbxl
--
-- Путь файла повторяет иерархию в игре: src/ServerScriptService/Grid.luau.
-- Суффикс задаёт класс: .server.luau — Script, .client.luau — LocalScript, .luau — ModuleScript.
-- Простые инстансы без свойств (RemoteEvent'ы в ReplicatedStorage.Remotes, SoundGroup'ы) лежат
-- как Имя.model.json с {"className": ...} — тот же формат читает Rojo. Remotes выгружаются из
-- места целиком; остальные .model.json заводятся руками в src/, extract их не трогает.
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local PLACE = "place/game.rbxl"
local SRC = "src"

local REMOTES = { "ReplicatedStorage", "Remotes" }
local MODEL = ".model.json"

local SUFFIX = { Script = ".server.luau", LocalScript = ".client.luau", ModuleScript = ".luau" }

local function pathOf(inst)
	local parts = {}
	local p = inst
	while p and p.ClassName ~= "DataModel" do
		table.insert(parts, 1, p.Name)
		p = p.Parent
	end
	return parts
end

local function parseFile(rel)
	for class, suffix in { Script = ".server.luau", LocalScript = ".client.luau" } do
		if rel:sub(-#suffix) == suffix then
			return class, rel:sub(1, -#suffix - 1)
		end
	end
	return "ModuleScript", rel:sub(1, -6)
end

local function listFiles(dir, prefix, out)
	for _, name in fs.readDir(dir) do
		local full = dir .. "/" .. name
		local rel = prefix and (prefix .. "/" .. name) or name
		if fs.isDir(full) then
			listFiles(full, rel, out)
		elseif name:sub(-5) == ".luau" or name:sub(-#MODEL) == MODEL then
			table.insert(out, rel)
		end
	end
	return out
end

local function scripts(game)
	local list = {}
	for _, d in game:GetDescendants() do
		if SUFFIX[d.ClassName] then
			table.insert(list, d)
		end
	end
	return list
end

local function extract()
	local game = roblox.deserializePlace(fs.readFile(PLACE))
	-- Стираются только выгружаемые файлы: .luau и Remotes. Ручные .model.json остаются.
	local function clean(dir)
		for _, name in fs.readDir(dir) do
			local full = dir .. "/" .. name
			if fs.isDir(full) then
				clean(full)
			elseif name:sub(-5) == ".luau" then
				fs.removeFile(full)
			end
		end
	end
	if fs.isDir(SRC) then
		clean(SRC)
		local remotesDir = SRC .. "/" .. table.concat(REMOTES, "/")
		if fs.isDir(remotesDir) then
			fs.removeDir(remotesDir)
		end
	end
	local seen = {}
	for _, s in scripts(game) do
		local parts = pathOf(s)
		local rel = table.concat(parts, "/") .. SUFFIX[s.ClassName]
		assert(not seen[rel], "два скрипта с одинаковым путём: " .. rel)
		seen[rel] = true
		fs.writeDir(SRC .. "/" .. table.concat(parts, "/", 1, #parts - 1))
		fs.writeFile(SRC .. "/" .. rel, s.Source)
	end
	local remotes = game:GetService(REMOTES[1]):FindFirstChild(REMOTES[2])
	local dir = SRC .. "/" .. table.concat(REMOTES, "/")
	fs.writeDir(dir)
	for _, r in remotes:GetChildren() do
		fs.writeFile(dir .. "/" .. r.Name .. MODEL, serde.encode("json", { className = r.ClassName }, true) .. "\n")
	end
	print("extract: скриптов", #scripts(game), "remote'ов", #remotes:GetChildren())
end

local function build()
	local game = roblox.deserializePlace(fs.readFile(PLACE))
	local wanted = {}
	local remotesDir = table.concat(REMOTES, "/") .. "/"
	local remotes = game:GetService(REMOTES[1]):FindFirstChild(REMOTES[2])
	local wantedRemotes = {}
	for _, rel in listFiles(SRC, nil, {}) do
		if rel:sub(-#MODEL) == MODEL then
			local parts = string.split(rel:sub(1, -#MODEL - 1), "/")
			local parent = game:GetService(parts[1])
			for i = 2, #parts - 1 do
				parent = assert(parent:FindFirstChild(parts[i]), "нет родителя для " .. rel)
			end
			local name = parts[#parts]
			local class = serde.decode("json", fs.readFile(SRC .. "/" .. rel)).className
			local inst = parent:FindFirstChild(name)
			if inst and inst.ClassName ~= class then
				inst:Destroy()
				inst = nil
			end
			if not inst then
				inst = roblox.Instance.new(class)
				inst.Name = name
				inst.Parent = parent
				print("новый:", rel)
			end
			wantedRemotes[inst] = true
			continue
		end
		local class, path = parseFile(rel)
		local parts = string.split(path, "/")
		local parent = game:GetService(parts[1])
		for i = 2, #parts - 1 do
			local child = parent:FindFirstChild(parts[i])
			if not child then
				child = roblox.Instance.new("Folder")
				child.Name = parts[i]
				child.Parent = parent
			end
			parent = child
		end
		local name = parts[#parts]
		local inst
		for _, c in parent:GetChildren() do
			if c.Name == name and c.ClassName == class then
				inst = c
			end
		end
		if not inst then
			inst = roblox.Instance.new(class)
			inst.Name = name
			inst.Parent = parent
			print("новый:", rel)
		end
		inst.Source = fs.readFile(SRC .. "/" .. rel)
		wanted[inst] = true
	end
	for _, s in scripts(game) do
		if not wanted[s] then
			print("удалён:", table.concat(pathOf(s), "/"))
			s:Destroy()
		end
	end
	for _, r in remotes:GetChildren() do
		if not wantedRemotes[r] then
			print("удалён:", remotesDir .. r.Name)
			r:Destroy()
		end
	end
	fs.writeFile(PLACE, roblox.serializePlace(game))
	print("build: скриптов", #scripts(game))
end

local cmd = process.args[1]
if cmd == "extract" then
	extract()
elseif cmd == "build" then
	build()
else
	print("использование: lune run tools/sync extract|build")
	process.exit(1)
end
