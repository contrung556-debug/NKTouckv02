-- NKTouch v0.8.6 Touch & Color Precision: one-frame pixel contracts.
-- SPDX-License-Identifier: GPL-3.0-or-later
-- Explicit physical pixels. No guessed Retina/orientation transformation.
-- Read-only inspection by default; touch requires double opt-in + foreground.
local M={VERSION="0.8.6-beta"}

local function integer(n,lo,hi)
  return type(n)=="number" and n==n and n%1==0 and n>=lo and n<=hi
end
local function fail(message,code) return nil,message,code end
local function dense(t,lo,hi)
  if type(t)~="table" then return false end
  local n=#t
  if n<lo or n>hi then return false end
  local count=0
  for k in pairs(t) do
    if not integer(k,1,n) then return false end
    count=count+1
  end
  return count==n
end
local function rgb(v)
  if type(v)~="table" or not integer(v.red,0,255) or
     not integer(v.green,0,255) or not integer(v.blue,0,255) then
    return false
  end
  return v.packed==nil or
         v.packed==v.red*65536+v.green*256+v.blue
end
local function checkColor(c)
  return type(c)=="table" and integer(c.r,0,255) and
    integer(c.g,0,255) and integer(c.b,0,255) and
    integer(c.tolerance or 0,0,255)
end
local function getScreen(nk)
  if type(nk)~="table" or type(nk.screen)~="function" or
     type(nk.withFrame)~="function" then
    return fail("screen and same-frame vision APIs required","NO_BACKEND")
  end
  local called,raw=pcall(nk.screen)
  if not called then return fail("screen query raised","SCREEN") end
  local geometry,e,c=require("nkcoords").screen(raw)
  if not geometry then return nil,e,c end
  return geometry
end
local function bounds(x,y,w,h)
  return integer(x,0,w-1) and integer(y,0,h-1)
end
local function validPoints(points,geometry)
  if not dense(points,1,16) then return fail("1..16 dense pixel specs required","INVALID") end
  for i,p in ipairs(points) do
    if type(p)~="table" or not bounds(p.x,p.y,geometry.width,geometry.height)
       or not checkColor(p) then
      return fail("invalid pixel/color spec at index "..i,"INVALID")
    end
  end
  return true
end
local function frameRun(nk,geometry,callback)
  local called,result,err,code=pcall(nk.withFrame,function(frame)
    if type(frame)~="table" or type(frame.info)~="function" then
      return fail("invalid Vision frame","FRAME")
    end
    local info,ie,ic=frame:info()
    if not info then return nil,ie or "frame info unavailable",ic or "FRAME" end
    local match,e,c=require("nkcoords").inspectFrame(geometry,info)
    if not match then return nil,e,c end
    if not match.matches then
      return fail("frame and screen pixel geometry differ: "..match.kind,
                  "GEOMETRY_MISMATCH")
    end
    return callback(frame)
  end)
  if not called then return fail("frame callback raised; no action sent","FRAME") end
  if result==nil then return nil,err or "frame failed",code or "FRAME" end
  return result
end
local function pixelPattern(nk,geometry,points)
  return frameRun(nk,geometry,function(frame)
    if type(frame.getColor)~="function" then
      return fail("frame pixel API unavailable","NO_COLOR")
    end
    local matched,n,values=true,0,{}
    for i,p in ipairs(points) do
      local sample,e,c=frame:getColor(p.x,p.y)
      if not sample then return nil,e or "pixel unavailable",c or "COLOR" end
      if not rgb(sample) then
        return fail("backend returned inconsistent RGB/packed pixel","BACKEND")
      end
      local tol=p.tolerance or 0
      local ok=math.abs(sample.red-p.r)<=tol and
               math.abs(sample.green-p.g)<=tol and
               math.abs(sample.blue-p.b)<=tol
      if ok then n=n+1 else matched=false end
      values[i]={x=p.x,y=p.y,matched=ok,
                 red=sample.red,green=sample.green,blue=sample.blue}
    end
    return {matched=matched,matches=n,total=#points,pixels=values,
            frame_count=1,geometry_verified=true,units="physical_pixels"}
  end)
end

function M.inspect(nk,opts)
  if type(opts)~="table" then return fail("options table required","INVALID") end
  local geometry,e,c=getScreen(nk)
  if not geometry then return nil,e,c end
  local ok,pe,pc=validPoints(opts.points,geometry)
  if not ok then return nil,pe,pc end
  return pixelPattern(nk,geometry,opts.points)
end

local function validRegion(reg,g)
  return type(reg)=="table" and
    integer(reg.x,0,g.width-1) and integer(reg.y,0,g.height-1) and
    integer(reg.w,1,g.width) and integer(reg.h,1,g.height) and
    reg.x+reg.w<=g.width and reg.y+reg.h<=g.height
