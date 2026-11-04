-- NKTouch v0.6.4 hardened direct native Lua API
-- SPDX-License-Identifier: GPL-3.0-or-later
local M={}
M.VERSION="0.6.4"
M.NATIVE_VERSION="0.6.0"
M.LUA_VERSION="5.4.9"

local CTL="/var/jb/usr/bin/nktouchctl"
local okCore,core=pcall(require,"nkcore")
if not okCore or type(core)~="table" or not core.DIRECT then core=nil end
M.DIRECT=core~=nil
M.CORE_VERSION=core and core.VERSION or nil

local retries=tonumber(os.getenv("NKTOUCH_READ_RETRIES") or "2") or 2
retries=math.max(1,math.min(4,math.floor(retries)))

local function shq(s)
  s=tostring(s or "")
  return "'"..s:gsub("'","'\\''").."'"
end

local function command(parts)
  local out={}
  for i,v in ipairs(parts) do out[i]=shq(v) end
  return CTL.." "..table.concat(out," ")
end

local function status_ok(a,b,c)
  if type(a)=="boolean" then
    if a then return true,tonumber(c) or 0 end
    return false,tonumber(c) or 1
  end
  if type(a)=="number" then return a==0,a end
  if a==nil then return false,tonumber(c) or 1 end
  return a==true,tonumber(c) or 0
end

local function run(parts)
  local a,b,c=os.execute(command(parts))
  return status_ok(a,b,c)
end

local function capture(parts)
  local p=io.popen(command(parts).." 2>/dev/null","r")
  if not p then return nil,"spawn-failed","SPAWN" end
  local out=p:read("*a") or ""
  local a,b,c=p:close()
  local ok,code=status_ok(a,b,c)
  out=out:gsub("[\r\n]+$","")
  if not ok then return nil,"command failed: "..tostring(code),"CLI" end
  return out,nil,nil
end

local function classify(err)
  local s=tostring(err or ""):lower()
  if s:find("timeout",1,true) or s:find("timed out",1,true) then return "TIMEOUT",true end
  if s:find("connect",1,true) or s:find("unreachable",1,true) then return "CONNECT",true end
  if s:find("recv",1,true) or s:find("send",1,true) or s:find("broken pipe",1,true) or s:find("reset",1,true) or s:find("empty reply",1,true) then return "TRANSPORT",true end
  if s:find("not found",1,true) or s:find("color not found",1,true) then return "NOT_FOUND",false end
  if s:find("core error",1,true) then return "CORE",false end
  if s:find("invalid",1,true) or s:find("out of range",1,true) then return "INVALID",false end
  return "UNKNOWN",false
end

function M.classifyError(err)
  local code,transient=classify(err)
  return {code=code,transient=transient,message=tostring(err or "")}
end

local function sideCall(name,fn,...)
  local v,err=fn(...)
  if v~=nil and v~=false then return v end
  local code=classify(err)
  return nil,tostring(err or (name.." failed")),code
end

local function readCall(name,fn,...)
  local args={...}
  local lastErr,lastCode
  for attempt=1,retries do
    local v,err=fn(table.unpack(args))
    if v~=nil and v~=false then return v end
    local code,transient=classify(err)
    lastErr=tostring(err or (name.." failed")); lastCode=code
    if not transient or attempt>=retries then break end
    if core and core.sleep then core.sleep(math.min(250,50*attempt)) end
  end
  return nil,lastErr,lastCode
end

local function splitRect(s)
  if not s then return nil end
  local x,y,w,h=s:match("^([%-%.%d]+);;([%-%.%d]+);;([%-%.%d]+);;([%-%.%d]+)$")
  if not x then return nil end
  return {x=tonumber(x),y=tonumber(y),width=tonumber(w),height=tonumber(h)}
end

local function splitColor(s,withPos)
  if not s then return nil end
  if withPos then
    local x,y,r,g,b=s:match("^([%-%.%d]+);;([%-%.%d]+);;([%-%.%d]+);;([%-%.%d]+);;([%-%.%d]+)$")
    if not x then return nil end
    return {x=tonumber(x),y=tonumber(y),red=tonumber(r),green=tonumber(g),blue=tonumber(b),packed=tonumber(r)*65536+tonumber(g)*256+tonumber(b)}
  end
  local r,g,b=s:match("^([%-%.%d]+);;([%-%.%d]+);;([%-%.%d]+)$")
  if not r then return nil end
  return {red=tonumber(r),green=tonumber(g),blue=tonumber(b),packed=tonumber(r)*65536+tonumber(g)*256+tonumber(b)}
