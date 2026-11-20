-- NCU Strip: your running nano programs as a row of icons for the bottom-centre stack.
-- Standalone addon (Actions -> Addons -> NCU Strip). Data comes from the public effects API,
-- so it works while the NCU window is closed. It cannot cancel programs: use the NCU window
-- (right-click a row) for that.
--
-- Icons fill left to right from the column's left edge and wrap to a new row at 520px,
-- stacking rows bottom to top; the strip grows upward so its bottom edge stays put.
-- Each icon: outline colour by type (red hostile, green team), a sweep for time used, and
-- the time left underneath (amber in the last minute). Same order as the NCU list:
-- biggest NCU cost first.
pcall(ui.require, "spiritech.modern-common/screenfit") -- keep window positions through fullscreen changes
local Theme = ui.require("spiritech.modern-common/theme")
local Move = ui.require("core.move")
local Placement = ui.require("core.placement")

local WIDTH = 520 -- the bottom-centre column
local CELL_W, CELL_H, GAP = 34, 47, 3
local COLUMNS = math.floor((WIDTH + GAP) / (CELL_W + GAP)) -- 14
local BOTTOM_INSET = 330 -- initial spot only; drag it into your stack
local SOON = 60 -- seconds

local OUTLINES = {
	Hostile = "#B23A3A",
	Team = "#3E8A58",
}
local OUTLINE = "#2A3039"
local SOON_COLOR = "#F0C060"

local root = ui.load("root.xml")
ui.root(root)
local strip = ui.find(ui.load("strip.xml"), "ncu_strip")
ui.add(root, strip)
ui.size(strip, WIDTH, CELL_H)
ui.align(strip, "center", "end")
ui.borders(strip, 0, 0, 0, BOTTOM_INSET)

local shown_height = CELL_H
-- A restored position comes with the height it was saved at; adopt it so the bottom-edge
-- anchoring below doesn't drift when the rows are re-counted after login.
local placement = Placement.attach(strip, {
	only_moved = true,
	remember_open = true,
	resize = function(_, height)
		shown_height = height
		ui.size(strip, WIDTH, height)
	end,
})
Move.attach(strip, { placement = placement })
ui.require("spiritech.modern-common/centre").attach(strip)
ui.register_view(strip, "strip")

local cells = {}

local function cell(index)
	local existing = cells[index]
	if existing then return existing end
	local loaded = ui.load("cell.xml")
	ui.add(strip, loaded)
	local view = ui.find(loaded, "cell")
	local entry = {
		view = view,
		outline = ui.find(view, "cell_outline"),
		icon = ui.find(view, "cell_icon"),
		time = ui.find(view, "cell_time"),
	}
	ui.align(view, "start", "start")
	ui.text_alignment(entry.time, "center")
	-- Icons take the pointer (for tooltips), so each one is also a drag handle for the strip.
	Move.attach(strip, { handle = view, placement = placement })
	cells[index] = entry
	return entry
end

local function short_time(effect)
	if effect.permanent then return "" end
	local seconds = math.max(0, math.floor(effect.remaining or 0))
	if seconds < 60 then return seconds .. "s" end
	if seconds < 3600 then return math.floor(seconds / 60) .. "m" end
	return math.floor(seconds / 3600) .. "h"
end

local function long_time(effect)
	if effect.permanent then return "Permanent" end
	local seconds = math.max(0, math.floor(effect.remaining or 0))
	local minutes = math.floor(seconds / 60)
	if seconds >= 3600 then
		return string.format("%d:%02d:%02d", math.floor(minutes / 60), minutes % 60, seconds % 60)
	end
	return string.format("%d:%02d", minutes, seconds % 60)
end

local function sorted(effects)
	local list = {}
	for _, effect in ipairs(effects) do
		if not effect.hidden then list[#list + 1] = effect end
	end
	table.sort(list, function(a, b)
		if a.ncu_cost ~= b.ncu_cost then return a.ncu_cost > b.ncu_cost end
		if a.name ~= b.name then return a.name < b.name end
		return a.reference < b.reference
	end)
	return list
end

-- Keeps the strip's bottom edge where it is when rows are added or removed, so extra
-- rows push upward instead of covering whatever sits below it.
local function set_height(height)
	if height == shown_height then return end
	local grow = height - shown_height
	shown_height = height
	ui.size(strip, WIDTH, height)
	if ui.vertical_alignment(strip) == "start" then -- dragged: placed by its top-left corner
		Move.place(strip, ui.local_x(strip), ui.local_y(strip) - grow)
		placement:changed()
	end
end

local function present(effects)
	local list = sorted(effects)
	local count = #list
	local rows = math.max(1, math.ceil(count / COLUMNS))
	set_height(rows * CELL_H + (rows - 1) * GAP)
	for index, effect in ipairs(list) do
		local view = cell(index)
		local slot = index - 1
		-- Left to right, wrapping to a new row once the 520px column is full. The first row
		-- sits at the bottom and later rows stack on top of it.
		local row = math.floor(slot / COLUMNS)
		local left = (slot % COLUMNS) * (CELL_W + GAP)
		ui.place(view.view, left, (rows - 1 - row) * (CELL_H + GAP))
		ui.visible(view.view, true)
		-- Like Core's grid/table: mark the slot as holding content, then set its icon.
		ui.content(view.icon, true)
		ui.icon(view.icon, effect.icon)
		local used = 0
		if not effect.permanent and (effect.duration or 0) > 0 then
			used = math.max(0, math.min(1, 1 - (effect.remaining or 0) / effect.duration))
		end
		pcall(ui.progress, view.icon, used)
		ui.fill_color(view.outline, OUTLINES[effect.kind] or OUTLINE)
		ui.text(view.time, short_time(effect))
		local soon = not effect.permanent and (effect.remaining or 0) < SOON
		ui.text_color(view.time, soon and SOON_COLOR or Theme.color.text)
		ui.tooltip(view.view, string.format("%s\n%d NCU  ·  %s\nCancel from the NCU window (right-click).",
			effect.name, effect.ncu_cost or 0, long_time(effect)))
	end
	for index = count + 1, #cells do
		ui.visible(cells[index].view, false)
		ui.icon(cells[index].icon, 0)
		ui.content(cells[index].icon, false)
	end
end

-- Your own effects. Subscribe by the "self" alias; if that collection never becomes known,
-- also subscribe by your character's lifetime reference (from game.character).
local current_reference, by_reference, self_known = nil, nil, false

local function deliver(update, accept)
	local data = update and update.data
	if not data then return end
	for _, owner in ipairs(data) do
		if accept(owner) and owner.known then
			present(owner.effects or {})
			return true
		end
	end
end

game.effects.subscribe("self", function(update)
	if deliver(update, function() return true end) then self_known = true end
end)

game.character.subscribe("self", "", function(_, character)
	local reference = character and character.reference
	if not reference or reference == current_reference then return end
	current_reference = reference
	if by_reference and game.observation then
		pcall(game.observation.unsubscribe, by_reference)
	end
	by_reference = game.effects.subscribe(reference, function(update)
		if self_known then return end
		deliver(update, function(owner) return owner.subject == current_reference end)
	end)
end)
