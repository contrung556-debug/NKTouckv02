-- NKTouch v0.8.9 Runtime Reliability (cooperative Lua guard).
-- SPDX-License-Identifier: GPL-3.0-or-later
-- Supplements, NEVER replaces, the existing native nktask supervisor.
-- Cooperatively checks deadlines between calls; cannot interrupt a stuck
-- synchronous native call. Cleanup callbacks run on ordinary Lua completion,
-- not on SIGKILL, process crash or a hard native timeout.
-- DO NOT log callback arguments, results, exceptions or OCR/input text.
local M={VERSION="0.8.9-beta"}
local function fail(code) return nil,"NKTouch runtime: "..code,code end
local function num(v,low,high)
  return type(v)=="number" and v==v and v~=math.huge and v~=-math.huge
     and v>=low and v<=high
end
local function int(v,low,high)
  return num(v,low,high) and v%1==0
end
local function token(v,max)
  return type(v)=="string" and #v>0 and #v<=max and
    v:match("^[a-zA-Z0-9_.%-]+$")~=nil
end
local function safeCode(value)
  if token(value,40) then return value end
  return "UNCLASSIFIED"
end
local function nativeClock()
  local ok,core=pcall(require,"nkcore")
  if ok and type(core)=="table" then
    return core.nowMs,core.sleep
  end
end
local function getTime(clock,start)
  local success,now=pcall(clock)
  if not success or not num(now,0,math.huge) or (start and now<start) then
    return nil
  end
  return now
