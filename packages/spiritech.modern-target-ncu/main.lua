-- Modern Target NCU (role prk.target-ncu): the nano programs running on your nano target or
-- fight target (one instance each; the game names them through target_ncu_configure), in
-- the Modern NCU style: two-line rows (icon | name / "NCU cost · time left"), red names and
-- bars for hostile programs, a faint bar for the time left. Read-only: nothing to cancel;
-- inspecting stays native. Title: "<window name>  ·  <count>".
-- Title menu: Hostile only (debuffs and other hostile programs; remembered per window, and
-- the game's default for that window when never set), then the sorts as in Modern NCU.
pcall(ui.require, "spiritech.modern-common/screenfit") -- keep window positions through fullscreen changes
local Window = ui.require("core.window")
local Theme = ui.require("spiritech.modern-common/theme")
local NcuList = ui.require("spiritech.modern-common/ncu_list")

local WIDTH = 240
local HOSTILE_ITEM = 1

local stored = ui.preference.read("modern_target_ncu_hostile") or ""
stored = stored:gsub('^"(.*)"$', "%1")
local hostile_only = stored == "true"
local title = "Target NCU"
local snapshot = {}

local list = NcuList.create({
	target = true,
	sort_preference = "modern_target_ncu_sort",
	table_preference = "modern_target_ncu_list",
	empty = "No nano programs on the target",
})

local frame
local function apply()
	local entries, hidden = {}, 0
	for _, entry in ipairs(snapshot) do
		if not entry.hidden then
			if hostile_only and not entry.hostile then
				hidden = hidden + 1
			else
				entries[#entries + 1] = entry
			end
		end
	end
	list:set(entries)
	local text = title .. "  ·  " .. #entries
	if hidden > 0 then text = text .. " (+" .. hidden .. ")" end
	ui.text(ui.find(frame.root, "window_title"), text)
	ui.tooltip(ui.find(frame.root, "window_title"), hidden > 0 and (hidden .. " friendly programs hidden (Hostile only)") or "")
	frame:resize(ui.chosen_width(frame.root), ui.chosen_height(frame.root))
end

local menu = {
	{
		label = "Hostile only",
		checked = hostile_only,
		invoke = function()
			if ui.in_combat() then return end
			hostile_only = not hostile_only
			ui.preference.write("modern_target_ncu_hostile", tostring(hostile_only), "bool")
			ui.menu.checked(frame.icon, HOSTILE_ITEM, hostile_only)
			ui.publish("hostile_only", tostring(hostile_only))
			apply()
		end,
	},
}
for _, item in ipairs(list:menu_items(#menu + 1)) do menu[#menu + 1] = item end

frame = Window.create({
	menu = menu,
	template = Theme.WINDOW_TEMPLATE,
	title = title,
	content = list.content,
	x = 10,
	y = 320,
	width = WIDTH,
	height = Window.CONTENT_ENDS or 33,
	layout = function(window, width)
		list:layout(window, width)
	end,
})
ui.root(frame.root)
list:attach(frame)

function target_ncu_configure(window_title, hostile_default)
	title = (window_title ~= nil and window_title ~= "") and window_title or title
	if stored == "" and hostile_default ~= nil then
		hostile_only = hostile_default == true
		ui.menu.checked(frame.icon, HOSTILE_ITEM, hostile_only)
	end
	ui.text(ui.find(frame.root, "window_title"), title)
	apply()
end

function target_ncu_apply(effects)
	snapshot = effects or {}
	apply()
end
