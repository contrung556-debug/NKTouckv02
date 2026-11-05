-- NKTouch v0.8.0 beta Diagnostics SDK.
-- Opt-in tracing; never records API arguments, typed strings, OCR text,
-- screenshot paths, usernames, passwords or callback return values.
-- A pre-call checkpoint survives a native crash: in_flight=true.
local json=require("nkjson")
local M={VERSION="0.8.0-beta"}
M.DEFAULT_PATH="/var/mobile/Library/NKTouch/tmp/diagnostics-last.json"
local MAX_EVENTS=60
local ALLOW={
  tap=true,hold=true,swipe=true,path=true,inputText=true,inputPassword=true,
  ocr=true,withFrame=true,captureFrame=true,getColor=true,findColor=true,
  matchColor=true,findImage=true,screenshot=true,screen=true,foreground=true,
  ping=true,sleep=true,waitText=true,stress=true
}
local function invalid(msg) return nil,msg,"INVALID" end
local function taskId()
  local v=os.getenv("NKTOUCH_TASK_ID") or ""
  if #v>0 and #v<=64 and v:match("^[A-Za-z0-9_-]+$") then return v end
  return "unknown"
end
local function sanitizeCode(v)
  if type(v)~="string" then return "UNKNOWN" end
  if #v<=48 and v:match("^[A-Za-z0-9_%-]+$") then return v end
  return "OTHER"
end
local function writeAtomic(path,value)
  local encoded,err=json.encode(value)
  if not encoded then return nil,"encode failure: "..tostring(err),"ENCODE" end
  if #encoded>48*1024 then return nil,"report too large","LIMIT" end
  local temp=path..".tmp"
  local f,e=io.open(temp,"wb")
  if not f then return nil,tostring(e),"IO" end
  local success=f:write(encoded)
  local closed=f:close()
  if not success or not closed then
    os.remove(temp)
    return nil,"report write failed","IO"
  end
  local ok,msg=os.rename(temp,path)
  if not ok then os.remove(temp);return nil,tostring(msg),"IO" end
  return true
end
local function boundedPath(path)
  return type(path)=="string" and #path>4 and #path<=512
    and not path:find("[%z\r\n]") and path:sub(-1)~="/"
end
local function record(session,name,state,code)
  local events=session.events
  events[#events+1]={api=name,state=state,code=sanitizeCode(code),seq=session.seq}
  if #events>MAX_EVENTS then table.remove(events,1) end
  session.last_api=name
  session.in_flight=(state=="ENTER")
  session.last_status=state
  session.last_code=sanitizeCode(code)
end
function M.create(opts)
  opts=opts or {}
  if type(opts)~="table" then return invalid("options must be a table") end
  local path=opts.path or M.DEFAULT_PATH
  if not boundedPath(path) then return invalid("invalid output path") end
  local session={
    version=M.VERSION,task_id=taskId(),in_flight=false,
    seq=0,last_api="none",last_status="NEW",events={}
  }
  local self={session=session}
  local persist=opts.persist==true
  function self:checkpoint()
    if not persist then return true end
    return writeAtomic(path,session)
  end
  function self:wrap(nk)
    if type(nk)~="table" then return invalid("NKTouch API table expected") end
    local wrappers={}
    return setmetatable({},{
      __index=function(_,key)
        local raw=nk[key]
        if not ALLOW[key] or type(raw)~="function" then return raw end
        if wrappers[key] then return wrappers[key] end
        wrappers[key]=function(...)
          session.seq=session.seq+1
          record(session,key,"ENTER","IN_FLIGHT")
          local checkpointOK,writeErr,writeCode=self:checkpoint()
          if not checkpointOK then
            -- Never dispatch if durable checkpoint was required but failed.
            return nil,"diagnostics checkpoint failed: "..tostring(writeErr),
                   writeCode or "IO"
          end
          local result=table.pack(pcall(raw,...))
          if not result[1] then
            record(session,key,"EXCEPTION","LUA_EXCEPTION")
            self:checkpoint()
            error(result[2],0)
          end
          if result[2]==nil or result[2]==false then
            record(session,key,"ERROR",result[4])
          else
            record(session,key,"OK","OK")
          end
          self:checkpoint()
          return table.unpack(result,2,result.n)
        end
        return wrappers[key]
      end,
      __newindex=function() error("diagnostics view is read-only",0) end,
      __metatable="NKTouchDiagnostics"
    })
  end
  function self:snapshot()
    local out={version=session.version,task_id=session.task_id,
      in_flight=session.in_flight,last_api=session.last_api,
      last_status=session.last_status,last_code=session.last_code,
      seq=session.seq,events={}}
    for i,e in ipairs(session.events) do
      out.events[i]={api=e.api,state=e.state,code=e.code,seq=e.seq}
    end
    return out
  end
  return self
end
function M.readTask(task,opts)
  opts=opts or {}
  if type(opts)~="table" then return invalid("options must be table") end
  if type(task)~="string" or #task<4 or #task>64 or
      not task:match("^[A-Za-z0-9_-]+$") then
    return invalid("task id must be safe alphanumeric")
  end
  local dir=opts.directory or "/var/mobile/Library/NKTouch/tasks"
  if not boundedPath(dir) then return invalid("invalid task directory") end
  local file=io.open(dir.."/"..task..".state","rb")
  if not file then return nil,"task state unavailable","NOT_FOUND" end
  local raw=file:read(8192)
  file:close()
  local status={id=task,state="unknown",exit_code=nil,signal=nil,
                 duration_seconds=nil}
  local startTime,endTime
  for key,value in raw:gmatch("([^\r\n=]+)=([^\r\n]*)") do
    if key=="state" and value:match("^[a-z]+$") then status.state=value end
    if key=="signal" or key=="exit_code" or
        key=="started_at" or key=="ended_at" then
      local num=tonumber(value)
      if num and num%1==0 and num>=-1 and num<1e12 then
        if key=="started_at" then startTime=num
        elseif key=="ended_at" then endTime=num
        else status[key]=num end
      end
    end
  end
  if startTime and endTime and endTime>=startTime then
    status.duration_seconds=endTime-startTime
  end
  status.crashed=(status.signal or 0)>0
  status.finished=status.state=="success" or status.state=="failed" or
                  status.state=="stopped" or status.state=="timeout"
  return status
end
return M
