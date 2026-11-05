-- Host-only deterministic mocks; no iOS, no network, no device mutation.
package.path="lua/?.lua;"..package.path
local perf=require("nkocr_perf")
local frameCount,closed,frameOCR,liveOCR,touchWrites=0,0,0,0,0
local unstable=false
local clock=0
local nk={}
function nk.screen() return "750;;1334" end
function nk.sleep(ms) assert(ms>=0 and ms<=1500); return true end
function nk.tap() touchWrites=touchWrites+1; error("touch must never run") end
function nk.inputText() touchWrites=touchWrites+1; error("input must never run") end
function nk.ocr(x,y,w,h)
  assert(x==0 and y==0 and w==750 and h==220)
  liveOCR=liveOCR+1
  return "LIVE TEXT"
end
function nk.withFrame(cb)
  frameCount=frameCount+1
  local no=frameCount
  local backend="SERVICE_JPEG_SAME_FRAME"
  local f={}
  function f:info()
    return {width=750,height=1334,ocr_backend=backend}
  end
  function f:getColor(x,y)
    assert(x>=0 and y>=0 and x<750 and y<1334)
    local value=20
    if unstable and no%2==0 then value=100 end
    return {red=value,green=5,blue=5}
  end
  function f:ocr(x,y,w,h)
    assert(x==0 and y==0 and w==750 and h==220)
    frameOCR=frameOCR+1
    return "SAME-FRAME TEXT"
  end
  local ok,result=pcall(cb,f)
  closed=closed+1
  if not ok then return nil,result,"MOCK_FRAME_ERROR" end
  return result
end
package.loaded.nkmemory=nil
package.preload.nkmemory=function()
  local index=0
  return {stats=function()
    index=index+1
    return {lua_kb=310+index,
            process_rss_available=true,
            process_rss_bytes=8500000+index*4096}
  end}
end
local function now()
  clock=clock+60
  return clock
end
local report,e,c=perf.benchmark(
  {runs=10,warmup=2,roi_height=220,live_runs=3,memory_frames=10,pause_ms=0},
  {nk=nk,now=now})
assert(report, tostring(e).." "..tostring(c))
assert(report.status=="PASS" and report.clock_type=="injected_monotonic_ms")
assert(report.frame.succeeded==10 and report.frame.failed==0)
assert(report.frame.stats.p50_ms==60 and report.frame.stats.p95_ms==60)
assert(report.live.succeeded==3 and report.live.stats.mean_ms==60)
assert(report.memory.frames_done==10 and report.memory.status=="PASS")
assert(frameCount==22 and closed==22 and frameOCR==12 and liveOCR==3)
assert(touchWrites==0)
assert(perf.printReport(report)==true)

local baseline=frameCount
local text,meta=perf.ocrIfStable({interval_ms=200,tolerance=8,roi_height=220},
  {nk=nk,sleep=nk.sleep})
assert(text=="SAME-FRAME TEXT" and meta.captures==2
       and meta.ocr_capture==2 and meta.stable_sample
       and meta.backend=="SERVICE_JPEG_SAME_FRAME")
assert(frameCount==baseline+2 and frameOCR==13)

unstable=true
baseline=frameOCR
local result,msg,code,info=perf.ocrIfStable({interval_ms=200,tolerance=8},
  {nk=nk,sleep=nk.sleep})
assert(result==nil and code=="SCREEN_UNSTABLE")
assert(info.max_channel_delta==80)
assert(frameOCR==baseline,"must not OCR a changing screen")
local countBeforeSleep=frameCount
local skipped,whySleep,sleepCode=perf.ocrIfStable({interval_ms=200},
  {nk=nk,sleep=function() return false end})
assert(skipped==nil and sleepCode=="SLEEP")
assert(frameCount==countBeforeSleep+1,"sleep failure must not cause a second frame")

local bad,why,err=perf.benchmark({runs=500},{nk=nk,now=now})
assert(bad==nil and err=="INVALID")
bad,why,err=perf.ocrIfStable({interval_ms=50},{nk=nk,sleep=nk.sleep})
assert(bad==nil and err=="INVALID")
assert(touchWrites==0)

-- The same-frame backend must not be silently replaced by live OCR.
local old=nk.withFrame
nk.withFrame=function(fn)
  return old(function(frame)
    frame.info=function() return {width=750,height=1334,
                                   ocr_backend="OCR_FALLBACK_LIVE"} end
    return fn(frame)
  end)
end
local degraded=assert(perf.benchmark({runs=3,warmup=0,live_runs=0},
  {nk=nk,now=now}))
assert(degraded.status=="FAIL" and degraded.frame.failed==3)
assert(degraded.frame.errors[1].code=="UNVERIFIED_BACKEND")
print("[NKPERF][HOST] PASS: sample metrics, real metadata, safe stability, closed frames")
