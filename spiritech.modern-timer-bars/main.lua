-- Modern Timer Bars: flat attack / cast / item / special / reload / equip timers (role prk.timer-bars).
-- Sits at the bottom centre directly above the Modern Compass and grows upward.
-- As with the built-in stack, it is click-through in play and only movable in the layout editor.
local WIDTH, HEIGHT, GAP = 520, 16, 3 -- WIDTH matches Player Bars / Modern Compass
-- Compass: bottom inset 263, height 22. Each row carries its own 3px gap underneath.
local BOTTOM_INSET = 263 + 22

local COLORS = {
	attack = "#2F6E45",
	cast = "#2A62A8",
	item = "#7652B0",
	special = "#A33434",
	reload = "#8C6520",
	recharge = "#4A5361", -- any timer in its recharge phase
}

local root = ui.load("stack.xml")
ui.root(root)
local frame = ui.find(root, "layout_editor_frame")
local host = ui.find(root, "timer_rows")
local editing = false
ui.require("core.move").attach(root, { enabled = function() return editing end })
ui.require("spiritech.modern-common/centre").attach(root)
ui.size(root, WIDTH, -1)
-- Initial placement only; a position saved from the layout editor takes over afterwards.
ui.align(root, "center", "end")
ui.borders(root, 0, 0, 0, BOTTOM_INSET)

local latest = {}
local rows = {}
local order = {}

local function row(key, title, color, preview_progress, preview_title)
	local view = ui.load("row.xml")
	ui.add(host, view)
	local entry = {
		key = key,
		view = ui.find(view, "timer_row"),
		bar = ui.find(view, "timer_bar"),
		fill = ui.find(view, "timer_fill"),
		label = ui.find(view, "timer_label"),
		time = ui.find(view, "timer_time"),
		title = title,
		color = color,
		preview_progress = preview_progress,
		preview_title = preview_title or title,
	}
	ui.size(entry.bar, WIDTH, HEIGHT)
	rows[key] = entry
	order[#order + 1] = entry
end

-- Top to bottom: rarer timers on top, the nano cast closest to the player bars.
row("equipment", "Changing equipment", COLORS.reload, 0.4)
row("reload", "Reloading", COLORS.reload, 0.5)
for index = 20, 2, -1 do
	row("special_" .. index, "Special", COLORS.special)
end
row("special_1", "Special", COLORS.special, 0.5)
for index = 4, 2, -1 do
	row("item_" .. index, "Item", COLORS.item)
end
row("item_1", "Item", COLORS.item, 0.5)
row("martial_arts", "Attack", COLORS.attack, 0.5, "Attack (martial arts)")
row("left", "Attack", COLORS.attack, 0.35, "Attack (left)")
row("right", "Attack", COLORS.attack, 0.7, "Attack (right)")
row("cast", "Casting", COLORS.cast, 0.6, "Nano casting")

local function draw(entry, progress, color)
	local width = math.floor((WIDTH - 2) * math.max(0, math.min(1, progress)) + 0.5)
	ui.fill_color(entry.fill, color)
	ui.visible(entry.fill, width > 0)
	ui.size(entry.fill, math.max(1, width), -1)
end

local function present_reading(key, entry, reading)
	local recharging = reading.phase == "recharge"
	local progress = reading.progress
	if recharging and (key ~= "cast" or reading.countdown) then
		progress = 1 - progress
	end
	draw(entry, progress, recharging and COLORS.recharge or entry.color)
	if not reading.active then
		return
	end
	local title = entry.title
	if recharging then
		title = (key == "cast" and reading.name ~= "") and (reading.name .. " (recharge)") or "Recharge"
	elseif key == "cast" and reading.name ~= "" then
		title = reading.name
	elseif key == "reload" and reading.name ~= "" then
		title = title .. ": " .. reading.name
	elseif (key == "left" or key == "right" or key == "martial_arts") and reading.name ~= "" then
		title = reading.name
	end
	ui.text(entry.label, title)
	ui.text(entry.time, reading.countdown and string.format("%.1fs", math.max(0, reading.remaining)) or "")
end

local function present()
	for _, entry in ipairs(order) do
		local reading = latest[entry.key]
		if editing then
			ui.visible(entry.view, entry.preview_progress ~= nil)
			if entry.preview_progress then
				draw(entry, entry.preview_progress, entry.color)
				ui.text(entry.label, entry.preview_title)
				ui.text(entry.time, "1.5s")
			end
		else
			ui.visible(entry.view, reading ~= nil and reading.active)
			if reading then
				present_reading(entry.key, entry, reading)
			end
		end
	end
end

function timer_bars_apply(readings)
	latest = {}
	for _, reading in ipairs(readings) do
		latest[reading.key] = reading
	end
	present()
end

function timer_bars_editing(value)
	editing = value
	ui.visible(frame, editing)
	present()
end
