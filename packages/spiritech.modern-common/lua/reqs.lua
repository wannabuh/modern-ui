-- Item requirements, weapon damage and implant modifiers by item name + QL.
-- Shared by Modern Inventory and Modern Trade. Load with:
--   local Reqs = ui.require("spiritech.modern-common/reqs")
-- Data: spiritech.modern-common/lua/itemreqs_<letter>.lua, generated from the client's item
-- database by spiritech.modern-common/tools/gen_itemreqs.py (re-run after game updates).
-- Lookup is by item name + QL: the database has a few QL points per item, and requirements
-- in between are interpolated linearly (as the game does). Each requirement is checked
-- against your current (effective) stats, so unmet ones can be shown in red.
local Reqs = {}

-- Short display names for AO stat IDs (unknown IDs are simply not shown).
local NAMES = {
	[16] = "Str", [17] = "Agi", [18] = "Sta", [19] = "Int", [20] = "Sen", [21] = "Psy",
	[54] = "Level", [37] = "Title lvl",
	[100] = "Martial Arts", [101] = "Multi Melee", [102] = "1h Blunt", [103] = "1h Edged",
	[104] = "Melee Energy", [105] = "2h Edged", [106] = "Piercing", [107] = "2h Blunt",
	[108] = "Sharp Obj", [109] = "Grenade", [110] = "Heavy Weap", [111] = "Bow", [112] = "Pistol",
	[113] = "Rifle", [114] = "MG/SMG", [115] = "Shotgun", [116] = "Assault Rifle",
	[117] = "Vehicle Water", [118] = "Melee Init", [119] = "Ranged Init", [120] = "Physical Init",
	[121] = "Bow Special", [122] = "Sensory Impr", [123] = "First Aid", [124] = "Treatment",
	[125] = "Mech Eng", [126] = "Elec Eng", [127] = "Matter Meta", [128] = "Bio Meta",
	[129] = "Psycho Modi", [130] = "Matter Crea", [131] = "Time&Space", [132] = "Nano Pool",
	[133] = "Ranged Energy", [134] = "Multi Ranged", [135] = "Trap Disarm", [136] = "Perception",
	[137] = "Adventuring", [138] = "Swimming", [139] = "Vehicle Air", [140] = "Map Nav",
	[141] = "Tutoring", [142] = "Brawl", [143] = "Riposte", [144] = "Dimach", [145] = "Parry",
	[146] = "Sneak Attack", [147] = "Fast Attack", [148] = "Burst", [149] = "Nano Init",
	[150] = "Fling Shot", [151] = "Aimed Shot", [152] = "Body Dev", [153] = "Duck-Exp",
	[154] = "Dodge-Rng", [155] = "Evade-ClsC", [156] = "Run Speed", [157] = "Quantum FT",
	[158] = "Weapon Smith", [159] = "Pharma Tech", [160] = "Nano Prog", [161] = "Comp Lit",
	[162] = "Psychology", [163] = "Chemistry", [164] = "Concealment", [165] = "Break&Entry",
	[166] = "Vehicle Grnd", [167] = "Full Auto", [168] = "Nano Resist",
}
local PROFESSIONS = {
	[1] = "Soldier", [2] = "Martial Artist", [3] = "Engineer", [4] = "Fixer", [5] = "Agent",
	[6] = "Adventurer", [7] = "Trader", [8] = "Bureaucrat", [9] = "Enforcer", [10] = "Doctor",
	[11] = "Nano-Technician", [12] = "Meta-Physicist", [14] = "Keeper", [15] = "Shade",
}
Reqs.MAX_SHOWN = 3

local buckets = {} -- letter -> table (or false when missing)
local cache = {} -- name|ql -> requirement list
local my_profession

if game and game.character and game.character.subscribe then
	pcall(game.character.subscribe, "self", "", function(_, me)
		if me and me.profession then my_profession = PROFESSIONS[me.profession] end
	end)
end

