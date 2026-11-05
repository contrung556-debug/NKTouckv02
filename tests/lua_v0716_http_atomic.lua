-- NKTouch v0.7.16 dev HTTP offline test.
-- Requires existing dir and env NKTOUCH_HTTP_TMP=<existing subdir>.
-- NO internet requests are issued. Simulates the native nkhttp helper.
package.path="lua/?.lua;"..package.path
local tmp=assert(arg[1],"temporary directory argument required")
local network=require("nknet")
local calls=0
local failTransport=true
local originalExecute=os.execute
local function readAll(path)
  local f=assert(io.open(path,"rb"))
  local data=assert(f:read("*a"));assert(f:close());return data
end
local function writeAll(path,data)
  local f=assert(io.open(path,"wb"))
  assert(f:write(data));assert(f:close())
end
local target=tmp.."/user-existing.txt"
writeAll(target,"MY_ORIGINAL_CONTENT")
os.execute=function(cmd)
  if cmd:find("mkdir %-p") then return true,"exit",0 end
  local specPath=cmd:match(" request '([^']+)'")
  assert(specPath and specPath~="","unexpected os.execute: "..tostring(cmd))
  calls=calls+1
  local spec={}
  for line in readAll(specPath):gmatch("[^\r\n]+") do
    local k,v=line:match("^([^=]+)=(.*)$")
    spec[k]=v
  end
  assert(spec.response_file~=target,"nkhttp helper must not write user target directly")
  assert(spec.max_response_bytes=="1000")
  if failTransport then
    writeAll(spec.response_file,"TRUNCATED_NETWORK_REPLY")
    writeAll(spec.meta_file,
      "status=0\nbytes=23\nerror_code=7\nerror=connection lost\n")
    return false,"exit",7
  end
  local reply='{"value":"Xin chào Việt Nam"}'
  writeAll(spec.response_file,reply)
  writeAll(spec.meta_file,
     "status=200\nbytes="..#reply..
     "\ncontent_type=application/json\nfinal_url=https://example.com/data"..
     "\nerror_code=0\n")
  return true,"exit",0
end
local function preflight(o)
  local old=calls
  local v,e,c=network.request(o)
  assert(v==nil and c=="INVALID", "expected preflight INVALID: "..tostring(e).." "..tostring(c))
  assert(calls==old,"invalid arguments reached HTTP helper")
end
preflight({url="https://example.com/a\0fake",timeout_ms=1000})
preflight({url="https://example.com",timeout_ms=math.huge})
preflight({url="https://example.com",timeout_ms=0/0})
preflight({url="https://example.com",timeout_ms=101.5})
preflight({url="https://example.com",max_bytes=1/0})
preflight({url="https://example.com",save_to=tmp.."/out\0evil"})
preflight({url="https://example.com",headers="invalid"})
preflight({url="https://example.com",overwrite="yes"})
preflight({url="https://",timeout_ms=1000})
local bad,e,c=network.request({
 url="https://example.com/data",timeout_ms=1000,max_bytes=1000,
 headers={["X-Test"]="bad\0data"}
})
assert(bad==nil and c=="INVALID" and calls==0,"NUL header must be rejected")
local old,e,c=network.request({url="https://example.com/data",save_to=target,
  overwrite=true,max_bytes=1000,timeout_ms=1000})
assert(old==nil and c=="NETWORK" and calls==1,"simulated network failure expected")
assert(readAll(target)=="MY_ORIGINAL_CONTENT","failed HTTP wiped user file!")
-- Subsequent success may replace only after helper returns complete result.
failTransport=false
local result,e,c=network.request({url="https://example.com/data",save_to=target,
  overwrite=true,max_bytes=1000,timeout_ms=1000})
assert(result and result.status==200 and result.ok and result.path==target,
       "HTTP success and final path required "..tostring(e or c))
assert(readAll(target)=='{"value":"Xin chào Việt Nam"}')
local count=0
local p=io.popen("find "..string.format("%q",tmp).." -name '*.part' -print")
if p then for line in p:lines() do count=count+1 end;p:close() end
assert(count==0,"temporary partial downloads leaked")
os.execute=originalExecute
print("[NKQA][HTTP_ATOMIC] PASS helper_calls="..calls.." no network/no original data loss")
