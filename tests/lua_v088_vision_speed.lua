-- NKTouch 0.8.8 deterministic Vision Speed + Stability host contracts.
-- Fake screenshot frames only. No real OCR, images, network, HID, or typed text.
package.path="lua/?.lua;"..package.path
local engine=require("nkvision_speed")
assert(engine.VERSION=="0.8.8-beta")
local state={clock=0,frames=0,closes=0,pixels=0,ocr=0,
             image=0,color=0,screens=0,writes=0,changing=false,
             backend="SERVICE_JPEG_SAME_FRAME",broken=false,geom=false}
local nk={}
function nk.screen()
  state.screens=state.screens+1
  return "750;;1334"
end
function nk.sleep(ms)
  assert(ms>=0 and ms<=1500)
  state.clock=state.clock+ms
  return true
end
function nk.tap() state.writes=state.writes+1; error("no HID in Vision") end
function nk.inputText() state.writes=state.writes+1; error("no Input in Vision") end
function nk.ocr() state.writes=state.writes+1; error("no LIVE OCR in Vision") end
local function now() return state.clock end
function nk.withFrame(fn)
  state.frames=state.frames+1
  state.clock=state.clock+20
  local frameNo=state.frames
  local frame={ocr_backend="NONE"}
  function frame:info()
    return {width=state.geom and 1334 or 750,height=state.geom and 750 or 1334,
            ocr_backend=self.ocr_backend,format="JPEG"}
  end
  function frame:getColor(x,y)
    state.pixels=state.pixels+1
    local value=state.changing and ((frameNo%2==0) and 80 or 20) or 20
    return {red=value,green=40,blue=60,packed=state.broken and 123 or value*65536+40*256+60}
  end
  function frame:findColor(x,y,w,h,r1,r2,g1,g2,b1,b2,skip)
    state.color=state.color+1
    assert(x>=0 and y>=0 and x+w<=750 and y+h<=1334)
    assert(r1<=r2 and g1<=g2 and b1<=b2 and skip>=0)
    return {x=x+2,y=y+2,red=20,green=40,blue=60,packed=20*65536+40*256+60}
  end
  function frame:findImage(path,max,confidence,scale)
    state.image=state.image+1
    assert(path=="/tmp/example-template.png" and max==1 and confidence==0.8 and scale==0.8)
    return {x=10,y=20,confidence=0.99}
  end
  function frame:ocr(x,y,w,h,lang)
    state.ocr=state.ocr+1
    assert(x==0 and y==0 and w==300 and h==200 and lang=="")
    self.ocr_backend=state.backend
    state.clock=state.clock+30
    return "Sensitive demo OCR text"
  end
  local ok,a,b,c=pcall(fn,frame)
  state.closes=state.closes+1
  if not ok then return nil,tostring(a),"CALLBACK" end
  return a,b,c
end
local rect={x=0,y=0,w=50,h=40,
           rmin=18,rmax=25,gmin=39,gmax=45,bmin=59,bmax=65}
