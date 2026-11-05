-- NKTouch v0.8.0 Touch/Input actions with explicit double opt-in.
-- Separate SDK: does NOT monkeypatch legacy nk.tap/swipe/inputText.
-- Dispatch is never retried; success means "sent", not visually confirmed.
local M={VERSION="0.8.0-beta"}
local function invalid(msg) return nil,msg,"INVALID" end
local function integer(x,min,max)
  return type(x)=="number" and x==x and x%1==0 and x>=min and x<=max
end
local function bounds(nk)
  if type(nk.screen)~="function" then return nil,nil,"screen API unavailable" end
  local raw,e,c=nk.screen()
  if not raw then return nil,nil,tostring(c or e) end
  local w,h=tostring(raw):match("^%s*(%d+%.?%d*)%s*;;%s*(%d+%.?%d*)%s*$")
  w,h=tonumber(w),tonumber(h)
  if not w or not h or not integer(math.floor(w+0.5),200,10000)
       or not integer(math.floor(h+0.5),300,10000) then
    return nil,nil,"invalid physical screen size"
  end
  return math.floor(w+0.5),math.floor(h+0.5)
end
local function foreground(nk,bundle)
  if type(bundle)~="string" or #bundle<3 or #bundle>180
    or not bundle:match("^[%w%._%-]+$") then
    return invalid("matching foreground bundle identifier required")
  end
  if type(nk.foreground)~="function" then
    return nil,"foreground API unavailable","NO_FOREGROUND"
  end
  local actual,e,c=nk.foreground()
  if not actual then return nil,"foreground: "..tostring(c or e),"FOREGROUND" end
  if actual~=bundle then return nil,"foreground app does not match","WRONG_APP" end
  return true
end
local function auth(opts)
  if type(opts)~="table" then return invalid("action options must be a table") end
  if opts.enabled~=true or opts.confirmed~=true then
    return nil,"enabled=true and confirmed=true are both required","NOT_CONFIRMED"
  end
  return true
end
local function point(x,y,w,h)
  return integer(x,0,w-1) and integer(y,0,h-1)
end
local function transport(nk,fn,...)
  if type(nk[fn])~="function" then
    return nil,"input/gesture backend unavailable","NO_BACKEND"
  end
  local executed,value,e,c=pcall(nk[fn],...)
  if not executed then
    return nil,"command raised; delivery uncertain; no retry","DISPATCH_UNCERTAIN"
  end
  if value==nil or value==false then
    return nil,"command not acknowledged; no retry: "..tostring(c or e),
          c or "DISPATCH"
  end
  return true,{sent=true,visually_confirmed=false,status="UNVERIFIED",
               action=fn}
end
function M.preflight(nk,opts)
  local approved,err,code=auth(opts)
  if not approved then return nil,err,code end
  if type(nk)~="table" then return invalid("NKTouch API table required") end
  local on,e,c=foreground(nk,opts.bundle)
  if not on then return nil,e,c end
  local w,h,reason=bounds(nk)
  if not w then return nil,reason,"SCREEN" end
  return {width=w,height=h,bundle=opts.bundle,confirmed=true}
end
function M.gesture(nk,opts)
  local gate,e,c=M.preflight(nk,opts)
  if not gate then return nil,e,c end
  if opts.action=="tap" then
    if not point(opts.x,opts.y,gate.width,gate.height) then
      return invalid("tap must be inside physical screen")
    end
    return transport(nk,"tap",opts.x,opts.y)
  elseif opts.action=="hold" then
    if not point(opts.x,opts.y,gate.width,gate.height)
         or not integer(opts.ms,100,2000) then
      return invalid("hold coordinates or duration invalid")
    end
    return transport(nk,"hold",opts.x,opts.y,opts.ms)
  elseif opts.action=="swipe" then
    if not point(opts.x1,opts.y1,gate.width,gate.height)
        or not point(opts.x2,opts.y2,gate.width,gate.height)
        or not integer(opts.ms,100,2000) then
      return invalid("swipe coordinates or duration invalid")
    end
    return transport(nk,"swipe",opts.x1,opts.y1,opts.x2,opts.y2,opts.ms)
  end
  return invalid("gesture action must be tap, hold or swipe")
end
function M.typeText(nk,opts)
  local gate,e,c=M.preflight(nk,opts)
  if not gate then return nil,e,c end
  local content=opts.text
  if type(content)~="string" or #content<1 or #content>256 or
     content:find("%z") or not utf8.len(content) then
    return invalid("nonsecret text must be valid UTF-8, 1..256 bytes")
  end
  if opts.secure==true then
    return nil,"secure text is not accepted by the diagnostics SDK","SECURE"
  end
  if not point(opts.x,opts.y,gate.width,gate.height) then
    return invalid("focus point must be inside physical screen")
  end
  -- Focus once, check foreground again, send text ONCE. No backspace,
  -- retries or automatic second input if native acknowledgement is ambiguous.
  local tapped,te,tc=transport(nk,"tap",opts.x,opts.y)
  if not tapped then return nil,te,tc end
  local on,fe,fc=foreground(nk,opts.bundle)
  if not on then return nil,"after focus: "..tostring(fe),fc end
  local sent,se,sc=transport(nk,"inputText",content,{})
  if not sent then return nil,se,sc end
  return true,{sent=true,bytes=#content,verified=false,status="UNVERIFIED",
               action="inputText",attempts=1}
end
return M
