-- NKTouch v0.4 Lua compatibility/runtime helper
-- SPDX-License-Identifier: GPL-3.0-or-later

local M = {}
M.VERSION = "0.4.0"

local CTL = "/var/jb/usr/bin/nktouchctl"

local function shq(s)
    s = tostring(s or "")
    return "'" .. s:gsub("'", "'\\''") .. "'"
end

local function run(parts)
    local out = {}
    for i, v in ipairs(parts) do out[i] = shq(v) end
    local cmd = CTL .. " " .. table.concat(out, " ")
    return os.execute(cmd)
end

local function number_or_error(value, name)
    local n = tonumber(value)
    if n == nil then
        error("NKTouch: " .. name .. " phải là số", 3)
    end
    return n
end

function M.status(percent, message)
    return run({"status", tonumber(percent) or 0, message or ""})
end

function M.success(message)
    return run({"success", message or "Hoàn tất"})
end

function M.warning(message)
    return run({"warning", message or "Cảnh báo"})
end

function M.error(message)
    return run({"error", message or "Lỗi"})
end

function M.hide()
    return run({"hide"})
end

function M.log(message)
    return run({"log", message or ""})
end

function M.heartbeat()
    return run({"heartbeat"})
end

-- Native automation commands inherited from v0.3.
function M.tap(x, y)
    return run({"tap", x, y})
end

function M.hold(x, y, ms)
    return run({"hold", x, y, ms or 500})
end

function M.swipe(x1, y1, x2, y2, ms)
    return run({"swipe", x1, y1, x2, y2, ms or 400})
end

function M.openApp(bundleId)
    return run({"openapp", bundleId})
end

M.appRun = M.openApp

function M.recordStart()
    return run({"record", "start"})
end

function M.recordStop()
    return run({"record", "stop"})
end

function M.stop()
    return run({"stop"})
end

function M.ping()
    return run({"ping"})
end

function M.screen()
    return run({"screen"})
end

function M.foreground()
    return run({"foreground"})
end

-- Lua itself has no portable sleep function. The v0.4 runner prepends the
-- rootless Procursus paths, so the standard sleep utility can be used without
-- Python or AutoTouch.
function M.sleep(seconds)
    local sec = number_or_error(seconds, "seconds")
    if sec < 0 then error("NKTouch: seconds không được âm", 2) end
    return os.execute(string.format("sleep %.6f", sec))
end

function M.usleep(microseconds)
    local us = number_or_error(microseconds, "microseconds")
    if us < 0 then error("NKTouch: microseconds không được âm", 2) end
    return M.sleep(us / 1000000.0)
end

function M.installAutoTouchCompat()
    _G.setTopStatus = M.status
    _G.hideTopStatus = M.hide
    _G.tap = M.tap
    _G.hold = M.hold
    _G.swipe = M.swipe
    _G.appRun = M.openApp
    _G.usleep = M.usleep
    _G.sleep = M.sleep
    _G.log = M.log
    return true
end

return M