local plan={
 pixels={{x=149,y=266},{x=149,y=266},{x=10,y=10}},
 colors={rect},
 ocr={{x=0,y=0,w=300,h=200}},
 templates={{path="/tmp/example-template.png"}}
}
local batch=assert(engine.batch(nk,plan,{now=now}))
assert(batch.status=="PASS" and batch.frame_count==1)
assert(batch.metrics.captures==1 and batch.metrics.pixel_native_reads==2)
assert(batch.metrics.pixel_cache_hits==1)
assert(batch.metrics.ocr_calls==1 and batch.metrics.template_calls==1)
assert(batch.metrics.color_searches==1 and batch.metrics.elapsed_ms==50)
assert(batch.ocr[1].bytes==#"Sensitive demo OCR text")
assert(batch.ocr[1].text==nil and batch.ocr[1].same_frame)
assert(state.frames==1 and state.closes==1 and state.ocr==1)
assert(state.screens==1 and state.writes==0)
local text=assert(engine.batch(nk,{ocr={{x=0,y=0,w=300,h=200}}},{now=now,include_text=true}))
assert(text.ocr[1].text=="Sensitive demo OCR text")
assert(state.frames==2 and state.closes==2 and state.ocr==2)
local baseFrames,baseOCR=state.frames,state.ocr
local invalid,msg,code=engine.batch(nk,{ocr={{x=0,y=0,w=0,h=100}}},{now=now})
assert(invalid==nil and code=="INVALID" and state.frames==baseFrames)
invalid,msg,code=engine.batch(nk,{unknown={}}, {now=now})
assert(invalid==nil and code=="INVALID" and state.frames==baseFrames)
invalid,msg,code=engine.batch(nk,{pixels={{x=1,y=2},[3]={x=4,y=5}}},{now=now})
assert(invalid==nil and code=="INVALID" and state.frames==baseFrames)

state.broken=true
local corrupt=assert(engine.batch(nk,{pixels={{x=10,y=10}}},{now=now}))
assert(corrupt.status=="PARTIAL" and corrupt.pixels[1].code=="BACKEND")
state.broken=false
state.geom=true
invalid,msg,code=engine.batch(nk,plan,{now=now})
assert(invalid==nil and code=="GEOMETRY_MISMATCH")
state.geom=false
assert(state.ocr==baseOCR)

-- Final sampled frame is REUSED for OCR and color; no extra snapshot.
local beforeFrames,beforeOCR=state.frames,state.ocr
local stable=assert(engine.whenStable(nk,plan,{
  now=now,sleep=nk.sleep,stable_frames=3,max_captures=5,interval_ms=100,
  watch_points={{x=149,y=266}},include_text=false}))
assert(stable.status=="PASS" and stable.metrics.reused_last_frame)
assert(stable.metrics.captures==3 and stable.metrics.stable_frames==3)
assert(stable.metrics.stability_heuristic==true)
assert(stable.metrics.pixel_cache_hits>=1)
assert(state.frames==beforeFrames+3 and state.ocr==beforeOCR+1)
assert(state.closes==state.frames and state.writes==0)
assert(stable.ocr[1].text==nil)

-- Do not OCR any unstable frame, never send tap or text.
state.changing=true
beforeOCR=state.ocr
beforeFrames=state.frames
invalid,msg,code,info=engine.whenStable(nk,plan,{
  now=now,sleep=nk.sleep,stable_frames=3,max_captures=5,interval_ms=100})
assert(invalid==nil and code=="SCREEN_UNSTABLE" and info.captures==5)
assert(state.frames==beforeFrames+5 and state.ocr==beforeOCR)
assert(state.closes==state.frames)
state.changing=false

-- A backend that does not positively confirm SAME-FRAME cannot be trusted.
state.backend="OCR_FALLBACK_LIVE"
local refused=assert(engine.batch(nk,{ocr={{x=0,y=0,w=300,h=200}}},{now=now}))
assert(refused.status=="PARTIAL" and refused.ocr[1].code=="UNVERIFIED_BACKEND")
assert(refused.ocr[1].text==nil)
state.backend="SERVICE_JPEG_SAME_FRAME"

beforeFrames=state.frames
invalid,msg,code=engine.whenStable(nk,plan,{
  now=now,sleep=function() return false end,interval_ms=100})
assert(invalid==nil and code=="SLEEP" and state.frames==beforeFrames+1)
beforeFrames=state.frames
invalid,msg,code=engine.whenStable(nk,plan,{
  now=now,sleep=nk.sleep,watch_points={{x=750,y=1}}})
assert(invalid==nil and code=="OUT_OF_BOUNDS" and state.frames==beforeFrames+1)

invalid,msg,code=engine.whenStable(nk,plan,{
  now=now,sleep=nk.sleep,stable_frames=5})
assert(invalid==nil and code=="INVALID")
local oldTime=state.clock
invalid,msg,code=engine.whenStable(nk,plan,{
  now=now,sleep=nk.sleep,timeout_ms=200,interval_ms=200,max_captures=6})
assert(invalid==nil and code=="SCREEN_UNSTABLE")
assert(state.clock-oldTime<=240)
assert(state.writes==0 and state.closes==state.frames)
print(("[NKVISION088][HOST] PASS captures=%d closes=%d pixel_reads=%d ocr=%d no_input=%d"):format(
  state.frames,state.closes,state.pixels,state.ocr,state.writes))
