if CC_ROLE ~= "hotbar" then return end -- see role.lua
-- Modern Hotbar: flat shortcut bar (role prk.hotbar; one instance per visible bar).
-- Copy of spiritech.modern-hotbar living in the Control Center package, so each bar can
-- relay its slots' cooldowns to the Control Center's Perk Actions window through the shared
-- package storage (see relay below).
-- Ten 36px slots showing the 32px icons at native size, 2px apart, plus a slim drag grip
-- (teal on the active number-key bar). Empty slots are faded to a faint outline.
-- Each horizontal bar has an editable label above it (click "Add label" and type).
-- No row arrows / row number / active button: rows and the active bar still follow your
-- key bindings. All commands stay native: slots, drag/drop, macros, cooldowns, counts.
local GAP, LENGTH, THICKNESS = 2, 388, 36
local LABELLED = 52 -- horizontal height with the label line (14 + 2 + 36)

local ACTIVE_COLOR = "#4FB3BF"
local GRIP_COLOR = "#3A424D"
local EMPTY_OPACITY = 0.35

local root = ui.load("hotbar_bar.xml")
local horizontal = ui.find(root, "shortcut_bar_horizontal")
local vertical = ui.find(root, "shortcut_bar_vertical")
local horizontal_slots = ui.find(horizontal, "shortcut_bar_slots")
local vertical_slots = ui.find(vertical, "shortcut_bar_slots")
local cells, slots, outlines, fills = {}, {}, {}, {}
local arranged_vertical

for index = 1, 10 do
	local loaded = ui.load("hotbar_slot.xml")
	cells[index] = ui.find(loaded, "slot_cell") or loaded
	slots[index] = ui.find(loaded, "shortcut_slot")
	outlines[index] = ui.find(loaded, "slot_outline")
	fills[index] = ui.find(loaded, "slot_fill")
	ui.add(horizontal_slots, cells[index])
end

local function spacing(vertical_mode)
	for index, cell in ipairs(cells) do
		local gap = index < #cells and GAP or 0
		if vertical_mode then
			ui.borders(cell, 0, 0, 0, gap)
		else
			ui.borders(cell, 0, 0, gap, 0)
		end
	end
end
spacing(false)

ui.root(root)
ui.size(root, LENGTH, LABELLED)

local Move = ui.require("core.move")
local on_restored -- set once the label code below exists
-- "restored" fires after the game has restored this bar's saved position; labels are filed
-- under that position, so they can only be looked up from then on.
local placement = ui.require("core.placement").attach(root, {
	only_moved = true,
	restored = function()
		if on_restored then on_restored() end
	end,
})
local open_menu -- defined below
local on_moved -- set once labels are loaded
local current_label -- the label text as last typed / loaded

-- The grip: drag to move; a click without moving opens the bar menu (Show label).
-- Right-click stays native (turns the bar).
local function grip(host)
	local handle = ui.find(host, "shortcut_bar_spinner")
	local start_x, start_y
	Move.attach(root, {
		handle = handle,
		placement = placement,
		started = function()
			start_x, start_y = ui.local_x(root), ui.local_y(root)
		end,
		finished = function(completed)
			if completed and start_x == ui.local_x(root) and start_y == ui.local_y(root) then
				open_menu(handle)
			elseif completed and on_moved then
				on_moved()
			end
		end,
	})
end
grip(horizontal)
grip(vertical)
ui.require("spiritech.modern-common/centre").attach(root)

-- Bar label: typed into the line above the bar and saved in this bar's own state.
-- It can be hidden per bar (grip click -> Show label); the bar then drops to 36px tall and
-- shifts down by the label's height so the slots stay where they were.
local label = ui.find(horizontal, "shortcut_bar_label")
local label_tab = ui.find(horizontal, "shortcut_bar_label_tab")

local TAB_MIN, TAB_MAX, TAB_PADDING = 64, 220, 14 -- 64 fits the "Add label" hint

