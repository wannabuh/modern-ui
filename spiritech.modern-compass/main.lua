-- Modern Compass: flat direction strip with waypoint marker and distance (role prk.compass).
-- Defaults to the Player Bars width at the bottom centre. Drag to move; drag an edge or
-- corner to resize (letters grow with the height). Position and size are remembered.
pcall(ui.require, "spiritech.modern-common/screenfit") -- keep window positions through fullscreen changes
local Transform = ui.require("core.transform")
local Placement = ui.require("core.placement")

local WIDTH, HEIGHT = 520, 22 -- default size; WIDTH matches Player Bars
-- Resizable by dragging any edge or corner; the size is remembered with the position.
local MIN_WIDTH, MAX_WIDTH = 200, 1600
local MIN_HEIGHT, MAX_HEIGHT = 16, 48
-- Player Bars: bottom inset 200, height 60 (20 + 3 + 20 + 3 + 14); then the same 3px gap.
local BOTTOM_INSET = 200 + 60 + 3
local SPAN = math.pi -- visible arc across the strip (180 degrees)
local TURN = math.pi * 2
local ACCENT = "#4FB3BF"

local root = ui.load("window.xml")
ui.root(root)
ui.limits(root, MIN_WIDTH, MIN_HEIGHT, MAX_WIDTH, MAX_HEIGHT)
ui.request_size(root, WIDTH, HEIGHT)
-- Initial placement only; a saved (moved) position takes over afterwards.
ui.align(root, "center", "end")
ui.borders(root, 0, 0, 0, BOTTOM_INSET)

local band = ui.find(root, "compass_band")
local distance_box = ui.find(root, "compass_distance_box")
local distance_label = ui.find(root, "compass_distance")
local band_width, band_height = WIDTH - 2, HEIGHT - 2
local scale = band_width / SPAN -- pixels per radian
local layout -- defined below, once the marks exist

local placement = Placement.attach(root, {
	only_moved = true,
	resize = function(width, height) if layout then layout(width, height) end end,
})
Transform.attach(root, {
	resizable = true,
	resize = function(width, height) if layout then layout(width, height) end end,
	draggable = function() return true end,
	finished = function(completed)
		if completed then placement:changed() end
	end,
})
ui.require("spiritech.modern-common/centre").attach(root) -- snaps onto the screen's centre line

local function load(file, name)
	local view = ui.load(file)
	ui.add(band, view)
	return ui.find(view, name)
end

