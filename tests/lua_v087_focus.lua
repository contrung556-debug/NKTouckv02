-- NKTouch v0.8.7: native focus queried by bundle, no OCR, no retry.
package.path="lua/?.lua;"..package.path
local pro=require("nkinput_pro")
local cnt={tap=0,input=0,probe=0,app=0,ocr=0}
local app="com.apple.mobilenotes"
local expected=app
local focus=true
local failInput=false
local nk={}
function nk.foreground()
  cnt.app=cnt.app+1
  return app
end
function nk.screen() return "750;;1334" end
function nk.tap(x,y)
  cnt.tap=cnt.tap+1
  assert(x==330 and y==440)
  return true
end
function nk.sleep(ms) return true end
function nk.inputTextV2(text,opts)
  cnt.input=cnt.input+1
  if failInput then error("socket failed after dispatch") end
  assert(opts.mode=="direct")
  assert(opts.verify==nil)
  assert(text=="Nguyễn 🌻 123" or text=="test")
  return true,{sent=true}
end
function nk.ocr()
  cnt.ocr=cnt.ocr+1
  error("OCR forbidden in v0.8.7 focus and input")
end
function nk.focusedInput(bundle)
  cnt.probe=cnt.probe+1
  assert(bundle==expected,"native probe must receive target bundle")
  if focus=="unknown" then return nil,"native timeout","FOCUS_PROBE_UNAVAILABLE" end
  if focus=="raise" then error("native probe exception") end
  return focus
end
local function options(key)
  return {bundle=expected,focus={x=330,y=440},settleMs=0,
          onceKey=key,requireFocusProof=true}
end
local ok,receipt,code=pro.safe(nk,"Nguyễn 🌻 123",options("notes.ready"))
assert(ok and receipt.focus_verified and receipt.foreground_verified)
assert(receipt.status=="DISPATCHED_UNVERIFIED")
assert(cnt.input==1 and cnt.probe==1 and cnt.ocr==0)
-- Duplicate blocks even before an extra tap or focus check.
local t,i,p=cnt.tap,cnt.input,cnt.probe
ok,receipt,code=pro.safe(nk,"Nguyễn 🌻 123",options("notes.ready"))
assert(not ok and code=="DUPLICATE_BLOCKED")
assert(cnt.tap==t and cnt.input==i and cnt.probe==p)

focus=false
ok,receipt,code=pro.safe(nk,"Nguyễn 🌻 123",options("notes.no_focus"))
assert(not ok and code=="FOCUS_NOT_CONFIRMED" and cnt.input==i)
focus="unknown"
ok,receipt,code=pro.safe(nk,"Nguyễn 🌻 123",options("notes.timeout"))
assert(not ok and code=="FOCUS_PROBE_UNAVAILABLE" and cnt.input==i)
focus="raise"
ok,receipt,code=pro.safe(nk,"Nguyễn 🌻 123",options("notes.exception"))
assert(not ok and code=="FOCUS_PROBE_UNAVAILABLE" and cnt.input==i)
focus=true
-- Foreground changes AFTER a successful native focus query: fail closed.
local old=nk.focusedInput
nk.focusedInput=function(bundle) local ans=old(bundle); app="com.apple.mobilesafari"; return ans end
ok,receipt,code=pro.safe(nk,"Nguyễn 🌻 123",options("notes.app_changed"))
assert(not ok and code=="WRONG_APP" and cnt.input==i)
nk.focusedInput=old
app=expected
-- Missing native probe prevents any touch.
nk.focusedInput=nil
t=cnt.tap
ok,receipt,code=pro.safe(nk,"Nguyễn 🌻 123",options("notes.no_bridge"))
assert(not ok and code=="FOCUS_PROBE_UNAVAILABLE" and cnt.tap==t)
nk.focusedInput=old
-- Native dispatch uncertainty: never send second mutation with same key.
failInput=true
ok,receipt,code=pro.safe(nk,"test",options("notes.uncertain"))
assert(not ok and code=="DISPATCH_UNCERTAIN")
t,i,p=cnt.tap,cnt.input,cnt.probe
ok,receipt,code=pro.safe(nk,"test",options("notes.uncertain"))
assert(not ok and code=="DUPLICATE_BLOCKED")
assert(cnt.tap==t and cnt.input==i and cnt.probe==p)
assert(cnt.ocr==0)
print(("[NK087][HOST] PASS focus=yes/no/unknown/exception, app-race, idempotency; native_probes=%d"):format(cnt.probe))
