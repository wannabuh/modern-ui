-- Modern Mission Terminal, terminal half (role prk.mission-terminal): offers as a list.
--   Row: icon | the reward item names once known | the server's short summary.
--   Click selects (as the stock slot does); inspecting with the modifier held stays native.
--   The server sends no reward data with an offer (summary is cut to ~28 characters, icon
--   is a slot handle), so rewards come from the Info half: clicking a row writes storage
--   "inspect_pending" = "<offer key>\t<ms>"; the Info page that opens next records its
--   item names under "rewards" (lines "<offer key>\t<name>\t<name>..."); rows poll that.
-- The rest (reward mode, chosen reward, sliders, request / accept / cancel) is the stock
-- window's logic in the flat palette. Every reply is logged to storage "terminal_log".
function BUILD_TERMINAL()
local Window = ui.require("core.window")
local Theme = ui.require("spiritech.modern-common/theme")

local WIDTH, MAX_OFFERS, LINES = 360, 6, 3
local REWARD_COLOR, SUMMARY_COLOR, HINT_COLOR = "#F0C060", "#A3ADBA", "#5E6875"
local TEXT_ROOM_PAD = 4 + 36 + 8 + 6 + 6 -- row borders + icon + text gap + right pad + slack

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
local session = tostring(ui.time())
local generation, last_summaries = 0, nil
local rewards, rewards_raw = {}, nil -- offer key -> { names }

local function offer_key(index)
	return session .. ":" .. generation .. ":" .. index
end

local function read_rewards()
	local ok, raw = pcall(ui.storage.read, "rewards")
	raw = ok and raw or ""
	if raw == rewards_raw then return false end
	rewards_raw, rewards = raw, {}
	for line in (raw .. "\n"):gmatch("(.-)\n") do
		local fields = {}
		for field in (line .. "\t"):gmatch("(.-)\t") do fields[#fields + 1] = field end
		if #fields >= 1 and fields[1] ~= "" then
			rewards[fields[1]] = { table.unpack(fields, 2) }
		end
	end
	return true
end

local function show_offers()
	local room = width - Window.CONTENT_SIDES - 8 - TEXT_ROOM_PAD
	for index, row in ipairs(rows) do
		local offer = offers[index]
		if offer and offer.reference ~= 0 then
			local summary = plain(offer.description)
			local names = rewards[offer_key(index)]
			if not names then
				local by_title = rewards[session .. ":" .. generation .. ":title:" .. summary]
				if by_title then
					local matches = 0
					for _, other in ipairs(offers) do
						if plain(other.description) == summary then matches = matches + 1 end
					end
					if matches == 1 then names = by_title end
				end
			end
			ui.bind(row.root, offer.reference)
			ui.action(row.root, "game.mission_terminal.choose", offer.reference, "left")
			ui.selected(row.root, offer.selected)
			ui.content(row.icon, true)
			ui.icon(row.icon, offer.icon)
			local lines = {}
			if names then
				local text = #names > 0 and table.concat(names, " · ") or "No item reward"
				for _, line in ipairs(wrap(text, room, 2)) do lines[#lines + 1] = { line, REWARD_COLOR } end
			end
			for _, line in ipairs(wrap(summary, room, LINES - #lines)) do lines[#lines + 1] = { line, SUMMARY_COLOR } end
			if #lines == 0 then lines[1] = { "Mission " .. index, SUMMARY_COLOR } end
			if not names and #lines < LINES then lines[#lines + 1] = { "Inspect to see the reward", HINT_COLOR } end
			ui.tooltip(row.root, names and (table.concat(names, "\n") .. "\n\n" .. summary) or summary)
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

-- Pressing a row (select or inspect) marks it as the offer the next Info page belongs to.
-- on_pointer "start" is used because on_click does not fire on these command-bound rows.
local function mark(index)
	local offer = offers[index]
	if offer then
		pcall(ui.storage.write, "inspect_pending", offer_key(index) .. "\t" .. tostring(ui.time())
			.. "\t" .. plain(offer.description):gsub("[\t\n]", " "))
	end
end
for index, row in ipairs(rows) do
	ui.on_pointer(row.root, function(phase)
		if phase == "start" then mark(index) end
	end)
	ui.on_click(row.root, function() mark(index) end)
end

-- Pick up reward names the Info half wrote (polled while offers are shown).
local next_poll = 0
ui.on_update(function(now)
	if now < next_poll then return end
	next_poll = now + 300
	if #offers > 0 and read_rewards() then show_offers() end
end)

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

-- ------------------------------------------------------------------ diagnostic
local replies = 0
local function log_reply(state, list_offers, reward)
	replies = replies + 1
	local out = { string.format("reply %d  offers=%d  selected=%s", replies, #list_offers, tostring(state.selected)) }
	for index, offer in ipairs(list_offers) do
		out[#out + 1] = string.format("#%d ref=%s icon=%s selected=%s", index, tostring(offer.reference),
			tostring(offer.icon), tostring(offer.selected))
		out[#out + 1] = "  " .. (offer.description or ""):gsub("\r", ""):gsub("\n", "\\n\n  ")
	end
	out[#out + 1] = string.format("reward pinned_mode=%s has_pin=%s name=%s ql=%s icon=%s cost=%s",
		tostring(reward.pinned_mode), tostring(reward.has_pin), tostring(reward.name), tostring(reward.ql),
		tostring(reward.icon), tostring(reward.cost))
	pcall(ui.storage.write, "terminal_log", table.concat(out, "\n"))
end

function mission_terminal_apply(state, list_offers, reward)
	pcall(log_reply, state, list_offers, reward)
	local summaries = {}
	for index, offer in ipairs(list_offers) do summaries[index] = tostring(offer.description) end
	summaries = table.concat(summaries, "\0")
	if summaries ~= last_summaries then
		last_summaries, generation = summaries, generation + 1
		pcall(ui.storage.write, "offer_set", session .. ":" .. generation)
	end
	offers = list_offers
	read_rewards()
	ui.visible(empty, #offers == 0)
	show_offers()
	command(request, "game.mission_terminal.request", state.request)
	ui.enabled(request, not reward.pinned_mode or reward.has_pin)
	apply_reward(reward)
	command(accept, "game.mission_terminal.accept", state.accept)
	ui.enabled(accept, state.selected)
	command(cancel, "game.mission_terminal.cancel", state.cancel)
end
end
