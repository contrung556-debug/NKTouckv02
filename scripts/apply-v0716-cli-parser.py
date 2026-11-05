#!/usr/bin/env python3
"""Fix legacy CLI reply decoding and wait timing in staged nktouch.lua only.

The direct native bridge remains unchanged. Legacy fallback must not return
nil-filled rects, throw on malformed RGB, or treat no-match sentinels as hits.
"""
from pathlib import Path
import sys

if len(sys.argv)!=2:
    raise SystemExit("usage: apply-v0716-cli-parser.py <staged-upstream>")
p=Path(sys.argv[1])/"layout/usr/share/nktouch/lua/nktouch.lua"
if not p.is_file(): raise SystemExit("staged nktouch.lua missing")
s=p.read_text()
start=s.index("local function splitRect(s)\n")
end=s.index("local function nowMs()\n",start)
replacement=r'''-- Strict legacy CLI reply decoders. Read-only operations must distinguish
-- a valid result, NOT_FOUND, and a broken native/CLI wire response.
local function wireNumbers(s,count)
  if type(s)~="string" or s=="" then
    return nil,"empty CLI reply","PARSE"
  end
  local out={}
  -- The wire format is numeric fields joined by exactly ";;".
  if s:find("[\r\n]") or s:find(";;;") or s:find(";;",1,true)==nil then
    return nil,"malformed CLI separator","PARSE"
  end
  local remaining=s
  for i=1,count-1 do
    local pos=remaining:find(";;",1,true)
    if not pos then return nil,"missing CLI field","PARSE" end
    local field=remaining:sub(1,pos-1)
    if field=="" then return nil,"empty CLI field","PARSE" end
    local n=tonumber(field)
    if not n or n~=n or n==math.huge or n==-math.huge then
      return nil,"non-finite CLI field","PARSE"
    end
    out[i]=n
    remaining=remaining:sub(pos+2)
  end
  if remaining=="" or remaining:find(";;",1,true) then
    return nil,"wrong CLI field count","PARSE"
  end
  local n=tonumber(remaining)
  if not n or n~=n or n==math.huge or n==-math.huge then
    return nil,"invalid last CLI field","PARSE"
  end
  out[count]=n
  return out
end

local function splitRect(s)
  local v,err,kind=wireNumbers(s,4)
  if not v then return nil,err,kind end
  if v[1]==-1 and v[2]==-1 then return nil,"image not found","NOT_FOUND" end
  if v[1]<0 or v[2]<0 or v[3]<0 or v[4]<0
    or v[1]>10000 or v[2]>10000 or v[3]>10000 or v[4]>10000 then
    return nil,"image rectangle out of range","PARSE"
  end
  return {x=v[1],y=v[2],width=v[3],height=v[4]}
end

local function splitColor(s,withPos)
  local v,err,kind=wireNumbers(s,withPos and 5 or 3)
  if not v then return nil,err,kind end
  local first=withPos and 3 or 1
  if withPos and v[1]==-1 and v[2]==-1 then
    return nil,"color not found","NOT_FOUND"
  end
  for i=first,first+2 do
    if v[i]<0 or v[i]>255 or v[i]%1~=0 then
      return nil,"RGB reply outside 0..255","PARSE"
    end
  end
  if withPos and (v[1]<0 or v[2]<0 or v[1]>10000 or v[2]>10000
    or v[1]%1~=0 or v[2]%1~=0) then
    return nil,"color hit coordinates out of range","PARSE"
  end
  local r,g,b=v[first],v[first+1],v[first+2]
  local result={red=r,green=g,blue=b,packed=r*65536+g*256+b}
  if withPos then result.x=v[1]; result.y=v[2] end
  return result
end

'''
s=s[:start]+replacement+s[end:]
# If core.nowMs is absent, CPU-time os.clock() is not a wall-clock timeout;
# a sleeping loop could run far longer than intended. Use coarse wall-clock.
needle='  return math.floor(os.clock()*1000)\nend\n\nlocal function coreWait('
assert s.count(needle)==1,"unexpected clock fallback baseline"
s=s.replace(needle,'  return os.time()*1000\nend\n\nlocal function coreWait(',1)
# Clamp the next sleep to remaining time so a short timeout never sleeps for
# the full interval; do not spin if the app is busy.
needle='    if core and core.sleep then core.sleep(interval) end\n'
assert s.count(needle)==1,"unexpected wait sleep baseline"
s=s.replace(needle,'''    if core and core.sleep then
      local remain=math.max(0,deadline-nowMs())
      if remain>0 then core.sleep(math.min(interval,remain)) end
    end
''',1)
p.write_text(s)
print("NKTouch dev: legacy CLI parsing and bounded wait logic hardened")
