if CC_ROLE ~= "control-center" then return end -- shortcut-bar instances run hotbar.lua (role.lua)
-- Modern Control Center: one slim bar in the bottom-right corner instead of the two wings
-- (role prk.control-center). Menus, window toggles, commands, perks, addon windows, the
-- minibar and the docking column work as in the built-in package (ControlCenter/main.lua).
local root = ui.load("root.xml")
local dock = ui.find(root, "right_wing_dock")
local bar = ui.load("bar.xml")
ui.add(dock, bar)
ui.root(root)

-- The built-in code looks some views up through the old wing roots.
local left, right = bar, bar

-- NCU and credits are two small separate windows, meant for the bottom-centre player stack.
local ncu_window = ui.load("ncu_window.xml")
ui.add(root, ncu_window)
local credits_window = ui.load("credits_window.xml")
ui.add(root, credits_window)
local ncu = ui.find(ncu_window, "ncu")
local credits = ui.find(credits_window, "credits")
local ncu_meter = ui.find(ncu_window, "ncu_meter")
local ncu_meter_fill = ui.find(ncu_window, "ncu_meter_fill")
local NCU_METER_WIDTH = 120 -- fallback estimate before layout (200 window - padding, label, number)
local aggdef = ui.find(bar, "aggdef")
local commands = {}
local latest_state = nil
local latest_perks = {}
local menu_state = {}
local top_menus = {}
local addon_windows = {}
local perk_anchor = ui.load("menu_anchor.xml")
ui.add(root, perk_anchor)

game.control_center.bind_aggdef(aggdef)

local AGGDEF_MIN = -100
local AGGDEF_MAX = 100

local function aggdef_progress(value)
	return (value - AGGDEF_MIN) / (AGGDEF_MAX - AGGDEF_MIN)
end

local function aggdef_value(progress)
	return math.floor(AGGDEF_MIN + progress * (AGGDEF_MAX - AGGDEF_MIN) + 0.5)
end

local function aggdef_tooltip(value)
	if value > 0 then
		return "Aggressive: " .. tostring(value) .. "%"
	elseif value < 0 then
		return "Defensive: " .. tostring(-value) .. "%"
	end
	return "Balanced (0%)"
end

local function show_aggdef(value)
	ui.tooltip(aggdef, aggdef_tooltip(value))
end

ui.on_value_changed(aggdef, function(progress)
	show_aggdef(aggdef_value(progress))
end)

---------------------------------------------------------------------------
-- Bar layout
---------------------------------------------------------------------------
local BUTTONS = {
	{ "actions", "Actions" }, { "character", "Skills" }, { "inventory", "Inventory" }, { "wear", "Wear" },
	{ "nano", "Nanos" }, { "ncu_window", "NCU" }, { "map", "Map" }, { "missions", "Missions" },
	{ "team", "Team" }, { "friends", "Friends" }, { "store", "Shop" },
}
local PADDING, MINIMUM_CELL = 9, 34
local BUTTONS_HEIGHT = 24
local GRIP_WIDTH, AGGDEF_WIDTH = 12, 190 -- drag grip; divider + DEF + slider + AGG (+ info button)
local NCU_WIDTH, CREDITS_WIDTH, STATUS_HEIGHT = 200, 140, 20
local underline = {}

local width = 2 + GRIP_WIDTH + AGGDEF_WIDTH
for _, entry in ipairs(BUTTONS) do
	local name, label = entry[1], entry[2]
	local button = ui.find(bar, name)
	ui.text(button, label)
	ui.text_alignment(button, "center")
	local text_width = ui.text_width(button)
	if not text_width or text_width <= 0 then
		text_width = #label * 6.5 -- font not measurable yet: estimate for 11px text
	end
	local cell_width = math.max(MINIMUM_CELL, math.ceil(text_width) + 2 * PADDING)
	ui.size(ui.find(bar, name .. "_cell"), cell_width, BUTTONS_HEIGHT)
	ui.size(button, cell_width, BUTTONS_HEIGHT)
	underline[name] = ui.find(bar, name .. "_open")
	width = width + cell_width
