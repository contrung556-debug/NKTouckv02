-- Host-only NKTouch 0.8.5 Input Pro contract. No actual device taps.
package.path="lua/?.lua;"..package.path
local pro=require("nkinput_pro")
assert(pro.VERSION=="0.8.5-beta")
local c={tap=0,input=0,foreground=0,screen=0,sleep=0,ocr=0}
local bundle="com.apple.mobilenotes"
local active=bundle
local changeAfterTap=false
local throwInput=false
local focusReady=true
local modes={}
local typed={}
local nk={}
function nk.foreground()
  c.foreground=c.foreground+1
  return active
end
function nk.screen()
  c.screen=c.screen+1
  return "750;;1334"
end
function nk.tap(x,y)
  c.tap=c.tap+1
  assert(x==350 and y==400)
  if changeAfterTap then active="com.apple.mobilesafari" end
  return true
end
function nk.sleep(ms)
  c.sleep=c.sleep+1
  assert(ms>=0 and ms<=1500)
  return true
end
function nk.inputTextV2(s,opts)
  c.input=c.input+1
  if throwInput then error("native transport failed after dispatch") end
  assert(opts.verify==nil)
  modes[#modes+1]=opts.mode
  typed[#typed+1]=s
  return true,{status="dispatched"}
end
function nk.ocr()
  c.ocr=c.ocr+1
  error("OCR must never run in any Input Pro mode")
end

local unicode="Nguyễn Văn A 🇻🇳\nDòng tiếp;;theo"
local ok,result,code=pro.fast(nk,unicode)
assert(ok and result.sent and not result.verified)
assert(result.mode=="direct" and result.bytes==#unicode)
assert(result.status=="DISPATCHED_UNVERIFIED")
assert(c.input==1 and c.tap==0 and c.ocr==0 and c.screen==0)
assert(modes[1]=="direct" and typed[1]==unicode)

local k,meta=pro.keyboard(nk,"123456",{secure=true})
assert(k and meta.mode=="keyboard" and meta.ocr_used==false)
assert(c.input==2 and modes[2]=="keyboard")

local invalid,why,kind=pro.fast(nk,string.char(255))
assert(invalid==nil and kind=="INVALID" and c.input==2)
invalid,why,kind=pro.fast(nk,"hello",{verify=true})
assert(invalid==nil and kind=="INVALID" and c.input==2)
invalid,why,kind=pro.keyboard(nk,"")
assert(invalid==nil and kind=="INVALID" and c.input==2)

local opts={bundle=bundle,focus={x=350,y=400},onceKey="form.firstname",settleMs=100}
ok,result=pro.safe(nk,unicode,opts)
assert(ok and result.focus_tap_sent and not result.focus_verified)
assert(result.foreground_verified and result.once_key_reserved)
assert(result.attempts==1 and c.input==3 and c.tap==1 and c.sleep==1)
assert(c.foreground==2 and c.ocr==0)

local tapBefore,inputBefore=c.tap,c.input
invalid,why,kind=pro.safe(nk,unicode,opts)
assert(invalid==nil and kind=="DUPLICATE_BLOCKED")
assert(c.tap==tapBefore and c.input==inputBefore)

local beforeUnsafeTap=c.tap
invalid,why,kind=pro.safe(nk,"field",{bundle=bundle,focus={x=350,y=400}})
assert(invalid==nil and kind=="ONCE_KEY_REQUIRED" and c.tap==beforeUnsafeTap)
active="com.apple.mobilesafari"
invalid,why,kind=pro.safe(nk,"field",{bundle=bundle,focus={x=350,y=400},onceKey="form.second"})
assert(invalid==nil and kind=="WRONG_APP")
assert(c.tap==tapBefore and c.input==inputBefore)
active=bundle
local baseline=c.tap
invalid,why,kind=pro.safe(nk,"field",{bundle=bundle,focus={x=350,y=400},
                                       requireFocusProof=true,onceKey="strict.no"})
assert(invalid==nil and kind=="FOCUS_PROBE_UNAVAILABLE" and c.tap==baseline)

nk.focusedInput=function() return focusReady end
ok,result=pro.safe(nk,"field",{bundle=bundle,focus={x=350,y=400},
                              requireFocusProof=true,onceKey="strict.yes",settleMs=0})
assert(ok and result.focus_verified and c.tap==baseline+1)

focusReady=false
local beforeInput=c.input
invalid,why,kind=pro.safe(nk,"field",{bundle=bundle,focus={x=350,y=400},
                                      requireFocusProof=true,onceKey="strict.false",
                                      settleMs=0})
assert(invalid==nil and kind=="FOCUS_NOT_CONFIRMED" and c.input==beforeInput)
focusReady=true

changeAfterTap=true
invalid,why,kind=pro.safe(nk,"field",{bundle=bundle,focus={x=350,y=400},
                                      onceKey="app.changed",settleMs=0})
assert(invalid==nil and kind=="WRONG_APP" and c.input==beforeInput)
changeAfterTap=false
active=bundle
invalid,why,kind=pro.safe(nk,"field",{bundle=bundle,focus={x=350,y=400},
                                      onceKey="app.changed",settleMs=0})
assert(invalid==nil and kind=="DUPLICATE_BLOCKED")
assert(c.input==beforeInput)

throwInput=true
invalid,why,kind=pro.safe(nk,"test",{bundle=bundle,focus={x=350,y=400},
                                     onceKey="native.uncertain",settleMs=0})
assert(invalid==nil and kind=="DISPATCH_UNCERTAIN")
tapBefore,inputBefore=c.tap,c.input
invalid,why,kind=pro.safe(nk,"test",{bundle=bundle,focus={x=350,y=400},
                                     onceKey="native.uncertain",settleMs=0})
assert(invalid==nil and kind=="DUPLICATE_BLOCKED")
assert(c.tap==tapBefore and c.input==inputBefore)
throwInput=false
assert(c.ocr==0)
print("[NKINPUT_PRO][HOST] PASS direct_unicode, keyboard_explicit, preflight, focus_strict, no_ocr, once_key, no_retry")
