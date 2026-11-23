-- Keeps window positions through screen-size changes (leaving / returning to fullscreen).
-- Load once per package, as early as possible (before windows are created):
--   pcall(ui.require, "spiritech.modern-common/screenfit")
--
-- Core's placement remembers where you put a window ("intended") apart from where it is
-- shown (clamped onto a smaller screen). Two problems when the screen size changes:
--   1. A capture runs and can read the squeezed position back as the new intended one.
--      -> when the parent's size changed since the last capture, keep the intended pos/size.
--   2. When the screen grows again nothing re-places the window, so it stays squeezed
--      (seen in-game 2026-11-17: saved positions were right, windows drawn squeezed).
--      -> a watcher checks the screen size 4x a second and re-places every window from its
--      intended position when it changed. It shares the package's single ui.on_update
--      observer: ui.on_update / ui.stop_updates are wrapped so the package's own animation
--      callback still works exactly as before.
-- Storage key "screenfit_log" (in each package's own storage) keeps the last few events.
local Placement = ui.require("core.placement")
if Placement.screenfit_patched then return true end
Placement.screenfit_patched = true

local known = setmetatable({}, { __mode = "k" }) -- every Placement seen in this package

-- Packages with several instances (every hotbar is its own VM) share one storage, so each
-- line is tagged with this VM and appended to what the others wrote.
local vm_tag = (tostring({}):match("0x(%x+)") or "?"):sub(-4)
local function log(text)
	local ok, current = pcall(ui.storage.read, "screenfit_log")
	local lines = {}
	for line in ((ok and current) or ""):gmatch("[^\n]+") do lines[#lines + 1] = line end
	lines[#lines + 1] = string.format("%d %s %s", ui.time() // 1000 % 100000, vm_tag, text)
	while #lines > 24 do table.remove(lines, 1) end
	pcall(ui.storage.write, "screenfit_log", table.concat(lines, "\n"))
end

local function rect(intended)
	if not intended then return "-" end
	return string.format("%.0f,%.0f %.0fx%.0f", intended.x, intended.y, intended.width or 0, intended.height or 0)
end

-- ---------------------------------------------------------------- 1. capture
local capture, place = Placement.capture, Placement.place

local function before(self)
	known[self] = true
	local width, height = ui.parent_width(self.view), ui.parent_height(self.view)
	local resized = self.parent_width ~= nil and width > 0 and height > 0
		and (width ~= self.parent_width or height ~= self.parent_height)
	if resized then
		log(string.format("capture: screen %sx%s -> %sx%s, keep %s", self.parent_width, self.parent_height,
			width, height, rect(self.intended)))
	end
	if width > 0 and height > 0 then self.parent_width, self.parent_height = width, height end
	local keep = resized and self.intended and {
		x = self.intended.x, y = self.intended.y, width = self.intended.width, height = self.intended.height,
	} or nil
	if keep and self.options.resize and keep.width and keep.height and keep.width > 0 and keep.height > 0 then
		self.options.resize(keep.width, keep.height)
	end
	return keep
end

local function after(self, keep)
	if not (keep and self.intended) or (self.options.embedded and self.options.embedded()) then return end
	local intended = self.intended
	intended.x, intended.y = keep.x, keep.y
	if keep.width and keep.width > 0 then intended.width, intended.height = keep.width, keep.height end
	self:place()
	self:write(self.options.field or "WindowFrame", table.concat({ intended.x, intended.y,
		intended.x + intended.width, intended.y + intended.height }, ","), "rect")
end

-- Core decides "the player moved it" when the current position differs AT ALL from where it
-- last placed the window. With a fractional screen size (UI scaling: 1255.66 x 676.51 seen
-- in-game) the engine snaps the squeezed position to whole pixels, so 879 vs 879.34 counted
-- as a move and the squeezed spot replaced the real one. Sub-pixel differences are noise:
-- snap Core's record to the actual position so they never count. Real drags move further.
local NOISE = 1.5
local function coordinate(view, horizontal)
	local alignment = horizontal and ui.horizontal_alignment(view) or ui.vertical_alignment(view)
	if alignment == "start" then
		return horizontal and ui.offset_x(view) or ui.offset_y(view)
	end
	return horizontal and ui.local_x(view) or ui.local_y(view)
end

local function ignore_rounding(self)
	if not (self.intended and self.display_x and self.display_y) then return end
	local x, y = coordinate(self.view, true), coordinate(self.view, false)
	if math.abs(x - self.display_x) <= NOISE and math.abs(y - self.display_y) <= NOISE then
		self.display_x, self.display_y = x, y
	end
end

-- Any error in the extra steps only skips them; Core's own capture always runs.
function Placement:capture()
	local ok, keep = pcall(before, self)
	pcall(ignore_rounding, self)
	capture(self)
	if ok and keep then pcall(after, self, keep) end
end

function Placement:place()
	known[self] = true
	local result = place(self)
	-- Remember the last squeezed spot, so a late echo of it from the game (after the screen
	-- has grown back) is not taken as a move either.
	local intended = self.intended
	if intended and self.display_x and (math.abs(self.display_x - intended.x) > NOISE
		or math.abs(self.display_y - intended.y) > NOISE) then
		self.squeezed_x, self.squeezed_y = self.display_x, self.display_y
	end
	return result
end

-- ---------------------------------------------------------------- 1b. game placement requests
-- Hotbars are placed by the game (ui.on_placement_request), and Core takes every request as
-- the new intended position. When the screen shrinks the game asks for the squeezed spot,
-- which then replaced the real one, so the bars stayed squeezed back in fullscreen.
-- A request that only repeats where the window already is, or the squeezed version of its
-- intended spot, is not a real move: keep the intended position and just re-place.
local by_view = {}
local attach = Placement.attach
function Placement.attach(view, options)
	local self = attach(view, options)
	by_view[view] = self
	known[self] = true
	return self
end

local function extent(view, horizontal, fallback)
	local chosen = horizontal and ui.chosen_width(view) or ui.chosen_height(view)
	if chosen > 0 then return chosen end
	local minimum = horizontal and ui.minimum_width(view) or ui.minimum_height(view)
	return minimum > 0 and minimum or fallback or 0
end

local function near(ax, ay, bx, by)
	return ax and bx and math.abs(ax - bx) <= NOISE and math.abs(ay - by) <= NOISE
end

local function squeezed(self, x, y)
	local intended = self and self.intended
	if not intended or (self.options.embedded and self.options.embedded()) then return false end
	local view = self.view
	local parent_width, parent_height = ui.parent_width(view), ui.parent_height(view)
	local cx, cy = intended.x, intended.y
	if parent_width > 0 then cx = math.max(0, math.min(cx, parent_width - extent(view, true, intended.width))) end
	if parent_height > 0 then cy = math.max(0, math.min(cy, parent_height - extent(view, false, intended.height))) end
	return near(x, y, cx, cy) or near(x, y, self.display_x, self.display_y)
		or near(x, y, self.squeezed_x, self.squeezed_y)
end

local request = ui.on_placement_request
pcall(function()
	ui.on_placement_request = function(view, callback)
		return request(view, function(x, y)
			local self = by_view[view]
			local ok, keep = pcall(squeezed, self, x, y)
			if ok and keep then
				if not near(x, y, self.intended.x, self.intended.y) then
					log(string.format("request %.0f,%.0f ignored, keep %s", x, y, rect(self.intended)))
				end
				return self:place()
			end
			log(string.format("request %.0f,%.0f applied (was %s)", x, y, rect(self and self.intended)))
			return callback(x, y)
		end)
	end
end)

-- ---------------------------------------------------------------- 2. watcher
local last_check, screen_width, screen_height = 0, nil, nil

local function watch(now)
	if now - last_check < 250 then return end
	last_check = now
	local count, width, height = 0, nil, nil
	for placement in pairs(known) do
		width, height = ui.parent_width(placement.view), ui.parent_height(placement.view)
		if width > 0 and height > 0 and (placement.seen_width ~= width or placement.seen_height ~= height) then
			local first = placement.seen_width == nil
			placement.seen_width, placement.seen_height = width, height
			if not first and placement.intended and not (placement.options.embedded and placement.options.embedded()) then
				placement:place()
				count = count + 1
			end
		end
	end
	if count > 0 then
		log(string.format("screen %sx%s -> %sx%s: re-placed %d", screen_width, screen_height, width, height, count))
	end
	if width then screen_width, screen_height = width, height end
end

local package_update -- the package's own ui.on_update callback, if any
local on_update = ui.on_update

local function tick(now)
	pcall(watch, now)
	if package_update then return package_update(now) end
end

local wrapped = pcall(function()
	ui.on_update = function(callback)
		package_update = callback
		on_update(tick)
	end
	ui.stop_updates = function()
		package_update = nil -- keep watching the screen
	end
end)
if wrapped then
	on_update(tick)
	log("watching (package update hook shared)")
else
	log("could not share ui.on_update: screen watcher off")
end

return true
