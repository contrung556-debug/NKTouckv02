-- NKTouch v0.8.0 immutable Vision snapshot batch SDK.
-- One screenshot per capture(), multiple same-frame pixels/colors/OCR/template.
-- wait* deliberately recaptures ONLY when polling a read-only condition.
local M={VERSION="0.8.0-beta"}
local function invalid(msg) return nil,msg,"INVALID" end
local function number(v,low,high)
  return type(v)=="number" and v==v and v%1==0 and v>=low and v<=high
end
local function list(v,n,label)
  if v==nil then return {} end
  if type(v)~="table" or #v>n then return nil,label.." must be <= "..n.." items" end
  for i=1,#v do if type(v[i])~="table" then
    return nil,label.."["..i.."] must be a table" end end
  for k in pairs(v) do
    if type(k)~="number" or k%1~=0 or k<1 or k>#v then
      return nil,label.." must be a dense array"
    end
  end
  return v
end
local function region(r,w,h)
  return type(r)=="table" and number(r.x,0,w-1) and
    number(r.y,0,h-1) and number(r.w,1,w) and
    number(r.h,1,h) and r.x+r.w<=w and r.y+r.h<=h
end
local function status(code,msg) return {status="FAIL",code=code,detail=msg} end
local function normalizeRGB(v)
  if type(v)~="table" then return false end
  for _,key in ipairs({"red","green","blue"}) do
    if not number(v[key],0,255) then return false end
  end
  return v.packed==nil or
    v.packed==v.red*65536+v.green*256+v.blue
end
local function validatePlan(plan)
  if type(plan)~="table" then return nil,"plan must be a table" end
  local result={}
  for _,k in ipairs({"pixels","colors","ocr","templates"}) do
    local max=k=="ocr" and 8 or 32
    local values,err=list(plan[k],max,k)
    if not values then return nil,err end
    result[k]=values
  end
  return result
