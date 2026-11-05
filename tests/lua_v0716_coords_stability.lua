-- NKTouch v0.7.16-dev: pure Lua no-device coordinate/stability suite.
package.path="lua/?.lua;"..package.path
local coords=require("nkcoords")
local stability=require("nkstability")
local checks=0
local function eq(a,b,label) assert(a==b,(label or "mismatch")..": "..tostring(a).." ~= "..tostring(b));checks=checks+1 end
local function errCode(value,err,code,expected)
  eq(value,nil,"value must be nil")
  eq(code,expected,"error code")
  assert(type(err)=="string" and #err>0)
end

local screen=assert(coords.screen("750.000000;;1334.000000"))
eq(screen.width,750)
eq(screen.height,1334)
eq(screen.units,"physical_pixels")
local area=assert(coords.screen("390;;844"))
eq(area.width,390)
errCode(coords.screen("750.000000;;bad"),"INVALID")
errCode(coords.screen("750.5;;1334"),"INVALID")
errCode(coords.screen("abc"),"INVALID")
errCode(coords.screen("0;;999"),"INVALID")
local p=assert(coords.point(100,200,screen))
eq(p.x,100);eq(p.y,200)
p=assert(coords.point(100,200,screen,{units="point",scale=2}))
eq(p.x,200);eq(p.y,400)
errCode(coords.point(100,200,screen,{units="point"}),"INVALID")
errCode(coords.point(10,20,screen,{units="pixel",scale=2}),"INVALID")
errCode(coords.point(750,0,screen),"OUT_OF_BOUNDS")
errCode(coords.point(-1,0,screen),"OUT_OF_BOUNDS")
errCode(coords.point(749.9,0,screen),"OUT_OF_BOUNDS")
errCode(coords.point(0/0,1,screen),"INVALID")
-- NaN is invalid but point() specifically rejects nonfinite inputs.
local same=assert(coords.inspectFrame(screen,{width=750,height=1334}))
eq(same.kind,"IDENTICAL");eq(same.matches,true)
local trans=assert(coords.inspectFrame(screen,{width=1334,height=750}))
eq(trans.kind,"ROTATED_90")
local scaled=assert(coords.inspectFrame({width=780,height=1688},{width=390,height=844}))
eq(scaled.kind,"SCALE_MISMATCH");eq(scaled.scale,2)
local mixed=assert(coords.inspectFrame(screen,{width=390,height=844}))
eq(mixed.kind,"GEOMETRY_MISMATCH")
local path=assert(coords.path({{x=3,y=4,t=0},{x=7,y=8,t=250}},screen))
eq(#path,2);eq(path[2].t,250)
errCode(coords.path({{x=3,y=4,t=0},{x=7,y=8,t=0}},screen),"INVALID")
errCode(coords.path({{x=3,y=4,t=0},{x=750,y=8,t=250}},screen),"OUT_OF_BOUNDS")
errCode(coords.path({{x=3,y=4,t=20},{x=7,y=8,t=250}},screen),"INVALID")
errCode(coords.path({{x=3,y=4,t=0}},screen),"INVALID")

local ticks,tries=0,0
local function now()return ticks end
local function sleep(ms)ticks=ticks+ms;return true end
local probe=function()
  tries=tries+1
  if tries==1 then return nil,"disconnected","CONNECT" end
  return true
end
local value,meta=stability.pollRead(probe,{read_only=true,max_attempts=4,
  timeout_ms=500,interval_ms=40,now=now,sleep=sleep})
eq(value,true);eq(meta.attempts,2);eq(meta.elapsed_ms,40);eq(tries,2)
errCode(stability.pollRead(function()error("should not execute")end,
       {read_only=false,now=now,sleep=sleep}),"INVALID")
tries=0
value,meta=stability.pollRead(function()
  tries=tries+1
  return nil,"not found","NOT_FOUND"
end,{read_only=true,max_attempts=3,timeout_ms=500,interval_ms=10,
  now=now,sleep=sleep})
eq(value,nil);eq(meta,"not found");eq(tries,1)
tries=0
local r,e,c,detail=stability.pollRead(function()
  tries=tries+1
  return nil,"offline","CONNECT"
end,{read_only=true,max_attempts=3,timeout_ms=15,interval_ms=10,
  now=now,sleep=sleep})
eq(r,nil);eq(c,"CONNECT");eq(detail.attempts,3)
eq(detail.elapsed_ms,15)
tries=0
r,e,c,detail=stability.pollRead(function()
  tries=tries+1
  return nil,"not found","NOT_FOUND"
end,{read_only=true,retry_not_found=true,max_attempts=3,timeout_ms=30,
  interval_ms=10,now=now,sleep=sleep})
eq(detail.attempts,3)
local count=0
local measure=0
local stats=assert(stability.sampleRead(function()
  count=count+1;measure=measure+count
  return count
end,{read_only=true,count=4,now=function()
  measure=measure+1
  return measure
end}))
eq(stats.checks,4)
assert(stats.max_ms>=stats.min_ms and stats.p95_ms>=stats.min_ms)
errCode(stability.sampleRead(function()return true end,{read_only=false}),"INVALID")
print(("[NKCORE][HARDENING] PASS assertions=%d, no real touch/network"):format(checks))
