-- Modern Nano Programs: the Nano Programs window (role prk.nano-programs), built for looking
-- nanos up. Toolbar: search (name or nanoline) and school tabs. List view: two-line rows
-- (icon | name over "QL · nano cost · NCU · duration" | running time), grouped by nanoline
-- (strongest first) or sorted, with "Hide outranked nanos" keeping only your best in each
-- line. Right-click a nano for its details: every stat the game sends, its nanoline, and
-- your other nanos in that line. Left-click casts, as in the built-in window (rows are bound
-- to the nano). Running: your own active nanos (effects API) show their time left.
-- Table and Grid views (title menu) are the built-in ones.
--
-- In combat the game pins rows, so new grouping / filtering / sorting shows after combat;
-- searching then dims non-matches instead of hiding them.
pcall(ui.require, "spiritech.modern-common/screenfit") -- keep window positions through fullscreen changes
local Window = ui.require("core.window")
local Security = ui.require("core.security")
local Grid = ui.require("core.icon_grid")
local Table = ui.require("core.table")
local Theme = ui.require("spiritech.modern-common/theme")
local presentation = NanoPresentation
NanoPresentation = nil

local WIDTH, HEIGHT = 700, 500
local MIN_WIDTH, MIN_HEIGHT, MAX_WIDTH, MAX_HEIGHT = 480, 300, 1800, 1400
local DETAILS = 226 -- details column incl. its gap; must match content.xml
local ROW_HEIGHT, HEADER = 32, 20 -- must match row.xml / header.xml
local SIDES = Window.CONTENT_SIDES or 11
local TEXT, DETAIL, IDLE, ACCENT = "#E8ECF1", "#8B95A3", "#A3ADBA", "#4FB3BF"
local SCHOOLS = { "Combat", "Medical", "Protection", "Psi", "Space" }
local SORTS = {
	{ "name", "Name" },
	{ "line", "Nanoline (strongest first)" },
	{ "nano_cost", "Nano cost (highest first)" },
	{ "ncu_cost", "NCU (highest first)" },
	{ "time", "Duration (longest first)" },
	{ "level", "QL (highest first)" },
}
local STATS = {
	{ "nano_cost", "Nano cost" },
	{ "ncu_cost", "NCU" },
	{ "time", "Duration" },
	{ "radius", "Radius" },
	{ "attack_range", "Attack range" },
	{ "attack_delay", "Attack delay" },
	{ "recharge_delay", "Recharge" },
}

-- Text preferences are stored JSON-quoted; accept both.
local function read_text(key)
	return ((ui.preference.read(key) or ""):gsub('^"(.*)"$', "%1"))
end

local content = ui.load("content.xml")
local search = ui.find(content, "search")
local list_scroll = ui.find(content, "nano_scroll")
local list_host = ui.find(content, "nano_rows")
local table_host = ui.find(content, "nano_list")
local grid_scroll = ui.find(content, "nano_grid_scroll")
local grid = ui.find(content, "nano_grid")
local details_column = ui.find(content, "details_column")
local status = ui.find(content, "status")
local sort_anchor = ui.find(content, "sort_menu")
local school_tabs = {}
for index = 0, #SCHOOLS do school_tabs[index] = ui.find(content, "school_" .. index) end

local view = read_text("modern_nanos_view")
if view ~= "table" and view ~= "grid" then view = "list" end
local grouped = ui.preference.read("modern_nanos_grouped") ~= "false"
local hide_outranked = ui.preference.read("modern_nanos_outranked") == "true"
local sort_mode = "name"
for _, sort in ipairs(SORTS) do
	if read_text("modern_nanos_sort") == sort[1] then sort_mode = sort[1] end
end

local entries = {} -- latest snapshot
local school = 0 -- 0 = all
local terms = {}
local selected -- key of the right-clicked nano
local running = {} -- nano name -> { remaining, permanent, at }
local frame, render
local row_width = 400
local items, views = {}, {} -- current list items and their views
local structure -- key of the list's current structure
local dirty = false -- something changed in combat that needs a rebuild

