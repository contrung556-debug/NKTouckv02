-- NKTouch Vision Core 0.7.9. Explicit immutable frame snapshots.
-- Retains all v0.7.8.1 live APIs. The user chooses when to capture/refresh.
-- GPL-3.0-or-later
local M = {}
local nextCapture = 0

local function temporaryFile()
  nextCapture = nextCapture + 1
  local id = tostring(os.getenv("NKTOUCH_TASK_ID") or "manual")
  id = id:gsub("[^%w_-]", ""):sub(1, 64)
  if id == "" then id = "manual" end
  return ("/var/mobile/Library/NKTouch/vision-%s-%d-%d.jpg"):format(
      id, os.time(), nextCapture)
end

function M.capture(nk)
  if type(nk) ~= "table" or type(nk.screenshot) ~= "function" then
    return nil, "NKTouch screenshot API unavailable", "NO_SCREENSHOT"
  end
  local loaded, native = pcall(require, "nkvision_native")
  if not loaded or type(native) ~= "table" or type(native.open) ~= "function" then
    return nil, "Vision Core native module unavailable", "NO_VISION"
  end
  local path = temporaryFile()
  local shot, err, kind = nk.screenshot(path)
  if not shot then return nil, err or "screen capture failed", kind or "CAPTURE" end
  if shot ~= path then
    return nil, "screenshot returned unexpected path", "CAPTURE"
  end
  local ok, frame, openErr, openCode = pcall(native.open, path)
  local removed, removeErr = os.remove(path)
  if not removed then
    if ok and frame and type(frame.close)=="function" then pcall(frame.close,frame) end
    return nil, "cannot remove temporary screenshot: "..tostring(removeErr), "CLEANUP"
  end
  if not ok then return nil, tostring(frame), "DECODE" end
  if not frame then return nil, openErr or "cannot open screenshot frame", openCode or "DECODE" end
  return frame
end

-- Guaranteed frame close, even when callback returns an error or raises.
-- Callback may return any number of Lua values; they are propagated verbatim.
function M.withFrame(nk, callback)
  if type(callback) ~= "function" then
    return nil, "a callback function is required", "INVALID"
  end
  local frame, err, kind = M.capture(nk)
  if not frame then return nil, err, kind end
  local values = table.pack(pcall(callback, frame))
  local closeOk, closeResult = pcall(frame.close, frame)
  if not closeOk or closeResult ~= true then
    return nil, "failed to release Vision frame", "CLEANUP"
  end
  if not values[1] then return nil, tostring(values[2]), "CALLBACK" end
  return table.unpack(values, 2, values.n)
end

return M
