-- NKTouch v0.8.3 OCR Performance & Screen Stability Lab
-- Read-only, opt-in. No touch/input/network, private OCR text never logged.
-- SPDX-License-Identifier: GPL-3.0-or-later
local M={VERSION="0.8.3-dev"}

local function integer(v,lo,hi)
  return type(v)=="number" and v==v and v%1==0 and v>=lo and v<=hi
end
local function num(v)
  return type(v)=="number" and v==v and v~=math.huge and v~=-math.huge
end
local function depsFor(deps)
  deps=deps or {}
  local nk=deps.nk or require("nktouch_v7")
  local now=deps.now
  local clock="injected_monotonic_ms"
  if not now then
    local ok,core=pcall(require,"nkcore")
    if ok and type(core)=="table" and type(core.nowMs)=="function" then
      now=core.nowMs
      clock="native_monotonic_ms"
    end
  end
  if type(now)~="function" then
    return nil,nil,nil,"native monotonic clock unavailable","CLOCK_UNAVAILABLE"
  end
  return nk,now,clock
end
local function statistics(values)
  if #values==0 then return nil end
  table.sort(values)
  local sum=0
  for _,v in ipairs(values) do sum=sum+v end
  local function percentile(p)
    return values[math.max(1,math.ceil(#values*p))]
  end
  return {n=#values,min_ms=values[1],mean_ms=math.floor(sum/#values+0.5),
          p50_ms=percentile(0.50),p95_ms=percentile(0.95),
          max_ms=values[#values]}
end
local function sampleFrame(nk,roi)
  local res,e,c=nk.withFrame(function(frame)
    local info,ie,ic=frame:info()
    if not info then return {ok=false,code=ic or "FRAME_INFO"} end
    if not integer(info.width,1,10000) or
       not integer(info.height,1,10000) then
      return {ok=false,code="FRAME_DIMENSIONS"}
    end
    local h=math.min(info.height,roi)
    local text,oe,oc=frame:ocr(0,0,info.width,h,"")
    if text==nil then
      return {ok=false,code=oc or "FRAME_OCR"}
    end
    local after=frame:info()
    local backend=after and after.ocr_backend or "UNKNOWN"
    local supported=backend=="SERVICE_JPEG_SAME_FRAME" or backend=="NATIVE_FRAME"
    return {ok=supported,code=supported and nil or "UNVERIFIED_BACKEND",
            bytes=#tostring(text),backend=backend,
            width=info.width,height=info.height}
  end)
  if not res then return {ok=false,code=c or "FRAME_CAPTURE"} end
  return res
end
local function series(runs,now,fn,pause,sleep)
  local values,errors,empty,backends={}, {}, 0, {}
  for i=1,runs do
    local start=now()
    if not num(start) then return nil,"invalid monotonic clock","CLOCK_INVALID" end
    local ok,result=pcall(fn)
    local finish=now()
    if not num(finish) or finish<start then
      return nil,"clock moved backwards","CLOCK_INVALID"
    end
    if not ok then
      errors[#errors+1]={round=i,code="LUA_EXCEPTION"}
    elseif not result or not result.ok then
      errors[#errors+1]={round=i,code=result and result.code or "EMPTY_RESULT"}
    else
      values[#values+1]=finish-start
      if result.bytes==0 then empty=empty+1 end
      if result.backend then backends[result.backend]=true end
    end
    if i<runs and pause>0 and type(sleep)=="function" then sleep(pause) end
  end
  return {stats=statistics(values),errors=errors,empty_text=empty,backends=backends,
          requested=runs,succeeded=#values,failed=#errors}
end
local function memoryStress(nk,frames)
  if frames==0 then return nil end
  local ok,mem=pcall(require,"nkmemory")
  if not ok or type(mem)~="table" or type(mem.stats)~="function" then
    return {status="SKIP",reason="MEMORY_TELEMETRY_UNAVAILABLE"}
  end
  local start=mem.stats()
  local warm,done=0,0
  local firstError=nil
  for i=1,frames do
    local info,e,c=nk.withFrame(function(frame)
      local meta=frame:info()
      if not meta or not integer(meta.width,1,10000) or
         not integer(meta.height,1,10000) then return nil end
      local pixel=frame:getColor(math.floor(meta.width/2),
                                 math.floor(meta.height/2))
      return pixel and true or nil
    end)
    if not info then firstError=c or "FRAME_STRESS"; break end
    done=done+1
    if i==2 then warm=mem.stats() end
  end
  collectgarbage("collect")
  local finish=mem.stats()
  local warmRSS=warm and warm.process_rss_bytes
  local afterRSS=finish and finish.process_rss_bytes
  return {status=(firstError or done~=frames) and "FAIL" or "PASS",
          code=firstError,frames_done=done,frames_requested=frames,
          rss_delta_bytes=(num(warmRSS) and num(afterRSS))
                          and (afterRSS-warmRSS) or nil,
          lua_before_kb=start and start.lua_kb,
          lua_after_kb=finish and finish.lua_kb,
          note="Lua process RSS only; one run cannot establish a memory leak"}
end

-- Opt-in benchmark. Uses exactly one captured image per frame OCR attempt.
-- Live OCR, when requested, is a separate capture and separate series.
function M.benchmark(opts,deps)
  opts=opts or {}
  if type(opts)~="table" then return nil,"options must be a table","INVALID" end
  local runs=opts.runs or 10
  local warmup=opts.warmup or 2
  local roi=opts.roi_height or 220
  local liveRuns=opts.live_runs or 0
  local frames=opts.memory_frames or 0
  local pause=opts.pause_ms or 0
  if not integer(runs,3,20) or not integer(warmup,0,3) or
     not integer(roi,16,800) or not integer(liveRuns,0,10) or
     (frames~=0 and frames~=10 and frames~=50 and frames~=100) or
     not integer(pause,0,1000) then
    return nil,"runs=3..20, warmup=0..3, roi=16..800, live_runs=0..10, memory_frames=0/10/50/100, pause_ms=0..1000","INVALID"
  end
  local nk,now,clock,e,c=depsFor(deps)
  if not nk then return nil,e,c end
  if type(nk.withFrame)~="function" then
    return nil,"withFrame unavailable","FRAME_UNAVAILABLE"
  end
  local sleep=(deps and deps.sleep) or nk.sleep
  for _=1,warmup do
    sampleFrame(nk,roi) -- ignore warmup success/failure only for timing
  end
  local frame,fe,fc=series(runs,now,function()
    return sampleFrame(nk,roi)
  end,pause,sleep)
  if not frame then return nil,fe,fc end
  local live=nil
  if liveRuns>0 then
    if type(nk.ocr)~="function" then
      return nil,"live OCR unavailable","LIVE_UNAVAILABLE"
    end
    local dimensions,e2,c2=nk.screen()
    local w,h=tostring(dimensions or ""):match("^(%d+%.?%d*);;(%d+%.?%d*)$")
    w,h=tonumber(w),tonumber(h)
    if not integer(w,1,10000) or not integer(h,1,10000) then
      return nil,e2 or "invalid screen dimensions",c2 or "DIMENSIONS"
    end
    live,fe,fc=series(liveRuns,now,function()
      local s,err,code=nk.ocr(0,0,w,math.min(h,roi),"")
      return s and {ok=true,bytes=#tostring(s),backend="LIVE_SEPARATE_CAPTURE"}
            or {ok=false,code=code or "LIVE_OCR"}
    end,pause,sleep)
    if not live then return nil,fe,fc end
  end
  local memory=memoryStress(nk,frames)
  local status=frame.failed==0 and (not live or live.failed==0)
      and (not memory or memory.status~="FAIL") and "PASS" or "FAIL"
  if status=="PASS" and (frame.empty_text>0 or
      (live and live.empty_text>0) or
      (memory and memory.status=="SKIP")) then status="WARN" end
  return {version=M.VERSION,status=status,clock_type=clock,frame=frame,
          live=live,memory=memory,limits={runs=runs,warmup=warmup,
          live_runs=liveRuns,memory_frames=frames},
          note="Do not compare frame/live latency as identical capture paths"}
end

local function signature(frame)
  local info=frame:info()
  if not info or not integer(info.width,1,10000)
      or not integer(info.height,1,10000) then return nil end
  local colors={}
  for _,yf in ipairs({0.20,0.50,0.80}) do
    for _,xf in ipairs({0.20,0.50,0.80}) do
      local x=math.floor((info.width-1)*xf)
      local y=math.floor((info.height-1)*yf)
      local p=frame:getColor(x,y)
      if not p or not integer(p.red,0,255) or
         not integer(p.green,0,255) or not integer(p.blue,0,255) then
        return nil
      end
      colors[#colors+1]={p.red,p.green,p.blue}
    end
  end
  return {width=info.width,height=info.height,colors=colors}
end
local function difference(a,b)
  if not a or not b or a.width~=b.width or a.height~=b.height then
    return math.huge
  end
  local max=0
  for i=1,#a.colors do
    for k=1,3 do
      max=math.max(max,math.abs(a.colors[i][k]-b.colors[i][k]))
    end
  end
  return max
end

-- Two screenshots; OCR is performed on the SECOND captured frame only if
-- sampled pixels are stable. This is a heuristic, NOT a spinner/UI guarantee.
function M.ocrIfStable(opts,deps)
  opts=opts or {}
  if type(opts)~="table" then return nil,"options must be a table","INVALID" end
  local interval=opts.interval_ms or 300
  local tolerance=opts.tolerance or 8
  local roi=opts.roi_height or 220
  if not integer(interval,100,1500) or not integer(tolerance,0,40) or
     not integer(roi,16,800) then
    return nil,"interval_ms=100..1500, tolerance=0..40, roi_height=16..800","INVALID"
  end
  local nk=deps and deps.nk or require("nktouch_v7")
  if type(nk.withFrame)~="function" then
    return nil,"withFrame unavailable","FRAME_UNAVAILABLE"
  end
  local first,e,c=nk.withFrame(signature)
  if not first then return nil,e or "first snapshot failed",c or "FRAME" end
  local sleep=(deps and deps.sleep) or nk.sleep
  if type(sleep)~="function" then return nil,"sleep unavailable","SLEEP" end
  local waited,completed=pcall(sleep,interval)
  if not waited or completed==false or completed==nil then
    return nil,"screen sampling interval failed","SLEEP"
  end
  local second,e2,c2=nk.withFrame(function(frame)
    local sig=signature(frame)
    if not sig then return {ok=false,code="SIGNATURE"} end
    local delta=difference(first,sig)
    if delta>tolerance then
      return {ok=false,code="SCREEN_UNSTABLE",max_delta=delta}
    end
    local s,err,code=frame:ocr(0,0,sig.width,math.min(sig.height,roi),"")
    if s==nil then return {ok=false,code=code or "FRAME_OCR"} end
    local info=frame:info()
    return {ok=true,text=s,backend=info and info.ocr_backend,
            max_delta=delta}
  end)
  if not second then return nil,e2 or "second snapshot failed",c2 or "FRAME" end
  if not second.ok then
    return nil,"screen pixel samples changed or OCR unavailable",
      second.code,{max_channel_delta=second.max_delta}
  end
  if second.backend~="SERVICE_JPEG_SAME_FRAME" and
     second.backend~="NATIVE_FRAME" then
    return nil,"same-frame backend unverified","UNVERIFIED_BACKEND"
  end
  return second.text,{backend=second.backend,stable_sample=true,
    captures=2,ocr_capture=2,max_channel_delta=second.max_delta,
    heuristic=true}
end

function M.printReport(result)
  if type(result)~="table" then return false end
  local f=result.frame or {}
  local s=f.stats or {}
  print(("[NKPERF] version=%s status=%s clock=%s frame_pass=%d/%d frame_p50=%s frame_p95=%s frame_mean=%s"):format(
    result.version,result.status,result.clock_type,f.succeeded or 0,
    f.requested or 0,tostring(s.p50_ms or "NA"),tostring(s.p95_ms or "NA"),
    tostring(s.mean_ms or "NA")))
  if result.live then
    local live=result.live
    print(("[NKPERF] live_separate_capture_pass=%d/%d p50=%s p95=%s"):format(
      live.succeeded,live.requested,tostring(live.stats and live.stats.p50_ms or "NA"),
      tostring(live.stats and live.stats.p95_ms or "NA")))
  end
  if result.memory then
    print(("[NKPERF] memory_frames=%d/%d status=%s rss_delta_bytes=%s"):format(
      result.memory.frames_done or 0,result.memory.frames_requested or 0,
      result.memory.status,tostring(result.memory.rss_delta_bytes or "NA")))
  end
  return true
end
return M
