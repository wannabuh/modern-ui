-- Stock Info window (client UI/Packages/Info/main.lua, unchanged), built only in the Info
-- instance of this package; see main.lua.
function BUILD_INFO()
	local Window = ui.require("core.window")
	local content = ui.load("content.xml")
	local lines = ui.find(content, "info_lines")
	local scroll = ui.find(content, "info_scroll")
	local back = ui.find(content, "info_back")
	local forward = ui.find(content, "info_forward")
	local history, current = {}, 0
	local views, rows, column_widths = {}, {}, {}
	local pending_scroll, width, needed_width = nil, 0, nil
	local metric_revision
	local before_impact, applied_impact, manually_resized = nil, nil, false
	local history_limit, cell_gap, note_gap, indent_width = 32, 16, 4, 20
	local colors = {
		title = "#F2F25C",
		highlight = "#FFFFFF",
		heading = "#3DE33D",
		detail = "#9CD69C",
		link = "#7FD4FF",
	}
	local frame = Window.create({
		content = content,
		title = "Info",
		remember_open = false,
		width = 420,
		height = 520,
		horizontal = "center",
		vertical = "center",
		layout = function(window, requested_width, requested_height)
			ui.limits(window.root, 260, 160, 900, 1200)
			ui.request_size(window.root, requested_width, requested_height)
			local chosen_width, chosen_height = ui.chosen_width(window.root), ui.chosen_height(window.root)
			window:fit_title(chosen_width, true)
			window:fit_content(chosen_width, chosen_height)
		end,
	})
	ui.root(frame.root)
	game.info.surface(lines, scroll)
	ui.enabled(back, false)
	ui.enabled(forward, false)

	local function rgb(value)
		return string.format("#%06X", value)
	end

	local function fit_width()
		if width <= 0 then
			return
		end
		for _, view in ipairs(views) do
			if view.wrap then
				ui.maximum(view.root, math.max(1, width - view.indent), -1)
			end
		end
	end

	local function fit_columns()
		local needed = nil
		for _, row in ipairs(rows) do
			for index, cell in ipairs(row.cells) do
				local measured = math.ceil(ui.text_width(cell.value))
				if cell.note then
					measured = measured + note_gap + math.ceil(ui.text_width(cell.note))
				end
				column_widths[index] = math.max(column_widths[index] or 0, measured)
			end
		end
		for _, row in ipairs(rows) do
			local measured = row.indent + math.ceil(ui.text_width(row.label))
			for index, cell in ipairs(row.cells) do
				ui.size(cell.root, column_widths[index], -1)
				measured = measured + column_widths[index] + cell_gap
			end
			needed = math.max(needed or 0, measured)
		end
		needed_width = needed
		ui.publish("width_needed", needed and tostring(needed) or "")
	end

	local function create_cell(fact)
		local root = ui.load("cell.xml")
		local value = ui.find(root, "value")
		ui.text(value, fact.text)
		ui.text_color(value, rgb(fact.rgb))
		local note = ui.find(root, "note")
		if fact.note ~= "" then
			ui.text(note, fact.note)
			ui.text_color(note, rgb(fact.note_rgb))
		else
			ui.destroy(note)
			note = nil
		end
		return { root = root, value = value, note = note }
	end

	local function create_row(fact, cells)
		local root = ui.load("row.xml")
		local label = ui.find(root, "label")
		ui.text(label, fact.text)
		ui.text_color(label, fact.rgb >= 0 and rgb(fact.rgb) or colors[fact.tone])
		local row = { root = root, label = label, cells = {}, indent = fact.indent * indent_width }
		for index, cell in ipairs(cells or {}) do
			row.cells[index] = create_cell(cell)
			ui.add(root, row.cells[index].root)
		end
		rows[#rows + 1] = row
		return root
	end

	local function escape_markup(text)
		return (text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
	end

	local function colored(color, text)
		return "<font color=" .. color .. ">" .. escape_markup(text) .. "</font>"
	end

	local function create_line(page, fact, index, cells)
		local named_item = fact.item and fact.link
		local template = named_item and "named_item.xml" or fact.item and "item.xml" or fact.row and "row.xml" or
			(fact.link or fact.document) and "interactive.xml" or "text.xml"
		local root = fact.row and create_row(fact, cells) or ui.load(template)
		ui.borders(root, fact.indent * indent_width, 0, 0, fact.document and 0 or 1)
		ui.add(lines, root)
		if named_item then
			local icon = ui.find(root, "icon")
			ui.content(icon, true)
			ui.icon(icon, fact.icon)
			local label = ui.find(root, "label")
			ui.text(label, fact.text)
			ui.text_color(label, colors.link)
			ui.aoml(label, "", "<u>" .. escape_markup(fact.text) .. "</u>", false)
			ui.tooltip(root, fact.text)
		elseif fact.item then
			ui.content(root, true)
			ui.icon(root, fact.icon)
			ui.tooltip(root, fact.text)
		elseif not fact.row then
			ui.text(root, fact.text)
			ui.text_color(root, fact.document and "#FFFFFF" or fact.link and colors.link or
				fact.rgb >= 0 and rgb(fact.rgb) or colors[fact.tone])
			if fact.document then
				game.info.document(root, page, index)
			elseif fact.link then
				ui.aoml(root, "", "<u>" .. escape_markup(fact.text) .. "</u>", false)
			elseif fact.value ~= "" and fact.rgb < 0 then
				local label = fact.text:sub(1, #fact.text - #fact.value)
				ui.aoml(root, "", colored(colors[fact.tone], label) .. colored(colors.detail, fact.value), false)
			end
		end
		if fact.item or fact.link then
			ui.bind(root, fact.token)
			ui.action(root, "game.info.inspect", fact.token, "left")
		end
		views[#views + 1] = {
			root = root,
			wrap = not fact.item and not fact.row,
			indent = fact.indent * indent_width,
		}
	end

	local function save_scroll()
		if current > 0 then
			history[current].scroll = pending_scroll or ui.scroll_offset(scroll)
		end
	end

	local function render(refresh)
		local page = history[current]
		game.info.select(page.token)
		for _, view in ipairs(views) do
			ui.destroy(view.root)
		end
		views, rows, column_widths = {}, {}, {}
		pending_scroll = page.scroll
		if not refresh then
			ui.scroll_top(scroll)
		end
		ui.enabled(back, current > 1)
		ui.enabled(forward, current < #history)
		for index, fact in ipairs(page.lines) do
			create_line(page.token, fact, index, page.cells[index])
		end
		fit_columns()
		fit_width()
		game.info.selection(refresh)
	end

	function info_show(token, facts, cells, refresh)
		save_scroll()
		local grouped = {}
		for _, cell in ipairs(cells) do
			grouped[cell.line] = grouped[cell.line] or {}
			table.insert(grouped[cell.line], cell)
		end
		local page = { token = token, lines = facts, cells = grouped, scroll = 0 }
		local replaced
		if refresh and current > 0 then
			replaced = history[current].token
			page.scroll = history[current].scroll
			history[current] = page
		else
			while #history > current do
				game.info.release(table.remove(history).token)
			end
			history[#history + 1] = page
			current = #history
		end
		render(refresh)
		if replaced then
			game.info.release(replaced)
		end
		if #history > history_limit then
			game.info.release(table.remove(history, 1).token)
			current = current - 1
			ui.enabled(back, current > 1)
		end
	end

	function info_navigate(direction)
		local next_page = current + direction
		if next_page < 1 or next_page > #history or next_page == current then
			return
		end
		save_scroll()
		current = next_page
		render(false)
	end

	function info_update(metrics)
		if metrics ~= metric_revision then
			metric_revision = metrics
			column_widths = {}
			fit_columns()
		end
		frame:resize(ui.chosen_width(frame.root), ui.chosen_height(frame.root))
		local available = ui.width(lines)
		local changed = available > 0 and available ~= width
		if changed then
			width = available
			fit_width()
			ui.publish("width_available", tostring(width))
		end
		if changed or pending_scroll == nil then
			return
		end
		for _, view in ipairs(views) do
			if ui.height(view.root) <= 0 then
				return
			end
		end
		ui.scroll_to(scroll, pending_scroll)
		pending_scroll = nil
	end

	function info_impact_width(visible, impact, viewport_width)
		if not visible or not impact then
			if before_impact then
				frame:resize(before_impact.width, before_impact.height)
			end
			before_impact, applied_impact, manually_resized = nil, nil, false
			return
		end
		if manually_resized then
			return
		end
		local current_width, current_height = ui.chosen_width(frame.root), ui.chosen_height(frame.root)
		if applied_impact and (current_width ~= applied_impact.width or current_height ~= applied_impact.height) then
			before_impact, applied_impact, manually_resized = nil, nil, true
			return
		end
		if not needed_width or width <= 0 then
			return
		end
		local target = math.min(current_width + needed_width - width, viewport_width)
		target = math.max(target, before_impact and before_impact.width or 0)
		if math.abs(target - current_width) <= 0.5 or not before_impact and target < current_width then
			return
		end
		frame:resize(target, current_height)
		local chosen = ui.chosen_width(frame.root)
		if math.abs(chosen - current_width) <= 0.5 then
			return
		end
		before_impact = before_impact or { width = current_width, height = current_height }
		applied_impact = { width = chosen, height = ui.chosen_height(frame.root) }
	end

	ui.on_click(back, function()
		info_navigate(-1)
	end)
	ui.on_click(forward, function()
		info_navigate(1)
	end)
end
