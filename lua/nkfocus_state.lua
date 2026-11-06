-- NKTouch v0.8.12 stable native input-focus state gate.
-- Read-only: this module never taps, types, launches apps, or logs input text.
-- SPDX-License-Identifier: GPL-3.0-or-later
local M={VERSION="0.8.12-beta"}

local function fail(message,code,detail) return nil,message,code,detail end
local function integer(v,lo,hi)
  return type(v)=="number" and v==v and v%1==0 and v>=lo and v<=hi
end
local function monotonic()
  local ok,core=pcall(require,"nkcore")
  if ok and type(core)=="table" and type(core.nowMs)=="function" then return core.nowMs end
  return nil
end
local function compile(options)
  if type(options)~="table" then return nil,"options table required","INVALID" end
  local allowed={bundle=true,stable_reads=true,max_reads=true,interval_ms=true,
    timeout_ms=true,now=true,sleep=true}
  for key in pairs(options) do if not allowed[key] then return nil,"unknown option","INVALID" end end
  local bundle=options.bundle
  if type(bundle)~="string" or #bundle<3 or #bundle>180
      or not bundle:match("^[%w%._%-]+$") or not bundle:find("%.") then
    return nil,"valid target bundle ID required","INVALID"
  end
  local stable=options.stable_reads or 2
  local maximum=options.max_reads or 8
  local interval=options.interval_ms or 250
  local timeout=options.timeout_ms or 4000
  if not integer(stable,2,4) or not integer(maximum,stable,16)
      or not integer(interval,100,1500)
      or not integer(timeout,200,15000) then
    return nil,"stable_reads 2..4, max_reads stable..16, interval 100..1500, timeout 200..15000","INVALID"
  end
  local now=options.now or monotonic()
  if type(now)~="function" then return nil,"monotonic clock unavailable","NO_CLOCK" end
  local sleep=options.sleep
  if sleep==nil then sleep=function(ms) return require("nktouch_v7").sleep(ms) end end
  if type(sleep)~="function" then return nil,"sleep callback required","NO_SLEEP" end
  return {bundle=bundle,stable=stable,maximum=maximum,interval=interval,
    timeout=timeout,now=now,sleep=sleep}
end

function M.waitFor(nk,options)
  if type(nk)~="table" or type(nk.focusedInput)~="function" then
    return fail("native UIKit focus probe unavailable","FOCUS_PROBE_UNAVAILABLE")
  end
  local cfg,err,code=compile(options)
  if not cfg then return nil,err,code end
  local function clock()
    local ok,value=pcall(cfg.now)
    if not ok or not integer(value,0,math.huge) then return nil end
    return value
  end
  local start=clock()
  if not start then return fail("invalid monotonic clock","CLOCK") end
  local function elapsed()
    local current=clock()
    if not current or current<start then return nil end
    return current-start
  end

  local reads,stable=0,0
  while reads<cfg.maximum do
    local spent=elapsed()
    if not spent then return fail("monotonic clock failed or regressed","CLOCK") end
    if reads>0 and spent>=cfg.timeout then break end
    reads=reads+1
    local called,focused,focusErr,focusCode=pcall(nk.focusedInput,cfg.bundle)
    if not called then return fail("native focus query raised an error","FOCUS") end
    if focused~=true and focused~=false then
      return fail("native focus query was unconfirmed",
        focusCode or "FOCUS_PROBE_UNAVAILABLE",
        {reads=reads,error=tostring(focusErr or ""):sub(1,96)})
    end
    stable=focused and (stable+1) or 0
    local afterRead=elapsed()
    if not afterRead then return fail("monotonic clock failed or regressed","CLOCK") end
    if stable>=cfg.stable and afterRead<cfg.timeout then
      return {status="PASS",state="FOCUSED",bundle=cfg.bundle,reads=reads,
        stable_reads=stable,elapsed_ms=afterRead}
    end
    if reads<cfg.maximum then
      local used=elapsed()
      if not used then return fail("monotonic clock failed or regressed","CLOCK") end
      local remaining=cfg.timeout-used
      if remaining<=0 then break end
      local delay=math.min(cfg.interval,remaining)
      local sleptOK,slept=pcall(cfg.sleep,delay)
      if not sleptOK or slept~=true then
        return fail("bounded focus wait sleep failed","SLEEP",{reads=reads})
      end
    end
  end
  return fail("first responder did not stabilize before the read/time limit",
    "FOCUS_UNSTABLE",{reads=reads,stable_reads=stable,elapsed_ms=elapsed(),
      action_taken=false})
end
return M
