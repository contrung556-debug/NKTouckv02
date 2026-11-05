-- NKTouch 0.7.16-dev: explicit coordinate units and screen geometry.
-- No device calls or automatic rescaling. Never guess a rotation / Retina ratio.
-- Inputs and returned coordinates refer to physical pixels by default.
local M={VERSION="0.7.16-dev"}
local function finite(n)
  return type(n)=="number" and n==n and n~=math.huge and n~=-math.huge
end
local function integer(n,lo,hi)
  return finite(n) and n%1==0 and n>=lo and n<=hi
end
local function invalid(msg) return nil,msg,"INVALID" end

function M.screen(raw)
  if type(raw)~="string" then return invalid("screen must be a string") end
  local w,h=raw:match("^%s*(%d+%.?%d*)%s*;;%s*(%d+%.?%d*)%s*$")
  w,h=tonumber(w),tonumber(h)
  if not finite(w) or not finite(h) or w<200 or h<300 or
      w>10000 or h>10000 or w%1~=0 or h%1~=0 then
    return invalid("screen needs integer physical width;;height")
  end
  return {width=w,height=h,units="physical_pixels"}
end

function M.point(x,y,geometry,opts)
  if type(geometry)~="table" or
      not integer(geometry.width,1,10000) or
      not integer(geometry.height,1,10000) then
    return invalid("explicit physical screen geometry is required")
  end
  opts=opts or {}
  if type(opts)~="table" then return invalid("options must be table") end
  local units=opts.units or "pixel"
  local scale=opts.scale
  if units=="pixel" then
    if scale~=nil then return invalid("pixel inputs must not specify scale") end
    scale=1
  elseif units=="point" then
    if not finite(scale) or scale<=0 or scale>8 then
      return invalid("points require an explicit finite display scale")
    end
  else return invalid("units must be pixel or point") end
  if not finite(x) or not finite(y) then return invalid("finite coordinates required") end
  local px,py=x*scale,y*scale
  if not finite(px) or not finite(py) or
     px<0 or py<0 or px>=geometry.width or py>=geometry.height then
    return nil,"coordinates outside physical screen bounds","OUT_OF_BOUNDS"
  end
  -- Round only after verifying that the rounded pixel is still in
  -- bounds. A coordinate 749.8 on a 750-wide screen rounds to 750,
  -- which is NOT a valid pixel index.
  local ix,iy=math.floor(px+0.5),math.floor(py+0.5)
  if ix>=geometry.width or iy>=geometry.height then
    return nil,"rounded pixel outside physical screen","OUT_OF_BOUNDS"
  end
  return {x=ix,y=iy,units="physical_pixels",input_units=units}
end

function M.inspectFrame(geometry,frame)
  if type(geometry)~="table" or type(frame)~="table" then
    return invalid("screen and frame required")
  end
  local sw,sh,fw,fh=geometry.width,geometry.height,frame.width,frame.height
  if not integer(sw,1,10000) or not integer(sh,1,10000) or
     not integer(fw,1,10000) or not integer(fh,1,10000) then
    return invalid("frame/screen dimensions must be positive integers")
  end
  if sw==fw and sh==fh then
    return {matches=true,kind="IDENTICAL",message="pixel geometry agrees"}
  end
  if sw==fh and sh==fw then
    return {matches=false,kind="ROTATED_90",
            message="frame appears transposed; do not transform automatically"}
  end
  if sw/fw==sh/fh then
    return {matches=false,kind="SCALE_MISMATCH",
            scale=sw/fw,message="frame-to-screen scale differs; manual verification required"}
  end
  return {matches=false,kind="GEOMETRY_MISMATCH",
          message="screen/frame pixels disagree; rotation/crop must be calibrated"}
end

function M.path(points,geometry)
  if type(points)~="table" then return invalid("path must be table") end
  local n=#points
  if n<2 or n>256 then return invalid("path needs 2..256 points") end
  local out,last={},-1
  for i=1,n do
    local p=points[i]
    if type(p)~="table" or not integer(p.t,0,300000) then
      return invalid("path timestamp invalid at "..i)
    end
    if (i==1 and p.t~=0) or (i>1 and p.t<=last) then
      return invalid("path timestamps must start at 0 and increase")
    end
    local pos,err,code=M.point(p.x,p.y,geometry,{units="pixel"})
    if not pos then return nil,("path point %d: %s"):format(i,err),code end
    out[#out+1]={x=pos.x,y=pos.y,t=p.t}
    last=p.t
  end
  return out
end
return M
