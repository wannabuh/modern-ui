-- Modern World Map: flat planet map (role prk.planet-map).
-- Same behaviour as the built-in map (zoom levels, centring, map choice, right-click
-- teleport where allowed, saved state), restyled:
--   * the shared flat frame; title shows the current map
--   * the old button rows become a 30px toolbar underneath the map:
--       Newland Desert            −  2/5  +   [==slider==]   │  Me  Mission
--   * the game's own player and mission markers; switch maps from the title menu
-- "Show buttons" (title menu / right-click) still hides the toolbar.
-- "Me" (or "Follow player" in the menu) centres on you and keeps following as you move;
-- dragging the map or clicking "Me" again stops following.
-- Two zooms: −/+ switch between the map's images (levels, as the built-in map), the slider
-- magnifies the current image (1x to 4x). Both keep the spot in the middle of the view put.
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
local zoom_slider = ui.find(content, "planet_zoom")
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
local following = false
local set_following

-- Map units (pan offsets, view width/height, marker positions) are the current level's image
-- pixels, so the middle of the view is x + width / 2 at any scale.
local MAX_SCALE = 4 -- slider: magnification of the current image, 1x to MAX_SCALE
local levels = {} -- [level + 1] = { w, h }: each level's image size at scale 1
local scale = 1
local calibrate_pending = true
local PLAYER_RADIUS, PLAYER_OUTLINE = 5, 1.5 -- player dot, in screen pixels at any magnification
local PLAYER_COLOR = "#FFFFD84A" -- yellow

-- Mission marker (the game's sprite) and the player as a flat dot. Sprites grow with the
-- slider's magnification and have no size option; the dot's radius is divided by it instead.
local function draw_markers()
	view.markers_begin()
	if game.planet_map.point("quest") ~= 0 then
		view.sprite("GFX_GUI_PLANETMAP_MISSION_MARKER2", game.planet_map.point("quest_x"), game.planet_map.point("quest_y"), 0)
	end
	if game.planet_map.point("character") ~= 0 then
		local x, y = game.planet_map.point("character_x"), game.planet_map.point("character_y")
		view.fan(x, y, (PLAYER_RADIUS + PLAYER_OUTLINE) / scale, 0, 2 * math.pi, "#FF0D1015")
		view.fan(x, y, PLAYER_RADIUS / scale, 0, 2 * math.pi, PLAYER_COLOR)
	end
	view.markers_end()
end

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
	ui.menu.add(anchor, "Follow player", following, function() set_following(not following) end)
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
	ui.text(zoom_level, records > 0 and string.format("%d/%d", zoom + 1, records) or "")
	enable(character, game.planet_map.point("character") ~= 0, ME_COLOR)
	enable(quest, game.planet_map.point("held_quest") ~= 0, MISSION_COLOR)
	ui.enabled(zoom_slider, records > 0)
	if menu_character ~= (game.planet_map.point("character") ~= 0)
		or menu_quest ~= (game.planet_map.point("quest") ~= 0) then
		rebuild_menu()
	end
	ui.menu.checked(frame.icon, 4, buttons)
	ui.menu.checked(frame.icon, 5, following)
end

-- Follow mode: the "Me" button reads "● Me" while the map follows you.
set_following = function(value)
	following = value
	ui.text(character, following and "● Me" or "Me")
	ui.tooltip(character, following and "Following you (drag the map or click to stop)" or "Center on you and follow")
	if following then planet_map_centre("character") end
	refresh_buttons()
end

local function follow()
	if not following or game.planet_map.point("character") == 0 then return end
	if view.read("dragged") ~= 0 then -- you grabbed the map: stop following
		set_following(false)
		return
	end
	if view.read("width") <= 0 or view.read("height") <= 0 then return end
	local x = game.planet_map.point("character_x") - view.read("width") / 2
	local y = game.planet_map.point("character_y") - view.read("height") / 2
	if math.abs(view.read("x") - x) > 1 or math.abs(view.read("y") - y) > 1 then
		view.pan(x, y) -- near the map edges the pan is clamped; harmless to repeat
	end
end

-- One level's image size: zoom far in so the image overflows the view, pan past the far
-- corner (the pan is clamped to the image) and read where it stopped.
local function measure(index)
	game.planet_map.record(index)
	view.zoom(16, 0, 0)
	view.pan(1e7, 1e7)
	return view.read("x") + view.read("width"), view.read("y") + view.read("height")
end

local function calibrate()
	levels = {}
	local log = {}
	for index = 0, records - 1 do
		local w, h = measure(index)
		log[#log + 1] = string.format("%d:%.0fx%.0f", index, w, h)
		local previous = levels[index]
		if not (w > 0 and h > 0) or (previous and w <= previous.w) then
			-- Unreadable: assume each level doubles the previous one.
			w = previous and previous.w * 2 or 1024
			h = previous and previous.h * 2 or 1024
			log[#log] = log[#log] .. "?"
		end
		levels[index + 1] = { w = w, h = h }
	end
	pcall(ui.storage.write, "zoom_log", table.concat(log, " ")) -- for diagnosis
	calibrate_pending = false
end

-- Where the middle of the view is, as a share of the current image (nil if unknown).
local function centre_share()
	local current = levels[zoom + 1]
	if not current then return nil end
	return (view.read("x") + view.read("width") / 2) / current.w,
		(view.read("y") + view.read("height") / 2) / current.h
end

local function pan_to_share(u, v)
	local current = levels[zoom + 1]
	if not (u and current) then return end
	view.pan(u * current.w - view.read("width") / 2, v * current.h - view.read("height") / 2)
end

-- Slider: magnify the current image, keeping the middle of the view put.
local function set_scale(value)
	local u, v = centre_share()
	scale = math.max(1, math.min(MAX_SCALE, value))
	view.zoom(scale, 0, 0)
	pan_to_share(u, v)
	ui.progress(zoom_slider, math.log(scale) / math.log(MAX_SCALE))
	draw_markers()
end

-- −/+: switch image (level), keeping the middle of the view on the same spot and the slider's magnification.
local function change_zoom(step)
	local chosen = math.max(0, math.min(records - 1, zoom + step))
	if records == 0 or chosen == zoom then
		return
	end
	local u, v = centre_share()
	zoom = chosen
	game.planet_map.record(zoom)
	view.zoom(scale, 0, 0)
	pan_to_share(u, v)
	draw_markers()
	refresh_buttons()
	publish(true)
end

ui.on_value_changed(zoom_slider, function(position)
	set_scale(MAX_SCALE ^ position)
end)
ui.on_value_committed(zoom_slider, function()
	ui.storage.write("zoom_scale", string.format("%.3f", scale))
end)
ui.on_click(zoom_in, function() change_zoom(1) end)
ui.on_click(zoom_out, function() change_zoom(-1) end)
ui.on_click(character, function() set_following(not following) end)
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
		calibrate_pending = true -- another map: measure its levels once the view has a size
		publish(false)
	end
	if first_pending then
		first_pending = false
		frame:resize(411, 433)
		ui.place(frame.root, 95, 72)
	elseif centre_pending and view.read("width") > 0 and view.read("height") > 0 then
		centre_pending = false
		if calibrate_pending and records > 0 then
			calibrate()
			game.planet_map.record(zoom) -- measuring visited every level
			view.pan(0, 0)
			set_scale(tonumber(ui.storage.read("zoom_scale")) or 1)
		end
		planet_map_centre("character")
	end
	follow()
	frame:resize(ui.chosen_width(frame.root), ui.chosen_height(frame.root))
	refresh_buttons()
	draw_markers()
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