-- The tab hugs its text (5px padding each side, plus a little room for the cursor).
local function fit_tab(value)
	local width = TAB_MIN
	if value and value ~= "" then
		local measure = ui.find(horizontal, "shortcut_bar_label_measure")
		ui.text(measure, value)
		local ok, measured = pcall(ui.text_width, measure)
		if ok and measured and measured > 0 then
			width = math.max(TAB_MIN, math.min(TAB_MAX, math.ceil(measured) + TAB_PADDING))
		else
			width = math.max(TAB_MIN, math.min(TAB_MAX, #value * 6 + TAB_PADDING))
		end
	end
	ui.limits(label_tab, width, 14, width, 14)
	ui.size(label_tab, width, 14)
end
local label_loaded, label_shown = false, true

-- Saving: the bar's own settings file only keeps fields the game knows (position etc.), so
-- labels live in this addon's storage instead. The game doesn't tell a bar which number it
-- is, so each label is filed under its bar's saved position ("bar@x,y") and re-filed
-- whenever the bar moves. Value: "<hidden 0/1>|<label text>".
local storage_key

-- Labels are per character: keys are "<character>/bar@x,y". The character comes from
-- game.character (its persistent key, or its name when the realm is unknown).
local character_id

local function key_for(x, y)
	return string.format("%s/bar@%.0f,%.0f", character_id or "?", x, y)
end

game.character.subscribe("self", "", function(_, character)
	if character and not character_id then
		local id = character.key or character.name
		if id and id ~= "" then character_id = id:gsub("[^%w_%-]", "_") end
	end
end)

local function saved_position()
	-- Accepts "x,y,r,b" or "Rect(x,y,r,b)".
	local x, y = ui.state.read(root, "WindowFrame"):match("(-?[%d.]+)%s*,%s*(-?[%d.]+)")
	x, y = tonumber(x), tonumber(y)
	if x and y then return x, y end
	return ui.local_x(root), ui.local_y(root)
end

local function save_label()
	if not character_id then return end
	-- Typed before the label was looked up: file it under the current position anyway.
	storage_key = storage_key or key_for(saved_position())
	local text = current_label or ""
	if text == "" and label_shown then
		ui.storage.write(storage_key, "")
	else
		ui.storage.write(storage_key, (label_shown and "0" or "1") .. "|" .. text)
	end
end

-- After a move: file the label under the new position.
local function refile()
	if not storage_key then return end
	local pose = placement.intended
	local x, y = pose and pose.x or ui.local_x(root), pose and pose.y or ui.local_y(root)
	local key = key_for(x, y)
	if key ~= storage_key then
		ui.storage.write(storage_key, "")
		storage_key = key
		save_label()
	end
end
on_moved = refile

ui.on_text_changed(label, function(value)
	current_label = value
	fit_tab(value)
	save_label()
end)

local function bar_height()
	if arranged_vertical then return LENGTH end
	return label_shown and LABELLED or THICKNESS
end

local function show_label(shown, keep_slots_in_place)
	local before = bar_height()
	label_shown = shown
	ui.visible(label_tab, shown)
	local after = bar_height()
	ui.size(root, arranged_vertical and THICKNESS or LENGTH, after)
	if keep_slots_in_place and not arranged_vertical and before ~= after
		and ui.vertical_alignment(root) == "start" then
		Move.place(root, ui.local_x(root), ui.local_y(root) + before - after)
		placement:changed()
		refile()
	end
end

-- Finds this bar's saved label: the stored "bar@x,y" nearest to where the bar is now,
-- within a few pixels (positions are saved as decimals and the game may still be placing
-- the bar). Retried on the bar's first updates until it matches or gives up.
local MATCH = 6 -- px

local function stored_label_near(x, y)
	local found, distance
	local prefix = character_id .. "/"
	for index = 1, ui.storage.count() do
		local key = ui.storage.key(index)
		local mine = key:sub(1, #prefix) == prefix
		local legacy = not key:find("/", 1, true) -- saved before labels were per character
		local kx, ky
		if mine or legacy then
			kx, ky = key:match("bar@(-?%d+),(-?%d+)$")
		end
		kx, ky = tonumber(kx), tonumber(ky)
		if kx and ky then
			local d = math.max(math.abs(kx - x), math.abs(ky - y))
			-- Prefer this character's own entry over an old shared one at the same spot.
			if mine then d = d - 0.5 end
			if d <= MATCH and (not distance or d < distance) then
				found, distance = key, d
			end
		end
	end
	return found
end

local GIVE_UP_MS = 15000 -- if the bar never reports a position, stop looking after this
local first_try

local function load_label(now)
	if label_loaded or not character_id then return end -- wait for the character too
	-- Hotbars are created before the game places them (no saved frame yet, sitting at 0,0),
	-- and they update rarely, so this runs every frame until the bar has a real position.
	local frame = ui.state.read(root, "WindowFrame")
	local x, y = saved_position()
	local placed = frame ~= "" or ui.local_x(root) ~= 0 or ui.local_y(root) ~= 0
	now = now or 0
	first_try = first_try or now
	local key = placed and (stored_label_near(x, y) or stored_label_near(ui.local_x(root), ui.local_y(root)))
	if not key and not (placed and now - first_try > 2000) and now - first_try < GIVE_UP_MS then
		return -- not placed yet (or position still settling); try again next frame
	end
	label_loaded = true
	local stored = key and ui.storage.read(key) or ""
	storage_key = key_for(x, y)
	if key and key ~= storage_key then
		-- Old shared entry (or a slightly different position): move it to this character's key.
		ui.storage.write(key, "")
		ui.storage.write(storage_key, stored)
	end
	local hidden, saved = stored:match("^([01])|(.*)$")
	saved = saved or ""
	current_label = saved
	ui.text(label, saved)
	fit_tab(saved)
	show_label(hidden ~= "1", false)
end

-- Poll each frame until the label is loaded, then stop.
ui.on_update(function(now)
	load_label(now)
	if label_loaded then ui.stop_updates() end
end)

-- Remove leftovers from the earlier diagnostic build.
for index = ui.storage.count(), 1, -1 do
	local key = ui.storage.key(index)
	if key:match("^debug_") then ui.storage.write(key, "") end
end

on_restored = function() load_label(ui.time()) end

local menu_items = {}
open_menu = function(anchor)
	if not menu_items[anchor] then
		ui.menu.style(anchor, "context")
		menu_items[anchor] = ui.menu.add(anchor, "Show label", label_shown, function()
			show_label(not label_shown, true)
			save_label()
		end)
	end
	ui.menu.checked(anchor, menu_items[anchor], label_shown)
	ui.menu.show(anchor)
end

local function controls(host, state)
	-- Only the grip remains; it keeps the native spinner binding (right-click turns the bar).
	ui.bind(ui.find(host, "shortcut_bar_spinner"), state.spinner)
end

local function arrange(vertical_mode)
	if arranged_vertical == vertical_mode then
		return
	end
	if ui.in_combat() then
		return
	end
	local target = vertical_mode and vertical_slots or horizontal_slots
	for _, cell in ipairs(cells) do
		ui.add(target, cell)
	end
	spacing(vertical_mode)
	ui.visible(horizontal, not vertical_mode)
	ui.visible(vertical, vertical_mode)
	arranged_vertical = vertical_mode
	ui.size(root, vertical_mode and THICKNESS or LENGTH, bar_height())
end

local function present(slot, entry)
	ui.bind(slot, entry.token)
	ui.action(slot, "game.hotbar.use", entry.token, "left")
	ui.icon(slot, entry.icon)
	ui.content(slot, entry.content)
	ui.tooltip(slot, entry.tooltip)
	ui.badge(slot, entry.badge)
	ui.fade(slot, entry.faded, "")
	ui.image(slot, entry.graphic ~= "" and "gfx://" .. entry.graphic or "")
	ui.caption(slot, entry.caption)
	ui.corner(slot, entry.corner)
	ui.center(slot, entry.countdown)
end

-- Cooldown relay: this bar's filled slots as "name<TAB>countdown<TAB>icon" lines under its own key
-- "cd/<instance>", stamped with the write time. Written only when something changed
-- (countdowns change about once a second while cooling). The Control Center reads every
-- "cd/" key and matches names to its perk actions.
local relay_key = "cd/" .. string.format("%.0f", ui.time()) .. "-" .. (tostring({}):match("0x(%x+)") or "0")
local relayed = nil

local function slot_name(entry)
	local first = (entry.tooltip or ""):match("^[^\n]*") or ""
	first = first:gsub("<[^>]*>", ""):gsub("^%s+", ""):gsub("%s+$", "")
	return first
end

-- The game puts a slot's cooldown in `badge` for perks and specials ("48s", once a second)
-- and in `countdown` for some others; badge can also hold other short text, so it only counts
-- when it reads as a time.
local function looks_like_time(text)
	return text:match("^%d+[smh]?$") or text:match("^%d+:%d%d$") or text:match("^%d+:%d%d:%d%d$")
end

local function cooldown_of(entry)
	local countdown = entry.countdown or ""
	if countdown ~= "" then return countdown end
	local badge = (entry.badge or ""):gsub("%s", "")
	if badge ~= "" and looks_like_time(badge) then return badge end
	return ""
end

local function relay(entries)
	local lines = {}
	for _, entry in ipairs(entries) do
		if entry.content then
			local name = slot_name(entry)
			if name ~= "" then
				local icon = tonumber(entry.icon) and string.format("%d", entry.icon) or ""
				lines[#lines + 1] = name .. "\t" .. cooldown_of(entry) .. "\t" .. icon
			end
		end
	end
	local payload = table.concat(lines, "\n")
	if payload == relayed then return end
	relayed = payload
	ui.storage.write(relay_key, payload == "" and "" or (string.format("%.0f", ui.time()) .. "\n" .. payload))
end

function hotbar_apply(state, entries)
	controls(horizontal, state)
	controls(vertical, state)
	arrange(state.vertical)
	-- The active (number-key) bar shows a teal grip.
	local grip = state.active and ACTIVE_COLOR or GRIP_COLOR
	for _, host in ipairs({ horizontal, vertical }) do
		ui.fill_color(ui.find(host, "shortcut_bar_grip_a"), grip)
		ui.fill_color(ui.find(host, "shortcut_bar_grip_b"), grip)
	end
	for index, slot in ipairs(slots) do
		local entry = entries[index]
		present(slot, entry)
		-- Empty slots: just a faint outline, so a half-filled bar doesn't read as a black grid.
		local filled = entry.content == true
		ui.opacity(outlines[index], filled and 1 or EMPTY_OPACITY)
		ui.opacity(fills[index], filled and 1 or EMPTY_OPACITY)
	end
	pcall(relay, entries)
end
