-- Modern Mission Terminal: one package, two roles (prk.mission-terminal + prk.info), so the
-- Info window can hand the reward items of an inspected mission to the terminal list
-- through the package's shared storage.
-- A provider must mount its window during init, but no API names the role. Each role gets
-- its own native adapter, so this asks the Mission Terminal adapter: a direct Lua call of
-- accept is always refused with false (never sends anything) in the terminal instance and
-- fails ("Unknown ... capability") in the Info instance. Result logged to storage "role_log_<role>".
pcall(ui.require, "spiritech.modern-common/screenfit") -- keep window positions through fullscreen changes

local PENDING_MS = 4000 -- an Info page opening this soon after a row click belongs to it

-- ------------------------------------------------------------------ info relay
local function split(text, separator)
	local fields = {}
	for field in (text .. separator):gmatch("(.-)" .. separator) do fields[#fields + 1] = field end
	return fields
end

local function relay(facts)
	local pending = split(ui.storage.read("inspect_pending") or "", "\t")
	local key, stamp = pending[1], tonumber(pending[2])
	if not key or key == "" or not stamp or ui.time() - stamp > PENDING_MS then return end
	ui.storage.write("inspect_pending", "") -- one page per click (item pages opened later are not rewards)

	local names, seen, log = {}, {}, { "key " .. key }
	for index, fact in ipairs(facts) do
		log[#log + 1] = string.format("%d %s indent=%d item=%s link=%s doc=%s row=%s value=%s | %s", index,
			tostring(fact.tone), fact.indent or 0, tostring(fact.item), tostring(fact.link), tostring(fact.document),
			tostring(fact.row), tostring(fact.value), tostring(fact.text):gsub("\n", "\\n"))
		local name = fact.item and tostring(fact.text or ""):gsub("[\t\n]", " ") or ""
		if name ~= "" and not seen[name] then
			seen[name] = true
			names[#names + 1] = name
		end
	end
	ui.storage.write("info_log", table.concat(log, "\n"))

	-- Keep only this offer set's entries (key = session:generation:index).
	local set = key:match("^(.*):%d+$") or key
	local lines = {}
	for _, line in ipairs(split(ui.storage.read("rewards") or "", "\n")) do
		local other = line:match("^([^\t]*)")
		if other and other ~= key and (other:match("^(.*):%d+$") or other) == set then lines[#lines + 1] = line end
	end
	lines[#lines + 1] = key .. (#names > 0 and ("\t" .. table.concat(names, "\t")) or "")
	ui.storage.write("rewards", table.concat(lines, "\n"))
end

-- ------------------------------------------------------------------ role
local ok, result = pcall(game.mission_terminal.accept, 0)
local role = (ok and result == false) and "terminal" or "info"
pcall(ui.storage.write, "role_log_" .. role, string.format("accept probe ok=%s result=%s -> %s",
	tostring(ok), tostring(result), role))

if role == "info" then
	BUILD_INFO()
	local stock_show = info_show
	info_show = function(token, facts, cells, refresh)
		stock_show(token, facts, cells, refresh)
		if not refresh then pcall(relay, facts) end
	end
else
	BUILD_TERMINAL()
end
