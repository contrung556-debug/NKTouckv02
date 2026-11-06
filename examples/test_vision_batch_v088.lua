-- NKTouch 0.8.8 Vision Batch: READ ONLY, exactly one screenshot.
-- Uses same-frame pixel/Color/OCR. OCR text is NOT returned or logged.
local nk=require("nktouch_v7")
local raw,err,code=nk.screen()
if not raw then print("[NKVISION088][SKIP] screen "..tostring(code)); return end
local w,h=raw:match("^(%d+%.?%d*);;(%d+%.?%d*)$")
w,h=tonumber(w),tonumber(h)
if not w or not h then print("[NKVISION088][SKIP] bad pixel geometry"); return end
local width=math.min(w,300)
local height=math.min(h,180)
local result,why,kind=nk.visionBatch({
  pixels={{x=math.floor(w/2),y=math.floor(h/2)},
          {x=math.floor(w/2),y=math.floor(h/2)}},
  ocr={{x=0,y=0,w=width,h=height}},
  colors={{x=0,y=0,w=width,h=height,
           rmin=245,rmax=255,gmin=245,gmax=255,bmin=245,bmax=255}}
})
if not result then
  print("[NKVISION088][FAIL] "..tostring(kind)..": "..tostring(why))
  return
end
print(("[NKVISION088][BATCH] status=%s frames=%d pixel_native=%d cache_hits=%d OCR_calls=%d elapsed_ms=%s"):format(
  result.status,result.metrics.captures,result.metrics.pixel_native_reads,
  result.metrics.pixel_cache_hits,result.metrics.ocr_calls,
  tostring(result.metrics.elapsed_ms)))
-- A same-frame OCR request may still cost time, depending on the backend.
-- Do not print recognized text. No tap / input / network operation here.