end
function M.create(opts)
  if opts==nil then opts={} end
  if type(opts)~="table" then return fail("INVALID") end
  local deadline=opts.deadline_ms or 120000
  local steps=opts.max_steps or 100
  local resources=opts.max_resources or 32
  local maxEvents=opts.max_events or 80
  if not int(deadline,100,600000) or not int(steps,1,1000) or
      not int(resources,1,64) or not int(maxEvents,5,120) then
    return fail("INVALID")
  end
  local baseClock,baseSleep=nativeClock()
  local clock=opts.now or baseClock
  local sleep=opts.sleep or baseSleep
  if type(clock)~="function" or type(sleep)~="function" then
    return fail("NO_CLOCK")
  end
  if opts.cancelled~=nil and type(opts.cancelled)~="function" then
    return fail("INVALID")
  end
  local started=getTime(clock)
  if not started then return fail("CLOCK") end
  local state={closed=false,in_flight=false,
               steps=0,started=started,deadline=deadline,
               max_steps=steps,max_resources=resources,
               max_events=maxEvents,events={},
               resources={},keys={},status="READY",last_code="READY",
               cleanup_failures=0}
  local session={}
  local function nowElapsed()
    local current=getTime(clock,started)
    if not current then return nil end
    return current-started
  end
  local function pushEvent(kind,code)
    -- No user-controlled text except a strictly sanitized event category.
    local evt={step=state.steps,kind=kind,status=safeCode(code)}
    state.events[#state.events+1]=evt
    if #state.events>state.max_events then table.remove(state.events,1) end
    state.last_code=evt.status
  end
  function session:checkpoint()
    if state.closed then return fail("CLOSED") end
    local used=nowElapsed()
    if not used then
      state.status="FAILED";pushEvent("check","CLOCK")
      return fail("CLOCK")
    end
    if used>=deadline then
      state.status="TIMEOUT";pushEvent("check","DEADLINE_EXCEEDED")
      return fail("DEADLINE_EXCEEDED")
    end
    if opts.cancelled then
      local success,cancel=pcall(opts.cancelled)
      if not success or (cancel~=true and cancel~=false) then
        state.status="FAILED";pushEvent("check","CANCEL_UNKNOWN")
        return fail("CANCEL_UNKNOWN")
      end
      if cancel then
        state.status="CANCELLED";pushEvent("check","CANCELLED")
        return fail("CANCELLED")
      end
    end
    return true,{elapsed_ms=used,deadline_ms=deadline}
  end
  function session:defer(name,callback)
    if state.closed then return fail("CLOSED") end
    if not token(name,40) or type(callback)~="function" then
      return fail("INVALID")
    end
    if #state.resources>=resources then return fail("RESOURCE_LIMIT") end
    state.resources[#state.resources+1]={name=name,callback=callback}
    return true
  end
  function session:step(kind,callback,options)
    options=options or {}
    if state.closed then return fail("CLOSED") end
    if type(options)~="table" or type(callback)~="function" or
        (kind~="read" and kind~="write") then
      return fail("INVALID")
    end
    if state.steps>=steps then
      state.status="LIMIT";pushEvent("check","STEP_LIMIT")
      return fail("STEP_LIMIT")
    end
    local key=nil
    if kind=="write" then
      key=options.onceKey
      if options.confirmed~=true or not token(key,64) then
        return fail("WRITE_NOT_CONFIRMED")
      end
      if state.keys[key] then
        pushEvent("write","DUPLICATE_BLOCKED")
        return fail("DUPLICATE_BLOCKED")
      end
    elseif options.onceKey~=nil then
      return fail("INVALID")
    end
    local ready,e,c=self:checkpoint()
    if not ready then return nil,e,c end
    -- A mutating action reserves its id BEFORE calling a potentially
    -- ambiguous backend. Never release this key after an exception/timeout.
    if key then state.keys[key]=true end
    state.steps=state.steps+1
    state.in_flight=true
    state.status="RUNNING"
    pushEvent(kind,"DISPATCH_STARTED")
    local result=table.pack(pcall(callback))
    state.in_flight=false
    if not result[1] then
      state.status="FAILED"
      pushEvent(kind,kind=="write" and "DISPATCH_UNCERTAIN" or "CALLBACK_EXCEPTION")
      return fail(kind=="write" and "DISPATCH_UNCERTAIN" or "CALLBACK_EXCEPTION")
    end
    local value=result[2]
    if kind=="write" then
      if value~=true then
        state.status="FAILED";pushEvent(kind,"DISPATCH_UNCERTAIN")
        return fail("DISPATCH_UNCERTAIN")
      end
      state.status="RUNNING";pushEvent(kind,"DISPATCHED_UNVERIFIED")
      -- A backend acknowledgment is not proof that the target app acted.
      return true,{status="DISPATCHED_UNVERIFIED",attempts=1,
                   once_key_reserved=true}
    end
    if value==nil or value==false then
      state.status="FAILED";pushEvent(kind,"READ_FAILED")
      return fail("READ_FAILED")
    end
    state.status="RUNNING";pushEvent(kind,"READ_OK")
    -- Return read results to the caller ONLY. Never store or log them.
    return true,table.unpack(result,2,result.n)
  end
  function session:sleep(ms)
    if state.closed then return fail("CLOSED") end
    if not int(ms,0,10000) then return fail("INVALID") end
    local used=0
    repeat
      local ok,e,c=self:checkpoint()
      if not ok then return nil,e,c end
      if used>=ms then return true end
      local elapsed=nowElapsed()
      if not elapsed then return fail("CLOCK") end
      local remaining=deadline-elapsed
      if remaining<=0 then return fail("DEADLINE_EXCEEDED") end
      local span=math.min(100,ms-used,remaining)
      if span<1 then return fail("DEADLINE_EXCEEDED") end
      local called,ack=pcall(sleep,span)
      if not called or ack~=true then
        state.status="FAILED";pushEvent("sleep","SLEEP_FAILED")
        return fail("SLEEP_FAILED")
      end
      used=used+span
    until used>=ms
    return self:checkpoint()
  end
  function session:snapshot()
    -- Never serializes registered callback, returned values or onceKey.
    local events={}
    for i,v in ipairs(state.events) do
      events[i]={step=v.step,kind=v.kind,status=v.status}
    end
    return {version=M.VERSION,kind="COOPERATIVE_GUARD",
      status=state.status,steps=state.steps,
      max_steps=steps,deadline_ms=deadline,
      elapsed_ms=nowElapsed(),closed=state.closed,
      resources_pending=#state.resources,
      cleanup_failures=state.cleanup_failures,
      in_flight=state.in_flight,last_code=state.last_code,events=events,
      note="Native task supervisor controls hard stop/timeout"}
  end
  function session:finish()
    if state.closed then return fail("CLOSED") end
    state.closed=true
    -- Release in reverse order, exactly once. Cleanup is not guaranteed
    -- on hard kill or a native crash; nktask supervises those separately.
    for i=#state.resources,1,-1 do
      local resource=state.resources[i]
      local ok,ack=pcall(resource.callback)
      if not ok or ack~=true then
        state.cleanup_failures=state.cleanup_failures+1
        pushEvent("cleanup","CLEANUP_FAILED")
      end
      state.resources[i]=nil
    end
    if state.cleanup_failures>0 then
      state.status="FAILED"
      return nil,"NKTouch runtime: CLEANUP_FAILED",
             "CLEANUP_FAILED",self:snapshot()
    end
    if state.status=="READY" or state.status=="RUNNING" then
      state.status="FINISHED"
    end
    return true,self:snapshot()
  end
  function session:run(callback)
    if type(callback)~="function" then return fail("INVALID") end
    local ready,e,c=self:checkpoint()
    if not ready then
      local _,_,_,summary=self:finish()
      return nil,e,c,summary or self:snapshot()
    end
    local performed=table.pack(pcall(callback,self))
    if not performed[1] then
      state.status="FAILED"
      pushEvent("run","CALLBACK_EXCEPTION")
    end
    local completed,final,code,summary=self:finish()
    if not completed then return nil,final,code,summary end
    if not performed[1] then
      return nil,"NKTouch runtime: CALLBACK_EXCEPTION",
             "CALLBACK_EXCEPTION",final
    end
    return true,{status="FINISHED",summary=final},table.unpack(performed,2,performed.n)
  end
  return session
end
function M.run(callback,options)
  if type(callback)~="function" then return fail("INVALID") end
  local session,e,c=M.create(options)
  if not session then return nil,e,c end
  return session:run(callback)
end
return M
