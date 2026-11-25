-- Modern NCU list: running nano programs as slim two-line rows, shared by Modern NCU (your
-- own programs) and Modern Target NCU (nano / fight target). Load with:
--   local NcuList = ui.require("spiritech.modern-common/ncu_list")
--
-- Row: icon | name (tinted by type: red hostile, green team) / "NCU cost · time left" in
-- smaller, dimmer text (amber under a minute), over a faint bar showing the time left.
-- No header; the sort comes from the title menu: biggest NCU users first, or time left
-- (soonest / longest; permanent programs count as the longest). Rows keep the built-in
-- bindings, so inspecting stays native, and with `action` (your own NCU) right-click still
-- cancels, also in combat. In combat the game pins the row order; a new sort shows after it.
--
--   local list = NcuList.create({
--       action = "game.ncu.cancel" | nil,  -- right-click command (nil: read-only)
--       target = bool,                     -- tooltips as for a target's programs
--       sort_preference = "modern_ncu_sort", table_preference = "modern_ncu_list",
--       empty = "No nanos running",        -- shown in place of rows when there are none
--   })
--   window.content = list.content; menu items: list:menu_items(first_index)
--   list:attach(frame); list:set(entries); list:layout(window, width) from the window's layout
local Security = ui.require("core.security")
local Table = ui.require("core.table")
local Presentation = ui.require("ncu.presentation")
local Theme = ui.require("spiritech.modern-common/theme")

local NcuList = {}
NcuList.__index = NcuList

NcuList.MIN_WIDTH, NcuList.MAX_WIDTH = 200, 600
NcuList.ROW_HEIGHT = 32 -- two lines
local ROW_HEIGHT = NcuList.ROW_HEIGHT
local ICON_SIZE = 26
local ICON_TOP = 4 -- px from the row's top edge; nudge if icons sit high or low
local ICON_LEFT = 4 -- px nudge to the right
NcuList.MAX_ROWS = 30
local PADDING = 2 -- below the last row
local SOON = 60 -- seconds; time left turns amber below this
local SCROLLBAR = 12

local NAME_COLORS = { Hostile = "#FF7A70", Team = "#8FD6A0" }
local DETAIL_COLOR = "#A3ADBA"
-- Background bar showing time left (full = just cast). Kept faint so the text stays readable.
local BAR_COLORS = { normal = "#4D2A8A99", soon = "#4DF0C060", Hostile = "#4DB23A3A" }
local SOON_COLOR = "#F0C060"

-- Sort modes: id, menu label, descending.
NcuList.SORTS = {
	{ "ncu", "Sort by NCU (biggest first)", true },
	{ "time", "Sort by time left (soonest first)", false },
	{ "time_desc", "Sort by time left (longest first)", true },
}

