-- NKTouch v0.4 Lua bootstrap
-- Loaded automatically by nktouch-run through LUA_INIT.

local ok, nk = pcall(require, "nktouch")
if not ok then
    error("NKTouch bootstrap: cannot load nktouch module: " .. tostring(nk))
end

_G.nk = nk
nk.installAutoTouchCompat()
