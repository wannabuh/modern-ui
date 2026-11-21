-- Modern Inventory: the built-in item container package (inventory, bags, bank, loot)
-- restyled: shared flat frame, crisp 38px slots (32px icons at native size) 2px apart,
-- flat search box and slot count, flat bank credits panel, neutral list colours.
-- All item handling (drag, split, use, equip, search, bank) is unchanged and native.
pcall(ui.require, "spiritech.modern-common/screenfit") -- keep window positions through fullscreen changes
local Window = ui.require("core.window")
local Theme = ui.require("spiritech.modern-common/theme")
local CELL, SPACING = 38, 2 -- slot size and gap; must match slot.xml and grid_spacing in window.xml
local Security = ui.require("core.security")
local Grid = ui.require("core.icon_grid")
local Table = ui.require("core.table")
local content = ui.load("window.xml")
local grid = ui.find(content, "inventory_grid")
local grid_scroll = ui.find(content, "inventory_content")
local list_host = ui.find(content, "inventory_list")
local search_query = ui.find(content, "search_query")
local FOOTER_HEIGHT = 26
local footer = ui.find(content, "footer")
local footer_spacer = ui.find(content, "footer_spacer")
local slot_count = ui.find(content, "slot_count")
local slot_count_frame = ui.find(content, "slot_count_frame")
local counts_slots = false
local CREDITS_CHOICE_HEIGHT = 31
local CREDITS_ENTRY_HEIGHT = 57
local ACCOUNT_BANK_MINIMUM_COLUMNS = 6
local ACCOUNT_BANK_MINIMUM_ROWS = 4
local credits_section = ui.find(content, "credits_section")
local credits_balance = ui.find(content, "credits_balance")
local credits_choice = ui.find(content, "credits_choice")
local credits_entry = ui.find(content, "credits_entry")
local credits_entry_label = ui.find(content, "credits_entry_label")
local credits_amount = ui.find(content, "credits_amount")
local credits_transfer = ui.find(content, "credits_transfer")
local credits_shown = false
local credits_height = 0
local credits_reference = nil
local MATCH_FRAME = "GFX_GUI_SELECTED_ICON"
local searchable = false
local search_reserved = false
local entries, occupied = {}, {}
local selected, splitting, split_count = -1, -1, ""
local mode = ui.preference.read("listview_config.listview_mode") == "true" and "list" or "grid"
local frame, reconcile
local capacity, request_close = 30, false
local function is_selected(entry)
	return entry.occupied and entry.placement == selected
end
local function faded(entry)
	return entry.locked or entry.over_equipped or entry.search == "other"
end
local function match_frame(entry)
	return entry.search == "match" and MATCH_FRAME or ""
end
local function tint(entry)
	return entry.over_equipped and "#FF0000" or ""
end
local function count(entry)
	if entry.placement == splitting then
		return split_count
	end
	return tostring(entry.count)
end
local cells = Grid.cells({
	collection = "inventory_grid",
	host = grid,
	template = "slot.xml",
	binding = function(entry)
		return entry.token
	end,
	content = function(entry)
		return entry.occupied
	end,
	icon = function(entry)
		return entry.icon
	end,
	selected = is_selected,
	faded = faded,
	tint = tint,
	overlay = match_frame,
	corner = function(entry)
		return entry.count > 1 and tostring(entry.count) or ""
	end,
	center = function(entry)
		if entry.placement == splitting then
			return split_count
		end
		return entry.remaining
	end,
})
-- List mode: the same two-line rows as the NCU list and list panels (icon, then the name
-- over a smaller grey "×count · QL" line). Order comes from the organizer (header hidden).
local organizer -- created below; the list text is composed by it
local main_list = { name_width = 200 } -- name column width for fitting long names
local LIST_ICON = 28 -- 26px icon + 2px nudge, as in organizer.lua
local list = Table.create({
	collection = "inventory_list",
	fit_columns = true,
	host = list_host,
	row_height = 32,
	preference = "modern_main_list",
	binding = function(entry)
		return entry.token
	end,
	selected = is_selected,
	columns = {
		{
			id = "icon",
			title = "",
			width = LIST_ICON,
			minimum = 26,
			kind = "icon",
			resizable = false,
			icon = function(entry)
				return entry.icon
			end,
			faded = faded,
			tint = tint,
		},
		{
			id = "item",
			title = "Item",
			width = 200,
			minimum = 60,
			text = function(entry)
				if entry.placement == splitting then
					return entry.name .. "\nSplit: " .. split_count
				end
				return organizer and organizer:list_plain(main_list, entry) or entry.name
			end,
		},
	},
})
ui.visible(ui.find(list.root, "table_header_scroll"), false)
list.sort = ""
-- Organizer (main inventory only): tabs, filter, sort, New, Organize mode. See organizer.lua.
local Organizer = ui.require("inventory.organizer")
local filtered_scroll = ui.find(content, "filtered_content")
local filtered_grid = ui.find(content, "filtered_grid")
-- Same cell presentation as the main grid, without the native collection (display-only view).
local filtered_cells = Grid.cells(setmetatable({ collection = false, host = filtered_grid }, { __index = cells.options }))
organizer = Organizer.create(content, {
	reconcile = function() if reconcile then reconcile() end end,
	resize = function()
		if frame then frame:resize(ui.chosen_width(frame.root), ui.chosen_height(frame.root)) end
	end,
})

