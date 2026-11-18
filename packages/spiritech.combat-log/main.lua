-- Combat Log: compact, colour-coded combat feed in the dark flat style (standalone addon,
-- Actions -> Addons -> Combat Log). Built from the structured combat stream, not chat lines.
--
--   ▶ Target     512   melee     your (or your pet's) hit       white, crits amber
--   ◀ Attacker    86   melee     a hit on you (or your pet)     red
--   + Healer     340   heal      healing you give or receive    green
--   ▶ Target    miss             misses / absorbs in grey
--
-- Crits get a tinted row with a left accent: amber for yours, red for crits on you.
--
-- Header: DPS for the current fight (resets after 8s without your damage), its length and
-- total, plus Out / In / Heal filters and Clear. Newest row at the bottom; scroll up (mouse
-- wheel or scrollbar) for the last 200 matching events, and it stops following new lines
-- until you scroll back to the bottom.
pcall(ui.require, "spiritech.modern-common/screenfit") -- keep window positions through fullscreen changes
local Window = ui.require("core.window")
local Theme = ui.require("spiritech.modern-common/theme")

local WIDTH, HEIGHT = 340, 220
local MIN_WIDTH, MIN_HEIGHT = 240, 100
local KEEP = 300 -- events kept for filtering / resizing
local FIGHT_IDLE = 8 -- seconds without your damage that end a fight

local COLORS = {
	out = "#4FB3BF",
	incoming = "#FF6B5E",
	heal = "#5FD07A",
	crit = "#F0C060",
	text = Theme.color.text,
	muted = "#8B95A3",
	dim = "#A3ADBA",
	off = "#5E6875",
}
-- Crit row background (about 18% opacity) and 2px accent, by direction.
local CRIT_ROW = {
	out = { tint = "#2EF0C060", accent = "#F0C060" },
	incoming = { tint = "#33FF6B5E", accent = "#FF6B5E" },
}
local GLYPHS = { out = "▶", incoming = "◀", heal = "+", death = "×" }

-- Damage type names (stat IDs from the client where available).
local DAMAGE_TYPES = {}
do
	local names = {
		projectileac = "projectile", meleeac = "melee", energyac = "energy", chemicalac = "chemical",
		radiationac = "radiation", coldac = "cold", poisonac = "poison", fireac = "fire", nanoac = "nano",
	}
	for stat, label in pairs(names) do
		local ok, id = pcall(function() return ui.combat and ui.combat.stat(stat) end)
		if ok and type(id) == "number" and id > 0 then DAMAGE_TYPES[id] = label end
	end
	-- Fallback: Anarchy Online's AC stat IDs, used when the client lookup isn't available here.
	for id, label in pairs({
		[90] = "projectile", [91] = "melee", [92] = "energy", [93] = "chemical",
		[94] = "radiation", [95] = "cold", [96] = "poison", [97] = "fire",
	}) do
		if DAMAGE_TYPES[id] == nil then DAMAGE_TYPES[id] = label end
	end
end

local root = ui.load("root.xml")
ui.root(root)
local content = ui.load("content.xml")
local rows_host = ui.find(content, "log_rows")
local scroll = ui.find(content, "log_scroll")
local SHOWN = 200 -- most recent filtered events kept on screen (scroll up for older ones)
local summary = ui.find(content, "log_summary")
local measure = ui.find(content, "log_measure")
local filter_buttons = {
	out = ui.find(content, "filter_out"),
	incoming = ui.find(content, "filter_in"),
	heal = ui.find(content, "filter_heal"),
}

local filters = { out = true, incoming = true, heal = true }
for key in pairs(filters) do
	local saved = ui.preference.read("filter_" .. key)
	if saved ~= "" then filters[key] = saved == "true" end
end

local events = {} -- newest last
local rows = {}
local name_width = 120
local shown = true

-- Fight tracking for the DPS line.
local fight = { start = nil, last = nil, damage = 0 }

local describe, show_copy -- copy box helpers, defined further down

local function row(index)
	if rows[index] then return rows[index] end
	local loaded = ui.load("row.xml")
	ui.add(rows_host, loaded)
	local view = ui.find(loaded, "log_row") or loaded
	local entry = {
		view = view,
		glyph = ui.find(view, "row_glyph"),
		name = ui.find(view, "row_name"),
		amount = ui.find(view, "row_amount"),
		type = ui.find(view, "row_type"),
		tint = ui.find(view, "row_tint"),
		accent = ui.find(view, "row_accent"),
	}
	ui.text_alignment(entry.amount, "right")
	ui.on_click(view, function()
		if entry.entry then show_copy(describe(entry.entry)) end
	end)
	rows[index] = entry
	return entry
end

local fitted = {}
local function fit(name)
	local key = name .. "\0" .. name_width
	if fitted[key] then return fitted[key] end
	local function width(text)
		ui.text(measure, text)
		return ui.text_width(measure)
	end
	local result = name
	if width(name) > name_width then
		local low, high = 0, #name
		while low < high do
			local middle = math.floor((low + high + 1) / 2)
			if width(name:sub(1, middle) .. "...") <= name_width then low = middle else high = middle - 1 end
		end
		result = name:sub(1, low):gsub("%s+$", "") .. "..."
	end
	fitted[key] = result
	return result
end

local function damage_word(event)
	if event.origin == "special" then return "special" end
	if event.origin == "reflect" then return "reflect" end
	if event.origin == "shield" then return "shield" end
	local word = DAMAGE_TYPES[event.damage_type]
	if word then return word end
	-- The game only reports a weapon hit's type when it knows it.
	if event.origin == "weapon" then return "weapon" end
	return event.damage_type ~= 0 and ("type " .. event.damage_type) or ""
end

-- Turns a raw observation into a display entry, or nil if it doesn't involve you.
local function classify(event)
	local mine_out = event.source_is_self or event.source_is_my_pet
	local mine_in = event.target_is_self or event.target_is_my_pet
	local kind = event.kind
	if kind == "healing" then
		if not (mine_out or mine_in) then return nil end
		local name = mine_in and (event.source_is_self and "You" or event.source_name) or event.target_name
		return { group = "heal", glyph = GLYPHS.heal, name = name, amount = event.amount, word = "heal",
			color = COLORS.heal, glyph_color = COLORS.heal }
	elseif kind == "damage" or kind == "miss" or kind == "absorb" then
		local group = mine_out and "out" or mine_in and "incoming" or nil
		if not group then return nil end
		local name = group == "out" and event.target_name or event.source_name
		local entry = { group = group, glyph = GLYPHS[group], name = name, word = damage_word(event),
			glyph_color = COLORS[group] }
		if kind == "miss" then
			entry.amount_text, entry.color = "miss", COLORS.muted
		elseif kind == "absorb" then
			entry.amount, entry.color, entry.word = event.amount, COLORS.muted, "absorbed"
		else
			entry.amount = event.amount
			if event.critical then
				entry.critical = true
				entry.color = group == "incoming" and COLORS.incoming or COLORS.crit
				entry.word = ("CRIT " .. entry.word):gsub("%s+$", "")
			else
				entry.color = group == "incoming" and COLORS.incoming or COLORS.text
			end
		end
		if event.source_is_my_pet and group == "out" then entry.word = ("pet " .. entry.word):gsub("%s+$", "") end
		return entry
	elseif kind == "death" then
		if not (mine_out or mine_in) and not event.target_is_self then return nil end
		return { group = "out", glyph = GLYPHS.death, name = event.target_is_self and "You" or event.target_name,
			amount_text = "died", word = "", color = COLORS.dim, glyph_color = COLORS.dim, always = true }
	end
	return nil
end

-- Plain-text version of a row, for the copy box.
describe = function(entry)
	local name = entry.name ~= "" and entry.name or "?"
	local amount = entry.amount and Theme.thousands(entry.amount) or entry.amount_text or ""
	local word = entry.word ~= "" and (" " .. entry.word:gsub("CRIT%s*", "")) or ""
	if entry.glyph == GLYPHS.death then
		return name .. " died"
	elseif entry.group == "heal" then
		return name .. " healed " .. amount
	elseif entry.amount_text == "miss" then
		return entry.group == "out" and ("Missed " .. name) or (name .. " missed you")
	elseif entry.critical and entry.group == "incoming" then
		return string.format("Crit! %s hit you for %s%s damage", name, amount, word)
	elseif entry.critical then
		return string.format("Crit! %s%s damage on %s", amount, word, name)
	elseif entry.group == "out" then
		return string.format("Hit %s for %s%s damage", name, amount, word)
	end
	return string.format("%s hit you for %s%s damage", name, amount, word)
end

local copy_bar = ui.find(content, "copy_bar")
local copy_text = ui.find(content, "copy_text")
show_copy = function(text)
	ui.text(copy_text, text)
	ui.visible(copy_bar, true)
end
ui.on_click(ui.find(content, "copy_close"), function() ui.visible(copy_bar, false) end)

local best -- your best crit since the log was cleared

local function update_summary(now)
	if not fight.start then
		ui.text(summary, "No combat yet")
		return
	end
	local length = math.max(1, (fight.last or fight.start) - fight.start)
	local dps = math.floor(fight.damage / length + 0.5)
	local active = now and fight.last and (now - fight.last) <= FIGHT_IDLE
	local text = string.format("%s %s  ·  %ds  ·  %s dmg", active and "DPS" or "Last fight DPS",
		Theme.thousands(dps), math.floor(length + 0.5), Theme.thousands(fight.damage))
	if best then text = text .. "  ·  best crit " .. Theme.thousands(best.amount) end
	ui.text(summary, text)
end

local function render()
	if not shown then return end
	-- Oldest at the top, newest at the bottom; follow the newest line unless scrolled up.
	local list = {}
	for index = #events, 1, -1 do
		local entry = events[index]
		if entry.always or filters[entry.group] then
			list[#list + 1] = entry
			if #list >= SHOWN then break end
		end
	end
	local ok, at_end = pcall(ui.at_scroll_end, scroll)
	local follow = not ok or at_end
	local count = #list
	for index = 1, count do
		local view = row(index)
		local entry = list[count - index + 1]
		if view.entry ~= entry then
			view.entry = entry
			ui.visible(view.view, true)
			ui.text(view.glyph, entry.glyph)
			ui.text_color(view.glyph, entry.glyph_color)
			ui.text(view.name, fit(entry.name ~= "" and entry.name or "?"))
			ui.text(view.amount, entry.amount_text or Theme.thousands(entry.amount or 0))
			ui.text_color(view.amount, entry.color)
			ui.text(view.type, entry.word or "")
			ui.text_color(view.type, entry.critical and entry.color or COLORS.muted)
			local crit = entry.critical and CRIT_ROW[entry.group]
			ui.fill_color(view.tint, crit and crit.tint or "")
			ui.fill_color(view.accent, crit and crit.accent or "")
		end
	end
	for index = count + 1, #rows do
		if rows[index].entry ~= false then
			rows[index].entry = false
			ui.visible(rows[index].view, false)
		end
	end
	if follow then ui.scroll_end(scroll) end
end

local function paint_filters()
	for key, button in pairs(filter_buttons) do
		ui.text_color(button, filters[key] and COLORS.text or COLORS.off)
	end
end

local frame = Window.create({
	template = Theme.WINDOW_TEMPLATE,
	title = "Combat",
	content = content,
	width = WIDTH,
	height = HEIGHT,
	horizontal = "end",
	vertical = "end",
	layout = function(window, width, height)
		ui.limits(window.root, MIN_WIDTH, MIN_HEIGHT, 1200, 1200)
		ui.request_size(window.root, width, height)
		width, height = ui.chosen_width(window.root), ui.chosen_height(window.root)
		window:fit_title(width, true)
		window:fit_content(width, height)
		-- name column = row width - padding - glyph - amount - type - scrollbar
		name_width = math.max(40, width - 11 - 8 - 14 - 56 - 72 - 10)
		fitted = {}
		for _, view in ipairs(rows) do view.entry = nil end -- re-fit names
		render()
	end,
})
ui.add(root, frame.root)
ui.register_view(frame.root, "log")

for key, button in pairs(filter_buttons) do
	ui.on_click(button, function()
		filters[key] = not filters[key]
		ui.preference.write("filter_" .. key, tostring(filters[key]), "bool")
		paint_filters()
		render()
	end)
end
ui.on_click(ui.find(content, "log_clear"), function()
	events = {}
	fight = { start = nil, last = nil, damage = 0 }
	best = nil
	update_summary()
	render()
end)

ui.on_click(summary, function()
	if best then show_copy(describe(best)) end
end)

ui.on_visibility(frame.root, function(visible)
	shown = visible
	if shown then render() end
end)

game.combat.subscribe("damage,healing,miss,absorb,death", function(batch, observed)
	if batch.reset then
		fight = { start = nil, last = nil, damage = 0 }
	end
	local now
	for _, event in ipairs(observed) do
		now = event.elapsed
		local entry = classify(event)
		if entry then
			events[#events + 1] = entry
			if #events > KEEP then table.remove(events, 1) end
			if entry.critical and entry.group == "out" and (not best or entry.amount > best.amount) then
				best = entry
			end
			if event.kind == "damage" and entry.group == "out" then
				if not fight.last or event.elapsed - fight.last > FIGHT_IDLE then
					fight = { start = event.elapsed, last = event.elapsed, damage = 0 }
				end
				fight.last = event.elapsed
				fight.damage = fight.damage + event.amount
			end
		end
	end
	update_summary(now)
	render()
end)

paint_filters()
update_summary()
