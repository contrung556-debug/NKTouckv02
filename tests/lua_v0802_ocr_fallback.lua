-- Host-only test: simulated OCR outcomes, no screenshots, no device calls.
package.path="./lua/?.lua;"..package.path
package.preload["nkcore"]=function()return {DIRECT=false} end
local nk=require("nktouch")
local frameCalls,liveCalls=0,0
nk.withFrame=function(callback)
  frameCalls=frameCalls+1
  return callback({
    ocr=function()return "FRAME TEXT" end,
    info=function()return {ocr_backend="SERVICE_JPEG_SAME_FRAME"} end,
  })
end
nk.ocr=function()liveCalls=liveCalls+1;return "LIVE TEXT" end
local text,meta=nk.ocrWithFallback(0,0,750,220)
assert(text=="FRAME TEXT" and meta.backend=="SERVICE_JPEG_SAME_FRAME")
assert(meta.same_frame==true and meta.recaptured==false)
assert(frameCalls==1 and liveCalls==0,"a successful frame must not recapture")

nk.withFrame=function(callback)
  frameCalls=frameCalls+1
  return callback({ocr=function()return nil,"CVBuffer failed","OCR" end})
end
text,meta=nk.ocrWithFallback(0,0,750,220)
assert(text=="LIVE TEXT" and meta.backend=="OCR_FALLBACK_LIVE")
assert(meta.same_frame==false and meta.recaptured==true)
assert(meta.frame_error_code=="OCR" and liveCalls==1)
nk.withFrame=function(callback)
  frameCalls=frameCalls+1
  return callback({ocr=function()
    return nil,"Vision OCR failed NSOSStatusErrorDomain:-6662 failed buffer","OCR"
  end})
end
text,meta=nk.ocrWithFallback(0,0,750,220)
assert(text=="LIVE TEXT" and meta.frame_error_osstatus==-6662)
assert(meta.frame_error_code=="OCR" and liveCalls==2)

nk.withFrame=function(callback)
  frameCalls=frameCalls+1
  return callback({ocr=function()return nil,"outside frame","OUT_OF_BOUNDS" end})
end
local bad,msg,kind=nk.ocrWithFallback(0,0,750,220)
assert(bad==nil and kind=="OUT_OF_BOUNDS" and liveCalls==2)

local before=frameCalls
bad,msg,kind=nk.ocrWithFallback(0,nil,750,220)
assert(bad==nil and kind=="INVALID" and frameCalls==before)

nk.withFrame=function()frameCalls=frameCalls+1;return nil,"no camera","FRAME_IO" end
text,meta=nk.ocrWithFallback(0,0,750,220)
assert(text=="LIVE TEXT" and meta.backend=="OCR_FALLBACK_LIVE")
assert(meta.frame_error_code=="FRAME_IO" and liveCalls==3)
print("v0.8.2 OCR fallback provenance: PASS (host mock only)")
