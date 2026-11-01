-- NKTouch v0.2 Lua compatibility helper
-- SPDX-License-Identifier: GPL-3.0-or-later

local M = {}
local CTL = "/var/jb/usr/bin/nktouchctl"

local function shq(s)
    s = tostring(s or "")
    return "'" .. s:gsub("'", "'\\''") .. "'"
end

local function run(parts)
    local out = {}
    for i, v in ipairs(parts) do out[i] = shq(v) end
    local cmd = CTL .. " " .. table.concat(out, " ")
    local ok = os.execute(cmd)
    return ok
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

function M.recordStart()
    return run({"record", "start"})
end

function M.recordStop()
    return run({"record", "stop"})
end

function M.stop()
    return run({"stop"})
end

function M.installAutoTouchCompat()
    _G.setTopStatus = M.status
    _G.hideTopStatus = M.hide
    _G.tap = M.tap
    _G.log = M.log
    return true
end

return M
