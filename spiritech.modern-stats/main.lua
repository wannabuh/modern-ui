-- Modern Stats: compact title-less strip for the bottom-centre stack (role prk.stats).
-- Shows name, level, attack rating and all eight ACs. Health / nano / XP bars are left to
-- the Player Bars addon. Keeps the built-in contract: native code calls stats_apply().
pcall(ui.require, "spiritech.modern-common/screenfit") -- keep window positions through fullscreen changes
local Window = ui.require("core.window")
local Theme = ui.require("spiritech.modern-common/theme")

local WIDTH, HEIGHT = 520, 43 -- matches the 520px bottom-centre column; see content.xml
local DEFAULT_BOTTOM_INSET = 120 -- initial spot only; drag it into your stack

local content = ui.load("content.xml")
local name = ui.find(content, "character_name")

local values = {}
for _, key in ipairs({
	"level", "attack_rating", "melee_ac", "projectile_ac", "energy_ac",
	"disease_ac", "chemical_ac", "radiation_ac", "cold_ac", "fire_ac",
}) do
	values[key] = ui.find(content, key)
end

local frame = Window.create({
	template = "frame.xml",
	title = "Stats",
	content = content,
	width = WIDTH,
	height = HEIGHT,
	resizable = false,
	close = false,
	pin = false,
	menu = false,
	horizontal = "center",
	vertical = "end",
	layout = function(window)
		ui.limits(window.root, WIDTH, HEIGHT, WIDTH, HEIGHT)
		ui.size(window.root, WIDTH, HEIGHT)
		ui.size(content, WIDTH, HEIGHT)
		window:fit_title(WIDTH, false)
	end,
})
ui.root(frame.root)
ui.require("spiritech.modern-common/centre").attach(frame.root)
-- Initial placement only; a saved (moved) position takes over afterwards.
ui.borders(frame.root, 0, 0, 0, DEFAULT_BOTTOM_INSET)

local function number(value, known)
	return known and Theme.thousands(value) or "--"
end

function stats_apply(state, readings, status)
	ui.text(name, state.name ~= "" and state.name or "--")
	for _, reading in ipairs(readings) do
		local view = values[reading.key]
		if view then
			ui.text(view, number(reading.value, reading.known))
		end
	end
	-- `status` (health / nano / XP bars) is intentionally not shown here.
end
