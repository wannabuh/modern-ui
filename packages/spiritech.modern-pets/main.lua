-- Modern Pets (role prk.pets): your pets as flat unit frames, like Modern Team.
-- Each pet: a health bar (green, amber under 50%, red under 25%) with its name and level on
-- the left and health on the right ("Dead", "Out of zone"), then flat Attack (red; "Heal",
-- green, for healer pets) / Follow / Wait buttons, and the nano programs running on it
-- underneath. Click a pet's bar to target it; the targeted pet gets a teal edge.
-- Title menu: Show buttons (remembered), Fixed pet buttons (the game's own setting).
-- Commands and targeting are the game's bound actions, as in the built-in window.
pcall(ui.require, "spiritech.modern-common/screenfit") -- keep window positions through fullscreen changes
local Window = ui.require("core.window")
local Security = ui.require("core.security")
local Strip = ui.require("ncu.strip")
local Effects = ui.require("effects.presentation")
local Theme = ui.require("spiritech.modern-common/theme")

local WIDTH, NARROW = 340, 200 -- with / without the buttons
local ROW = 28 + 1 -- row + divider
local EMPTY = 24
local PADDING = 4 -- content borders
local STRIP_SIDES = 12
local GREEN, AMBER, RED, DEAD = "#3E8A58", "#B5852B", "#A33434", "#5E6875"
local ATTACK, HEAL = "#6B2A2A", "#2F6E45"

local content = ui.load("content.xml")
local host = ui.find(content, "pet_rows")
local empty = ui.find(content, "pet_empty")
local rows, pets, nanos = {}, {}, {}
local stored_buttons = (ui.preference.read("modern_pets_buttons") or ""):gsub('^"(.*)"$', "%1")
local show_buttons = stored_buttons ~= "false"
local fixed_slots = false
local selected
local frame

local function width()
	return show_buttons and WIDTH or NARROW
end

-- Height fits the rows and their buff strips exactly.
local function layout(window)
	local total = width()
	local inner = total - Window.CONTENT_SIDES
	local height = PADDING
	for _, row in ipairs(rows) do
		ui.visible(row.pet_buttons, show_buttons)
		height = height + ROW
		local strip = row.strip:show(nanos[row.subject] or {}, inner - STRIP_SIDES, true) or 0
		if strip > 0 then height = height + strip + 3 end
	end
	ui.visible(empty, #rows == 0)
	if #rows == 0 then height = height + EMPTY end
	local outer = height + (Window.CONTENT_ENDS or 33)
	ui.limits(window.root, total, outer, total, outer)
	ui.request_size(window.root, total, outer)
	window:fit_title(total, true)
	window:fit_content(total, outer)
end

local function resize()
	frame:resize(width(), 0)
end

frame = Window.create({
	template = Theme.WINDOW_TEMPLATE,
	title = "Pets", content = content, width = width(), height = 80, resizable = false,
	horizontal = "center", vertical = "center", layout = layout,
	menu = {
		{
			label = "Show buttons", checked = show_buttons,
			invoke = function()
				show_buttons = not show_buttons
				ui.preference.write("modern_pets_buttons", tostring(show_buttons), "bool")
				ui.menu.checked(frame.icon, 1, show_buttons)
				resize()
			end,
		},
		{
			label = "Fixed pet buttons", checked = fixed_slots,
			invoke = function()
				fixed_slots = not fixed_slots
				game.pets.set_fixed_slots(fixed_slots)
				ui.menu.checked(frame.icon, 2, fixed_slots)
			end,
		},
	},
})
ui.image(frame.icon, "gfx://GFX_GUI_WINDOW_ICON_PET")
ui.root(frame.root)

local function add_row()
	local loaded = ui.load("row.xml")
	ui.add(host, loaded)
	local root = ui.find(loaded, "pet_row") or loaded
	local row = { root = root, subject = 0 }
	for _, name in ipairs({ "pet_bar", "pet_fill", "pet_name", "pet_level", "pet_health", "pet_buttons",
		"pet_primary", "pet_primary_fill", "pet_primary_label", "pet_follow", "pet_wait", "pet_ncu_strip",
		"row_target", "row_target_edge" }) do
		row[name] = ui.find(root, name)
	end
	row.buttons = { row.pet_primary, row.pet_follow, row.pet_wait }
	row.strip = Strip.create(row.pet_ncu_strip, {
		template = "team_ncu_slot.xml", cell_width = 16, cell_height = 16, lines = 2, flash = true,
	})
	return row
end

local function fill(row, fraction, color)
	local bar = ui.width(row.pet_bar)
	if not bar or bar <= 0 then bar = width() - Window.CONTENT_SIDES - 12 - (show_buttons and 156 or 0) end
	local pixels = math.floor(math.max(0, bar - 2) * math.max(0, math.min(1, fraction)) + 0.5)
	ui.visible(row.pet_fill, pixels > 0)
	ui.size(row.pet_fill, math.max(1, pixels), -1)
	ui.fill_color(row.pet_fill, color)
end

local function present(row)
	local character = row.pet.character
	local present_now = character.present
	local health, maximum = character.health, character.max_health
	local dead = present_now and health == 0
	local fraction = (present_now and health and maximum and maximum > 0) and health / maximum or 0
	fill(row, fraction, dead and DEAD or fraction < 0.25 and RED or fraction < 0.5 and AMBER or GREEN)
	ui.text(row.pet_name, (character.name or "Pet"):gsub("[%c]", ""))
	ui.text(row.pet_level, character.level and tostring(character.level) or "")
	local text = ""
	if not present_now then
		text = "Out of zone"
	elseif dead then
		text = "Dead"
	elseif health and maximum then
		text = Theme.thousands(health) .. " / " .. Theme.thousands(maximum)
	end
	ui.text(row.pet_health, text)
	ui.tooltip(row.pet_bar, character.name or "")
	local targeted = selected ~= nil and character.reference == selected
	ui.visible(row.row_target, targeted)
	ui.visible(row.row_target_edge, targeted)
	ui.opacity(row.root, present_now and 1 or 0.5)
	local healer = row.pet.healer
	ui.text(row.pet_primary_label, healer and "Heal" or "Attack")
	ui.fill_color(row.pet_primary_fill, healer and HEAL or ATTACK)
	ui.tooltip(row.pet_primary, healer and "Commands the pet to heal your selected target"
		or "Commands the pet to attack your selected target")
end

game.pets.subscribe(function(update)
	local state = update.data or { members = {}, fixed_slots = false }
	pets, fixed_slots = state.members, state.fixed_slots
	rows = Security.reconcile(host, rows, pets, #pets,
		function(pet) return pet.character.reference end, add_row,
		function(row)
			row.strip:destroy()
			ui.destroy(row.root)
		end,
		function(row) return row.subject end)
	for index, row in ipairs(rows) do
		local pet = pets[index]
		row.subject, row.pet = pet.character.reference, pet
		local target = game.targeting.prepare_select(row.subject)
		ui.actions.bind(row.root, target, "left", "press")
		ui.actions.bind(row.pet_bar, target, "left", "press")
		local commands = {
			game.pets.prepare_primary(row.subject),
			game.pets.prepare_follow(row.subject),
			game.pets.prepare_wait(row.subject),
		}
		for command_index, button in ipairs(row.buttons) do
			ui.actions.bind(button, commands[command_index], "left", "release")
			ui.enabled(button, ui.actions.available(commands[command_index]))
		end
		present(row)
	end
	ui.menu.checked(frame.icon, 2, fixed_slots)
	resize()
end)

game.targeting.subscribe(function(update)
	selected = update.data and update.data.selected and update.data.selected.reference
	for _, row in ipairs(rows) do present(row) end
end)

game.effects.subscribe("pets", function(update)
	nanos = Effects.collections(update)
	resize()
end)
