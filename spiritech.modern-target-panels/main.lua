-- Modern Target Panels: flat friendly / hostile target frames (role prk.target-panels).
-- Native code runs one instance per panel. By default the two panels sit side by side
-- directly above Player Bars, together spanning the same 520px column:
-- friendly on the left, hostile on the right, 4px apart.
local Theme = ui.require("spiritech.modern-common/theme")

local STACK_WIDTH, GAP = 520, 4 -- Player Bars column, and the gap between the two panels
local WIDTH = math.floor((STACK_WIDTH - GAP) / 2) -- 258
-- Player Bars: bottom inset 200, height 60; then the usual 3px gap. The primary slot sits on
-- this line and a second target appears above it, so the primary never moves.
local BOTTOM_INSET = 200 + 60 + 3

local OUTLINE = "#2A3039"
local IN_REACH = "#4FB3BF" -- outline colour while the target is within weapon reach

local root = ui.load("panel.xml")
ui.root(root)
ui.require("core.move").attach(root)
ui.require("spiritech.modern-common/centre").attach(root)
ui.size(root, WIDTH, -1)

local hostile = false

local function slot_views(name)
	local prefix = "target_" .. name
	return {
		slot = ui.find(root, prefix),
		name = ui.find(root, prefix .. "_name"),
		con = ui.find(root, prefix .. "_con"),
		level = ui.find(root, prefix .. "_level"),
		bar = ui.find(root, prefix .. "_bar"),
		outline = ui.find(root, prefix .. "_outline"),
		fill = ui.find(root, prefix .. "_fill"),
		health = ui.find(root, prefix .. "_health"),
		percent = ui.find(root, prefix .. "_percent"),
	}
end

local upper = slot_views("upper")
local lower = slot_views("lower")
local last_upper, last_lower

-- Optional extra facts (level, exact health) from the read-only targeting API, matched by name.
local known = {}

local function hex(color)
	return string.format("#%06X", color or 0xFFFFFF)
end

local function apply_slot(views, slot)
	local visible = slot ~= nil and slot.name ~= ""
	ui.visible(views.slot, visible)
	if not visible then
		return
	end

	ui.text(views.name, slot.name)
	ui.text_color(views.name, hex(slot.name_color))
	ui.tooltip(views.slot, slot.header)
	ui.fill_color(views.con, hex(slot.bar_color))

	local summary = known[slot.name]
	ui.text(views.level, summary and summary.level and ("Lv " .. summary.level) or "")

	ui.visible(views.bar, slot.has_bar)
	if not slot.has_bar then
		return
	end
	local fraction = math.max(0, math.min(1, slot.fraction or 0))
	local width = math.floor((WIDTH - 2) * fraction + 0.5)
	ui.fill_color(views.fill, hostile and Theme.bar.health or Theme.bar.alien)
	ui.visible(views.fill, width > 0)
	ui.size(views.fill, math.max(1, width), -1)
	ui.fill_color(views.outline, slot.in_reach and IN_REACH or OUTLINE)
	ui.text(views.percent, string.format("%d%%", math.floor(fraction * 100 + 0.5)))
	if summary and summary.health and summary.max_health then
		ui.text(views.health, Theme.thousands(summary.health) .. " / " .. Theme.thousands(summary.max_health))
	else
		ui.text(views.health, "")
	end
end

local function refresh()
	apply_slot(upper, last_upper)
	apply_slot(lower, last_lower)
end

ui.visible(upper.slot, false)
ui.visible(lower.slot, false)

function target_panel_place(viewport_width, is_hostile)
	hostile = is_hostile
	local column_left = viewport_width / 2 - STACK_WIDTH / 2
	local left = hostile and (column_left + WIDTH + GAP) or column_left
	-- Initial placement only; a saved (moved) position takes over afterwards.
	ui.align(root, "start", "end")
	ui.borders(root, math.floor(math.max(0, left)), 0, 0, BOTTOM_INSET)
end

function target_panel_apply(upper_slot, lower_slot, viewport_width)
	last_upper, last_lower = upper_slot, lower_slot
	refresh()
end

if game.targeting and game.targeting.subscribe then
	pcall(game.targeting.subscribe, function(update)
		known = {}
		local data = update and update.data
		if data then
			for _, summary in ipairs({ data.selected, data.fight }) do
				if summary and summary.name then
					known[summary.name] = summary
				end
			end
		end
		refresh()
	end)
end
