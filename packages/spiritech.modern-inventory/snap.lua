-- Snapping between the inventory window and its pop-out panels.
-- They live inside the package's full-screen container, which the game's own snapping can't
-- see, so this adds the same behaviour among them: while dragging, an edge within the
-- Magnetism distance (Options -> Interface & HUD -> Windows and HUD) snaps to another
-- piece's edge, either flush-aligned or with the configured Spacing gap.
ui.define("inventory.snap", function()
	local Move = ui.require("core.move")
	local Snap = {}
	local members = {} -- view -> true

	local function setting(name, fallback)
		local ok, value = pcall(function() return ui.movable_geometry[name]() end)
		return (ok and type(value) == "number") and value or fallback
	end

	local function overlaps(a, a_size, b, b_size, reach)
		return a <= b + b_size + reach and b <= a + a_size + reach
	end

	-- Best offset along one axis: start/size of the moving piece against a peer.
	local function axis(start, size, other, other_size, gap, best, distance)
		for _, offset in ipairs({
			other + other_size + gap - start, -- my leading edge after their trailing edge
			other - gap - (start + size),     -- my trailing edge before their leading edge
			other - start,                    -- leading edges aligned
			other + other_size - (start + size), -- trailing edges aligned
		}) do
			if math.abs(offset) < distance then best, distance = offset, math.abs(offset) end
		end
		return best, distance
	end

	local function offset(view, x, y)
		local reach = setting("magnetism", 0)
		if reach <= 0 then reach = 8 end -- still snap here when global magnetism is off
		local gap = setting("spacing", 3)
		local w, h = ui.width(view), ui.height(view)
		local dx, dy, best_x, best_y = 0, 0, reach + 0.5, reach + 0.5
		for peer in pairs(members) do
			if peer ~= view and ui.requested_visible(peer) then
				local px, py, pw, ph = ui.local_x(peer), ui.local_y(peer), ui.width(peer), ui.height(peer)
				if pw > 0 and ph > 0 then
					if overlaps(y, h, py, ph, gap + reach) then dx, best_x = axis(x, w, px, pw, gap, dx, best_x) end
					if overlaps(x, w, px, pw, gap + reach) then dy, best_y = axis(y, h, py, ph, gap, dy, best_y) end
				end
			end
		end
		return dx, dy
	end

	if not Move.inventory_snap_drag then
		local drag = Move.drag
		Move.inventory_snap_drag = drag
		Move.drag = function(view, x, y, bounded)
			if members[view] then
				local dx, dy = offset(view, x, y)
				if dx ~= 0 or dy ~= 0 then
					return Move.place(view, x + dx, y + dy, bounded)
				end
			end
			return drag(view, x, y, bounded)
		end
	end

	function Snap.add(view) members[view] = true end
	function Snap.remove(view) members[view] = nil end
	return Snap
end)
