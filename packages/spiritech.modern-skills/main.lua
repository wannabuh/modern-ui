-- Modern Skills: the Skills window (role prk.skills) in the flat Modern style.
-- Layout: IP header (remaining points, native status, Suggest IP), then categories | skills |
-- details, then Reset all / Save / Close. Each skill row: star, name (coloured by IP cost
-- tier), unsaved change, value (green buffed / red debuffed), a bar for purchased / cap, - / +.
--
-- Views (title menu, remembered, each with its own size): Full (resizable: the skill list
-- takes the extra width, the body the extra height), Compact (height only), and Favorites
-- (width only; height fits the rows). Views: Full, Compact (categories with the open one's skills under
-- them), and Favorites: a small window with only the starred skills, - / +, IP and Save, to
-- keep open while you play. Star a skill (★ on its row) to add it; the full view also lists
-- them in a Favorites category at the top. "Group favorites by type" (title menu, on by
-- default) shows favorites under category headers, in the Skills window's order: in the
-- Favorites view and in the Favorites category of the full and compact views.
--
-- All skill logic is the built-in package's: the game stages, prices and validates every
-- change (game.skills.propose), and Save / resets / confirmations stay protected native
-- actions bound to their buttons. Nothing here calculates IP.
--
-- Favorites are saved per character in this package's storage: fav/<character> = skill ids.
pcall(ui.require, "spiritech.modern-common/screenfit") -- keep window positions through fullscreen changes
local Window = ui.require("core.window")
local Security = ui.require("core.security")
local Theme = ui.require("spiritech.modern-common/theme")

local WIDTH, HEIGHT = 628, 456 -- content size (full view); must match content.xml
local COMPACT_WIDTH = 220 -- content width (compact); must match compact.xml
local FAVORITES_WIDTH = 268 -- content width (favorites view)
local ROW_WIDTH, COMPACT_ROW_WIDTH = 264, 206
local ROW_HEIGHT, COMPACT_ROW_HEIGHT = 24, 22
local FAVORITES_CHROME = 26 + 4 + 36 + 4 -- favorites view: IP strip, gaps, footer
local BAR_WIDTH = 48 -- must match row.xml
local GROUP_HEADER = 20 -- favorites view category header; must match favorite_header.xml
local SIDEBAR, DETAILS = 150, 190 -- fixed column widths (content.xml)
local HEADER, FOOTER, BODY_GAP = 36, 36, 6 -- full view: IP strip, buttons (incl. gap), gap above body
local SIDES = Window.CONTENT_SIDES or 11
local ENDS = Window.CONTENT_ENDS or 33

local TEXT, IDLE = "#E8ECF1", "#A3ADBA"
local UP, DOWN = "#7FD98A", "#FF7A70"
local STAR_ON, STAR_OFF = "#F0C060", "#3A414C"

local content = ui.load("content.xml")
local expanded = ui.find(content, "skills_content")
local compact = ui.load("compact.xml")
local favorites_view = ui.load("favorites.xml")
local confirmation = ui.load("confirmation.xml")
ui.add(content, compact)
ui.add(content, favorites_view)
ui.add(content, confirmation)
local favorite_host = ui.find(favorites_view, "favorite_rows")
local favorites_empty = ui.find(favorites_view, "favorites_empty")
local tree = ui.find(ui.load("tree.xml"), "skill_categories")

-- Favorites first (its skills are yours), then the built-in window's categories and order.
local favorite_category = { name = "favorites", title = "★ Favorites", skills = {}, favorites = true }
local categories = {
	favorite_category,
	{ name = "abilities", title = "Abilities", skills = { 16, 17, 18, 19, 20, 21 } },
	{ name = "body", title = "Body & Defense", skills = { 152, 132, 155, 154, 153, 168, 145 } },
	{ name = "meleew", title = "Melee Weapons", skills = { 102, 103, 106, 107, 105, 104, 100, 101, 118, 120 } },
	{ name = "melees", title = "Melee Specials", skills = { 146, 142, 147, 144, 143 } },
	{ name = "rangedw", title = "Ranged Weapons", skills = { 112, 111, 114, 116, 115, 113, 133, 109, 110, 134, 119 } },
	{ name = "rangeds", title = "Ranged Specials", skills = { 150, 151, 148, 167, 121, 108 } },
	{ name = "nanocast", title = "Nanos & Casting", skills = { 127, 128, 129, 122, 131, 130, 149 } },
	{ name = "exploring", title = "Exploring", skills = { 139, 166, 117, 156, 137 } },
	{ name = "combatheal", title = "Combat & Healing", skills = { 136, 164, 162, 135, 123, 124 } },
	{ name = "traderepair", title = "Trade & Repair", skills = { 125, 126, 157, 163, 158, 160, 141, 165, 161, 159 } },
	{ name = "disabled", title = "Disabled / Legacy", skills = { 138, 140 } },
}
-- Text preferences come back as written, but are stored JSON-quoted; accept both.
local function read_text(key)
	local value = ui.preference.read(key) or ""
	return (value:gsub('^"(.*)"$', "%1"))
