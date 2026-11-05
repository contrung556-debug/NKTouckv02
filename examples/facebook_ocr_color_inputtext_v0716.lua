-- NKTouch v0.7.16 | Facebook OCR + Color + inputText smoke test
-- For testing YOUR app. Does NOT submit registration or press "Tiep".
-- Open Facebook -> optionally "Tao tai khoan moi" -> "Bat dau"
-- -> "Ban ten gi?" -> type Ho then Ten exactly ONCE each -> STOP.
-- Screenshot references: 720x1280; coordinates adapt using width,
-- top-anchored form and bottom-anchored large CTA.
-- IMPORTANT: Do not rerun on already-filled fields: inputText inserts,
-- it does not clear/replace text. No automatic retries for mutations.

local nk=require("nktouch_v7")
local FACEBOOK="com.facebook.Facebook"
local HO="Nguyễn"          -- EDIT: non-sensitive test surname
local TEN="An"              -- EDIT: non-sensitive test first name
local MAX_POLLS=12
local POLL_MS=800
local VERIFY_LIVE_FINDCOLOR=true  -- Test public nk.findColor as well as frame
local CHECK_TYPED_TEXT=true       -- OCR fields, WARN only: never retype

local function log(level,msg)
  print(("[NKFB][%s] %s"):format(level,tostring(msg)))
end
local function stop(msg)
  error("[NKFB][STOP] "..tostring(msg),0)
end
local function must(value,err,code,where)
  if value==nil or value==false then
    stop((where or "API")..": "..tostring(err or "failed")..
         " ["..tostring(code or "UNKNOWN").."]")
  end
  return value
end
local function pause(ms)
  local ok,err,code=nk.sleep(ms)
  must(ok,err,code,"sleep")
end
local function foreground()
  local app,err,code=nk.foreground()
  must(app,err,code,"foreground")
  if app~=FACEBOOK then stop("wrong foreground app: "..tostring(app)) end
end
local function round(v) return math.floor(v+0.5) end
local raw,err,code=nk.screen()
must(raw,err,code,"screen")
local sw,sh=tostring(raw):match("^%s*(%d+%.?%d*)%s*;;%s*(%d+%.?%d*)%s*$")
local W,H=tonumber(sw),tonumber(sh)
if not W or not H or W<320 or H<600 or H/W<1.5 then
  stop("portrait physical-pixel screen required: "..tostring(raw))
end
W,H=round(W),round(H)
local scale=W/720
local function xRef(n) return round(n*scale) end
local function topY(n) return round(n*scale) end
local function bottomY(n) return round(H-(1280-n)*scale) end
local function crop(x,y,w,h)
  x=math.max(0,math.min(W-1,round(x)))
  y=math.max(0,math.min(H-1,round(y)))
  w=math.max(1,math.min(W-x,round(w)))
  h=math.max(1,math.min(H-y,round(h)))
  return x,y,w,h
end
local buttonY={
  login=bottomY(1106),meta=bottomY(1100),name=topY(490)
}
local function buttonRegion(page)
  local y=assert(buttonY[page],"unknown page")
  return crop(xRef(135),y-xRef(20),xRef(390),xRef(42))
end

-- Strip Vietnamese accents for OCR comparison. Apple Vision may lose accents.
local accent={}
local function mapChars(chars,base)
  for _,cp in utf8.codes(chars) do accent[utf8.char(cp)]=base end
