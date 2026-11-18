-- Centre snapping for the bottom-centre stack.
-- The built-in snapping (Options -> Interface & HUD -> Windows and HUD -> Magnetism / Spacing)
-- lines windows up edge to edge with an even gap, but never on the screen's centre line.
-- Centre.attach(view) adds that: while dragging, a view whose middle comes within the
-- magnetism distance of the screen's middle snaps exactly onto it. Vertical snapping
-- (even gaps between stacked pieces) is left to the built-in rules.
--
-- Load with: ui.require("spiritech.modern-common/centre").attach(view)
local Move = ui.require("core.move")

local M = {}
local centred = {}

-- Reach used when the player has magnetism switched off (0): centre snapping still works.
local FALLBACK_REACH = 10

if not Move.spiritech_centre_drag then
	local drag = Move.drag
	Move.spiritech_centre_drag = drag
	Move.drag = function(view, x, y, bounded)
		local next_x, next_y = drag(view, x, y, bounded)
		if centred[view] then
			local parent_width = ui.parent_width(view)
			local middle = (parent_width - ui.width(view)) / 2
			local reach = ui.movable_geometry.magnetism()
			if reach <= 0 then reach = FALLBACK_REACH end
			if parent_width > 0 and math.abs(x - middle) <= reach then
				next_x, next_y = Move.place(view, middle, next_y, bounded)
			end
		end
		return next_x, next_y
	end
end

function M.attach(view)
	centred[view] = true
	return view
end

return M
