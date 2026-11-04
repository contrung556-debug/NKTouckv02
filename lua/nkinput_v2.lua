-- NKTouch Input Engine v2 — explicit, Unicode-safe and non-retrying.
-- The old nk.inputText(text) API remains unchanged for legacy scripts.
-- SPDX-License-Identifier: GPL-3.0-or-later
local M = { VERSION="0.7.10" }
local MAX_BYTES = 8192
local function integer(v,low,high)
  return type(v)=="number" and v%1==0 and v>=low and v<=high
end

local function optionsValid(opts)
  if type(opts)~="table" then
    return nil,"options must be a table","INVALID"
  end
  for key in pairs(opts) do
    if key~="mode" and key~="secure" and key~="verify" and key~="settleMs" then
      return nil,"unknown input option: "..tostring(key),"INVALID"
    end
  end
  if opts.secure~=nil and type(opts.secure)~="boolean" then
    return nil,"secure must be boolean","INVALID"
  end
  local mode=opts.mode or "direct"
  if mode~="direct" and mode~="keyboard" then
    return nil,"mode must be 'direct' or 'keyboard'","INVALID"
  end
  if opts.secure and opts.verify then
    return nil,"OCR verification of passwords is forbidden","SECURE"
  end
  local delay=opts.settleMs
  if delay==nil then delay=350 end
  if not integer(delay,0,5000) then
    return nil,"settleMs must be 0..5000","INVALID"
  end
  local verify=opts.verify
  if verify~=nil and verify~=false then
    if type(verify)~="table" then
      return nil,"verify must be a region table","INVALID"
    end
    for _,key in ipairs({"x","y","w","h"}) do
      if not integer(verify[key],(key=="x" or key=="y") and 0 or 1,10000) then
        return nil,"verify requires valid x,y,w,h integers","INVALID"
      end
    end
    if verify.expected~=nil and (type(verify.expected)~="string"
        or verify.expected=="") then
      return nil,"verify.expected must be nonempty text","INVALID"
    end
    if verify.language~=nil and (type(verify.language)~="string"
        or #verify.language>64) then
      return nil,"verify.language invalid","INVALID"
    end
  end
  return {mode=mode,secure=opts.secure==true,verify=verify,delay=delay}
end

function M.input(nk,text,opts)
  if type(text)~="string" or #text==0 or #text>MAX_BYTES
    or text:find("\0",1,true) or not utf8.len(text) then
    return nil,"input must be valid nonempty UTF-8, no NUL, max 8192 bytes","INVALID"
  end
  if opts==nil then opts={} end
  local config,err,code=optionsValid(opts)
  if not config then return nil,err,code end
  -- No old-protocol fallback: it truncates Unicode text containing CR/LF or ';;'.
  -- A native dispatch acknowledgement is NOT proof the app accepted the text.
  if type(nk)~="table" or type(nk._inputNativeV2)~="function" then
    return nil,"native Input Engine v2 unavailable","NO_BACKEND"
  end
  if config.verify and type(nk.ocr)~="function" then
    return nil,"OCR API unavailable for verification","NO_OCR"
  end
  local ok,submitErr,submitCode=nk._inputNativeV2(text,config.mode)
  if not ok then return nil,submitErr or "input dispatch failed",submitCode or "INPUT" end

  local result={sent=true,verified=false,mode=config.mode,
                status="dispatched",bytes=#text}
  if not config.verify then return true,result end

  if config.delay>0 and type(nk.sleep)=="function" then
    local slept,sleepErr=nk.sleep(config.delay)
    if not slept then
      result.status="unverified"
      return nil,"input dispatched; verification delay failed (no retry)",
             "UNVERIFIED",result
    end
  end
  local r=config.verify
  local actual,ocrErr,ocrCode=nk.ocr(r.x,r.y,r.w,r.h,r.language or "")
  if not actual then
    result.status="unverified"
    return nil,"input dispatched but OCR unavailable (no retry): "..tostring(ocrCode or "OCR"),
           "UNVERIFIED",result
  end
  local expected=r.expected or text
  if not actual:find(expected,1,true) then
    result.status="unverified"
    return nil,"input dispatched but text not confirmed (no retry)","UNVERIFIED",result
  end
  result.verified=true
  result.status="verified"
  return true,result
end

function M.password(nk,text,opts)
  if opts==nil then opts={} end
  if type(opts)~="table" then return nil,"options must be a table","INVALID" end
  local secure={}
  for k,v in pairs(opts) do secure[k]=v end
  secure.secure=true
  return M.input(nk,text,secure)
end
return M
