-- NKTouch v0.7.4 JSON codec
-- SPDX-License-Identifier: GPL-3.0-or-later
local M = {}
M.VERSION = "0.7.4"
M.null = setmetatable({}, {__tostring=function() return "null" end})

local ARRAY_MT = {__jsontype="array"}
local OBJECT_MT = {__jsontype="object"}
function M.array(t) return setmetatable(t or {}, ARRAY_MT) end
function M.object(t) return setmetatable(t or {}, OBJECT_MT) end

local function esc(s)
  local map={['"']='\\"',['\\']='\\\\',['\b']='\\b',['\f']='\\f',['\n']='\\n',['\r']='\\r',['\t']='\\t'}
  return '"'..s:gsub('[%z\1-\31\\"]', function(c)
    return map[c] or string.format('\\u%04x', c:byte())
  end)..'"'
end

local function is_array(t)
  local mt=getmetatable(t)
  if mt==ARRAY_MT or (mt and mt.__jsontype=="array") then
    local n=0
    for k in pairs(t) do
      if type(k)~="number" or k<1 or k%1~=0 then return false,"tagged array has non-integer key" end
      if k>n then n=k end
    end
    for i=1,n do if rawget(t,i)==nil then return false,"tagged array has holes" end end
    return true,n
  end
  if mt==OBJECT_MT or (mt and mt.__jsontype=="object") then return false,nil end
  local n,count=0,0
  for k in pairs(t) do
    if type(k)~="number" or k<1 or k%1~=0 then return false,nil end
    if k>n then n=k end
    count=count+1
  end
  if count==0 then return false,nil end
  if n~=count then return false,"array has holes" end
  return true,n
end

local function encode_value(v, seen, depth)
  if depth>64 then error("JSON nesting too deep",0) end
  local tv=type(v)
  if v==M.null then return "null" end
  if tv=="nil" then return "null" end
  if tv=="boolean" then return v and "true" or "false" end
  if tv=="number" then
    if v~=v or v==math.huge or v==-math.huge then error("JSON cannot encode non-finite number",0) end
    return string.format("%.17g",v)
  end
  if tv=="string" then return esc(v) end
  if tv~="table" then error("JSON unsupported type: "..tv,0) end
  if seen[v] then error("JSON circular table",0) end
  seen[v]=true
  local arr,n_or_err=is_array(v)
  local out={}
  if arr then
    for i=1,n_or_err do out[#out+1]=encode_value(v[i],seen,depth+1) end
    seen[v]=nil
    return "["..table.concat(out,",").."]"
  elseif n_or_err then
    seen[v]=nil
    error(n_or_err,0)
  end
  for k,val in pairs(v) do
    if type(k)~="string" then seen[v]=nil; error("JSON object keys must be strings",0) end
    out[#out+1]=esc(k)..":"..encode_value(val,seen,depth+1)
  end
  table.sort(out)
  seen[v]=nil
  return "{"..table.concat(out,",").."}"
end

function M.encode(v)
  local ok,res=pcall(encode_value,v,{},0)
  if not ok then return nil,res end
  return res
end

local function decoder(s)
  local p,n=1,#s
  local function fail(msg) error(string.format("JSON error at byte %d: %s",p,msg),0) end
  local function ws() while p<=n and s:sub(p,p):match("%s") do p=p+1 end end
  local parse

  local function hex4()
    local h=s:sub(p,p+3)
    if #h~=4 or not h:match("^[0-9a-fA-F]+$") then fail("invalid unicode escape") end
    p=p+4
    return tonumber(h,16)
  end

  local function stringv()
    if s:sub(p,p)~='"' then fail("expected string") end
    p=p+1
    local out={}
    while p<=n do
      local c=s:sub(p,p)
      if c=='"' then p=p+1; return table.concat(out) end
      if c=='\\' then
        p=p+1
        local e=s:sub(p,p)
        if e=='' then fail("unterminated escape") end
        local map={['"']='"',['\\']='\\',['/']='/',b='\b',f='\f',n='\n',r='\r',t='\t'}
        if map[e] then out[#out+1]=map[e]; p=p+1
        elseif e=='u' then
          p=p+1
          local cp=hex4()
          if cp>=0xD800 and cp<=0xDBFF then
            if s:sub(p,p+1)~='\\u' then fail("missing low surrogate") end
            p=p+2
            local lo=hex4()
            if lo<0xDC00 or lo>0xDFFF then fail("invalid low surrogate") end
            cp=0x10000+(cp-0xD800)*0x400+(lo-0xDC00)
          elseif cp>=0xDC00 and cp<=0xDFFF then fail("unexpected low surrogate") end
          local ok,ch=pcall(utf8.char,cp); if not ok then fail("invalid unicode codepoint") end
          out[#out+1]=ch
        else fail("invalid escape") end
      else
        if c:byte()<0x20 then fail("control character in string") end
        out[#out+1]=c; p=p+1
      end
    end
    fail("unterminated string")
  end

  local function numberv()
    local start=p
    if s:sub(p,p)=='-' then p=p+1 end
    local c=s:sub(p,p)
    if c=='0' then p=p+1
    elseif c:match('[1-9]') then repeat p=p+1; c=s:sub(p,p) until not c:match('%d')
    else fail("invalid number") end
    if s:sub(p,p)=='.' then
      p=p+1
      if not s:sub(p,p):match('%d') then fail("invalid fraction") end
      repeat p=p+1 until not s:sub(p,p):match('%d')
    end
    c=s:sub(p,p)
    if c=='e' or c=='E' then
      p=p+1; c=s:sub(p,p)
      if c=='+' or c=='-' then p=p+1 end
      if not s:sub(p,p):match('%d') then fail("invalid exponent") end
      repeat p=p+1 until not s:sub(p,p):match('%d')
    end
    local v=tonumber(s:sub(start,p-1)); if not v then fail("invalid number") end
    return v
  end

  local function arrayv(depth)
    p=p+1; ws(); local a=M.array({})
    if s:sub(p,p)==']' then p=p+1; return a end
    while true do
      a[#a+1]=parse(depth+1); ws()
      local c=s:sub(p,p)
      if c==']' then p=p+1; return a end
      if c~=',' then fail("expected ',' or ']'") end
      p=p+1; ws()
    end
  end

  local function objectv(depth)
    p=p+1; ws(); local o=M.object({})
    if s:sub(p,p)=='}' then p=p+1; return o end
    while true do
      if s:sub(p,p)~='"' then fail("expected object key") end
      local k=stringv(); ws()
      if s:sub(p,p)~=':' then fail("expected ':'") end
      p=p+1; ws(); o[k]=parse(depth+1); ws()
      local c=s:sub(p,p)
      if c=='}' then p=p+1; return o end
      if c~=',' then fail("expected ',' or '}'") end
      p=p+1; ws()
    end
  end

  parse=function(depth)
    if depth>64 then fail("nesting too deep") end
    ws(); local c=s:sub(p,p)
    if c=='"' then return stringv() end
    if c=='{' then return objectv(depth) end
    if c=='[' then return arrayv(depth) end
    if c=='-' or c:match('%d') then return numberv() end
    if s:sub(p,p+3)=='true' then p=p+4; return true end
    if s:sub(p,p+4)=='false' then p=p+5; return false end
    if s:sub(p,p+3)=='null' then p=p+4; return M.null end
    fail("unexpected token")
  end

  local v=parse(0); ws(); if p<=n then fail("trailing data") end
  return v
end

function M.decode(s)
  if type(s)~="string" then return nil,"JSON input must be a string" end
  local ok,res=pcall(decoder,s)
  if not ok then return nil,res end
  return res
end

return M
