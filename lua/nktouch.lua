-- NKTouch v0.4 Lua compatibility/helper API
-- SPDX-License-Identifier: GPL-3.0-or-later

local M = {}
M.VERSION = "0.4.0"
local CTL = "/var/jb/usr/bin/nktouchctl"

local function shq(s)
    s = tostring(s or "")
    return "'" .. s:gsub("'", "'\\''") .. "'"
end

local function command(parts)
    local out = {}
    for i, v in ipairs(parts) do out[i] = shq(v) end
    return CTL .. " " .. table.concat(out, " ")
end

local function run(parts)
    return os.execute(command(parts))
end

local function capture(parts)
    local p = io.popen(command(parts) .. " 2>/dev/null", "r")
    if not p then return nil end
    local out = p:read("*a") or ""
    local ok = p:close()
    out = out:gsub("[\r\n]+$", "")
    if not ok then return nil end
    return out
end

function M.status(percent, message) return run({"status", tonumber(percent) or 0, message or ""}) end
function M.success(message) return run({"success", message or "Hoàn tất"}) end
function M.warning(message) return run({"warning", message or "Cảnh báo"}) end
function M.error(message) return run({"error", message or "Lỗi"}) end
function M.hide() return run({"hide"}) end
function M.log(message) return run({"log", message or ""}) end
function M.heartbeat() return run({"heartbeat"}) end

function M.tap(x, y) return run({"tap", x, y}) end
function M.hold(x, y, ms) return run({"hold", x, y, ms or 500}) end
function M.swipe(x1, y1, x2, y2, ms) return run({"swipe", x1, y1, x2, y2, ms or 400}) end
function M.openApp(bundleId) return run({"openapp", bundleId}) end
function M.recordStart() return run({"record", "start"}) end
function M.recordStop() return run({"record", "stop"}) end
function M.stop() return run({"stop"}) end
function M.ping() return run({"ping"}) end

-- v0.4 keyboard / clipboard
function M.text(text) return run({"text", text or ""}) end
M.inputText = M.text
function M.showKeyboard() return run({"keyboard", "show"}) end
function M.hideKeyboard() return run({"keyboard", "hide"}) end
function M.moveCursor(offset) return run({"cursor", tonumber(offset) or 0}) end
function M.delete(count) return run({"delete", tonumber(count) or 1}) end
function M.paste(text) return run({"paste", text or ""}) end
function M.getClipboard() return capture({"clipboard-get"}) end
function M.setClipboard(text) return run({"clipboard-set", text or ""}) end

-- v0.4 screen / device queries
function M.screenshot() return capture({"screenshot"}) end
function M.screen() return capture({"screen"}) end
function M.foreground() return capture({"foreground"}) end
function M.orientation() return capture({"orientation"}) end
function M.scale() return capture({"scale"}) end
function M.device() return capture({"device"}) end
function M.battery() return capture({"battery"}) end
function M.runtime() return capture({"runtime"}) end
function M.backend() return capture({"backend"}) end

function M.installAutoTouchCompat()
    _G.setTopStatus = M.status
    _G.hideTopStatus = M.hide
    _G.tap = M.tap
    _G.inputText = M.inputText
    _G.log = M.log
    return true
end

return M
