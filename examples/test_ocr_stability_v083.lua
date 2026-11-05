-- NKTouch v0.8.3 opt-in 2-frame stability guard.
-- Run on a safe screen with visible text; do not capture passwords/OTP.
-- This is a 9-point color-change heuristic, not proof a spinner is gone.
local perf=require("nkocr_perf")
local text,meta,code,info=perf.ocrIfStable({
  interval_ms=350,
  tolerance=8,
  roi_height=220
})
if text==nil then
  print("[NKSTABLE] skipped_ocr code="..tostring(code)..
    " max_delta="..tostring(info and info.max_channel_delta or "NA"))
else
  print(("[NKSTABLE] same_frame=%s captures=%d recognized_bytes=%d heuristic=true"):format(
    tostring(meta.backend),meta.captures,#text))
end
-- The recognized words are intentionally never written to task logs.