end
ui.size(ui.find(bar, "cc_aggdef"), AGGDEF_WIDTH, BUTTONS_HEIGHT)
local HEIGHT = 1 + BUTTONS_HEIGHT + 1
ui.size(bar, width, HEIGHT)
ui.size(dock, width, HEIGHT)
ui.size(ncu_window, NCU_WIDTH, STATUS_HEIGHT)
ui.size(credits_window, CREDITS_WIDTH, STATUS_HEIGHT)

---------------------------------------------------------------------------
-- Dragging. Positions are kept in this addon's storage (shared by all characters).
---------------------------------------------------------------------------
local Move = ui.require("core.move")
local Storage = ui.require("core.storage")
local no_placement = { changed = function() end } -- positions are saved below instead

local function restore(view, key, default)
	local ok, saved = pcall(Storage.get, key)
	local x, y
	if ok and type(saved) == "string" then
		x, y = saved:match("^(-?[%d.]+),(-?[%d.]+)$")
	end
	x, y = tonumber(x), tonumber(y)
	if x and y then
		ui.place(view, x, y)
	else
		default()
	end
end

local function movable(view, key, handle)
	Move.attach(view, {
		handle = handle,
		placement = no_placement,
		finished = function(completed)
			if completed then
				pcall(Storage.set, key, string.format("%.0f,%.0f", ui.local_x(view), ui.local_y(view)))
			end
		end,
	})
end

-- Bar: bottom-right corner by default (root.xml), dragged by its grip.
restore(dock, "bar_position", function() end)
movable(dock, "bar_position", ui.find(bar, "cc_grip"))
-- NCU and Credits: by default stacked at the bottom centre, just under Player Bars
-- (bottom inset 200). Drag them wherever you like.
restore(ncu_window, "ncu_position", function()
	ui.align(ncu_window, "center", "end")
	ui.borders(ncu_window, 0, 0, 0, 200 - 3 - STATUS_HEIGHT)
end)
movable(ncu_window, "ncu_position")
ui.require("spiritech.modern-common/centre").attach(ncu_window)
restore(credits_window, "credits_position", function()
	ui.align(credits_window, "center", "end")
	ui.borders(credits_window, 0, 0, 0, 200 - 2 * (3 + STATUS_HEIGHT))
end)
movable(credits_window, "credits_position")
ui.require("spiritech.modern-common/centre").attach(credits_window)

-- Cooldowns window (cooldown_window.lua); fed by the bars' relay, perk icons from
-- control_center_apply.
local CooldownWindow = ui.require("control_center.cooldown_window")
CooldownWindow.clear_relay()
local cooldown_menu_items = {} -- anchor -> index of the "Cooldowns Window" toggle
local cooldown_window = CooldownWindow.create({
	parent = root,
	restore = restore,
	movable = movable,
	on_toggle = function(visible)
		for anchor, index in pairs(cooldown_menu_items) do ui.menu.checked(anchor, index, visible) end
	end,
})

local function mark(button_name, open)
	local view = underline[button_name]
	if view then
		ui.visible(view, open)
	end
end

local windows = {
	inventory = ui.destinations.require("prk.inventory"),
	wear = ui.destinations.require("prk.wear"),
	ncu = ui.destinations.require("prk.ncu"),
	nano = ui.destinations.require("prk.nano-programs"),
	missions = ui.destinations.require("prk.missions"),
	friends = ui.destinations.require("prk.friends"),
	aggdef = ui.destinations.require("prk.aggdef"),
	actions = ui.destinations.require("prk.actions"),
	stats = ui.destinations.require("prk.stats"),
	health = ui.destinations.require("prk.health-bar"),
	nano_bar = ui.destinations.require("prk.nano-bar"),
	experience = ui.destinations.require("prk.experience-bar"),
	alien_experience = ui.destinations.require("prk.alien-experience-bar"),
	chat = ui.destinations.require("prk.chat.default"),
	combat_chat = ui.destinations.require("prk.chat.combat"),
	tradeskills = ui.destinations.require("prk.tradeskills"),
	chat_config = ui.destinations.require("prk.chat-config"),
	skills = ui.destinations.require("prk.skills"),
	perks = ui.destinations.require("prk.perks"),
	planet_map = ui.destinations.require("prk.planet-map"),
	playfield_map = ui.destinations.require("prk.playfield-map"),
	team = ui.destinations.require("prk.team"),
	raid = ui.destinations.require("prk.raid"),
	team_search = ui.destinations.require("prk.team-search"),
	pets = ui.destinations.require("prk.pets"),
	faction = ui.destinations.require("prk.faction"),
}

