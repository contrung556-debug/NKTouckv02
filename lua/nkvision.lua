-- NKTouch Vision Core 0.7.9. Explicit immutable frame snapshots.
-- Retains all v0.7.8.1 live APIs. The user chooses when to capture/refresh.
-- GPL-3.0-or-later
local M = {}
local function cleanup(path)
  local ok, removed, err = pcall(os.remove, path)
  if not ok then return nil, tostring(removed) end
  if not removed then return nil, tostring(err) end
  return true
end

function M.capture(nk)
  if type(nk) ~= "table" or type(nk.screenshot) ~= "function" then
    return nil, "NKTouch screenshot API unavailable", "NO_SCREENSHOT"
  end
  local loaded, native = pcall(require, "nkvision_native")
  if not loaded or type(native) ~= "table"
      or type(native.open) ~= "function"
      or type(native.tempPath) ~= "function" then
    return nil, "Vision Core native module unavailable", "NO_VISION"
  end

  -- This path is an exclusive, mode-0600 reservation made by mkstemps.
  -- It cannot collide with another script/process launched this second.
  local pathOK, path, pathErr, pathCode = pcall(native.tempPath)
  if not pathOK then return nil, tostring(path), "FRAME_IO" end
  if type(path) ~= "string" or path == "" then
    return nil, pathErr or "cannot create screenshot path", pathCode or "FRAME_IO"
  end

  local shotOK, shot, err, code = pcall(nk.screenshot, path)
  if not shotOK or not shot or shot ~= path then
    local cleaned, cleanErr = cleanup(path)
    if not cleaned then
      return nil, "capture failed; cleanup failed: "..cleanErr, "CLEANUP"
    end
    if not shotOK then return nil, tostring(shot), "CAPTURE" end
    if shot ~= nil and shot ~= path then
      return nil, "screenshot returned unexpected path", "CAPTURE"
    end
    return nil, err or "screen capture failed", code or "CAPTURE"
  end

  local ok, frame, openErr, openCode = pcall(native.open, path)
  local removed, removeErr = cleanup(path)
  if not removed then
    if ok and frame and type(frame.close) == "function" then
      pcall(frame.close, frame)
    end
    return nil, "cannot remove temporary screenshot: "..removeErr, "CLEANUP"
  end
  if not ok then return nil, tostring(frame), "DECODE" end
  if not frame then
    return nil, openErr or "cannot open screenshot frame", openCode or "DECODE"
  end
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