local function escape(text)
	return (text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

local function time_left(entry)
	return entry.permanent and "Permanent" or Presentation.time(entry)
end

local function soon(entry)
	return not entry.permanent and entry.seconds < SOON
end

function NcuList.create(options)
	local self = setmetatable({ options = options, entries = {}, bars = {}, fitted = {} }, NcuList)
	self.sort_mode = "ncu"
	local saved = ui.preference.read(options.sort_preference) or ""
	saved = saved:gsub('^"(.*)"$', "%1")
	for _, sort in ipairs(NcuList.SORTS) do
		if saved == sort[1] then self.sort_mode = sort[1] end
	end
	self.content = ui.load("library://spiritech.modern-common/ncu_list.xml")
	self.list = ui.find(self.content, "ncu_list")
	self.measure = ui.find(self.content, "ncu_measure")
	self.bar_layer = ui.find(self.content, "ncu_bars")
	self.empty = ui.find(self.content, "ncu_empty")
	ui.text(self.empty, options.empty or "")
	self.row_width, self.name_width = 270, 150

	self.columns = {
		{
			id = "icon", title = "", width = ICON_SIZE, minimum = ICON_SIZE, kind = "icon", resizable = false,
			icon = function(entry) return entry.icon end,
		},
		{
			-- One cell for both lines. Sorted by NCU cost or time left (the id is only the sort key).
			id = "program", title = "Program", width = 150, minimum = 60,
			value = function(entry)
				if self.sort_mode == "ncu" then return entry.ncu_cost end
				return entry.permanent and math.huge or math.max(0, entry.seconds)
			end,
			text = function(entry) return self:plain(entry) end,
		},
	}
	self.table = Table.create({
		stable = true,
		collection = "ncu_list",
		host = self.list,
		style = "inset",
		columns = self.columns,
		row_height = ROW_HEIGHT,
		default_sort = "program",
		fit_columns = true,
		preference = options.table_preference, -- own saved widths, not the built-in table's
		binding = function(entry) return entry.token end,
		tooltip = function(entry) return Presentation.tooltip(entry, options.target == true) end,
		opacity = Presentation.flash,
		button = "right",
		action = options.action,
		tie = Presentation.tie,
	})
	-- Flat look: no header row; the sort is chosen from the title menu (ties by name).
	ui.visible(ui.find(self.table.root, "table_header_scroll"), false)
	self.table.sort, self.table.descending = "program", self:descending()
	return self
end

function NcuList:descending()
	for _, sort in ipairs(NcuList.SORTS) do
		if sort[1] == self.sort_mode then return sort[3] end
	end
	return true
end

-- Long names are cut to fit their column with a trailing ellipsis.
function NcuList:fit_name(name)
	local room = self.name_width - 6
	local key = name .. "\0" .. room
	if self.fitted[key] then return self.fitted[key] end
	local measure = self.measure
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
	self.fitted[key] = result
	return result
end

-- Plain two-line text; also the fallback if rich text is unavailable.
function NcuList:plain(entry)
	return self:fit_name(entry.name) .. "\n" .. entry.ncu_cost .. " NCU  ·  " .. time_left(entry)
end

-- Line 1: name (tinted by type). Line 2: NCU cost and time left, dimmer.
function NcuList:rich(entry)
	return string.format('<font color=%s>%s</font><br><font color=%s>%d NCU  ·  </font><font color=%s>%s</font>',
		NAME_COLORS[entry.effect_type] or Theme.color.text, escape(self:fit_name(entry.name)),
		DETAIL_COLOR, entry.ncu_cost,
		soon(entry) and SOON_COLOR or DETAIL_COLOR, time_left(entry))
end

-- After the table writes its rows: bigger icons, and rich text for the two lines.
-- Runs after every update (also in combat, where the game may add rows itself).
function NcuList:style_row(row)
	local icon, text = row.cells[1], row.cells[2]
	if icon and icon.icon then
		-- The shared template pins its icon at 15px; widen the limits, then place it.
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
			local markup = self:rich(entry)
			if text.rich ~= markup or text.rich_source ~= text.text then
				pcall(ui.aoml, text.value, "", markup, false)
				text.rich, text.rich_source = markup, text.text
			end
		end
	end
end

-- Lines the background bars up with the rows the table is currently showing.
function NcuList:draw_bars()
	local count = 0
	for index, row in ipairs(self.table.rows) do
		local entry = row.cells[2] and row.cells[2].entry
		local left = entry and not entry.permanent and entry.total_time > 0 and (1 - Presentation.elapsed(entry)) or 0
		-- Bars start where the text column starts, so the icon stays a separate block.
		local bar_left = ICON_SIZE + self.table.style.gap
		local width = math.floor((self.row_width - bar_left) * math.max(0, math.min(1, left)) + 0.5)
		if width > 0 then
			count = count + 1
			local bar = self.bars[count]
			if not bar then
				local loaded = ui.load("library://spiritech.modern-common/ncu_bar.xml")
				ui.add(self.bar_layer, loaded)
				bar = ui.find(loaded, "ncu_bar")
				ui.align(bar, "start", "start")
				self.bars[count] = bar
			end
			local color = entry.effect_type == "Hostile" and BAR_COLORS.Hostile
				or soon(entry) and BAR_COLORS.soon or BAR_COLORS.normal
			ui.fill_color(bar, color)
			ui.size(bar, width, ROW_HEIGHT - 2)
			ui.place(bar, bar_left, (index - 1) * ROW_HEIGHT + 1)
			ui.visible(bar, true)
		end
	end
	for index = count + 1, #self.bars do
		ui.visible(self.bars[index], false)
	end
end

function NcuList:show()
	self.table:show(self.entries)
	for _, row in ipairs(self.table.rows) do self:style_row(row) end
	self:draw_bars()
	if self.table.prototype then self:style_row(self.table.prototype) end
	ui.visible(self.empty, #self.entries == 0)
end

function NcuList:set(entries)
	self.entries = entries
end

-- Title-menu entries for the sorts; first_index is the first one's position in the menu.
function NcuList:menu_items(first_index)
	self.first_index = first_index or 1
	local items = {}
	for _, sort in ipairs(NcuList.SORTS) do
		items[#items + 1] = { label = sort[2], checked = sort[1] == self.sort_mode, invoke = function() self:set_sort(sort[1]) end }
	end
	return items
end

function NcuList:attach(frame)
	self.frame = frame
	Security.on_unlock(function()
		frame:resize(ui.chosen_width(frame.root), ui.chosen_height(frame.root))
	end)
end

function NcuList:set_sort(mode)
	self.sort_mode = mode
	self.table.descending = self:descending()
	ui.preference.write(self.options.sort_preference, mode, "text")
	if self.frame then
		for index, sort in ipairs(NcuList.SORTS) do
			ui.menu.checked(self.frame.icon, (self.first_index or 1) + index - 1, sort[1] == mode)
		end
	end
	self:show()
end

-- Window layout: width is yours to drag; height always fits the rows exactly (one row's
-- height for the empty note).
function NcuList:layout(window, width)
	local ends = window.CONTENT_ENDS or 33
	local sides = window.CONTENT_SIDES or 11
	local rows = math.max(1, math.min(NcuList.MAX_ROWS, #self.entries))
	local height = ends + rows * ROW_HEIGHT + PADDING
	ui.limits(window.root, NcuList.MIN_WIDTH, height, NcuList.MAX_WIDTH, height)
	width = math.max(NcuList.MIN_WIDTH, math.min(NcuList.MAX_WIDTH, width or NcuList.MIN_WIDTH))
	window:fit_title(width, true)
	ui.request_size(window.root, width, height)
	window:fit_content(width, height)
	-- The name column takes whatever the fixed columns leave.
	local inner = width - sides
	local fixed = SCROLLBAR + #self.columns * self.table.style.gap
	for index = 1, #self.columns do
		if self.columns[index].id ~= "program" then fixed = fixed + self.columns[index].width end
	end
	self.table.preferred_widths[2] = math.max(self.columns[2].minimum, inner - fixed)
	self.name_width = self.table.preferred_widths[2]
	self.row_width = inner - SCROLLBAR -- rows stop at the (covered) scrollbar
	self.table:set_width(inner)
	self:show()
end

return NcuList
