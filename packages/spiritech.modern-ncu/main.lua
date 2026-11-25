-- Modern NCU: slim list of your running nano programs (role prk.ncu).
-- Two-line rows (icon | name / "NCU cost · time left"), drawn by the shared list in
-- spiritech.modern-common/ncu_list (also used by Modern Target NCU). No header; the title
-- shows NCU used / maximum. Rows keep the built-in bindings, so right-click still cancels and
-- Shift-click still inspects (also in combat). Sort from the title menu ("i"): biggest NCU
-- users first (default: the programs worth cancelling to free space), or by time left
-- (soonest / longest first; permanent programs count as the longest). Saved in preference
-- modern_ncu_sort. In combat the game pins the row order, so a new sort shows after combat.
pcall(ui.require, "spiritech.modern-common/screenfit") -- keep window positions through fullscreen changes
local Window = ui.require("core.window")
local Theme = ui.require("spiritech.modern-common/theme")
local NcuList = ui.require("spiritech.modern-common/ncu_list")

local WIDTH = 270

local list = NcuList.create({
	action = "game.ncu.cancel",
	sort_preference = "modern_ncu_sort",
	table_preference = "modern_ncu_list",
	empty = "No nano programs running",
})

local frame = Window.create({
	menu = list:menu_items(1),
	template = Theme.WINDOW_TEMPLATE,
	title = "NCU --/--",
	content = list.content,
	x = 10,
	y = 174,
	width = WIDTH,
	height = Window.CONTENT_ENDS or 33,
	layout = function(window, width)
		list:layout(window, width)
	end,
})
ui.root(frame.root)
list:attach(frame)

function ncu_apply(snapshot, usage)
	local entries = {}
	for _, entry in ipairs(snapshot) do
		if not entry.hidden then
			entries[#entries + 1] = entry
		end
	end
	list:set(entries)
	if usage then
		local used = usage.used_known and tostring(usage.used) or "--"
		local maximum = usage.maximum_known and tostring(usage.maximum) or "--"
		ui.text(ui.find(frame.root, "window_title"), "NCU  " .. used .. " / " .. maximum)
	end
	frame:resize(ui.chosen_width(frame.root), ui.chosen_height(frame.root))
end
