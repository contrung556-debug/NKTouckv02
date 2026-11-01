-- NKTouch v0.6.3 direct native Lua compatibility/helper API
-- SPDX-License-Identifier: GPL-3.0-or-later
local M={}
M.VERSION="0.6.3"
M.NATIVE_VERSION="0.6.0"
M.LUA_VERSION="5.4.9"

local CTL="/var/jb/usr/bin/nktouchctl"
local okCore,core=pcall(require,"nkcore")
if not okCore or type(core)~="table" or not core.DIRECT then core=nil end
M.DIRECT=core~=nil
M.CORE_VERSION=core and core.VERSION or nil

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
    if a then return true, tonumber(c) or 0 end
    return false, tonumber(c) or 1
  end
  if type(a)=="number" then return a==0, a end
  if a==nil then return false, tonumber(c) or 1 end
  return a==true, tonumber(c) or 0
end

local function run(parts)
  local a,b,c=os.execute(command(parts))
  return status_ok(a,b,c)
end

local function capture(parts)
  local p=io.popen(command(parts).." 2>/dev/null","r")
  if not p then return nil,"spawn-failed" end
  local out=p:read("*a") or ""
  local a,b,c=p:close()
  local ok,code=status_ok(a,b,c)
  out=out:gsub("[\r\n]+$","")
  if not ok then return nil,code end
  return out,0
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

local function coreWait(timeoutMs,intervalMs,probe)
  local timeout=math.max(0,tonumber(timeoutMs) or 0)
  local interval=math.max(1,tonumber(intervalMs) or 200)
  local deadline=core.nowMs()+timeout
  repeat
    local value,err=probe()
    if value then return value end
    if core.nowMs()>=deadline then return nil,"timeout" end
    core.sleep(interval)
  until false
end

function M.isDirect() return M.DIRECT end
function M.coreVersion() return M.CORE_VERSION end

-- Status/diagnostic helpers intentionally remain shell-backed because they manage runtime files.
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

function M.tap(x,y)
  if core then return core.tap(x,y,45) end
  return run({"tap",x,y})
end
function M.hold(x,y,ms)
  if core then return core.hold(x,y,ms or 500) end
  return run({"hold",x,y,ms or 500})
end
function M.swipe(x1,y1,x2,y2,ms)
  if core then return core.swipe(x1,y1,x2,y2,ms or 400) end
  return run({"swipe",x1,y1,x2,y2,ms or 400})
end
function M.openApp(id)
  if core then return core.openApp(id) end
  return run({"openapp",id})
