-- Offline harness: runs the client's real Core package plus one of our packages with a mocked
-- native host (__prk_host), so package logic can be exercised without the game.
-- Usage: lua tools/mock_host.lua <package dir> <scenario.lua> [client dir]
-- The scenario runs after the package's scripts, with MOCK (see below) and the package globals.
local package_dir, scenario = arg[1], arg[2]
local client = arg[3] or (os.getenv("HOME") .. "/Games/spiritech/client")
local core = client .. "/UI/Packages/Core/"
local repo = package_dir:match("^(.*)/packages/") or "."

MOCK = { storage = {}, preferences = {}, calls = {}, now = 1000000, subscriptions = {}, log = false,
	updates = nil, views = 0, numbers = 100 }
local found = {}
local function new_view()
	MOCK.views = MOCK.views + 1
	return MOCK.views
end
local function host(name, ...)
	local a = { ... }
	MOCK.calls[name] = (MOCK.calls[name] or 0) + 1
	if MOCK.log then print("host", name, ...) end
	if name == "xml.load" or name:match("^ui%.create") then return new_view() end
	if name == "ui.find" then
		local key = tostring(a[1]) .. "/" .. tostring(a[2])
		found[key] = found[key] or new_view()
		return found[key]
	end
	if name == "ui.time" then MOCK.now = MOCK.now + 16; return MOCK.now end
	if name == "ui.storage.read" then return MOCK.storage[a[1]] or "" end
	if name == "ui.storage.write" then MOCK.storage[a[1]] = a[2]; return end
	if name == "ui.storage.count" then local n = 0; for _ in pairs(MOCK.storage) do n = n + 1 end; return n end
	if name == "ui.preference.read" or name == "ui.preference.read_array_encoded" then return MOCK.preferences[a[1]] or "" end
	if name == "ui.preference.write" then MOCK.preferences[a[1]] = a[2]; return end
	if name == "ui.on_update" then MOCK.updates = a[1]; return end
	if name == "ui.stop_updates" then MOCK.updates = nil; return end
	if name == "game.character.subscribe" then MOCK.subscriptions[#MOCK.subscriptions + 1] = a[3]; return 1 end
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
for _, path in ipairs(scripts(package_dir)) do dofile(path) end

function MOCK.tick(ms)
	MOCK.now = MOCK.now + (ms or 16)
	if MOCK.updates then MOCK.updates(MOCK.now) end
end
function MOCK.character(me)
	for _, callback in ipairs(MOCK.subscriptions) do callback("update", me) end
end
dofile(scenario)
