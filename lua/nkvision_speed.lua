-- NKTouch v0.8.8 Vision Speed & Screen Stability.
-- SPDX-License-Identifier: GPL-3.0-or-later
-- READ ONLY. Bounded frames; no tap/input, OCR of unstable frames or retry
-- after a side effect. Does NOT prove that a spinner or animation has ended.
-- One immutable frame is shared by pixel/color/ocr/template queries.
local M={VERSION="0.8.8-beta"}
local BACKEND={SERVICE_JPEG_SAME_FRAME=true,NATIVE_FRAME=true}

local function fail(msg,code) return nil,msg,code end
local function number(v,lo,hi)
  return type(v)=="number" and v==v and
    v~=math.huge and v~=-math.huge and v>=lo and v<=hi
end
local function integer(v,lo,hi)
  return number(v,lo,hi) and v%1==0
end
local function dense(items,maximum)
  if items==nil then return {} end
  if type(items)~="table" or #items>maximum then return nil end
  local count=0
  for k,v in pairs(items) do
    if not integer(k,1,#items) or type(v)~="table" then return nil end
    count=count+1
  end
  if count~=#items then return nil end
  return items
end
local function roi(p)
  return type(p)=="table" and integer(p.x,0,10000) and
     integer(p.y,0,10000) and integer(p.w,1,10000) and
     integer(p.h,1,10000)
end
local function inside(p,w,h)
  return p.x<w and p.y<h and p.w<=w-p.x and p.h<=h-p.y
end
local function pixel(p)
  return type(p)=="table" and integer(p.x,0,10000) and
    integer(p.y,0,10000)
end
local function col(p)
  if not roi(p) then return false end
  for _,k in ipairs({"rmin","rmax","gmin","gmax","bmin","bmax"}) do
    if not integer(p[k],0,255) then return false end
  end
  return p.rmin<=p.rmax and p.gmin<=p.gmax and
    p.bmin<=p.bmax and integer(p.skip or 0,0,1000)
end
local function ocr(p)
  return roi(p) and (p.language==nil or
    (type(p.language)=="string" and #p.language<=64 and
     not p.language:find("[\r\n%z]")))
end
local function template(p)
  return type(p)=="table" and type(p.path)=="string" and
    #p.path>0 and #p.path<=1024 and
    not p.path:find("[%z\r\n]") and utf8.len(p.path)~=nil and
    integer(p.max_try or 1,0,4) and
    number(p.confidence or 0.8,0.5,1) and
    number(p.scale or 0.8,0.051,0.999)
end
local function planCheck(plan)
  if type(plan)~="table" then return fail("plan table required","INVALID") end
  for k in pairs(plan) do
    if k~="pixels" and k~="colors" and k~="ocr" and k~="templates" then
      return fail("unknown plan key","INVALID")
    end
  end
  local cfg={}
  for _,spec in ipairs({{"pixels",32,pixel},
                         {"colors",12,col},
                         {"ocr",2,ocr},
                         {"templates",4,template}}) do
    local k,max,validator=spec[1],spec[2],spec[3]
    local list=dense(plan[k],max)
    if not list then return fail("invalid or oversized "..k.." list","INVALID") end
    for _,v in ipairs(list) do
      if not validator(v) then return fail("invalid "..k.." request","INVALID") end
    end
    cfg[k]=list
  end
  return cfg
end
local function rgb(p)
  return type(p)=="table" and integer(p.red,0,255) and
    integer(p.green,0,255) and integer(p.blue,0,255) and
    (p.packed==nil or
       p.packed==p.red*65536+p.green*256+p.blue)
end
local function depsFor(nk,opts)
  if type(nk)~="table" or type(nk.withFrame)~="function" or
    type(nk.screen)~="function" then
    return fail("same-frame Vision and screen APIs required","NO_VISION")
  end
  if type(opts)~="table" then return fail("options table required","INVALID") end
  local called,raw,readErr,readCode=pcall(nk.screen)
  if not called or raw==nil then
    return fail("screen query unavailable",readCode or "SCREEN")
  end
  local geom,err,code=require("nkcoords").screen(raw)
  if not geom then return nil,err,code end
  local now=opts.now
  if now==nil then
    local ok,core=pcall(require,"nkcore")
    if ok and type(core)=="table" then now=core.nowMs end
  end
  if type(now)~="function" then return fail("monotonic clock required","NO_CLOCK") end
  local start=now()
  if not number(start,0,math.huge) then return fail("invalid monotonic clock","CLOCK") end
  return {geom=geom,now=now,start=start}
end
local function elapsed(ctx)
  local t=ctx.now()
  if not number(t,ctx.start,math.huge) then return nil end
  return t-ctx.start
end
local function getFrame(frame,ctx)
  if (type(frame)~="userdata" and type(frame)~="table") or
     type(frame.info)~="function" or
     type(frame.getColor)~="function" then
    return fail("native Vision frame unavailable","FRAME")
  end
  local info,e,c=frame:info()
  if not info then return nil,e or "frame metadata unavailable",c or "FRAME" end
  local match,me,mc=require("nkcoords").inspectFrame(ctx.geom,info)
  if not match then return nil,me,mc end
  if match.matches~=true then
    return fail("screen/frame geometry changed: "..match.kind,
                "GEOMETRY_MISMATCH")
  end
  local call={native_reads=0,cache_hits=0,colors=0,
              ocr_calls=0,templates=0,cache={}}
  function call:read(x,y)
    local key=x..":"..y
    local sample=self.cache[key]
    if sample then self.cache_hits=self.cache_hits+1; return sample end
    local p,pe,pc=frame:getColor(x,y)
    if not p then return nil,pe or "pixel read failed",pc or "COLOR" end
    if not rgb(p) then return fail("invalid native RGB result","BACKEND") end
    self.cache[key]=p
    self.native_reads=self.native_reads+1
    return p
  end
  return info,call
end

local function readPlan(frame,info,call,cfg,opts)
  local w,h=info.width,info.height
  local out={status="PASS",width=w,height=h,units="physical_pixels",
             frame_count=1,pixels={},colors={},ocr={},templates={},
             errors=0,privacy="no_ocr_text_by_default"}
  local function add(k,item)
    out[k][#out[k]+1]=item
    if item.status=="FAIL" then out.errors=out.errors+1 end
  end
  for _,p in ipairs(cfg.pixels) do
    if p.x>=w or p.y>=h then
      add("pixels",{status="FAIL",code="OUT_OF_BOUNDS"})
    else
      local v,e,c=call:read(p.x,p.y)
      if not v then
        add("pixels",{status="FAIL",code=c or "COLOR"})
      else
        add("pixels",{status="PASS",x=p.x,y=p.y,
          rgb={red=v.red,green=v.green,blue=v.blue}})
      end
    end
  end
  for _,p in ipairs(cfg.colors) do
    if not inside(p,w,h) then
      add("colors",{status="FAIL",code="OUT_OF_BOUNDS"})
    elseif type(frame.findColor)~="function" then
      add("colors",{status="FAIL",code="NO_COLOR"})
    else
      call.colors=call.colors+1
      local hit,e,c=frame:findColor(p.x,p.y,p.w,p.h,
          p.rmin,p.rmax,p.gmin,p.gmax,p.bmin,p.bmax,p.skip or 0)
      if not hit then
        if c=="NOT_FOUND" then
          add("colors",{status="NOT_FOUND",code="NOT_FOUND"})
        else
          add("colors",{status="FAIL",code=c or "COLOR"})
        end
      elseif not rgb(hit) or not integer(hit.x,p.x,p.x+p.w-1)
         or not integer(hit.y,p.y,p.y+p.h-1)
         or hit.red<p.rmin or hit.red>p.rmax
         or hit.green<p.gmin or hit.green>p.gmax
         or hit.blue<p.bmin or hit.blue>p.bmax then
        add("colors",{status="FAIL",code="BACKEND"})
      else
        add("colors",{status="PASS",x=hit.x,y=hit.y,
          rgb={red=hit.red,green=hit.green,blue=hit.blue}})
      end
    end
  end
  for _,p in ipairs(cfg.templates) do
    if type(frame.findImage)~="function" then
      add("templates",{status="FAIL",code="NO_IMAGE"})
    else
      call.templates=call.templates+1
      local hit,e,c=frame:findImage(p.path,p.max_try or 1,
                                    p.confidence or 0.8,p.scale or 0.8)
      if not hit then
        add("templates",{status=c=="NOT_FOUND" and "NOT_FOUND" or "FAIL",
          code=c or "IMAGE"})
      elseif type(hit)~="table" or
          not integer(hit.x,0,w-1) or not integer(hit.y,0,h-1) or
          not integer(hit.width,1,w) or not integer(hit.height,1,h) or
          hit.width>w-hit.x or hit.height>h-hit.y or
          not number(hit.confidence,0,1) or
          hit.confidence<(p.confidence or 0.8) then
        add("templates",{status="FAIL",code="BACKEND"})
      else
        add("templates",{status="PASS",found=true,hit=hit})
      end
    end
  end
  for _,p in ipairs(cfg.ocr) do
    if not inside(p,w,h) then
      add("ocr",{status="FAIL",code="OUT_OF_BOUNDS"})
    elseif type(frame.ocr)~="function" then
      add("ocr",{status="FAIL",code="NO_OCR"})
    else
      call.ocr_calls=call.ocr_calls+1
      local text,e,c=frame:ocr(p.x,p.y,p.w,p.h,p.language or "")
      if text==nil then
        add("ocr",{status="FAIL",code=c or "OCR"})
      elseif type(text)~="string" then
        add("ocr",{status="FAIL",code="BACKEND"})
      else
        local meta=frame:info()
        if not meta or not BACKEND[meta.ocr_backend] then
          add("ocr",{status="FAIL",code="UNVERIFIED_BACKEND"})
        else
          local item={status=#text>0 and "PASS" or "EMPTY",bytes=#text,
                      backend=meta.ocr_backend,same_frame=true}
          if opts.include_text==true then item.text=text end
          add("ocr",item)
        end
      end
    end
  end
  out.status=out.errors>0 and "PARTIAL" or "PASS"
  out.metrics={pixel_native_reads=call.native_reads,
               pixel_cache_hits=call.cache_hits,
               color_searches=call.colors,ocr_calls=call.ocr_calls,
               template_calls=call.templates}
  return out
end
function M.batch(nk,plan,opts)
  opts=opts or {}
  local cfg,e,c=planCheck(plan)
  if not cfg then return nil,e,c end
  local ctx,de,dc=depsFor(nk,opts)
  if not ctx then return nil,de,dc end
  local value,ve,vc=nk.withFrame(function(frame)
    local info,call,err=getFrame(frame,ctx)
    if not info then return nil,call,err end
    return readPlan(frame,info,call,cfg,opts)
  end)
  if not value then return nil,ve or "batch capture failed",vc or "FRAME" end
  value.metrics.elapsed_ms=elapsed(ctx)
  value.metrics.captures=1
  return value
end
local function stableOptions(opts)
  local interval=opts.interval_ms or 200
  local tolerance=opts.tolerance or 6
  local stable=opts.stable_frames or 3
  local max=opts.max_captures or 6
  local timeout=opts.timeout_ms or 3500
  if not integer(interval,100,1500) or
     not integer(tolerance,0,40) or
     not integer(stable,2,4) or
     not integer(max,stable,8) or
     not integer(timeout,200,15000) then
    return fail("interval 100..1500; tolerance 0..40; stable 2..4; captures 2..8; timeout 200..15000","INVALID")
  end
  local watch=dense(opts.watch_points,16)
  if not watch then return fail("watch_points must be a dense array <=16","INVALID") end
  for _,p in ipairs(watch) do
    if not pixel(p) then return fail("watch point invalid","INVALID") end
  end
  return {interval=interval,tolerance=tolerance,stable=stable,
          max=max,timeout=timeout,watch=watch}
end
local function points(info,watch)
  local p={}
  for yi=1,4 do
    for xi=1,4 do
      p[#p+1]={x=math.floor((info.width-1)*xi/5),
               y=math.floor((info.height-1)*yi/5)}
    end
  end
  for _,extra in ipairs(watch) do p[#p+1]=extra end
  return p
end
local function signature(frame,info,call,watch)
  local sig={width=info.width,height=info.height,values={}}
  for _,p in ipairs(points(info,watch)) do
    if p.x>=info.width or p.y>=info.height then
      return fail("watch point outside current frame","OUT_OF_BOUNDS")
    end
    local rgbValue,e,c=call:read(p.x,p.y)
    if not rgbValue then return nil,e,c end
    sig.values[#sig.values+1]={rgbValue.red,rgbValue.green,rgbValue.blue}
  end
  return sig
end
local function difference(a,b)
  if not a or not b or a.width~=b.width or a.height~=b.height
     or #a.values~=#b.values then return math.huge end
  local peak=0
  for i=1,#a.values do
    for k=1,3 do
      local delta=math.abs(a.values[i][k]-b.values[i][k])
      if delta>peak then peak=delta end
    end
  end
  return peak
end
function M.whenStable(nk,plan,opts)
  opts=opts or {}
  if type(opts)~="table" then return fail("options table required","INVALID") end
  local cfg,e,c=planCheck(plan)
  if not cfg then return nil,e,c end
  local setting,se,sc=stableOptions(opts)
  if not setting then return nil,se,sc end
  local ctx,de,dc=depsFor(nk,opts)
  if not ctx then return nil,de,dc end
  local sleep=opts.sleep or nk.sleep
  if type(sleep)~="function" then return fail("native sleep unavailable","NO_SLEEP") end
  local previous=nil
  local consecutive=0
  local lastDelta=nil
  local count=0
  while count<setting.max do
    local spent=elapsed(ctx)
    if not spent then return fail("monotonic clock regressed","CLOCK") end
    if count>0 and spent>=setting.timeout then break end
    count=count+1
    local result,re,rc=nk.withFrame(function(frame)
      local info,call,code=getFrame(frame,ctx)
      if not info then return nil,call,code end
      local sig,serr,scode=signature(frame,info,call,setting.watch)
      if not sig then return nil,serr,scode end
      local delta=difference(previous,sig)
      if delta<=setting.tolerance then
        consecutive=consecutive+1
      else
        consecutive=1
      end
      lastDelta=delta
      previous=sig
      if consecutive<setting.stable then
        return {ready=false}
      end
      -- The final verified signature frame is REUSED for batch Color/OCR/
      -- Template operations. Never take a third capture for the same work.
      local remaining=elapsed(ctx)
      if not remaining or remaining>=setting.timeout then
        return {ready=false,exhausted=true}
      end
      local output=readPlan(frame,info,call,cfg,opts)
      output.metrics.captures=count
      output.metrics.stable_frames=consecutive
      output.metrics.stability_max_channel_delta=delta
      output.metrics.stability_heuristic=true
      output.metrics.reused_last_frame=true
      output.metrics.elapsed_ms=elapsed(ctx)
      return {ready=true,output=output}
    end)
    if not result then return nil,re or "Vision capture failed",rc or "FRAME" end
    if result.ready then return result.output end
    if result.exhausted then break end
    if count<setting.max then
      local used=elapsed(ctx)
      if not used then return fail("monotonic clock regressed","CLOCK") end
      local remaining=setting.timeout-used
      if remaining<=0 then break end
      local delay=math.min(setting.interval,remaining)
      local called,slept=pcall(sleep,delay)
      if not called or slept~=true then
        return fail("read-only sampling sleep failed","SLEEP")
      end
    end
  end
  return nil,"sampled pixels did not stabilize before bounded deadline",
             "SCREEN_UNSTABLE",
             {captures=count,last_max_delta=lastDelta,
              elapsed_ms=elapsed(ctx),heuristic=true}
end
return M
