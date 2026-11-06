-- NKTouch v0.8.6 host regression: no real HID, OCR or screenshots.
package.path="lua/?.lua;"..package.path
local p=require("nkprecision")
assert(p.VERSION=="0.8.6-beta")
local n={frames=0,screen=0,taps=0,colors=0,finds=0,apps=0}
local dimW,dimH=750,1334
local nativeW,nativeH=750,1334
local active="com.apple.mobilenotes"
local red=100
local green=150
local blue=200
local corrupt=false
local missing=false
local changedAfterFrame=false
local badHit=false
local tapFails=false
local pixelPositions={}
local nk={}
function nk.screen()
  n.screen=n.screen+1
  return ("%d.000000;;%d.000000"):format(dimW,dimH)
end
function nk.foreground()
  n.apps=n.apps+1
  return active
end
function nk.tap(x,y)
  n.taps=n.taps+1
  assert(x>=0 and x<dimW and y>=0 and y<dimH)
  if tapFails then error("delivery uncertain") end
  return true
end
function nk.ocr() error("precision must not call OCR") end
function nk.screenshot() error("precision must use one frame") end
function nk.withFrame(cb)
  n.frames=n.frames+1
  local frame={}
  function frame:info()return {width=nativeW,height=nativeH}end
  function frame:getColor(x,y)
    n.colors=n.colors+1
    pixelPositions[#pixelPositions+1]={x=x,y=y}
    if missing then return nil,"failed","COLOR" end
    return {red=red,green=green,blue=blue,
            packed=corrupt and 12 or red*65536+green*256+blue}
  end
  function frame:findColor(x,y,w,h,r1,r2,g1,g2,b1,b2,skip)
    n.finds=n.finds+1
    assert(x>=0 and y>=0 and x+w<=nativeW and y+h<=nativeH)
    assert(r1<=r2 and g1<=g2 and b1<=b2 and skip>=0)
    if missing then return nil,"no color","NOT_FOUND" end
    if badHit then
      return {x=x+w,y=y,red=red,green=green,blue=blue,
              packed=red*65536+green*256+blue}
    end
    return {x=x+2,y=y+3,red=red,green=green,blue=blue,
            packed=corrupt and 0 or red*65536+green*256+blue}
  end
  local a,b,c=cb(frame)
  if changedAfterFrame then active="com.apple.mobilesafari" end
  return a,b,c
end
local target="com.apple.mobilenotes"
local pt={x=120,y=210,r=100,g=150,b=200,tolerance=2}
local group={pt,{x=160,y=250,r=99,g=149,b=199,tolerance=1}}
local result=assert(p.inspect(nk,{points=group}))
assert(result.matched and result.matches==2 and result.frame_count==1)
assert(n.frames==1 and n.colors==2 and n.taps==0)
assert(result.geometry_verified and result.units=="physical_pixels")
red=104
result=assert(p.inspect(nk,{points=group}))
assert(not result.matched and result.matches==0 and n.frames==2)
red=100
local v,e,c=p.inspect(nk,{points={{x=750,y=0,r=1,g=2,b=3}}})
assert(v==nil and c=="INVALID" and n.frames==2)
v,e,c=p.inspect(nk,{points={{x=1,y=1,r=1,g=2,b=3,tolerance=256}}})
assert(v==nil and c=="INVALID")
v,e,c=p.inspect(nk,{points={}})
assert(v==nil and c=="INVALID")
corrupt=true
v,e,c=p.inspect(nk,{points={pt}})
assert(v==nil and c=="BACKEND")
corrupt=false
missing=true
v,e,c=p.inspect(nk,{points={pt}})
assert(v==nil and c=="COLOR")
missing=false

local geometry=assert(p.inspect(nk,{points={pt}}))
nativeW,nativeH=1334,750
v,e,c=p.inspect(nk,{points={pt}})
assert(v==nil and c=="GEOMETRY_MISMATCH")
nativeW,nativeH=750,1334

local found=assert(p.find(nk,{region={x=40,y=60,w=100,h=100},
                              color={r=100,g=150,b=200,tolerance=3}}))
assert(found.found and found.x==42 and found.y==63 and n.finds==1)
missing=true
found=assert(p.find(nk,{region={x=40,y=60,w=100,h=100},
                        color={r=100,g=150,b=200,tolerance=3}}))
assert(found.found==false and found.status=="NOT_FOUND")
missing=false
badHit=true
v,e,c=p.find(nk,{region={x=40,y=60,w=100,h=100},
                 color={r=100,g=150,b=200,tolerance=3}})
assert(v==nil and c=="BACKEND")
badHit=false
v,e,c=p.find(nk,{region={x=749,y=10,w=2,h=1},
                 color={r=100,g=150,b=200}})
assert(v==nil and c=="INVALID")

local guard={enabled=true,confirmed=true,bundle=target,tap={x=420,y=550},
             points={pt}}
local before=n.frames
v,e,c=p.tapIfMatch(nk,{bundle=target,tap={x=420,y=550},points={pt}})
assert(v==nil and c=="NOT_CONFIRMED" and n.taps==0 and n.frames==before)
v,e,c=p.tapIfMatch(nk,{enabled=true,confirmed=true,bundle=target,
                       tap={x=750,y=550},points={pt}})
assert(v==nil and c=="OUT_OF_BOUNDS" and n.taps==0 and n.frames==before)
active="com.apple.mobilesafari"
v,e,c=p.tapIfMatch(nk,guard)
assert(v==nil and c=="WRONG_APP" and n.taps==0)
active=target
red=105
v,e,c=p.tapIfMatch(nk,guard)
assert(v==nil and c=="COLOR_MISMATCH" and n.taps==0)
red=100
changedAfterFrame=true
v,e,c=p.tapIfMatch(nk,guard)
assert(v==nil and c=="WRONG_APP" and n.taps==0)
active=target
changedAfterFrame=false
local beforeTap=n.taps
local ok,ack=p.tapIfMatch(nk,guard)
assert(ok and n.taps==beforeTap+1 and ack.sent)
assert(ack.status=="DISPATCHED_UNVERIFIED" and ack.verified==false)
assert(ack.frame_count==1 and ack.sample_matched and ack.foreground_verified)

tapFails=true
beforeTap=n.taps
v,e,c=p.tapIfMatch(nk,guard)
assert(v==nil and c=="DISPATCH_UNCERTAIN" and n.taps==beforeTap+1)
tapFails=false
v,e,c=p.tapIfFound(nk,{enabled=true,confirmed=true,bundle=target,
    region={x=40,y=60,w=100,h=100},color={r=100,g=150,b=200}})
assert(v==true and e.sent and e.tap.x==42 and e.tap.y==63)
missing=true
beforeTap=n.taps
v,e,c=p.tapIfFound(nk,{enabled=true,confirmed=true,bundle=target,
    region={x=40,y=60,w=100,h=100},color={r=100,g=150,b=200}})
assert(v==nil and c=="NOT_FOUND" and n.taps==beforeTap)
missing=false
changedAfterFrame=true
v,e,c=p.tapIfFound(nk,{enabled=true,confirmed=true,bundle=target,
    region={x=40,y=60,w=100,h=100},color={r=100,g=150,b=200}})
assert(v==nil and c=="WRONG_APP" and n.taps==beforeTap)
assert(n.frames>=10 and n.colors>=5 and n.apps>=5)
print(("[NKPRECISION][HOST] PASS frames=%d color_samples=%d region_searches=%d taps=%d"):format(
  n.frames,n.colors,n.finds,n.taps))
