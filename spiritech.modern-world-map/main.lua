-- Modern World Map: flat planet map (role prk.planet-map).
-- Same behaviour as the built-in map (zoom levels, centring, map choice, right-click
-- teleport where allowed, saved state), restyled:
--   * the shared flat frame; title shows the current map
--   * the old button rows become a 30px toolbar underneath the map:
--       Newland Desert                       −  2/5  +  │  Me  Mission
--   * the game's own player and mission markers; switch maps from the title menu
-- "Show buttons" (title menu / right-click) still hides the toolbar.
pcall(ui.require, "spiritech.modern-common/screenfit") -- keep window positions through fullscreen changes
local Window = ui.require("core.window")
local Theme = ui.require("spiritech.modern-common/theme")

local ME_COLOR, MISSION_COLOR = "#4FB3BF", "#F0C060" -- Me / Mission button colours

local content = ui.load("content.xml")
local surface = ui.find(content, "planet_tiles")
local toolbar = ui.find(content, "planet_toolbar")
local zoom_in = ui.find(content, "planet_zoom_in")
local zoom_out = ui.find(content, "planet_zoom_out")
local zoom_level = ui.find(content, "planet_zoom_level")
local character = ui.find(content, "planet_centre_character")
local quest = ui.find(content, "planet_centre_quest")
local location = ui.find(content, "planet_location")
local choices_menu = ui.load("menu.xml")
local context_menu = ui.load("menu.xml")
ui.add(content, choices_menu)
ui.add(content, context_menu)
local view = game.map_surface
view.attach(surface, false)
local opened, buttons, first_time = false, true, true
local first_pending, centre_pending = false, false
local zoom, records, revision, extras = 0, 0, -1, 0
local frame
local menu_character, menu_quest
local rebuild_menu
local current_map = ""

local function publish(changed)
	ui.publish("buttons", tostring(buttons))
	ui.publish("zoom", tostring(zoom))
	if changed then
		extras = extras + 1
		ui.publish("extras", tostring(extras))
	end
end

local function show_buttons(value)
	buttons = value
	ui.visible(toolbar, buttons)
	publish(false)
end

function planet_map_toggle_buttons()
	show_buttons(not buttons)
	ui.menu.checked(frame.icon, 4, buttons)
	publish(true)
end

local function layout(window, width, height)
	local screen_width, screen_height = view.read("screen_width"), view.read("screen_height")
	local maximum_width = screen_width > 0 and math.min(1600, screen_width) or 1600
	local maximum_height = screen_height > 0 and math.min(1600, screen_height) or 1600
	ui.limits(window.root, math.min(160, maximum_width), math.min(160, maximum_height), maximum_width, maximum_height)
	ui.request_size(window.root, width, height)
	window:fit_title(ui.chosen_width(window.root), true)
	window:fit_content(ui.chosen_width(window.root), ui.chosen_height(window.root))
end

frame = Window.create({
	template = Theme.WINDOW_TEMPLATE,
	title = "World Map",
	content = content,
	width = 411,
	height = 433,
	x = 95,
	y = 72,
	layout = layout,
})
ui.root(frame.root)

local function set_title()
	local title = current_map ~= "" and ("World Map  ·  " .. current_map) or "World Map"
	ui.text(ui.find(frame.root, "window_title"), title)
end

function planet_map_centre(subject)
	if game.planet_map.point(subject) == 0 then
		return
	end
	view.pan(game.planet_map.point(subject .. "_x") - view.read("width") / 2,
		game.planet_map.point(subject .. "_y") - view.read("height") / 2)
end

local function compose_menu(anchor)
	ui.menu.clear(anchor)
	if game.planet_map.point("character") ~= 0 then
		ui.menu.add(anchor, "Center on player", false, function() planet_map_centre("character") end)
	else
		ui.menu.label(anchor, "Center on player")
	end
	if game.planet_map.point("quest") ~= 0 then
		ui.menu.add(anchor, "Center on mission", false, function() planet_map_centre("quest") end)
	else
		ui.menu.label(anchor, "Center on mission")
	end
	ui.menu.submenu(anchor, "Select Map", choices_menu)
	ui.menu.add(anchor, "Show buttons", buttons, planet_map_toggle_buttons)
end