-- Directions, using the native convention: angles from +X (east) toward +Z (north).
local marks = {}
local LETTERS = {
	{ "N", math.pi / 2, true }, { "NE", math.pi / 4 }, { "E", 0, true }, { "SE", -math.pi / 4 },
	{ "S", -math.pi / 2, true }, { "SW", -3 * math.pi / 4 }, { "W", math.pi, true }, { "NW", 3 * math.pi / 4 },
}
for _, spec in ipairs(LETTERS) do
	local view = load("letter.xml", "letter")
	ui.text(view, spec[1])
	if spec[3] then
		ui.text_color(view, spec[1] == "N" and "#FFFFFF" or "#D5DAE1")
	else
		ui.text_color(view, "#8B95A3")
	end
	marks[#marks + 1] = { view = view, angle = spec[2], kind = "letter", major = spec[3], width = 0, height = 13 }
end
-- Ticks every 15 degrees, skipping the lettered 45-degree positions.
for step = 0, 23 do
	if step % 3 ~= 0 then
		local view = load("tick.xml", "tick")
		marks[#marks + 1] = { view = view, angle = step * math.pi / 12, kind = "tick", width = 1, height = 4 }
	end
end

-- Centre line marks the direction you are facing.
local centre_line = load("tick.xml", "tick")
ui.fill_color(centre_line, "#E8ECF1")

-- Waypoint marker: the game's own compass waypoint artwork (as on the built-in compass).
local waypoint = load("waypoint.xml", "waypoint_icon")
ui.visible(waypoint, false)
local WAYPOINT_GRAPHIC = "GFX_GUI_COMPASS_WAYPOINT"
local waypoint_size = 13 -- replaced by the artwork's own width when the client reports it
do
	local ok, width = pcall(function() return ui.compass.graphic_width(WAYPOINT_GRAPHIC) end)
	if ok and type(width) == "number" and width > 0 then waypoint_size = width end
end

local last_reading

-- Fits everything to a new strip size. Letter size follows the strip height.
layout = function(width, height)
	width = math.floor(math.max(MIN_WIDTH, math.min(MAX_WIDTH, width)) + 0.5)
	height = math.floor(math.max(MIN_HEIGHT, math.min(MAX_HEIGHT, height)) + 0.5)
	-- request_size keeps the min/max limits (ui.size would pin them and disable resizing).
	ui.limits(root, MIN_WIDTH, MIN_HEIGHT, MAX_WIDTH, MAX_HEIGHT)
	ui.request_size(root, width, height)
	local chosen_width, chosen_height = ui.chosen_width(root), ui.chosen_height(root)
	if chosen_width > 0 then width = chosen_width end
	if chosen_height > 0 then height = chosen_height end
	band_width, band_height = width - 2, height - 2
	scale = band_width / SPAN
	local major = math.max(10, math.min(20, math.floor(height * 0.5 + 0.5)))
	for _, mark in ipairs(marks) do
		if mark.kind == "letter" then
			local size = mark.major and major or major - 1
			ui.font_size(mark.view, size)
			mark.height = size + 2
			mark.width = 0 -- re-measured on the next update
		else
			mark.height = math.max(3, math.floor(band_height * 0.2 + 0.5))
			ui.size(mark.view, 1, mark.height)
		end
	end
	ui.size(centre_line, 1, math.max(4, math.floor(band_height * 0.25 + 0.5)))
	ui.place(centre_line, math.floor(band_width / 2), 0)
	-- native size, shrunk only if the strip is shorter than the artwork
	local marker = math.min(waypoint_size, band_height)
	ui.size(waypoint, marker, marker)
	if last_reading then compass_apply(last_reading) end
end

local function wrap(angle)
	return (angle + math.pi) % TURN - math.pi
end

-- Horizontal position on the strip for a world direction, or nil when off the strip.
local function column(heading, angle)
	local offset = wrap(heading - angle)
	return band_width / 2 + offset * scale, math.abs(offset) <= SPAN / 2
end

layout(WIDTH, HEIGHT)

function compass_place(screen_width)
	-- Placement is handled above (bottom centre, paired with Player Bars).
end

function compass_apply(reading)
	last_reading = reading
	if not reading.has_heading then
		return
	end
	local heading = reading.heading

	for _, mark in ipairs(marks) do
		if mark.kind == "letter" and mark.width == 0 then
			mark.width = ui.text_width(mark.view)
		end
		local x, on_strip = column(heading, mark.angle)
		local left = math.floor(x - mark.width / 2 + 0.5)
		local fits = on_strip and left >= 2 and left + mark.width <= band_width - 2
		ui.visible(mark.view, fits)
		if fits then
			if mark.kind == "letter" then
				ui.place(mark.view, left, math.floor((band_height - mark.height) / 2))
			else
				ui.place(mark.view, left, band_height - mark.height)
			end
		end
	end

	local has_waypoint = reading.has_waypoint and reading.has_position and reading.waypoint_playfield == reading.playfield
	ui.visible(waypoint, has_waypoint)
	ui.visible(distance_box, has_waypoint)
	if has_waypoint then
		local dx, dz = reading.waypoint_x - reading.x, reading.waypoint_z - reading.z
		local bearing = math.atan(dz, dx)
		local x = column(heading, bearing)
		-- Behind you: pin the marker to the nearer edge of the strip.
		local marker = math.min(waypoint_size, band_height)
		x = math.max(0, math.min(band_width - marker, math.floor(x - marker / 2 + 0.5)))
		ui.place(waypoint, x, math.floor((band_height - marker) / 2))
		local distance = math.sqrt(dx * dx + dz * dz)
		ui.text(distance_label, distance >= 1000 and string.format("%.1fk", distance / 1000) or string.format("%dm", math.floor(distance + 0.5)))
		ui.tooltip(root, string.format("Waypoint: %.0f, %.0f", reading.waypoint_x, reading.waypoint_z))
	else
		ui.tooltip(root, "")
	end
end