-- ---------------------------------------------------------------- formatting
local function duration(centiseconds)
	if not centiseconds or centiseconds <= 0 then return "—" end
	local seconds = math.floor(centiseconds / 100)
	if seconds >= 3600 then return string.format("%dh %02dm", seconds // 3600, (seconds // 60) % 60) end
	if seconds >= 60 then
		local rest = seconds % 60
		return rest > 0 and string.format("%dm %02ds", seconds // 60, rest) or string.format("%dm", seconds // 60)
	end
	return seconds .. "s"
end

local function stat_text(entry, id)
	local value = entry[id] or 0
	if id == "time" then return duration(value) end
	if id == "radius" or id == "attack_range" then return value > 0 and (value .. "m") or "—" end
	if id == "attack_delay" or id == "recharge_delay" then return string.format("%.2fs", value / 100) end
	return Theme.thousands(value)
end

local function clock(seconds)
	seconds = math.max(0, math.floor(seconds))
	if seconds >= 3600 then return string.format("%d:%02d:%02d", seconds // 3600, (seconds // 60) % 60, seconds % 60) end
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

local function key_of(entry)
	return entry.name .. "\0" .. entry.level
end

-- Running: time left now for one of your active nanos, or nil.
local function running_text(entry)
	local effect = running[entry.name]
	if not effect then return nil end
	if effect.permanent then return "running" end
	local left = effect.remaining - (ui.time() - effect.at) / 1000
	if left <= 0 then return nil end
	return clock(left)
end

-- ---------------------------------------------------------------- selection of nanos
local function matches(entry)
	if #terms == 0 then return true end
	local name, line = string.lower(entry.name), string.lower(entry.nanoline or "")
	for _, term in ipairs(terms) do
		if not name:find(term, 1, true) and not line:find(term, 1, true) then return false end
	end
	return true
end

local function stronger(a, b)
	if a.stacking_order ~= b.stacking_order then return a.stacking_order > b.stacking_order end
	if a.level ~= b.level then return a.level > b.level end
	return string.lower(a.name) < string.lower(b.name)
end

-- Your best nano in each nanoline (nanos without a line are never outranked).
local function best_by_line()
	local best = {}
	for _, entry in ipairs(entries) do
		local line = entry.nanoline or ""
		if line ~= "" and (not best[line] or stronger(entry, best[line])) then best[line] = entry end
	end
	return best
end

-- Nanos of the chosen school, without outranked ones when hidden. filter: also drop
-- search non-matches.
local function chosen(filter)
	local best = hide_outranked and best_by_line() or nil
	local list, outranked = {}, 0
	for _, entry in ipairs(entries) do
		if school == 0 or entry.school == school then
			local line = entry.nanoline or ""
			if best and line ~= "" and best[line] ~= entry then
				outranked = outranked + 1
			elseif not filter or matches(entry) then
				list[#list + 1] = entry
			end
		end
	end
	return list, outranked
end

local SORT_KEYS = { nano_cost = true, ncu_cost = true, time = true, level = true }
local function sorted(list)
	table.sort(list, function(a, b)
		if sort_mode == "line" then
			local x, y = string.lower(a.nanoline or ""), string.lower(b.nanoline or "")
			if x ~= y then
				if x == "" or y == "" then return y == "" end
				return x < y
			end
			return stronger(a, b)
		end
		if SORT_KEYS[sort_mode] and a[sort_mode] ~= b[sort_mode] then return a[sort_mode] > b[sort_mode] end
		local x, y = string.lower(a.name), string.lower(b.name)
		if x ~= y then return x < y end
		return a.level > b.level
	end)
	return list
end

-- The list: { header = line, count = n } and { entry = nano } items in display order.
local function list_items(list)
	local result = {}
	if not grouped then
		for _, entry in ipairs(sorted(list)) do result[#result + 1] = { entry = entry } end
		return result
	end
	local lines, by_line = {}, {}
	for _, entry in ipairs(list) do
		local line = entry.nanoline or ""
		if not by_line[line] then
			by_line[line] = {}
			lines[#lines + 1] = line
		end
		table.insert(by_line[line], entry)
	end
	table.sort(lines, function(x, y)
		if x == "" or y == "" then return y == "" end
		return string.lower(x) < string.lower(y)
	end)
	for _, line in ipairs(lines) do
		local members = by_line[line]
		table.sort(members, stronger)
		result[#result + 1] = { header = line ~= "" and line or "Other", count = #members }
		for _, entry in ipairs(members) do result[#result + 1] = { entry = entry } end
	end
	return result
end

-- ---------------------------------------------------------------- details
local detail = {
	hint = ui.find(content, "detail_hint"),
	body = ui.find(content, "detail_body"),
	name = ui.find(content, "detail_name"),
	sub = ui.find(content, "detail_sub"),
	running = ui.find(content, "detail_running"),
	line = ui.find(content, "detail_line"),
	rank = ui.find(content, "detail_rank"),
	line_host = ui.find(content, "detail_line_rows"),
	stats = {},
	line_rows = {},
}
for _, stat in ipairs(STATS) do
	local root = ui.find(ui.load("stat.xml"), "stat")
	ui.text(ui.find(root, "label"), stat[2])
	ui.add(ui.find(content, "detail_stats"), root)
	detail.stats[stat[1]] = ui.find(root, "value")
end

local function find_selected()
	if not selected then return nil end
	for _, entry in ipairs(entries) do
		if key_of(entry) == selected then return entry end
	end
end

local function show_details()
	local entry = find_selected()
	ui.visible(detail.hint, entry == nil)
	ui.visible(detail.body, entry ~= nil)
	if not entry then return end
	ui.text(detail.name, entry.name)
	ui.text(detail.sub, "QL " .. entry.level .. "  ·  " .. (SCHOOLS[entry.school] or "Unknown school"))
	local time = running_text(entry)
	ui.visible(detail.running, time ~= nil)
	ui.text(detail.running, time == "running" and "Running on you" or time and ("Running on you · " .. time .. " left") or "")
	for _, stat in ipairs(STATS) do ui.text(detail.stats[stat[1]], stat_text(entry, stat[1])) end
	local line = entry.nanoline or ""
	ui.text(detail.line, line ~= "" and line or "—")
	local members = {}
	if line ~= "" then
		for _, other in ipairs(entries) do
			if other.nanoline == line then members[#members + 1] = other end
		end
		table.sort(members, stronger)
	end
	local rank = 0
	for index, other in ipairs(members) do
		if other == entry then rank = index end
	end
	ui.text(detail.rank, line == "" and "" or #members <= 1 and "Your only nano in this line"
		or rank == 1 and ("Your best of " .. #members .. " in this line")
		or ("Outranked: #" .. rank .. " of your " .. #members .. " in this line"))
	if ui.in_combat() then return end
	for _, root in ipairs(detail.line_rows) do ui.destroy(root) end
	detail.line_rows = {}
	if #members > 1 then
		for _, other in ipairs(members) do
			local root = ui.find(ui.load("stat.xml"), "stat")
			local label, value = ui.find(root, "label"), ui.find(root, "value")
			ui.text(label, other.name)
			ui.text(value, "QL " .. other.level)
			local current = other == entry
			ui.text_color(label, current and TEXT or DETAIL)
			ui.text_color(value, current and ACCENT or DETAIL)
			ui.font_size(value, 11)
			ui.add(detail.line_host, root)
			detail.line_rows[#detail.line_rows + 1] = root
		end
	end
end

-- ---------------------------------------------------------------- list rows
local function make_row(entry)
	local root = ui.find(ui.load("row.xml"), "nano_row")
	local row = { root = root, icon = ui.find(root, "icon"), name = ui.find(root, "name"),
		detail = ui.find(root, "detail"), running = ui.find(root, "running") }
	ui.on_pointer_release(root, "right", function()
		if row.entry then
			selected = key_of(row.entry)
			render()
		end
	end)
	return row
end

local function make_header(item)
	local root = ui.find(ui.load("header.xml"), "nano_header")
	ui.text(ui.find(root, "label"), string.upper(item.header))
	ui.text(ui.find(root, "count"), tostring(item.count))
	return { root = root, header = true }
end

local function fill_row(row, entry, dim)
	row.entry = entry
	if row.resource ~= entry.icon then
		ui.icon(row.icon, entry.icon)
		row.resource = entry.icon
	end
	ui.content(row.icon, true)
	ui.text(row.name, entry.name)
	ui.text(row.detail, "QL " .. entry.level .. "  ·  " .. Theme.thousands(entry.nano_cost) .. " nano  ·  "
		.. entry.ncu_cost .. " NCU  ·  " .. duration(entry.time))
	ui.text(row.running, running_text(entry) or "")
	ui.selected(row.root, key_of(entry) == selected)
	ui.opacity(row.root, dim and 0.4 or 1)
	ui.tooltip(row.root, entry.nanoline ~= "" and (entry.name .. "\n" .. entry.nanoline) or entry.name)
end

local function show_list()
	local locked = ui.in_combat()
	local list, outranked = chosen(not locked)
	local wanted = list_items(list)
	local key_parts = {}
	for index, item in ipairs(wanted) do
		key_parts[index] = item.header and ("#" .. item.header .. item.count) or key_of(item.entry)
	end
	local key = table.concat(key_parts, "\n")
	if key ~= structure then
		if locked then
			dirty = true -- can't rebuild rows in combat: refresh what's there
		else
			for _, item in ipairs(views) do ui.destroy(item.root) end
			views = {}
			for _, item in ipairs(wanted) do
				local made = item.header and make_header(item) or make_row(item.entry)
				ui.add(list_host, made.root)
				views[#views + 1] = made
			end
			items, structure = wanted, key
		end
	end
	if not locked then
		for index, item in ipairs(items) do
			local made = views[index]
			ui.limits(made.root, row_width, made.header and HEADER or ROW_HEIGHT, row_width, made.header and HEADER or ROW_HEIGHT)
			ui.size(made.root, row_width, made.header and HEADER or ROW_HEIGHT)
			if item.entry then
				fill_row(made, item.entry, false)
				ui.bind(made.root, item.entry.token)
				ui.action(made.root, "game.nano_programs.cast", item.entry.token, "left")
			end
		end
	else
		-- Combat: same rows, newest facts by name / QL; dim search non-matches.
		local by_key = {}
		for _, entry in ipairs(entries) do by_key[key_of(entry)] = entry end
		for _, made in ipairs(views) do
			if made.entry then
				local entry = by_key[key_of(made.entry)] or made.entry
				fill_row(made, entry, not matches(entry))
			end
		end
	end
	local shown = 0
	for _, item in ipairs(items) do if item.entry then shown = shown + 1 end end
	local text = shown .. " of " .. #entries .. " nanos"
	if outranked > 0 then text = text .. "  ·  " .. outranked .. " outranked hidden" end
	ui.text(status, text)
end

-- Running times tick once a second.
local last_tick = 0
ui.on_update(function(now)
	if now - last_tick < 1000 or view ~= "list" then return end
	last_tick = now
	for _, made in ipairs(views) do
		if made.entry then ui.text(made.running, running_text(made.entry) or "") end
	end
	local entry = find_selected()
	if entry then
		local time = running_text(entry)
		ui.visible(detail.running, time ~= nil)
		ui.text(detail.running, time == "running" and "Running on you" or time and ("Running on you · " .. time .. " left") or "")
	end
end)

-- ---------------------------------------------------------------- table / grid (built-in)
local table_matches = {}
local list_table = Table.create({
	host = table_host,
	column_menu = true,
	columns = presentation.columns,
	default_sort = "name",
	row_template = "table_row_silent.xml",
	binding = function(entry) return entry.token end,
	tooltip = function(entry) return entry.name end,
	opacity = function(entry) return table_matches[entry.token] and 1 or 0.4 end,
	action = "game.nano_programs.cast",
	group = function(left, right)
		if table_matches[left.token] == table_matches[right.token] then return 0 end
		return table_matches[left.token] and -1 or 1
	end,
	tie = presentation.tie,
	changed = function() if render then render() end end,
})
local cells = Grid.cells({
	host = grid,
	template = "slot.xml",
	binding = function(entry) return entry.token end,
	icon = function(entry) return entry.icon end,
	tooltip = function(entry) return entry.name end,
	opacity = function(entry) return table_matches[entry.token] and 1 or 0.4 end,
	action = "game.nano_programs.cast",
})
local CELL, SPACING = 38, 4

local function show_table_or_grid()
	local list, outranked = chosen(false)
	table_matches = {}
	for _, entry in ipairs(list) do table_matches[entry.token] = matches(entry) end
	local ordered = list_table:order(list)
	if view == "table" then
		list_table:show(list, ordered)
	else
		cells:show(ordered, #ordered)
	end
	local text = #list .. " of " .. #entries .. " nanos"
	if outranked > 0 then text = text .. "  ·  " .. outranked .. " outranked hidden" end
	ui.text(status, text)
end

-- ---------------------------------------------------------------- render
render = function()
	for index, tab in pairs(school_tabs) do
		ui.text_color(tab, index == school and ACCENT or IDLE)
	end
	if view == "list" then
		show_list()
		show_details()
	else
		show_table_or_grid()
	end
end

local function apply_view()
	ui.visible(list_scroll, view == "list")
	ui.visible(details_column, view == "list")
	ui.visible(table_host, view == "table")
	ui.visible(grid_scroll, view == "grid")
end

local function layout(window, width, height)
	ui.limits(window.root, MIN_WIDTH, MIN_HEIGHT, MAX_WIDTH, MAX_HEIGHT)
	width = math.max(MIN_WIDTH, math.min(MAX_WIDTH, width or WIDTH))
	height = math.max(MIN_HEIGHT, math.min(MAX_HEIGHT, height or HEIGHT))
	ui.request_size(window.root, width, height)
	window:fit_title(width, true)
	window:fit_content(width, height)
	local inner = width - SIDES
	row_width = math.max(200, inner - DETAILS - 10) -- 8px scrollbar + 2
	local columns = math.max(1, math.floor((inner - 12 + SPACING) / (CELL + SPACING)))
	ui.size(grid, columns * (CELL + SPACING) - SPACING, -1)
	list_table.width = inner - 8
	render()
end

-- ---------------------------------------------------------------- menus
local VIEW_ITEMS = { { "list", "List view" }, { "table", "Table view" }, { "grid", "Grid view" } }
local GROUP_ITEM, OUTRANKED_ITEM = 4, 5

local function set_view(value)
	if ui.in_combat() or value == view then return end
	list_table:clear()
	cells:clear()
	view = value
	ui.preference.write("modern_nanos_view", view, "text")
	ui.publish("view_mode", view == "grid" and "grid" or "list")
	for index, item in ipairs(VIEW_ITEMS) do ui.menu.checked(frame.icon, index, item[1] == view) end
	apply_view()
	frame:resize(ui.chosen_width(frame.root), ui.chosen_height(frame.root))
end

ui.menu.style(sort_anchor, "context")
for index, sort in ipairs(SORTS) do
	ui.menu.add(sort_anchor, sort[2], sort[1] == sort_mode, function()
		sort_mode = sort[1]
		ui.preference.write("modern_nanos_sort", sort_mode, "text")
		for other, entry in ipairs(SORTS) do ui.menu.checked(sort_anchor, other, entry[1] == sort_mode) end
		render()
	end)
end

local menu = {}
for _, item in ipairs(VIEW_ITEMS) do
	menu[#menu + 1] = { label = item[2], checked = view == item[1], invoke = function() set_view(item[1]) end }
end
menu[GROUP_ITEM] = {
	label = "Group by nanoline",
	checked = grouped,
	invoke = function()
		grouped = not grouped
		ui.preference.write("modern_nanos_grouped", tostring(grouped), "bool")
		ui.menu.checked(frame.icon, GROUP_ITEM, grouped)
		render()
	end,
}
menu[OUTRANKED_ITEM] = {
	label = "Hide outranked nanos",
	checked = hide_outranked,
	invoke = function()
		hide_outranked = not hide_outranked
		ui.preference.write("modern_nanos_outranked", tostring(hide_outranked), "bool")
		ui.menu.checked(frame.icon, OUTRANKED_ITEM, hide_outranked)
		render()
	end,
}
menu[#menu + 1] = { label = "Sort list (when not grouped)", submenu = sort_anchor }
menu[#menu + 1] = { label = "Table sort", submenu = list_table:sort_menu(content) }

frame = Window.create({
	template = Theme.WINDOW_TEMPLATE,
	title = "Nano Programs",
	content = content,
	x = 10,
	y = 174,
	width = WIDTH,
	height = HEIGHT,
	layout = layout,
	menu = menu,
})
ui.root(frame.root)
apply_view()
ui.publish("view_mode", view == "grid" and "grid" or "list")

ui.on_text_changed(search, function(text)
	terms = {}
	for term in string.gmatch(string.lower(text or ""), "%S+") do terms[#terms + 1] = term end
	render()
end)
for index, tab in pairs(school_tabs) do
	ui.on_click(tab, function()
		school = (school == index or index == 0) and 0 or index
		render()
	end)
end

-- Your running nanos (self effects), for the running times.
game.effects.subscribe("self", function(update)
	local data = update and update.data
	if not data then return end
	local now = ui.time()
	for _, owner in ipairs(data) do
		if owner.known then
			running = {}
			for _, effect in ipairs(owner.effects or {}) do
				if effect.name and not effect.hidden then
					running[effect.name] = { remaining = effect.remaining or 0, permanent = effect.permanent, at = now }
				end
			end
		end
	end
	if view == "list" then render() end
end)

function nano_programs_apply(snapshot)
	entries = snapshot
	render()
end

Security.on_unlock(function()
	apply_view()
	if dirty then
		dirty = false
		structure = nil
	end
	render()
end)
