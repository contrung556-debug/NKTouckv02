-- NKTouch v0.8.1 same-frame OCR diagnostic, READ ONLY.
-- Keep a screen with visible text at the top. No tap or keyboard action.
local nk=require("nktouch_v7")
local snapshot=assert(nk.captureFrame())
local info=assert(snapshot:info())
local x,y,w,h=0,0,info.width,math.min(info.height,220)
local text,err,code=snapshot:ocr(x,y,w,h,"")
local closed,closeErr=snapshot:close()
assert(closed,closeErr or "frame close failed")
if text==nil then
  print(("[NK0801][FRAME_OCR_FAIL] code=%s detail=%s"):format(
    tostring(code),tostring(err)))
  error("native same-frame OCR is unavailable; no recapture or fake PASS",0)
end
print(("[NK0801][FRAME_OCR_OK] bytes=%d; same screenshot, no interaction"):format(#text))
if #text==0 then
  print("[NK0801][WARN] OCR returned empty text; put readable text on screen")
end
