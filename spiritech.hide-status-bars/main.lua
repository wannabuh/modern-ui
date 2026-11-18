-- Provides the prk.status-bars role but draws nothing, so the combined
-- Player Bars addon panel can replace the four separate built-in bars.
local root = ui.load("window.xml")
ui.root(root)
ui.visible(root, false)

function status_bar_initialize(kind) end

function status_bar_apply(reading, shadowknowledge) end
