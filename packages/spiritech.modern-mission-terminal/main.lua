-- Modern Mission Terminal: one package, two roles (prk.mission-terminal + prk.info): the
-- flat terminal list and the flat Info window, which names a mission's reward items.
-- A provider must mount its window during init, but no API names the role. Each role gets
-- its own native adapter, so this asks the Mission Terminal adapter: a direct Lua call of
-- accept is always refused with false (never sends anything) in the terminal instance and
-- fails ("Unknown ... capability") in the Info instance. Result logged to storage "role_log_<role>".
pcall(ui.require, "spiritech.modern-common/screenfit") -- keep window positions through fullscreen changes

-- ------------------------------------------------------------------ role
local ok, result = pcall(game.mission_terminal.accept, 0)
local role = (ok and result == false) and "terminal" or "info"
pcall(ui.storage.write, "role_log_" .. role, string.format("accept probe ok=%s result=%s -> %s",
	tostring(ok), tostring(result), role))

if role == "info" then
	BUILD_INFO()
else
	BUILD_TERMINAL()
end
