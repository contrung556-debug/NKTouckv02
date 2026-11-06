-- NKTouch v0.8.11 OCR State Gate.
-- Read-only OCR normalization and bounded stable-label detection.
-- This module never taps, types, launches apps or logs recognized screen text.
-- SPDX-License-Identifier: GPL-3.0-or-later
local M={VERSION="0.8.11-beta"}

local accents={}
local function put(chars,base)
  for _,code in utf8.codes(chars) do accents[utf8.char(code)]=base end
end
put("àáảãạăằắẳẵặâầấẩẫậÀÁẢÃẠĂẰẮẲẴẶÂẦẤẨẪẬ","a")
put("èéẻẽẹêềếểễệÈÉẺẼẸÊỀẾỂỄỆ","e")
put("ìíỉĩịÌÍỈĨỊ","i")
put("òóỏõọôồốổỗộơờớởỡợÒÓỎÕỌÔỒỐỔỖỘƠỜỚỞỠỢ","o")
put("ùúủũụưừứửữựÙÚỦŨỤƯỪỨỬỮỰ","u")
put("ỳýỷỹỵỲÝỶỸỴ","y")
put("đĐ","d")
-- Frequent OCR substitutions seen in Vietnamese screens.
put("äÄ","a")
put("ëË","e")
put("ïÏ","i")
put("öÖ","o")
put("üÜ","u")

