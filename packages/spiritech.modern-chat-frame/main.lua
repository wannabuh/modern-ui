-- Modern Chat Frame: flat chat windows (role prk.chat-frame; one instance per chat window).
-- Same behaviour as the built-in frame (docking groups, tabs, borderless / transparency /
-- click-through from Chat options, saved bounds); restyled with the shared flat frame and
-- flat text tabs (teal underline on the selected one). Which messages a window shows is
-- decided by the game from your chat configuration, so custom windows work unchanged.
pcall(ui.require, "spiritech.modern-common/screenfit") -- keep window positions through fullscreen changes
local Window = ui.require("core.window")
local content = ui.load("host.xml")
local borderless = false
local tabbed = false
local title_height = 24
local frame = Window.create({
	template = "frame.xml",
	content = content,
	keep_open_on_unavailable = true,
	width = 680,
	height = 240,
	layout = function(window, width, height)
		ui.request_size(window.root, width, height)
		width, height = ui.chosen_width(window.root), ui.chosen_height(window.root)
		window:fit_title(width, not tabbed)
		window:fit_content(width, height + (borderless and title_height or 0))
	end,
})
ui.root(frame.root)
local pane_visible
frame.placement.options.visibility_value = function()
	if pane_visible ~= nil then return pane_visible end
	return ui.requested_visible(frame.root)
end

function chat_frame_pane_visibility(visible)
	pane_visible = visible
end

local host = ui.find(frame.root, "window_tabs")
local measure = ui.find(ui.load("measure.xml"), "chat_frame_measure")
ui.add(content, measure)
local rows = {}
local SELECTED, IDLE = "#E8ECF1", "#8B95A3"

function chat_frame_setup(setup)
	ui.text(ui.find(frame.root, "window_title"), setup.title)
	ui.visible(frame.pin, setup.pin)
	ui.limits(frame.root, setup.minimum_width, setup.minimum_height, setup.maximum_width, setup.maximum_height)
	ui.align(frame.root, setup.horizontal, setup.vertical)
	ui.borders(frame.root, setup.left, setup.top, setup.right, setup.bottom)
	frame:resize(setup.width, setup.height)
end

local function paint(row, selected)
	ui.text_color(row.label, selected and SELECTED or IDLE)
	ui.visible(row.line, selected)
	ui.selected(row.label, selected)
end

function chat_frame_tabs(entries)
	for _, row in ipairs(rows) do
		ui.destroy(row.root)
	end
	rows = {}
	tabbed = #entries > 1
	ui.visible(frame.title, not tabbed)
	if #entries == 1 then
		ui.text(ui.find(frame.root, "window_title"), entries[1].name)
	end
	if #entries <= 1 then
		return
	end
	for _, entry in ipairs(entries) do
		local loaded = ui.load("tab.xml")
		ui.add(host, loaded)
		local root = ui.find(loaded, "chat_frame_tab") or loaded
		local label = ui.find(root, "chat_frame_tab_label")
		local row = { root = root, label = label, line = ui.find(root, "chat_frame_tab_line"), identity = entry.identity }
		ui.text(label, entry.name)
		ui.text(measure, entry.name)
		local ok, width = pcall(ui.text_width, measure)
		width = (ok and width and width > 0) and math.ceil(width) or #entry.name * 7
		ui.limits(root, width, 17, width, 17)
		ui.size(root, width, 17)
		ui.bind(label, entry.token) -- native tab binding (drag a tab between windows)
		paint(row, entry.selected)
		rows[#rows + 1] = row
		ui.on_click(label, function()
			if ui.chat_frame.select(entry.identity) then
				for _, other in ipairs(rows) do
					paint(other, other.identity == entry.identity)
				end
			end
		end)
	end
end

function chat_frame_visual(hidden, alpha, clickthrough)
	borderless = hidden
	ui.opacity(frame.root, alpha)
	ui.click_through(frame.root, clickthrough)
	ui.fill_color(frame.root, hidden and "#000000" or "")
	ui.visible(ui.find(frame.root, "window_outer"), not hidden)
	ui.visible(ui.find(frame.root, "window_inner"), not hidden)
	ui.visible(ui.find(frame.root, "window_titlebar"), not hidden)
	frame:resize(ui.chosen_width(frame.root), ui.chosen_height(frame.root))
end
