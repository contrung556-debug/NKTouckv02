-- NKTouch v0.7.17: read-only OCR comparison for device diagnosis.
-- No taps, typing, app switching, screenshots saved, or text content logging.
-- Run this on the device with visible static text on screen.
local nk = require("nktouch_v7")
pcall(function() io.stdout:setvbuf("no") end)

local function log(tag, message)
  print("[NK171_OCR][" .. tag .. "] " .. tostring(message))
  pcall(function() io.stdout:flush() end)
end

local function check(label, call)
  local ran, text, err, code = pcall(call)
  if not ran then
    log("EXCEPTION", label .. " " .. tostring(text))
    return false
  end
  if text == nil then
    log("FAIL", label .. " code=" .. tostring(code) .. " detail=" .. tostring(err))
    return false
  end
  -- Do not print recognized text: it may contain personal information.
  log("PASS", label .. " bytes=" .. #tostring(text)
    .. (text == "" and " (empty text is not an OCR error)" or ""))
  return true
end

local frame, err, code = nk.captureFrame()
if not frame then
  log("CAPTURE_FAIL", tostring(code) .. " " .. tostring(err))
  error("Cannot create immutable Vision frame")
end

local info = assert(frame:info())
local w, h = info.width, info.height
local top = math.min(220, h)
log("FRAME", tostring(w) .. "x" .. tostring(h) .. " top=" .. tostring(top))

local passes = 0
local function probe(label, f)
  if check(label, f) then passes = passes + 1 end
end

probe("frame_auto_top", function() return frame:ocr(0, 0, w, top, "") end)
probe("frame_en_US_top", function() return frame:ocr(0, 0, w, top, "en-US") end)
probe("frame_vi_VN_top", function() return frame:ocr(0, 0, w, top, "vi-VN") end)
probe("frame_auto_full", function() return frame:ocr(0, 0, w, h, "") end)

local closed, closeError = pcall(frame.close, frame)
log("CLOSE", tostring(closed and closeError == true))
frame = nil

-- Legacy live OCR uses the existing on-demand screen service.
-- It might take a new screenshot: this is intentionally one diagnostic probe.
local liveOk = check("live_nk_ocr_auto_top", function()
  return nk.ocr(0, 0, w, top, "")
end)

log("SUMMARY", "frame_pass=" .. tostring(passes) .. "/4 live_pass="
  .. tostring(liveOk) .. " (text content not logged)")
if passes == 0 and liveOk then
  log("HINT", "Frame OCR native Vision path failed while live OCR works")
elseif passes == 0 then
  log("HINT", "Both OCR paths fail; check iOS Vision errors/service availability")
else
  log("HINT", "At least one native OCR mode works; compare language and ROI")
end
log("DONE", "Diagnostic finished; check NKTask exit_code and signal separately")
