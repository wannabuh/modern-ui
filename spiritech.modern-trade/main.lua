-- Modern Trade (role prk.trade): the Trade window as flat lists, like Modern Inventory.
--
--   Player trade:  THEIR OFFER [Waiting] 1,000      Shop:  SHOP  ·  Name QL Price
--                  YOUR OFFER  [Accepted] [credits]        BOUGHT            cost
--                  [Accept] [Decline]                      SOLD
--                                                          [search] Balance  [Accept] [Decline]
--
-- Every row: icon, name, then "×count · QL · weapon damage · implant modifiers" and a line
-- of requirements (unmet ones red), from spiritech.modern-common/reqs.
--
-- Clicks are the game's: shop row left-click buys, bought row right-click returns, your
-- offered row left/right-click removes. Credits entry, drops, tooltips, pricing and
-- confirmation all stay native (the game finds `our_cash` and the docks by name).
--
-- Change warning (player trades): items the partner adds light up amber, items they take
-- away stay listed in red as "removed", and their status pill reads "Changed", for a few
-- seconds. Their credits flash too.
-- Unusable goods (title menu, or right-click a shop row): show / dim / hide shop goods whose
-- requirements you don't meet.
pcall(ui.require, "spiritech.modern-common/screenfit") -- keep window positions through fullscreen changes
local Window = ui.require("core.window")
local Security = ui.require("core.security")
local Reqs
do
	local ok, module = pcall(ui.require, "spiritech.modern-common/reqs")
	Reqs = ok and module or nil
end

local ROW2, ROW3 = 38, 54 -- row heights incl. 2px gap: two lines / details + requirements lines
local GAP = 2
local HEADER = 23 -- section header + divider
local FOOTER = 29 -- divider + buttons row
local ENDS = 33 -- window chrome (see modern-common/window.xml)
local SCROLLBAR = 8
local MIN_WIDTH, MAX_WIDTH, MAX_HEIGHT = 300, 900, 1200
local SIDE_MAX_ROWS = 4 -- bought / sold lists in a shop grow to this many rows, then scroll
local FLASH_MS = 8000
local SEPARATOR = "  ·  "
local DIMMED, MISSING = 0.45, 0.3
local ROW_FILL = { "#FF12161C", "#FF181D25" } -- zebra

local COLOR = {
	name = "#E8ECF1", name_dim = "#7D8794", detail = "#A3ADBA", unmet = "#FF7A70", match = "#F0C060",
	mod = "#8FD6A0", mod_negative = "#FF7A70", mod_unknown = "#6E7885",
	removed = "#FF8A80", gain = "#8FD6A0", loss = "#FF7A70",
	chip = "#8B95A3", chip_active = "#4FB3BF",
}
local ADDED = { tint = "#2EF0C060", accent = "#F0C060" }
local REMOVED = { tint = "#26FF6B5E", accent = "#FF6B5E" }
local PILL = {
	waiting = { fill = "#FF2A3039", text = "#A3ADBA", label = "Waiting" },
	accepted = { fill = "#FF2F6E45", text = "#FFFFFF", label = "Accepted" },
	changed = { fill = "#FF8C6520", text = "#FFFFFF", label = "Changed" },
}

local function pref(key, default)
	local value = ui.preference.read("modern_trade_" .. key)
	return value ~= "" and value or default
end
local options = {
	sort = pref("sort", "name"),
	descending = pref("descending", "false") == "true",
	unusable = pref("unusable", "show") == "hide" and "hide" or "show", -- show | hide
}
local function save_option(key, value, kind)
	options[key] = value
	ui.preference.write("modern_trade_" .. key, tostring(value), kind or "text")
end

local content = ui.load("content.xml")
local function find(name) return ui.find(content, name) end
local measure = find("trade_measure")
local menu_anchor = find("trade_menu")
local accept, decline = find("accept_button"), find("decline_button")
local our_cash, our_balance, partner_cash = find("our_cash"), find("our_balance"), find("partner_cash")

local function section(prefix, actions, dock, host)
	return {
		root = find(prefix .. "_section"), frame = find(prefix .. "_frame"), dock = find(dock or (prefix .. "_dock")),
		host = find(host or (prefix .. "_slots")), empty = find(prefix .. "_empty"), count = find(prefix .. "_count"),
		label = find(prefix .. "_label"), actions = actions, rows = {}, items = {}, by_token = {}, height = 0,
	}
