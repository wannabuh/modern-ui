-- Modern Team: flat unit-frame team window (role prk.team).
--
-- Each member: profession icon, L for the leader, name, level, then a flat health bar
-- (green, amber under 50%, red under 25%) over a thin nano bar. Out-of-zone members are
-- dimmed, dead ones read "Dead", and your current target gets a teal edge.
-- Title: "Team  4 · Lvl 45–60" (the server never reports a team level, so the range is shown).
--
-- Options (title menu, or right-click any member → Window options; works in compact too):
--   Health: current / max  or  missing ("−1,020")
--   Buffs: None / All (every nano on each member) / Mine (only nanos you cast, plus a line
--          listing your buffs that member is missing compared with the rest of the team)
--   Compact: hides the title bar and header while you're in a team; a slim grip stays for
--            dragging. (Leave is in your own row's right-click menu.)
-- Left-click a row to target (native); right-click for kick / make leader / leave.
pcall(ui.require, "spiritech.modern-common/screenfit") -- keep window positions through fullscreen changes
local Window = ui.require("core.window")
local Strip = ui.require("ncu.strip")
local Effects = ui.require("effects.presentation")
local Theme = ui.require("spiritech.modern-common/theme")

local MAX_ROWS = 6
local ROW = 28 + 1 -- row + divider
local HEADER = 22 + 1
local ENDS, COMPACT_ENDS = 33, 17 -- frame chrome; compact shrinks the title bar to 8px
local NAME_WIDTH = 100
local FIXED = 6 + 22 + 5 + 10 + 5 + 24 + 6 + 6 -- row padding, icon, L, gaps, level, bar gap, padding
local GREEN, AMBER, RED, DEAD = "#3E8A58", "#B5852B", "#A33434", "#5E6875"

local content = ui.load("content.xml")
local host = ui.find(content, "team_rows")
local invite = ui.find(content, "invite_button")
local leave = ui.find(content, "leave_button")
local header = ui.find(content, "team_header")
local header_divider = ui.find(content, "team_header_divider")
local info = ui.find(content, "team_info")
local measure = ui.find(content, "team_measure")
local rows, members, nanos, casters = {}, {}, {}, {}
local frame, state
local my_id
local target_reference
local bar_width, name_width = 120, NAME_WIDTH
local apply_compact -- defined with the options menu below

-- ------------------------------------------------------------------ options
local function pref(key, default)
	local value = ui.preference.read(key)
	if value == "" then return default end
	return value
end
local options = {
	missing = pref("modern_team_missing", "false") == "true",
	buffs = pref("modern_team_buffs", "none"), -- none / all / mine
	compact = pref("modern_team_compact", "false") == "true",
}

-- ------------------------------------------------------------------ rows
local function fit(name)
	ui.text(measure, name)
	if ui.text_width(measure) <= name_width then return name end
	local low, high = 0, #name
	while low < high do
		local middle = math.floor((low + high + 1) / 2)
		ui.text(measure, name:sub(1, middle) .. "...")
		if ui.text_width(measure) <= name_width then low = middle else high = middle - 1 end
	end
	return name:sub(1, low) .. "..."
end

for index = 1, MAX_ROWS do
	local loaded = ui.load("row.xml")
	ui.add(host, loaded)
	local root = ui.find(loaded, "team_row") or loaded
	local row = { root = root }
	for _, name in ipairs({ "profession", "leader_tag", "member_name", "member_level", "health_bar", "health_fill",
		"health_text", "nano_bar", "nano_fill", "ncu_strip", "missing_buffs", "row_target", "row_target_edge" }) do
		row[name] = ui.find(root, name)
	end
	ui.text_alignment(row.health_text, "right")
	ui.text_alignment(row.member_level, "right")
	row.strip = Strip.create(row.ncu_strip, {
		template = "team_ncu_slot.xml", cell_width = 16, cell_height = 16, lines = 2,
	})
	rows[index] = row
end

-- ------------------------------------------------------------------ buffs
-- Entries shown in a member's strip for the current Buffs option.
local function buffs_for(member)
	local list = member and nanos[member.character.reference] or {}
	if options.buffs ~= "mine" then return list end
	local mine = {}
	for _, entry in ipairs(list) do
		if my_id and casters[entry.token] == my_id then mine[#mine + 1] = entry end
	end
	return mine
end

-- Your buffs present on any teammate but missing on this one (by nano).
local function missing_for(member)
	if options.buffs ~= "mine" or not my_id then return nil end
	local everyone = {}
	for _, other in ipairs(members) do
		for _, entry in ipairs(buffs_for(other)) do everyone[entry.nano_id] = entry.name end
	end
	local has = {}
	for _, entry in ipairs(buffs_for(member)) do has[entry.nano_id] = true end
	local names = {}
	for nano, name in pairs(everyone) do
		if not has[nano] then names[#names + 1] = name end
	end
	table.sort(names)
	return #names > 0 and ("Missing: " .. table.concat(names, ", ")) or nil
end

-- ------------------------------------------------------------------ layout
-- Compact only applies while you're in a team; otherwise the normal header shows, so the
-- window (and its options) can never get stuck without a way back.
local function compact() return options.compact and #members > 0 end
local function ends() return compact() and COMPACT_ENDS or ENDS end

local function layout(window, width)
	width = math.max(220, math.min(640, width))
	local room = width - Window.CONTENT_SIDES - FIXED
	name_width = math.max(50, math.min(NAME_WIDTH, room - 60))
	bar_width = math.max(40, room - name_width)
	local height = ends() + (compact() and 0 or HEADER)
	for index, row in ipairs(rows) do
		local member = members[index]
		ui.visible(row.root, member ~= nil)
		ui.size(row.member_name, name_width, -1)
		if member then
			height = height + ROW
			local strip_height = row.strip:show(buffs_for(member), width - 19, options.buffs ~= "none")
			if strip_height > 0 then height = height + strip_height + 2 end
			local missing = missing_for(member)
			ui.visible(row.missing_buffs, missing ~= nil)
			if missing then
				ui.text(row.missing_buffs, missing)
				height = height + 14
			end
		else
			row.strip:show({}, width - 19, false)
			ui.visible(row.missing_buffs, false)
		end
	end
	if #members == 0 then height = height + 20 end
	ui.limits(window.root, 220, height, 640, height)
	ui.request_size(window.root, width, height)
	window:fit_title(width, not compact())
	-- Compact: the title bar is 16px shorter, so the content gets that much more room.
	window:fit_content(width, height + (compact() and (ENDS - COMPACT_ENDS) or 0))
end

frame = Window.create({
	template = Theme.WINDOW_TEMPLATE,
	title = "Team", content = content, width = 300, height = 120,
	horizontal = "center", x = 10, y = 174, layout = layout,
	menu = false,
})
ui.root(frame.root)
local titlebar = ui.find(frame.root, "window_titlebar")

local function resize()
	frame:resize(ui.chosen_width(frame.root), ui.chosen_height(frame.root))
end

-- ------------------------------------------------------------------ presentation
local function fill(bar, fill_view, current, maximum, color)
	local width = ui.width(bar)
	if width <= 0 then width = bar_width end
	local inner = math.max(0, width - 2)
	local fraction = (current and maximum and maximum > 0) and math.max(0, math.min(1, current / maximum)) or 0
	local pixels = math.floor(inner * fraction + 0.5)
	ui.visible(fill_view, pixels > 0)
	ui.size(fill_view, math.max(1, pixels), -1)
	if color then ui.fill_color(fill_view, color) end
	return fraction
end

local function present_row(row, member)
	local character = member.character
	local present = character.present
	local name = character.name or "?"
	if member.ignored then name = name .. " [i]" end
	ui.text(row.member_name, fit(name))
	ui.tooltip(row.root, character.name or "")
	ui.visible(row.leader_tag, member.leader)
	ui.text(row.member_level, character.level and tostring(character.level) or "")
	ui.content(row.profession, (character.profession or 0) > 0)
	ui.image(row.profession, character.profession and ("gfx://GFX_GUI_ICON_PROFESSION_" .. character.profession) or "")
	ui.visual_enabled(row.profession, present)

	local health, maximum = character.health, character.max_health
	local dead = health == 0 and present
	local fraction = (health and maximum and maximum > 0) and health / maximum or 0
	local color = dead and DEAD or fraction < 0.25 and RED or fraction < 0.5 and AMBER or GREEN
	fill(row.health_bar, row.health_fill, health, maximum, color)
	fill(row.nano_bar, row.nano_fill, character.nano, character.max_nano)
	local text = ""
	if not present then
		text = "Out of zone"
	elseif dead then
		text = "Dead"
	elseif health and maximum then
		if options.missing then
			local deficit = maximum - health
			text = deficit > 0 and ("−" .. Theme.thousands(deficit)) or ""
		else
			text = Theme.thousands(health) .. " / " .. Theme.thousands(maximum)
		end
	end
	ui.text(row.health_text, text)
	ui.opacity(row.root, present and 1 or 0.5)

	local targeted = target_reference ~= nil and character.reference == target_reference
	ui.visible(row.row_target, targeted)
	ui.visible(row.row_target_edge, targeted)
end

local function animate_names(now)
	local active = false
	for index, row in ipairs(rows) do
		local member = members[index]
		local flashing = member and member.flash_until_ms and member.flash_until_ms > now
		active = active or flashing
		ui.opacity(row.member_name, (flashing and math.floor(now / 500) % 2 == 1) and 0 or 1)
	end
	if not active then ui.stop_updates() end
	return active
end

local options_menu = ui.find(content, "team_options_menu")
local function row_menu(row, member, context)
	if row.menu_context == context then return end
	row.menu_context = context
	ui.menu.clear(row.root)
	if not member then return end
	ui.menu.submenu(row.root, "Window options", options_menu)
	ui.menu.separator(row.root)
	local character = member.character
	if character.is_self then
		ui.menu.prepared_action(row.root, "Leave", game.team.prepare_leave())
	elseif state.can_invite then
		ui.menu.prepared_action(row.root, "Kick " .. (character.name or "this player"),
			game.team.prepare_kick(character.reference))
		ui.menu.prepared_action(row.root, "Make " .. (character.name or "this player") .. " leader",
			game.team.prepare_leader(character.reference))
	end
end

for _, row in ipairs(rows) do
	for _, view in ipairs({ row.root, row.profession, row.member_name, row.health_bar }) do
		ui.on_pointer_release(view, "right", function() ui.menu.show(row.root) end)
	end
end

local function title_text()
	if not (state and state.in_team) then return "Team" end
	local low, high
	for _, member in ipairs(members) do
		local level = member.character.level
		if level then
			low = (not low or level < low) and level or low
			high = (not high or level > high) and level or high
		end
	end
	local levels = low and (low == high and ("Lvl " .. low) or ("Lvl " .. low .. "–" .. high)) or ""
	return "Team  " .. #members .. (levels ~= "" and ("  ·  " .. levels) or "")
end

local function present(update)
	if update then state = update.data or { in_team = false, can_invite = false, members = {} } end
	state = state or { in_team = false, can_invite = false, members = {} }
	members = {}
	local context = tostring(state.context) .. ":" .. tostring(state.can_invite)
	for _, member in ipairs(state.members or {}) do
		context = context .. ":" .. member.character.reference .. ":" .. tostring(member.leader)
			.. ":" .. (member.character.name or "")
		if member.own_team and #members < #rows then members[#members + 1] = member end
	end
	apply_compact()
	local title = title_text()
	ui.text(ui.find(frame.root, "window_title"), title)
	ui.text(info, state.in_team and title or "Not in a team")
	ui.visible(leave, state.in_team)
	ui.enabled(invite, state.can_invite)
	ui.actions.bind(leave, game.team.prepare_leave(), "left", "release")
	ui.actions.bind(invite, game.team.prepare_invite("target"), "left", "release")
	for index, row in ipairs(rows) do
		local member = members[index]
		local subject = member and member.character.reference
		if row.subject ~= subject then
			ui.cancel_input(row.root)
			row.subject = subject
		end
		row_menu(row, member, context .. ":" .. tostring(subject))
		local selection = subject and game.targeting.prepare_select(subject) or 0
		for _, view in ipairs({ row.root, row.profession, row.member_name, row.health_bar }) do
			ui.actions.bind(view, selection, "left", "press")
		end
		if member then present_row(row, member) end
	end
	if animate_names(ui.time()) then ui.on_update(animate_names) end
	resize()
end

-- ------------------------------------------------------------------ options menu & compact
-- Options live in the title menu and in every member's right-click menu ("Window options").
-- Not on the title bar: right-clicking there is the game's own pick-up-to-dock gesture.
local menu_anchors = { frame.icon, options_menu }

local applied_compact
apply_compact = function()
	local compact = compact()
	if applied_compact == compact then return end
	applied_compact = compact
	for _, name in ipairs({ "window_icon_slot", "window_title_tab", "window_tabs", "window_pin", "window_close" }) do
		local view = ui.find(frame.root, name)
		if view then ui.visible(view, not compact) end
	end
	local height = compact and 8 or 24
	ui.limits(titlebar, 0, height, 4096, height)
	ui.size(titlebar, -1, height)
	ui.tooltip(titlebar, compact and "Drag to move · right-click a member for options" or "")
	ui.visible(header, not compact)
	ui.visible(header_divider, not compact)
end

local build_menu
local function set_option(key, value)
	options[key] = value
	ui.preference.write("modern_team_" .. key, tostring(value), key == "buffs" and "text" or "bool")
	apply_compact()
	build_menu()
	present()
end

build_menu = function()
	for _, anchor in ipairs(menu_anchors) do
		ui.menu.clear(anchor)
		ui.menu.add(anchor, "Health: current / max", not options.missing, function() set_option("missing", false) end)
		ui.menu.add(anchor, "Health: missing", options.missing, function() set_option("missing", true) end)
		ui.menu.separator(anchor)
		ui.menu.add(anchor, "Buffs: none", options.buffs == "none", function() set_option("buffs", "none") end)
		ui.menu.add(anchor, "Buffs: all", options.buffs == "all", function() set_option("buffs", "all") end)
		ui.menu.add(anchor, "Buffs: mine (+ missing)", options.buffs == "mine", function() set_option("buffs", "mine") end)
		ui.menu.separator(anchor)
		ui.menu.add(anchor, "Compact", options.compact, function() set_option("compact", not options.compact) end)
		if anchor == frame.icon then
			ui.menu.separator(anchor)
			ui.menu.close(anchor, frame.root)
		end
	end
end

apply_compact()
build_menu()

-- ------------------------------------------------------------------ subscriptions
game.team.subscribe(function(update)
	present(update)
	build_menu()
end)
game.targeting.subscribe(function(update)
	local selected = update and update.data and update.data.selected
	target_reference = selected and selected.reference or nil
	ui.actions.bind(invite, game.team.prepare_invite("target"), "left", "release")
	if state then present() end
end)
game.effects.subscribe("team", function(update)
	nanos = Effects.collections(update)
	casters = {}
	for _, owner in ipairs(update.data or {}) do
		for _, effect in ipairs(owner.effects or {}) do casters[effect.reference] = effect.caster end
	end
	resize()
end)
game.character.subscribe("self", "", function(_, me)
	if me and me.id and me.id ~= my_id then
		my_id = me.id
		resize()
	end
end)
present()
