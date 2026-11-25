NanoPresentation = {}
local presentation = NanoPresentation
presentation.maximum_extent = 16384

presentation.columns = {
	{ id = "icon", title = "", width = 16, minimum = 16 },
	{ id = "name", title = "Name", width = 200 },
	{ id = "nano_cost", title = "Nano Cost", width = 69 },
	{ id = "ncu_cost", title = "NCU Cost", width = 67 },
	{ id = "time", title = "Time", width = 61 },
	{ id = "radius", title = "Radius", width = 57 },
	{ id = "attack_range", title = "Atk Range", width = 71 },
	{ id = "attack_delay", title = "Atk Delay", width = 69 },
	{ id = "recharge_delay", title = "Rcg Delay", width = 69 },
	{ id = "nanoline", title = "NanoLine", width = 200 },
}

function presentation.text(entry, id)
	local value = entry[id]
	if id == "time" then
		if value <= 0 then
			return "---"
		end
		local seconds = math.floor(value / 100)
		return string.format("%02d:%02d:%02d", math.floor(seconds / 3600), math.floor(seconds / 60) % 60, seconds % 60)
	end
	if id == "radius" and value <= 0 then
		return "---"
	end
	if id == "radius" or id == "attack_range" then
		return tostring(value) .. "m"
	end
	if id == "attack_delay" or id == "recharge_delay" then
		return string.format("%.2fs", value / 100)
	end
	return tostring(value)
end

function presentation.matches(entry, terms)
	local name = string.lower(entry.name)
	for _, term in ipairs(terms) do
		if not string.find(name, term, 1, true) then
			return false
		end
	end
	return true
end

for _, column in ipairs(presentation.columns) do
	column.maximum = presentation.maximum_extent - 6
	if column.id == "icon" then
		column.kind = "icon"
		column.icon = function(entry)
			return entry.icon
		end
	else
		column.value = function(entry)
			local value = entry[column.id]
			return type(value) == "string" and string.lower(value) or value
		end
		column.text = function(entry)
			return presentation.text(entry, column.id)
		end
	end
end

function presentation.tie(left, right)
	local a, b = string.lower(left.name), string.lower(right.name)
	return a == b and 0 or a < b and -1 or 1
end

local function strongest_first(left, right)
	if left.stacking_order ~= right.stacking_order then
		return left.stacking_order > right.stacking_order and -1 or 1
	end
	if left.level ~= right.level then
		return left.level > right.level and -1 or 1
	end
	return presentation.tie(left, right)
end

for _, column in ipairs(presentation.columns) do
	if column.id == "nanoline" then
		column.tie = strongest_first
	end
end
