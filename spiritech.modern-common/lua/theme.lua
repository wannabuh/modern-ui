-- Shared palette and formatting for the Modern UI packages.
-- Load with: local Theme = ui.require("spiritech.modern-common/theme")
local M = {}

M.WINDOW_TEMPLATE = "library://spiritech.modern-common/window.xml"

M.color = {
	text = "#E8ECF1", -- primary values
	label = "#8B95A3", -- secondary labels
	muted = "#5E6875", -- captions / section headers
	accent = "#4FB3BF",
	track = "#1B2028", -- empty bar
	stripe = "#0AFFFFFF", -- zebra row tint
}

-- Flat bar fills. Slightly desaturated so white text stays readable on top.
M.bar = {
	health = "#A33434",
	nano = "#2A62A8",
	xp = "#8C6520",
	alien = "#2F6E45",
	duel = "#7652B0",
	solo = "#7652B0",
	team = "#7652B0",
}

-- 1234567 -> "1,234,567"
function M.thousands(value)
	local text = tostring(math.floor(value))
	local sign, digits = text:match("^(-?)(%d+)$")
	if not digits then
		return text
	end
	digits = digits:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
	return sign .. digits
end

-- Format a native StatsBar / StatusReading as "1,121 / 1,121".
function M.reading(reading)
	local current = reading.current_known ~= false and reading.current ~= nil and M.thousands(reading.current) or "--"
	local maximum = reading.maximum_known ~= false and reading.maximum ~= nil and M.thousands(reading.maximum) or "--"
	return current .. " / " .. maximum
end

return M
