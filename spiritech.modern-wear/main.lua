-- Modern Wear: flat equipment window (role prk.wear).
--   Tabs: Weapons / Clothing / Implants / Social.
--   Resizable: make the window wider to show more pages side by side (1–4). The tab you
--     click becomes the first page shown; every visible page's tab is underlined.
--   Slots: the built-in ones restyled (42px flat cells, 32px icons, small labels when empty;
--     implants tinted blue, social purple); outline turns red when an item is over-equipped
--     (requirements no longer met) and amber while skill-locked.
--   Status line: "1 over-equipped · 1 locked · Ammo 120 / 45".
-- Equipping, drag and drop, tooltips and inspection are unchanged (native).
pcall(ui.require, "spiritech.modern-common/screenfit") -- keep window positions through fullscreen changes
local Window = ui.require("core.window")
local Grid = ui.require("core.icon_grid")
local Theme = ui.require("spiritech.modern-common/theme")

local RED, AMBER, OUTLINE = "#FF7A70", "#F0C060", "#2A3039"
local PAGES = { "weapons", "clothing", "implants", "social" }
local LABELS = { weapons = "Weapons", clothing = "Clothing", implants = "Implants", social = "Social" }
local CELL, GAP = 42, 3
local PAGE_WIDTH = 3 * CELL + 2 * GAP -- 132
local PAGE_HEIGHT = 5 * CELL + 4 * GAP -- 222
local PAGE_SPACING = 14 -- between pages shown side by side
local PADDING = 20 -- left + right around the pages
local TAB_SPACING, TAB_LEFT = 12, 6
local HEIGHT = 33 + 22 + 1 + 6 + PAGE_HEIGHT + 4 + 1 + 18 -- frame + tabs + pages + status
local WEAPON_HANDS = { [6] = true, [8] = true }

