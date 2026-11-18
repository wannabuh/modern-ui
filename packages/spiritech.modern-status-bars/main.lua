-- Modern Status Bars: flat horizontal health / nano / XP / alien XP bars (role prk.status-bars).
-- Native code runs one instance of this package per bar and calls the two globals below.
local Theme = ui.require("spiritech.modern-common/theme")
local root = ui.load("bar.xml")
ui.root(root)
ui.require("core.move").attach(root)

local WIDTH = 360
local GAP = 2
local BASE_INSET = 200 -- distance from the bottom of the screen to the lowest bar

-- Stacked top to bottom: health, nano, experience, alien.
local specs = {
	health = { label = "Health", color = Theme.bar.health, height = 20, font = 12, inset = BASE_INSET + 14 + 14 + 20 + 3 * GAP },
	nano = { label = "Nano", color = Theme.bar.nano, height = 20, font = 12, inset = BASE_INSET + 14 + 14 + 2 * GAP },
	experience = { label = "XP", color = Theme.bar.xp, height = 14, font = 11, inset = BASE_INSET + 14 + GAP, percent = true },
	alien = { label = "Alien XP", color = Theme.bar.alien, height = 14, font = 11, inset = BASE_INSET, percent = true },
}

local spec
local fill = ui.find(root, "status_fill")
local label = ui.find(root, "status_label")
local value = ui.find(root, "status_value")

function status_bar_initialize(kind)
	spec = assert(specs[kind], "Unknown player status bar")
	ui.size(root, WIDTH, spec.height)
	ui.fill_color(fill, spec.color)
	ui.font_size(label, spec.font)
	ui.font_size(value, spec.font)
	ui.text(label, spec.label)
	ui.visible(fill, false)
	-- Initial placement: bottom centre of the screen. A saved (moved) position overrides this.
	ui.align(root, "center", "end")
	ui.borders(root, 0, 0, 0, spec.inset)
end

function status_bar_apply(reading, shadowknowledge)
	local fraction = math.max(0, math.min(1, reading.fraction or 0))
	local width = math.floor((WIDTH - 2) * fraction + 0.5)
	ui.visible(fill, width > 0)
	ui.size(fill, math.max(1, width), -1)

	local name = spec.label
	if spec.label == "XP" and shadowknowledge then
		name = "SK"
	end
	if spec.percent then
		ui.text(label, string.format("%s  %d%%", name, math.floor(fraction * 100)))
	else
		ui.text(label, name)
	end
	local text = Theme.reading(reading)
	ui.text(value, text)
	ui.tooltip(root, (shadowknowledge and spec.percent and spec.label == "XP" and "Shadowknowledge" or spec.label) .. ": " .. text)
end
