-- Player Bars: one movable panel with health, nano, XP and alien XP.
-- Data comes from game.character (read-only). Pair with the
-- "Hidden (use Player Bars addon)" status-bars provider to remove the built-in bars.
pcall(ui.require, "spiritech.modern-common/screenfit") -- keep window positions through fullscreen changes
local Theme = ui.require("spiritech.modern-common/theme")
local Move = ui.require("core.move")
local Placement = ui.require("core.placement")

local WIDTH = 520
local GAP = 3 -- gap between bars; match panel.xml
local BOTTOM_INSET = 200 -- initial distance from the bottom of the screen
local VITAL_HEIGHT, PROGRESS_HEIGHT = 20, 14
local ORDER = { "health", "nano", "xp", "alien" }
local LABELS = { health = "Health", nano = "Nano", xp = "XP", alien = "Alien XP" }

local root = ui.load("root.xml")
ui.root(root)
local panel = ui.load("panel.xml")
ui.add(root, panel)

local bars = {}
for _, key in ipairs(ORDER) do
	local bar = {
		key = key,
		view = ui.find(panel, key .. "_bar"),
		fill = ui.find(panel, key .. "_fill"),
		label = ui.find(panel, key .. "_label"),
		value = ui.find(panel, key .. "_value"),
		shown = true,
		width = WIDTH,
	}
	ui.fill_color(bar.fill, Theme.bar[key])
	ui.text(bar.label, LABELS[key])
	bars[key] = bar
end

local last = {} -- latest reading per bar, so fills can be redrawn after a resize
local last_level
local show -- defined below

-- Health and nano span the full width. XP and alien XP share the bottom row;
-- XP takes the whole row while alien XP is hidden.
local function resize()
	bars.health.width, bars.nano.width = WIDTH, WIDTH
	if bars.alien.shown then
		bars.xp.width = math.floor((WIDTH - GAP) / 2)
		bars.alien.width = WIDTH - GAP - bars.xp.width
	else
		bars.xp.width = WIDTH
	end
	ui.size(bars.health.view, WIDTH, VITAL_HEIGHT)
	ui.size(bars.nano.view, WIDTH, VITAL_HEIGHT)
	ui.size(bars.xp.view, bars.xp.width, PROGRESS_HEIGHT)
	ui.size(bars.alien.view, bars.alien.width, PROGRESS_HEIGHT)
	ui.visible(bars.alien.view, bars.alien.shown)
	ui.size(panel, WIDTH, 2 * VITAL_HEIGHT + PROGRESS_HEIGHT + 2 * GAP)
	if show then
		for _, key in ipairs(ORDER) do
			show(bars[key], last[key], last_level)
		end
	end
end

-- Initial placement: bottom centre. Once dragged, the saved position wins.
ui.align(panel, "center", "end")
ui.borders(panel, 0, 0, 0, BOTTOM_INSET)
resize()
ui.visible(panel, true)

local placement = Placement.attach(panel, { only_moved = true, remember_open = true })
Move.attach(panel, { placement = placement })
ui.require("spiritech.modern-common/centre").attach(panel)
ui.register_view(panel, "bars")

-- Accepts a CharacterBar ({current, maximum, fraction}).
local function reading_text(reading)
	return Theme.reading({
		current_known = reading.current ~= nil, current = reading.current,
		maximum_known = reading.maximum ~= nil, maximum = reading.maximum,
	})
end

function show(bar, reading, level)
	local fraction = math.max(0, math.min(1, reading and reading.fraction or 0))
	local width = math.floor((bar.width - 2) * fraction + 0.5) -- inside the 1px outline
	ui.visible(bar.fill, width > 0)
	ui.size(bar.fill, math.max(1, width), -1)

	local name = LABELS[bar.key]
	if bar.key == "xp" and level and level >= 200 then
		name = "SK" -- past level 200 the experience bar tracks Shadowknowledge
	end
	if bar.key == "xp" or bar.key == "alien" then
		ui.text(bar.label, string.format("%s  %d%%", name, math.floor(fraction * 100)))
	else
		ui.text(bar.label, name)
	end
	local text = reading and reading_text(reading) or "-- / --"
	ui.text(bar.value, text)
	ui.tooltip(bar.view, name .. ": " .. text)
end

-- `bars` may arrive keyed by name or as an array of readings with a `key` field.
local function index(readings)
	local byKey = {}
	if readings then
		for k, v in pairs(readings) do
			if type(v) == "table" then
				byKey[v.key or k] = v
			end
		end
	end
	return byKey
end

game.character.subscribe("self", "", function(update, character, stats, readings)
	local byKey = index(readings)
	local level = character and character.level or nil
	-- Fall back to the character's own vitals if the bar readings are missing.
	if character then
		local function synth(current, maximum)
			local fraction = (current and maximum and maximum > 0) and current / maximum or 0
			return { current = current, maximum = maximum, fraction = fraction }
		end
		byKey.health = byKey.health or synth(character.health, character.max_health)
		byKey.nano = byKey.nano or synth(character.nano, character.max_nano)
	end

	-- Hide alien XP until the character has a known alien XP maximum.
	local alien = byKey.alien
	local alien_shown = alien ~= nil and alien.maximum ~= nil and alien.maximum > 0
	if alien_shown ~= bars.alien.shown then
		bars.alien.shown = alien_shown
		resize()
	end

	last_level = level
	for _, key in ipairs(ORDER) do
		last[key] = byKey[key]
		show(bars[key], byKey[key], level)
	end
end)