end
function M.waitApp(id,t,i)
  if core then
    return coreWait(t or 5000,i or 200,function()
      local fg=core.foreground()
      if fg==id then return true end
      return nil
    end)
  end
  local p={"wait-app",id,t or 5000}; if i then p[#p+1]=i end; return run(p)
end
function M.sleep(ms)
  if core then return core.sleep(ms or 0) end
  return run({"sleep",ms or 0})
end
function M.recordStart()
  if core then return core.recordStart() end
  return run({"record","start"})
end
function M.recordStop()
  if core then return core.recordStop() end
  return run({"record","stop"})
end
function M.stop()
  if core then return core.stop() end
  return run({"stop"})
end
function M.ping()
  if core then return core.ping() end
  return run({"ping"})
end

function M.text(t)
  if core then return core.text(t or "") end
  return run({"text",t or ""})
end
M.inputText=M.text
function M.showKeyboard()
  if core then return core.keyboard(true) end
  return run({"keyboard","show"})
end
function M.hideKeyboard()
  if core then return core.keyboard(false) end
  return run({"keyboard","hide"})
end
function M.moveCursor(o)
  if core then return core.cursor(tonumber(o) or 0) end
  return run({"cursor",tonumber(o) or 0})
end
function M.delete(c)
  if core then return core.delete(tonumber(c) or 1) end
  return run({"delete",tonumber(c) or 1})
end
function M.paste(t)
  if core then return core.paste(t or "") end
  return run({"paste",t or ""})
end
function M.getClipboard()
  if core then return core.getClipboard() end
  return capture({"clipboard-get"})
end
function M.setClipboard(t)
  if core then return core.setClipboard(t or "") end
  return run({"clipboard-set",t or ""})
end

function M.toast(kind,message,seconds)
  if core then return core.toast(kind or "message",seconds or 2,message or "") end
  return run({"toast",kind or "message",seconds or 2,message or ""})
end
function M.hideToast()
  if core then return core.hideToast() end
  return run({"toast","hide"})
end
function M.screenshot(path)
  if core then return core.screenshot(path) end
  local p={"screenshot"}; if path then p[#p+1]=path end; return capture(p)
end

function M.findImage(path,maxTry,confidence,scale)
  if core then return core.findImage(path,maxTry or 2,confidence or 0.8,scale or 0.8) end
  local p={"find-image",path}
  if maxTry or confidence or scale then p[#p+1]=maxTry or 2; p[#p+1]=confidence or 0.8; p[#p+1]=scale or 0.8 end
  return splitRect(capture(p))
end
function M.waitImage(path,t,i,c)
  if core then
    return coreWait(t or 5000,i or 250,function()
      local hit=core.findImage(path,2,c or 0.8,0.8)
      return hit
    end)
  end
  local p={"wait-image",path,t or 5000}; if i or c then p[#p+1]=i or 250 end; if c then p[#p+1]=c end
  return splitRect(capture(p))
end
function M.tapImage(path,t,i,c)
  if core then
    local hit,err=M.waitImage(path,t,i,c)
    if not hit then return nil,err end
    return core.tap(hit.x+hit.width/2,hit.y+hit.height/2,45)
  end
  local p={"tap-image",path,t or 5000}; if i or c then p[#p+1]=i or 250 end; if c then p[#p+1]=c end
  return run(p)
end

function M.getColor(x,y)
  if core then return core.getColor(x,y) end
  return splitColor(capture({"pixel",x,y}),false)
end
function M.findColor(x,y,w,h,rmin,rmax,gmin,gmax,bmin,bmax,skip)
  if core then return core.findColor(x,y,w,h,rmin,rmax,gmin,gmax,bmin,bmax,skip or 0) end
  local p={"find-color",x,y,w,h,rmin,rmax,gmin,gmax,bmin,bmax}; if skip then p[#p+1]=skip end
  return splitColor(capture(p),true)
end
function M.waitColor(x,y,w,h,rmin,rmax,gmin,gmax,bmin,bmax,t,i,skip)
  if core then
    return coreWait(t or 5000,i or 200,function()
      return core.findColor(x,y,w,h,rmin,rmax,gmin,gmax,bmin,bmax,skip or 0)
    end)
  end
  local p={"wait-color",x,y,w,h,rmin,rmax,gmin,gmax,bmin,bmax,t or 5000}; if i or skip then p[#p+1]=i or 200 end; if skip then p[#p+1]=skip end
  return splitColor(capture(p),true)
end
function M.tapColor(x,y,w,h,rmin,rmax,gmin,gmax,bmin,bmax,t,i,skip)
  if core then
    local hit,err=M.waitColor(x,y,w,h,rmin,rmax,gmin,gmax,bmin,bmax,t,i,skip)
    if not hit then return nil,err end
    return core.tap(hit.x,hit.y,45)
  end
  local p={"tap-color",x,y,w,h,rmin,rmax,gmin,gmax,bmin,bmax,t or 5000}; if i or skip then p[#p+1]=i or 200 end; if skip then p[#p+1]=skip end
  return run(p)
end

function M.ocr(x,y,w,h,languages)
  if core then return core.ocr(x,y,w,h,languages or "") end
  local p={"ocr",x,y,w,h}; if languages then p[#p+1]=languages end; return capture(p)
end
function M.waitText(x,y,w,h,needle,t,i,languages)
  if core then
    needle=tostring(needle or "")
    return coreWait(t or 5000,i or 300,function()
      local text=core.ocr(x,y,w,h,languages or "")
      if text and text:find(needle,1,true) then return text end
      return nil
    end)
  end
  local p={"wait-text",x,y,w,h,needle,t or 5000}; if i or languages then p[#p+1]=i or 300 end; if languages then p[#p+1]=languages end
  return capture(p)
end

function M.screen() if core then return core.screen() end; return capture({"screen"}) end
function M.foreground() if core then return core.foreground() end; return capture({"foreground"}) end
function M.orientation() if core then return core.orientation() end; return capture({"orientation"}) end
function M.scale() if core then return core.scale() end; return capture({"scale"}) end
function M.device() if core then return core.device() end; return capture({"device"}) end
function M.battery() if core then return core.battery() end; return capture({"battery"}) end
function M.runtime() if core then return core.runtime() end; return capture({"runtime"}) end
function M.backend() return capture({"backend"}) end
function M.runScript(path,...)
  local p={"run",path}
  for _,v in ipairs({...}) do p[#p+1]=v end
  return run(p)
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
    local c=M.getColor(x,y)
    if not c then return nil end
    return c.packed or (c.red*65536+c.green*256+c.blue)
  end
  return true
end

return M
