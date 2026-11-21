-- Inventory organizer (main inventory only): category tabs, display sorting, a "New" list of recently gained items and an Organize mode for tagging items.
--
-- Everything here is DISPLAY ONLY: items never move. Filtered views show the same slots
-- (same native bindings), so drag / use / equip / inspect keep working. The game only
-- lets its own main grid pick up brand-new items during combat, so a filtered view may show
-- a freshly looted item before it becomes clickable (it does once combat ends).
--
-- Categories:
--   All        every slot (the game's own grid when no sort is active)
--   New        items whose stack count grew since you last pressed "Mark seen"
--   Favorites  items you tagged (by name, so every stack of that item)
--   Bags       containers: every bag you have opened (remembered by name, renames followed),
--              plus names that look like one (Backpack, Bag, Pouch, ...) for bags never opened
--   Implants   implants and symbiants (by name, checked against the item database: 46,721 of
--              46,728 match, plus any item with known implant modifiers)
--   Nanos      nano crystals, instruction discs, compiled algorithms, ... ("<carrier> (<nano>)")
--   Implants / Nanos tabs only show while you carry such items.
--   Unsorted   items not in any category yet (not tagged, not a bag): what's left to organize
--   + your own categories (tagged), added with the + button; right-click a tab to remove it
--
-- Tags and custom categories are saved per character in this package's storage:
--   inv/<character>/categories        custom category names, one per line
--   inv/<character>/tag/<category>    item names, one per line
ui.define("inventory.organizer", function()
	local Organizer = {}
	Organizer.__index = Organizer

	local BUILT_IN = { "All", "New", "Unsorted", "Favorites", "Bags", "Implants", "Nanos" }
	-- Automatic tabs that only show while you carry something for them (keeps the row short).
	local AUTO_HIDE = { Implants = true, Nanos = true }
	local kind_of -- item name -> "implant" | "nano" | false (defined with the implant/nano rules below)
	local TAGGABLE_BUILT_IN = { "Favorites" }
	local BAG_WORDS = { "backpack", "bag", "pouch", "sack", "satchel", "container" } -- name words that mean "container"
	local SORTS = { "Slot", "Name", "Quality", "Stack", "New" }
	local BAG_SORTS = { Slot = true, Name = true, Quality = true } -- bag / bank / loot windows (title menu)
	local SELECTED, IDLE = "#E8ECF1", "#A3ADBA"
	local ORGANIZE_ON = "#4FB3BF"
	local ROW_HEIGHT = 26 -- the organizer row incl. divider; keep in sync with window.xml

	local function split_lines(text)
		local list = {}
		for line in (text or ""):gmatch("[^\n]+") do list[#list + 1] = line end
		return list
	end

	-- Package storage allows 4096 bytes per value and raises a Lua error past that (which shuts
	-- the whole inventory down until relog). Line lists that grow with the inventory (the "seen"
	-- baseline above all) are spread over <key>, <key>#2, <key>#3 ... at line boundaries, and a
	-- failed write is dropped instead of breaking the window.
	local PART_BYTES = 4000

	local function fetch(key)
		local first_ok, first = pcall(ui.storage.read, key)
		if not first_ok or first == "" then return "" end
		local parts, index = { first }, 2
		while true do
			local ok, part = pcall(ui.storage.read, key .. "#" .. index)
			if not ok or part == "" then break end
			parts[#parts + 1], index = part, index + 1
		end
		return table.concat(parts, "\n")
	end

	local function store(key, text)
		local parts, current, size = {}, {}, 0
		for raw in (text or ""):gmatch("[^\n]+") do
			local line = #raw > PART_BYTES and raw:sub(1, PART_BYTES) or raw
			if size > 0 and size + 1 + #line > PART_BYTES then
				parts[#parts + 1], current, size = table.concat(current, "\n"), {}, 0
			end
			current[#current + 1] = line
			size = size + (size > 0 and 1 or 0) + #line
		end
		if size > 0 then parts[#parts + 1] = table.concat(current, "\n") end
		local ok = pcall(ui.storage.write, key, parts[1] or "")
		if not ok then return end
		for index = 2, #parts do
			if not pcall(ui.storage.write, key .. "#" .. index, parts[index]) then return end
		end
		local index = #parts + 1
		if index < 2 then index = 2 end
		while true do
			local read_ok, left = pcall(ui.storage.read, key .. "#" .. index)
			if not read_ok or left == "" then break end
			pcall(ui.storage.write, key .. "#" .. index, "")
			index = index + 1
		end
	end

	local function key_of(entry)
		return entry.name .. "|" .. tostring(entry.quality)
	end

	function Organizer.create(content, options)
		local self = setmetatable({}, Organizer)
		self.options = options -- { reconcile = fn, resize = fn }
		self.root = ui.find(content, "organizer")
		self.tab_row = ui.find(content, "tab_row")
		self.measure = ui.find(content, "organizer_measure")
		self.sort_button = ui.find(content, "sort_button")
		self.seen_button = ui.find(content, "seen_button")
		self.organize_button = ui.find(content, "organize_button")
		self.tools_row = ui.find(content, "organizer_row")
		self.tab_add = ui.find(content, "tab_add")
		self.add_row = ui.find(content, "add_row")
		self.add_name = ui.find(content, "add_name")
		self.overlay = ui.find(content, "organize_overlay")
		self.empty_note = ui.find(content, "empty_note")
		self.active = false
		self.category = "All"
		self.filter = ""
		self.sort = "Slot"
		self.bag_sort = "Slot" -- display order in bag / bank / loot windows (organizer inactive)
		self.organizing = false
		self.custom = {}
		self.tags = {} -- category -> { [item name] = true }
		self.tabs = {}
		self.new = {} -- item key -> true
		self.baseline = nil -- item key -> count when last "seen"
		self.character = nil
		self.pending_name = ""
		self.panels = {} -- category -> panel
		self.panel_order = {}

		ui.on_click(self.sort_button, function()
			local index = 1
			for i, name in ipairs(SORTS) do if name == self.sort then index = i end end
			self.sort = SORTS[index % #SORTS + 1]
			ui.text(self.sort_button, "Sort: " .. self.sort)
			ui.preference.write("modern_sort", self.sort, "text")
			self.options.reconcile()
		end)
		ui.on_click(self.seen_button, function()
			self:mark_seen()
		end)
		ui.on_click(self.organize_button, function()
			self:set_organizing(not self.organizing)
		end)
		ui.on_click(ui.find(content, "tab_add"), function()
			ui.text(self.add_name, "")
			self.pending_name = ""
			ui.visible(self.tools_row, false)
			ui.visible(self.add_row, true)
		end)
		ui.on_text_changed(self.add_name, function(value) self.pending_name = value or "" end)
		ui.on_click(ui.find(content, "add_cancel"), function() self:close_add() end)
		ui.on_click(ui.find(content, "add_confirm"), function()
			self:add_category(self.pending_name)
			self:close_add()
		end)
		ui.on_pointer(self.overlay, function(phase, x, y)
			if phase == "start" then
				ui.capture_pointer(self.overlay)
			elseif phase == "end" then
				self:organize_click(x, y)
			end
		end)

		-- What the title menu shows/hides: tabs, Sort, Organize (saved per window preferences).
		self.show = {}
		for _, part in ipairs({ "tabs", "sort", "organize" }) do
			self.show[part] = ui.preference.read("modern_show_" .. part) ~= "false"
		end

		local saved_sort = ui.preference.read("modern_sort")
		for _, name in ipairs(SORTS) do if name == saved_sort then self.sort = name end end
		ui.text(self.sort_button, "Sort: " .. self.sort)

		game.character.subscribe("self", "", function(_, me)
			if me and not self.character then
				local id = me.key or me.name
				if id and id ~= "" then
					self.character = id:gsub("[^%w_%-]", "_")
					self:load()
					self:flush_bags()
				end
			end
		end)
		return self
	end

	-- ---------------------------------------------------------------- storage
	function Organizer:storage_key(suffix)
		return "inv/" .. self.character .. "/" .. suffix
	end

	function Organizer:load()
		local bag_sort = fetch(self:storage_key("bag_sort"))
		if BAG_SORTS[bag_sort] then self.bag_sort = bag_sort end
		self.custom = split_lines(fetch(self:storage_key("categories")))
		self.tags = {}
		for _, category in ipairs(self:taggable()) do
			local set = {}
			for _, name in ipairs(split_lines(fetch(self:storage_key("tag/" .. category)))) do
				set[name] = true
			end
			self.tags[category] = set
		end
		local saved = ui.preference.read("modern_category")
		if saved ~= "" and self:category_exists(saved) and (self.show == nil or self.show.tabs) then
			self.category = saved
		end
		self:build_tabs()
		self:restore_panels()
		self.options.reconcile()
	end

	function Organizer:save_tags(category)
		if not self.character then return end
		local names = {}
		for name in pairs(self.tags[category] or {}) do names[#names + 1] = name end
		table.sort(names)
		store(self:storage_key("tag/" .. category), table.concat(names, "\n"))
	end

	function Organizer:save_categories()
		if not self.character then return end
		store(self:storage_key("categories"), table.concat(self.custom, "\n"))
	end

	function Organizer:taggable()
		local list = {}
		for _, name in ipairs(TAGGABLE_BUILT_IN) do list[#list + 1] = name end
		for _, name in ipairs(self.custom) do list[#list + 1] = name end
		return list
	end

	-- ---------------------------------------------------------------- categories
	function Organizer:add_category(name)
		name = (name or ""):gsub("^%s+", ""):gsub("%s+$", ""):gsub("[\n/]", " ")
		if name == "" then return end
		for _, existing in ipairs(BUILT_IN) do if existing:lower() == name:lower() then return end end
		for _, existing in ipairs(self.custom) do if existing:lower() == name:lower() then return end end
		self.custom[#self.custom + 1] = name
		self.tags[name] = self.tags[name] or {}
		self:save_categories()
		self:build_tabs()
		self:select(name)
	end

	function Organizer:remove_category(name)
		for index, existing in ipairs(self.custom) do
			if existing == name then
				table.remove(self.custom, index)
				self.tags[name] = nil
				self:close_panel(name)
				if self.character then store(self:storage_key("tag/" .. name), "") end
				self:save_categories()
				if self.category == name then self.category = "All" end
				self:build_tabs()
				self.options.reconcile()
				return
			end
		end
	end

	function Organizer:close_add()
		ui.visible(self.add_row, false)
		ui.visible(self.tools_row, true)
	end

	function Organizer:tab_label(name)
		if name == "New" then
			local count = 0
			for _ in pairs(self.new) do count = count + 1 end
			return count > 0 and ("New " .. count) or "New"
		end
		return name
	end

	function Organizer:build_tabs()
		for _, tab in ipairs(self.tabs) do ui.destroy(tab.root) end
		self.tabs = {}
		local names = {}
		for _, name in ipairs(BUILT_IN) do names[#names + 1] = name end
		for _, name in ipairs(self.custom) do names[#names + 1] = name end
		for _, name in ipairs(names) do
			local loaded = ui.load("tab.xml")
			ui.add(self.tab_row, loaded)
			local root = ui.find(loaded, "tab") or loaded
			local tab = { name = name, root = root, label = ui.find(root, "tab_label"), line = ui.find(root, "tab_line") }
			ui.on_click(tab.label, function() self:select(name) end)
			local custom = true
			for _, built in ipairs(BUILT_IN) do if built == name then custom = false end end
			if name ~= "All" then
				ui.menu.style(tab.label, "context")
				ui.on_pointer_release(tab.label, "right", function()
					ui.menu.clear(tab.label)
					if self.panels[name] then
						ui.menu.add(tab.label, "Close panel", false, function() self:toggle_panel(name) end)
					else
						ui.menu.add(tab.label, "Pop out as grid", false, function() self:toggle_panel(name, "grid") end)
						ui.menu.add(tab.label, "Pop out as grid with names", false, function() self:toggle_panel(name, "named") end)
						ui.menu.add(tab.label, "Pop out as list", false, function() self:toggle_panel(name, "list") end)
					end
					if custom then
						ui.menu.separator(tab.label)
						ui.menu.add(tab.label, "Remove category \"" .. name .. "\"", false, function()
							self:remove_category(name)
						end)
					end
					ui.menu.show(tab.label)
				end)
				ui.tooltip(tab.label, custom and "Right-click: pop out / remove" or "Right-click: pop out")
			end
			self.tabs[#self.tabs + 1] = tab
		end
		self:paint_tabs()
	end

	function Organizer:paint_tabs()
		for _, tab in ipairs(self.tabs) do
			local text = self:tab_label(tab.name)
			ui.text(tab.label, text)
			ui.text(self.measure, text)
			local ok, width = pcall(ui.text_width, self.measure)
			width = (ok and width and width > 0) and math.ceil(width) or (#text * 7)
			ui.limits(tab.root, width, 22, width, 22)
			ui.size(tab.root, width, 22)
			local selected = tab.name == self.category
			if AUTO_HIDE[tab.name] then
				ui.visible(tab.root, selected or (self.auto_counts and (self.auto_counts[tab.name] or 0) > 0) or false)
			end
			ui.text_color(tab.label, selected and SELECTED or (tab.name == "New" and next(self.new) and "#F0C060" or IDLE))
			ui.visible(tab.line, selected)
		end
		ui.visible(self.seen_button, self.category == "New" and (not self.show or self.show.tabs))
	end

	function Organizer:select(name)
		self.category = name
		ui.preference.write("modern_category", name, "text") -- restored on login
		self:paint_tabs()
		self.options.reconcile()
	end

	-- ---------------------------------------------------------------- New tracking
	-- An item is "new" when its total count is higher than in the "seen" baseline. The baseline
	-- is saved per character (inv/<character>/seen), so relogging keeps it. While the game
	-- (re)fills the inventory after a login or zone change, snapshots can be partial; changes
	-- are ignored until it has been settled for SETTLE_MS, and whenever the inventory suddenly
	-- looks much emptier (a reload, not you dropping things).
	local SETTLE_MS = 6000

	local function copy(map)
		local result = {}
		for key, value in pairs(map or {}) do result[key] = value end
		return result
	end

	function Organizer:save_baseline()
		if not self.character or not self.baseline then return end
		local lines = {}
		for key, count in pairs(self.baseline) do lines[#lines + 1] = key .. "\t" .. count end
		table.sort(lines)
		store(self:storage_key("seen"), table.concat(lines, "\n"))
	end

	function Organizer:load_baseline()
		local stored = fetch(self:storage_key("seen"))
		if stored == "" then return nil end
		local baseline = {}
		for _, line in ipairs(split_lines(stored)) do
			local key, count = line:match("^(.*)\t(%d+)$")
			if key then baseline[key] = tonumber(count) end
		end
		return baseline
	end

	-- Called with every snapshot.
	function Organizer:count_auto(entries)
		local counts = { Implants = 0, Nanos = 0 }
		for _, entry in ipairs(entries) do
			if entry.occupied then
				local kind = kind_of(entry.name)
				if kind == "implant" then counts.Implants = counts.Implants + 1
				elseif kind == "nano" then counts.Nanos = counts.Nanos + 1 end
			end
		end
		local before = self.auto_counts or {}
		self.auto_counts = counts
		if ((before.Implants or 0) > 0) ~= (counts.Implants > 0) or ((before.Nanos or 0) > 0) ~= (counts.Nanos > 0)
			or not before.Implants then
			self:paint_tabs()
		end
	end

	function Organizer:track(entries)
		self:count_auto(entries)
		local totals, occupied = {}, 0
		for _, entry in ipairs(entries) do
			if entry.occupied then
				occupied = occupied + 1
				local key = key_of(entry)
				totals[key] = (totals[key] or 0) + math.max(1, entry.count or 1)
			end
		end
		self.totals = totals
		local now = ui.time()
		if not self.settle_until or occupied == 0
			or (self.last_occupied and occupied < self.last_occupied * 0.75) then
			self.settle_until = now + SETTLE_MS
		end
		self.last_occupied = occupied
		if now < self.settle_until or not self.character then
			self:wait_to_settle()
			return
		end
		self:evaluate()
	end

	-- Re-check once the settle time has passed (snapshots only arrive when something changes).
	function Organizer:wait_to_settle()
		if self.waiting then return end
		self.waiting = true
		ui.on_update(function(now)
			if now >= (self.settle_until or 0) and self.character then
				self.waiting = false
				ui.stop_updates()
				self:evaluate()
				self.options.reconcile()
			end
		end)
	end

	function Organizer:evaluate()
		local totals = self.totals or {}
		if not self.baseline then
			self.baseline = self:load_baseline()
			if not self.baseline then
				self.baseline = copy(totals) -- first time ever: nothing is new
				self:save_baseline()
				return
			end
		end
		local new = {}
		for key, total in pairs(totals) do
			if total > (self.baseline[key] or 0) then new[key] = true end
		end
		-- Used up / moved out: lower the baseline so regaining the item counts as new.
		local lowered = false
		for key, count in pairs(self.baseline) do
			local total = totals[key] or 0
			if total < count then
				self.baseline[key] = total > 0 and total or nil
				lowered = true
			end
		end
		if lowered then self:save_baseline() end
		local changed = false
		for key in pairs(new) do if not self.new[key] then changed = true end end
		for key in pairs(self.new) do if not new[key] then changed = true end end
		self.new = new
		if changed then self:paint_tabs() end
	end

	function Organizer:mark_seen()
		self.baseline = copy(self.totals)
		self:save_baseline()
		self.new = {}
		self:paint_tabs()
		self.options.reconcile()
	end

	-- ---------------------------------------------------------------- known bags
	-- Item slots carry only a name, so a renamed bag no longer looks like a bag. But the game
	-- marks bag windows "renamable" (bags only), so every bag window (in this package, any
	-- instance) records its title here; a rename swaps the old custom name for the new one.
	--   inv/<character>/bags        one bag name per line
	--   inv/<character>/bag_custom  names you gave (dropped again when renamed / reset)
	function Organizer:read_set(suffix)
		local set = {}
		for _, name in ipairs(split_lines(fetch(self:storage_key(suffix)))) do set[name] = true end
		return set
	end

	function Organizer:write_set(suffix, set)
		local names = {}
		for name in pairs(set) do names[#names + 1] = name end
		table.sort(names)
		store(self:storage_key(suffix), table.concat(names, "\n"))
	end

	-- A bag window showed `name`; `previous` is its earlier title when it was just renamed.
	function Organizer:note_bag(name, previous)
		if not name or name == "" then return end
		self.pending_bags = self.pending_bags or {}
		self.pending_bags[#self.pending_bags + 1] = { name = name, previous = previous }
		self:flush_bags()
	end

	function Organizer:flush_bags()
		if not self.character or not self.pending_bags or #self.pending_bags == 0 then return end
		local bags, custom = self:read_set("bags"), self:read_set("bag_custom")
		for _, change in ipairs(self.pending_bags) do
			bags[change.name] = true
			if change.previous and change.previous ~= change.name then
				custom[change.name] = true
				if custom[change.previous] then -- an earlier name you gave: no longer a bag name
					custom[change.previous], bags[change.previous] = nil, nil
				end
			end
		end
		self.pending_bags = {}
		self:write_set("bags", bags)
		self:write_set("bag_custom", custom)
		self.bags_read_at = nil -- re-read now
	end

	-- Known bag names, re-read from storage at most once a second (bag windows write it).
	function Organizer:known_bags()
		if not self.character then return {} end
		local now = ui.time()
		if not self.bags_read_at or now - self.bags_read_at > 1000 then
			self.bags_read_at = now
			self.bags = self:read_set("bags")
		end
		return self.bags
	end

	-- ---------------------------------------------------------------- implants / nanos
	local NANO_CARRIERS = { ["instruction disc"] = true, ["compiled algorithm"] = true,
		["programmed photon particle emitter"] = true }
	local kind_cache = {} -- name -> "implant" | "nano" | false

	function kind_of(name) -- assigns the local declared at the top
		local known = kind_cache[name]
		if known ~= nil then return known end
		local lower = string.lower(name)
		local kind = false
		local carrier = lower:match("^(.-)%s*%(.+%)$")
		if carrier and (carrier:find("crystal", 1, true) or NANO_CARRIERS[carrier]) then
			kind = "nano"
		elseif lower:find("implant:", 1, true) or lower:find("implant$") or lower:find("implant - ", 1, true)
			or lower:find("symbiant", 1, true) then
			kind = "implant"
		else
			local ok, Reqs = pcall(ui.require, "inventory.reqs")
			if ok and Reqs.mods and Reqs.mods(name, 1) then kind = "implant" end
		end
		kind_cache[name] = kind
		return kind
	end

	function Organizer:is_implant(entry) return kind_of(entry.name) == "implant" end
	function Organizer:is_nano(entry) return kind_of(entry.name) == "nano" end

	-- ---------------------------------------------------------------- filtering
	function Organizer:is_bag(entry)
		if self:known_bags()[entry.name] then return true end
		local name = string.lower(entry.name)
		for _, word in ipairs(BAG_WORDS) do
			if name:find(word, 1, true) then return true end
		end
		return false
	end

	-- Organized = tagged into any category (Favorites or your own), or a bag.
	function Organizer:is_organized(entry)
		if self:is_bag(entry) or kind_of(entry.name) then return true end
		for _, set in pairs(self.tags) do
			if set[entry.name] then return true end
		end
		return false
	end

	function Organizer:in_category(entry, category)
		if category == "All" then return true end
		if category == "New" then return self.new[key_of(entry)] == true end
		if category == "Bags" then return self:is_bag(entry) end
		if category == "Implants" then return self:is_implant(entry) end
		if category == "Nanos" then return self:is_nano(entry) end
		if category == "Unsorted" then return not self:is_organized(entry) end
		local set = self.tags[category]
		return set ~= nil and set[entry.name] == true
	end

	-- True when the plain game grid can be shown as-is (keeps empty slots as drop targets).
	function Organizer:is_plain()
		if not self.active then return self.bag_sort == "Slot" end
		return (self.category == "All" and self.filter == "" and self.sort == "Slot")
	end

	-- Items of one category (optionally name-filtered), in the current display order.
	function Organizer:entries_for(entries, category, filter)
		local list = {}
		for index, entry in ipairs(entries) do
			if entry.occupied and self:in_category(entry, category)
				and (filter == "" or string.lower(entry.name):find(filter, 1, true)) then
				list[#list + 1] = { entry = entry, order = index }
			end
		end
		local sort = self.active and self.sort or self.bag_sort
		table.sort(list, function(a, b)
			local x, y = a.entry, b.entry
			if sort == "Name" then
				if x.name ~= y.name then return x.name < y.name end
				if x.quality ~= y.quality then return x.quality > y.quality end
			end
			if sort == "Quality" and x.quality ~= y.quality then return x.quality > y.quality end
			if sort == "Stack" and x.count ~= y.count then return x.count > y.count end
			if sort == "New" then
				local nx, ny = self.new[key_of(x)] and 1 or 0, self.new[key_of(y)] and 1 or 0
				if nx ~= ny then return nx > ny end
				if x.name ~= y.name then return x.name < y.name end
			end
			return a.order < b.order
		end)
		local result = {}
		for index, item in ipairs(list) do result[index] = item.entry end
		return result
	end

	function Organizer:select_entries(entries)
		self.shown = self:entries_for(entries, self.category, self.filter)
		return self.shown
	end

	function Organizer:show_empty_note(count)
		local text = ""
		if count == 0 then
			if self.filter ~= "" then
				text = "Nothing matches \"" .. self.filter .. "\""
			elseif self.category == "New" then
				text = "Nothing new since you last looked"
			elseif self.category == "Bags" then
				text = "No containers"
			elseif self.category == "Implants" then
				text = "No implants or symbiants"
			elseif self.category == "Nanos" then
				text = "No nano crystals"
			elseif self.category == "Unsorted" then
				text = "Everything is organized"
			elseif self.category ~= "All" then
				text = "Empty. Turn on Organize and click items to add them."
			end
		end
		ui.text(self.empty_note, text)
		ui.visible(self.empty_note, text ~= "")
	end

	-- ---------------------------------------------------------------- organize mode
	function Organizer:set_organizing(on)
		self.organizing = on
		ui.visible(self.overlay, on)
		ui.text_color(self.organize_button, on and ORGANIZE_ON or IDLE)
		ui.text(self.organize_button, on and "Organizing" or "Organize")
	end

	-- cells: list of { root = view, entry = entry } currently on screen
	function Organizer:set_cells(provider)
		self.cell_provider = provider
	end

	function Organizer:organize_click(x, y)
		if not self.cell_provider or not self.character then return end
		for _, cell in ipairs(self.cell_provider()) do
			local entry = cell.entry
			if entry and entry.occupied then
				local left, top = ui.x(cell.root), ui.y(cell.root)
				if x >= left and x < left + ui.width(cell.root) and y >= top and y < top + ui.height(cell.root) then
					self:tag_menu(entry, x, y)
					return
				end
			end
		end
	end

	function Organizer:tag_menu(entry, x, y)
		local anchor = self.overlay
		ui.menu.clear(anchor)
		ui.menu.style(anchor, "context")
		ui.menu.label(anchor, entry.name)
		ui.menu.separator(anchor)
		for _, category in ipairs(self:taggable()) do
			local set = self.tags[category] or {}
			ui.menu.add(anchor, category, set[entry.name] == true, function()
				self.tags[category] = set
				set[entry.name] = not set[entry.name] or nil
				self:save_tags(category)
				self.options.reconcile()
			end)
		end
		ui.menu.show_at(anchor, x, y)
	end

	-- ---------------------------------------------------------------- pop-out panels
	-- Panels sit in the package's full-screen container next to the inventory window, so they
	-- open and close with the inventory; drag a panel by its header to place it anywhere on
	-- screen. Saved per character:
	--   inv/<character>/panels   one line per panel: category<TAB>x<TAB>y<TAB>columns<TAB>mode<TAB>width
	local CELL, GAP = 38, 2
	-- Grid with names: slots 14px apart, a 50px name label under each (6px wider each side).
	local NAMED_GAP, LABEL_W, LABEL_H = 14, 50, 12
	local COLUMN_CHOICES = { 4, 6, 8, 10 }
	local WIDTH_CHOICES = {
		{ label = "Narrow", width = 200 }, { label = "Normal", width = 260 }, { label = "Wide", width = 340 },
	}
	-- List rows, as in the NCU list: 26px icon, then name over a smaller grey detail line.
	local ROW, ICON, ICON_LEFT, ICON_TOP = 32, 26, 2, 5
	local ROW3 = 46 -- three-line row height (requirements on their own line)
	local MAX_LIST_ROWS = 14 -- taller lists scroll

	-- host: the full-screen container; window: the inventory window (for default placement);
	-- make_cells(grid_view) builds a display-only cell grid.
	function Organizer:attach_panels(host, window, make_cells)
		self.panel_host, self.window, self.make_cells = host, window, make_cells
		self:restore_panels()
	end

	function Organizer:save_panels()
		if not self.character then return end
		local lines = {}
		for _, name in ipairs(self.panel_order) do
			local panel = self.panels[name]
			if panel then
				lines[#lines + 1] = string.format("%s\t%.0f\t%.0f\t%d\t%s\t%d", name, panel.x, panel.y,
					panel.columns, panel.mode, panel.list_width)
			end
		end
		store(self:storage_key("panels"), table.concat(lines, "\n"))
	end

	function Organizer:restore_panels()
		if self.panels_restored or not self.panel_host or not self.character or not self.active then return end
		self.panels_restored = true
		for _, line in ipairs(split_lines(fetch(self:storage_key("panels")))) do
			local name, x, y, columns, rest = line:match("^(.-)\t(-?%d+)\t(-?%d+)\t(%d+)(.*)$")
			local mode, width = (rest or ""):match("^\t(%a+)\t(%d+)$")
			if name and self:category_exists(name) then
				self:open_panel(name, tonumber(x), tonumber(y), tonumber(columns), mode, tonumber(width))
			end
		end
	end

	function Organizer:category_exists(name)
		for _, built in ipairs(BUILT_IN) do if built == name then return true end end
		for _, custom in ipairs(self.custom) do if custom == name then return true end end
		return false
	end

	function Organizer:toggle_panel(name, mode)
		if self.panels[name] then self:close_panel(name) else self:open_panel(name, nil, nil, nil, mode) end
		self:save_panels()
	end

	function Organizer:open_panel(name, x, y, columns, mode, list_width)
		if self.panels[name] or not self.panel_host then return end
		local loaded = ui.load("panel.xml")
		ui.add(self.panel_host, loaded)
		local root = ui.find(loaded, "panel") or loaded
		local panel = {
			name = name, root = root,
			header = ui.find(root, "panel_header"),
			title = ui.find(root, "panel_title"),
			count = ui.find(root, "panel_count"),
			grid = ui.find(root, "panel_grid"),
			named_area = ui.find(root, "panel_named_area"),
			named_grid = ui.find(root, "panel_named_grid"),
			label_layer = ui.find(root, "panel_labels"),
			label_measure = ui.find(root, "panel_measure"),
			labels = {}, fitted = {},
			empty = ui.find(root, "panel_empty"),
			columns = columns or 6,
			mode = (mode == "list" or mode == "named") and mode or "grid",
			list_width = list_width or 260,
			list_area = ui.find(root, "panel_list_area"),
			list_host = ui.find(root, "panel_list"),
		}
		panel.cells = self.make_cells(panel.grid)
		pcall(ui.composite, root, true)
		ui.text(panel.title, name)
		ui.align(root, "start", "start")
		-- Default spot: just right of the inventory window, stacked down for each new panel.
		panel.x = x or (ui.local_x(self.window) + ui.width(self.window) + 6)
		panel.y = y or (ui.local_y(self.window) + #self.panel_order * 60)
		ui.place(root, panel.x, panel.y)
		panel.default_spot = x == nil

		local Move = ui.require("core.move")
		ui.require("inventory.snap").add(root)
		Move.attach(root, {
			handle = panel.header,
			placement = { changed = function() end },
			finished = function(completed)
				if completed then
					panel.x, panel.y = ui.local_x(root), ui.local_y(root)
					self:save_panels()
				end
			end,
		})
		ui.on_click(ui.find(root, "panel_close"), function() self:toggle_panel(name) end)

		-- Header right-click: Grid / List, then columns (grid) or width (list).
		ui.menu.style(panel.header, "context")
		ui.on_pointer_release(panel.header, "right", function()
			local header = panel.header
			ui.menu.clear(header)
			local function set(field, value)
				return function()
					panel[field] = value
					self:fill_panel(panel)
					self:save_panels()
				end
			end
			ui.menu.add(header, "Grid", panel.mode == "grid", set("mode", "grid"))
			ui.menu.add(header, "Grid with names", panel.mode == "named", set("mode", "named"))
			ui.menu.add(header, "List", panel.mode == "list", set("mode", "list"))
			ui.menu.separator(header)
			if panel.mode ~= "list" then
				for _, choice in ipairs(COLUMN_CHOICES) do
					ui.menu.add(header, choice .. " columns", choice == panel.columns, set("columns", choice))
				end
			else
				for _, choice in ipairs(WIDTH_CHOICES) do
					ui.menu.add(header, choice.label, choice.width == panel.list_width, set("list_width", choice.width))
				end
			end
			ui.menu.show(header)
		end)

		self.panels[name] = panel
		self.panel_order[#self.panel_order + 1] = name
		self:fill_panel(panel)
		self:keep_on_screen(panel)
	end

	-- Keeps a panel inside the screen. A new panel goes right of the inventory window, or
	-- left of it when that runs off the screen; a saved spot past an edge is pulled back in.
	function Organizer:keep_on_screen(panel)
		local screen_w, screen_h = ui.parent_width(panel.root), ui.parent_height(panel.root)
		if not screen_w or screen_w <= 0 then screen_w, screen_h = ui.width(self.panel_host), ui.height(self.panel_host) end
		if not screen_w or screen_w <= 0 or not screen_h or screen_h <= 0 then return end -- not laid out yet
		local w, h = panel.width or ui.chosen_width(panel.root), panel.height or ui.chosen_height(panel.root)
		local x, y = panel.x, panel.y
		if panel.default_spot and x + w > screen_w then
			x = ui.local_x(self.window) - w - 6
		end
		panel.default_spot = false
		x = math.max(0, math.min(x, screen_w - w))
		y = math.max(0, math.min(y, screen_h - h))
		if x ~= panel.x or y ~= panel.y then
			panel.x, panel.y = x, y
			ui.place(panel.root, x, y)
			self:save_panels()
		end
	end

	-- Name labels under the slots of a "grid with names" panel (display only).
	function Organizer:fit_label(panel, name)
		local known = panel.fitted[name]
		if known then return known end
		local function width(text)
			ui.text(panel.label_measure, text)
			local ok, value = pcall(ui.text_width, panel.label_measure)
			return (ok and value) or #text * 5
		end
		local result = name
		if width(name) > LABEL_W - 2 then
			local low, high = 0, #name
			while low < high do
				local middle = (low + high + 1) // 2
				if width(name:sub(1, middle) .. "..") <= LABEL_W - 2 then low = middle else high = middle - 1 end
			end
			result = name:sub(1, low):gsub("%s+$", "") .. ".."
		end
		panel.fitted[name] = result
		return result
	end

	function Organizer:place_labels(panel, list)
		local count = panel.mode == "named" and #list or 0
		while #panel.labels < count do
			local loaded = ui.load("panel_label.xml")
			ui.add(panel.label_layer, loaded)
			local view = ui.find(loaded, "panel_label") or loaded
			ui.align(view, "start", "start")
			panel.labels[#panel.labels + 1] = { view = view }
		end
		for index, label in ipairs(panel.labels) do
			local entry = list[index]
			ui.visible(label.view, index <= count)
			if index <= count and entry then
				local column = (index - 1) % panel.columns
				local row = (index - 1) // panel.columns
				-- slot left = 6 + column * (CELL + gap); label centred under it
				ui.place(label.view, 6 + column * (CELL + NAMED_GAP) + (CELL - LABEL_W) / 2,
					row * (CELL + NAMED_GAP) + CELL + 1)
				local text = self:fit_label(panel, entry.name or "")
				if label.text ~= text then
					label.text = text
					ui.text(label.view, text)
					ui.tooltip(label.view, entry.name or "")
				end
			end
		end
	end

	function Organizer:close_panel(name)
		local panel = self.panels[name]
		if not panel then return end
		panel.cells:clear()
		if panel.named_cells then panel.named_cells:clear() end
		if panel.list then panel.list:clear() end
		ui.require("inventory.snap").remove(panel.root)
		ui.destroy(panel.root)
		self.panels[name] = nil
		for index, other in ipairs(self.panel_order) do
			if other == name then table.remove(self.panel_order, index) break end
		end
	end

	function Organizer:fill_panel(panel)
		local entries = self.entries or {}
		local list = self:entries_for(entries, panel.name, "")
		ui.text(panel.count, tostring(#list))
		ui.visible(panel.empty, #list == 0)
		local listing = panel.mode == "list"
		local named = panel.mode == "named"
		ui.visible(panel.grid, panel.mode == "grid" and #list > 0)
		ui.visible(panel.named_area, named and #list > 0)
		ui.visible(panel.list_area, listing and #list > 0)
		local width, body
		if listing then
			width = panel.list_width
			local rows = math.min(MAX_LIST_ROWS, math.max(1, #list))
			local inner = width - 2 - 4
			local view = self:panel_list(panel)
			local fixed = 12 + 2 * view.style.gap + ICON + ICON_LEFT
			view.preferred_widths[2] = math.max(60, inner - fixed)
			panel.name_width = view.preferred_widths[2]
			view:set_width(inner)
			panel.three = self:needs_three(list, panel.name_width - 6)
			local row_height = panel.three and ROW3 or ROW
			self:set_row_height(view, row_height)
			ui.size(panel.list_area, inner, rows * row_height)
			view:show(list, list) -- keep our order
			for _, row in ipairs(view.rows) do self:style_list_row(panel, row) end
			if view.prototype then self:style_list_row(panel, view.prototype) end
			panel.cells:show({})
			if panel.named_cells then panel.named_cells:show({}) end
			self:place_labels(panel, {})
			body = #list > 0 and (2 + rows * row_height + 2) or 20
		elseif named then
			local columns = panel.columns
			local rows = math.max(1, math.ceil(#list / columns))
			local grid_width = columns * CELL + (columns - 1) * NAMED_GAP
			local grid_height = rows * CELL + (rows - 1) * NAMED_GAP
			panel.named_cells = panel.named_cells or self.make_cells(panel.named_grid)
			ui.grid_columns(panel.named_grid, columns)
			ui.size(panel.named_grid, grid_width, grid_height)
			ui.size(panel.label_layer, 6 + grid_width + 6, grid_height + LABEL_H + 1)
			ui.size(panel.named_area, 6 + grid_width + 6, grid_height + LABEL_H + 1)
			panel.cells:show({})
			panel.named_cells:show(list)
			if panel.list then panel.list:show({}, {}) end
			self:place_labels(panel, list)
			width = 1 + 4 + 6 + grid_width + 6 + 4 + 1
			body = #list > 0 and (3 + grid_height + LABEL_H + 1 + 4) or 20
		else
			local columns = panel.columns
			local rows = math.max(1, math.ceil(#list / columns))
			local grid_width = columns * CELL + (columns - 1) * GAP
			ui.grid_columns(panel.grid, columns)
			ui.size(panel.grid, grid_width, rows * CELL + (rows - 1) * GAP)
			panel.cells:show(list)
			if panel.named_cells then panel.named_cells:show({}) end
			self:place_labels(panel, {})
			if panel.list then panel.list:show({}, {}) end
			width = 1 + 4 + grid_width + 4 + 1
			body = #list > 0 and (3 + rows * CELL + (rows - 1) * GAP + 4) or 20
		end
		local height = 1 + 20 + 1 + body + 1
		ui.limits(panel.root, width, height, width, height)
		ui.size(panel.root, width, height)
		panel.width, panel.height = width, height
		if self.panels[panel.name] then self:keep_on_screen(panel) end
	end

	-- The panel's list (created the first time it's needed).
	function Organizer:panel_list(panel)
		if panel.list then return panel.list end
		local Table = ui.require("core.table")
		local organizer = self
		panel.list = Table.create({
			host = panel.list_host,
			style = "inset",
			row_height = ROW,
			fit_columns = true,
			preference = "modern_panel_list",
			binding = function(entry) return entry.token end,
			columns = {
				{ id = "icon", title = "", width = ICON + ICON_LEFT, minimum = ICON, kind = "icon", resizable = false,
					icon = function(entry) return entry.icon end },
				{ id = "item", title = "Item", width = 150, minimum = 60,
					text = function(entry) return organizer:list_plain(panel, entry) end },
			},
		})
		ui.visible(ui.find(panel.list.root, "table_header_scroll"), false)
		panel.list.sort = ""
		return panel.list
	end

	function Organizer:fit_name(name, width)
		self.fitted = self.fitted or {}
		local key = name .. "\0" .. width
		if self.fitted[key] then return self.fitted[key] end
		local function measure(text)
			ui.text(self.measure, text)
			local ok, value = pcall(ui.text_width, self.measure)
			return (ok and value) or #text * 6
		end
		local result = name
		if measure(name) > width then
			local low, high = 0, #name
			while low < high do
				local middle = math.floor((low + high + 1) / 2)
				if measure(name:sub(1, middle) .. "...") <= width then low = middle else high = middle - 1 end
			end
			result = name:sub(1, low):gsub("%s+$", "") .. "..."
		end
		self.fitted[key] = result
		return result
	end

	local DETAIL, UNMET = "#A3ADBA", "#FF7A70"
	local MOD, MOD_NEGATIVE, MOD_UNKNOWN = "#8FD6A0", "#FF7A70", "#6E7885"
	local SEPARATOR = "  ·  "

	-- Second-line parts: stack, QL, lock timer, then requirements (unmet ones red).
	-- Requirements that don't fit the row width are dropped from the end.
	local function texts_of(parts)
		local texts = {}
		for index, part in ipairs(parts) do texts[index] = part.text end
		return table.concat(texts, SEPARATOR)
	end

	function Organizer:measure_width(text)
		ui.text(self.measure, text)
		local ok, measured = pcall(ui.text_width, self.measure)
		return (ok and measured) or #text * 6
	end

	-- Line 2: stack, QL, lock timer, weapon damage. Then implant modifiers (green, negative
	-- red, "+?" when more clusters may be present). Requirements: unmet ones red.
	-- Returns fixed parts, requirement parts, modifier parts.
	function Organizer:item_parts(entry)
		local fixed = {}
		if (entry.count or 1) > 1 then fixed[#fixed + 1] = { text = "×" .. entry.count } end
		fixed[#fixed + 1] = { text = "QL " .. tostring(entry.quality) }
		if entry.locked and entry.remaining and entry.remaining ~= "" then
			fixed[#fixed + 1] = { text = "locked " .. entry.remaining }
		end
		local ok, Reqs = pcall(ui.require, "inventory.reqs")
		local damage = ok and Reqs.damage(entry.name, entry.quality) or nil
		if damage then fixed[#fixed + 1] = { text = damage, color = "#E8ECF1" } end
		local reqs = {}
		for _, req in ipairs(ok and Reqs.parts(entry.name, entry.quality) or {}) do
			reqs[#reqs + 1] = { text = req.text, color = req.met == false and UNMET or nil }
		end
		local mods = {}
		for _, mod in ipairs(ok and Reqs.mods and Reqs.mods(entry.name, entry.quality) or {}) do
			mods[#mods + 1] = { text = mod.text,
				color = mod.unknown and MOD_UNKNOWN or mod.negative and MOD_NEGATIVE or MOD }
		end
		return fixed, reqs, mods
	end

	-- Drop parts from the end (never below `keep`) until the line fits `width`.
	function Organizer:fit_parts(parts, keep, width)
		while #parts > keep and self:measure_width(texts_of(parts)) > width do
			table.remove(parts)
		end
		return parts
	end

	-- True when an item's details don't fit on one line (so the list needs a third line).
	function Organizer:crowded(entry, width)
		local fixed, reqs, mods = self:item_parts(entry)
		if #reqs == 0 then return false end
		local all = {}
		for _, part in ipairs(fixed) do all[#all + 1] = part end
		for _, part in ipairs(mods) do all[#all + 1] = part end
		for _, part in ipairs(reqs) do all[#all + 1] = part end
		return self:measure_width(texts_of(all)) > width
	end

	-- Detail lines for a row: { line2 parts, line3 parts or nil }.
	-- Modifiers ride on line 2 after the fixed parts; requirements go to line 3 when the
	-- list has three lines. Whatever doesn't fit is dropped from the end.
	function Organizer:detail_lines(entry, width, three)
		local fixed, reqs, mods = self:item_parts(entry)
		local keep = #fixed
		for _, part in ipairs(mods) do fixed[#fixed + 1] = part end
		if three then
			return self:fit_parts(fixed, keep, width), self:fit_parts(reqs, 0, width)
		end
		for _, part in ipairs(reqs) do fixed[#fixed + 1] = part end
		return self:fit_parts(fixed, keep, width), nil
	end

	-- Does any of these items need a third line at this width?
	function Organizer:needs_three(entries, width)
		for _, entry in ipairs(entries) do
			if self:crowded(entry, width) then return true end
		end
		return false
	end

	-- Switch a list's rows between two and three lines (all rows share one height).
	function Organizer:set_row_height(view, height)
		if view.row_height == height then return end
		view.row_height = height
		local function resize(row)
			ui.size(row.root, -1, height)
			for index = 1, #view.columns do view:cell_width(row, index) end
		end
		for _, row in ipairs(view.rows) do resize(row) end
		if view.prototype then resize(view.prototype) end
	end

	function Organizer:list_plain(panel, entry)
		local width = (panel.name_width or 150) - 6
		local line2, line3 = self:detail_lines(entry, width, panel.three)
		local text = self:fit_name(entry.name, width) .. "\n" .. texts_of(line2)
		if line3 then text = text .. "\n" .. texts_of(line3) end
		return text
	end

	local function escape(text)
		return (text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
	end

	-- Bigger icon + rich two-line text, applied after the table writes each row.
	function Organizer:style_list_row(panel, row)
		local icon, text = row.cells[1], row.cells[2]
		if icon and icon.icon then
			ui.limits(icon.icon, ICON, ICON, ICON, ICON)
			ui.size(icon.icon, ICON, ICON)
			ui.align(icon.icon, "start", "start")
			local row_height = panel.three and ROW3 or ROW
			ui.borders(icon.icon, ICON_LEFT, ICON_TOP + math.floor((row_height - ROW) / 2), 0, 0)
			if icon.space then ui.size(icon.space, ICON + ICON_LEFT, row_height) end
		end
		if text and text.value then
			ui.font_size(text.value, 12)
			local entry = text.entry
			if entry then
				-- Amber: new, or matching the item search; red: can't equip; dim: search non-match.
				local name_color = (entry.search == "match" or self.new[key_of(entry)]) and "#F0C060"
					or (entry.over_equipped and "#FF7A70")
					or (entry.search == "other" and "#6E7885") or "#E8ECF1"
				local width = (panel.name_width or 150) - 6
				local function rich(parts)
					local pieces = {}
					for index, part in ipairs(parts) do
						if index > 1 then pieces[#pieces + 1] = string.format("<font color=%s>%s</font>", DETAIL, SEPARATOR) end
						pieces[#pieces + 1] = string.format("<font color=%s>%s</font>", part.color or DETAIL, escape(part.text))
					end
					return table.concat(pieces)
				end
				local line2, line3 = self:detail_lines(entry, width, panel.three)
				local markup = string.format('<font color=%s>%s</font><br>%s',
					name_color, escape(self:fit_name(entry.name, width)), rich(line2))
				if line3 then markup = markup .. "<br>" .. rich(line3) end
				if text.rich ~= markup or text.rich_source ~= text.text then
					pcall(ui.aoml, text.value, "", markup, false)
					text.rich, text.rich_source = markup, text.text
				end
			end
		end
	end

	-- Called with every snapshot (and whenever tags / sort change).
	function Organizer:refresh_panels(entries)
		self.entries = entries
		for _, name in ipairs(self.panel_order) do
			local panel = self.panels[name]
			if panel then self:fill_panel(panel) end
		end
	end

	-- ---------------------------------------------------------------- show / hide parts
	function Organizer:height()
		if not self.active then return 0 end
		return (self.show.tabs or self.show.sort or self.show.organize) and ROW_HEIGHT or 0
	end

	function Organizer:apply_visibility()
		local show = self.show
		if not show.tabs and self.category ~= "All" then
			self.category = "All" -- no tabs to get back with, so show everything
			self:paint_tabs()
		end
		if not show.organize and self.organizing then self:set_organizing(false) end
		ui.visible(self.tab_row, show.tabs)
		ui.visible(self.tab_add, show.tabs)
		ui.visible(self.sort_button, show.sort)
		ui.visible(self.organize_button, show.organize)
		ui.visible(self.seen_button, show.tabs and self.category == "New")
		ui.visible(self.root, self.active and self:height() > 0)
	end

	function Organizer:set_shown(part, value)
		self.show[part] = value
		ui.preference.write("modern_show_" .. part, tostring(value), "bool")
		self:apply_visibility()
		if self.options.resize then self.options.resize() end
		self.options.reconcile()
	end

	-- Bag / bank / loot windows: one sort order shared by all of them (per character).
	function Organizer:set_bag_sort(sort)
		if not BAG_SORTS[sort] or sort == self.bag_sort then return end
		self.bag_sort = sort
		if self.character then store(self:storage_key("bag_sort"), sort) end
		self.options.reconcile()
	end

	-- ---------------------------------------------------------------- lifecycle
	function Organizer:activate(on)
		self.active = on
		if not on then self:set_organizing(false) end
		if on and #self.tabs == 0 then self:build_tabs() end
		if on then self:restore_panels() end
		self:apply_visibility()
	end

	return Organizer
end)
