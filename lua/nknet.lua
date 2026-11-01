-- NKTouch v0.7.4 on-demand HTTP/HTTPS API
-- SPDX-License-Identifier: GPL-3.0-or-later
local json=require("nkjson")
local M={VERSION="0.7.4"}

local HELPER=os.getenv("NKTOUCH_HTTP_HELPER") or "/var/jb/usr/libexec/nktouch/nkhttp"
local TMP=os.getenv("NKTOUCH_HTTP_TMP") or "/var/mobile/Library/NKTouch/tmp/network"
local MAX_BODY=16*1024*1024
local MAX_RESPONSE=32*1024*1024
local seq=0

local function shq(s) return "'"..tostring(s):gsub("'","'\\''").."'" end
local function status_ok(a,b,c)
  if type(a)=="boolean" then return a,tonumber(c) or (a and 0 or 1) end
  if type(a)=="number" then return a==0,a end
  return false,tonumber(c) or 1
end
local function mkdir_tmp()
  local a,b,c=os.execute("mkdir -p "..shq(TMP).." >/dev/null 2>&1")
  local ok=status_ok(a,b,c); return ok
end
local function exists(path)
  local f=io.open(path,"rb"); if f then f:close(); return true end; return false
end
local function filesize(path)
  local f=io.open(path,"rb"); if not f then return nil end
  local n=f:seek("end"); f:close(); return n
end
local function writefile(path,data)
  local f,err=io.open(path,"wb"); if not f then return nil,err end
  local ok,werr=f:write(data); f:close(); if not ok then return nil,werr end
  return true
end
local function readfile(path,limit)
  local f,err=io.open(path,"rb"); if not f then return nil,err end
  local n=f:seek("end") or 0; f:seek("set",0)
  if limit and n>limit then f:close(); return nil,"response exceeds Lua read limit" end
  local data=f:read("*a"); f:close(); return data
end
local function cleanup(paths) for _,p in ipairs(paths) do if p and p~="" then os.remove(p) end end end
local function unique()
  seq=seq+1
  local t=os.time()
  local clock=math.floor((os.clock()%1)*1000000)
  return string.format("%d-%d-%d",t,clock,seq)
end
local function line_safe(s) return type(s)=="string" and not s:find("[\r\n]") end
local METHODS={GET=true,POST=true,PUT=true,PATCH=true,DELETE=true,HEAD=true,OPTIONS=true}