local function bucket_for(name)
	local first = string.lower(name:sub(1, 1))
	local key = first:match("%l") and first or "other"
	if buckets[key] == nil then
		local ok, data = pcall(ui.require, "spiritech.modern-common/itemreqs_" .. key)
		buckets[key] = ok and type(data) == "table" and data or false
	end
	return buckets[key] or nil
end

local function parse(point)
	local nums = {}
	for stat, value in point[2]:gmatch("(%d+):(-?%d+)") do nums[tonumber(stat)] = tonumber(value) end
	return nums
end

-- { {stat=, need=, label=} ..., professions = "Doctor/Adventurer" } for an item, or nil.
local function lookup(name, ql)
	local key = name .. "|" .. tostring(ql)
	if cache[key] ~= nil then return cache[key] or nil end
	local data = bucket_for(name)
	local points = data and data[name]
	if not points then cache[key] = false return nil end
	local low, high
	for _, point in ipairs(points) do
		if point[1] <= ql then low = point end
		if point[1] >= ql and not high then high = point end
	end
	low, high = low or high, high or low
	local nums, a, b = {}, parse(low), parse(high)
	for stat, value in pairs(a) do
		local other = b[stat]
		if other and high[1] ~= low[1] then
			value = value + (other - value) * (ql - low[1]) / (high[1] - low[1])
		end
		nums[stat] = math.floor(value + 0.5)
	end
	local list = {}
	for stat, need in pairs(nums) do
		if NAMES[stat] then list[#list + 1] = { stat = stat, need = need, label = NAMES[stat] } end
	end
	table.sort(list, function(x, y)
		if (x.stat == 54) ~= (y.stat == 54) then return x.stat == 54 end -- level first
		return x.need > y.need
	end)
	list.professions = low[3] ~= "" and low[3] or nil
	-- Weapon damage "min:max:crit:type", interpolated like the requirements.
	local function damage(point)
		local values = {}
		for value in (point[4] or ""):gmatch("%d+") do values[#values + 1] = tonumber(value) end
		return #values >= 3 and values or nil
	end
	local dl, dh = damage(low), damage(high)
	if dl then
		dh = dh or dl
		local t = (high[1] ~= low[1]) and (ql - low[1]) / (high[1] - low[1]) or 0
		local function mix(i) return math.floor(dl[i] + (dh[i] - dl[i]) * t + 0.5) end
		list.damage = { min = mix(1), max = mix(2), crit = mix(3), type = dl[4] }
	end
	cache[key] = list
	return list
end

local function current(stat)
	if not (game and game.character and game.character.stat) then return nil end
	local ok, value = pcall(game.character.stat, "self", stat, "effective")
	return ok and value or nil
end

local DAMAGE_TYPES = { [90] = "proj", [91] = "melee", [92] = "energy", [93] = "chem",
	[94] = "rad", [95] = "cold", [96] = "poison", [97] = "fire" }

-- Weapon damage text, e.g. "19–146 (67) proj", or nil for non-weapons.
function Reqs.damage(name, ql)
	local list = lookup(name, ql or 1)
	local d = list and list.damage
	if not d then return nil end
	local text = d.min .. "–" .. d.max .. " (" .. d.crit .. ")"
	if DAMAGE_TYPES[d.type] then text = text .. " " .. DAMAGE_TYPES[d.type] end
	return text
end

-- Display parts for an item: { {text=, met=true/false/nil}, ... } (at most MAX_SHOWN skills).
function Reqs.parts(name, ql)
	local list = lookup(name, ql or 1)
	if not list then return nil end
	local parts = {}
	if list.professions then
		local profs = list.professions
		local met = nil
		if my_profession then met = ("/" .. profs .. "/"):find("/" .. my_profession .. "/", 1, true) ~= nil end
		local count = select(2, profs:gsub("/", "")) + 1
		parts[#parts + 1] = { text = count > 2 and (count .. " professions") or profs, met = met,
			tooltip = profs }
	end
	for index, req in ipairs(list) do
		if index > Reqs.MAX_SHOWN then break end
		local have, met = current(req.stat), nil
		if have ~= nil then met = have >= req.need end -- nil = unknown (shown neutral)
		parts[#parts + 1] = { text = req.label .. " " .. req.need, met = met }
	end
	return parts
end

-- ------------------------------------------------------------ implant modifiers
-- Data: spiritech.modern-common/lua/itemmods.lua (tools/gen_itemmods.py), one module on
-- purpose: a package may register at most 64 modules in total.
-- Implants and symbiants only. A cluster implant's name only reveals its named cluster
-- ("Eye Implant: Rifle, Shiny" covers every bright/faded combination), so `more` marks
-- names where further clusters may be present but can't be told apart.
local MOD_NAMES = setmetatable({
	[1] = "Max Health", [181] = "Max NCU", [221] = "Max Nano",
	[90] = "Proj AC", [91] = "Melee AC", [92] = "Energy AC", [93] = "Chem AC",
	[94] = "Rad AC", [95] = "Cold AC", [96] = "Poison AC", [97] = "Fire AC",
	[205] = "Reflect Proj", [206] = "Reflect Melee", [207] = "Reflect Energy",
	[208] = "Reflect Chem", [216] = "Reflect Rad", [217] = "Reflect Cold",
	[219] = "Reflect Fire", [225] = "Reflect Poison",
	[226] = "Shield Proj", [227] = "Shield Melee", [228] = "Shield Energy",
	[229] = "Shield Chem", [230] = "Shield Rad", [231] = "Shield Cold",
	[233] = "Shield Fire", [234] = "Shield Poison",
	[276] = "Add All Off", [277] = "Add All Def",
	[278] = "Proj Dmg", [279] = "Melee Dmg", [280] = "Energy Dmg", [281] = "Chem Dmg",
	[282] = "Rad Dmg", [311] = "Cold Dmg", [316] = "Fire Dmg", [317] = "Poison Dmg",
	[318] = "Nano Cost %", [319] = "XP %", [343] = "Heal Delta", [364] = "Nano Delta",
	[380] = "Range Weap", [381] = "Range NF", [382] = "Skill Lock", [383] = "Nano Interrupt",
}, { __index = NAMES })

local mod_data, mod_cache = nil, {}

local function mod_bucket()
	if mod_data == nil then
		local ok, data = pcall(ui.require, "spiritech.modern-common/itemmods")
		mod_data = ok and type(data) == "table" and data or false
	end
	return mod_data or nil
end

-- { {stat=, amount=}, ... (biggest first), more = bool } for an implant at a QL, or nil.
local function mods_of(name, ql)
	local key = name .. "|" .. tostring(ql)
	if mod_cache[key] ~= nil then return mod_cache[key] or nil end
	local data = mod_bucket(name)
	local points = data and data[name]
	if not points or #points == 0 then mod_cache[key] = false return nil end
	local low, high
	for _, point in ipairs(points) do
		if point[1] <= ql then low = point end
		if point[1] >= ql and not high then high = point end
	end
	low, high = low or high, high or low
	local a, b = parse(low), parse(high)
	local t = high[1] ~= low[1] and (ql - low[1]) / (high[1] - low[1]) or 0
	local list = { more = points.more == true }
	for stat, value in pairs(a) do
		local other = b[stat] or value
		list[#list + 1] = { stat = stat, amount = math.floor(value + (other - value) * t + 0.5) }
	end
	table.sort(list, function(x, y)
		if x.amount ~= y.amount then return x.amount > y.amount end
		return x.stat < y.stat
	end)
	mod_cache[key] = list
	return list
end

-- Display parts for an implant's modifiers: { {text=, negative=bool}, ..., {text="+?", unknown=true} }
-- or nil when the item isn't an implant/symbiant.
function Reqs.mods(name, ql)
	local list = mods_of(name, ql or 1)
	if not list then return nil end
	local parts = {}
	for _, mod in ipairs(list) do
		local label = MOD_NAMES[mod.stat]
		if label then
			parts[#parts + 1] = { text = string.format("%s %+d", label, mod.amount), negative = mod.amount < 0 }
		end
	end
	if list.more then parts[#parts + 1] = { text = "+?", unknown = true } end
	return #parts > 0 and parts or nil
end

return Reqs
