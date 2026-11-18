-- Modern NCU: slim list of running nano programs (role prk.ncu).
-- Two-line rows: icon | name / "NCU cost · time left" in smaller, dimmer text. No header; the title shows
-- NCU used / maximum. Rows keep the built-in bindings, so right-click still cancels and
-- Shift-click still inspects (also in combat). Biggest NCU users at the top, so the
-- programs worth cancelling to free space are first.
pcall(ui.require, "spiritech.modern-common/screenfit") -- keep window positions through fullscreen changes
local Window = ui.require("core.window")
local Security = ui.require("core.security")
local Table = ui.require("core.table")
local Presentation = ui.require("ncu.presentation")
local Theme = ui.require("spiritech.modern-common/theme")

local WIDTH = 270
local MIN_WIDTH, MAX_WIDTH = 200, 600
local ROW_HEIGHT = 32 -- two lines
local ICON_SIZE = 26
local ICON_TOP = 4 -- px from the row's top edge; nudge if icons sit high or low
local ICON_LEFT = 4 -- px nudge to the right
local MAX_ROWS = 30
local PADDING = 2 -- below the last row
local SOON = 60 -- seconds; time left turns amber below this

local NAME_COLORS = {
	Hostile = "#FF7A70",
	Team = "#8FD6A0",
}
local DETAIL_COLOR = "#A3ADBA"
-- Background bar showing time left (full = just cast). Kept faint so the text stays readable.
local BAR_COLORS = {
	normal = "#4D2A8A99",
	soon = "#4DF0C060",
	Hostile = "#4DB23A3A",
}
local SOON_COLOR = "#F0C060"

local content = ui.load("content.xml")
local list = ui.find(content, "ncu_list")
local measure = ui.find(content, "ncu_measure")
local bar_layer = ui.find(content, "ncu_bars")
local bars = {}
local row_width = WIDTH
local entries = {}
local name_width = 150 -- current width of the name column, set in layout

-- Long names are cut to fit their column with a trailing ellipsis.
local fitted = {}
local function fit_name(name)
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

local function lower(value)
	return type(value) == "string" and string.lower(value) or value
end

local function time_left(entry)
	return entry.permanent and "Permanent" or Presentation.time(entry)
end

local function soon(entry)
	return not entry.permanent and entry.seconds < SOON
end

-- Plain two-line text; also the fallback if rich text is unavailable.
local function plain(entry)
	return fit_name(entry.name) .. "\n" .. entry.ncu_cost .. " NCU  ·  " .. time_left(entry)
end

