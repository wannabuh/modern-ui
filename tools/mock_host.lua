-- Offline harness: runs the client's real Core package plus one of our packages with a mocked
-- native host (__prk_host), so package logic can be exercised without the game.
-- Usage: [MOCK_PRELUDE=pre.lua] lua tools/mock_host.lua <package dir> <scenario.lua> [client dir]
-- The scenario runs after the package's scripts, with MOCK (see below) and the package globals.
local package_dir, scenario = arg[1], arg[2]
local client = arg[3] or (os.getenv("HOME") .. "/Games/spiritech/client")
local core = client .. "/UI/Packages/Core/"
local repo = package_dir:match("^(.*)/packages/") or "."

MOCK = { storage = {}, preferences = {}, calls = {}, now = 1000000, subscriptions = {}, log = false,
	updates = nil, views = 0, numbers = 100, handlers = {} }
local found = {}
local function new_view()
	MOCK.views = MOCK.views + 1
	return MOCK.views
end
-- Since API 0.2.0 Core's generated ui.lua calls the host by number. Map each id back to the
-- function that makes the call (read from the client's own ui.lua, so renumbering in a later
-- update needs nothing here), spelled as the older name-based host calls were.
local LEGACY = { ["game.actions.execute"] = "actions.execute", ["ui.load"] = "xml.load", ["ui.on_click"] = "ui.click" }
local host_names = {}
do
	local f = io.open(core .. "ui.lua")
	if f then
		local current
		for line in f:lines() do
			current = line:match("^function ([%w_.]+)%(") or current
			local id = line:match("host%((%d+)")
			if id and current then host_names[tonumber(id)] = LEGACY[current] or current end
		end
		f:close()
	end
end
MOCK.settings = {} -- ui.settings values by key (toggle / number / choice)

