-- Modern Map: square, title-less local map (role prk.playfield-map).
-- Based on the built-in PlayfieldMap package; keeps its native callback contract.
pcall(ui.require, "spiritech.modern-common/screenfit") -- keep window positions through fullscreen changes
local Window = ui.require("core.window")

-- Plate = 3px border on left/top/right, map square, 18px info strip. Matches content.xml.
local EXTRA_WIDTH, EXTRA_HEIGHT = 6, 21
local CONTROLS_HEIGHT = 140 -- pfmap_controls (136) + its top gap (4)
local DEFAULT_SIZE, MINIMUM_SIZE = 220, 120 -- side of the square map itself
local EDGE = 0.92 -- off-map markers are pinned at this fraction of the half-width
-- Default spot: top-right corner of the screen.
local SCREEN_INSET, DEFAULT_TOP = 8, 8

local content = ui.load("content.xml")
local plate = ui.find(content, "pfmap_plate")
local map_view = ui.find(content, "pfmap_view")
local surface = ui.find(content, "pfmap_surface")
local controls = ui.find(content, "pfmap_controls")
local areas_button = ui.find(content, "pfmap_show_areas")
local unavailable = ui.find(content, "pfmap_unavailable")
local coords_label = ui.find(content, "pfmap_coords")
local heading_label = ui.find(content, "pfmap_heading")
local context_menu = ui.load("menu.xml")
ui.add(content, context_menu)

local view = game.map_surface
view.attach(surface, true)
game.playfield_map.coordinates(ui.find(content, "pfmap_x"), ui.find(content, "pfmap_z"))

local opened, available, buttons, areas = false, true, false, false
local first_pending, centre_pending, follow_pending = false, false, false
local previous_x, previous_y, previous_character
local zoom, wheel, extras = 0, 0, 0
local size = DEFAULT_SIZE -- side length of the square map
local shown_size
local frame

local function window_width()
	return size + EXTRA_WIDTH
end

local function window_height()
	return size + EXTRA_HEIGHT + (buttons and CONTROLS_HEIGHT or 0)
end

local function publish(changed)
	ui.publish("buttons", tostring(buttons))
	if changed then
		extras = extras + 1
		ui.publish("extras", tostring(extras))
	end
end

-- Keep the map square. Resizing either edge changes both dimensions.
local function layout(window, width, height)
	local control_height = buttons and CONTROLS_HEIGHT or 0
	local from_width = width - EXTRA_WIDTH
	local from_height = height - EXTRA_HEIGHT - control_height
	if not shown_size then
		size = math.min(from_width, from_height)
	elseif from_width ~= shown_size then
		size = from_width
	elseif from_height ~= shown_size then
		size = from_height
	end
	local screen_width, screen_height = view.read("screen_width"), view.read("screen_height")
	local maximum = math.min((screen_width > 0 and screen_width or 4096) - EXTRA_WIDTH,
		(screen_height > 0 and screen_height or 4096) - EXTRA_HEIGHT - control_height)
	size = math.floor(math.max(MINIMUM_SIZE, math.min(maximum, size)))
	ui.limits(window.root, MINIMUM_SIZE + EXTRA_WIDTH, MINIMUM_SIZE + EXTRA_HEIGHT + control_height,
		maximum + EXTRA_WIDTH, maximum + EXTRA_HEIGHT + control_height)
	ui.request_size(window.root, window_width(), window_height())
	ui.size(map_view, size, size)
	ui.size(plate, window_width(), size + EXTRA_HEIGHT)
	ui.size(content, window_width(), window_height())
	window:fit_title(window_width(), false)
	if shown_size ~= size then
		follow_pending = true
	end
	shown_size = size
end

local function show_buttons(value)
	buttons = value
	ui.visible(controls, buttons)
	if frame then
		frame:relayout(window_width(), window_height())
	end
	publish(false)
end

function playfield_map_toggle_buttons()
	show_buttons(not buttons)
	publish(true)
end

frame = Window.create({
	template = "frame.xml",
	title = "Local Map",
	content = content,
	width = DEFAULT_SIZE + EXTRA_WIDTH,
	height = DEFAULT_SIZE + EXTRA_HEIGHT,
	horizontal = "end",
	close = false,
	pin = false,
	menu = false,
	layout = layout,
})
ui.root(frame.root)
-- Initial placement only; a saved (moved) position takes over afterwards.
ui.borders(frame.root, 0, DEFAULT_TOP, SCREEN_INSET, 0)

function playfield_map_context(x, y)
	if not opened then
		return
	end
	ui.menu.clear(context_menu)
	ui.menu.add(context_menu, "Show buttons", buttons, playfield_map_toggle_buttons)
	ui.menu.show_at(context_menu, x, y)
end

function playfield_map_configure(first_open, areas_text, build_tooltip, war_tooltip)
	first_pending = first_open
	ui.text(areas_button, areas_text)
	ui.tooltip(ui.find(content, "pfmap_build"), build_tooltip)
	ui.tooltip(ui.find(content, "pfmap_war"), war_tooltip)
end

ui.on_click(areas_button, function() areas = not areas end)
ui.bind(ui.find(content, "pfmap_add_waypoint"), 1)
ui.action(ui.find(content, "pfmap_add_waypoint"), "game.playfield_map.add_waypoint", 1, "left")
ui.bind(ui.find(content, "pfmap_remove_waypoint"), 1)
ui.action(ui.find(content, "pfmap_remove_waypoint"), "game.playfield_map.remove_waypoint", 1, "left")

function playfield_map_restore(saved_buttons)
	show_buttons(saved_buttons)
end

function playfield_map_visibility(shown)
	opened = shown
	centre_pending, follow_pending = shown, false
	previous_x, previous_y, previous_character = nil, nil, nil
	if not shown then
		available = true
		ui.visible(unavailable, false)
		publish(true)
	end