local function escape(text)
	return (text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

-- Line 1: name (tinted by type). Line 2: NCU cost and time left, dimmer.
local function rich(entry)
	return string.format('<font color=%s>%s</font><br><font color=%s>%d NCU  ·  </font><font color=%s>%s</font>',
		NAME_COLORS[entry.effect_type] or Theme.color.text, escape(fit_name(entry.name)),
		DETAIL_COLOR, entry.ncu_cost,
		soon(entry) and SOON_COLOR or DETAIL_COLOR, time_left(entry))
end

local columns = {
	{
		id = "icon", title = "", width = ICON_SIZE, minimum = ICON_SIZE, kind = "icon", resizable = false,
		icon = function(entry) return entry.icon end,
	},
	{
		-- One cell for both lines. Sorted by NCU cost (the id is only the sort key).
		id = "program", title = "Program", width = 150, minimum = 60,
		value = function(entry) return entry.ncu_cost end,
		text = plain,
	},
}

local tooltip = function(entry)
	return Presentation.tooltip(entry, false)
end

local table_view = Table.create({
	stable = true,
	collection = "ncu_list",
	host = list,
	style = "inset",
	columns = columns,
	row_height = ROW_HEIGHT,
	default_sort = "program",
	fit_columns = true,
	preference = "modern_ncu_list", -- own saved widths, not the built-in table's
	binding = function(entry) return entry.token end,
	tooltip = tooltip,
	opacity = Presentation.flash,
	button = "right",
	action = "game.ncu.cancel",
	tie = Presentation.tie,
})
-- Flat look: no header row; always sorted by NCU cost, biggest first (ties by name).
ui.visible(ui.find(table_view.root, "table_header_scroll"), false)
table_view.sort, table_view.descending = "program", true

-- After the table writes its rows: bigger icons, and rich text for the two lines.
-- Runs after every update (also in combat, where the game may add rows itself).
local function style_row(row)
	local icon, text = row.cells[1], row.cells[2]
	if icon and icon.icon then
		-- The shared template pins its icon at 15px; widen the limits, then centre it in the row.
		ui.limits(icon.icon, ICON_SIZE, ICON_SIZE, ICON_SIZE, ICON_SIZE)
		ui.size(icon.icon, ICON_SIZE, ICON_SIZE)
		-- Centring by layout left the artwork ~3px high (the slot draws it from its top edge),
		-- so place it explicitly: ICON_TOP lines the artwork up with the bar's middle.
		ui.align(icon.icon, "start", "start")
		ui.borders(icon.icon, ICON_LEFT, ICON_TOP, 0, 0)
		if icon.space then
			ui.size(icon.space, ICON_SIZE + ICON_LEFT, ROW_HEIGHT)
		end
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

-- Lines the background bars up with the rows the table is currently showing.
local function draw_bars()
	local count = 0
	for index, row in ipairs(table_view.rows) do
		local entry = row.cells[2] and row.cells[2].entry
		local left = entry and not entry.permanent and entry.total_time > 0 and (1 - Presentation.elapsed(entry)) or 0
		-- Bars start where the text column starts, so the icon stays a separate block.
		local bar_left = ICON_SIZE + table_view.style.gap
		local width = math.floor((row_width - bar_left) * math.max(0, math.min(1, left)) + 0.5)
		if width > 0 then
			count = count + 1
			local bar = bars[count]
			if not bar then
				local loaded = ui.load("bar.xml")
				ui.add(bar_layer, loaded)
				bar = ui.find(loaded, "ncu_bar")
				ui.align(bar, "start", "start")
				bars[count] = bar
			end
			local color = entry.effect_type == "Hostile" and BAR_COLORS.Hostile
				or soon(entry) and BAR_COLORS.soon or BAR_COLORS.normal
			ui.fill_color(bar, color)
			ui.size(bar, width, ROW_HEIGHT - 2)
			ui.place(bar, bar_left, (index - 1) * ROW_HEIGHT + 1)
			ui.visible(bar, true)
		end
	end
	for index = count + 1, #bars do
		ui.visible(bars[index], false)
	end
end

local function show()
	table_view:show(entries)
	for _, row in ipairs(table_view.rows) do style_row(row) end
	draw_bars()
	if table_view.prototype then style_row(table_view.prototype) end
end

local frame
frame = Window.create({
	template = Theme.WINDOW_TEMPLATE,
	title = "NCU --/--",
	content = content,
	x = 10,
	y = 174,
	width = WIDTH,
	height = Window.CONTENT_ENDS or 33,
	layout = function(window, width)
		-- Width is yours to drag; height always fits the rows exactly.
		local ends = Window.CONTENT_ENDS or 33
		local rows = math.max(1, math.min(MAX_ROWS, #entries))
		local height = ends + rows * ROW_HEIGHT + PADDING
		ui.limits(window.root, MIN_WIDTH, height, MAX_WIDTH, height)
		width = math.max(MIN_WIDTH, math.min(MAX_WIDTH, width))
		window:fit_title(width, true)
		ui.request_size(window.root, width, height)
		window:fit_content(width, height)
		-- The name column takes whatever the fixed columns leave (12 = scrollbar).
		local inner = width - Window.CONTENT_SIDES
		local fixed = 12 + #columns * table_view.style.gap
		for index = 1, #columns do
			if columns[index].id ~= "program" then fixed = fixed + columns[index].width end
		end
		table_view.preferred_widths[2] = math.max(columns[2].minimum, inner - fixed)
		name_width = table_view.preferred_widths[2]
		row_width = inner - 12 -- rows stop at the (covered) scrollbar
		table_view:set_width(inner)
		show()
	end,
})
ui.root(frame.root)

Security.on_unlock(function()
	frame:resize(ui.chosen_width(frame.root), ui.chosen_height(frame.root))
end)

function ncu_apply(snapshot, usage)
	entries = {}
	for _, entry in ipairs(snapshot) do
		if not entry.hidden then
			entries[#entries + 1] = entry
		end
	end
	if usage then
		local used = usage.used_known and tostring(usage.used) or "--"
		local maximum = usage.maximum_known and tostring(usage.maximum) or "--"
		ui.text(ui.find(frame.root, "window_title"), "NCU  " .. used .. " / " .. maximum)
	end
	frame:resize(ui.chosen_width(frame.root), ui.chosen_height(frame.root))
end