end
function M.capture(plan,options)
  options=options or {}
  if type(options)~="table" then return invalid("options must be a table") end
  local cfg,e=validatePlan(plan)
  if not cfg then return invalid(e) end
  local nk=options.nk or require("nktouch_v7")
  if type(nk)~="table" or type(nk.withFrame)~="function" then
    return nil,"Vision frame API unavailable","NO_VISION"
  end
  local count=0
  local data,frameError,frameCode=nk.withFrame(function(frame)
    count=count+1
    local info,err,code=frame:info()
    if not info then return nil,err,code end
    local w,h=info.width,info.height
    if not number(w,1,10000) or not number(h,1,10000) then
      return nil,"bad frame dimensions","FRAME"
    end
    local output={width=w,height=h,frame_count=1,pixels={},colors={},ocr={},
                  templates={},errors=0,format=info.format}
    local function add(key,item)
      output[key][#output[key]+1]=item
      if item.status=="FAIL" then output.errors=output.errors+1 end
    end
    for _,p in ipairs(cfg.pixels) do
      if not number(p.x,0,w-1) or not number(p.y,0,h-1) then
        add("pixels",status("INVALID","pixel out of bounds"))
      else
        local rgb,re,rc=frame:getColor(p.x,p.y)
        if not normalizeRGB(rgb) then
          add("pixels",status(rc or "RGB",re or "invalid RGB"))
        else
          add("pixels",{status="PASS",x=p.x,y=p.y,rgb=rgb})
        end
      end
    end
    for _,p in ipairs(cfg.colors) do
      local valid=region(p,w,h)
      for _,name in ipairs({"rmin","rmax","gmin","gmax","bmin","bmax"}) do
        valid=valid and number(p[name],0,255)
      end
      valid=valid and p.rmin<=p.rmax and p.gmin<=p.gmax and p.bmin<=p.bmax
      local skip=p.skip or 0
      valid=valid and number(skip,0,1000)
      if not valid then
        add("colors",status("INVALID","invalid search rectangle or RGB range"))
      else
        local hit,he,hc=frame:findColor(p.x,p.y,p.w,p.h,
            p.rmin,p.rmax,p.gmin,p.gmax,p.bmin,p.bmax,skip)
        if not hit then
          if hc=="NOT_FOUND" then
            add("colors",{status="NOT_FOUND",code="NOT_FOUND"})
          else
            add("colors",status(hc or "COLOR",he or "color query failed"))
          end
        elseif not number(hit.x,p.x,p.x+p.w-1) or
               not number(hit.y,p.y,p.y+p.h-1) or
               not normalizeRGB(hit) or
               hit.red<p.rmin or hit.red>p.rmax or
               hit.green<p.gmin or hit.green>p.gmax or
               hit.blue<p.bmin or hit.blue>p.bmax then
          add("colors",status("MISMATCH","native color result failed validation"))
        else
          add("colors",{status="PASS",x=hit.x,y=hit.y,rgb=hit})
        end
      end
    end
    for _,p in ipairs(cfg.ocr) do
      if not region(p,w,h) then
        add("ocr",status("INVALID","OCR region invalid"))
      elseif p.language~=nil and
          (type(p.language)~="string" or #p.language>64 or
           p.language:find("[\r\n%z]")) then
        add("ocr",status("INVALID","OCR language invalid"))
      else
        local text,re,rc=frame:ocr(p.x,p.y,p.w,p.h,p.language or "")
        if text==nil then
          add("ocr",status(rc or "OCR",re or "Vision OCR failed"))
        else
          local item={status=#text>0 and "PASS" or "EMPTY",bytes=#text}
          -- OCR may contain private information; only return it on explicit
          -- in-memory opt-in, and NEVER put it in automatic reports.
          if options.include_text==true then item.text=text end
          add("ocr",item)
        end
      end
    end
    for _,p in ipairs(cfg.templates) do
      if type(p.path)~="string" or p.path=="" or #p.path>1024 or
         p.path:find("[%z\r\n]") then
        add("templates",status("INVALID","template path invalid"))
      else
        local hit,err,code=frame:findImage(p.path,2,p.confidence or 0.8,
                                           p.scale or 0.8)
        if hit then
          add("templates",{status="PASS",hit=hit})
        elseif code=="NOT_FOUND" then
          add("templates",{status="NOT_FOUND",code=code})
        else
          add("templates",status(code or "TEMPLATE",err or "template failed"))
        end
      end
    end
    return output
  end)
  if not data then return nil,frameError or "frame capture failed",frameCode or "FRAME" end
  if type(data)~="table" then return nil,"invalid frame result","FRAME" end
  data.frame_count=count
  return data
end
local function waitRead(probe,opts)
  opts=opts or {}
  if type(opts)~="table" then return invalid("options must be table") end
  local stability=require("nkstability")
  return stability.pollRead(probe,{
    read_only=true,retry_not_found=true,
    max_attempts=opts.max_attempts or 5,
    timeout_ms=opts.timeout_ms or 3000,
    interval_ms=opts.interval_ms or 200,
    now=opts.now,sleep=opts.sleep
  })
end
function M.waitText(needle,rect,opts)
  if type(needle)~="string" or #needle==0 or #needle>256 or
     not utf8.len(needle) or type(rect)~="table" then
    return invalid("nonempty UTF-8 text and OCR rectangle required")
  end
  opts=opts or {}
  return waitRead(function()
    local output,e,c=M.capture({ocr={{
      x=rect.x,y=rect.y,w=rect.w,h=rect.h,language=rect.language
    }}},{nk=opts.nk,include_text=true})
    if not output then return nil,e,c end
    local item=output.ocr[1]
    if not item then return nil,"OCR result missing","OCR" end
    if item.status=="FAIL" then return nil,item.detail,item.code end
    if type(item.text)=="string" and item.text:find(needle,1,true) then
      return {found=true,bytes=item.bytes}
    end
    return nil,"text not found yet","NOT_FOUND"
  end,opts)
end
function M.waitColor(rect,opts)
  if type(rect)~="table" then return invalid("color rectangle required") end
  opts=opts or {}
  return waitRead(function()
    local output,e,c=M.capture({colors={rect}},{nk=opts.nk})
    if not output then return nil,e,c end
    local item=output.colors[1]
    if item.status=="PASS" then
      return {found=true,x=item.x,y=item.y,rgb=item.rgb}
    end
    if item.status=="NOT_FOUND" then return nil,"color not yet found","NOT_FOUND" end
    return nil,item.detail,item.code
  end,opts)
end
return M