end

local known_skill, category_of = {}, {}
for _, value in ipairs(categories) do
	for _, id in ipairs(value.skills) do
		known_skill[id] = true
		category_of[id] = value
	end
end
local grouped = ui.preference.read("modern_skills_grouped") ~= "false" -- favorites view by type
local favorite_headers = {} -- header views in the favorites view
local favorite_groups = 0 -- headers currently shown

local rows, facts, suggestion_rows = {}, {}, {}
local favorite_rows = {} -- rows built for the favorites (Favorites category + Favorites view)
local favorites, favorite_set = {}, {} -- skill ids in order; id -> true
local character -- storage-safe id of the logged-in character
local favorites_pending = false -- the favorites changed during combat; rebuild rows after it
local state, frame
local selected, category = 16, categories[2]
local mode = "full" -- "full" | "compact" | "favorites"
local show_suggestions = false
local last_confirmation, last_suggestions = 0, false
local render, select_skill, set_mode, toggle_favorite
local row_width = { full = ROW_WIDTH, favorites = ROW_WIDTH } -- current row widths per host kind

local function number(value, known)
	return known and Theme.thousands(value) or "--"
end

-- IP cost tier (profession / breed): cheap green through expensive blue, as the built-in
-- window, in softer tones.
local function cost_color(level)
	if level < 0 then return IDLE end
	if level <= 5 then return "#8FD6A0" end
	if level <= 10 then return "#6CD4B8" end
	if level <= 15 then return "#6CC8D4" end
	if level <= 20 then return "#6CA8E0" end
	return "#8C9CFF"
end

local function edit(id, direction, shifted)
	local entry = facts[id]
	if not entry or not state.can_edit or not entry.known then
		return
	end
	select_skill(id)
	local target = entry.purchased + direction
	if shifted then
		target = direction > 0 and game.skills.affordable_maximum(entry.reference)
			or game.skills.saved_value(entry.reference)
	end
	if target >= 0 then
		game.skills.propose(entry.reference, target)
	end
end