local content = ui.load("content.xml")
local placements, views, outlines = {}, {}, {}
local function add(first, last)
	for placement = first, last do
		placements[#placements + 1] = placement
		views[#views + 1] = ui.find(content, "wear_slot_" .. placement)
		outlines[placement] = ui.find(content, "wear_outline_" .. placement)
	end
end
add(1, 15)
add(17, 31)
add(33, 45)
add(49, 63)

local entries, selected = {}, -1
local cells = Grid.cells({
	host = content,
	views = views,
	binding = function(entry) return entry.token end,
	content = function(entry) return entry.occupied end,
	icon = function(entry) return entry.icon end,
	selected = function(entry) return entry.occupied and entry.placement == selected end,
	faded = function(entry) return entry.locked or entry.over_equipped end,
	tint = function(entry) return entry.over_equipped and "#FF0000" or "" end,
	corner = function(entry)
		if entry.rounds ~= "" then return entry.rounds end
		return entry.count > 1 and tostring(entry.count) or ""
	end,
	center = function(entry) return entry.remaining end,
})

-- ------------------------------------------------------------------ tabs / pages
local page_views, tabs = {}, {}
for _, name in ipairs(PAGES) do page_views[name] = ui.find(content, "wear_" .. name) end
local measure = ui.find(content, "wear_measure")

-- Tab widths from the real text width, so none are cut off.
local tabs_width = TAB_LEFT
for _, name in ipairs(PAGES) do
	ui.text(measure, LABELS[name])
	local ok, width = pcall(ui.text_width, measure)
	width = (ok and width and width > 0) and math.ceil(width) or #LABELS[name] * 8
	local cell = ui.find(content, "wear_" .. name .. "_tab_cell")
	ui.limits(cell, width, 22, width, 22)
	ui.size(cell, width, 22)
	tabs[name] = { button = ui.find(content, "wear_" .. name .. "_tab"), line = ui.find(content, "wear_" .. name .. "_tab_line") }
	tabs_width = tabs_width + width + TAB_SPACING
end

local function width_for(count)
	return PADDING + count * PAGE_WIDTH + (count - 1) * PAGE_SPACING + Window.CONTENT_SIDES
end
local MIN_WIDTH = math.max(width_for(1), tabs_width + Window.CONTENT_SIDES)
local MAX_WIDTH = math.max(MIN_WIDTH, width_for(#PAGES))

local saved = ui.preference.read("modern_wear_tab")
local first = 1
for index, name in ipairs(PAGES) do if name == saved then first = index end end
local shown_count = 1
local frame

local function show_pages()
	-- Keep the run of visible pages inside the four.
	local start = math.max(1, math.min(first, #PAGES - shown_count + 1))
	for index, name in ipairs(PAGES) do
		local visible = index >= start and index < start + shown_count
		ui.visible(page_views[name], visible)
		ui.borders(page_views[name], 0, 0, (visible and index < start + shown_count - 1) and PAGE_SPACING or 0, 0)
		ui.text_color(tabs[name].button, visible and Theme.color.text or "#8B95A3")
		ui.visible(tabs[name].line, visible)
	end
end

local function select(index)
	first = index
	ui.preference.write("modern_wear_tab", PAGES[index], "text")
	ui.publish("tab", PAGES[index])
	show_pages()
end
for index, name in ipairs(PAGES) do
	ui.on_click(tabs[name].button, function() select(index) end)
end

frame = Window.create({
	template = Theme.WINDOW_TEMPLATE,
	title = "Wear",
	content = content,
	width = MIN_WIDTH,
	height = HEIGHT,
	x = 218,
	y = 174,
	layout = function(window, width)
		-- Width is free between one and four pages; height is always one page tall.
		width = math.max(MIN_WIDTH, math.min(MAX_WIDTH, width or MIN_WIDTH))
		ui.limits(window.root, MIN_WIDTH, HEIGHT, MAX_WIDTH, HEIGHT)
		ui.request_size(window.root, width, HEIGHT)
		width = ui.chosen_width(window.root) > 0 and ui.chosen_width(window.root) or width
		window:fit_title(width, true)
		window:fit_content(width, HEIGHT)
		local room = width - Window.CONTENT_SIDES - PADDING + PAGE_SPACING
		shown_count = math.max(1, math.min(#PAGES, math.floor(room / (PAGE_WIDTH + PAGE_SPACING))))
		show_pages()
	end,
	on_visibility = function(visible)
		ui.publish("visibility", tostring(visible))
	end,
})
ui.root(frame.root)
show_pages()

-- ------------------------------------------------------------------ data
local status = ui.find(content, "wear_status")

local function present_status()
	local over, locked, ammo = 0, 0, {}
	for _, entry in ipairs(entries) do
		if entry.occupied then
			if entry.over_equipped then over = over + 1 end
			if entry.locked then locked = locked + 1 end
			if WEAPON_HANDS[entry.placement] and entry.rounds ~= "" then ammo[#ammo + 1] = entry.rounds end
		end
		local outline = outlines[entry.placement]
		if outline then
			ui.fill_color(outline, entry.occupied and (entry.over_equipped and RED or entry.locked and AMBER) or OUTLINE)
		end
	end
	local parts = {}
	if over > 0 then parts[#parts + 1] = string.format('<font color=%s>%d over-equipped</font>', RED, over) end
	if locked > 0 then parts[#parts + 1] = string.format('<font color=%s>%d locked</font>', AMBER, locked) end
	if #ammo > 0 then parts[#parts + 1] = "Ammo " .. table.concat(ammo, " / ") end
	local markup = #parts > 0 and table.concat(parts, "  ·  ") or "All equipment OK"
	if not pcall(ui.aoml, status, "", markup, false) then
		ui.text(status, (markup:gsub("<[^>]*>", "")))
	end
end

function wear_apply(snapshot)
	local by_placement = {}
	for _, entry in ipairs(snapshot) do
		by_placement[entry.placement] = entry
	end
	entries = {}
	for index, placement in ipairs(placements) do
		entries[index] = assert(by_placement[placement], "Missing equipment placement")
	end
	cells:show(entries)
	present_status()
end

function wear_selection(value)
	selected = value
	if #entries > 0 then
		cells:show(entries)
	end
end
