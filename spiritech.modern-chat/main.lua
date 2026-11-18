-- Modern Chat content (role prk.chat): flat log and input line; lines are composed
-- by presentation.lua. Behaviour (sending, channels, links, scrolling) is the game's.
local Presentation = ui.require("chat.presentation")
local content = ui.load("content.xml")
local entry = ui.find(content, "chat_entry")
local target = ui.find(content, "chat_target")
ui.root(content)

function chat_present(messages)
	for _, message in ipairs(messages) do
		Presentation.line(message)
	end
end

function chat_output(name, color)
	local tint = color ~= "" and color or "#F2EEB0"
	ui.text(target, name ~= "" and name or "Vicinity")
	ui.text_color(target, tint)
	ui.text_color(ui.find(content, "chat_input"), tint)
end

function chat_visual(borderless)
	ui.chat.borders(not borderless)
end

function chat_state(show_entry, show_target)
	ui.visible(entry, show_entry)
	ui.visible(target, show_target)
end