local function headers_file(path,headers)
  if headers==nil then return writefile(path,"") end
  if type(headers)~="table" then return nil,"headers must be a table" end
  local lines={}
  for k,v in pairs(headers) do
    k=tostring(k); v=tostring(v)
    if not line_safe(k) or k=="" or k:find(":",1,true) or not k:match("^[!#$%%&'*+.^_`|~0-9A-Za-z-]+$") then return nil,"invalid HTTP header name" end
    if not line_safe(v) then return nil,"invalid HTTP header value" end
    lines[#lines+1]=k..": "..v
  end
  table.sort(lines)
  return writefile(path,table.concat(lines,"\n")..(#lines>0 and "\n" or ""))
end

local function parse_meta(path)
  local data,err=readfile(path,64*1024); if not data then return nil,err end
  local m={}
  for line in data:gmatch("[^\r\n]+") do
    local k,v=line:match("^([A-Za-z0-9_]+)=(.*)$")
    if k then m[k]=v end
  end
  m.status=tonumber(m.status) or 0
  m.bytes=tonumber(m.bytes) or 0
  m.error_code=tonumber(m.error_code) or 0
  return m
end

function M.request(opts)
  if type(opts)~="table" then return nil,"request options must be a table","INVALID" end
  local url=opts.url
  if not line_safe(url or "") or url=="" or not url:match("^https?://") then return nil,"url must be http:// or https://","INVALID" end
  local method=tostring(opts.method or "GET"):upper()
  if not METHODS[method] then return nil,"unsupported HTTP method","INVALID" end
  local timeout=math.floor(tonumber(opts.timeout_ms) or 15000)
  if timeout<100 or timeout>120000 then return nil,"timeout_ms must be 100..120000","INVALID" end
  local maxbytes=math.floor(tonumber(opts.max_bytes) or (opts.save_to and MAX_RESPONSE or 8*1024*1024))
  if maxbytes<1 or maxbytes>MAX_RESPONSE then return nil,"max_bytes must be 1..33554432","INVALID" end
  if opts.body~=nil and opts.json~=nil then return nil,"body and json are mutually exclusive","INVALID" end
  if opts.body_file~=nil and (opts.body~=nil or opts.json~=nil) then return nil,"body_file cannot be combined with body/json","INVALID" end
  if not mkdir_tmp() then return nil,"cannot create network temp directory","IO" end

  local id=unique()
  local spec=TMP.."/req-"..id..".txt"
  local hdr=TMP.."/hdr-"..id..".txt"
  local bodytmp=TMP.."/body-"..id..".bin"
  local metap=TMP.."/meta-"..id..".txt"
  local response=opts.save_to or (TMP.."/resp-"..id..".bin")
  local temps={spec,hdr,metap}; if not opts.save_to then temps[#temps+1]=response end
  local bodyfile="-"

  if opts.save_to then
    if not line_safe(opts.save_to) or opts.save_to=="" then cleanup(temps); return nil,"invalid save_to path","INVALID" end
    if exists(opts.save_to) and not opts.overwrite then cleanup(temps); return nil,"save_to already exists; set overwrite=true to replace","EXISTS" end
  end

  local headers={}
  if opts.headers then for k,v in pairs(opts.headers) do headers[k]=v end end
  if opts.json~=nil then
    local encoded,jerr=json.encode(opts.json); if not encoded then cleanup(temps); return nil,jerr,"JSON" end
    if #encoded>MAX_BODY then cleanup(temps); return nil,"JSON body too large","LIMIT" end
    local ok,err=writefile(bodytmp,encoded); if not ok then cleanup(temps); return nil,err,"IO" end
    temps[#temps+1]=bodytmp; bodyfile=bodytmp
    local hasct=false; for k in pairs(headers) do if tostring(k):lower()=="content-type" then hasct=true end end
    if not hasct then headers["Content-Type"]="application/json" end
  elseif opts.body~=nil then
    if type(opts.body)~="string" then cleanup(temps); return nil,"body must be a string","INVALID" end
    if #opts.body>MAX_BODY then cleanup(temps); return nil,"request body too large","LIMIT" end
    local ok,err=writefile(bodytmp,opts.body); if not ok then cleanup(temps); return nil,err,"IO" end
    temps[#temps+1]=bodytmp; bodyfile=bodytmp
  elseif opts.body_file~=nil then
    if not line_safe(opts.body_file) or not exists(opts.body_file) then cleanup(temps); return nil,"body_file not readable","IO" end
    local n=filesize(opts.body_file); if not n or n>MAX_BODY then cleanup(temps); return nil,"body_file too large","LIMIT" end
    bodyfile=opts.body_file
  end

  local ok,herr=headers_file(hdr,headers); if not ok then cleanup(temps); return nil,herr,"INVALID" end
  local lines={
    "method="..method,
    "url="..url,
    "timeout_ms="..timeout,
    "headers_file="..hdr,
    "body_file="..bodyfile,
    "response_file="..response,
    "meta_file="..metap,
    "max_response_bytes="..maxbytes,
  }
  ok,herr=writefile(spec,table.concat(lines,"\n").."\n"); if not ok then cleanup(temps); return nil,herr,"IO" end

  local a,b,c=os.execute(shq(HELPER).." request "..shq(spec).." >/dev/null 2>&1")
  local ran,rc=status_ok(a,b,c)
  local meta,merr=parse_meta(metap)
  if not meta then
    if opts.save_to and not ran then os.remove(response) end
    cleanup(temps)
    return nil,merr or ("network helper failed: "..tostring(rc)),"NETWORK"
  end
  if not ran or meta.error_code~=0 then
    if opts.save_to then os.remove(response) end
    local msg=(meta.error and meta.error~="" and meta.error) or ("network request failed: "..tostring(rc))
    cleanup(temps)
    return nil,msg,"NETWORK"
  end

  local result={
    ok=meta.status>=200 and meta.status<400,
    status=meta.status,
    bytes=meta.bytes,
    content_type=meta.content_type~="" and meta.content_type or nil,
    url=meta.final_url~="" and meta.final_url or url,
    path=opts.save_to,
  }
  if not opts.save_to and method~="HEAD" then
    local data,rerr=readfile(response,maxbytes); if not data then cleanup(temps); return nil,rerr,"IO" end
    result.body=data
    if opts.decode_json then
      local decoded,jerr=json.decode(data); if not decoded then cleanup(temps); return nil,jerr,"JSON" end
      result.json=decoded
    end
  end
  cleanup(temps)
  return result
end

local function merge(opts,extra)
  local out={}; if opts then for k,v in pairs(opts) do out[k]=v end end
  for k,v in pairs(extra) do out[k]=v end
  return out
end
function M.get(url,opts) return M.request(merge(opts,{url=url,method="GET"})) end
function M.post(url,body,opts)
  local x=merge(opts,{url=url,method="POST"})
  if type(body)=="table" then x.json=body else x.body=body end
  return M.request(x)
end
function M.download(url,path,opts) return M.request(merge(opts,{url=url,method="GET",save_to=path})) end
function M.upload(url,path,opts)
  local x=merge(opts,{url=url,method=(opts and opts.method) or "POST",body_file=path})
  return M.request(x)
end

return M