end

local function nowMs()
  if core and core.nowMs then return core.nowMs() end
  return math.floor(os.clock()*1000)
end

local function coreWait(timeoutMs,intervalMs,probe)
  local timeout=math.max(0,tonumber(timeoutMs) or 0)
  local interval=math.max(1,tonumber(intervalMs) or 200)
  local deadline=nowMs()+timeout
  local lastErr,lastCode
  repeat
    local value,err,code=probe()
    if value then return value end
    lastErr,lastCode=err,code
    if nowMs()>=deadline then return nil,lastErr or "timeout",lastCode or "TIMEOUT" end
    if core and core.sleep then core.sleep(interval) end
  until false
end

function M.isDirect() return M.DIRECT end
function M.coreVersion() return M.CORE_VERSION end
function M.retryConfig() return retries end

-- Runtime-file helpers remain shell-backed by design.
function M.status(p,m) return run({"status",tonumber(p) or 0,m or ""}) end
function M.success(m) return run({"success",m or "Hoàn tất"}) end
function M.warning(m) return run({"warning",m or "Cảnh báo"}) end
function M.error(m) return run({"error",m or "Lỗi"}) end
function M.hide() return run({"hide"}) end
function M.log(m) return run({"log",m or ""}) end
function M.heartbeat() return run({"heartbeat"}) end
function M.doctor(mode) local p={"doctor"}; if mode then p[#p+1]=mode end; return capture(p) end
function M.selftest() return capture({"selftest"}) end
function M.cleanup() return run({"cleanup"}) end

-- Side-effecting direct calls are intentionally never retried.
function M.tap(x,y) if core then return sideCall("tap",core.tap,x,y,45) end; return run({"tap",x,y}) end
function M.hold(x,y,ms) if core then return sideCall("hold",core.hold,x,y,ms or 500) end; return run({"hold",x,y,ms or 500}) end
function M.swipe(x1,y1,x2,y2,ms) if core then return sideCall("swipe",core.swipe,x1,y1,x2,y2,ms or 400) end; return run({"swipe",x1,y1,x2,y2,ms or 400}) end
-- Preserve continuous finger contact across every move. Never emulate this with
-- several nk.swipe calls: those would lift the finger between segments.
function M.path(points)
  if not core or not core.path then
    return nil,"native continuous path playback unavailable","NO_DIRECT"
  end
  return sideCall("path",core.path,points)
end
function M.openApp(id) if core then return sideCall("openApp",core.openApp,id) end; return run({"openapp",id}) end
function M.sleep(ms) if core then return core.sleep(ms or 0) end; return run({"sleep",ms or 0}) end
function M.recordStart() if core then return sideCall("recordStart",core.recordStart) end; return run({"record","start"}) end
function M.recordStop() if core then return sideCall("recordStop",core.recordStop) end; return run({"record","stop"}) end
function M.stop() if core then return sideCall("stop",core.stop) end; return run({"stop"}) end
function M.ping() if core then return readCall("ping",core.ping) end; return run({"ping"}) end

function M.waitApp(id,t,i)
  if core then
    return coreWait(t or 5000,i or 200,function()
      local fg,err,code=readCall("foreground",core.foreground)
      if fg==id then return true end
      return nil,err,code
    end)
  end
  local p={"wait-app",id,t or 5000}; if i then p[#p+1]=i end; return run(p)
end

function M.text(t) if core then return sideCall("text",core.text,t or "") end; return run({"text",t or ""}) end
M.inputText=M.text
-- v0.7.10 Input Engine v2 is opt-in. No mutation retries: callers must
-- never duplicate a password or field value after an uncertain dispatch.
M.INPUT_VERSION="0.7.10"
function M._inputNativeV2(value,mode)
  if not core or type(core.inputTextV2)~="function" then
    return nil,"Input Engine v2 native transport unavailable","NO_BACKEND"
  end
  return sideCall("inputTextV2",core.inputTextV2,value,mode)
end
function M.inputTextV2(value,options)
  return require("nkinput_v2").input(M,value,options)
end
function M.inputPassword(value,options)
  return require("nkinput_v2").password(M,value,options)
end
function M.showKeyboard() if core then return sideCall("keyboard",core.keyboard,true) end; return run({"keyboard","show"}) end
function M.hideKeyboard() if core then return sideCall("keyboard",core.keyboard,false) end; return run({"keyboard","hide"}) end
function M.moveCursor(o) if core then return sideCall("cursor",core.cursor,tonumber(o) or 0) end; return run({"cursor",tonumber(o) or 0}) end
function M.delete(c) if core then return sideCall("delete",core.delete,tonumber(c) or 1) end; return run({"delete",tonumber(c) or 1}) end
function M.paste(t) if core then return sideCall("paste",core.paste,t or "") end; return run({"paste",t or ""}) end
function M.getClipboard() if core then return readCall("clipboard",core.getClipboard) end; return capture({"clipboard-get"}) end
function M.setClipboard(t) if core then return sideCall("setClipboard",core.setClipboard,t or "") end; return run({"clipboard-set",t or ""}) end

function M.toast(kind,message,seconds) if core then return sideCall("toast",core.toast,kind or "message",seconds or 2,message or "") end; return run({"toast",kind or "message",seconds or 2,message or ""}) end
function M.hideToast() if core then return sideCall("hideToast",core.hideToast) end; return run({"toast","hide"}) end
function M.screenshot(path)
  if core then return readCall("screenshot",core.screenshot,path) end
  local p={"screenshot"}; if path then p[#p+1]=path end; return capture(p)
end

function M.findImage(path,maxTry,confidence,scale)
  if core then return readCall("findImage",core.findImage,path,maxTry or 2,confidence or 0.8,scale or 0.8) end
  local p={"find-image",path}; if maxTry or confidence or scale then p[#p+1]=maxTry or 2; p[#p+1]=confidence or 0.8; p[#p+1]=scale or 0.8 end
  local s,e,c=capture(p); if not s then return nil,e,c end; return splitRect(s)
end
function M.waitImage(path,t,i,c)
  if core then return coreWait(t or 5000,i or 250,function() return M.findImage(path,2,c or 0.8,0.8) end) end
  local p={"wait-image",path,t or 5000}; if i or c then p[#p+1]=i or 250 end; if c then p[#p+1]=c end
  local s,e,code=capture(p); if not s then return nil,e,code end; return splitRect(s)
end
function M.tapImage(path,t,i,c)
  if core then
    local hit,err,code=M.waitImage(path,t,i,c); if not hit then return nil,err,code end
    return sideCall("tapImage",core.tap,hit.x+hit.width/2,hit.y+hit.height/2,45)
  end
  local p={"tap-image",path,t or 5000}; if i or c then p[#p+1]=i or 250 end; if c then p[#p+1]=c end; return run(p)
end

function M.getColor(x,y)
  if core then return readCall("getColor",core.getColor,x,y) end
  local s,e,code=capture({"pixel",x,y}); if not s then return nil,e,code end; return splitColor(s,false)
end
function M.findColor(x,y,w,h,rmin,rmax,gmin,gmax,bmin,bmax,skip)
  if core then return readCall("findColor",core.findColor,x,y,w,h,rmin,rmax,gmin,gmax,bmin,bmax,skip or 0) end
  local p={"find-color",x,y,w,h,rmin,rmax,gmin,gmax,bmin,bmax}; if skip then p[#p+1]=skip end
  local s,e,code=capture(p); if not s then return nil,e,code end; return splitColor(s,true)
end
function M.waitColor(x,y,w,h,rmin,rmax,gmin,gmax,bmin,bmax,t,i,skip)
  if core then return coreWait(t or 5000,i or 200,function() return M.findColor(x,y,w,h,rmin,rmax,gmin,gmax,bmin,bmax,skip or 0) end) end
  local p={"wait-color",x,y,w,h,rmin,rmax,gmin,gmax,bmin,bmax,t or 5000}; if i or skip then p[#p+1]=i or 200 end; if skip then p[#p+1]=skip end
  local s,e,code=capture(p); if not s then return nil,e,code end; return splitColor(s,true)
end

-- v0.7.7 Color API. All inputs use native screenshot pixel coordinates.
-- The same single-frame color engine backs getColor and findColor.
M.COLOR_VERSION="0.7.7"

local function validInteger(value, minimum, maximum)
  local n=tonumber(value)
  if not n or n~=n or n==math.huge or n==-math.huge
     or n%1~=0 or n<minimum or n>maximum then return nil end
  return n
end

local function colorArguments(r,g,b,tolerance)
  local rv=validInteger(r,0,255)
  local gv=validInteger(g,0,255)
  local bv=validInteger(b,0,255)
  local tol=validInteger(tolerance or 0,0,255)
  if not rv or not gv or not bv or not tol then
    return nil,"RGB/tolerance must be integer values from 0 to 255","INVALID"
  end
  return {r=rv,g=gv,b=bv,tolerance=tol}
end

-- Returns false,color for an ordinary color mismatch. Returns nil,error,kind
-- for invalid input/capture failure; never silently converts errors to false.
function M.matchColor(x,y,r,g,b,tolerance)
  if not validInteger(x,0,10000) or not validInteger(y,0,10000) then
    return nil,"invalid pixel coordinates","INVALID"
  end
  local opts,err,kind=colorArguments(r,g,b,tolerance)
  if not opts then return nil,err,kind end
  local color,cerr,ccode=M.getColor(x,y)
  if not color then return nil,cerr,ccode end
  if not validInteger(color.red,0,255) or not validInteger(color.green,0,255)
     or not validInteger(color.blue,0,255) then
    return nil,"invalid RGB returned from color backend","CORE"
  end
  return math.abs(color.red-opts.r)<=opts.tolerance
     and math.abs(color.green-opts.g)<=opts.tolerance
     and math.abs(color.blue-opts.b)<=opts.tolerance,color
end

-- Wait for a pixel matching RGB +/- tolerance within a *pixel* rectangle.
-- Timeout is bounded. Native core scans each captured screen once per poll.
function M.waitColorMatch(r,g,b,tolerance,region,timeoutMs,intervalMs)
  local opts,err,kind=colorArguments(r,g,b,tolerance)
  if not opts then return nil,err,kind end
  if type(region)~="table" then return nil,"region table required","INVALID" end
  local x=validInteger(region.x,0,10000)
  local y=validInteger(region.y,0,10000)
  local w=validInteger(region.w,1,10000)
  local h=validInteger(region.h,1,10000)
  local timeout=validInteger(timeoutMs or 5000,0,300000)
  local interval=validInteger(intervalMs or 200,50,10000)
  if not x or not y or not w or not h or not timeout or not interval then
    return nil,"invalid region/timeout/interval","INVALID"
  end
  local t=opts.tolerance
  return M.waitColor(x,y,w,h,
    math.max(0,opts.r-t),math.min(255,opts.r+t),
    math.max(0,opts.g-t),math.min(255,opts.g+t),
    math.max(0,opts.b-t),math.min(255,opts.b+t),
    timeout,interval,0)
end

function M.tapColor(x,y,w,h,rmin,rmax,gmin,gmax,bmin,bmax,t,i,skip)
  if core then
    local hit,err,code=M.waitColor(x,y,w,h,rmin,rmax,gmin,gmax,bmin,bmax,t,i,skip); if not hit then return nil,err,code end
    return sideCall("tapColor",core.tap,hit.x,hit.y,45)
  end
  local p={"tap-color",x,y,w,h,rmin,rmax,gmin,gmax,bmin,bmax,t or 5000}; if i or skip then p[#p+1]=i or 200 end; if skip then p[#p+1]=skip end; return run(p)
end

function M.ocr(x,y,w,h,languages)
  if core then return readCall("ocr",core.ocr,x,y,w,h,languages or "") end
  local p={"ocr",x,y,w,h}; if languages then p[#p+1]=languages end; return capture(p)
end
function M.waitText(x,y,w,h,needle,t,i,languages)
  if core then
    needle=tostring(needle or "")
    return coreWait(t or 5000,i or 300,function()
      local text,err,code=M.ocr(x,y,w,h,languages or "")
      if text and text:find(needle,1,true) then return text end
      return nil,err,code
    end)
  end
  local p={"wait-text",x,y,w,h,needle,t or 5000}; if i or languages then p[#p+1]=i or 300 end; if languages then p[#p+1]=languages end; return capture(p)
end

function M.screen() if core then return readCall("screen",core.screen) end; return capture({"screen"}) end
function M.foreground() if core then return readCall("foreground",core.foreground) end; return capture({"foreground"}) end
function M.orientation() if core then return readCall("orientation",core.orientation) end; return capture({"orientation"}) end
function M.scale() if core then return readCall("scale",core.scale) end; return capture({"scale"}) end
function M.device() if core then return readCall("device",core.device) end; return capture({"device"}) end
function M.battery() if core then return readCall("battery",core.battery) end; return capture({"battery"}) end
function M.runtime() if core then return readCall("runtime",core.runtime) end; return capture({"runtime"}) end
function M.backend() return capture({"backend"}) end

function M.benchmark(iterations)
  iterations=math.max(1,math.min(100,math.floor(tonumber(iterations) or 20)))
  if not core then return nil,"direct core unavailable","NO_DIRECT" end
  collectgarbage("collect")
  local memBefore=collectgarbage("count")
  local t0=nowMs()
  for _=1,iterations do local v,e,c=M.screen(); if not v then return nil,e,c end end
  local directMs=math.max(1,nowMs()-t0)
  local t1=nowMs()
  for _=1,iterations do local v,e,c=capture({"screen"}); if not v then return nil,e,c end end
  local cliMs=math.max(1,nowMs()-t1)
  collectgarbage("collect")
  local memAfter=collectgarbage("count")
  return {iterations=iterations,direct_ms=directMs,cli_ms=cliMs,direct_per_call_ms=directMs/iterations,cli_per_call_ms=cliMs/iterations,speedup=cliMs/directMs,memory_delta_kb=memAfter-memBefore}
end

function M.stress(iterations)
  iterations=math.max(1,math.min(2000,math.floor(tonumber(iterations) or 100)))
  if not core then return nil,"direct core unavailable","NO_DIRECT" end
  collectgarbage("collect")
  local memBefore=collectgarbage("count")
  local failures,lastErr,lastCode=0,nil,nil
  local start=nowMs()
  for i=1,iterations do
    local v,e,c=M.screen()
    if not v then failures=failures+1; lastErr,lastCode=e,c end
    if i%10==0 then
      local f,fe,fc=M.foreground()
      if not f then failures=failures+1; lastErr,lastCode=fe,fc end
    end
  end
  collectgarbage("collect")
  local elapsed=math.max(1,nowMs()-start)
  local memAfter=collectgarbage("count")
  return {iterations=iterations,failures=failures,elapsed_ms=elapsed,ops_per_sec=(iterations+math.floor(iterations/10))*1000/elapsed,memory_delta_kb=memAfter-memBefore,last_error=lastErr,last_code=lastCode}
end

-- v0.7.9 Vision Core (opt-in; old live-screen functions are unchanged).
-- Capture ONCE, then use frame:getColor/findColor/findImage/ocr/save.
-- JPEG snapshots may differ slightly from the raw RGB Color Engine. Use
-- tolerances if comparing native getColor with a decoded JPEG snapshot.
M.VISION_VERSION="0.7.9"

function M.captureFrame()
  local vision=require("nkvision")
  return vision.capture(M)
end

function M.withFrame(callback)
  local vision=require("nkvision")
  return vision.withFrame(M,callback)
end

function M.runScript(path,...)
  local p={"run",path}; for _,v in ipairs({...}) do p[#p+1]=v end; return run(p)
end

function M.installAutoTouchCompat()
  _G.setTopStatus=M.status
  _G.hideTopStatus=M.hide
  _G.tap=M.tap
  _G.swipe=M.swipe
  _G.inputText=M.inputText
  _G.log=M.log
  _G.usleep=function(us) return M.sleep(math.floor((tonumber(us) or 0)/1000)) end
  _G.sleep=function(sec) return M.sleep(math.floor((tonumber(sec) or 0)*1000)) end
  _G.getColor=function(x,y)
    local c=M.getColor(x,y); if not c then return nil end
    return c.packed or (c.red*65536+c.green*256+c.blue)
  end
  return true
end

return M
