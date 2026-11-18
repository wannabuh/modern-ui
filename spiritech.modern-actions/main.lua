-- Modern Actions (role prk.actions): the Actions window as a plain flat list.
--
--   [ic] Fling Shot
--   [ic] Burst          (dimmed while locked / unavailable)
--   [ic] Aimed Shot
--
-- Every action in your Actions grid order; left-click uses it. Rows keep their order and
-- bindings in combat (the game locks them). Cooldown timers live in the Control Center's
-- Cooldowns window (Actions → Cooldowns Window), fed by the shortcut bars.
-- Compact (title menu, or right-click any row) hides the title bar; an 8px grip stays.
pcall(ui.require, "spiritech.modern-common/screenfit") -- keep window positions through fullscreen changes
local Window = ui.require("core.window")
local Security = ui.require("core.security")
local Theme = ui.require("spiritech.modern-common/theme")

local WIDTH, HEIGHT = 200, 220
local MIN_WIDTH, MIN_HEIGHT, MAX_WIDTH, MAX_HEIGHT = 150, 50, 600, 1000
local ENDS, COMPACT_ENDS = 33, 17 -- frame chrome; compact shrinks the title bar to 8px
local SCROLLBAR = 8
local LOCKED_OPACITY, MISSING_OPACITY = 0.45, 0.3

local function pref(key, default)
	local value = ui.preference.read("modern_actions_" .. key)
	return value ~= "" and value or default
end
local options = { compact = pref("compact", "false") == "true" }

local content = ui.load("content.xml")
local host = ui.find(content, "all_rows")
local menu_anchor = ui.find(content, "actions_menu")
local measure = ui.find(content, "actions_measure")

local entries, by_token, rows = {}, {}, {}
local name_width = 120
local frame, open_menu

local fitted = {}
local function fit(name)
	local key = name .. "\0" .. name_width
	if fitted[key] then return fitted[key] end
	local function width(text)
		ui.text(measure, text)
		local ok, value = pcall(ui.text_width, measure)
		return ok and value or #text * 6
	end
	local result = name
	if width(name) > name_width then
		local low, high = 0, #name
		while low < high do
			local middle = (low + high + 1) // 2
			if width(name:sub(1, middle) .. "...") <= name_width then low = middle else high = middle - 1 end
		end
		result = name:sub(1, low):gsub("%s+$", "") .. "..."
	end
	fitted[key] = result
	return result
end

local function create_row()
	local loaded = ui.load("row.xml")
	ui.add(host, loaded)
	local view = ui.find(loaded, "action_row") or loaded
	ui.borders(view, 0, 0, 0, 1)
	ui.on_pointer_release(view, "right", function() open_menu() end)
	return { root = view, icon = ui.find(view, "row_icon"), name = ui.find(view, "row_name") }
end

local function set(row, field, value, apply)
	if row[field] ~= value then
		row[field] = value
		apply(value)
	end
end

-- One bound row per action, in the player's grid order. Rebuilt out of combat only.
local function rebuild()
	if ui.in_combat() then return end
	local ordered = {}
	for _, entry in ipairs(entries) do ordered[#ordered + 1] = entry end
	table.sort(ordered, function(a, b)
		if a.slot ~= b.slot then return a.slot < b.slot end
		return a.name < b.name
	end)
	while #rows < #ordered do rows[#rows + 1] = create_row() end
	while #rows > #ordered do
		ui.destroy(rows[#rows].root)
		rows[#rows] = nil
	end
	for index, entry in ipairs(ordered) do
		local row = rows[index]
		if row.token ~= entry.token then
			row.token = entry.token
			ui.bind(row.root, entry.token)
			ui.action(row.root, "game.actions.execute", entry.token, "left")
		end
	end
end

local function present()
	for _, row in ipairs(rows) do
		-- In combat a row keeps its action; it dims further if that action left the snapshot.
		local entry = by_token[row.token]
		if entry then
			local locked = not entry.supported or (entry.seconds or 0) > 0
			set(row, "v_icon", entry.icon, function(v) ui.icon(row.icon, v); ui.content(row.icon, true) end)
			set(row, "v_name", fit(entry.name), function(v) ui.text(row.name, v) end)
			local tip = entry.reason ~= "" and (entry.tooltip .. "\n" .. entry.reason) or entry.tooltip
			set(row, "v_tip", tip, function(v) ui.tooltip(row.root, v) end)
			set(row, "v_alpha", locked and LOCKED_OPACITY or 1, function(v) ui.opacity(row.root, v) end)
		else
			set(row, "v_alpha", MISSING_OPACITY, function(v) ui.opacity(row.root, v) end)
		end
	end
end

local function ends() return options.compact and COMPACT_ENDS or ENDS end

local function layout(window, width, height)
	ui.limits(window.root, MIN_WIDTH, MIN_HEIGHT, MAX_WIDTH, MAX_HEIGHT)
	ui.request_size(window.root, width, height)
	width, height = ui.chosen_width(window.root), ui.chosen_height(window.root)
	window:fit_title(width, not options.compact)
	window:fit_content(width, height + (options.compact and (ENDS - COMPACT_ENDS) or 0))
	name_width = math.max(30, width - Window.CONTENT_SIDES - SCROLLBAR - 3 - 18 - 6 - 6)
	fitted = {}
	for _, row in ipairs(rows) do row.v_name = nil end
	present()
end

frame = Window.create({
	template = Theme.WINDOW_TEMPLATE,
	title = "Actions",
	content = content,
	x = 10,
	y = 174,
	width = WIDTH,
	height = HEIGHT,
	layout = layout,
	menu = false,
})
ui.root(frame.root)
local titlebar = ui.find(frame.root, "window_titlebar")

local function resize()
	frame:resize(ui.chosen_width(frame.root), ui.chosen_height(frame.root))
end

local function apply_compact()
	for _, name in ipairs({ "window_icon_slot", "window_title_tab", "window_tabs", "window_pin", "window_close" }) do
		local view = ui.find(frame.root, name)
		if view then ui.visible(view, not options.compact) end
	end
	local height = options.compact and 8 or 24
	ui.limits(titlebar, 0, height, 4096, height)
	ui.size(titlebar, -1, height)
	ui.tooltip(titlebar, options.compact and "Drag to move · right-click a row for options" or "")
end

-- Options: title menu and every row's right-click (the only way in compact mode;
-- right-clicking the title bar is the game's own pick-up-to-dock gesture).
local build_menu
local function set_option(key, value)
	options[key] = value
	ui.preference.write("modern_actions_" .. key, tostring(value), "bool")
	apply_compact()
	build_menu()
	resize()
end

build_menu = function()
	for _, anchor in ipairs({ frame.icon, menu_anchor }) do
		ui.menu.clear(anchor)
		ui.menu.add(anchor, "Compact", options.compact, function() set_option("compact", not options.compact) end)
		if anchor == frame.icon then
			ui.menu.separator(anchor)
			ui.menu.close(anchor, frame.root)
		end
	end
end

open_menu = function() ui.menu.show(menu_anchor) end

apply_compact()
build_menu()

Security.on_unlock(function()
	rebuild()
	present()
	resize()
end)

function actions_apply(snapshot)
	entries = snapshot or {}
	by_token = {}
	for _, entry in ipairs(entries) do by_token[entry.token] = entry end
	rebuild()
	present()
end