end
mapChars("àáảãạăằắẳẵặâầấẩẫậÀÁẢÃẠĂẰẮẲẴẶÂẦẤẨẪẬ","a")
mapChars("èéẻẽẹêềếểễệÈÉẺẼẸÊỀẾỂỄỆ","e")
mapChars("ìíỉĩịÌÍỈĨỊ","i")
mapChars("òóỏõọôồốổỗộơờớởỡợÒÓỎÕỌÔỒỐỔỖỘƠỜỚỞỠỢ","o")
mapChars("ùúủũụưừứửữựÙÚỦŨỤƯỪỨỬỮỰ","u")
mapChars("ỳýỷỹỵỲÝỶỸỴ","y")
mapChars("đĐ","d")
local function normalize(value)
  local str=tostring(value or "")
  local output={}
  local ok=pcall(function()
    for _,cp in utf8.codes(str) do
      local ch=utf8.char(cp)
      output[#output+1]=accent[ch] or ch:lower()
    end
  end)
  if not ok then return "" end
  return table.concat(output):gsub("[^a-z0-9]","")
end
local function has(value,fragment)
  return normalize(value):find(fragment,1,true)~=nil
end

local function scanFrame()
  local state,e,c=nk.withFrame(function(frame)
    local meta,metaErr,metaCode=frame:info()
    if not meta then error("frame info: "..tostring(metaCode or metaErr),0) end
    -- Wrong screen/Retina geometry must NEVER yield a blind touch.
    if meta.width~=W or meta.height~=H then
      error(("frame %dx%d differs from screen %dx%d; calibrate first"):format(
        meta.width,meta.height,W,H),0)
    end
    -- One capture; multiple OCR and color queries on the SAME frame.
    local tx,ty,tw,th=crop(0,topY(70),W,math.min(H-topY(70),topY(860)))
    local upper,oe,oc=frame:ocr(tx,ty,tw,th,"")
    if type(upper)~="string" then
      error("OCR top failed: "..tostring(oc or oe),0)
    end
    local bx,by,bw,bh=crop(0,bottomY(1000),W,H-bottomY(1000))
    local lower,le,lc=frame:ocr(bx,by,bw,bh,"")
    if type(lower)~="string" then
      error("OCR bottom failed: "..tostring(lc or le),0)
    end
    local page
    if has(upper,"bantengi") or
       has(upper,"nhaptenbansudungtrongdoithuc") then
      page="name"
    elseif has(lower,"taotaikhoanmoi") and
           (has(upper,"dangnhap") or has(upper,"quenmatkhau") or
            has(upper,"sodidong") or has(upper,"matkhau")) then
      page="login"
    elseif (has(upper,"taikhoanmeta") or
            has(upper,"batdautrenfacebook")) and
           has(lower,"batdau") then
      page="meta"
    end
    local blueHit,blueErr,blueCode
    if page then
      local cx,cy,cw,ch=buttonRegion(page)
      blueHit,blueErr,blueCode=frame:findColor(cx,cy,cw,ch,
                         0,100,50,190,145,255,4)
    end
    return {
      page=page,blue=blueHit,blueError=blueCode or blueErr,
      top=upper:sub(1,180),bottom=lower:sub(1,120)
    }
  end)
  if not state then stop("Vision capture/OCR failed: "..tostring(c or e)) end
  return state
end

local function detect(expected)
  for n=1,MAX_POLLS do
    foreground()
    local found=scanFrame()
    if found.page and (not expected or found.page==expected) then
      if not found.blue then
        stop(("OCR sees '%s' but blue button is absent: %s"):format(
          found.page,tostring(found.blueError)))
      end
      log("SCREEN","OCR+COLOR="..found.page.." (poll "..n..")")
      return found.page
    end
    if n==1 or n==MAX_POLLS then
      log("WAIT",("poll %d expected=%s found=%s OCR=%s"):format(
        n,tostring(expected),tostring(found.page),
        (found.top.." "..found.bottom):sub(1,150)))
    end
    if n<MAX_POLLS then pause(POLL_MS) end
  end
  stop("not on the expected screen; no tap or input performed")
end

local function clickBlue(page)
  foreground()
  local x,y,w,h=buttonRegion(page)
  -- Second, independent call exercises the public live Color Engine.
  if VERIFY_LIVE_FINDCOLOR then
    local hit,e,c=nk.findColor(x,y,w,h,0,100,50,190,145,255,4)
    must(hit,e,c,"nk.findColor "..page)
    log("COLOR",("nk.findColor %s at (%d,%d) RGB=%d,%d,%d"):format(
      page,hit.x,hit.y,hit.red,hit.green,hit.blue))
  end
  -- Only tap INSIDE the blue area, not an arbitrary screen location.
  local px,py=xRef(245),buttonY[page]
  log("TAP",("%s x=%d y=%d"):format(page,px,py))
  local ok,e,c=nk.tap(px,py)
  must(ok,e,c,"tap "..page)
  pause(1100)
end

local function fieldText(side)
  local xx=(side=="ho") and 35 or 372
  local yy=295
  return nk.withFrame(function(frame)
    local info=assert(frame:info())
    if info.width~=W or info.height~=H then
      error("frame geometry changed during text verification",0)
    end
    local x,y,w,h=crop(xRef(xx),topY(yy),xRef(300),topY(115))
    local txt,e,c=frame:ocr(x,y,w,h,"")
    if type(txt)~="string" then error(tostring(c or e or "OCR"),0) end
    return txt
  end)
end

local function typeField(side,label,text,refX)
  foreground()
  local page=detect("name")
  if page~="name" then stop("not on name screen") end
  -- Prevent accidental text APPENDING if a field was already filled.
  -- This is read-only OCR; it never clears or overwrites the user's value.
  local before,be,bc=fieldText(side)
  if not before then stop(label.." cannot inspect current field: "..tostring(bc or be)) end
  local current=normalize(before)
  local placeholder=(side=="ho") and "ho" or "ten"
  if current~="" and current~=placeholder then
    stop(label.." is not empty (OCR="..before:sub(1,65).."); no duplicate input")
  end
  local px,py=xRef(refX),topY(351)
  log("FOCUS",("%s tap(%d,%d)"):format(label,px,py))
  local ok,e,c=nk.tap(px,py)
  must(ok,e,c,"tap "..label)
  pause(420)
  foreground()
  log("INPUT",label.." inputText ONCE, bytes="..#text)
  local sent,meta,kind=nk.inputText(text,{mode="direct"})
  must(sent,meta,kind,"inputText "..label)
  log("INPUT",label.." dispatch acknowledged; UI may still be unverified")
  pause(550)
  if CHECK_TYPED_TEXT then
    local actual,ae,ac=fieldText(side)
    if not actual then
      log("WARN",label.." OCR failed: "..tostring(ac or ae))
    elseif has(actual,normalize(text)) then
      log("PASS",label.." OCR recognized: "..actual:sub(1,80))
    else
      log("WARN",label.." OCR did not confirm typed value; never retry. OCR="..
          actual:sub(1,80))
    end
  end
end

log("START",("Facebook name fields, screen=%dx%d, color+OCR enabled"):format(W,H))
if nk.foreground()~=FACEBOOK then
  local ok,e,c=nk.openApp(FACEBOOK)
  must(ok,e,c,"openApp")
end
must(nk.waitApp(FACEBOOK,12000,250))
pause(1200)

-- Auto-detect the supplied login / Meta intro / name screen.
-- Every navigation button is tapped at most once.
local visited={}
for _=1,3 do
  local page=detect()
  if page=="name" then break end
  if visited[page] then stop("navigation did not advance; refusing repeated tap") end
  visited[page]=true
  if page=="login" or page=="meta" then
    clickBlue(page)
  else
    stop("unknown Facebook screen")
  end
end
detect("name")
typeField("ho","HO",HO,180)
typeField("ten","TEN",TEN,525)

-- Last read-only check: never click "Tiep".
local lastPage=detect("name")
if lastPage=="name" then
  log("DONE","Two inputText commands issued ONCE each; no Next/registration submitted")
  log("STOP","Please visually inspect Ho and Ten fields in Facebook")
end
