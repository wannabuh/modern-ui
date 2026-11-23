-- Bank groups: the bank's list view split into named sections you can fold.
--
-- Display only, like the organizer: items never move. Rows are bound to the same native slot
-- references as the plain list, so drag, use and inspect keep working.
--
--   Click a group header to fold / unfold it; right-click it to rename, move or delete it.
--   Organize groups (title menu, or the bar's Done button to leave it): while on, rows are not
--   bound to their slots, so clicking an item opens its group menu instead of the game's item
--   handling (right-click is the game's bank <-> inventory move). The choice is saved by item
--   name, so every stack / bag with that name follows it.
--   Items you haven't placed get a suggested group from their name: "Implants ..." bags and
--   implants go to Implants, "... Nanos" bags and nano items to Profession nanos. Anything else
--   is in Other, at the bottom.
--
-- Saved per character in this package's storage:
--   inv/<character>/bank_groups     group names in display order, one per line
--   inv/<character>/bank_assign     "<item name>\t<group>" per line ("" group = Other)
--   inv/<character>/bank_folded     folded group names, one per line
--   inv/<character>/bank_grouping   "off" when Show groups is turned off in the title menu
ui.define("inventory.groups", function()
	local Groups = {}
	Groups.__index = Groups

	local OTHER = "Other"
	local IMPLANTS, NANOS = "Implants", "Profession nanos"
	local HEADER = 22
	local ICON_COLUMN = 28 -- as the plain list's icon column (26px icon + 2px nudge)
	local GAP = 6 -- the core table's compact cell gap
	local MAX_NAME = 32

	local function lines(text)
		local list = {}
		for line in (text or ""):gmatch("[^\n]+") do list[#list + 1] = line end
		return list
	end

	local function clean(name)
		name = (name or ""):gsub("[\t\n\r]", " "):gsub("^%s+", ""):gsub("%s+$", "")
		if #name > MAX_NAME then name = name:sub(1, MAX_NAME) end
		return name
	end

	-- content: the inventory window content; options: { organizer, reconcile, selected, faded, tint }
	function Groups.create(content, options)
		local self = setmetatable({}, Groups)
		self.options = options
		self.organizer = options.organizer
		self.view = ui.find(content, "grouped_view")
		self.scroll = ui.find(content, "grouped_content")
		self.host = ui.find(content, "grouped_rows")
		self.name_row = ui.find(content, "group_name_row")
		self.name_input = ui.find(content, "group_name")
		self.menu = ui.find(content, "group_menu")
		self.window = false -- this window can be grouped (the bank)
		self.on = true
		self.loaded = nil -- character the saved groups were read for
		self.order = {} -- group names, display order
		self.assign = {} -- item name -> group ("" = Other)
		self.folded = {} -- group -> true
		self.sections = {} -- shown sections, in order: { name, root, header, arrow, label, count, body, rows }
		self.layout_key = nil
		self.pending_name, self.naming = "", nil
		self.dirty = false
		self.organizing = false
		self.rows_organizing = false -- the mode the current rows were created for
		self.organize_bar = ui.find(content, "group_organize_bar")
		ui.menu.style(self.menu, "context")
		ui.on_text_changed(self.name_input, function(value) self.pending_name = value or "" end)
		ui.on_click(ui.find(content, "group_name_cancel"), function() self:close_naming() end)
		ui.on_click(ui.find(content, "group_name_confirm"), function() self:confirm_naming() end)
		ui.on_click(ui.find(content, "group_organize_done"), function() self:set_organizing(false) end)
		ui.require("core.security").on_unlock(function()
			if self.dirty then self.dirty = false; self.options.reconcile() end
		end)
		return self
	end

	-- ---------------------------------------------------------------- storage
	function Groups:key(suffix)
		return "inv/" .. self.organizer.character .. "/" .. suffix
	end

	function Groups:load()
		local character = self.organizer.character
		if not character or self.loaded == character then return end
		self.loaded = character
		local fetch = self.organizer.fetch
		self.on = fetch(self:key("bank_grouping")) ~= "off"
		self.order = {}
		for _, name in ipairs(lines(fetch(self:key("bank_groups")))) do
			name = clean(name)
			if name ~= "" and name ~= OTHER then self.order[#self.order + 1] = name end
		end
		self.assign = {}
		for _, line in ipairs(lines(fetch(self:key("bank_assign")))) do
			local item, group = line:match("^(.-)\t(.*)$")
			if item and item ~= "" then self.assign[item] = group end
		end
		self.folded = {}
		for _, name in ipairs(lines(fetch(self:key("bank_folded")))) do self.folded[name] = true end
	end

	function Groups:save_order()
		if not self.loaded then return end
		self.organizer.store(self:key("bank_groups"), table.concat(self.order, "\n"))
	end

	function Groups:save_assign()
		if not self.loaded then return end
		local items = {}
		for item in pairs(self.assign) do items[#items + 1] = item end
		table.sort(items)
		for index, item in ipairs(items) do items[index] = item .. "\t" .. self.assign[item] end
		self.organizer.store(self:key("bank_assign"), table.concat(items, "\n"))
	end

	function Groups:save_folded()
		if not self.loaded then return end
		local names = {}
		for name in pairs(self.folded) do names[#names + 1] = name end
		table.sort(names)
		self.organizer.store(self:key("bank_folded"), table.concat(names, "\n"))
	end

	-- ---------------------------------------------------------------- state
	-- Only the bank is grouped; main.lua says whether this window is it.
	function Groups:set_window(is_bank)
		self.window = is_bank
		if not is_bank then self:close_naming(); self:set_organizing(false) end
	end

	-- Rows are rebuilt for the new mode (bound or not), which can't happen during combat.
	function Groups:set_organizing(on)
		if on == self.organizing or (on and ui.in_combat()) then return end
		self.organizing = on
		ui.visible(self.organize_bar, on)
		if not on then self:close_naming() end
		if self.options.organizing then self.options.organizing(on) end
		self.options.reconcile()
	end

	function Groups:active()
		self:load()
		return self.window and self.on
	end

	function Groups:set_on(on)
		self.on = on
		if self.loaded then self.organizer.store(self:key("bank_grouping"), on and "" or "off") end
		self.options.reconcile()
	end

	function Groups:index_of(name)
		for index, other in ipairs(self.order) do
			if other == name then return index end
		end
	end

	-- Suggested group for an item nobody placed yet.
	function Groups:suggest(entry)
		local name = string.lower(entry.name)
		if name:find("^implants?[%s:]") or name == "implants" or self.organizer:is_implant(entry) then return IMPLANTS end
		if name:find("%snanos$") or self.organizer:is_nano(entry) then return NANOS end
		return ""
	end

	function Groups:group_of(entry)
		local chosen = self.assign[entry.name]
		if chosen ~= nil and (chosen == "" or self:index_of(chosen)) then return chosen end
		return self:suggest(entry)
	end

	-- ---------------------------------------------------------------- editing
	function Groups:place(item, group)
		if group ~= "" and not self:index_of(group) then
			self.order[#self.order + 1] = group
			self:save_order()
		end
		self.assign[item] = group
		self:save_assign()
		self.options.reconcile()
	end

	-- Pins every item currently shown in a group to it (so renaming / deleting a suggested
	-- group doesn't bring the suggestion back).
	function Groups:pin_members(name, target)
		for _, section in ipairs(self.sections) do
			if section.name == name then
				for _, entry in ipairs(section.entries or {}) do self.assign[entry.name] = target end
			end
		end
		for item, group in pairs(self.assign) do
			if group == name then self.assign[item] = target end
		end
	end

	function Groups:rename(old, new)
		new = clean(new)
		if new == "" or new == old or new == OTHER or self:index_of(new) then return end
		local index = self:index_of(old)
		if not index then return end
		self:pin_members(old, new)
		self.order[index] = new
		if self.folded[old] then self.folded[old], self.folded[new] = nil, true; self:save_folded() end
		self:save_order()
		self:save_assign()
		self.options.reconcile()
	end

	function Groups:delete(name)
		local index = self:index_of(name)
		if not index then return end
		self:pin_members(name, "")
		table.remove(self.order, index)
		if self.folded[name] then self.folded[name] = nil; self:save_folded() end
		self:save_order()
		self:save_assign()
		self.options.reconcile()
	end

	function Groups:move(name, step)
		local index = self:index_of(name)
		local target = index and index + step
		if not target or target < 1 or target > #self.order then return end
		self.order[index], self.order[target] = self.order[target], self.order[index]
		self:save_order()
		self.options.reconcile()
	end

	function Groups:toggle_fold(name)
		self.folded[name] = not self.folded[name] or nil
		self:save_folded()
		self.options.reconcile()
	end

	-- The name row (top of the grouped view): naming = { item = name } for a new group from an
	-- item's menu, or { rename = group }.
	function Groups:open_naming(naming, text)
		self.naming = naming
		self.pending_name = text or ""
		ui.text(self.name_input, self.pending_name)
		ui.visible(self.name_row, true)
		pcall(ui.focus, self.name_input)
	end

	function Groups:close_naming()
		self.naming = nil
		ui.visible(self.name_row, false)
	end

	function Groups:confirm_naming()
		local naming, name = self.naming, clean(self.pending_name)
		self:close_naming()
		if not naming or name == "" or name == OTHER then return end
		if naming.rename then
			self:rename(naming.rename, name)
		elseif naming.item then
			self:place(naming.item, name)
		end
	end

	-- ---------------------------------------------------------------- menus
	function Groups:item_menu(entry)
		if not entry or not entry.occupied then return end
		local menu, item = self.menu, entry.name
		local current = self:group_of(entry)
		ui.menu.clear(menu)
		ui.menu.label(menu, item)
		ui.menu.separator(menu)
		local names = {}
		for _, name in ipairs(self.order) do names[#names + 1] = name end
		for _, section in ipairs(self.sections) do -- suggested groups on screen, not saved yet
			if section.name ~= OTHER and not self:index_of(section.name) then names[#names + 1] = section.name end
		end
		for _, name in ipairs(names) do
			ui.menu.add(menu, name, current == name, function() self:place(item, name) end)
		end
		ui.menu.add(menu, OTHER, current == "", function() self:place(item, "") end)
		ui.menu.separator(menu)
		ui.menu.add(menu, "New group...", false, function() self:open_naming({ item = item }) end)
		ui.menu.show(menu)
	end

	function Groups:group_menu(name)
		local menu = self.menu
		ui.menu.clear(menu)
		ui.menu.label(menu, name)
		ui.menu.separator(menu)
		local folded = self.folded[name] == true
		ui.menu.add(menu, folded and "Unfold" or "Fold", false, function() self:toggle_fold(name) end)
		ui.menu.add(menu, "Fold all", false, function()
			for _, section in ipairs(self.sections) do self.folded[section.name] = true end
			self:save_folded()
			self.options.reconcile()
		end)
		ui.menu.add(menu, "Unfold all", false, function()
			self.folded = {}
			self:save_folded()
			self.options.reconcile()
		end)
		if name ~= OTHER then
			-- A suggested group gets a place in the saved order the first time it's edited.
			local function adopt()
				if not self:index_of(name) then self.order[#self.order + 1] = name end
			end
			ui.menu.separator(menu)
			ui.menu.add(menu, "Rename...", false, function() adopt(); self:open_naming({ rename = name }, name) end)
			ui.menu.add(menu, "Move up", false, function() adopt(); self:move(name, -1) end)
			ui.menu.add(menu, "Move down", false, function() adopt(); self:move(name, 1) end)
			ui.menu.add(menu, "Delete group", false, function() adopt(); self:delete(name) end)
		end
		ui.menu.show(menu)
	end

	-- ---------------------------------------------------------------- display
	-- Sections in display order: saved groups, then suggested ones not saved yet, then Other.
	function Groups:partition(entries)
		local by_group = {}
		for _, entry in ipairs(entries) do
			local group = self:group_of(entry)
			by_group[group] = by_group[group] or {}
			table.insert(by_group[group], entry)
		end
		local result, seen = {}, {}
		local function add(name, key)
			if seen[key] then return end
			seen[key] = true
			if by_group[key] and #by_group[key] > 0 then
				result[#result + 1] = { name = name, entries = by_group[key] }
			end
		end
		for _, name in ipairs(self.order) do add(name, name) end
		add(IMPLANTS, IMPLANTS)
		add(NANOS, NANOS)
		add(OTHER, "")
		return result
	end

	function Groups:create_row(section)
		local row = { root = ui.shared_layout("table_row.xml"), cells = {} }
		ui.add(section.body, row.root)
		local icon_root = ui.shared_layout("table_icon.xml")
		local text_root = ui.shared_layout("table_text.xml")
		row.cells[1] = { root = icon_root, icon = ui.find(icon_root, "icon") }
		row.cells[2] = { root = text_root, value = ui.find(text_root, "value") }
		ui.text_alignment(row.cells[2].value, "left")
		ui.add(row.root, icon_root)
		ui.add(row.root, text_root)
		if self.organizing then
			ui.on_click(row.root, function() self:item_menu(row.entry) end)
		end
		return row
	end

	function Groups:create_section(name)
		local loaded = ui.load("group.xml")
		ui.add(self.host, loaded)
		local root = ui.find(loaded, "group_section") or loaded
		local section = {
			name = name, root = root, rows = {},
			header = ui.find(root, "group_header"),
			arrow = ui.find(root, "group_arrow"),
			label = ui.find(root, "group_label"),
			count = ui.find(root, "group_count"),
			body = ui.find(root, "group_body"),
		}
		ui.text(section.label, name)
		ui.on_click(section.header, function() self:toggle_fold(section.name) end)
		ui.on_pointer_release(section.header, "right", function() self:group_menu(section.name) end)
		return section
	end

	function Groups:clear()
		if ui.in_combat() then return end
		for _, section in ipairs(self.sections) do ui.destroy(section.root) end
		self.sections, self.layout_key = {}, nil
	end

	-- entries: the occupied slots in the window's display order; style: { name_width, three }
	-- for the organizer's row text; row_height: 32 or 46.
	function Groups:show(entries, style, row_height)
		local parts = self:partition(entries)
		local locked = ui.in_combat()
		local names = {}
		for index, part in ipairs(parts) do names[index] = part.name end
		local key = table.concat(names, "\n")
		if self.organizing ~= self.rows_organizing and not locked then
			self:clear()
			self.rows_organizing = self.organizing
		end
		if key ~= self.layout_key then
			if locked then
				self.dirty = true -- sections can't be rebuilt during combat; refresh what's there
			else
				self:clear()
				for _, name in ipairs(names) do self.sections[#self.sections + 1] = self:create_section(name) end
				self.layout_key = key
			end
		end
		local by_name = {}
		for _, part in ipairs(parts) do by_name[part.name] = part.entries end
		local organizer, options = self.organizer, self.options
		local text_width = style.name_width
		for _, section in ipairs(self.sections) do
			local list = by_name[section.name] or {}
			local folded = self.folded[section.name] == true
			ui.text(section.arrow, folded and "►" or "▼")
			ui.text(section.count, tostring(#list))
			ui.visible(section.body, not folded and #list > 0)
			if locked then
				-- Keep each row's binding; only refresh rows whose item is still there.
				local present = {}
				for _, entry in ipairs(entries) do present[entry.token] = entry end
				for _, row in ipairs(section.rows) do
					local entry = row.entry and present[row.entry.token]
					if entry then row.entry = entry end
					ui.opacity(row.root, entry and 1 or 0.4)
				end
				list = {}
				for _, row in ipairs(section.rows) do list[#list + 1] = row.entry end
			else
				section.entries = list
				local shown = folded and {} or list
				while #section.rows > #shown do
					ui.destroy(section.rows[#section.rows].root)
					section.rows[#section.rows] = nil
				end
				while #section.rows < #shown do section.rows[#section.rows + 1] = self:create_row(section) end
				for index, entry in ipairs(shown) do
					local row = section.rows[index]
					row.entry = entry
					if not self.rows_organizing then ui.bind(row.root, entry.token) end
					ui.opacity(row.root, 1)
				end
			end
			for _, row in ipairs(section.rows) do
				local entry = row.entry
				if entry then
					local icon, text = row.cells[1], row.cells[2]
					ui.size(row.root, -1, row_height)
					ui.size(icon.root, ICON_COLUMN + GAP, row_height)
					ui.size(text.root, text_width + GAP, row_height)
					ui.size(text.value, math.max(1, text_width - GAP), row_height)
					ui.selected(row.root, options.selected(entry))
					if icon.resource ~= entry.icon then
						ui.icon(icon.icon, entry.icon)
						icon.resource = entry.icon
					end
					ui.content(icon.icon, true)
					ui.fade(icon.icon, options.faded(entry), options.tint(entry))
					text.entry = entry
					local plain = organizer:list_plain(style, entry)
					if text.text ~= plain then
						ui.text(text.value, plain)
						text.text = plain
					end
					organizer:style_list_row(style, row)
				end
			end
		end
	end

	return Groups
end)
