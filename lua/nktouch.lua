-- NKTouch v0.5 Lua compatibility/helper API
-- SPDX-License-Identifier: GPL-3.0-or-later

local M = {}
M.VERSION = "0.5.0"
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

local function splitRect(s)
    if not s then return nil end
    local x,y,w,h = s:match("^([%-%.%d]+);;([%-%.%d]+);;([%-%.%d]+);;([%-%.%d]+)$")
    if not x then return nil end
    return {x=tonumber(x), y=tonumber(y), width=tonumber(w), height=tonumber(h)}
end

function M.status(percent, message) return run({"status", tonumber(percent) or 0, message or ""}) end
function M.success(message) return run({"success", message or "Hoàn tất"}) end
function M.warning(message) return run({"warning", message or "Cảnh báo"}) end
function M.error(message) return run({"error", message or "Lỗi"}) end
function M.hide() return run({"hide"}) end
function M.log(message) return run({"log", message or ""}) end
function M.heartbeat() return run({"heartbeat"}) end
function M.doctor() return capture({"doctor"}) end

function M.tap(x, y) return run({"tap", x, y}) end
function M.hold(x, y, ms) return run({"hold", x, y, ms or 500}) end
function M.swipe(x1, y1, x2, y2, ms) return run({"swipe", x1, y1, x2, y2, ms or 400}) end
function M.openApp(bundleId) return run({"openapp", bundleId}) end
function M.waitApp(bundleId, timeoutMs, intervalMs)
    local p = {"wait-app", bundleId, timeoutMs or 5000}
    if intervalMs then p[#p+1] = intervalMs end
    return run(p)
end
function M.sleep(ms) return run({"sleep", ms or 0}) end
function M.recordStart() return run({"record", "start"}) end
function M.recordStop() return run({"record", "stop"}) end
function M.stop() return run({"stop"}) end
function M.ping() return run({"ping"}) end

function M.text(text) return run({"text", text or ""}) end
M.inputText = M.text
function M.showKeyboard() return run({"keyboard", "show"}) end
function M.hideKeyboard() return run({"keyboard", "hide"}) end
function M.moveCursor(offset) return run({"cursor", tonumber(offset) or 0}) end
function M.delete(count) return run({"delete", tonumber(count) or 1}) end
function M.paste(text) return run({"paste", text or ""}) end
function M.getClipboard() return capture({"clipboard-get"}) end
function M.setClipboard(text) return run({"clipboard-set", text or ""}) end

function M.screenshot(path)
    local p = {"screenshot"}
    if path then p[#p+1] = path end
    return capture(p)
end

function M.findImage(path, maxTry, confidence, scale)
    local p = {"find-image", path}
    if maxTry or confidence or scale then
        p[#p+1] = maxTry or 2
        p[#p+1] = confidence or 0.8
        p[#p+1] = scale or 0.8
    end
    return splitRect(capture(p))
end

function M.waitImage(path, timeoutMs, intervalMs, confidence)
    local p = {"wait-image", path, timeoutMs or 5000}
    if intervalMs or confidence then p[#p+1] = intervalMs or 250 end
    if confidence then p[#p+1] = confidence end
    return splitRect(capture(p))
end

function M.tapImage(path, timeoutMs, intervalMs, confidence)
    local p = {"tap-image", path, timeoutMs or 5000}
    if intervalMs or confidence then p[#p+1] = intervalMs or 250 end
    if confidence then p[#p+1] = confidence end
    return run(p)
end

function M.ocr(x, y, width, height, languages)
    local p = {"ocr", x, y, width, height}
    if languages then p[#p+1] = languages end
    return capture(p)
end

function M.screen() return capture({"screen"}) end
function M.foreground() return capture({"foreground"}) end
function M.orientation() return capture({"orientation"}) end
function M.scale() return capture({"scale"}) end
function M.device() return capture({"device"}) end
function M.battery() return capture({"battery"}) end
function M.runtime() return capture({"runtime"}) end
function M.backend() return capture({"backend"}) end

function M.runScript(path, ...)
    local p = {"run", path}
    for _,v in ipairs({...}) do p[#p+1] = v end
    return run(p)
end

function M.installAutoTouchCompat()
    _G.setTopStatus = M.status
    _G.hideTopStatus = M.hide
    _G.tap = M.tap
    _G.inputText = M.inputText
    _G.log = M.log
    _G.usleep = function(us) return M.sleep(math.floor((tonumber(us) or 0) / 1000)) end
    return true
end

return M
