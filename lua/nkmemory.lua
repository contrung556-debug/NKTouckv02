-- NKTouch Memory Core (development). Explicit, safe Lua-heap GC only.
-- This module does NOT forcibly clear iOS RAM, kill apps, restart SpringBoard,
-- clear unrelated app caches, or free live Vision frames owned by callers.
local M={VERSION="0.7.17-memory-dev"}
local function finiteInt(n,lo,hi)
  return type(n)=="number" and n==n and n~=math.huge and n~=-math.huge
      and n%1==0 and n>=lo and n<=hi
end
local function gc(op,n)
  if type(collectgarbage)~="function" then return nil,"Lua GC unavailable","NO_GC" end
  local ok,result=pcall(collectgarbage,op,n)
  if not ok then return nil,tostring(result),"GC" end
  return result
end
local function kbytes()
  local value,err,code=gc("count")
  if value==nil then return nil,err,code end
  return value
end
local function rounded(n) return math.floor(n*100+0.5)/100 end
-- This reads only our own process. iOS can cache freed pages, so RSS
-- need not fall after Lua collection; report measurements, not a promise.
local function resident()
  local loaded,native=pcall(require,"nkvision_native")
  if not loaded or type(native)~="table" or type(native.memoryStats)~="function" then
    return nil
  end
  local ok,value=pcall(native.memoryStats)
  if not ok or type(value)~="table" or type(value.rss_bytes)~="number" then
    return nil
  end
  if value.rss_bytes<0 or value.rss_bytes~=value.rss_bytes then return nil end
  return value
end

function M.stats()
  local kb,err,code=kbytes()
  if not kb then return nil,err,code end
  local process=resident()
  return {
    lua_kb=rounded(kb),
    scope="LUA_HEAP_AND_OPTIONAL_PROCESS_RSS",
    process_rss_available=process~=nil,
    process_rss_bytes=process and process.rss_bytes or nil,
    process_virtual_bytes=process and process.virtual_bytes or nil,
    native_frames_managed_separately=true
  }
end

function M.release(opts)
  if opts==nil then opts={} end
  if type(opts)~="table" then return nil,"options must be a table","INVALID" end
  local mode=opts.mode or "step"
  if mode~="step" and mode~="full" then
    return nil,"mode must be step or full","INVALID"
  end
  local step=opts.step_kb or 64
  if not finiteInt(step,8,1024) then
    return nil,"step_kb must be integer 8..1024","INVALID"
  end
  local before,err,code=kbytes()
  if not before then return nil,err,code end
  local rssBefore=resident()
  local ok,gcErr,gcCode
  if mode=="full" then ok,gcErr,gcCode=gc("collect")
  else ok,gcErr,gcCode=gc("step",step) end
  if ok==nil then return nil,gcErr,gcCode end
  local after,afterErr,afterCode=kbytes()
  if not after then return nil,afterErr,afterCode end
  local rssAfter=resident()
  return {
    mode=mode,
    lua_kb_before=rounded(before),
    lua_kb_after=rounded(after),
    reclaimed_lua_kb=rounded(math.max(0,before-after)),
    scope="LUA_HEAP_AND_OPTIONAL_PROCESS_RSS",
    process_rss_available=rssBefore~=nil and rssAfter~=nil,
    process_rss_before=rssBefore and rssBefore.rss_bytes or nil,
    process_rss_after=rssAfter and rssAfter.rss_bytes or nil,
    note="RSS may not decrease after GC. Native Vision buffers need frame:close()."
  }
end

return M
