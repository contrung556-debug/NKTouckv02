-- NKTouch v0.8.0 integrated SDK demonstration, READ-ONLY.
-- No tap, swipe, keyboard or network. Visible text helps OCR exercise.
local sdk=assert(require("nksdk").new({trace=true,persist=false}))
local nk=sdk.nk
local raw=assert(nk.screen())
local w,h=raw:match("^(%d+%.?%d*);;(%d+%.?%d*)$")
w,h=math.floor(tonumber(w)+0.5),math.floor(tonumber(h)+0.5)
local x,y=math.floor(w/2),math.floor(h/2)
local sample,err,code=sdk:inspect({
  pixels={{x=x,y=y}},
  ocr={{x=0,y=0,w=w,h=math.min(h,220),language=""}},
})
if not sample then
  print(("[NK0800][FAIL] snapshot %s %s"):format(tostring(code),tostring(err)))
  error("Snapshot failed; check Task Center",0)
end
local color=sample.pixels[1]
local ocr=sample.ocr[1]
print(("[NK0800][FRAME] %dx%d count=%d"):format(sample.width,sample.height,sample.frame_count))
print(("[NK0800][COLOR] %s"):format(color.status))
print(("[NK0800][OCR] %s bytes=%s code=%s"):format(ocr.status,tostring(ocr.bytes),tostring(ocr.code)))
local trace=sdk:report()
print(("[NK0800][TRACE] api=%s status=%s"):format(
  tostring(trace.last_api),tostring(trace.last_status)))
print("[NK0800][DONE] readonly demo; check NKTask exit_code and signal")
