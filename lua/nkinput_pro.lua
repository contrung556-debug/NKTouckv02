-- NKTouch v0.8.5 Input Engine Pro: single-dispatch fast and guarded safe modes.
-- SPDX-License-Identifier: GPL-3.0-or-later
-- No OCR, screenshots, character-by-character typing or silent keyboard fallback.
-- v2 transport ACK confirms dispatch only, not acceptance by the target app.
local M={VERSION="0.8.5-beta"}
local MAX_BYTES=8192
local MAX_KEYS=128
local seen={}
local keyCount=0

local function validText(s)
  return type(s)=="string" and #s>0 and #s<=MAX_BYTES
    and not s:find("\0",1,true) and utf8.len(s)~=nil
end
local function integer(v,a,b)
  return type(v)=="number" and v==v and v%1==0 and v>=a and v<=b
end
local function err(msg,code)
  return nil,msg,code
end
local function keysOnly(opts,allowed)
  if type(opts)~="table" then return false end
  for k in pairs(opts) do if not allowed[k] then return false end end
  return true
end
local FAST_OPTIONS={secure=true}
local SAFE_OPTIONS={
  bundle=true,focus=true,onceKey=true,settleMs=true,secure=true,
  requireFocusProof=true
}
local function dispatch(nk,s,mode,secure)
  -- The existing v2 protocol sends ONE UTF-8/base64 packet to the native
  -- focused-field receiver. Never automatically retry or switch transport.
  if type(nk)~="table" or type(nk.inputTextV2)~="function" then
    return err("Native Input v2 is unavailable","NO_BACKEND")
  end
  local ok,value,details,code=pcall(nk.inputTextV2,s,{mode=mode,secure=secure})
  if not ok then return err("Native input delivery uncertain; no retry","DISPATCH_UNCERTAIN") end
  if value~=true then
    -- The dispatcher may have already posted the mutation. Treat any
    -- ambiguous failure as uncertain and never send again automatically.
    return err("Native input not acknowledged; do not retry automatically",
               code or "DISPATCH_UNCERTAIN")
  end
  return true,{sent=true,verified=false,status="DISPATCHED_UNVERIFIED",
               mode=mode,bytes=#s,attempts=1,ocr_used=false}
end

-- Fast by default: one native direct packet, zero OCR/focus/keyboard probes.
-- No automatic fallback. Opt-in secure=true marks a secret but never logs it.
function M.fast(nk,s,opts)
  opts=opts or {}
  if not keysOnly(opts,FAST_OPTIONS) or
     (opts.secure~=nil and type(opts.secure)~="boolean") then
    return err("fast options support only secure=true/false","INVALID")
  end
  if not validText(s) then
    return err("text must be valid UTF-8 (1..8192 bytes), no NUL","INVALID")
  end
  return dispatch(nk,s,"direct",opts.secure==true)
end

-- Explicit keyboard transport, one packet, never fallback after uncertainty.
function M.keyboard(nk,s,opts)
  opts=opts or {}
  if not keysOnly(opts,FAST_OPTIONS) or
     (opts.secure~=nil and type(opts.secure)~="boolean") then
    return err("keyboard options support only secure=true/false","INVALID")
  end
  if not validText(s) then
    return err("text must be valid UTF-8 (1..8192 bytes), no NUL","INVALID")
  end
  return dispatch(nk,s,"keyboard",opts.secure==true)
end

local function foreground(nk,bundle)
  if type(nk.foreground)~="function" then
    return err("foreground query unavailable","NO_FOREGROUND")
  end
  local called,name=pcall(nk.foreground)
  if not called or type(name)~="string" or name=="" then
    return err("foreground query failed","FOREGROUND_UNAVAILABLE")
  end
  if name~=bundle then return err("target application not foreground","WRONG_APP") end
  return true
end
local function dimensions(nk)
  if type(nk.screen)~="function" then
    return nil,nil,"SCREEN_UNAVAILABLE"
  end
  local called,result=pcall(nk.screen)
  if not called or type(result)~="string" then
    return nil,nil,"SCREEN_UNAVAILABLE"
  end
  local w,h=result:match("^%s*(%d+%.?%d*)%s*;;%s*(%d+%.?%d*)%s*$")
  w,h=tonumber(w),tonumber(h)
  if not integer(w,1,10000) or not integer(h,1,10000) then
    return nil,nil,"SCREEN_INVALID"
  end
  return w,h
end
local function dispatchTap(nk,x,y)
  if type(nk.tap)~="function" then return err("tap unavailable","NO_TOUCH") end
  local called,result=pcall(nk.tap,x,y)
  if not called or result~=true then
    return err("focus tap acknowledgement uncertain; no text sent","FOCUS_UNCERTAIN")
  end
  return true
end

-- SAFE: the foreground app and coordinates are verified before the tap;
-- foreground is checked AGAIN after the optional focus tap and settle delay.
-- This does NOT establish that a UIKeyInput first responder actually exists.
-- requireFocusProof fails closed if the optional *native* probe is unavailable.
-- The onceKey is a caller-chosen, per-field token (never the typed text).
-- It is reserved BEFORE touch and never released on ambiguous errors.
function M.safe(nk,s,opts)
  if not keysOnly(opts,SAFE_OPTIONS) then
    return err("invalid safe input options","INVALID")
  end
  if not validText(s) then
    return err("text must be valid UTF-8 (1..8192 bytes), no NUL","INVALID")
  end
  if type(nk)~="table" or type(nk.inputTextV2)~="function" then
    return err("Native Input v2 is unavailable","NO_BACKEND")
  end
  local bundle=opts.bundle
  if type(bundle)~="string" or #bundle<3 or #bundle>180 or
     not bundle:match("^[%w%._%-]+$") then
    return err("valid target bundle is required","INVALID")
  end
  local focus=opts.focus
  if type(focus)~="table" or not integer(focus.x,0,10000) or
     not integer(focus.y,0,10000) then
    return err("focus requires numeric x,y in physical pixels","INVALID")
  end
  for k in pairs(focus) do if k~="x" and k~="y" then
    return err("focus accepts only x,y","INVALID") end
  end
  if opts.secure~=nil and type(opts.secure)~="boolean" then
    return err("secure must be boolean","INVALID")
  end
  local delay=opts.settleMs
  if delay==nil then delay=100 end
  if not integer(delay,0,1500) then
    return err("settleMs must be 0..1500","INVALID")
  end
  local strict=opts.requireFocusProof
  if strict~=nil and type(strict)~="boolean" then
    return err("requireFocusProof must be boolean","INVALID")
  end
  if strict and type(nk.focusedInput)~="function" then
    return err("native first-responder focus probe unavailable; no input sent",
               "FOCUS_PROBE_UNAVAILABLE")
  end
  local key=opts.onceKey
  if key~=nil and (type(key)~="string" or #key<1 or #key>64 or
                    not key:match("^[A-Za-z0-9_.%-]+$")) then
    return err("onceKey must be 1..64 ASCII token characters","INVALID")
  end
  -- Reject duplicate before any side-effect, including an extra focus tap.
  if key and seen[key] then
    return err("onceKey already attempted by this Lua process","DUPLICATE_BLOCKED")
  end
  if key and keyCount>=MAX_KEYS then
    return err("too many onceKey reservations; use a fresh Lua task","KEY_LIMIT")
  end
  local w,h,dc=dimensions(nk)
  if not w then return err("physical screen dimensions unavailable",dc) end
  if focus.x>=w or focus.y>=h then
    return err("focus point outside physical screen","OUT_OF_BOUNDS")
  end
  local before,e,c=foreground(nk,bundle)
  if not before then return nil,e,c end

  -- A full preflight has passed. Key stays reserved after ANY tap / input
  -- uncertainty so a repeated call cannot duplicate the same field value.
  if key then seen[key]=true; keyCount=keyCount+1 end
  local tapped,te,tc=dispatchTap(nk,focus.x,focus.y)
  if not tapped then return nil,te,tc end
  if delay>0 then
    if type(nk.sleep)~="function" then
      return err("focus settle unavailable; text not sent","SLEEP_UNAVAILABLE")
    end
    local called,waited=pcall(nk.sleep,delay)
    if not called or waited==false or waited==nil then
      return err("focus settle failed; text not sent","FOCUS_UNCERTAIN")
    end
  end
  local after,ae,ac=foreground(nk,bundle)
  if not after then return nil,ae,ac end

  local focusVerified=false
  if strict then
    local called,yes=pcall(nk.focusedInput)
    if not called or yes~=true then
      return err("native first-responder not confirmed; text not sent",
                 "FOCUS_NOT_CONFIRMED")
    end
    focusVerified=true
  end
  local ok,result,code=dispatch(nk,s,"direct",opts.secure==true)
  if not ok then return nil,result,code end
  result.target_app=bundle
  result.foreground_verified=true
  result.focus_tap_sent=true
  result.focus_verified=focusVerified
  result.once_key_reserved=key~=nil
  return true,result
end

function M.version() return M.VERSION end
return M
