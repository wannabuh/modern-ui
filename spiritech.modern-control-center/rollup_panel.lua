ui.define("control_center.rollup_panel", function()
	local Column = ui.require("core.hud_column")
	local Panel = {}
	Panel.__index = Panel

	function Panel.create(owner, wing, minibar)
		if not ui.docking.available() then return nil end
		local self = setmetatable({ root = ui.load("rollup_panel.xml"), wing = wing, minibar = minibar }, Panel)
		self.background = ui.find(self.root, "rollup_background")
		ui.attach(owner, self.root, function() self:refresh() end)
		ui.rollup_host(self.root, ui.find(self.root, "rollup_pages"), Column.WIDTH)
		self:refresh()
		return self
	end

	function Panel:refresh()
		local top = ui.requested_visible(self.minibar) and Column.TOP or 0
		local height = math.max(0, ui.parent_height(self.root) - top - ui.minimum_height(self.wing))
		if height == self.height and top == self.top then return end
		self.height, self.top = height, top
		ui.size(self.root, Column.WIDTH, height)
		ui.place(self.root, 0, top)
		ui.align(self.root, "end", "start")
	end

	function Panel:show(shown, opacity)
		ui.visible(self.root, shown)
		ui.opacity(self.background, opacity)
		self:refresh()
	end

	return Panel
end)
