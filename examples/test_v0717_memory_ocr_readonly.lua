-- NKTouch v0.7.17 read-only Vision/Memory stress probe.
-- No taps, no InputText, no app switching, no cleanup of other apps.
-- Intended for ON-DEVICE beta validation, not a background service.
local nk=require("nktouch_v7")
local mem=require("nkmemory")
local LOOPS=30 -- manual 30-frame test; increase to max 100 if device is stable
local INTERVAL_MS=250
assert(LOOPS>=1 and LOOPS<=100,"LOOPS must be 1..100")
pcall(function() io.stdout:setvbuf("no") end)
local function say(key,value)
  print("[NK171]["..key.."] "..tostring(value))
  pcall(function()io.stdout:flush()end)
end
local function snapshot()
  local m,err,code=mem.stats()
  if not m then
    say("MEM_ERROR",tostring(code or err))
    return nil
  end
  say("MEM",string.format("Lua=%.1fKiB RSS=%s",m.lua_kb,
        tostring(m.process_rss_bytes or "not available")))
  return m
end
local before=snapshot()
local counts={ok=0,ocr_ok=0,ocr_err=0,error=0}
for i=1,LOOPS do
  local data,err,kind=nk.withFrame(function(frame)
    local info=assert(frame:info())
    assert(info.width>0 and info.height>0)
    local initialRgba=info.rgba_bytes or -1
    local initialGray=info.gray_bytes or -1
    local _,ocrErr,ocrCode=frame:ocr(0,0,info.width,
           math.min(info.height,220),"vi-VN")
    local ocrOK=(ocrErr==nil)
    local pixel=frame:getColor(
           math.floor(info.width/2),math.floor(info.height/2))
    local endInfo=assert(frame:info())
    return {
      width=info.width,height=info.height,
      ocr_ok=ocrOK,
      ocr_err=ocrOK and nil or tostring(ocrCode or ocrErr),
      initial_rgba=initialRgba,
      initial_gray=initialGray,
      after_rgba=endInfo.rgba_bytes or -1,
      color_ok=type(pixel)=="table"
    }
  end)
  if not data then
    counts.error=counts.error+1
    say("ERROR",string.format("frame=%d code=%s detail=%s",i,
          tostring(kind),tostring(err)))
    break
  end
  counts.ok=counts.ok+1
  if data.ocr_ok then counts.ocr_ok=counts.ocr_ok+1
  else
    counts.ocr_err=counts.ocr_err+1
    say("OCR_WARN",string.format("#%d %s",i,data.ocr_err))
  end
  if data.initial_rgba~=0 or data.initial_gray~=0
      or data.after_rgba<=0 or not data.color_ok then
    counts.error=counts.error+1
    say("MEM_GUARD",string.format("#%d first=%s/%s afterRGBA=%s",
       i,tostring(data.initial_rgba),tostring(data.initial_gray),
       tostring(data.after_rgba)))
    break
  end
  if i%10==0 then
    say("PROGRESS",i.."/"..LOOPS.." screenshots; OCR_ok="..counts.ocr_ok)
    snapshot()
  end
  if i<LOOPS then nk.sleep(INTERVAL_MS) end
end
local collected,collectErr=mem.release({mode="full"})
if collected then
  say("GC",string.format("Lua %.1f -> %.1f KiB; RSS %s -> %s",
     collected.lua_kb_before,collected.lua_kb_after,
     tostring(collected.process_rss_before),
     tostring(collected.process_rss_after)))
else
  say("GC_WARN",tostring(collectErr))
end
local after=snapshot()
say("SUMMARY",string.format("frames=%d/%d OCR_ok=%d OCR_fail=%d guard_errors=%d",
     counts.ok,LOOPS,counts.ocr_ok,counts.ocr_err,counts.error))
if counts.error~=0 then error("NKTouch v0.7.17 read-only memory/vision validation failed") end
say("DONE","Read-only validation finished; check NKTask exit_code and RSS trend")
