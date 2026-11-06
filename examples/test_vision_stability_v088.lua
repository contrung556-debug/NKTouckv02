-- NKTouch 0.8.8 Stable-Screen Gate: READ ONLY, bounded.
-- A 4x4+selected-pixels heuristic cannot prove spinners stopped.
-- Same second frame is reused for OCR ONLY IF sampled colors stabilize.
local nk=require("nktouch_v7")
local raw,err,code=nk.screen()
if not raw then print("[NKVISION088][SKIP] screen "..tostring(code)); return end
local w,h=raw:match("^(%d+%.?%d*);;(%d+%.?%d*)$")
w,h=tonumber(w),tonumber(h)
if not w or not h then print("[NKVISION088][SKIP] invalid screen"); return end
local result,why,kind,detail=nk.visionWhenStable({
  ocr={{x=0,y=0,w=math.min(w,300),h=math.min(h,180)}}
},{
  stable_frames=3,max_captures=6,interval_ms=250,
  timeout_ms=3500,tolerance=6,
  watch_points={{x=math.floor(w/2),y=math.floor(h/2)}}
})
if not result then
  print(("[NKVISION088][NOT_STABLE] code=%s captures=%s"):format(
    tostring(kind),tostring(detail and detail.captures)))
  return
end
print(("[NKVISION088][STABLE_SAMPLE] captures=%d reused_last_frame=%s OCR_calls=%d elapsed_ms=%s"):format(
  result.metrics.captures,tostring(result.metrics.reused_last_frame),
  result.metrics.ocr_calls,tostring(result.metrics.elapsed_ms)))
-- Result means sampled pixels were stable, NOT that any particular
-- app transition/spinner/modal has finished. No recognized text logged.
