-- Modern Mission Terminal (role prk.mission-terminal): offers as a list.
--   Row: icon | the server's summary (cut to ~28 characters by the server).
--   Click selects (as the stock slot does); inspecting with the modifier held stays native,
--   and the (restyled) Info window names the reward item.
-- The rest (reward mode, chosen reward, sliders, request / accept / cancel) is the stock
-- window's logic in the flat palette.
pcall(ui.require, "spiritech.modern-common/screenfit") -- keep window positions through fullscreen changes
local Window = ui.require("core.window")
local Theme = ui.require("spiritech.modern-common/theme")

local WIDTH, MAX_OFFERS, LINES = 360, 6, 2
local TEXT_ROOM_PAD = 4 + 32 + 8 + 6 + 6 -- row borders + icon + text gap + right pad + slack

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
local width = WIDTH
local show_advanced = ui.preference.read("show_advanced_options") == "true"

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

local function markup(lines)
local pieces = {}
for _, line in ipairs(lines) do
	pieces[#pieces + 1] = string.format("<font color=%s>%s</font>", line[2], escape(line[1]))
end
return table.concat(pieces, "<br>")
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
}
ui.visible(root, false)
end

local offers = {}

local function show_offers()
local room = width - Window.CONTENT_SIDES - 8 - TEXT_ROOM_PAD
for index, row in ipairs(rows) do
	local offer = offers[index]
	if offer and offer.reference ~= 0 then
		local summary = plain(offer.description)
		ui.bind(row.root, offer.reference)
		ui.action(row.root, "game.mission_terminal.choose", offer.reference, "left")
		ui.selected(row.root, offer.selected)
		ui.content(row.icon, true)
		ui.icon(row.icon, offer.icon)
		local lines = {}
		for line_index, line in ipairs(wrap(summary, room, LINES)) do
			lines[line_index] = { line, line_index == 1 and Theme.color.text or "#A3ADBA" }
		end
		if #lines == 0 then lines[1] = { "Mission " .. index, Theme.color.text } end
		local texts = {}
		for line_index, line in ipairs(lines) do texts[line_index] = line[1] end
		ui.text(row.text, table.concat(texts, "\n"))
		pcall(ui.aoml, row.text, "", markup(lines), false)
		ui.visible(row.root, true)
	else
		ui.visible(row.root, false)
	end
end
end

-- ------------------------------------------------------------------ window
local frame = Window.create({
template = Theme.WINDOW_TEMPLATE,
title = "Mission Terminal",
remember_open = false,
content = content,
width = width,
resizable = false,
horizontal = "center",
vertical = "center",
layout = function(window)
	ui.size(window.root, width, -1)
	ui.size(content, width - Window.CONTENT_SIDES, -1)
	window:fit_title(width, true)
end,
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
frame:resize(width, -1)
show_offers()
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
command(request, "game.mission_terminal.request", state.request)
ui.enabled(request, not reward.pinned_mode or reward.has_pin)
apply_reward(reward)
command(accept, "game.mission_terminal.accept", state.accept)
ui.enabled(accept, state.selected)
command(cancel, "game.mission_terminal.cancel", state.cancel)
end