end
local function findRegion(nk,g,reg,col,skip)
  return frameRun(nk,g,function(frame)
    if type(frame.findColor)~="function" then
      return fail("frame color search unavailable","NO_COLOR")
    end
    local t=col.tolerance or 0
    local hit,e,c=frame:findColor(reg.x,reg.y,reg.w,reg.h,
      math.max(0,col.r-t),math.min(255,col.r+t),
      math.max(0,col.g-t),math.min(255,col.g+t),
      math.max(0,col.b-t),math.min(255,col.b+t),skip)
    if not hit then
      if c=="NOT_FOUND" then
        return {found=false,status="NOT_FOUND",frame_count=1,
                geometry_verified=true}
      end
      return nil,e or "color search failed",c or "COLOR"
    end
    if type(hit)~="table" or not bounds(hit.x,hit.y,g.width,g.height)
       or hit.x<reg.x or hit.x>=reg.x+reg.w
       or hit.y<reg.y or hit.y>=reg.y+reg.h
       or not rgb(hit) then
      return fail("native search returned invalid hit","BACKEND")
    end
    if math.abs(hit.red-col.r)>t or math.abs(hit.green-col.g)>t
       or math.abs(hit.blue-col.b)>t then
      return fail("native search RGB is outside requested tolerance","BACKEND")
    end
    return {found=true,status="FOUND",x=hit.x,y=hit.y,
            rgb={red=hit.red,green=hit.green,blue=hit.blue},
            frame_count=1,geometry_verified=true,units="physical_pixels"}
  end)
end
function M.find(nk,opts)
  if type(opts)~="table" or not checkColor(opts.color) or
     not integer(opts.skip or 0,0,1000) then
    return fail("valid color/range and skip 0..1000 required","INVALID")
  end
  local g,e,c=getScreen(nk)
  if not g then return nil,e,c end
  if not validRegion(opts.region,g) then
    return fail("search region outside physical pixel bounds","INVALID")
  end
  return findRegion(nk,g,opts.region,opts.color,opts.skip or 0)
end

local function authorize(nk,opts)
  if type(opts)~="table" or opts.enabled~=true or opts.confirmed~=true then
    return fail("enabled=true and confirmed=true required","NOT_CONFIRMED")
  end
  local bundle=opts.bundle
  if type(bundle)~="string" or #bundle<3 or #bundle>180 or
     not bundle:match("^[%w%._%-]+$") then
    return fail("valid target bundle required","INVALID")
  end
  if type(nk)~="table" or type(nk.foreground)~="function"
     or type(nk.tap)~="function" then
    return fail("foreground/tap APIs missing","NO_BACKEND")
  end
  return true
end
local function checkForeground(nk,bundle)
  local called,active=pcall(nk.foreground)
  if not called or type(active)~="string" then
    return fail("foreground query failed","FOREGROUND")
  end
  if active~=bundle then return fail("foreground app differs","WRONG_APP") end
  return true
end
local function tapOnce(nk,x,y,meta)
  -- A native ACK is not visual proof of touch delivery or UI transition.
  -- Do not retry on a false ACK or exception (dispatch may be uncertain).
  local called,ack=pcall(nk.tap,x,y)
  if not called or ack~=true then
    return fail("touch may have been dispatched; do not retry automatically",
                "DISPATCH_UNCERTAIN")
  end
  meta.tap={x=x,y=y}
  meta.sent=true
  meta.verified=false
  meta.status="DISPATCHED_UNVERIFIED"
  meta.attempts=1
  return true,meta
end
function M.tapIfMatch(nk,opts)
  local approved,e,c=authorize(nk,opts)
  if not approved then return nil,e,c end
  local g,ge,gc=getScreen(nk)
  if not g then return nil,ge,gc end
  local points=opts.points
  local ok,pe,pc=validPoints(points,g)
  if not ok then return nil,pe,pc end
  local at=opts.tap
  if type(at)~="table" or not bounds(at.x,at.y,g.width,g.height) then
    return fail("tap coordinate must be physical screen pixel","OUT_OF_BOUNDS")
  end
  local before,be,bc=checkForeground(nk,opts.bundle)
  if not before then return nil,be,bc end
  local result,re,rc=pixelPattern(nk,g,points)
  if not result then return nil,re,rc end
  if not result.matched then return fail("color pattern did not match","COLOR_MISMATCH") end
  local after,ae,ac=checkForeground(nk,opts.bundle)
  if not after then return nil,ae,ac end
  return tapOnce(nk,at.x,at.y,{
    target_app=opts.bundle,frame_count=1,geometry_verified=true,
    sample_matched=true,foreground_verified=true
  })
end
function M.tapIfFound(nk,opts)
  local approved,e,c=authorize(nk,opts)
  if not approved then return nil,e,c end
  if not checkColor(opts.color) or not integer(opts.skip or 0,0,1000) then
    return fail("valid color/skip required","INVALID")
  end
  local g,ge,gc=getScreen(nk)
  if not g then return nil,ge,gc end
  if not validRegion(opts.region,g) then
    return fail("invalid search region","INVALID")
  end
  local before,be,bc=checkForeground(nk,opts.bundle)
  if not before then return nil,be,bc end
  local hit,he,hc=findRegion(nk,g,opts.region,opts.color,opts.skip or 0)
  if not hit then return nil,he,hc end
  if not hit.found then return fail("color not found","NOT_FOUND") end
  local after,ae,ac=checkForeground(nk,opts.bundle)
  if not after then return nil,ae,ac end
  return tapOnce(nk,hit.x,hit.y,{
    target_app=opts.bundle,frame_count=1,geometry_verified=true,
    search_matched=true,foreground_verified=true
  })
end
return M
