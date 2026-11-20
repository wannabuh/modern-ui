-- Whompah route planning for the world map (global ROUTE, used by main.lua).
--
-- Positions are planned in global world coordinates: global = zone offset + local * scale,
-- with the current map's offsets (whompahs.lua, from the map's coords.xml). Rubi-Ka is one
-- continuous surface, so a walking leg is the straight distance between two points and no
-- zone outlines are needed.
--
-- Projection (global -> this map level's image pixels), measured in-game on Saavick's map:
-- every level stretches one fixed world rectangle over its MapRect,
--   map_x = left + (gx - X0) * (right - left) / (X1 - X0)
--   map_y = top  + (gz - Z0) * (bottom - top) / (Z1 - Z0)        (gz grows north, map y south)
-- That fit had 0.02 px error over four zones. Other maps start from the same rectangle and
-- are corrected live: main.lua reports where the game draws you (ROUTE.observe), which first
-- fixes the offset and, once you have moved far enough, the scale too.
ROUTE = {}

local X0, X1 = 31022.08, 49772.90
local Z0, Z1 = 48995.01, 24880.00
local WALK_SPEED = 10 -- world units (metres) per second, a running character
local HOP_SECONDS = 25 -- whompah animation + zoning
local SPREAD = 150 -- metres of movement along an axis before its scale is measured

local function seed(map, level)
	local info = WHOMPAH_MAPS and WHOMPAH_MAPS[map]
	local rect = info and info.rects and info.rects[level + 1]
	if not rect then return nil end
	local left, top, right, bottom = rect[1], rect[2], rect[3], rect[4]
	local sx, sy = (right - left) / (X1 - X0), (bottom - top) / (Z1 - Z0)
	return { sx = sx, ox = left - X0 * sx, sy = sy, oy = top - Z0 * sy }
end

-- Live calibration per map level: { sx, ox, sy, oy } plus the extreme samples seen.
local fitted = {}

local function key(map, level) return map .. "|" .. level end

local function projection(map, level)
	local fit = fitted[key(map, level)]
	if fit and fit.sx and fit.sy then return fit end
	return seed(map, level)
end

local function global(map, zone, lx, lz)
	local info = WHOMPAH_MAPS and WHOMPAH_MAPS[map]
	local offset = info and info.zones[zone]
	if not offset then return nil end
	return offset[1] + lx * offset[2], offset[3] + lz * offset[4]
end

function ROUTE.project(map, level, gx, gz)
	local p = projection(map, level)
	if not p then return nil end
	return p.sx * gx + p.ox, p.sy * gz + p.oy
end

function ROUTE.unproject(map, level, mx, my)
	local p = projection(map, level)
	if not p or p.sx == 0 or p.sy == 0 then return nil end
	return (mx - p.ox) / p.sx, (my - p.oy) / p.sy
end

-- One reading: you are in `zone` at local (lx, lz) and the game draws you at (mx, my).
-- Only zones with known offsets on this map count (whompah zones).
function ROUTE.observe(map, level, zone, lx, lz, mx, my)
	local gx, gz = global(map, zone, lx, lz)
	if not gx then return end
	local k = key(map, level)
	local fit = fitted[k]
	if not fit then
		local s = seed(map, level)
		fit = { seed_sx = s and s.sx, seed_sy = s and s.sy }
		fitted[k] = fit
	end
	local function axis(g, m, low, high, scale, offset, seed_scale)
		if not fit[low] or g < fit[low][1] then fit[low] = { g, m } end
		if not fit[high] or g > fit[high][1] then fit[high] = { g, m } end
		local a, b = fit[low], fit[high]
		if b[1] - a[1] >= SPREAD then
			fit[scale] = (b[2] - a[2]) / (b[1] - a[1])
		elseif seed_scale then
			fit[scale] = seed_scale
		end
		if fit[scale] then fit[offset] = m - fit[scale] * g end
	end
	axis(gx, mx, "x_low", "x_high", "sx", "ox", fit.seed_sx)
	axis(gz, my, "z_low", "z_high", "sy", "oy", fit.seed_sy)
end

-- ------------------------------------------------------------------ planning
local names = PLAYFIELDS or {}
local function zone_name(id) return names[id] or ("zone " .. id) end

local function km(metres)
	if metres < 1000 then return string.format("%d m", math.floor(metres / 10 + 0.5) * 10) end
	return string.format("%.1f km", metres / 1000)
end

-- Fastest way from the start to the goal (both global positions) on `map`.
-- Returns { seconds, steps = { text... }, legs = { { gx, gz, gx, gz }... }, stands = { { gx, gz }... } }
-- or nil when the map has no whompah data.
function ROUTE.plan(map, start_x, start_z, goal_x, goal_z)
	if not WHOMPAHS or not (WHOMPAH_MAPS and WHOMPAH_MAPS[map]) then return nil end
	-- nodes: 1 start, 2 goal, 2 + i whompah i
	local nodes = { { start_x, start_z }, { goal_x, goal_z } }
	local whompah = {}
	for i, w in ipairs(WHOMPAHS) do
		local gx, gz = global(map, w[1], w[2], w[3])
		if gx then
			nodes[#nodes + 1] = { gx, gz, zone = w[1], dest = w[4] }
			whompah[#whompah + 1] = #nodes
		end
	end
	-- each whompah's arrival stand: the one in its destination zone that leads back
	local partner = {}
	for _, a in ipairs(whompah) do
		for _, b in ipairs(whompah) do
			if nodes[b].zone == nodes[a].dest and nodes[b].dest == nodes[a].zone then partner[a] = b end
		end
	end
	local function walk(a, b)
		local dx, dz = nodes[a][1] - nodes[b][1], nodes[a][2] - nodes[b][2]
		return math.sqrt(dx * dx + dz * dz) / WALK_SPEED
	end
	-- Dijkstra over ~66 nodes; edge kinds: walk to any stand or the goal, hop to the partner.
	local cost, previous, hopped, done = { [1] = 0 }, {}, {}, {}
	while true do
		local best
		for n in pairs(cost) do
			if not done[n] and (not best or cost[n] < cost[best]) then best = n end
		end
		if not best or best == 2 then break end
		done[best] = true
		local function relax(n, value, hop)
			if not done[n] and (not cost[n] or value < cost[n]) then
				cost[n], previous[n], hopped[n] = value, best, hop
			end
		end
		relax(2, cost[best] + walk(best, 2), false)
		for _, w in ipairs(whompah) do
			if w ~= best then relax(w, cost[best] + walk(best, w), false) end
		end
		if partner[best] and hopped[best] == false then -- arrived at a stand on foot: may hop
			relax(partner[best], cost[best] + HOP_SECONDS, true)
		end
	end
	if not cost[2] then return nil end

	local path = {}
	local n = 2
	while n do
		table.insert(path, 1, n)
		n = previous[n]
	end
	local result = { seconds = cost[2], steps = {}, legs = {}, stands = {} }
	local walked = 0
	local function flush_walk(target, always)
		if walked >= 50 or (always and walked > 0) then -- skip the few steps between stands
			result.steps[#result.steps + 1] = "Walk " .. km(walked) .. " " .. target
		end
		walked = 0
	end
	for i = 2, #path do
		local a, b = path[i - 1], path[i]
		if hopped[b] then
			result.stands[#result.stands + 1] = { nodes[a][1], nodes[a][2] }
			result.stands[#result.stands + 1] = { nodes[b][1], nodes[b][2] }
			flush_walk("to the " .. zone_name(nodes[a].zone) .. " whompah")
			result.steps[#result.steps + 1] = "Whompah: " .. zone_name(nodes[a].zone) .. " → " .. zone_name(nodes[b].zone)
		else
			result.legs[#result.legs + 1] = { nodes[a][1], nodes[a][2], nodes[b][1], nodes[b][2] }
			walked = walked + walk(a, b) * WALK_SPEED
		end
	end
	flush_walk("to the mission", true)
	return result
end
