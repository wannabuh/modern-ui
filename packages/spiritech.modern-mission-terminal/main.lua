-- Modern Mission Terminal (role prk.mission-terminal): offers as a list.
--   Row: icon (numbered like its map marker) | the server's summary, the reward items (gold;
--   a red warning sign when you can't use one), the class (when restricted), requirements,
--   then QL · location · credits · XP | the reward items' icons. Rewards are looked up in modern-common's item database
--   (name + QL): the requirements line shows the profession and every requirement with only
--   its number coloured (green met, red unmet, plus your value in brackets); the row's
--   tooltip (plain text: tooltips can't be coloured) adds damage or implant modifiers.
-- The window is resizable (sizes remembered with and without the map): the offers scroll,
-- and without the map the list takes the width. With the map, drag the divider between them
-- to share it (remembered: modern_mission_list_width); resizing the window resizes the map.
-- Offer map (API 0.2.0, title menu "Show map", on by default): the planet map beside the list
-- with a numbered marker per offer (gold; the selected one ringed in teal) and your position.
-- Wheel zooms, drag pans, clicking a marker chooses its offer; - / + step the map's detail
-- levels and Fit shows every offer again. The marker logic is the built-in terminal's.
--   Click selects (as the stock slot does); inspecting with the modifier held stays native,
--   and the (restyled) Info window names the reward item.
-- The rest (reward mode, chosen reward, sliders, request / accept / cancel) is the stock
-- window's logic in the flat palette.
pcall(ui.require, "spiritech.modern-common/screenfit") -- keep window positions through fullscreen changes
local Window = ui.require("core.window")
local Theme = ui.require("spiritech.modern-common/theme")
local Reqs
do
	local ok, module = pcall(ui.require, "spiritech.modern-common/reqs")
	Reqs = ok and module or nil
	-- Check every requirement (the shared default shows three), so none can hide a problem.
	if Reqs then Reqs.MAX_SHOWN = 12 end
end

local WIDTH, MAX_OFFERS, LINES = 360, 6, 5
local MAP_WIDTH = 560 -- added to the window by default while the map shows
local MAP_MIN_WIDTH = 300
local SPLITTER = 6 -- the divider between list and map; must match terminal.xml
local MIN_HEIGHT, MAX_HEIGHT = 380, 1600
local ROW_HEIGHT = 92 -- incl. the 2px gap; must match offer_row.xml
local SCROLL_ROOM = 10 -- the offer list's scrollbar + gap
local COLUMN_BORDERS = 8 -- mission_terminal's left + right borders (terminal.xml)
local TEXT_ROOM_PAD = 4 + 32 + 8 + 6 + 6 -- row borders + icon + text gap + right pad + slack
local REWARD_ICON = 30 -- one reward icon incl. its gap
local SIDES = Window.CONTENT_SIDES or 11
local ENDS = Window.CONTENT_ENDS or 33

-- Colours: white summary, gold reward items, then the requirement numbers alone in green /
-- red so a line of requirements doesn't turn into a wall of one colour.
local TEXT, SOFT, DIM, DIVIDER = "#E8ECF1", "#C5CCD6", "#8B95A3", "#5E6875"
local GOLD, GOOD, BAD, TEAL = "#F0C060", "#8FCF9A", "#FF7A70", "#6CC8D4"

local content = ui.load("terminal.xml")
local function find(name) return ui.find(content, name) end
local list, empty, measure = find("offer_list"), find("offer_empty"), find("offer_measure")
local request, accept, cancel = find("request"), find("accept"), find("cancel")
local request_text = find("request_label")
local advanced, advanced_rows = find("advanced"), find("advanced_rows")
local mode_random, mode_pinned = find("mode_random"), find("mode_pinned")
local reward_row, reward_slot = find("reward_row"), find("reward_slot")
local reward_name, reward_ql, reward_cost, reward_clear = find("reward_name"), find("reward_ql"), find("reward_cost"), find("reward_clear")
local row_difficulty = find("row_difficulty")
local request_label = "Request missions"
local slider_rows = { "difficulty", "good", "order", "open", "physical", "headon", "credits" }
local sliders = {}
local width = WIDTH -- the list's minimum width (fits the slider labels)
local list_width = -1 -- the list column's current width (outer, like `width`); -1 = rows not sized yet
local show_advanced = ui.preference.read("show_advanced_options") == "true"
local show_map = ui.preference.read("modern_mission_map") ~= "false"
local list_column, offer_map = find("mission_terminal"), find("offer_map")
local splitter, splitter_line = find("list_splitter"), find("list_splitter_line")
-- The list's chosen width beside the map (outer, like `width`); nil = as narrow as it fits.
local list_target = tonumber(((ui.preference.read("modern_mission_list_width") or ""):gsub('^"(.*)"$', "%1")))
local map_tiles = find("offer_map_tiles")
local map_zoom_in, map_zoom_out, map_fit = find("offer_map_zoom_in"), find("offer_map_zoom_out"), find("offer_map_fit")
local map_view = game.map_surface
map_view.attach(map_tiles, true)

for index, name in ipairs(slider_rows) do
sliders[index] = find("slider_" .. name)
ui.on_value_committed(sliders[index], function(value)
	game.mission_terminal.slider(index, value)
end)
end

-- ------------------------------------------------------------------ text
local function escape(text)
return (text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

local function plain(text)
text = (text or ""):gsub("\r", ""):gsub("<[^>]*>", "")
return text
end

local function text_width(text)
ui.text(measure, text)
return ui.text_width(measure)
end

-- Word-wrap the summary into lines that fit `room`; the last shown line ends in "..." when cut.
local function wrap(text, room, limit)
local lines = {}
for raw in (text .. "\n"):gmatch("(.-)\n") do
	local paragraph = raw:gsub("^%s+", ""):gsub("%s+$", "")
	if paragraph ~= "" then
		local line = ""
		for word in paragraph:gmatch("%S+") do
			local candidate = line == "" and word or (line .. " " .. word)
			if line ~= "" and text_width(candidate) > room then
				lines[#lines + 1] = line
				line = word
			else
				line = candidate
			end
		end
		if line ~= "" then lines[#lines + 1] = line end
	end
end
if #lines > limit then
	local last = lines[limit]
	while last ~= "" and text_width(last .. "...") > room do
		last = last:sub(1, -2)
	end
	lines[limit] = last:gsub("%s+$", "") .. "..."
	for index = #lines, limit + 1, -1 do lines[index] = nil end
end
return lines
end

-- A line is { text, colour }, or { text, colour, segments = { { text, colour }, ... } } for
-- a line in several colours (text is then the plain version, used for measuring).
local function markup(lines)
local pieces = {}
for _, line in ipairs(lines) do
	if line.segments then
		local parts = {}
		for _, segment in ipairs(line.segments) do
			parts[#parts + 1] = string.format("<font color=%s>%s</font>", segment[2], escape(segment[1]))
		end
		pieces[#pieces + 1] = table.concat(parts)
	else
		pieces[#pieces + 1] = string.format("<font color=%s>%s</font>", line[2], escape(line[1]))
	end
end
return table.concat(pieces, "<br>")
end

local grouped = Theme.thousands

-- What the item database knows about one reward: tooltip lines and whether you can use it
-- (false: something unmet; nil: not in the database or your stats aren't known).
local function reward_details(item)
	local lines, usable = { item.name .. " (QL " .. item.ql .. ")" }, nil
	if not Reqs then return lines, usable, nil end
	local damage = Reqs.damage(item.name, item.ql)
	if damage then lines[#lines + 1] = "   Damage " .. damage end
	local mods = {}
	for _, mod in ipairs(Reqs.mods(item.name, item.ql) or {}) do mods[#mods + 1] = mod.text end
	if #mods > 0 then lines[#lines + 1] = "   " .. table.concat(mods, ", ") end
	local parts = Reqs.parts(item.name, item.ql)
	if parts and #parts > 0 then
		local needs = {}
		for _, part in ipairs(parts) do
			local text = part.tooltip or part.text
			if part.met == false then
				usable = false
				text = "✗ " .. text
			elseif part.met == true and usable == nil then
				usable = true
			end
			needs[#needs + 1] = text
		end
		lines[#lines + 1] = "   Requires " .. table.concat(needs, ", ")
	elseif parts then
		usable = true
	end
	return lines, usable, parts
end

-- ------------------------------------------------------------------ rows
local rows = {}
for index = 1, MAX_OFFERS do
local loaded = ui.load("offer_row.xml")
ui.add(list, loaded)
local root = ui.find(loaded, "offer_row") or loaded
rows[index] = {
	root = root,
	icon = ui.find(loaded, "row_icon"),
	text = ui.find(loaded, "row_text"),
	rewards = { ui.find(loaded, "reward_icon_1"), ui.find(loaded, "reward_icon_2") },
}
ui.visible(root, false)
end

local offers = {}

-- Fit coloured segments into one line of `room` pixels, cutting the last one with "...".
local function fit_segments(segments, room)
local kept, plain_text = {}, ""
for _, segment in ipairs(segments) do
	local candidate = plain_text .. segment[1]
	if text_width(candidate) <= room then
		kept[#kept + 1] = segment
		plain_text = candidate
	else
		local cut = segment[1]
		while cut ~= "" and text_width(plain_text .. cut .. "...") > room do
			cut = cut:sub(1, (utf8.offset(cut, -1) or #cut) - 1)
		end
		cut = cut:gsub("[%s·]+$", "")
		if cut == "" and kept[#kept] and kept[#kept][1]:match("^[%s·|]+$") then
			kept[#kept] = nil -- nothing of the next one fits: drop the dangling divider too
		end
		kept[#kept + 1] = { cut .. "...", segment[2] }
		plain_text = plain_text .. cut .. "..."
		break
	end
end
return { plain_text, "#A3ADBA", segments = kept }
end

-- Requirement segments for one reward: the profession (coloured as a whole), then each
-- requirement as "Skill " + the number coloured, with your value after an unmet one.
local function requirement_segments(parts, out)
local first = true
for _, part in ipairs(parts) do
	if not part.profession and not first then out[#out + 1] = { " · ", DIVIDER } end
	if not part.profession then first = false end
	local color = part.met == false and BAD or part.met == true and GOOD or SOFT
	if part.profession then
		-- shown on the class line instead
	elseif not part.label then
		out[#out + 1] = { part.text, color }
	else
		out[#out + 1] = { part.label .. " ", SOFT }
		out[#out + 1] = { tostring(part.need), part.met == nil and DIM or color }
		if part.met == false and part.have then
			out[#out + 1] = { " (" .. math.floor(part.have) .. ")", DIM }
		end
	end
end
end

local function divided(items)
local out = {}
for item_index, item in ipairs(items) do
	if item_index > 1 then out[#out + 1] = { " · ", DIVIDER } end
	out[#out + 1] = item
end
return out
end

local function show_offers()
local row_width = list_width - SIDES - COLUMN_BORDERS - SCROLL_ROOM
for index, row in ipairs(rows) do
	local offer_rewards = (offers[index] and offers[index].rewards) or {}
	local icons = math.min(#offer_rewards, #row.rewards)
	local room = row_width - TEXT_ROOM_PAD - icons * REWARD_ICON
	local offer = offers[index]
	if offer and offer.reference ~= 0 then
		local summary = plain(offer.description)
		ui.bind(row.root, offer.reference)
		ui.action(row.root, "game.mission_terminal.choose", offer.reference, "left")
		ui.selected(row.root, offer.selected)
		ui.content(row.icon, true)
		ui.icon(row.icon, offer.icon)
		ui.corner(row.icon, tostring(index))
		-- API 0.2.0 offers also carry rewards, QL, location and pay; the summary gets
		-- whatever lines those leave.
		local extra = {}
		local names, tips, unusable = {}, { summary }, false
		local needs = {} -- requirement segments of every reward
		local classes = {} -- class segments of every restricted reward
		for _, item in ipairs(offer.rewards or {}) do
			names[#names + 1] = item.name
			local lines, usable, parts = reward_details(item)
			if parts and #parts > 0 then
				local skills = 0
				for _, part in ipairs(parts) do
					if part.profession then
						if #classes > 0 then classes[#classes + 1] = { "  |  ", DIVIDER } end
						local names = (part.tooltip or part.text):gsub("/", ", ")
						classes[#classes + 1] = { names, part.met == false and BAD or part.met == true and GOOD or SOFT }
					else
						skills = skills + 1
					end
				end
				if skills > 0 then
					if #needs > 0 then needs[#needs + 1] = { "  |  ", DIVIDER } end
					requirement_segments(parts, needs)
				end
			end
			if usable == false then
				unusable = true
			end
			tips[#tips + 1] = ""
			for _, line in ipairs(lines) do tips[#tips + 1] = line end
		end
		if #names > 0 then
			local segments = {}
			if unusable then segments[1] = { "⚠ ", BAD } end
			segments[#segments + 1] = { table.concat(names, ", "), GOLD }
			extra[#extra + 1] = fit_segments(segments, room)
		end
		if #classes > 0 then
			table.insert(classes, 1, { "Class ", DIM })
			extra[#extra + 1] = fit_segments(classes, room)
		end
		if #needs > 0 then
			extra[#extra + 1] = fit_segments(needs, room)
		end
		local facts = {}
		if (offer.ql or 0) > 0 then facts[#facts + 1] = { "QL " .. offer.ql, DIM } end
		if offer.location and offer.location ~= "" then facts[#facts + 1] = { offer.location, SOFT } end
		if (offer.credits or 0) > 0 then facts[#facts + 1] = { grouped(offer.credits) .. " cr", GOLD } end
		if (offer.experience or 0) > 0 then facts[#facts + 1] = { grouped(offer.experience) .. " XP", TEAL } end
		if #facts > 0 then
			extra[#extra + 1] = fit_segments(divided(facts), room)
		end
		local lines = {}
		for line_index, line in ipairs(wrap(summary, room, math.max(1, LINES - #extra))) do
			lines[line_index] = { line, line_index == 1 and TEXT or DIM }
		end
		if #lines == 0 then lines[1] = { "Mission " .. index, TEXT } end
		for slot_index, slot in ipairs(row.rewards) do
			local item = offer_rewards[slot_index]
			ui.visible(slot, item ~= nil)
			ui.content(slot, item ~= nil)
			ui.icon(slot, item and item.icon or 0)
		end
		for _, line in ipairs(extra) do lines[#lines + 1] = line end
		ui.tooltip(row.root, table.concat(tips, "\n"))
		local texts = {}
		for line_index, line in ipairs(lines) do texts[line_index] = line[1] end
		ui.text(row.text, table.concat(texts, "\n"))
		pcall(ui.aoml, row.text, "", markup(lines), false)
		ui.visible(row.root, true)
	else
		for _, slot in ipairs(row.rewards) do ui.visible(slot, false) end
		ui.visible(row.root, false)
	end
end
end

-- ------------------------------------------------------------------ window
-- Outer window sizes, with and without the map: preference modern_mission_size_<map|list> =
-- "width,height". Unset ones start from the list's width (known after configure).
local sizes = {}
for _, key in ipairs({ "map", "list" }) do
	local value = (ui.preference.read("modern_mission_size_" .. key) or ""):gsub('^"(.*)"$', "%1")
	local w, h = value:match("^([%d.]+),([%d.]+)$")
	if w then sizes[key] = { math.floor(tonumber(w) + 0.5), math.floor(tonumber(h) + 0.5) } end
end

local function limits()
if show_map then return width + SPLITTER + MAP_MIN_WIDTH, MIN_HEIGHT, 2400, MAX_HEIGHT end
return width, MIN_HEIGHT, 900, MAX_HEIGHT
end

local function size_rows(row_width)
for _, row in ipairs(rows) do
	ui.limits(row.root, row_width, ROW_HEIGHT, row_width, ROW_HEIGHT)
	ui.size(row.root, row_width, ROW_HEIGHT)
end
end

local function layout(window, w, h)
local key = show_map and "map" or "list"
if not w or w <= 0 or not h or h <= 0 then
	local saved = sizes[key]
	w = saved and saved[1] or (width + (show_map and MAP_WIDTH or 0))
	h = saved and saved[2] or 560
end
local min_w, min_h, max_w, max_h = limits()
w = math.max(min_w, math.min(max_w, w))
h = math.max(min_h, math.min(max_h, h))
ui.limits(window.root, min_w, min_h, max_w, max_h)
ui.request_size(window.root, w, h)
window:fit_title(w, true)
window:fit_content(w, h)
ui.size(content, w - SIDES, h - ENDS)
-- Beside the map the list keeps its chosen width (within what leaves the map its minimum);
-- the map takes the rest.
local column = w
if show_map then
	column = math.max(width, math.min(list_target or width, w - SPLITTER - MAP_MIN_WIDTH))
end
-- Pin the column (limits, not just a size request): otherwise the offer list keeps its full
-- height instead of scrolling, and pushes the controls out of the window.
ui.limits(list_column, column - SIDES, h - ENDS, column - SIDES, h - ENDS)
ui.size(list_column, column - SIDES, h - ENDS)
if column ~= list_width then
	list_width = column
	size_rows(list_width - SIDES - COLUMN_BORDERS - SCROLL_ROOM)
	show_offers()
end
local saved = sizes[key]
if not saved or saved[1] ~= w or saved[2] ~= h then
	sizes[key] = { w, h }
	ui.preference.write("modern_mission_size_" .. key, math.floor(w + 0.5) .. "," .. math.floor(h + 0.5), "text")
end
end

local MAP_ITEM = 1
local toggle_map, draw_map_markers
local frame = Window.create({
template = Theme.WINDOW_TEMPLATE,
title = "Mission Terminal",
remember_open = false,
content = content,
width = width + (show_map and MAP_WIDTH or 0),
height = 560,
resizable = true,
menu = {
	{ label = "Show map", checked = show_map, invoke = function() toggle_map() end },
},
horizontal = "center",
vertical = "center",
layout = layout,
})
ui.root(frame.root)

local function advanced_visibility()
ui.visible(advanced_rows, show_advanced)
ui.text(advanced, show_advanced and "Fewer options" or "More options")
end
ui.on_click(advanced, function()
show_advanced = not show_advanced
ui.preference.write("show_advanced_options", tostring(show_advanced), "bool")
advanced_visibility()
end)
advanced_visibility()

function mission_terminal_configure(label_request, accept_label, labels)
request_label = label_request ~= "" and label_request or request_label
ui.text(request_text, request_label)
if accept_label ~= "" then ui.text(find("accept_label"), accept_label) end
local widest = 0
for index, name in ipairs(slider_rows) do
	local minimum = find("row_" .. name .. "_min")
	local maximum = find("row_" .. name .. "_max")
	ui.text(minimum, labels[index].minimum)
	ui.text(maximum, labels[index].maximum)
	widest = math.max(widest, ui.text_width(minimum), ui.text_width(maximum))
	ui.progress(sliders[index], labels[index].progress)
end
local column = math.ceil(widest) + 5
for _, name in ipairs(slider_rows) do
	for _, bound in ipairs({ "_min", "_max" }) do
		local label = find("row_" .. name .. bound)
		ui.size(label, column, 18)
		ui.maximum(label, column, -1)
	end
end
width = math.max(WIDTH, column * 2 + 102 + 21)
list_width = -1 -- re-fit the rows
frame:resize(0, 0)
end

function mission_terminal_sliders(values)
for index, value in ipairs(values) do
	ui.progress(sliders[index], value)
end
end

local function command(view, name, reference)
ui.bind(view, reference)
ui.action(view, name, reference, "left")
end

local function apply_reward(reward)
ui.selected(mode_random, not reward.pinned_mode)
ui.selected(mode_pinned, reward.pinned_mode)
command(mode_random, "game.mission_terminal.random", reward.random)
command(mode_pinned, "game.mission_terminal.pinned", reward.pinned)
ui.visible(reward_row, reward.pinned_mode)
ui.visible(row_difficulty, not reward.pinned_mode)
command(reward_slot, "game.mission_terminal.choose_reward", reward.choose)
ui.icon(reward_slot, reward.icon)
ui.content(reward_slot, reward.has_pin)
ui.text(reward_name, reward.has_pin and reward.name or "No reward chosen")
ui.text(reward_ql, reward.has_pin and ("QL " .. reward.ql) or "Click the slot to choose one")
ui.visible(reward_clear, reward.has_pin)
ui.visible(reward_cost, reward.has_pin and reward.cost > 0)
ui.text(reward_cost, "Each roll costs " .. Theme.thousands(reward.cost) .. " credits")
command(reward_clear, "game.mission_terminal.clear_reward", reward.clear)
ui.text(request_text, reward.pinned_mode and "Request chain" or request_label)
end

function mission_terminal_apply(state, list_offers, reward)
offers = list_offers
ui.visible(empty, #offers == 0)
show_offers()
draw_map_markers()
command(request, "game.mission_terminal.request", state.request)
ui.enabled(request, not reward.pinned_mode or reward.has_pin)
apply_reward(reward)
command(accept, "game.mission_terminal.accept", state.accept)
ui.enabled(accept, state.selected)
command(cancel, "game.mission_terminal.cancel", state.cancel)
end


-- ------------------------------------------------------------------ offer map
-- The built-in terminal's map logic (MissionTerminal/main.lua, API 0.2.0) in the Modern
-- colours. game.mission_map chooses the atlas record and places offers / you on it;
-- game.map_surface draws. Markers that would overlap fan out on short leaders around a dot.
local MARKER_RADIUS, SELECTED_RADIUS, MARKER_RIM, SELECTED_HALO = 9, 11, 2, 4
local MARKER_FILL, MARKER_INK, MARKER_HALO, MARKER_TEXT_SIZE = "#F0C060", "#3A2A00", "#4FB3BF", 12
local FULL_TURN = 2 * math.pi
local WHEEL_STEPS_PER_DOUBLING, MAX_WHEEL_STEPS = 3, 6
local MARKER_GAP, DOOR_RADIUS = 1, 3
local LEADER_WIDTH, LEADER_BORDER, LEADER_LENGTH = 2, 1, 10
local MARKER_REACH = SELECTED_RADIUS + SELECTED_HALO
local PLAYER_MARKER = "GFX_GUI_PLANETMAP_PLAYER_MARKER"
local wheel_step, wheel_turn, map_scale = 0, 0, 1
local map_revision, map_records, map_zoom, map_fit_pending = -1, 0, 0, false
local revealed
local drawn_player_placed, drawn_player_x, drawn_player_y = 0, 0, 0

local function disc(x, y, radius, color)
map_view.fan(x, y, radius, 0, FULL_TURN, color)
end

local function placed(index)
return game.mission_map.offer(index, "placed") ~= 0
end

local function player_moved()
return game.mission_map.player("placed") ~= drawn_player_placed or game.mission_map.player("x") ~= drawn_player_x
	or game.mission_map.player("y") ~= drawn_player_y
end

local function marker_groups()
local groups = {}
for index = 1, #offers do
	if placed(index) then
		local x, y = game.mission_map.offer(index, "x"), game.mission_map.offer(index, "y")
		local joined
		for _, group in ipairs(groups) do
			if math.abs(group.x - x) * map_scale < MARKER_REACH * 2 and math.abs(group.y - y) * map_scale < MARKER_REACH * 2 then
				joined = group
				break
			end
		end
		if joined then
			joined[#joined + 1] = index
		else
			groups[#groups + 1] = { x = x, y = y, index }
		end
	end
end
return groups
end

local function marker_spots(groups)
local spots = {}
for _, group in ipairs(groups) do
	if #group == 1 then
		spots[group[1]] = { x = group.x, y = group.y }
	else
		local spaced = (MARKER_REACH + MARKER_GAP / 2) / math.sin(math.pi / #group)
		local ring = math.max(spaced, MARKER_REACH + LEADER_LENGTH) / map_scale
		for slot, index in ipairs(group) do
			local angle = FULL_TURN * (slot - 1) / #group - math.pi / 2
			spots[index] = { x = group.x + ring * math.cos(angle), y = group.y + ring * math.sin(angle) }
		end
	end
end
return spots
end

local function draw_marker(index, spot, selected)
local radius = (selected and SELECTED_RADIUS or MARKER_RADIUS) / map_scale
local outline = radius + MARKER_RIM / map_scale
if selected then
	outline = radius + SELECTED_HALO / map_scale
	disc(spot.x, spot.y, outline, MARKER_HALO)
end
game.mission_map.target(index, spot.x, spot.y, outline)
disc(spot.x, spot.y, radius + MARKER_RIM / map_scale, MARKER_INK)
disc(spot.x, spot.y, radius, MARKER_FILL)
map_view.text(tostring(index), spot.x, spot.y, MARKER_TEXT_SIZE / map_scale, MARKER_INK)
end

local function selected_offer()
for index, offer in ipairs(offers) do
	if offer.selected and placed(index) then
		return index
	end
end
end

local function centre_on(x, y)
map_view.pan(x - map_view.read("width") / 2, y - map_view.read("height") / 2)
end

local function centre_on_offers()
local left, top, right, bottom
for index = 1, #offers do
	if placed(index) then
		local x, y = game.mission_map.offer(index, "x"), game.mission_map.offer(index, "y")
		left, right = math.min(left or x, x), math.max(right or x, x)
		top, bottom = math.min(top or y, y), math.max(bottom or y, y)
	end
end
if not left then
	centre_on(game.mission_map.planet("x"), game.mission_map.planet("y"))
	return
end
if game.mission_map.player("placed") ~= 0 then
	local x, y = game.mission_map.player("x"), game.mission_map.player("y")
	left, right = math.min(left, x), math.max(right, x)
	top, bottom = math.min(top, y), math.max(bottom, y)
end
local chosen = selected_offer()
if chosen and (right - left > map_view.read("width") or bottom - top > map_view.read("height")) then
	centre_on(game.mission_map.offer(chosen, "x"), game.mission_map.offer(chosen, "y"))
else
	centre_on((left + right) / 2, (top + bottom) / 2)
end
end

-- Bring a newly selected offer into view when it is off screen.
local function reveal_selected()
local chosen = selected_offer()
if not chosen or chosen == revealed then
	revealed = chosen
	return
end
revealed = chosen
local x, y = game.mission_map.offer(chosen, "x"), game.mission_map.offer(chosen, "y")
local left, top = map_view.read("x"), map_view.read("y")
local reach = (SELECTED_RADIUS + SELECTED_HALO) / map_scale
if x - reach < left or y - reach < top or x + reach > left + map_view.read("width")
	or y + reach > top + map_view.read("height") then
	centre_on(x, y)
end
end

draw_map_markers = function()
if not show_map or map_records == 0 or map_fit_pending then
	return
end
reveal_selected()
local groups = marker_groups()
local spots = marker_spots(groups)
game.mission_map.clear_targets()
map_view.markers_begin()
for _, pass in ipairs({ { LEADER_WIDTH + 2 * LEADER_BORDER, MARKER_INK }, { LEADER_WIDTH, MARKER_FILL } }) do
	for _, group in ipairs(groups) do
		if #group > 1 then
			for _, index in ipairs(group) do
				map_view.line(group.x, group.y, spots[index].x, spots[index].y, pass[1] / map_scale, pass[2])
			end
		end
	end
end
for _, group in ipairs(groups) do
	if #group > 1 then
		disc(group.x, group.y, DOOR_RADIUS / map_scale, MARKER_INK)
	end
end
local chosen
for index, offer in ipairs(offers) do
	if spots[index] then
		if offer.selected then
			chosen = index
		else
			draw_marker(index, spots[index], false)
		end
	end
end
if chosen then
	draw_marker(chosen, spots[chosen], true)
end
drawn_player_placed = game.mission_map.player("placed")
drawn_player_x, drawn_player_y = game.mission_map.player("x"), game.mission_map.player("y")
if drawn_player_placed ~= 0 then
	map_view.sprite(PLAYER_MARKER, drawn_player_x, drawn_player_y, 0, 1 / map_scale)
end
map_view.markers_end()
end

local function set_wheel_step(step, x, y)
wheel_step = step
map_scale = 2 ^ (wheel_step / WHEEL_STEPS_PER_DOUBLING)
map_view.zoom(map_scale, x, y)
end

-- Show one detail level of the atlas, centred on the offers.
local function show_map_record(zoom)
map_zoom = math.max(0, math.min(map_records - 1, zoom))
wheel_turn = 0
set_wheel_step(0, 0, 0)
game.mission_map.record(map_zoom)
centre_on_offers()
revealed = selected_offer()
draw_map_markers()
ui.enabled(map_zoom_in, map_zoom < map_records - 1)
ui.enabled(map_zoom_out, map_zoom > 0)
end

local function fit_map()
local view_width, view_height = map_view.read("width") or 0, map_view.read("height") or 0
if map_records > 0 and view_width > 0 and view_height > 0 then
	map_fit_pending = false
	show_map_record(game.mission_map.fit(view_width, view_height))
end
end

ui.on_click(map_zoom_in, function() if not map_fit_pending then show_map_record(map_zoom + 1) end end)
ui.on_click(map_zoom_out, function() if not map_fit_pending then show_map_record(map_zoom - 1) end end)
ui.on_click(map_fit, function() if map_records > 0 then fit_map() end end)

-- Native wheel over the map: three detents per doubling, up to two doublings in.
function mission_terminal_map_wheel(turn, x, y)
if not show_map or map_records == 0 or map_fit_pending then
	return
end
wheel_turn = wheel_turn + turn
local detents = wheel_turn < 0 and math.ceil(wheel_turn) or math.floor(wheel_turn)
wheel_turn = wheel_turn - detents
local step = math.max(0, math.min(MAX_WHEEL_STEPS, wheel_step + detents))
if step == wheel_step then
	return
end
set_wheel_step(step, x, y)
draw_map_markers()
end

-- The game refreshes the map here: a new revision / record count means new offers or a new
-- atlas, so fit again once the surface has a size; otherwise follow the player.
function mission_terminal_map(revision, records)
if revision ~= map_revision or records ~= map_records then
	map_revision, map_records = revision, records
	map_fit_pending = true
	ui.enabled(map_zoom_in, false)
	ui.enabled(map_zoom_out, false)
end
if not show_map then
	return
end
if map_fit_pending then
	fit_map()
elseif map_records > 0 and player_moved() then
	draw_map_markers()
end
end

-- Dragging the divider: the window keeps its size, the list and the map trade width.
local drag
ui.on_pointer(splitter, function(phase, x)
	if phase == "hover" then
		ui.cursor(splitter, "horizontal")
	elseif phase == "start" then
		ui.capture_pointer(splitter)
		ui.cursor(splitter, "horizontal")
		ui.fill_color(splitter_line, "#4FB3BF")
		drag = { x = x, list = list_width }
	elseif drag and (phase == "move" or phase == "end") then
		local size = sizes.map
		if size then
			local wanted = drag.list + (x - drag.x)
			list_target = math.max(width, math.min(wanted, size[1] - SPLITTER - MAP_MIN_WIDTH))
			frame:resize(size[1], size[2])
		end
		if phase == "end" then
			drag = nil
			ui.fill_color(splitter_line, "#232831")
			if list_target then
				ui.preference.write("modern_mission_list_width", tostring(math.floor(list_target + 0.5)), "text")
			end
		end
	elseif phase == "cancel" then
		drag = nil
		ui.fill_color(splitter_line, "#232831")
	end
end)

toggle_map = function()
show_map = not show_map
ui.preference.write("modern_mission_map", tostring(show_map), "bool")
ui.menu.checked(frame.icon, MAP_ITEM, show_map)
ui.visible(offer_map, show_map)
ui.visible(splitter, show_map)
map_fit_pending = true -- the surface was hidden or resized: fit once it has its new size
frame:resize(0, 0) -- this view's own remembered size
if show_map then
	local frames = 0
	ui.on_update(function()
		frames = frames + 1
		if not show_map or not map_fit_pending or frames > 60 then
			ui.stop_updates()
			return
		end
		if map_records > 0 then fit_map() end
	end)
end
end
ui.visible(offer_map, show_map)
ui.visible(splitter, show_map)
ui.enabled(map_zoom_in, false)
ui.enabled(map_zoom_out, false)