local function add_row(host, id, small, list, kind)
	local root = ui.find(ui.load("row.xml"), "skill_row")
	local row = { root = root, id = id, small = small, kind = small and "compact" or (kind or "full") }
	for _, name in ipairs({ "star", "name", "delta", "value", "bar", "bar_fill", "increase", "decrease" }) do
		row[name] = ui.find(root, name)
	end
	local width = small and COMPACT_ROW_WIDTH or row_width[row.kind]
	ui.limits(root, width, small and COMPACT_ROW_HEIGHT or ROW_HEIGHT, width, small and COMPACT_ROW_HEIGHT or ROW_HEIGHT)
	ui.size(root, width, small and COMPACT_ROW_HEIGHT or ROW_HEIGHT)
	if small then
		ui.visible(row.bar, false)
	end
	ui.on_click(root, function()
		select_skill(id)
	end)
	ui.on_click(row.star, function()
		toggle_favorite(id)
	end)
	ui.on_repeat(row.increase, function(shifted)
		edit(id, 1, shifted)
	end)
	ui.on_repeat(row.decrease, function(shifted)
		edit(id, -1, shifted)
	end)
	ui.add(host, root)
	rows[#rows + 1] = row
	if list then list[#list + 1] = row end
	return row
end

local function select_category(value)
	if ui.in_combat() then
		return
	end
	ui.cancel_input(content)
	if mode == "compact" and category == value then
		category = nil
	else
		category, selected = value, value.skills[1] or selected
	end
	show_suggestions = false
	ui.scroll_top(ui.find(expanded, "skill_scroll"))
	render()
end

for _, value in ipairs(categories) do
	value.root = ui.find(ui.load("category.xml"), "category")
	value.button = ui.find(value.root, "category_button")
	value.label = ui.find(value.root, "category_label")
	value.marker = ui.find(value.root, "category_marker")
	ui.text(value.label, value.title)
	value.compact = ui.find(value.root, "compact_rows")
	value.expanded = ui.find(ui.load("group.xml"), "skill_group")
	ui.add(ui.find(expanded, "group_host"), value.expanded)
	for _, id in ipairs(value.skills) do
		add_row(value.expanded, id, false)
		add_row(value.compact, id, true)
	end
	ui.on_click(value.button, function()
		select_category(value)
	end)
	ui.add(tree, value.root)
end
ui.add(ui.find(expanded, "category_host"), tree)

-- ---------------------------------------------------------------- favorites
-- Rows for the favorites: in the Favorites category (full + compact) and the Favorites view.
-- Built out of combat only; a change during combat shows once it ends.
local function build_favorite_rows()
	if ui.in_combat() then
		favorites_pending = true
		return
	end
	favorites_pending = false
	local gone = {}
	for _, row in ipairs(favorite_rows) do
		gone[row] = true
		ui.destroy(row.root)
	end
	if next(gone) then
		local kept = {}
		for _, row in ipairs(rows) do
			if not gone[row] then kept[#kept + 1] = row end
		end
		rows = kept
	end
	for _, header in ipairs(favorite_headers) do ui.destroy(header) end
	favorite_rows, favorite_headers, favorite_groups = {}, {}, 0
	-- Display order: starred order, or (grouped) by category in the Skills window's order,
	-- starred order within each, with a header before each category.
	local order = {} -- { header = category } or { id = skill }
	if grouped then
		for _, value in ipairs(categories) do
			if not value.favorites then
				local started = false
				for _, id in ipairs(favorites) do
					if category_of[id] == value then
						if not started then
							order[#order + 1] = { header = value }
							started = true
							favorite_groups = favorite_groups + 1
						end
						order[#order + 1] = { id = id }
					end
				end
			end
		end
	else
		for _, id in ipairs(favorites) do order[#order + 1] = { id = id } end
	end
	local function header(host, value, width)
		local view = ui.find(ui.load("favorite_header.xml"), "favorite_header")
		ui.text(ui.find(view, "label"), string.upper(value.title))
		ui.size(view, width, GROUP_HEADER)
		ui.add(host, view)
		favorite_headers[#favorite_headers + 1] = view
	end
	favorite_category.skills = {}
	for _, item in ipairs(order) do
		if item.header then
			header(favorite_category.expanded, item.header, row_width.full)
			header(favorite_category.compact, item.header, COMPACT_ROW_WIDTH)
			header(favorite_host, item.header, row_width.favorites)
		else
			favorite_category.skills[#favorite_category.skills + 1] = item.id
			add_row(favorite_category.expanded, item.id, false, favorite_rows)
			add_row(favorite_category.compact, item.id, true, favorite_rows)
			add_row(favorite_host, item.id, false, favorite_rows, "favorites")
		end
	end
	ui.visible(favorites_empty, #favorites == 0)
	if mode == "favorites" and frame then frame:resize(0, 0) end
end

local function save_favorites()
	if character then
		pcall(ui.storage.write, "fav/" .. character, table.concat(favorites, ","))
	end
end

toggle_favorite = function(id)
	if favorite_set[id] then
		favorite_set[id] = nil
		for index, other in ipairs(favorites) do
			if other == id then table.remove(favorites, index) break end
		end
	else
		favorite_set[id] = true
		favorites[#favorites + 1] = id
	end
	save_favorites()
	build_favorite_rows()
	render()
end

local function load_favorites()
	favorites, favorite_set = {}, {}
	local ok, saved = pcall(ui.storage.read, "fav/" .. character)
	for text in ((ok and saved) or ""):gmatch("%d+") do
		local id = tonumber(text)
		if known_skill[id] and not favorite_set[id] then
			favorites[#favorites + 1] = id
			favorite_set[id] = true
		end
	end
	build_favorite_rows()
	render()
end

game.character.subscribe("self", "", function(_, me)
	if not me or character then return end
	local id = me.key or me.name
	if not id or id == "" then return end
	character = id:gsub("[^%w_%-]", "_")
	load_favorites()
end)
Security.on_unlock(function()
	if favorites_pending then
		build_favorite_rows()
		render()
	end
end)

select_skill = function(id)
	if ui.in_combat() then
		return
	end
	selected, show_suggestions = id, false
	-- Stay in the open category when it lists this skill (Favorites does too).
	local stays = false
	for _, skill in ipairs(category and category.skills or {}) do
		if skill == id then stays = true end
	end
	if not stays then
		for _, value in ipairs(categories) do
			if not value.favorites then
				for _, skill in ipairs(value.skills) do
					if skill == id then category = value end
				end
			end
		end
	end
	render()
end

-- ---------------------------------------------------------------- sizes
-- Window sizes per view (outer size, incl. the frame), remembered in preference
-- modern_skills_size_<view> = "width,height". Favorites: the height always fits the rows.
local LIMITS = {
	full = { 560, 360, 1400, 1100 },
	compact = { COMPACT_WIDTH + SIDES, 280, COMPACT_WIDTH + SIDES, 1100 },
	favorites = { 220, 0, 700, 0 },
}
local sizes = {
	full = { WIDTH + SIDES, HEIGHT + ENDS },
	compact = { COMPACT_WIDTH + SIDES, HEIGHT + ENDS },
	favorites = { FAVORITES_WIDTH + SIDES, 0 },
}
for view, size in pairs(sizes) do
	local w, h = read_text("modern_skills_size_" .. view):match("^([%d.]+),([%d.]+)$")
	if w and tonumber(w) and tonumber(h) then size[1], size[2] = math.floor(tonumber(w) + 0.5), math.floor(tonumber(h) + 0.5) end
end

local function favorites_height()
	return ENDS + FAVORITES_CHROME + math.max(1, #favorites) * ROW_HEIGHT + favorite_groups * GROUP_HEADER
		+ (#favorites == 0 and 20 or 0)
end

local function fix(view, width, height)
	ui.limits(view, width, height, width, height)
	ui.size(view, width, height)
end

local function size_rows(kind, width)
	if row_width[kind] == width then return end
	row_width[kind] = width
	for _, row in ipairs(rows) do
		if row.kind == kind then fix(row.root, width, ROW_HEIGHT) end
	end
end

-- Lay the current view out in a content area of width x height.
local function apply_layout(width, height)
	if mode == "full" then
		local body = math.max(100, height - HEADER - BODY_GAP - FOOTER)
		local inner = width - 4 -- skills_content side borders
		local list = math.max(200, inner - SIDEBAR - DETAILS - 12) -- 12 = the list's side gaps
		fix(expanded, inner, height)
		fix(ui.find(expanded, "body"), inner, body)
		fix(ui.find(expanded, "category_column"), SIDEBAR, body)
		fix(ui.find(expanded, "info_area"), list, body)
		fix(ui.find(expanded, "details_column"), DETAILS, body)
		size_rows("full", list - 10) -- 8px scrollbar + 2
	elseif mode == "compact" then
		fix(compact, COMPACT_WIDTH, height)
	else
		fix(favorites_view, width, height)
		size_rows("favorites", width - 4)
	end
end

local function layout(window, width, height)
	local limits, saved = LIMITS[mode], sizes[mode]
	if not width or width <= 0 or not height or height <= 0 then
		width, height = saved[1], saved[2] -- a view switch: that view's own size
	end
	local min_h, max_h = limits[2], limits[4]
	if mode == "favorites" then min_h, max_h = favorites_height(), favorites_height() end
	width = math.max(limits[1], math.min(limits[3], width))
	height = math.max(min_h, math.min(max_h, height))
	ui.limits(window.root, limits[1], min_h, limits[3], max_h)
	ui.request_size(window.root, width, height)
	window:fit_title(width, true)
	window:fit_content(width, height)
	ui.size(content, width - SIDES, height - ENDS)
	apply_layout(width - SIDES, height - ENDS)
	if saved[1] ~= width or saved[2] ~= height then
		saved[1], saved[2] = width, height
		ui.preference.write("modern_skills_size_" .. mode, math.floor(width + 0.5) .. "," .. math.floor(height + 0.5), "text")
	end
end

local MODES = { { "compact", "Compact View" }, { "favorites", "Favorites View" } }

set_mode = function(value)
	if ui.in_combat() or value == mode then
		return
	end
	if value ~= "full" and state and state.confirmation ~= 0 then
		return
	end
	ui.cancel_input(content)
	mode = value
	ui.visible(expanded, mode == "full")
	ui.visible(compact, mode == "compact")
	ui.visible(favorites_view, mode == "favorites")
	ui.add(ui.find(mode == "compact" and compact or expanded, "category_host"), tree)
	frame:resize(0, 0)
	ui.publish("compact", tostring(mode == "compact"))
	ui.preference.write("modern_skills_view", mode, "text")
	for index, entry in ipairs(MODES) do
		ui.menu.checked(frame.icon, index, mode == entry[1])
	end
	render()
end

-- The last view you used comes back next time (set before the window's first layout).
do
	local saved = read_text("modern_skills_view")
	if saved == "compact" or saved == "favorites" then
		mode = saved
		ui.visible(expanded, false)
		ui.visible(compact, mode == "compact")
		ui.visible(favorites_view, mode == "favorites")
		ui.add(ui.find(mode == "compact" and compact or expanded, "category_host"), tree)
	end
end

local menu = {}
for _, entry in ipairs(MODES) do
	menu[#menu + 1] = {
		label = entry[2],
		checked = mode == entry[1],
		invoke = function()
			set_mode(mode == entry[1] and "full" or entry[1])
		end,
	}
end
local GROUP_ITEM = #menu + 1 -- "Group favorites by type"
menu[GROUP_ITEM] = {
	label = "Group favorites by type",
	checked = grouped,
	invoke = function()
		if ui.in_combat() then return end
		grouped = not grouped
		ui.preference.write("modern_skills_grouped", tostring(grouped), "bool")
		ui.menu.checked(frame.icon, GROUP_ITEM, grouped)
		build_favorite_rows()
		render()
	end,
}

frame = Window.create({
	template = Theme.WINDOW_TEMPLATE,
	title = "Skills",
	content = content,
	width = sizes[mode][1],
	height = mode == "favorites" and favorites_height() or sizes[mode][2],
	horizontal = "center",
	vertical = "center",
	resizable = true,
	layout = layout,
	menu = menu,
	on_visibility = function(visible)
		ui.publish("visibility", tostring(visible))
	end,
})
ui.root(frame.root)
for _, host in ipairs({ expanded, compact, favorites_view }) do
	ui.on_click(ui.find(host, "quit"), function()
		frame:close()
	end)
end
ui.on_click(ui.find(favorites_view, "full_view"), function()
	set_mode("full")
end)
ui.on_click(ui.find(expanded, "suggest_ip"), function()
	game.skills.suggest()
end)
local function cancel()
	game.skills.cancel_confirmation(state.confirmation)
end
ui.on_click(ui.find(confirmation, "cancel"), cancel)
ui.on_click(ui.find(confirmation, "close"), cancel)
ui.visible(favorites_empty, true)


local function render_row(row)
	ui.text_color(row.star, favorite_set[row.id] and STAR_ON or STAR_OFF)
	local entry = facts[row.id]
	if not entry then
		return
	end
	ui.text(row.name, entry.name)
	ui.tooltip(row.root, entry.title)
	ui.selected(row.root, row.id == selected)
	ui.text_color(row.name, cost_color(entry.cost_level))
	ui.text(row.value, number(entry.buffed, entry.buffed_known))
	local color = TEXT
	if entry.known and entry.buffed_known then
		if entry.buffed > entry.unmodified then
			color = UP
		elseif entry.buffed < entry.unmodified then
			color = DOWN
		end
	end
	ui.text_color(row.value, color)
	ui.text(row.delta, entry.known and entry.delta > 0 and ("+" .. entry.delta) or "")
	ui.bind(row.increase, entry.reference)
	ui.bind(row.decrease, entry.reference)
	ui.selected(row.increase, entry.delta > 0)
	ui.selected(row.decrease, entry.delta > 0)
	ui.enabled(row.increase, state.can_edit and entry.can_improve)
	ui.enabled(row.decrease, state.can_edit and entry.can_improve and entry.delta > 0)
	if not row.small then
		local share = entry.known and entry.maximum > 0 and math.max(0, math.min(1, entry.purchased / entry.maximum)) or 0
		local fill = math.floor(BAR_WIDTH * share + 0.5)
		ui.limits(row.bar_fill, fill, 4, fill, 4)
		ui.size(row.bar_fill, fill, 4)
		ui.tooltip(row.bar, entry.known and (entry.purchased .. " / " .. entry.maximum .. " bought") or "")
	end
end

render = function()
	if not state then
		return
	end
	for _, value in ipairs(categories) do
		local open = category == value
		ui.selected(value.button, open)
		ui.visible(value.marker, open)
		ui.text_color(value.label, open and TEXT or IDLE)
		ui.visible(value.expanded, mode == "full" and open)
		ui.visible(value.compact, mode == "compact" and open)
	end
	for _, row in ipairs(rows) do
		render_row(row)
	end
	for _, host in ipairs({ expanded, compact, favorites_view }) do
		ui.text(ui.find(host, "remaining_ip"), number(state.remaining, state.remaining_known))
		ui.tooltip(ui.find(host, "remaining_ip"), state.status)
		local save = ui.find(host, "accept")
		ui.bind(save, state.save)
		ui.action(save, "game.skills.save", state.save, "left")
		ui.enabled(save, state.can_save)
	end
	for _, host in ipairs({ expanded, compact }) do
		local reset = ui.find(host, "reset_all")
		ui.bind(reset, state.reset_all)
		ui.action(reset, "game.skills.prepare_reset", state.reset_all, "left")
		ui.text(reset, "Reset all skills (" .. number(state.full_resets, state.full_resets_known) .. ")")
		ui.enabled(reset, state.reset_reason == "")
		ui.tooltip(reset, state.reset_reason)
	end
	ui.text(ui.find(expanded, "status"), state.status)
	ui.tooltip(ui.find(expanded, "status"), state.status)
	ui.enabled(ui.find(expanded, "suggest_ip"), state.can_suggest)
	ui.tooltip(ui.find(expanded, "suggest_ip"), state.suggestion_hint)
	ui.visible(ui.find(expanded, "details"), not show_suggestions)
	ui.visible(ui.find(expanded, "suggestion_result"), show_suggestions)
	local entry = facts[selected]
	if entry then
		ui.text(ui.find(expanded, "stat_name"), entry.title)
		ui.text(ui.find(expanded, "stat_description"), entry.description)
		for _, field in ipairs({
			{ "base", entry.unbuffed, entry.known },
			{ "buffed", entry.buffed, entry.buffed_known },
			{ "maxskill", entry.display_maximum, entry.known },
			{ "pointdelta", entry.delta, entry.known },
			{ "unitcost", entry.next_cost, entry.next_cost_known },
			{ "totalcost", entry.cost, entry.known },
		}) do
			ui.text(ui.find(expanded, field[1]), number(field[2], field[3]))
		end
		ui.text_color(ui.find(expanded, "pointdelta"), entry.known and entry.delta > 0 and "#F0C060" or TEXT)
		ui.visible(ui.find(expanded, "reset_area"), entry.reset ~= 0)
		ui.text(
			ui.find(expanded, "reset_points"),
			"Reset points left: " .. number(state.reset_points, state.reset_points_known)
		)
		local reset = ui.find(expanded, "reset_skill")
		ui.bind(reset, entry.reset)
		ui.action(reset, "game.skills.prepare_reset", entry.reset, "left")
		ui.enabled(reset, entry.reset_reason == "")
		ui.tooltip(reset, entry.reset_reason)
	end
end

function skills_apply(snapshot, current)
	facts, state = {}, current
	for _, entry in ipairs(snapshot) do
		facts[entry.id] = entry
	end
	if state.suggestions_shown and not last_suggestions then
		show_suggestions = true
	end
	if not state.suggestions_shown then
		show_suggestions = false
	end
	last_suggestions = state.suggestions_shown
	if not ui.in_combat() then
		for _, row in ipairs(suggestion_rows) do
			ui.destroy(row)
		end
		suggestion_rows = {}
		if show_suggestions then
			for _, entry in ipairs(snapshot) do
				if entry.delta > 0 then
					local row = ui.load("suggestion.xml")
					ui.text(ui.find(row, "name"), entry.name)
					ui.text(ui.find(row, "delta"), "+" .. tostring(entry.delta))
					ui.add(ui.find(expanded, "suggestion_rows"), row)
					suggestion_rows[#suggestion_rows + 1] = row
				end
			end
		end
	end
	if state.confirmation ~= last_confirmation then
		ui.cancel_input(content)
		-- Questions are shown over the full view.
		if state.confirmation ~= 0 and mode ~= "full" then
			set_mode("full")
		end
	end
	last_confirmation = state.confirmation
	for index = 1, GROUP_ITEM do
		ui.menu.visible(frame.icon, index, state.confirmation == 0)
	end
	ui.visible(confirmation, state.confirmation ~= 0)
	ui.enabled(expanded, state.confirmation == 0)
	ui.text(ui.find(confirmation, "window_title"), state.confirmation_title)
	ui.text(ui.find(confirmation, "message"), state.confirmation_message)
	ui.bind(ui.find(confirmation, "confirm"), state.confirmation)
	ui.action(ui.find(confirmation, "confirm"), "game.skills.confirm", state.confirmation, "left")
	render()
end

Security.render("skills_apply")
