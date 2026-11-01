-- NKTouch v0.6 Lua compatibility/helper API
-- SPDX-License-Identifier: GPL-3.0-or-later
local M={}; M.VERSION="0.6.0"; local CTL="/var/jb/usr/bin/nktouchctl"
local function shq(s) s=tostring(s or ""); return "'"..s:gsub("'","'\\''").."'" end
local function command(parts) local out={}; for i,v in ipairs(parts) do out[i]=shq(v) end; return CTL.." "..table.concat(out," ") end
local function run(parts) return os.execute(command(parts)) end
local function capture(parts) local p=io.popen(command(parts).." 2>/dev/null","r"); if not p then return nil end; local out=p:read("*a") or ""; local ok=p:close(); out=out:gsub("[\r\n]+$",""); if not ok then return nil end; return out end
local function splitRect(s) if not s then return nil end; local x,y,w,h=s:match("^([%-%.%d]+);;([%-%.%d]+);;([%-%.%d]+);;([%-%.%d]+)$"); if not x then return nil end; return {x=tonumber(x),y=tonumber(y),width=tonumber(w),height=tonumber(h)} end
local function splitColor(s,withPos) if not s then return nil end; if withPos then local x,y,r,g,b=s:match("^([%-%.%d]+);;([%-%.%d]+);;([%-%.%d]+);;([%-%.%d]+);;([%-%.%d]+)$"); if not x then return nil end; return {x=tonumber(x),y=tonumber(y),red=tonumber(r),green=tonumber(g),blue=tonumber(b)} else local r,g,b=s:match("^([%-%.%d]+);;([%-%.%d]+);;([%-%.%d]+)$"); if not r then return nil end; return {red=tonumber(r),green=tonumber(g),blue=tonumber(b)} end end
function M.status(p,m) return run({"status",tonumber(p) or 0,m or ""}) end
function M.success(m) return run({"success",m or "Hoàn tất"}) end
function M.warning(m) return run({"warning",m or "Cảnh báo"}) end
function M.error(m) return run({"error",m or "Lỗi"}) end
function M.hide() return run({"hide"}) end
function M.log(m) return run({"log",m or ""}) end
function M.heartbeat() return run({"heartbeat"}) end
function M.doctor() return capture({"doctor"}) end
function M.tap(x,y) return run({"tap",x,y}) end
function M.hold(x,y,ms) return run({"hold",x,y,ms or 500}) end
function M.swipe(x1,y1,x2,y2,ms) return run({"swipe",x1,y1,x2,y2,ms or 400}) end
function M.openApp(id) return run({"openapp",id}) end
function M.waitApp(id,t,i) local p={"wait-app",id,t or 5000}; if i then p[#p+1]=i end; return run(p) end
function M.sleep(ms) return run({"sleep",ms or 0}) end
function M.recordStart() return run({"record","start"}) end
function M.recordStop() return run({"record","stop"}) end
function M.stop() return run({"stop"}) end
function M.ping() return run({"ping"}) end
function M.text(t) return run({"text",t or ""}) end; M.inputText=M.text
function M.showKeyboard() return run({"keyboard","show"}) end
function M.hideKeyboard() return run({"keyboard","hide"}) end
function M.moveCursor(o) return run({"cursor",tonumber(o) or 0}) end
function M.delete(c) return run({"delete",tonumber(c) or 1}) end
function M.paste(t) return run({"paste",t or ""}) end
function M.getClipboard() return capture({"clipboard-get"}) end
function M.setClipboard(t) return run({"clipboard-set",t or ""}) end
function M.toast(kind,message,seconds) return run({"toast",kind or "message",seconds or 2,message or ""}) end
function M.hideToast() return run({"toast","hide"}) end
function M.screenshot(path) local p={"screenshot"}; if path then p[#p+1]=path end; return capture(p) end
function M.findImage(path,maxTry,confidence,scale) local p={"find-image",path}; if maxTry or confidence or scale then p[#p+1]=maxTry or 2; p[#p+1]=confidence or 0.8; p[#p+1]=scale or 0.8 end; return splitRect(capture(p)) end
function M.waitImage(path,t,i,c) local p={"wait-image",path,t or 5000}; if i or c then p[#p+1]=i or 250 end; if c then p[#p+1]=c end; return splitRect(capture(p)) end
function M.tapImage(path,t,i,c) local p={"tap-image",path,t or 5000}; if i or c then p[#p+1]=i or 250 end; if c then p[#p+1]=c end; return run(p) end
function M.getColor(x,y) return splitColor(capture({"pixel",x,y}),false) end
function M.findColor(x,y,w,h,rmin,rmax,gmin,gmax,bmin,bmax,skip) local p={"find-color",x,y,w,h,rmin,rmax,gmin,gmax,bmin,bmax}; if skip then p[#p+1]=skip end; return splitColor(capture(p),true) end
function M.waitColor(x,y,w,h,rmin,rmax,gmin,gmax,bmin,bmax,t,i,skip) local p={"wait-color",x,y,w,h,rmin,rmax,gmin,gmax,bmin,bmax,t or 5000}; if i or skip then p[#p+1]=i or 200 end; if skip then p[#p+1]=skip end; return splitColor(capture(p),true) end
function M.tapColor(x,y,w,h,rmin,rmax,gmin,gmax,bmin,bmax,t,i,skip) local p={"tap-color",x,y,w,h,rmin,rmax,gmin,gmax,bmin,bmax,t or 5000}; if i or skip then p[#p+1]=i or 200 end; if skip then p[#p+1]=skip end; return run(p) end
function M.ocr(x,y,w,h,languages) local p={"ocr",x,y,w,h}; if languages then p[#p+1]=languages end; return capture(p) end
function M.waitText(x,y,w,h,needle,t,i,languages) local p={"wait-text",x,y,w,h,needle,t or 5000}; if i or languages then p[#p+1]=i or 300 end; if languages then p[#p+1]=languages end; return capture(p) end
function M.screen() return capture({"screen"}) end
function M.foreground() return capture({"foreground"}) end
function M.orientation() return capture({"orientation"}) end
function M.scale() return capture({"scale"}) end
function M.device() return capture({"device"}) end
function M.battery() return capture({"battery"}) end
function M.runtime() return capture({"runtime"}) end
function M.backend() return capture({"backend"}) end
function M.runScript(path,...) local p={"run",path}; for _,v in ipairs({...}) do p[#p+1]=v end; return run(p) end
function M.installAutoTouchCompat() _G.setTopStatus=M.status; _G.hideTopStatus=M.hide; _G.tap=M.tap; _G.inputText=M.inputText; _G.log=M.log; _G.usleep=function(us) return M.sleep(math.floor((tonumber(us) or 0)/1000)) end; _G.getColor=function(x,y) local c=M.getColor(x,y); if not c then return nil end; return c.red*65536+c.green*256+c.blue end; return true end
return M
