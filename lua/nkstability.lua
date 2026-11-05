-- NKTouch 0.7.16-dev: safe bounded polling for READ-ONLY probes.
-- Not a generic retry wrapper for tap, inputText, swipe, POST or other
-- side-effecting operations. Caller MUST opt in to the read-only contract.
local M={VERSION="0.7.16-dev"}
local TRANSIENT={TIMEOUT=true,CONNECT=true,TRANSPORT=true}
local function finite(n) return type(n)=="number" and n==n and n~=math.huge and n~=-math.huge end
local function ms(n,lo,hi) return finite(n) and n%1==0 and n>=lo and n<=hi end
local function invalid(s) return nil,s,"INVALID" end
local function timeFn()
  local ok,core=pcall(require,"nkcore")
  if ok and type(core)=="table" and type(core.nowMs)=="function" and
     type(core.sleep)=="function" then
    return core.nowMs,core.sleep
  end
end
function M.pollRead(probe,opts)
  opts=opts or {}
  if type(probe)~="function" or type(opts)~="table" then
    return invalid("read-only probe and options table required")
  end
  if opts.read_only~=true then
    return invalid("pollRead requires explicit read_only=true")
  end
  local attempts=opts.max_attempts or 5
  local timeout=opts.timeout_ms or 3000
  local interval=opts.interval_ms or 200
  if not ms(attempts,1,20) or not ms(timeout,0,300000) or not ms(interval,1,10000) then
    return invalid("attempts / timeout / poll interval outside bounds")
  end
  local nativeNow,nativeSleep=timeFn()
  local now=opts.now or nativeNow
  local sleep=opts.sleep or nativeSleep
  if type(now)~="function" or type(sleep)~="function" then
    return nil,"monotonic native clock and sleep required","NO_CLOCK"
  end
  local start=now()
  if not finite(start) then return invalid("clock must return finite milliseconds") end
  local count=0
  local lastErr,lastCode="probe not yet attempted","TIMEOUT"
  local function elapsed()
    local t=now()
    if not finite(t) or t<start then return nil end
    return t-start
  end
  while count<attempts do
    local used=elapsed()
    if not used then return nil,"monotonic clock regressed","CLOCK" end
    if count>0 and used>=timeout then break end
    count=count+1
    local ok,value,err,code=pcall(probe,count)
    if not ok then
      return nil,"read-only probe raised: "..tostring(value),"PROBE",
        {attempts=count,elapsed_ms=elapsed() or 0}
    end
    if value~=nil and value~=false then
      return value,{attempts=count,elapsed_ms=elapsed() or 0}
    end
    lastErr,lastCode=tostring(err or "read-only probe returned no result"),code or "UNKNOWN"
    if not (TRANSIENT[lastCode] or
      (lastCode=="NOT_FOUND" and opts.retry_not_found==true)) then
      return nil,lastErr,lastCode,{attempts=count,elapsed_ms=elapsed() or 0}
    end
    if count>=attempts then break end
    local spent=elapsed()
    if not spent then return nil,"monotonic clock regressed","CLOCK" end
    local remaining=timeout-spent
    if remaining<=0 then break end
    local delay=math.min(interval,remaining)
    local slept,sleepErr,sleepCode=sleep(delay)
    if not slept then
      return nil,"poll sleep failed: "..tostring(sleepErr),sleepCode or "SLEEP",
             {attempts=count,elapsed_ms=elapsed() or 0}
    end
  end
  return nil,lastErr,lastCode,
         {attempts=count,elapsed_ms=elapsed() or 0,exhausted=true}
end

function M.sampleRead(probe,opts)
  opts=opts or {}
  if type(probe)~="function" or type(opts)~="table" or opts.read_only~=true then
    return invalid("sampleRead requires a function and read_only=true")
  end
  local count=opts.count or 5
  if not ms(count,1,30) then return invalid("count must be 1..30") end
  local nativeNow=timeFn()
  local now=opts.now or nativeNow
  if type(now)~="function" then return nil,"monotonic clock needed","NO_CLOCK" end
  local samples={}
  for i=1,count do
    local start=now()
    if not finite(start) then return invalid("clock invalid") end
    local ok,result,err,code=pcall(probe,i)
    local stop=now()
    if not finite(stop) or stop<start then return nil,"clock regressed","CLOCK" end
    if not ok then return nil,"probe raised: "..tostring(result),"PROBE" end
    if result==nil or result==false then
      return nil,tostring(err or "read failed"),code or "READ"
    end
    samples[#samples+1]=stop-start
  end
  table.sort(samples)
  local sum=0
  for _,n in ipairs(samples) do sum=sum+n end
  return {checks=count,min_ms=samples[1],max_ms=samples[count],
          avg_ms=sum/count,p95_ms=samples[math.ceil(count*.95)]}
end
return M