function M.normalize(text)
  if type(text)~="string" then return nil,"OCR text must be a string","INVALID" end
  local out={}
  local ok,err=pcall(function()
    for _,code in utf8.codes(text) do
      if code<0x0300 or code>0x036F then
        local ch=utf8.char(code)
        out[#out+1]=accents[ch] or ch:lower()
      end
    end
  end)
  if not ok then return nil,"OCR text is not valid UTF-8","INVALID_UTF8" end
  return table.concat(out):gsub("[^a-z0-9]","")
end

local function integer(v,lo,hi)
  return type(v)=="number" and v==v and v%1==0 and v>=lo and v<=hi
end
local function fail(message,code,detail) return nil,message,code,detail end
local function monotonic()
  local ok,core=pcall(require,"nkcore")
  if ok and type(core)=="table" and type(core.nowMs)=="function" then
    return core.nowMs
  end
  return nil
end
local function compile(options)
  if type(options)~="table" then return nil,"options table required","INVALID" end
  local allowed={x=true,y=true,w=true,h=true,labels=true,
    stable_reads=true,max_reads=true,interval_ms=true,timeout_ms=true,
    now=true,sleep=true}
  for key in pairs(options) do
    if not allowed[key] then return nil,"unknown option","INVALID" end
  end
  for _,key in ipairs({"x","y","w","h"}) do
    local lo=(key=="w" or key=="h") and 1 or 0
    if not integer(options[key],lo,10000) then
      return nil,"invalid OCR region","INVALID"
    end
  end
  local stable=options.stable_reads or 2
  local maximum=options.max_reads or 8
  local interval=options.interval_ms or 250
  local timeout=options.timeout_ms or 4000
  if not integer(stable,2,4) or not integer(maximum,stable,16)
      or not integer(interval,100,1500)
      or not integer(timeout,200,15000) then
    return nil,"stable_reads 2..4, max_reads stable..16, interval 100..1500, timeout 200..15000","INVALID"
  end
  if type(options.labels)~="table" then
    return nil,"labels map required","INVALID"
  end
  local labels={}
  local count=0
  for label,phrases in pairs(options.labels) do
    if type(label)~="string" or #label<1 or #label>48
        or not label:match("^[%w_%-]+$")
        or type(phrases)~="table" or #phrases<1 or #phrases>8 then
      return nil,"invalid label specification","INVALID"
    end
    count=count+1
    if count>12 then return nil,"at most 12 labels are allowed","INVALID" end
    local compiled={}
    local phraseCount=#phrases
    local phraseEntries=0
    for key in pairs(phrases) do
      if not integer(key,1,8) then return nil,"invalid phrase list","INVALID" end
      phraseEntries=phraseEntries+1
    end
    if phraseCount<1 or phraseEntries~=phraseCount then
      return nil,"phrase list must be dense","INVALID"
    end
    for i=1,phraseCount do
      local phrase=phrases[i]
      if type(phrase)~="string" or #phrase>256 then
        return nil,"invalid phrase","INVALID"
      end
      local normalized,err,code=M.normalize(phrase)
      if not normalized or #normalized<3 then
        return nil,err or "phrase too short",code or "INVALID"
      end
      compiled[#compiled+1]=normalized
    end
    labels[#labels+1]={name=label,phrases=compiled}
  end
  if count==0 then return nil,"labels map cannot be empty","INVALID" end
  table.sort(labels,function(a,b) return a.name<b.name end)
  local now=options.now or monotonic()
  if type(now)~="function" then return nil,"monotonic clock unavailable","NO_CLOCK" end
  local sleep=options.sleep
  if sleep==nil then sleep=function(ms) return require("nktouch_v7").sleep(ms) end end
  if type(sleep)~="function" then return nil,"sleep callback required","NO_SLEEP" end
  return {labels=labels,stable=stable,maximum=maximum,interval=interval,
    timeout=timeout,now=now,sleep=sleep}
end

local function matchLabel(text,labels)
  local found=nil
  for _,entry in ipairs(labels) do
    local matched=false
    for _,phrase in ipairs(entry.phrases) do
      if text:find(phrase,1,true) then matched=true; break end
    end
    if matched then
      if found then return nil,"AMBIGUOUS" end
      found=entry.name
    end
  end
  return found
end

function M.waitFor(nk,options)
  if type(nk)~="table" or type(nk.ocr)~="function" then
    return fail("live OCR API unavailable","NO_OCR")
  end
  local cfg,err,code=compile(options)
  if not cfg then return nil,err,code end
  if type(nk.screen)~="function" then return fail("screen API unavailable","NO_SCREEN") end
  local screenOK,screen,screenErr,screenCode=pcall(nk.screen)
  if not screenOK or type(screen)~="string" then
    return fail("screen geometry unavailable",screenCode or "SCREEN",
      {error=tostring(screenErr or screen):sub(1,96)})
  end
  local sw,sh=screen:match("^%s*(%d+%.?%d*)%s*;;%s*(%d+%.?%d*)%s*$")
  sw,sh=tonumber(sw),tonumber(sh)
  if not sw or not sh or options.x+options.w>sw or options.y+options.h>sh then
    return fail("OCR region is outside the current screen","OUT_OF_BOUNDS")
  end
  local function clock()
    local ok,value=pcall(cfg.now)
    if not ok or not integer(value,0,math.huge) then return nil end
    return value
  end
  local start=clock()
  if not start then return fail("invalid monotonic clock","CLOCK") end
  local function elapsed()
    local current=clock()
    if not current or current<start then return nil end
    return current-start
  end
  local previous=nil
  local stable=0
  local reads=0
  local lastState=nil
  while reads<cfg.maximum do
    local spent=elapsed()
    if not spent then return fail("monotonic clock failed or regressed","CLOCK") end
    if reads>0 and spent>=cfg.timeout then break end
    reads=reads+1
    local called,text,ocrErr,ocrCode=pcall(nk.ocr,options.x,options.y,options.w,options.h,"")
    if not called then return fail("OCR call raised an error","OCR") end
    if type(text)~="string" then
      return fail("OCR did not return text",ocrCode or "OCR",
        {reads=reads,error=tostring(ocrErr or ""):sub(1,96)})
    end
    local normalized,normErr,normCode=M.normalize(text)
    if not normalized then return fail(normErr,normCode) end
    local state,matchErr=matchLabel(normalized,cfg.labels)
    if matchErr then
      previous=nil
      stable=0
      lastState="AMBIGUOUS"
    elseif state then
      stable=(state==previous) and (stable+1) or 1
      previous=state
      lastState=state
      local afterRead=elapsed()
      if not afterRead then return fail("monotonic clock failed or regressed","CLOCK") end
      if stable>=cfg.stable and afterRead<cfg.timeout then
        return {status="PASS",state=state,reads=reads,
          stable_reads=stable,elapsed_ms=afterRead,ocr_text_included=false}
      end
    else
      previous=nil
      stable=0
      lastState=nil
    end
    if reads<cfg.maximum then
      local used=elapsed()
      if not used then return fail("monotonic clock failed or regressed","CLOCK") end
      local remaining=cfg.timeout-used
      if remaining<=0 then break end
      local delay=math.min(cfg.interval,remaining)
      local sleptOK,slept=pcall(cfg.sleep,delay)
      if not sleptOK or slept~=true then
        return fail("bounded OCR wait sleep failed","SLEEP",{reads=reads})
      end
    end
  end
  return fail("OCR state was not stable before the read/time limit",
    "STATE_UNCERTAIN",{reads=reads,last_state=lastState,elapsed_ms=elapsed(),
      ocr_text_included=false})
end

return M