end

function playfield_map_wheel(turn, x, y)
	if not opened or not available then
		return
	end
	wheel = wheel + turn
	local detents = wheel < 0 and math.ceil(wheel) or math.floor(wheel)
	wheel = wheel - detents
	local level = math.max(-6, math.min(6, zoom + detents))
	if level == zoom then
		return
	end
	zoom = level
	view.zoom(2 ^ (zoom / 3), x, y)
end

local function centre(facts)
	local x = facts.has_character and facts.x or facts.width / 2
	local y = facts.has_character and facts.y or facts.height / 2
	view.pan(x - view.read("width") / 2, y - view.read("height") / 2)
end

---------------------------------------------------------------------------
-- Markers
---------------------------------------------------------------------------
local graphics = {
	marked = "GFX_GUI_MAP_BIG_ARROW",
	selected = "GFX_GUI_MAP_ARROW_SELECTED",
	monster = "GFX_GUI_MAPSQUARE_MONSTER",
	team = "GFX_GUI_MAPSQUARE_TEAMMEMBER",
	clan = "GFX_GUI_MAPSQUARE_CLAN",
	omni = "GFX_GUI_MAPSQUARE_OMNI",
	neutral = "GFX_GUI_MAPSQUARE_NEUTRAL",
	door = "GFX_GUI_MAPFLAG_CYAN",
	shop = "GFX_GUI_MAPSQUARE_SHOP",
	mission = "GFX_GUI_MAPSQUARE_MISSION",
	player = "GFX_GUI_MAP_ARROW",
}
local faces = { marked = true, selected = true, player = true }
-- Kinds worth keeping visible on the map edge when they are off the map.
local pinned = { mission = true, marked = true, selected = true, team = true }

local DIRECTIONS = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" }

local function show_heading(facing)
	if not facing then
		ui.text(heading_label, "")
		return
	end
	-- Map facing 0 points up (north) and increases clockwise.
	local degrees = math.floor(math.deg(facing) % 360 + 0.5) % 360
	local direction = DIRECTIONS[math.floor((degrees + 22.5) / 45) % 8 + 1]
	ui.text(heading_label, string.format("%s %d°", direction, degrees))
end

function playfield_map_markers(readings)
	-- Visible circle, in map content coordinates.
	-- The map keeps the player centred, so use the player's marker as the centre.
	local width, height = view.read("width"), view.read("height")
	local half = math.min(width, height) / 2
	local cx, cy, player_facing
	for _, marker in ipairs(readings) do
		if marker.kind == "player" then
			cx, cy, player_facing = marker.x, marker.y, marker.facing
			break
		end
	end

	view.markers_begin()
	for _, marker in ipairs(readings) do
		if marker.kind == "wedge" then
			local direction = marker.facing - math.pi / 2
			view.fan(marker.x, marker.y, marker.radius,
				direction - marker.half_angle, direction + marker.half_angle, "#26FFFFFF")
		else
			local graphic = graphics[marker.kind]
			if graphic then
				local x, y = marker.x, marker.y
				local facing = faces[marker.kind] and marker.facing or 0
				if pinned[marker.kind] and cx and half > 0 then
					local dx, dy = x - cx, y - cy
					local reach = math.max(math.abs(dx), math.abs(dy))
					if reach > half * EDGE then
						x = cx + dx / reach * half * EDGE
						y = cy + dy / reach * half * EDGE
					end
				end
				view.sprite(graphic, x, y, facing, 1)
			end
		end
	end
	view.markers_end()
	show_heading(player_facing)
end

---------------------------------------------------------------------------
-- Coordinates (read-only character API; skipped if this role can't use it)
---------------------------------------------------------------------------
if game.character and game.character.subscribe then
	pcall(game.character.subscribe, "self", "", function(update, character)
		if character and character.x and character.z then
			ui.text(coords_label, string.format("%.0f, %.0f", character.x, character.z))
		else
			ui.text(coords_label, "")
		end
	end)
end

---------------------------------------------------------------------------
-- Map updates (same follow/availability rules as the built-in map)
---------------------------------------------------------------------------
function playfield_map_update(facts)
	if not opened then
		return
	end
	if facts.changed then
		centre_pending, follow_pending = true, false
		previous_x, previous_y, previous_character = nil, nil, nil
	end
	local resizing = false
	if first_pending then
		first_pending = false
		size = DEFAULT_SIZE
		frame:relayout(window_width(), window_height())
		resizing = true
	end
	local old_size = shown_size
	frame:relayout(window_width(), window_height())
	resizing = resizing or old_size ~= shown_size
	ui.enabled(areas_button, facts.land_control)
	if not facts.land_control then
		areas = false
	end
	ui.selected(areas_button, areas)
	local show_areas = areas and facts.has_areas
	local accessible = facts.accessible or show_areas
	if accessible ~= available then
		available = accessible
		ui.visible(unavailable, not available)
		if available then
			centre_pending = true
		else
			view.pan(0, 0)
			game.playfield_map.clear()
		end
	end
	if not available then
		if facts.changed then
			game.playfield_map.clear()
		end
		return
	end
	if centre_pending then
		if resizing or view.read("width") <= 0 or view.read("height") <= 0 then
			return
		end
		centre(facts)
		centre_pending = false
	elseif not resizing then
		follow_pending = follow_pending or facts.has_character and
			(not previous_character or facts.x ~= previous_x or facts.y ~= previous_y)
		previous_x, previous_y, previous_character = facts.x, facts.y, facts.has_character
		if follow_pending and view.read("dragged") == 0 then
			follow_pending = false
			centre(facts)
		end
	end
	game.playfield_map.render(show_areas)
end

show_buttons(buttons)
