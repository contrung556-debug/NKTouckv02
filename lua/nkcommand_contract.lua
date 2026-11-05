-- NKTouch 0.7.16 development: strict Lua argument contracts.
-- Applied to the staged nktouch.lua AFTER the v0.7.15 baseline patches.
-- No native/touch/keyboard protocol changes; no automatic mutation retries.
-- Each invalid invocation returns nil, message, "INVALID" BEFORE any side effect.
local M={VERSION="0.7.16-dev"}
local function number(v,lo,hi,integer)
  local n=tonumber(v)
  return n and n==n and n~=math.huge and n~=-math.huge
     and n>=lo and n<=hi and (not integer or n%1==0)
end
local function text(v,max,required)
  return type(v)=="string" and #v<=max
     and (not required or #v>0)
     and not v:find("[\r\n]") and not v:find(";;",1,true)
     and not v:find("\0",1,true)
end
local function coord(x,y)
  return number(x,0,9999.9,false) and number(y,0,9999.9,false)
end
local function pixel(x,y)
  return number(x,0,10000,true) and number(y,0,10000,true)
end
local function duration(v,default,lo,hi)
  return v==nil or number(v,lo,hi,true)
end
local function app(v)
  return text(v,255,true) and v:match("^[%w_.%-]+$") and v:find(".",1,true)
end
local function timeout(t,i,defaultInterval)
  return duration(t,0,0,300000)
     and duration(i,defaultInterval,50,10000)
end
local function rgb(v) return number(v,0,255,true) end

local function colorRegion(x,y,w,h,rmin,rmax,gmin,gmax,bmin,bmax,skip)
  return pixel(x,y)
     and number(w,0,10000,true) and number(h,0,10000,true)
     and rgb(rmin) and rgb(rmax) and rgb(gmin) and rgb(gmax)
     and rgb(bmin) and rgb(bmax)
     and tonumber(rmin)<=tonumber(rmax)
     and tonumber(gmin)<=tonumber(gmax)
     and tonumber(bmin)<=tonumber(bmax)
     and duration(skip,0,0,1000)
end

local function image(path,tries,confidence,scale)
  return text(path,500,true) and duration(tries,2,0,8)
     and (confidence==nil or number(confidence,0.000001,1,false))
     and (scale==nil or number(scale,0.050001,0.999999,false))
end
local function ocr(x,y,w,h,languages)
  return number(x,0,10000,false) and number(y,0,10000,false)
     and number(w,0.000001,10000,false)
     and number(h,0.000001,10000,false)
     and (languages==nil or text(languages,128,false))
end

function M.install(nk)
  assert(type(nk)=="table","NKTouch command contracts require API table")
  local function guard(name,check)
    local original=assert(nk[name],"missing NKTouch API: "..name)
    nk[name]=function(...)
      local ok,msg=check(...)
      if not ok then
        return nil,"invalid "..name.." arguments: "..tostring(msg or "out of range"),"INVALID"
      end
      return original(...)
    end
  end

  guard("tap",function(x,y)
    return coord(x,y),"x,y must be finite coordinates 0..9999.9"
  end)
  guard("hold",function(x,y,ms)
    return coord(x,y) and duration(ms,500,0,300000),
      "x,y or duration outside supported range"
  end)
  guard("swipe",function(x,y,x2,y2,ms)
    return coord(x,y) and coord(x2,y2) and duration(ms,400,32,300000),
      "coordinates or swipe duration invalid (32..300000ms)"
  end)
  guard("sleep",function(ms)
    return duration(ms,0,0,300000),"sleep must be 0..300000ms"
  end)
  guard("openApp",function(id)
    return app(id),"Bundle ID must be a simple nonempty identifier"
  end)
  guard("waitApp",function(id,ms,interval)
    return app(id) and timeout(ms,interval,200),
      "Bundle ID or wait interval/timeout invalid"
  end)
  guard("moveCursor",function(offset)
    return number(offset,-100000,100000,true),
      "offset must be an integer -100000..100000"
  end)
  guard("delete",function(count)
    return count==nil or number(count,0,100000,true),
      "count must be an integer 0..100000"
  end)
  guard("getColor",function(x,y)
    return pixel(x,y),"physical pixel x,y must be integer 0..10000"
  end)
  guard("findColor",function(...)
    return colorRegion(...),"pixel rectangle / RGB min-max / skip invalid"
  end)
  guard("waitColor",function(x,y,w,h,rmin,rmax,gmin,gmax,bmin,bmax,t,i,skip)
    return colorRegion(x,y,w,h,rmin,rmax,gmin,gmax,bmin,bmax,skip)
      and timeout(t,i,200),"color rectangle/timeout/interval invalid"
  end)
  guard("tapColor",function(x,y,w,h,rmin,rmax,gmin,gmax,bmin,bmax,t,i,skip)
    return colorRegion(x,y,w,h,rmin,rmax,gmin,gmax,bmin,bmax,skip)
      and timeout(t,i,200),"color rectangle/timeout/interval invalid"
  end)
  guard("findImage",function(path,n,confidence,scale)
    return image(path,n,confidence,scale),
       "image path/maxTry(0..8)/confidence/scale invalid"
  end)
  guard("waitImage",function(path,t,i,confidence)
    return image(path,2,confidence,0.8) and timeout(t,i,250),
       "image path, timeout, interval or confidence invalid"
  end)
  guard("tapImage",function(path,t,i,confidence)
    return image(path,2,confidence,0.8) and timeout(t,i,250),
       "image path, timeout, interval or confidence invalid"
  end)
  guard("ocr",function(x,y,w,h,lang)
    return ocr(x,y,w,h,lang),"OCR rectangle or language invalid"
  end)
  guard("waitText",function(x,y,w,h,needle,t,i,lang)
    return ocr(x,y,w,h,lang) and text(needle,1024,true)
       and timeout(t,i,300),"OCR region, required text or timeout invalid"
  end)
  guard("screenshot",function(path)
    return path==nil or text(path,1024,true),
       "screenshot path must be nonempty without line breaks"
  end)
  guard("status",function(percent,message)
    return (percent==nil or number(percent,0,100,false))
       and (message==nil or text(message,1024,false)),
       "status percent must be 0..100 and message a string"
  end)
  guard("toast",function(kind,message,seconds)
    return (kind==nil or
       ({error=true,warning=true,warn=true,message=true,info=true,success=true})[kind])
       and (message==nil or text(message,4096,false))
       and duration(seconds,2,1,60),
       "toast kind/message/duration invalid"
  end)
  -- Keep actions non-retrying. Preserve all the other original NKTouch APIs
  -- and their signatures; deeper native contracts remain on-device tests.
  nk.COMMAND_CONTRACT_VERSION=M.VERSION
  return nk
end

return M
