-- NKTouch v0.8.0 integrated Lua SDK facade.
-- Existing require("nktouch_v7") API behavior is unchanged.
local M={VERSION="0.8.0-beta"}
local snapshot=require("nksnapshot")
local actions=require("nkactions")
local diagnostics=require("nkdiagnostics")
function M.new(opts)
  opts=opts or {}
  if type(opts)~="table" then return nil,"options must be a table","INVALID" end
  local nk=opts.nk or require("nktouch_v7")
  if type(nk)~="table" then
    return nil,"NKTouch native Lua API unavailable","NO_BACKEND"
  end
  local trace=nil
  if opts.trace==true then
    local err,code
    trace,err,code=diagnostics.create({
      persist=opts.persist==true,path=opts.report_path
    })
    if not trace then return nil,err,code end
    local proxied,why,kind=trace:wrap(nk)
    if not proxied then return nil,why,kind end
    nk=proxied
  end
  local sdk={nk=nk,trace=trace,VERSION=M.VERSION}
  function sdk:inspect(plan,options)
    options=options or {}
    if type(options)~="table" then return nil,"invalid options","INVALID" end
    return snapshot.capture(plan,{nk=nk,include_text=options.include_text==true})
  end
  function sdk:waitText(needle,rect,options)
    options=options or {}
    if type(options)~="table" then return nil,"invalid options","INVALID" end
    local forwarded={}
    for k,v in pairs(options) do forwarded[k]=v end
    forwarded.nk=nk
    return snapshot.waitText(needle,rect,forwarded)
  end
  function sdk:waitColor(rect,options)
    options=options or {}
    if type(options)~="table" then return nil,"invalid options","INVALID" end
    local forwarded={}
    for k,v in pairs(options) do forwarded[k]=v end
    forwarded.nk=nk
    return snapshot.waitColor(rect,forwarded)
  end
  function sdk:gesture(options) return actions.gesture(nk,options) end
  function sdk:typeText(options) return actions.typeText(nk,options) end
  function sdk:taskStatus(task,options)
    return diagnostics.readTask(task,options)
  end
  function sdk:report()
    return trace and trace:snapshot() or {status="TRACING_DISABLED"}
  end
  return sdk
end
return M