end
local shop = section("shop", { { "game.trade.buy", "left" } })
local partner = section("partner", { { "game.trade.return_bought", "right" } })
local ours = section("our", { { "game.trade.remove", "left" }, { "game.trade.remove_right", "right" } },
	"our_list", "our_rows")

-- Drop strip: empty item slots under your offer. The game takes inventory drops on these,
-- as on the stock window's spare grid cells (empty, unbound cells = drop targets).
local DROP, DROP_CELL = 42, 38 -- strip height; cell + spacing
local drop_grid = find("our_slots")
local drop_cells = ui.require("core.icon_grid").cells({
	host = drop_grid,
	template = "drop_slot.xml",
	binding = function(entry) return entry.token end,
})
local drop_count = 0
local function size_drop(width)
	local count = math.max(1, math.floor((width - Window.CONTENT_SIDES - 4 + 2) / DROP_CELL))
	if count == drop_count then return end
	drop_count = count
	ui.grid_columns(drop_grid, count)
	drop_cells:show({}, count)
end
local SECTIONS = { shop, partner, ours }

local state = { mode = 0, partner_name = "", partner_cash = "", our_balance = "" }
local frame, open_menu, relayout
local text_width = 200 -- width available to a row's text (set by layout)

-- ------------------------------------------------------------------ text helpers
local function escape(text)
	return (text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

local measured = {}
local function width_of(text)
	local known = measured[text]
	if known then return known end
	ui.text(measure, text)
	local ok, value = pcall(ui.text_width, measure)
	value = ok and value or #text * 6
	measured[text] = value
	return value
end

local fitted = {}
local function fit(name, width)
	local key = name .. "\0" .. width
	if fitted[key] then return fitted[key] end
	local result = name
	if width_of(name) > width then
		local low, high = 0, #name
		while low < high do
			local middle = (low + high + 1) // 2
			if width_of(name:sub(1, middle) .. "...") <= width then low = middle else high = middle - 1 end
		end
		result = name:sub(1, low):gsub("%s+$", "") .. "..."
	end
	fitted[key] = result
	return result
end

local function plain(parts)
	local texts = {}
	for index, part in ipairs(parts) do texts[index] = part.text end
	return table.concat(texts, SEPARATOR)
end

-- Drop parts from the end (never below `keep`) until the line fits.
local function fit_parts(parts, keep, width)
	while #parts > keep and width_of(plain(parts)) > width do table.remove(parts) end
	return parts
end

local function rich(parts)
	local pieces = {}
	for index, part in ipairs(parts) do
		if index > 1 then pieces[#pieces + 1] = string.format("<font color=%s>%s</font>", COLOR.detail, SEPARATOR) end
		pieces[#pieces + 1] = string.format("<font color=%s>%s</font>", part.color or COLOR.detail, escape(part.text))
	end
	return table.concat(pieces)
end

-- Detail parts for an item: line 2 (count, QL, damage, implant modifiers), requirements,
-- and whether any requirement is unmet.
local details_cache = {}
local function details(entry)
	local key = entry.name .. "|" .. tostring(entry.quality) .. "|" .. tostring(entry.count)
	local known = details_cache[key]
	if known then return known end
	local line, reqs, unusable = {}, {}, false
	if (entry.count or 1) > 1 then line[#line + 1] = { text = "×" .. entry.count } end
	line[#line + 1] = { text = "QL " .. tostring(entry.quality) }
	local keep = #line
	if Reqs then
		local damage = Reqs.damage(entry.name, entry.quality)
		if damage then line[#line + 1] = { text = damage, color = COLOR.name } end
		keep = #line
		for _, mod in ipairs(Reqs.mods(entry.name, entry.quality) or {}) do
			line[#line + 1] = { text = mod.text,
				color = mod.unknown and COLOR.mod_unknown or mod.negative and COLOR.mod_negative or COLOR.mod }
		end
		for _, req in ipairs(Reqs.parts(entry.name, entry.quality) or {}) do
			if req.met == false then unusable = true end
			reqs[#reqs + 1] = { text = req.text, color = req.met == false and COLOR.unmet or nil }
		end
	end
	known = { line = line, keep = keep, reqs = reqs, unusable = unusable }
	details_cache[key] = known
	return known
end

-- ------------------------------------------------------------------ change warning
-- Player trades only. Items are compared by name + QL + count, so swapping a stack for a
-- smaller one shows as one removed and one added.
local watch = { bag = nil, last = {}, added = {}, ghosts = {}, changed_until = 0, cash_until = 0, cash = nil }

local function key_of(entry)
	return entry.name .. "|" .. tostring(entry.quality) .. "|" .. tostring(entry.count)
end

local function watch_reset(list)
	watch.bag, watch.last, watch.added, watch.ghosts = {}, {}, {}, {}
	watch.changed_until, watch.cash_until = 0, 0
	for _, entry in ipairs(list or {}) do
		local key = key_of(entry)
		watch.bag[key] = (watch.bag[key] or 0) + 1
		watch.last[key] = { name = entry.name, quality = entry.quality, count = entry.count }
	end
end

local function watch_update(list, cash, now)
	local bag, last = {}, {}
	for _, entry in ipairs(list) do
		local key = key_of(entry)
		bag[key] = (bag[key] or 0) + 1
		last[key] = { name = entry.name, quality = entry.quality, count = entry.count }
	end
	local changed = false
	for key, count in pairs(bag) do
		if count > (watch.bag[key] or 0) then
			watch.added[key] = now + FLASH_MS
			changed = true
			for index = #watch.ghosts, 1, -1 do -- put back: no longer "removed"
				if watch.ghosts[index].key == key then table.remove(watch.ghosts, index) break end
			end
		end
	end
	for key, count in pairs(watch.bag) do
		for _ = 1, count - (bag[key] or 0) do
			local gone = watch.last[key]
			watch.ghosts[#watch.ghosts + 1] = { key = key, name = gone.name, quality = gone.quality,
				count = gone.count, ghost = true, until_time = now + FLASH_MS }
			changed = true
		end
	end
	if watch.cash ~= nil and cash ~= watch.cash then
		watch.cash_until = now + FLASH_MS
		changed = true
	end
	if changed then watch.changed_until = now + FLASH_MS end
	watch.bag, watch.last, watch.cash = bag, last, cash
	return changed
end

-- ------------------------------------------------------------------ credits
-- Your credits: the Cash stat (61). nil when unavailable (then nothing is coloured).
local CASH_STAT = 61
local cash_cache = { at = -1, value = nil }
local function my_cash()
	local now = ui.time()
	if now - cash_cache.at > 200 then
		local ok, value = false, nil
		if game and game.character and game.character.stat then
			ok, value = pcall(game.character.stat, "self", CASH_STAT, "effective")
		end
		cash_cache.at, cash_cache.value = now, ok and value or nil
	end
	return cash_cache.value
end

-- "1,234,567" / "-27,200" -> number (nil when there are no digits).
local function amount(text)
	local digits = (text or ""):gsub("[^%d]", "")
	if digits == "" then return nil end
	local value = tonumber(digits)
	return (text:find("^%s*%-") or text:find("^%s*\226\136\146")) and -value or value -- "-" or U+2212
end

-- ------------------------------------------------------------------ rows
local function set(row, field, value, apply)
	if row[field] ~= value then
		row[field] = value
		apply(value)
	end
end

local function create_row(s)
	local loaded = ui.load("row.xml")
	ui.add(s.host, loaded)
	local view = ui.find(loaded, "trade_row") or loaded
	ui.borders(view, 0, 0, 0, GAP)
	if s == shop then ui.on_pointer_release(view, "right", function() open_menu() end) end
	return {
		root = view, bg = ui.find(view, "row_bg"), icon = ui.find(view, "row_icon"), text = ui.find(view, "row_text"),
		price = ui.find(view, "row_price"), tint = ui.find(view, "row_tint"), accent = ui.find(view, "row_accent"),
	}
end

local function is_player() return state.mode == 1 end
local function is_shop() return state.mode == 2 or state.mode == 3 end
local function shows_price(s) return is_shop() and s ~= nil end

local function row_width(s) return text_width - (shows_price(s) and 74 or 0) end

-- Detail lines under the name: QL / damage / modifiers, then requirements -- on the same
-- line when everything fits, else requirements get a line of their own.
local function detail_lines(info, width)
	local line, reqs = {}, {}
	for index, part in ipairs(info.line) do line[index] = part end
	for index, part in ipairs(info.reqs) do reqs[index] = part end
	if #reqs == 0 then return { fit_parts(line, info.keep, width) } end
	local all = {}
	for _, part in ipairs(line) do all[#all + 1] = part end
	for _, part in ipairs(reqs) do all[#all + 1] = part end
	if width_of(plain(all)) <= width then return { all } end
	return { fit_parts(line, info.keep, width), fit_parts(reqs, 1, width) }
end

-- Height a row needs at the current width.
local function row_height(s, item)
	if item.ghost then return ROW2 end
	return #detail_lines(details(item.entry), row_width(s)) > 1 and ROW3 or ROW2
end

-- Dims a row's content (never the row itself: its background would turn see-through).
local function set_dim(row, alpha)
	set(row, "v_alpha", alpha, function(v)
		ui.opacity(row.icon, v)
		ui.opacity(row.price, v < 1 and math.max(v, 0.6) or 1)
	end)
end

local function present_row(s, row, item, now)
	local width = row_width(s)
	if item.ghost then
		set(row, "v_icon", false, function() ui.content(row.icon, false) end)
		set(row, "v_text", "ghost:" .. item.key .. width, function()
			local markup = string.format("<font color=%s>%s</font><br><font color=%s>removed%sQL %s%s</font>",
				COLOR.removed, escape(fit(item.name, width)), COLOR.removed, SEPARATOR, tostring(item.quality),
				(item.count or 1) > 1 and (SEPARATOR .. "×" .. item.count) or "")
			pcall(ui.aoml, row.text, "", markup, false)
		end)
		set(row, "v_price", "", function(v) ui.text(row.price, v) end)
		set(row, "v_flag", "removed", function()
			ui.fill_color(row.tint, REMOVED.tint)
			ui.fill_color(row.accent, REMOVED.accent)
		end)
		set_dim(row, 1)
		return
	end
	local entry = item.entry
	if not entry then -- in combat, this row's item left the list
		set_dim(row, MISSING)
		set(row, "v_text", "missing", function() pcall(ui.aoml, row.text, "", string.format("<font color=%s>(gone)</font>", COLOR.name_dim), false) end)
		return
	end
	local info = details(entry)
	set(row, "v_icon", entry.icon, function(v)
		ui.icon(row.icon, v)
		ui.content(row.icon, true)
	end)
	local dim = entry.search == "other" -- search non-match only; unusable goods keep full colour (red reqs say why)
	local name_color = entry.search == "match" and COLOR.match or dim and COLOR.name_dim or COLOR.name
	local markup_key = table.concat({ entry.name, tostring(entry.quality), tostring(entry.count), name_color, width }, "\0")
	set(row, "v_text", markup_key, function()
		local markup = string.format("<font color=%s>%s</font>", name_color, escape(fit(entry.name, width)))
		for _, line in ipairs(detail_lines(info, width)) do markup = markup .. "<br>" .. rich(line) end
		pcall(ui.aoml, row.text, "", markup, false)
	end)
	set(row, "v_price", shows_price(s) and (entry.price or "") or "", function(v) ui.text(row.price, v) end)
	local cash = my_cash()
	local short = s == shop and cash ~= nil and (entry.price_value or 0) > cash
	set(row, "v_price_color", short and COLOR.loss or COLOR.name, function(v) ui.text_color(row.price, v) end)
	local flagged = s == partner and is_player() and (watch.added[key_of(entry)] or 0) > now
	set(row, "v_flag", flagged and "added" or "", function(v)
		ui.fill_color(row.tint, v == "added" and ADDED.tint or "")
		ui.fill_color(row.accent, v == "added" and ADDED.accent or "")
	end)
	set_dim(row, dim and DIMMED or 1)
end

-- ------------------------------------------------------------------ lists
local SORTERS = {
	name = function(e) return string.lower(e.name) end,
	quality = function(e) return e.quality or 0 end,
	price = function(e) return e.price_value or 0 end,
	count = function(e) return e.count or 0 end,
}

local function shop_items(entries)
	local list = {}
	for _, entry in ipairs(entries) do
		if not (options.unusable == "hide" and details(entry).unusable) then list[#list + 1] = entry end
	end
	local value, descending = SORTERS[options.sort] or SORTERS.name, options.descending
	table.sort(list, function(a, b)
		local va, vb = value(a), value(b)
		if va ~= vb then
			if descending then return va > vb end
			return va < vb
		end
		if a.name ~= b.name then return a.name < b.name end
		return (a.quality or 0) < (b.quality or 0)
	end)
	local items = {}
	for index, entry in ipairs(list) do items[index] = { entry = entry } end
	return items, #entries - #list
end

local function plain_items(entries)
	local items = {}
	for index, entry in ipairs(entries) do items[index] = { entry = entry } end
	return items
end

-- Out of combat: one bound row per item, in order. In combat bindings are frozen: rows keep
-- their item and only their presentation updates.
local function fill(s, items)
	s.items = items
	local height = 0
	for _, item in ipairs(items) do height = height + row_height(s, item) end
	s.height = height
	if ui.in_combat() then return end
	while #s.rows < #items do s.rows[#s.rows + 1] = create_row(s) end
	while #s.rows > #items do
		ui.destroy(s.rows[#s.rows].root)
		s.rows[#s.rows] = nil
	end
	for index, item in ipairs(items) do
		local row = s.rows[index]
		row.item = item
		local token = item.entry and item.entry.token or 0
		if row.token ~= token then
			row.token = token
			ui.bind(row.root, token)
			for _, action in ipairs(s.actions) do ui.action(row.root, action[1], token, action[2]) end
		end
		local h = row_height(s, item)
		set(row, "v_height", h, function(v)
			ui.limits(row.root, 0, v - GAP, 4096, v - GAP)
			ui.size(row.root, -1, v - GAP)
		end)
		set(row, "v_fill", ROW_FILL[index % 2 + 1], function(v) ui.fill_color(row.bg, v) end)
	end
end

local function present(now)
	now = now or ui.time()
	for _, s in ipairs(SECTIONS) do
		local by_token = {}
		for _, item in ipairs(s.items) do
			if item.entry then by_token[item.entry.token] = item end
		end
		for _, row in ipairs(s.rows) do
			local item = row.item
			if ui.in_combat() and item and not item.ghost then item = by_token[row.token] or {} end
			if item then present_row(s, row, item, now) end
		end
		ui.visible(s.empty, #s.items == 0)
	end
end

-- ------------------------------------------------------------------ header / footer
local function pill(prefix, kind)
	local style = PILL[kind]
	ui.fill_color(find(prefix .. "_status_fill"), style.fill)
	local text = find(prefix .. "_status_text")
	ui.text(text, style.label)
	ui.text_color(text, style.text)
end

local function chips()
	for key, name in pairs({ name = "sort_name", quality = "sort_ql", price = "sort_price" }) do
		local chip = find(name)
		pcall(ui.text_color, chip, options.sort == key and COLOR.chip_active or COLOR.chip)
	end
end

local function present_header(now)
	local player = is_player()
	if player then
		pill("partner", now < watch.changed_until and "changed" or (state.partner_locked and "accepted" or "waiting"))
		pill("our", state.our_locked and "accepted" or "waiting")
	end
	ui.text(partner_cash, state.partner_cash or "")
	local cash, cost = my_cash(), amount(state.partner_cash)
	local short = not player and cash ~= nil and cost ~= nil and cost > cash -- bought more than you can pay
	ui.text_color(partner_cash, (player and now < watch.cash_until) and COLOR.match or short and COLOR.loss or COLOR.name)
end

-- ------------------------------------------------------------------ animation
-- Runs only while a change warning is showing; ends it (and drops "removed" rows) on time.
local function warning_active(now)
	if now < watch.changed_until or now < watch.cash_until then return true end
	for _, until_time in pairs(watch.added) do
		if until_time > now then return true end
	end
	return #watch.ghosts > 0
end

local render
local function animate()
	local last = 0
	ui.on_update(function(now)
		if now - last < 250 then return end
		last = now
		local expired = false
		for index = #watch.ghosts, 1, -1 do
			if watch.ghosts[index].until_time <= now then
				table.remove(watch.ghosts, index)
				expired = true
			end
		end
		for key, until_time in pairs(watch.added) do
			if until_time <= now then watch.added[key] = nil end
		end
		if expired and not ui.in_combat() then
			render()
		else
			present(now)
			present_header(now)
		end
		if not warning_active(now) then ui.stop_updates() end
	end)
end

-- ------------------------------------------------------------------ layout
local function default_height()
	return is_player() and 380 or 520
end

local function clamp(value, low, high) return math.max(low, math.min(high, value)) end

local function size_frame(s, height)
	height = math.max(0, math.floor(height))
	if s.applied == height then return end
	s.applied = height
	ui.limits(s.frame, 0, height, 4096, height)
	ui.size(s.frame, -1, height)
end

local function layout(window, width, height)
	local player, sells = is_player(), state.mode ~= 3
	local sections = player and 2 or (sells and 3 or 2)
	local fixed = ENDS + FOOTER + HEADER * sections + (sells and DROP or 0)
	local minimum = fixed + (player and 2 * ROW2 or (sells and 4 * ROW2 or 3 * ROW2))
	ui.limits(window.root, MIN_WIDTH, minimum, MAX_WIDTH, MAX_HEIGHT)
	ui.request_size(window.root, width, height)
	width, height = ui.chosen_width(window.root), ui.chosen_height(window.root)
	window:fit_title(width, true)
	window:fit_content(width, height)
	size_drop(width)
	local new_width = math.max(60, width - Window.CONTENT_SIDES - SCROLLBAR - 4 - 26 - 6 - 6 - 2)
	if new_width ~= text_width then
		text_width = new_width
		fitted = {}
		for _, s in ipairs(SECTIONS) do
			for _, row in ipairs(s.rows) do row.v_text = nil end
		end
	end
	local space = height - fixed
	if player then
		-- Their offer gets the extra half-row so it's never the cramped one.
		local theirs = math.ceil(space / 2)
		size_frame(partner, theirs)
		size_frame(ours, space - theirs)
	else
		local bought = clamp(partner.height, ROW2, SIDE_MAX_ROWS * ROW2)
		local sold = sells and clamp(ours.height, ROW2, SIDE_MAX_ROWS * ROW2) or 0
		local goods = space - bought - sold
		if goods < 2 * ROW2 then -- short window: the side lists give way first
			local short = 2 * ROW2 - goods
			local cut = math.min(short, bought - ROW2)
			bought, goods = bought - cut, goods + cut
			if sells and goods < 2 * ROW2 then
				cut = math.min(2 * ROW2 - goods, sold - ROW2)
				sold, goods = sold - cut, goods + cut
			end
		end
		size_frame(shop, goods)
		size_frame(partner, bought)
		if sells then size_frame(ours, sold) end
	end
	present()
end

frame = Window.create({
	template = "library://spiritech.modern-common/window.xml",
	title = "Trade",
	content = content,
	width = 340,
	height = 520,
	horizontal = "center",
	vertical = "center",
	layout = layout,
	menu = false,
})
ui.root(frame.root)
local title_view = ui.find(frame.root, "window_title")

relayout = function(height)
	frame:resize(ui.chosen_width(frame.root), height or ui.chosen_height(frame.root))
end

-- ------------------------------------------------------------------ menu
local build_menu
local function set_sort(key)
	if options.sort == key then
		save_option("descending", not options.descending, "bool")
	else
		save_option("sort", key)
		save_option("descending", key ~= "name", "bool") -- QL / price / count: biggest first
	end
	chips()
	build_menu()
	render()
end

local function set_unusable(value)
	save_option("unusable", value)
	build_menu()
	render()
end

build_menu = function()
	for _, anchor in ipairs({ frame.icon, menu_anchor }) do
		ui.menu.clear(anchor)
		if is_shop() then
			for _, choice in ipairs({ { "name", "Arrange by Name" }, { "quality", "Arrange by Quality" },
				{ "price", "Arrange by Price" }, { "count", "Arrange by Count" } }) do
				ui.menu.add(anchor, choice[2], options.sort == choice[1], function() set_sort(choice[1]) end)
			end
			ui.menu.add(anchor, "Sort Descending", options.descending, function()
				save_option("descending", not options.descending, "bool")
				build_menu()
				render()
			end)
			ui.menu.separator(anchor)
			for _, choice in ipairs({ { "show", "Unusable Goods: Show" },
				{ "hide", "Unusable Goods: Hide" } }) do
				ui.menu.add(anchor, choice[2], options.unusable == choice[1], function() set_unusable(choice[1]) end)
			end
		end
		if anchor == frame.icon then
			if is_shop() then ui.menu.separator(anchor) end
			ui.menu.close(anchor, frame.root)
		end
	end
end
open_menu = function() ui.menu.show(menu_anchor) end

ui.on_click(find("sort_name"), function() set_sort("name") end)
ui.on_click(find("sort_ql"), function() set_sort("quality") end)
ui.on_click(find("sort_price"), function() set_sort("price") end)

game.trade.search_field(find("shop_search"))
ui.on_text_changed(find("shop_search"), function(value) game.trade.search_edited(value) end)

-- ------------------------------------------------------------------ apply
local latest = { shop = {}, partner = {}, ours = {} }

render = function()
	local player = is_player()
	local items, hidden = shop_items(latest.shop)
	fill(shop, items)
	local count = #latest.shop
	ui.tooltip(find("shop_count"), hidden > 0 and (hidden .. " unusable goods hidden (title menu)") or "")
	ui.text(find("shop_count"), count == 0 and "" or (hidden > 0 and ((count - hidden) .. " / " .. count) or tostring(count)))
	local partner_items = plain_items(latest.partner)
	if player then
		for _, ghost in ipairs(watch.ghosts) do partner_items[#partner_items + 1] = ghost end
	end
	fill(partner, partner_items)
	ui.text(find("partner_count"), #latest.partner > 0 and tostring(#latest.partner) or "")
	fill(ours, plain_items(latest.ours))
	ui.text(find("our_count"), #latest.ours > 0 and tostring(#latest.ours) or "")
	relayout()
	present_header(ui.time())
end

local previous_mode = 0
function trade_apply(trade, goods, bought, sold)
	local now = ui.time()
	state = trade
	latest = { shop = goods or {}, partner = bought or {}, ours = sold or {} }
	details_cache = {} -- requirements are checked against your current stats
	local player, shop_mode, sells = is_player(), is_shop(), trade.mode ~= 3

	if trade.opened or not watch.bag or trade.mode ~= previous_mode then
		watch_reset(player and latest.partner or {})
		watch.cash = trade.partner_cash
		if trade.opened then
			ui.scroll_top(shop.dock)
			ui.scroll_top(partner.dock)
			ui.scroll_top(ours.dock)
		end
	elseif player and watch_update(latest.partner, trade.partner_cash, now) then
		animate()
	end

	ui.text(title_view, trade.partner_name ~= "" and ("Trade  ·  " .. trade.partner_name) or "Trade")
	ui.visible(shop.root, shop_mode)
	ui.visible(ours.root, sells)
	ui.text(partner.label, player and "THEIR OFFER" or "BOUGHT")
	ui.text(ours.label, player and "YOUR OFFER" or "SOLD")
	ui.text(partner.empty, player and "Nothing offered yet" or "Click goods to buy")
	ui.text(ours.empty, player and "Drag items here to offer them" or "Drag items here to sell them")
	ui.visible(find("partner_status"), player)
	ui.visible(find("our_status"), player)
	ui.visible(find("our_cash_frame"), player)
	ui.tooltip(partner_cash, player and "Credits they offer" or "Cost of what you bought")
	ui.visible(find("search_box"), shop_mode)
	ui.visible(find("balance_box"), shop_mode and sells)
	ui.text(our_balance, trade.our_balance or "")
	-- Balance: green when you gain, plain when you pay what you can afford, red when you can't.
	local cash, balance = my_cash(), amount(trade.our_balance)
	local unaffordable = trade.balance_loss and cash ~= nil and balance ~= nil and math.abs(balance) > cash
	ui.text_color(our_balance, not trade.balance_loss and COLOR.gain
		or (unaffordable or cash == nil) and COLOR.loss or COLOR.name)
	ui.enabled(our_cash, trade.can_edit)
	ui.enabled(accept, trade.can_accept)
	ui.opacity(accept, trade.can_accept and 1 or 0.45)
	if not ui.in_combat() then
		ui.bind(accept, trade.context)
		ui.action(accept, "game.trade.accept", trade.context, "left")
		ui.bind(decline, trade.context)
		ui.action(decline, "game.trade.decline", trade.context, "left")
	end

	if trade.mode ~= previous_mode then
		previous_mode = trade.mode
		build_menu()
		chips()
		render()
		relayout(math.max(ui.chosen_height(frame.root), default_height()))
	else
		render()
	end
end

chips()
build_menu()
Security.render("trade_apply")