rebuild_menu = function()
	menu_character = game.planet_map.point("character") ~= 0
	menu_quest = game.planet_map.point("quest") ~= 0
	compose_menu(frame.icon)
	ui.menu.separator(frame.icon)
	ui.menu.close(frame.icon, frame.root)
end

function planet_map_context(x, y, teleport)
	if not opened then
		return
	end
	compose_menu(context_menu)
	if teleport ~= 0 then
		ui.menu.separator(context_menu)
		ui.menu.action(context_menu, "Teleport To Location", "game.planet_map.teleport", teleport)
	end
	ui.menu.show_at(context_menu, x, y)
end

function planet_map_choices(choices)
	ui.menu.clear(choices_menu)
	for _, choice in ipairs(choices) do
		if choice.chosen then current_map = choice.name end
		ui.menu.add(choices_menu, choice.name, choice.chosen, function()
			game.planet_map.choose(choice.index)
		end)
	end
	set_title()
	rebuild_menu()
end

local function enable(button, enabled, color)
	ui.enabled(button, enabled)
	ui.text_color(button, enabled and color or "#5E6875")
end

local function refresh_buttons()
	enable(zoom_in, zoom < records - 1, Theme.color.text)
	enable(zoom_out, records > 0 and zoom > 0, Theme.color.text)
	enable(character, game.planet_map.point("character") ~= 0, ME_COLOR)
	enable(quest, game.planet_map.point("held_quest") ~= 0, MISSION_COLOR)
	ui.text(zoom_level, records > 0 and string.format("%d/%d", zoom + 1, records) or "")
	if menu_character ~= (game.planet_map.point("character") ~= 0)
		or menu_quest ~= (game.planet_map.point("quest") ~= 0) then
		rebuild_menu()
	end
	ui.menu.checked(frame.icon, 4, buttons)
end

local function change_zoom(step)
	local chosen = math.max(0, math.min(records - 1, zoom + step))
	if records == 0 or chosen == zoom then
		return
	end
	local x, y = view.read("x"), view.read("y")
	zoom = chosen
	game.planet_map.record(zoom)
	view.pan(x, y)
	refresh_buttons()
	publish(true)
end

ui.on_click(zoom_in, function() change_zoom(1) end)
ui.on_click(zoom_out, function() change_zoom(-1) end)
ui.on_click(character, function() planet_map_centre("character") end)
ui.on_click(quest, function() planet_map_centre("quest") end)

function planet_map_restore(saved_zoom, saved_buttons, saved_first_time)
	zoom = math.max(0, saved_zoom)
	first_time = saved_first_time
	show_buttons(saved_buttons)
	ui.menu.checked(frame.icon, 4, buttons)
end

function planet_map_visibility(shown)
	opened = shown
	first_pending = shown and first_time
	centre_pending = shown
	if not shown then
		first_time = false
		publish(true)
	end
end

function planet_map_update(current_revision, count)
	if not opened then
		return
	end
	records = count
	if revision ~= current_revision then
		revision = current_revision
		zoom = math.max(0, math.min(zoom, records - 1))
		if records > 0 then
			game.planet_map.record(zoom)
		end
		view.pan(0, 0)
		centre_pending = true
		publish(false)
	end
	if first_pending then
		first_pending = false
		frame:resize(411, 433)
		ui.place(frame.root, 95, 72)
	elseif centre_pending and view.read("width") > 0 and view.read("height") > 0 then
		centre_pending = false
		planet_map_centre("character")
	end
	frame:resize(ui.chosen_width(frame.root), ui.chosen_height(frame.root))
	refresh_buttons()
	view.markers_begin()
	if game.planet_map.point("quest") ~= 0 then
		view.sprite("GFX_GUI_PLANETMAP_MISSION_MARKER2", game.planet_map.point("quest_x"), game.planet_map.point("quest_y"), 0)
	end
	if game.planet_map.point("character") ~= 0 then
		view.sprite("GFX_GUI_PLANETMAP_PLAYER_MARKER", game.planet_map.point("character_x"), game.planet_map.point("character_y"), 0)
	end
	view.markers_end()
end

-- The zone you're in, by name (playfields.lua, generated from the client database).
game.character.subscribe("self", "", function(_, me)
	local id = me and me.playfield
	local name = id and PLAYFIELDS and PLAYFIELDS[id]
	ui.text(location, name or (id and ("Zone " .. id)) or "")
end)

show_buttons(buttons)
set_title()
rebuild_menu()
refresh_buttons()
