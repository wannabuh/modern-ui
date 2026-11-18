-- Modern Chat line formatting (role prk.chat).
-- The game decides which messages each window gets (your chat configuration) and keeps
-- the message text, links and names; this only composes the line around them:
--   12:01  [OOC] Leet: anyone for Inferno?        dim timestamp, softer channel colours
--   ◄ Doccy: on my way    /    ► Wannama: ty      tells received / sent
--   ▌12:03  Leet: Wannama, inc!                   a line mentioning your name: amber marker
-- Custom colours set in Chat options still take priority.
ui.define("chat.presentation", function()
	local Presentation = {}
	local colors = {
		system = "#E6D36A",
		vicinity = "#F2EEB0",
		shout = "#F2C46B",
		emote = "#E58AC9",
		channel = "#E8ECF1",
		team = "#7FDC9A",
		tell = "#6FD3E0",
		sent_tell = "#8FB8F0",
		["local"] = "#8B95A3",
	}
	local TIME, MENTION = "#6E7885", "#F0C060"
	local separators = { emote = " ", shout = " shouts: " }

	-- Your character's name, for mention highlighting.
	local my_name
	if game and game.character and game.character.subscribe then
		pcall(game.character.subscribe, "self", "", function(_, me)
			if me and me.name and me.name ~= "" then my_name = string.lower(me.name) end
		end)
	end

	local function mentions_me(message)
		if not my_name or message.sent then return false end
		if string.lower(message.sender or "") == my_name then return false end
		local body = " " .. string.lower(message.body or "") .. " "
		local start = 1
		while true do
			local first, last = body:find(my_name, start, true)
			if not first then return false end
			-- whole word only ("Wannama" in "Wannama!" yes, in "Wannamax" no)
			local before, after = body:sub(first - 1, first - 1), body:sub(last + 1, last + 1)
			if not before:match("%w") and not after:match("%w") then return true end
			start = last + 1
		end
	end

	local function text(line, value, color)
		ui.chat.text(line, value, color or "", false)
	end

	local function color_of(message)
		if message.color ~= "" then return message.color end -- your own colour from Chat options
		if message.sent then return colors.sent_tell end
		return colors[message.kind] or colors.channel
	end

	function Presentation.line(message)
		local line = message.line
		local mention = mentions_me(message)
		ui.chat.style(line, color_of(message), message.font_size, false)
		ui.chat.font_family(line, message.font_family)
		if mention then text(line, "▌", MENTION) end
		if message.time ~= "" then
			text(line, message.time .. "  ", mention and MENTION or TIME)
		end
		if not message.structured then
			ui.chat.part(line, "message")
		else
			if message.channel ~= "" then
				ui.chat.channel(line, "[" .. message.channel .. "]")
				text(line, " ")
			end
			if message.kind == "tell" then
				text(line, message.sent and "► " or "◄ ")
				ui.chat.part(line, "sender")
				text(line, ": ")
			elseif message.sender ~= "" then
				ui.chat.part(line, "sender")
				text(line, separators[message.kind] or ": ")
			end
			ui.chat.part(line, "body")
		end
		ui.chat.commit(line)
	end

	return Presentation
end)
