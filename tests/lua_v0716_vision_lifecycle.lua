-- NKTouch 0.7.16-dev Vision frame lifecycle tests.
-- No screen capture: mocked immutable frame / secure temporary JPEG cleanup.
package.path="lua/?.lua;"..package.path
local vision=require("nkvision")
local base=assert(arg[1],"existing temporary directory argument required")
local nextID,captured,opened,closed=0,0,0,0
local lastPath
local failOpen=false
local function exists(path)
 local f=io.open(path,"rb"); if not f then return false end
 f:close();return true
end
package.preload.nkvision_native=function()
 return {
  tempPath=function()
    nextID=nextID+1
    lastPath=base.."/frame-"..nextID..".jpg"
    local f=assert(io.open(lastPath,"wb"))
    f:close()
    return lastPath
  end,
  open=function(path)
    assert(exists(path),"native.open must read a captured file")
    if failOpen then return nil,"invalid image","DECODE" end
    opened=opened+1
    local frame={isClosed=false}
    function frame:info()
      assert(not self.isClosed)
      return {width=750,height=1334}
    end
    function frame:getColor(x,y)
      assert(not self.isClosed)
      return {red=x%255,green=y%255,blue=4}
    end
    function frame:close()
      assert(not self.isClosed,"frame closed twice")
      self.isClosed=true
      closed=closed+1
      return true
    end
    return frame
  end
 }
end
local nk={
 screenshot=function(path)
   captured=captured+1
   local f=assert(io.open(path,"wb"))
   assert(f:write("fake-jpeg-private-test-data"))
   assert(f:close())
   return path
 end
}
local ok,dimensions=vision.withFrame(nk,function(frame)
 local a=frame:info()
 local p=frame:getColor(20,25)
 local second=frame:getColor(20,25)
 assert(p.red==second.red and a.width==750)
 return true,a
end)
assert(ok and dimensions.width==750)
assert(captured==1 and opened==1 and closed==1)
assert(not exists(lastPath),"frame temp JPEG must be deleted")
local a,b,c=vision.withFrame(nk,function(frame)
 assert(frame:info().height==1334)
 error("intentional callback failure")
end)
assert(a==nil and c=="CALLBACK" and closed==2)
assert(not exists(lastPath))
local ret,msg,code=vision.withFrame(nk,function(frame)
 return nil,"conditional query not found","NOT_FOUND"
end)
assert(ret==nil and msg=="conditional query not found" and code=="NOT_FOUND")
assert(closed==3 and not exists(lastPath))
failOpen=true
ret,msg,code=vision.capture(nk)
assert(ret==nil and code=="DECODE" and closed==3)
assert(not exists(lastPath),"failed decoder must clean temp JPEG")
print(("[NKQA][VISION] PASS captures=%d opens=%d closes=%d temp_leaks=0"):format(captured,opened,closed))
