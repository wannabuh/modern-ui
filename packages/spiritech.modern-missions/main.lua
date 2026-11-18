-- Modern Missions: flat missions window (role prk.missions).
--   List (default): two-line rows like the NCU list — icon, mission name, then a grey line
--     with "● On map" for the mission uploaded to your map and the time left (amber under
--     15 min, red under 5). Soonest deadline first, the mapped mission on top of ties.
--     A faint bar behind each row drains as the deadline approaches (the game doesn't say a
--     mission's full duration, so the bar starts full when this window first sees it).
--   Grid (title menu → List Mode off): crisp 38px icons.
-- The window fits its missions exactly. Clicking, dragging and inspecting stay native.
pcall(ui.require, "spiritech.modern-common/screenfit") -- keep window positions through fullscreen changes
local Window = ui.require("core.window")
local Grid = ui.require("core.icon_grid")
local Table = ui.require("core.table")
local Theme = ui.require("spiritech.modern-common/theme")

local WIDTH = 280
local ROW, ICON, ICON_LEFT, ICON_TOP = 32, 26, 2, 5 -- as in the NCU list
local CELL, SPACING = 38, 2
local ENDS = 33 -- shared frame chrome (Core window CONTENT_ENDS)
local SOON, URGENT = 15, 5 -- minutes
local MAP_COLOR, TIME_COLOR, SOON_COLOR, URGENT_COLOR = "#4FB3BF", "#A3ADBA", "#F0C060", "#FF7A70"
local BAR_COLORS = { normal = "#4D2A8A99", soon = "#4DF0C060", urgent = "#4DB23A3A" }

local content = ui.load("content.xml")
local grid = ui.find(content, "mission_grid")
local grid_scroll = ui.find(content, "mission_grid_scroll")
local list = ui.find(content, "mission_list")
local cover = ui.find(content, "mission_cover")
local empty = ui.find(content, "mission_empty")
local measure = ui.find(content, "mission_measure")
local bar_layer = ui.find(content, "mission_bars")
local entries, capacity = {}, 1
local stored = ui.preference.read("listview_config.listview_mode")
local mode = stored == "false" and "grid" or "list"
local sizing = Grid.create(CELL, SPACING, 60)
ui.grid_columns(grid, sizing.maximum)
local frame, populate
local name_width, row_width = 200, WIDTH

-- ------------------------------------------------------------------ text
local function clock(entry)
	return string.format("%d:%02d", math.floor(entry.minutes / 60), entry.minutes % 60)
end

local function time_color(entry)
	if not entry.timed then return TIME_COLOR end
	if entry.minutes < URGENT then return URGENT_COLOR end
	if entry.minutes < SOON then return SOON_COLOR end
	return TIME_COLOR
end

local fitted = {}
local function fit(name)
	local room = name_width - 6
	local key = name .. "\0" .. room
	if fitted[key] then return fitted[key] end
	local function width(text)
		ui.text(measure, text)
		return ui.text_width(measure)
	end
	local result = name
	if width(name) > room then
		local low, high = 0, #name
		while low < high do
			local middle = math.floor((low + high + 1) / 2)
			if width(name:sub(1, middle) .. "...") <= room then low = middle else high = middle - 1 end
		end
		result = name:sub(1, low):gsub("%s+$", "") .. "..."
	end
	fitted[key] = result
	return result
end

local function detail_parts(entry)
	local parts = {}
	if entry.selected then parts[#parts + 1] = { "● On map", MAP_COLOR } end
	parts[#parts + 1] = entry.timed and { clock(entry) .. " left", time_color(entry) } or { "No time limit", TIME_COLOR }
	return parts
end

local function plain(entry)
	local texts = {}
	for _, part in ipairs(detail_parts(entry)) do texts[#texts + 1] = part[1] end
	return fit(entry.name) .. "\n" .. table.concat(texts, "  ·  ")
end

local function escape(text)
	return (text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

local function rich(entry)
	local pieces = {}
	for index, part in ipairs(detail_parts(entry)) do
		if index > 1 then pieces[#pieces + 1] = "<font color=#A3ADBA>  ·  </font>" end
		pieces[#pieces + 1] = string.format("<font color=%s>%s</font>", part[2], escape(part[1]))
	end
	return string.format("<font color=%s>%s</font><br>%s", Theme.color.text, escape(fit(entry.name)), table.concat(pieces))
end

-- ------------------------------------------------------------------ order
-- Soonest deadline first; the mission on your map first among equals; untimed last.
local function ordered(list_entries)
	local copy = {}
	for index, entry in ipairs(list_entries) do copy[index] = { entry = entry, order = index } end
	table.sort(copy, function(a, b)
		local x, y = a.entry, b.entry
		local tx, ty = x.timed and x.minutes or math.huge, y.timed and y.minutes or math.huge
		if tx ~= ty then return tx < ty end
		if x.selected ~= y.selected then return x.selected end
		if x.name ~= y.name then return x.name < y.name end
		return a.order < b.order
	end)
	local result = {}
	for index, item in ipairs(copy) do result[index] = item.entry end
	return result
end

-- ------------------------------------------------------------------ views
local mission_table = Table.create({
	host = list,
	style = "inset",
	row_height = ROW,
	fit_columns = true,
	preference = "modern_missions_list",
	columns = {
		{ id = "icon", title = "", width = ICON + ICON_LEFT, minimum = ICON, kind = "icon", resizable = false,
			icon = function(entry) return entry.icon end },
		{ id = "mission", title = "Mission", width = 200, minimum = 60, text = plain },
	},
	binding = function(entry) return entry.token end,
	tooltip = function(entry) return entry.name end,
	selected = function(entry) return entry.selected end,
})
ui.visible(ui.find(mission_table.root, "table_header_scroll"), false)
mission_table.sort = ""

local cells = Grid.cells({
	host = grid,
	template = "slot.xml",
	binding = function(entry) return entry.token end,
	icon = function(entry) return entry.icon end,
	tooltip = function(entry)
		return entry.name .. "\n" .. (entry.selected and "On map · " or "") .. (entry.timed and (clock(entry) .. " left") or "No time limit")
	end,
	selected = function(entry) return entry.selected end,
	corner = function(entry)
		return entry.timed and entry.minutes < 60 and (entry.minutes .. "m") or ""
	end,
})

local function style_row(row)
	local icon, text = row.cells[1], row.cells[2]
	if icon and icon.icon then
		ui.limits(icon.icon, ICON, ICON, ICON, ICON)
		ui.size(icon.icon, ICON, ICON)
		ui.align(icon.icon, "start", "start")
		ui.borders(icon.icon, ICON_LEFT, ICON_TOP, 0, 0)
		if icon.space then ui.size(icon.space, ICON + ICON_LEFT, ROW) end
	end
	if text and text.value then
		ui.font_size(text.value, 12)
		local entry = text.entry
		if entry then
			local markup = rich(entry)
			if text.rich ~= markup or text.rich_source ~= text.text then
				pcall(ui.aoml, text.value, "", markup, false)
				text.rich, text.rich_source = markup, text.text
			end
		end
	end
end

-- Time-left bars. The full duration isn't known, so each mission's longest seen time left
-- (this session) counts as "full".
local longest = {} -- mission name -> minutes
local bars = {}
local function draw_bars(shown)
	local count = 0
	if mode == "list" then
		local bar_left = ICON + ICON_LEFT + mission_table.style.gap
		for index, entry in ipairs(shown) do
			if entry.timed then
				local full = longest[entry.name] or entry.minutes
				local fraction = full > 0 and math.max(0, math.min(1, entry.minutes / full)) or 0
				local width = math.floor((row_width - bar_left) * fraction + 0.5)
				if width > 0 then
					count = count + 1
					local bar = bars[count]
					if not bar then
						local loaded = ui.load("bar.xml")
						ui.add(bar_layer, loaded)
						bar = ui.find(loaded, "mission_bar") or loaded
						ui.align(bar, "start", "start")
						bars[count] = bar
					end
					local color = entry.minutes < URGENT and BAR_COLORS.urgent
						or entry.minutes < SOON and BAR_COLORS.soon or BAR_COLORS.normal
					ui.fill_color(bar, color)
					ui.size(bar, width, ROW - 2)
					ui.place(bar, bar_left, (index - 1) * ROW + 1)
					ui.visible(bar, true)
				end
			end
		end
	end
	for index = count + 1, #bars do ui.visible(bars[index], false) end
end

-- ------------------------------------------------------------------ layout
local function layout(window, width, height)
	if mode == "list" then
		-- Width is yours to drag; height always fits the missions.
		local rows = math.max(1, #entries)
		height = ENDS + rows * ROW + 2
		ui.limits(window.root, 200, height, 700, height)
		width = math.max(200, math.min(700, width))
		window:fit_title(width, true)
		local inner = width - Window.CONTENT_SIDES
		row_width = inner - 12
		mission_table.preferred_widths[2] = math.max(60, inner - 12 - 2 * mission_table.style.gap - ICON - ICON_LEFT)
		name_width = mission_table.preferred_widths[2]
		fitted = {}
		mission_table:set_width(inner)
	else
		local minimum_width, minimum_height = sizing:size(1, 1, false)
		local maximum_width, maximum_height = sizing:size(sizing.maximum, sizing.maximum, true)
		ui.limits(window.root, minimum_width, minimum_height, maximum_width, maximum_height)
		local columns, rows
		width, height, columns, rows = sizing:resolve(width, height, #entries)
		capacity = columns * rows
		ui.size(grid, columns * (CELL + SPACING) - SPACING, -1)
		window:fit_title(width, columns >= 3)
	end
	ui.request_size(window.root, width, height)
	window:fit_content(width, height)
	if populate then populate() end
end

local function set_mode(value)
	mode = value
	cells:clear()
	mission_table:clear()
	ui.visible(grid_scroll, mode == "grid")
	ui.visible(list, mode == "list")
	ui.visible(cover, mode == "list")
	ui.menu.checked(frame.icon, 1, mode == "list")
	ui.preference.write("listview_config.listview_mode", tostring(mode == "list"), "bool")
	ui.publish("view_mode", mode)
	frame:resize(ui.chosen_width(frame.root), ui.chosen_height(frame.root))
end

frame = Window.create({
	template = Theme.WINDOW_TEMPLATE,
	title = "Missions",
	content = content,
	width = WIDTH,
	height = ENDS + ROW + 2,
	layout = layout,
	menu = {
		{
			label = "List Mode",
			checked = mode == "list",
			invoke = function()
				set_mode(mode == "list" and "grid" or "list")
			end,
		},
	},
})
ui.root(frame.root)

populate = function()
	local shown = ordered(entries)
	ui.visible(empty, #entries == 0)
	if mode == "list" then
		mission_table:show(shown, shown)
		for _, row in ipairs(mission_table.rows) do style_row(row) end
	else
		cells:show(shown, capacity)
	end
	draw_bars(shown)
end

function missions_apply(snapshot)
	entries = snapshot
	for _, entry in ipairs(entries) do
		if entry.timed and entry.minutes > (longest[entry.name] or -1) then longest[entry.name] = entry.minutes end
	end
	ui.text(ui.find(frame.root, "window_title"), #entries > 0 and ("Missions  " .. #entries) or "Missions")
	frame:resize(ui.chosen_width(frame.root), ui.chosen_height(frame.root))
end

ui.visible(grid_scroll, mode == "grid")
ui.visible(list, mode == "list")
ui.visible(cover, mode == "list")
ui.publish("view_mode", mode)
populate()