local function host(name, ...)
	if type(name) == "number" then name = host_names[name] or ("host#" .. name) end
	local a = { ... }
	MOCK.calls[name] = (MOCK.calls[name] or 0) + 1
	if MOCK.log then print("host", name, ...) end
	-- Input handlers by kind and view, so scenarios can click / type / right-click.
	if name == "ui.click" or name == "ui.on_text_changed" or name == "ui.on_repeat" then
		MOCK.handlers[name] = MOCK.handlers[name] or {}; MOCK.handlers[name][a[1]] = a[2]
	elseif name == "ui.on_pointer_release" then
		MOCK.handlers[name] = MOCK.handlers[name] or {}; MOCK.handlers[name][a[1]] = a[3]
	end
	if MOCK.hook then -- scenarios can watch (and answer) host calls
		local answer = MOCK.hook(name, ...)
		if answer ~= nil then return answer end
	end
	if name == "xml.load" or name == "ui.shared_layout" or name:match("^ui%.create") then return new_view() end
	if name == "ui.find" then
		local key = tostring(a[1]) .. "/" .. tostring(a[2])
		found[key] = found[key] or new_view()
		return found[key]
	end
	if name == "ui.time" then MOCK.now = MOCK.now + 16; return MOCK.now end
	if name == "ui.storage.read" then return MOCK.storage[a[1]] or "" end
	if name == "ui.storage.write" then
		-- Documented limits (docs/lua-api/ui-storage.md); exceeding one raises a Lua error.
		assert(#a[1] >= 1 and #a[1] <= 128, "storage key must be 1..128 bytes: " .. a[1])
		assert(#a[2] <= 4096, "storage value over 4096 bytes (" .. #a[2] .. ") for " .. a[1])
		local value = a[2] ~= "" and a[2] or nil
		if value and MOCK.storage[a[1]] == nil then
			local n = 0; for _ in pairs(MOCK.storage) do n = n + 1 end
			assert(n < 1024, "storage over 1024 keys")
		end
		MOCK.storage[a[1]] = value
		local total = 0; for _, v in pairs(MOCK.storage) do total = total + #v end
		assert(total <= 256 * 1024, "storage over 256 KiB")
		return
	end
	if name == "ui.bind" then MOCK.bindings = MOCK.bindings or {}; MOCK.bindings[a[1]] = a[2]; return end
	if name == "ui.binding" then return (MOCK.bindings or {})[a[1]] or 0 end
	if name == "ui.storage.key" then
		local keys = {}; for k in pairs(MOCK.storage) do keys[#keys + 1] = k end
		table.sort(keys); return keys[a[1]] or ""
	end
	if name == "ui.storage.count" then local n = 0; for _ in pairs(MOCK.storage) do n = n + 1 end; return n end
	if name == "ui.preference.read" or name == "ui.preference.read_array_encoded" then return MOCK.preferences[a[1]] or "" end
	if name == "ui.preference.write" then MOCK.preferences[a[1]] = a[2]; return end
	if name == "ui.settings.toggle" then return MOCK.settings[a[1]] == true end
	if name == "ui.settings.number" then return tonumber(MOCK.settings[a[1]]) or 0 end
	if name == "ui.settings.choice" then return MOCK.settings[a[1]] or "" end
	if name == "ui.settings.on_change" then MOCK.settings_changed = a[1]; return end
	if name == "ui.on_update" then MOCK.updates = a[1]; return end
	if name == "ui.stop_updates" then MOCK.updates = nil; return end
	if name == "game.effects.subscribe" then
		MOCK.effects = MOCK.effects or {}; MOCK.effects[#MOCK.effects + 1] = a[2]; return 100 + #MOCK.effects
	end
	if name == "ui.menu.add" then
		MOCK.menu = MOCK.menu or {}; MOCK.menu[#MOCK.menu + 1] = { label = a[2], checked = a[3], invoke = a[4] }
		return #MOCK.menu
	end
	if name == "ui.menu.checked" then if MOCK.menu and MOCK.menu[a[2]] then MOCK.menu[a[2]].checked = a[3] end; return end
	if name == "ui.icon" then MOCK.icons = MOCK.icons or {}; MOCK.icons[#MOCK.icons + 1] = a[2]; return end
	if name == "game.character.subscribe" then
		MOCK.subscriptions[#MOCK.subscriptions + 1] = a[3]
		MOCK.subscribed = MOCK.subscribed or {}; MOCK.subscribed[#MOCK.subscribed + 1] = { stats = a[2], callback = a[3] }
		return #MOCK.subscriptions
	end
	if name:match("^ui%.is_") then return true end
	if name:match("width") or name:match("height") or name:match("offset") or name:match("^ui%.x$")
		or name:match("^ui%.y$") or name:match("_x$") or name:match("_y$") or name:match("count$") then return MOCK.numbers end
	return nil
end
__prk_host = host

local function lines(path)
	local f = assert(io.open(path)); local t = f:read("a"); f:close(); return t
end
local function scripts(dir)
	local list = {}
	for src in lines(dir .. "/package.xml"):gmatch('<Script src="([^"]+)"') do list[#list + 1] = dir .. "/" .. src end
	return list
end
for _, path in ipairs(scripts(core)) do dofile(path) end
-- library modules: every lua/*.lua of a required library, defined as "<library>/<name>"
for library in lines(package_dir .. "/package.xml"):gmatch('<Requires package="([^"]+)"') do
	local dir = repo .. "/packages/" .. library .. "/lua"
	local p = io.popen('ls "' .. dir .. '"')
	for file in p:lines() do
		local name = file:match("^(.*)%.lua$")
		if name then ui.define(library .. "/" .. name, function() return dofile(dir .. "/" .. file) end) end
	end
	p:close()
end
-- MOCK_PRELUDE=<file>: run before the package's scripts (set MOCK.hook / MOCK.settings for load time).
if os.getenv("MOCK_PRELUDE") then dofile(os.getenv("MOCK_PRELUDE")) end
for _, path in ipairs(scripts(package_dir)) do dofile(path) end

function MOCK.tick(ms)
	MOCK.now = MOCK.now + (ms or 16)
	if MOCK.updates then MOCK.updates(MOCK.now) end
end
function MOCK.character(me)
	for _, callback in ipairs(MOCK.subscriptions) do callback("update", me) end
end
dofile(scenario)
