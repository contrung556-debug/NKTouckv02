-- NKTouch v0.7.15 - Gesture transport Self-Test: TAP / HOLD / SWIPE.
-- IMPORTANT: OFF by default. Only run on your OWN disposable test screen.
-- Choose the matching target app in "Ứng dụng +" before pressing Run.
-- Gesture ACK means "command sent", not proof the app handled the touch.
local nk=require("nktouch_v7")

local ENABLE_GESTURES=false    -- Set true only when it is safe to touch.
local EXPECTED_BUNDLE=""       -- Example: com.apple.mobilenotes
local TAP_X,TAP_Y=nil,nil      -- Fill physical SCREEN PIXELS (not points).
local HOLD_X,HOLD_Y=nil,nil
local SWIPE_X1,SWIPE_Y1=nil,nil
local SWIPE_X2,SWIPE_Y2=nil,nil
local HOLD_MS=400
local SWIPE_MS=600

local function emit(status,name,detail)
  print(("[NKTEST][%s] %s %s"):format(status,name,tostring(detail or "")))
end
local function fail(name,message,code)
  emit("FAIL",name,tostring(code or "").." "..tostring(message or ""))
  error("GESTURE_TEST_FAIL: "..name.." "..tostring(message or ""),0)
end
local function check(name,ok,err,code)
  if ok==nil or ok==false then fail(name,err,code) end
  emit("PASS",name,"transport acknowledged")
end
local function screenSize(value)
  local a,b=tostring(value or ""):match("^%s*(%d+%.?%d*)%s*;;%s*(%d+%.?%d*)%s*$")
  local w,h=tonumber(a),tonumber(b)
  if not w or not h or w<200 or h<300 or w>10000 or h>10000 then
    fail("SCREEN_FORMAT","invalid screen dimensions "..tostring(value))
  end
  return math.floor(w+0.5),math.floor(h+0.5)
end
local function point(name,x,y,w,h)
  if type(x)~="number" or x%1~=0 or type(y)~="number" or y%1~=0
      or x<0 or y<0 or x>=w or y>=h then
    fail("CONFIG",name.." needs integer physical pixel coordinates inside "..w.."x"..h)
  end
end

if not ENABLE_GESTURES then
  emit("SKIP","TAP","Set ENABLE_GESTURES=true and fill coordinates to opt in")
  emit("SKIP","HOLD","Disabled by default")
  emit("SKIP","SWIPE","Disabled by default")
  emit("SUMMARY","status=SKIP","no touch events sent")
  return
end
if type(EXPECTED_BUNDLE)~="string" or not EXPECTED_BUNDLE:match("^[%w_.%-]+%.[%w_.%-]+$") then
  fail("CONFIG","EXPECTED_BUNDLE required (select same app in Ứng dụng +)")
end
if type(HOLD_MS)~="number" or HOLD_MS<100 or HOLD_MS>2000
   or type(SWIPE_MS)~="number" or SWIPE_MS<100 or SWIPE_MS>2500 then
  fail("CONFIG","HOLD_MS 100..2000; SWIPE_MS 100..2500")
end
local screen,serr,scode=nk.screen()
if not screen then fail("SCREEN",serr,scode) end
local w,h=screenSize(screen)
point("TAP",TAP_X,TAP_Y,w,h)
point("HOLD",HOLD_X,HOLD_Y,w,h)
point("SWIPE_START",SWIPE_X1,SWIPE_Y1,w,h)
point("SWIPE_END",SWIPE_X2,SWIPE_Y2,w,h)

local current,err,code=nk.foreground()
if not current then fail("FOREGROUND",err,code) end
if current~=EXPECTED_BUNDLE then
  fail("WRONG_APP","expected "..EXPECTED_BUNDLE..", got "..tostring(current))
end
local ready,waitErr,waitCode=nk.waitApp(EXPECTED_BUNDLE,2000,200)
if not ready then fail("WAIT_APP",waitErr,waitCode) end
emit("PASS","PREFLIGHT",("app=%s pixels=%dx%d"):format(current,w,h))

local ok,e,c=nk.tap(TAP_X,TAP_Y)
check("TAP",ok,e,c)
nk.sleep(500)
ok,e,c=nk.hold(HOLD_X,HOLD_Y,HOLD_MS)
check("HOLD",ok,e,c)
nk.sleep(500)
ok,e,c=nk.swipe(SWIPE_X1,SWIPE_Y1,SWIPE_X2,SWIPE_Y2,SWIPE_MS)
check("SWIPE",ok,e,c)
emit("SUMMARY","status=DISPATCHED","3 commands sent; verify UI manually")
