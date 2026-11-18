ui.define("control_center.minibar", function()
	local Minibar = {}

	function Minibar.create(parent, windows, bind_window)
		local root = ui.load("minibar.xml")
		local column = ui.require("core.hud_column")
		ui.size(root, column.WIDTH, column.TOP)
		ui.add(parent, root)
		for _, entry in ipairs({
			{ "wear", windows.wear },
			{ "actions", windows.actions },
			{ "missions", windows.missions },
			{ "team", windows.team },
			{ "playfield_map", windows.playfield_map },
			{ "friends", windows.friends },
			{ "programs", windows.nano },
			{ "stats", windows.stats },
			{ "ncu", windows.ncu },
		}) do
			bind_window("minibar_" .. entry[1], entry[2])
		end
		return root
	end

	return Minibar
end)
