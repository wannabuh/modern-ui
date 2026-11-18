-- Cooldowns window: everything currently cooling on a visible shortcut-bar row (perks,
-- specials, nanos, items), soonest ready first. Display only; use things from the bars.
-- The list shrinks to what's cooling; with nothing cooling only the title strip shows (so
-- the window can still be dragged). It grows UPWARD: the bottom edge stays put, and dragging
-- saves the bottom-left corner. Toggle: Actions → Cooldowns Window.
--
-- Data: every bar (same package, see role.lua / hotbar.lua) writes its slots to storage key
-- "cd/<bar>" as "<stamp>\n<name>\t<countdown>\t<slot>\n...", about once a second while
-- something on it is cooling. The game only sends whole seconds left, so a bar's "full" is
-- the time seen when that cooldown started; bars drain smoothly in between.
--
-- Icons: perks use the icon from the Control Center's perk list; other rows have none (a
-- bar's icon handles are local to that bar: 1, 2, 3... per slot).
ui.define("control_center.cooldown_window", function()
	local Window = {}
	Window.__index = Window

	local WIDTH = 220
	local ROW, TITLE = 22, 18 + 1 + 2 -- row + gap; title strip + divider + outline
	local POLL_MS = 100
	local SOON = 5
	local STALE_MS = 3000 -- this far past zero, the countdown came from a bar that went away
	local COLORS = { text = "#E8ECF1", time = "#E8ECF1", soon = "#F0C060" }
	local BARS = { normal = "#592A8A99", soon = "#59F0C060" }

	-- "12", "12s", "1:05", "1:02:03", "5m", "2h" -> seconds (nil when unreadable).
	local function parse_countdown(text)
		text = (text or ""):gsub("%s", "")
		if text == "" then return nil end
		local h, m, s = text:match("^(%d+):(%d%d):(%d%d)$")
		if h then return h * 3600 + m * 60 + s end
		m, s = text:match("^(%d+):(%d%d)$")
		if m then return m * 60 + s end
		local n, unit = text:match("^(%d+)([smh]?)$")
		if n then return tonumber(n) * (unit == "m" and 60 or unit == "h" and 3600 or 1) end
		return nil
	end

	local function format_time(seconds)
		seconds = math.max(0, math.ceil(seconds))
		if seconds < 60 then return seconds .. "s" end
		if seconds < 3600 then return string.format("%d:%02d", seconds // 60, seconds % 60) end
		return string.format("%dh%02d", seconds // 3600, (seconds % 3600) // 60)
	end

	-- Clears relay entries left by an earlier session (bars write fresh ones within a second).
	function Window.clear_relay()
		for index = ui.storage.count(), 1, -1 do
			local key = ui.storage.key(index)
			if key:sub(1, 3) == "cd/" then ui.storage.write(key, "") end
		end
	end

	-- Everything cooling right now: { {name=, left=, seconds=, text=, icon=}, ... }, one per name.
	local function read_relay(now)
		local by_name = {}
		for index = 1, ui.storage.count() do
			local key = ui.storage.key(index)
			if key:sub(1, 3) == "cd/" then
				local value = ui.storage.read(key)
				local stamp = tonumber(value:match("^(%d+)\n")) or now
				local elapsed = (now - stamp) / 1000
				for line in value:gmatch("\n([^\n]+)") do
					local name, countdown, icon = line:match("^([^\t]+)\t([^\t]*)\t?(.*)$")
					if name and countdown ~= "" then
						local seconds = parse_countdown(countdown)
						local left = seconds and seconds - elapsed or nil
						-- Whole seconds are rounded: stay within the second the bar last reported.
						if left and elapsed <= 1 then left = math.max(seconds - 1, left) end
						if not (left and left < -STALE_MS / 1000) and not (left and left <= 0) then
							local lower = string.lower(name)
							local known = by_name[lower]
							if not known or (left or math.huge) < (known.left or math.huge) then
								by_name[lower] = { name = name, lower = lower, text = countdown, seconds = seconds,
									left = left, icon = tonumber(icon) }
							end
						end
					end
				end
			end
		end
		local list = {}
		for _, item in pairs(by_name) do list[#list + 1] = item end
		table.sort(list, function(a, b)
			local la, lb = a.left or math.huge, b.left or math.huge
			if la ~= lb then return la < lb end
			return a.lower < b.lower
		end)
		return list
	end

	function Window.create(options)
		local self = setmetatable({}, Window)
		self.root = ui.load("cooldown_window.xml")
		self.view = ui.find(self.root, "cc_cooldowns") or self.root
		ui.add(options.parent, self.root)
		self.host = ui.find(self.view, "cd_rows")
		self.measure = ui.find(self.view, "cd_measure")
		self.title = ui.find(self.view, "cd_title_text")
		self.rows, self.timing, self.fitted, self.perk_icons = {}, {}, {}, {}
		self.name_width = WIDTH - 2 - 4 - 18 - 6 - 48 - 6
		self.on_toggle = options.on_toggle
		self.shown_rows = -1
		self.height = TITLE
		ui.size(self.view, WIDTH, TITLE)
		self:place_saved()
		self:resize(0)
		local Move = ui.require("core.move")
		Move.attach(self.view, {
			handle = ui.find(self.view, "cd_title"),
			placement = { changed = function() end },
			finished = function(completed)
				if completed then self:save_position() end
			end,
		})
		ui.on_click(ui.find(self.view, "cd_close"), function() self:show(false) end)
		local saved = ui.storage.read("cooldowns_shown")
		if saved == "" then saved = ui.storage.read("perks_window_shown") end
		self:show(saved == "1", true)
		return self
	end

	-- Saved as "x,bottom" so the window keeps its bottom edge whatever its height.
	function Window:save_position()
		self.x, self.bottom = ui.local_x(self.view), ui.local_y(self.view) + self.height
		ui.align(self.view, "start", "start") -- from now on placed explicitly (see resize)
		ui.place(self.view, self.x, self.bottom - self.height)
		ui.storage.write("cooldowns_bottom", string.format("%.0f,%.0f", self.x, self.bottom))
	end

	function Window:place_saved()
		local function read(key)
			local x, y = ui.storage.read(key):match("^(-?[%d.]+),(-?[%d.]+)$")
			return tonumber(x), tonumber(y)
		end
		local x, bottom = read("cooldowns_bottom")
		if not x then
			-- Older saves were the top-left corner (Perk Actions / first Cooldowns build).
			local top
			x, top = read("cooldowns_position")
			if not x then x, top = read("perks_position") end
			if x then bottom = top + self.height end
		end
		if x then
			self.x, self.bottom = x, bottom
			ui.align(self.view, "start", "start")
			ui.place(self.view, x, bottom - self.height)
		else
			-- First run: bottom-right, above the Control Center bar; grows upward by alignment.
			ui.align(self.view, "end", "end")
			ui.borders(self.view, 0, 0, 12, 260)
		end
	end

	function Window:shown() return self.visible == true end

	function Window:show(visible, quiet)
		self.visible = visible
		ui.visible(self.view, visible)
		if not quiet then ui.storage.write("cooldowns_shown", visible and "1" or "0") end
		if self.on_toggle then self.on_toggle(visible) end
		if visible then
			self:present(ui.time())
			self:animate()
		end
	end

	-- Perk list from control_center_apply: name -> icon, for row icons.
	function Window:set_perks(perks)
		self.perk_icons = {}
		for _, perk in ipairs(perks or {}) do self.perk_icons[string.lower(perk.label)] = perk.icon end
	end

	function Window:fit(name)
		if self.fitted[name] then return self.fitted[name] end
		local function width(text)
			ui.text(self.measure, text)
			local ok, value = pcall(ui.text_width, self.measure)
			return ok and value or #text * 6
		end
		local result = name
		if width(name) > self.name_width then
			local low, high = 0, #name
			while low < high do
				local middle = (low + high + 1) // 2
				if width(name:sub(1, middle) .. "...") <= self.name_width then low = middle else high = middle - 1 end
			end
			result = name:sub(1, low):gsub("%s+$", "") .. "..."
		end
		self.fitted[name] = result
		return result
	end

	function Window:resize(count)
		if count == self.shown_rows then return end
		self.shown_rows = count
		while #self.rows < count do
			local loaded = ui.load("cooldown_row.xml")
			ui.add(self.host, loaded)
			local view = ui.find(loaded, "cd_row") or loaded
			ui.borders(view, 0, 0, 0, 1)
			local row = {
				root = view, bar = ui.find(view, "row_bar"), icon = ui.find(view, "row_icon"),
				name = ui.find(view, "row_name"), time = ui.find(view, "row_time"),
			}
			ui.text_alignment(row.time, "right")
			self.rows[#self.rows + 1] = row
		end
		for index, row in ipairs(self.rows) do ui.visible(row.root, index <= count) end
		self.height = TITLE + count * ROW
		ui.size(self.view, WIDTH, self.height)
		-- Keep the bottom edge where it was (bottom-aligned by default, or placed from a save).
		if self.bottom then ui.place(self.view, self.x, self.bottom - self.height) end
	end

	local function set(row, field, value, apply)
		if row[field] ~= value then
			row[field] = value
			apply(value)
		end
	end

	function Window:icon_for(item)
		return self.perk_icons[item.lower]
	end

	function Window:present(now)
		if not self.visible then return end
		local list = read_relay(now)
		self:resize(#list)
		local seen = {}
		for index, item in ipairs(list) do
			local row = self.rows[index]
			seen[item.lower] = true
			local timing = self.timing[item.lower]
			if item.seconds then
				-- A new cooldown (first sighting, or the time went back up): its length is what
				-- the bar reports now.
				if not timing or item.seconds > timing.last then
					timing = { total = math.max(1, item.seconds) }
					self.timing[item.lower] = timing
				end
				timing.last = item.seconds
			end
			local soon = item.left and item.left <= SOON
			local icon = self:icon_for(item)
			set(row, "v_icon", icon or 0, function(v) ui.icon(row.icon, v); ui.content(row.icon, icon ~= nil) end)
			set(row, "v_name", self:fit(item.name), function(v) ui.text(row.name, v) end)
			set(row, "v_name_color", COLORS.text, function(v) ui.text_color(row.name, v) end)
			set(row, "v_time", item.left and format_time(item.left) or item.text, function(v) ui.text(row.time, v) end)
			set(row, "v_time_color", soon and COLORS.soon or COLORS.time, function(v) ui.text_color(row.time, v) end)
			local share = (item.left and timing) and math.min(1, item.left / timing.total) or 0
			local pixels = math.floor((WIDTH - 2) * share + 0.5)
			set(row, "v_fill", pixels > 0 and (soon and BARS.soon or BARS.normal) or "",
				function(v) ui.fill_color(row.bar, v) end)
			set(row, "v_width", math.max(1, pixels), function(v) ui.size(row.bar, v, 21) end)
		end
		for name in pairs(self.timing) do
			if not seen[name] then self.timing[name] = nil end -- finished: next use starts fresh
		end
		ui.text(self.title, #list > 0 and ("Cooldowns  ·  " .. #list) or "Cooldowns")
	end

	-- Polls the relay while the window is open (bars drain smoothly between updates).
	function Window:animate()
		local last = 0
		ui.on_update(function(now)
			if not self.visible then ui.stop_updates() return end
			if now - last >= POLL_MS then
				last = now
				self:present(now)
			end
		end)
	end

	return Window
end)