local function style_list()
	for _, row in ipairs(list.rows) do organizer:style_list_row(main_list, row) end
	if list.prototype then organizer:style_list_row(main_list, list.prototype) end
end
organizer:set_cells(function()
	if mode == "list" then return list.rows end
	return organizer:is_plain() and cells.cells or filtered_cells.cells
end)

reconcile = function()
	if organizer.active then organizer:refresh_panels(entries) end
	local plain = organizer:is_plain()
	if mode == "list" then
		ui.visible(filtered_scroll, false)
		local shown = plain and occupied or organizer:select_entries(entries)
		-- Name room from the list's real on-screen width (the layout width can lag behind a
		-- restored or resized window, which cut names short in bags).
		local actual = math.max(ui.width(list_host), ui.chosen_width(frame.root) - 19)
		if actual > 0 then
			main_list.name_width = math.max(60, actual - 12 - 2 * list.style.gap - LIST_ICON)
			list.preferred_widths[2] = main_list.name_width
		end
		-- Three-line rows (requirements on their own line) when any item's details are crowded.
		main_list.three = organizer:needs_three(shown, main_list.name_width - 6)
		organizer:set_row_height(list, main_list.three and 46 or 32)
		list:show(shown, shown) -- keep this order (the header, and its sorting, is hidden)
		style_list()
		organizer:show_empty_note(plain and 1 or #shown)
	else
		ui.visible(grid_scroll, plain)
		ui.visible(filtered_scroll, not plain)
		cells:show(entries)
		if plain then
			organizer:show_empty_note(1)
		else
			local shown = organizer:select_entries(entries)
			filtered_cells:show(shown)
			organizer:show_empty_note(#shown)
		end
	end
end
local sizing = Grid.create(CELL, SPACING, capacity)
local function footer_height(search)
	return (search or counts_slots) and FOOTER_HEIGHT or 0
end
local function show_footer()
	local shown = searchable or counts_slots
	ui.visible(footer, shown)
	ui.visible(search_query, searchable)
	ui.visible(footer_spacer, not searchable)
	ui.visible(slot_count_frame, counts_slots)
end
local function layout(window, width, height)
	local title_visible = true
	local reserved_height = footer_height(searchable) + credits_height
		+ organizer:height()
	if mode == "list" then
		ui.limits(window.root, 320, 120 + reserved_height, 900, 1200)
		width, height = math.max(320, math.min(900, width)), math.max(120 + reserved_height, math.min(1200, height))
	else
		local fewest_columns, fewest_rows, fewest_scroll = 1, 1, false
		if credits_shown then
			fewest_columns, fewest_rows = ACCOUNT_BANK_MINIMUM_COLUMNS, ACCOUNT_BANK_MINIMUM_ROWS
			fewest_scroll = capacity > fewest_columns * fewest_rows
		end
		local min_width, min_height = sizing:size(fewest_columns, fewest_rows, fewest_scroll)
		local max_width = sizing:size(capacity, capacity, true)
		local _, max_height = sizing:size(1, capacity, true)
		ui.limits(window.root, min_width, min_height + reserved_height, max_width, max_height + reserved_height)
		width, height = math.max(width, min_width), math.max(height, min_height + reserved_height)
		local columns
		width, height, columns = sizing:resolve(width, height - reserved_height, capacity)
		height = height + reserved_height
		title_visible = columns >= 3
		ui.size(grid, columns * (CELL + SPACING) - SPACING, -1)
		ui.size(filtered_grid, columns * (CELL + SPACING) - SPACING, -1)
	end
	-- List: the item column takes what the icon column and gaps leave (12 = scrollbar).
	local list_inner = width - 19
	list.preferred_widths[2] = math.max(60, list_inner - 12 - 2 * list.style.gap - LIST_ICON)
	main_list.name_width = list.preferred_widths[2]
	list:set_width(list_inner)
	window:fit_title(width, title_visible)
	ui.request_size(window.root, width, height)
	window:fit_content(width, height)
end
local function set_mode(value)
	if ui.in_combat() then
		return
	end
	if mode == value then
		return
	end
	cells:clear()
	list:clear()
	mode = value
	selected, splitting, split_count = -1, -1, ""
	ui.visible(grid_scroll, mode == "grid")
	ui.visible(list_host, mode == "list")
	ui.menu.checked(frame.icon, 1, mode == "list")
	frame:resize(ui.chosen_width(frame.root), ui.chosen_height(frame.root))
	reconcile()
	ui.preference.write("listview_config.listview_mode", tostring(mode == "list"), "bool")
	ui.publish("view_mode", mode)
end
-- The package root is a full-screen container holding the window and pop-out panels
-- (panels drawn outside a window's own area are cut off, so they can't hang off the window).
local container = ui.load("root.xml")
frame = Window.create({
	template = Theme.WINDOW_TEMPLATE,
	title = "Inventory",
	-- Closing the window closes the whole container (window + panels) the way the game expects.
	close_action = function() ui.close(container) end,
	-- The container's open state is the game's; the window itself is always shown inside it.
	remember_open = false,
	content = content,
	width = 198,
	height = 210,
	x = 10,
	y = 174,
	layout = layout,
	on_visibility = function(visible)
		ui.publish("visibility", tostring(visible))
	end,
	menu = {
		{
			label = "List Mode",
			checked = mode == "list",
			invoke = function()
				set_mode(mode == "list" and "grid" or "list")
			end,
		},
	},
})
ui.add(container, frame.root)
ui.root(container)
ui.require("inventory.snap").add(frame.root) -- window and panels snap to each other
ui.visible(frame.root, true)
-- Title menu: List Mode, then Close Window for the whole container (window + panels).
-- Title menu: List Mode; for the main inventory also Show tabs / sort / organize; then
-- Close Window for the whole container (window + panels). List Mode stays item 1.
-- Bag names (as the stock Inventory): Rename / Reset To Default publish "name_request"; the
-- game prompts for the name, the server stores it, and the new title arrives in inventory_apply.
local renamable, name_requests = false, 0
local renamable_title -- this bag window's current title
for _, key in ipairs({ "diag_names", "diag_icons_1", "diag_icons_2", "diag_session" }) do
	if ui.storage.read(key) ~= "" then pcall(ui.storage.write, key, "") end -- old diagnostics
end
local function request_name(kind)
	name_requests = name_requests + 1
	ui.publish("name_request", kind .. ":" .. name_requests)
end

local function build_title_menu()
	ui.menu.clear(frame.icon)
	ui.menu.add(frame.icon, "List Mode", mode == "list", function()
		set_mode(mode == "list" and "grid" or "list")
	end)
	if renamable then
		ui.menu.separator(frame.icon)
		ui.menu.add(frame.icon, "Rename", false, function() request_name("rename") end)
		ui.menu.add(frame.icon, "Reset To Default", false, function() request_name("reset") end)
	end
	if not organizer.active then
		-- Bags, bank and loot: display order (shared by all of them, per character).
		ui.menu.separator(frame.icon)
		for _, choice in ipairs({ { "Slot", "Sort by slot" }, { "Name", "Sort by name" }, { "Quality", "Sort by QL" } }) do
			local sort, label = choice[1], choice[2]
			ui.menu.add(frame.icon, label, organizer.bag_sort == sort, function()
				organizer:set_bag_sort(sort)
				build_title_menu() -- move the check mark
			end)
		end
	end
	if organizer.active then
		ui.menu.separator(frame.icon)
		for _, part in ipairs({ { "tabs", "Show tabs" }, { "sort", "Show sort" }, { "organize", "Show organize" } }) do
			local key, label = part[1], part[2]
			local index
			index = ui.menu.add(frame.icon, label, organizer.show[key], function()
				organizer:set_shown(key, not organizer.show[key])
				ui.menu.checked(frame.icon, index, organizer.show[key])
			end)
		end
	end
	ui.menu.separator(frame.icon)
	ui.menu.close(frame.icon, container)
end
build_title_menu()
-- Pop-out category panels live in the container next to the window (main inventory only).
organizer:attach_panels(container, frame.root, function(grid_view)
	return Grid.cells(setmetatable({ collection = false, host = grid_view }, { __index = cells.options }))
end)
ui.visible(grid_scroll, mode == "grid")
ui.visible(list_host, mode == "list")
ui.publish("view_mode", mode)

-- Window position and size. The game only saves these for a package's root view, and the
-- root is now the full-screen container, so they're kept in this package's storage instead:
--   win/<character>/<window title> = "x,y,width,height"
local window_key_title, window_character, window_restored = nil, nil, false
local loot_window = false -- corpses / chests: one shared spot ("win/<character>/~loot") for all of them
local last_saved, last_save_time = nil, 0

local function window_key()
	if not window_character then return nil end
	if loot_window then return "win/" .. window_character .. "/~loot" end
	if not window_key_title then return nil end
	return "win/" .. window_character .. "/" .. window_key_title:gsub("[^%w _%-]", "_")
end

local function save_window(force)
	local key = window_key()
	if not key or not window_restored then return end
	local value = string.format("%.0f,%.0f,%.0f,%.0f", ui.local_x(frame.root), ui.local_y(frame.root),
		ui.chosen_width(frame.root), ui.chosen_height(frame.root))
	if value == last_saved then return end
	local now = ui.time()
	if not force and now - last_save_time < 400 then return end -- at most a few writes a second
	last_saved, last_save_time = value, now
	pcall(ui.storage.write, key, value) -- a full store must not break the window
end

-- Open/closed state, for the main inventory only (bags and bank are opened by the server).
local function open_key()
	local key = window_key()
	return key and window_key_title == "Inventory" and not request_close and (key .. "/open") or nil
end

local function restore_window()
	local key = window_key()
	if not key or window_restored then return end
	window_restored = true
	local open = open_key()
	if open and ui.storage.read(open) == "true" then
		ui.visible(container, true)
	end
	local x, y, width, height = ui.storage.read(key):match("^(-?%d+),(-?%d+),(%d+),(%d+)$")
	if not x then return end
	ui.align(frame.root, "start", "start")
	ui.place(frame.root, tonumber(x), tonumber(y))
	frame:resize(tonumber(width), tonumber(height))
	last_saved = nil
end

game.character.subscribe("self", "", function(_, me)
	if me and not window_character then
		local id = me.key or me.name
		if id and id ~= "" then
			window_character = id:gsub("[^%w_%-]", "_")
			-- Name -> id lookup for tools/copy_ui.py (storage keys only carry the id).
			if me.name and me.name ~= "" then pcall(ui.storage.write, "who/" .. window_character, me.name) end
			restore_window()
			build_title_menu() -- the saved bag sort is known now (the organizer loads it first)
		end
	end
end)

-- Save while the window is dragged (throttled), and whenever the inventory closes.
local Move = ui.require("core.move")
local base_drag = Move.drag
Move.drag = function(view, x, y, bounded)
	local rx, ry = base_drag(view, x, y, bounded)
	if view == frame.root then save_window(false) end
	return rx, ry
end
ui.on_visibility(container, function(visible)
	if not visible then save_window(true) end
	-- Only record your own open/close, not the game hiding everything on logout or zoning
	-- (the same check the game's own window placement uses).
	local open = window_restored and ui.is_available(container) and open_key()
	if open then pcall(ui.storage.write, open, visible and "true" or "false") end
end)
local base_capture = frame.placement.capture
frame.placement.capture = function(self, ...)
	base_capture(self, ...)
	save_window(true)
end

function inventory_configure(configuration)
	capacity, request_close = math.max(1, configuration.capacity), configuration.request_close
	frame.placement.options.remember_open = false -- the container's open state is the game's
	sizing = Grid.create(CELL, SPACING, capacity)
	ui.grid_columns(grid, capacity)
	ui.grid_columns(filtered_grid, capacity)
	-- The organizer is for the main inventory only (not bags, bank or loot).
	organizer:activate(configuration.title == "Inventory" and configuration.slot_count and not configuration.request_close)
	-- Bags, bank and loot open in list mode unless List Mode was turned off for that window.
	if not organizer.active and mode ~= "list" and ui.preference.read("listview_config.listview_mode") == "" then
		set_mode("list")
	end
	renamable = configuration.renamable == true
	renamable_title = renamable and configuration.title or nil
	if renamable then
		organizer:note_bag(configuration.title) -- remembered as a bag for the Bags tab
	end
	build_title_menu()
	ui.text(ui.find(frame.root, "window_title"), configuration.title)
	ui.place(frame.root, configuration.x, configuration.y)
	ui.align(frame.root, configuration.horizontal, configuration.vertical)
	search_reserved = configuration.searchable
	counts_slots = configuration.slot_count
	show_footer()
	local width, height = 198, 210
	if configuration.columns > 0 and configuration.rows > 0 then
		width, height = sizing:size(configuration.columns, configuration.rows, true)
	end
	frame:resize(width, height + footer_height(search_reserved) + organizer:height())
	-- Inventory / bag / bank windows (they show a slot count) are remembered per title; loot
	-- windows (titles are corpse and chest names) all share one remembered spot and size.
	window_key_title = configuration.slot_count and configuration.title or nil
	loot_window = not configuration.slot_count
	if loot_window then window_restored = false end -- re-apply the saved spot each time a loot window opens
	restore_window()
end

function inventory_apply(snapshot, container, title, first_free)
	list:drop_target(first_free)
	if request_close then
		ui.bind(frame.close_button, container)
		ui.action(frame.close_button, "game.inventory.request_close", container, "left")
	end
	ui.text(ui.find(frame.root, "window_title"), title)
	if renamable then
		if title and title ~= "" and title ~= renamable_title then
			organizer:note_bag(title, renamable_title) -- renamed: the Bags tab follows the new name
			renamable_title = title
		end
	end
	-- A renamed bag: its saved position follows the new title (copied, so the old key still
	-- works if the game opens it under its old title next time).
	if not loot_window and window_key_title and title and title ~= "" and title ~= window_key_title and window_key_title ~= "Inventory" then
		local old = window_key()
		window_key_title = title
		local new = window_key()
		if old and new and ui.storage.read(new) == "" and ui.storage.read(old) ~= "" then
			pcall(ui.storage.write, new, ui.storage.read(old))
		end
		last_saved = nil
	end
	entries, occupied = snapshot, {}
	for _, entry in ipairs(entries) do
		if entry.occupied then
			occupied[#occupied + 1] = entry
		end
	end
	ui.text(slot_count, #occupied .. " / " .. capacity .. " slots")
	save_window(true) -- catches the final spot of a drag / resize (only writes when it changed)
	if organizer.active then organizer:track(entries) end
	frame:resize(ui.chosen_width(frame.root), ui.chosen_height(frame.root))
	reconcile()
end

game.inventory.search_field(search_query)
ui.on_text_changed(search_query, function(value)
	game.inventory.search_edited(value)
end)

function inventory_search(available)
	local shown = available and search_reserved
	if searchable == shown then
		return
	end
	searchable = shown
	show_footer()
	if not searchable then
		ui.text(search_query, "")
	end
	frame:resize(ui.chosen_width(frame.root), ui.chosen_height(frame.root))
end

local function size_credits(height)
	local grown = height - credits_height
	if grown == 0 then
		return
	end
	credits_height = height
	frame:resize(ui.chosen_width(frame.root), ui.chosen_height(frame.root) + grown)
end

local function choose_credits(mode)
	game.inventory.credits_mode(mode)
	local choosing = mode == ""
	ui.visible(credits_choice, choosing)
	ui.visible(credits_entry, not choosing)
	if not choosing then
		local label = mode == "deposit" and "Deposit" or "Withdraw"
		ui.text(credits_entry_label, label)
		ui.text(credits_transfer, label)
	end
	if credits_shown then
		size_credits(choosing and CREDITS_CHOICE_HEIGHT or CREDITS_ENTRY_HEIGHT)
	end
end
game.inventory.credits_field(credits_amount)
ui.on_click(ui.find(content, "credits_deposit"), function()
	choose_credits("deposit")
end)
ui.on_click(ui.find(content, "credits_withdraw"), function()
	choose_credits("withdraw")
end)
ui.on_click(ui.find(content, "credits_cancel"), function()
	ui.text(credits_amount, "")
	choose_credits("")
end)

local function bind_credits_transfer()
	ui.bind(credits_transfer, credits_reference)
	ui.action(credits_transfer, "game.inventory.credits_transfer", credits_reference, "left")
end

function inventory_credits(available, balance, transfer)
	ui.text(credits_balance, balance)
	credits_reference = transfer
	bind_credits_transfer()
	if credits_shown == available then
		return
	end
	credits_shown = available
	ui.visible(credits_section, available)
	choose_credits("")
	if not available then
		size_credits(0)
	end
end

function inventory_credits_sent()
	choose_credits("")
end

function inventory_selection(value, split, amount)
	selected, splitting, split_count = value, split, amount
	reconcile()
end

Security.render("inventory_apply")
Security.on_unlock(function()
	if credits_reference then
		bind_credits_transfer()
	end
	ui.grid_columns(grid, capacity)
	ui.visible(grid_scroll, mode == "grid")
	ui.visible(list_host, mode == "list")
	ui.publish("view_mode", mode)
	frame:resize(ui.chosen_width(frame.root), ui.chosen_height(frame.root))
	reconcile()
end)