local function window_entry(label, window)
	return { label = label, window = window }
end

local function command_entry(key, label)
	return { key = key, label = label }
end

local function menu_entry(label, children)
	return { label = label, children = children }
end

local function command_list(values)
	local result = {}
	for _, value in ipairs(values) do
		result[#result + 1] = command_entry(value[1], value[2])
	end
	return result
end

local actions_menu = {
	menu_entry("Emotes", {
		menu_entry("Greetings", command_list({
			{ "bow", "Bow" }, { "curt", "Curtsey" }, { "greet", "Greet" }, { "kneel", "Kneel" },
			{ "salute", "Salute" }, { "scared", "Scared" }, { "surprised", "Surprised" },
			{ "surrender", "Surrender" }, { "wave", "Wave" },
		})),
		menu_entry("Gestures", command_list({
			{ "cross", "Cross Arms" }, { "fishsize", "Fish Size" }, { "gloat", "Gloat" },
			{ "italian", "Italian" }, { "nod", "Nod" }, { "nono", "No No" }, { "pray", "Pray" },
			{ "shrug", "Shrug" }, { "speech", "Speech" }, { "thinker", "Thinker" },
		})),
		menu_entry("Approval", command_list({
			{ "applause", "Applause" }, { "blowkiss", "Blow Kiss" }, { "giggle", "Giggle" },
			{ "kisshigh", "Kiss High" }, { "kisslow", "Kiss Low" }, { "laugh-b", "Laugh-b" },
			{ "laugh-s", "Laugh-s" }, { "prostrate", "Prostrate" }, { "swroyal", "Swroyal" },
			{ "thumbs", "Thumbs Up" },
		})),
		menu_entry("Dislike", command_list({
			{ "angry", "Angry" }, { "bulge", "Bulge" }, { "fblock", "Fblock" }, { "flip", "Flip" },
			{ "moon", "Moon" }, { "puke", "Puke" }, { "shake", "Shake" }, { "slap", "Slap" },
			{ "spit", "Spit" },
		})),
		menu_entry("Dancing", command_list({
			{ "ballet", "Ballet" }, { "chicken", "Chicken" }, { "disco", "Disco" },
			{ "flamenco", "Flamenco" }, { "pulp", "Pulp" }, { "rocky", "Rocky" }, { "ymca", "YMCA" },
		})),
		menu_entry("Athletic", command_list({
			{ "backflip", "Backflip" }, { "strong1", "Strong 1" }, { "strong2", "Strong 2" },
			{ "strong3", "Strong 3" }, { "strong4", "Strong 4" },
		})),
		menu_entry("Relaxing", command_list({
			{ "adjust", "Adjust" }, { "drink", "Drink" }, { "eat", "Eat" }, { "itch", "Itch" },
			{ "legshake", "Leg Shake" }, { "lounge", "Lounge" }, { "read", "Read" },
			{ "scratch", "Scratch" },
		})),
		menu_entry("Directions", command_list({
			{ "apachi", "Apachi" }, { "lookout", "Lookout" }, { "pointba", "Point Back" },
			{ "pointfor", "Point Forward" }, { "pointlef", "Point Left" },
			{ "pointrig", "Point Right" }, { "pointup", "Point Up" },
		})),
	}),
	{ label = "Pets", state = "pets", children = {
		window_entry("Pet Info", windows.pets),
		command_entry("pet-attack", "Attack"), command_entry("pet-behind", "Behind"),
		command_entry("pet-follow", "Follow"), command_entry("pet-guard", "Guard"),
		command_entry("pet-heal", "Heal"), command_entry("pet-report", "Report"),
		command_entry("pet-terminate", "Terminate"), command_entry("pet-wait", "Wait"),
	}},
	menu_entry("Camera", command_list({
		{ "camera-first", "First Person" }, { "camera-trail", "Third Person Trail" },
		{ "camera-locked", "Third Person Locked" }, { "camera-rubber", "Third Person Rubber" },
	})),
	menu_entry("Movement", command_list({
		{ "sit", "Sit" }, { "stand", "Stand" }, { "crawl", "Crawl" }, { "walk", "Walk" }, { "run", "Run" },
	})),
	menu_entry("Normal Actions", command_list({ { "invite", "Invite" }, { "quit", "Quit" } })),
	{ label = "Targeting", targeting = true },
	window_entry("Attack Actions", windows.actions),
	{ label = "Perk Actions", dynamic_perks = true },
	{ label = "Cooldowns Window", cooldown_window = true },
	window_entry("Stats", windows.stats),
	menu_entry("Status Bars", {
		window_entry("Health", windows.health), window_entry("Nano", windows.nano_bar),
		window_entry("Experience", windows.experience), window_entry("Alien Experience", windows.alien_experience),
	}),
	menu_entry("Chat", {
		window_entry("Default Window", windows.chat), window_entry("Combat", windows.combat_chat),
	}),
	window_entry("Tradeskill Kit", windows.tradeskills),
	{ label = "Control Panel" },
	menu_entry("Help/Settings", {
		command_entry("help", "Help"), command_entry("settings", "Settings"),
		window_entry("Chat Configuration", windows.chat_config),
	}),
}

local character_menu = {
	window_entry("Skills", windows.skills),
	window_entry("Faction", windows.faction),
	{ label = "Perks", state = "perks_window", window = windows.perks },
	{ label = "Research" },
}

local map_menu = {
	window_entry("Planet Map", windows.planet_map),
	window_entry("Local Map", windows.playfield_map),
}

local shop_menu = {
	{ label = "Item Store" }, { label = "Daily Rewards" }, { label = "Pending Rewards" },
}

local team_menu = {
	window_entry("Team", windows.team), window_entry("Raid", windows.raid), window_entry("Find Team", windows.team_search),
}

local targeting_entries = {}

local function new_anchor()
	local anchor = ui.load("menu_anchor.xml")
	ui.add(root, anchor)
	return anchor
end

local function populate(anchor, items, path)
	for index, item in ipairs(items) do
		local menu_index
		if item.targeting then
			local child = new_anchor()
			populate(child, targeting_entries, path .. "." .. tostring(index))
			menu_index = ui.menu.submenu(anchor, item.label, child)
		elseif item.children then
			local child = new_anchor()
			populate(child, item.children, path .. "." .. tostring(index))
			menu_index = ui.menu.submenu(anchor, item.label, child)
		elseif item.dynamic_perks then
			menu_index = ui.menu.submenu(anchor, item.label, perk_anchor)
			menu_state.perks_index = menu_index
		elseif item.cooldown_window then
			menu_index = ui.menu.add(anchor, item.label, cooldown_window:shown(), function()
				cooldown_window:show(not cooldown_window:shown())
			end)
			cooldown_menu_items[anchor] = menu_index
		elseif item.window then
			menu_index = ui.menu.destination(anchor, item.label, item.window)
		elseif item.action_ref then
			menu_index = ui.menu.action(anchor, item.label, "game.control_center.activate", item.action_ref)
		elseif item.key and commands[item.key] then
			menu_index = ui.menu.action(anchor, item.label, "game.control_center.activate", commands[item.key])
		else
			menu_index = ui.menu.label(anchor, item.label)
		end
		if item.state then
			menu_state[item.state .. "_index"] = menu_index
		end
	end
end

local window_buttons = {}

local function update_window_selections()
	for _, entry in ipairs(window_buttons) do
		local open = ui.destinations.is_open(entry[2])
		ui.visual_selected(entry[1], open)
		mark(entry[3], open)
	end
end

local function bind_window(name, window)
	local button = ui.find(root, name)
	ui.bind(button, window)
	ui.action(button, "ui.destinations.toggle", window, "left")
	ui.on_click(button, update_window_selections)
	window_buttons[#window_buttons + 1] = { button, window, name }
end

bind_window("aggdef_info", windows.aggdef)
bind_window("inventory", windows.inventory)
bind_window("wear", windows.wear)
bind_window("ncu_window", windows.ncu)
bind_window("nano", windows.nano)
bind_window("missions", windows.missions)
bind_window("friends", windows.friends)

local minibar = ui.require("control_center.minibar").create(root, windows, bind_window)
local rollup_panel = ui.require("control_center.rollup_panel").create(root, dock, minibar)

local AGGDEF_SLIDER_WIDTH = 100
local AGGDEF_INFO_WIDTH = 18
local aggdef_info = ui.find(bar, "aggdef_info")
local aggdef_advanced_shown = false

local function show_aggdef_advanced(advanced)
	if advanced == aggdef_advanced_shown then
		return
	end
	aggdef_advanced_shown = advanced
	ui.visible(aggdef_info, advanced)
	ui.size(aggdef, advanced and AGGDEF_SLIDER_WIDTH - AGGDEF_INFO_WIDTH or AGGDEF_SLIDER_WIDTH, 14)
	if not advanced then
		ui.destinations.close(windows.aggdef)
	end
end

local function update_selections()
	update_window_selections()
	for _, entry in ipairs(top_menus) do
		local selected = ui.menu.is_open(entry.button)
		for _, window in ipairs(entry.windows) do
			selected = selected or ui.destinations.is_open(window)
		end
		ui.visual_selected(entry.button, selected)
		mark(entry.name, selected)
	end
end

local function rebuild_perks()
	ui.menu.clear(perk_anchor)
	for _, perk in ipairs(latest_perks) do
		ui.menu.action_icon(perk_anchor, perk.label, "game.control_center.activate", perk.reference, perk.icon)
	end
end

local function update_menu_state()
	if not latest_state or ui.in_combat() then
		return
	end
	if menu_state.pets_index then
		ui.menu.visible(ui.find(left, "actions"), menu_state.pets_index, latest_state.has_pets)
	end
	if menu_state.perks_window_index then
		ui.menu.visible(ui.find(left, "character"), menu_state.perks_window_index, latest_state.perks_available)
	end
	if menu_state.perks_index then
		ui.menu.visible(ui.find(left, "actions"), menu_state.perks_index, #latest_perks > 0)
	end
	rebuild_perks()
end

function control_center_configure(actions, registered_commands, registered_windows)
	for _, command in ipairs(registered_commands) do
		commands[command.key] = command.reference
	end
	table.sort(registered_windows, function(left_window, right_window)
		if left_window.label == right_window.label then
			return left_window.key < right_window.key
		end
		return left_window.label < right_window.label
	end)
	local addon_entries = {}
	for _, registered_window in ipairs(registered_windows) do
		local window = ui.destinations.require(registered_window.key)
		addon_windows[#addon_windows + 1] = window
		addon_entries[#addon_entries + 1] = window_entry(registered_window.label, window)
	end
	if #addon_entries > 0 then
		actions_menu[#actions_menu + 1] = menu_entry("Addons", addon_entries)
	end
	-- The wings' target buttons and arrows live in Actions -> Targeting.
	targeting_entries = {
		{ label = "Select Self", action_ref = actions.select_self },
		{ label = "Attack / Stop Attack", action_ref = actions.toggle_attack },
		{ label = "Previous Friendly", action_ref = actions.friendly_previous },
		{ label = "Next Friendly", action_ref = actions.friendly_next },
		{ label = "Previous Hostile", action_ref = actions.hostile_previous },
		{ label = "Next Hostile", action_ref = actions.hostile_next },
	}

	local actions_button = ui.find(bar, "actions")
	local character_button = ui.find(bar, "character")
	local map_button = ui.find(bar, "map")
	local shop_button = ui.find(bar, "store")
	local team_button = ui.find(bar, "team")
	-- Keep the Control Center menu behaviour (opens upward, click to cascade) at the screen edge.
	for _, button in ipairs({ actions_button, character_button, map_button, shop_button, team_button }) do
		ui.menu.style(button, "control_center")
	end
	populate(actions_button, actions_menu, "actions")
	populate(character_button, character_menu, "character")
	populate(map_button, map_menu, "map")
	populate(shop_button, shop_menu, "shop")
	populate(team_button, team_menu, "team")
	top_menus = {
		{ name = "actions", button = actions_button, windows = { windows.actions, windows.stats, windows.health, windows.nano_bar,
			windows.experience, windows.alien_experience, windows.chat, windows.combat_chat,
			windows.tradeskills, windows.chat_config, windows.pets } },
		{ name = "character", button = character_button, windows = { windows.skills, windows.perks } },
		{ name = "map", button = map_button, windows = { windows.planet_map, windows.playfield_map } },
		{ name = "team", button = team_button, windows = { windows.team, windows.raid, windows.team_search } },
	}
	for _, window in ipairs(addon_windows) do
		top_menus[1].windows[#top_menus[1].windows + 1] = window
	end
end

local function number(value)
	return value >= 0 and tostring(value) or "--"
end

local function grouped(value)
	if value < 0 then
		return "--"
	end
	local text = tostring(value)
	local first = #text % 3
	if first == 0 then
		first = 3
	end
	local result = string.sub(text, 1, first)
	for index = first + 1, #text, 3 do
		result = result .. "," .. string.sub(text, index, index + 2)
	end
	return result
end

function control_center_refresh()
	update_selections()
	if rollup_panel then rollup_panel:refresh() end
end

-- Since API 0.2.0 these are this package's own Options settings (package.xml); the
-- Control Center state no longer carries the built-in package's preferences.
local function apply_settings()
	local toggle = ui.settings.toggle
	ui.visible(minibar, toggle("minibar"))
	if rollup_panel then rollup_panel:show(toggle("rollup"), ui.settings.number("rollup-opacity") / 100) end
	show_aggdef_advanced(toggle("advanced-aggdef"))
end

apply_settings()
ui.settings.on_change(apply_settings)

function control_center_apply(state, perks)
	latest_state = state
	latest_perks = perks
	cooldown_window:set_perks(perks)
	ui.text(ncu, number(state.used_ncu) .. " / " .. number(state.max_ncu))
	local used, maximum = state.used_ncu, state.max_ncu
	local fraction = (used >= 0 and maximum > 0) and math.min(1, used / maximum) or 0
	-- The meter stretches, so measure it; before the first layout, estimate from the window.
	local meter_width = ui.width(ncu_meter)
	if not meter_width or meter_width <= 0 then
		meter_width = NCU_METER_WIDTH
	end
	local fill = math.floor(meter_width * fraction + 0.5)
	ui.visible(ncu_meter_fill, fill > 0)
	ui.size(ncu_meter_fill, math.max(1, fill), -1)
	ui.tooltip(ncu_window, string.format("NCU: %s of %s used", number(used), number(maximum)))
	ui.text(credits, grouped(state.credits))
	if state.aggdef >= AGGDEF_MIN then
		ui.progress(aggdef, aggdef_progress(state.aggdef))
		show_aggdef(state.aggdef)
	end
	update_selections()
	update_menu_state()
end

ui.on_lockdown(function(locked)
	if not locked then
		update_menu_state()
		update_selections()
	end
end)
