-- This package serves two roles: the Control Center (one instance) and every shortcut bar
-- (one instance per visible bar). The same scripts run in each instance, so this decides
-- which half applies: only the Control Center is granted window destinations, so resolving
-- one succeeds there and raises (caught here) everywhere else.
pcall(ui.require, "spiritech.modern-common/screenfit") -- keep window positions through fullscreen changes
CC_ROLE = pcall(ui.destinations.require, "prk.inventory") and "control-center" or "hotbar"
