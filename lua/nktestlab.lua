-- NKTouch Test Lab v0.7.16-dev
-- PASS / FAIL / WARN / SKIP; read-only by default, opt-in mutation tests.
-- Safe execution through existing nktask runner and Task Center.
-- All coordinates are *physical screen pixels*, not UIKit points.
local M={VERSION="0.7.16-dev"}
local ORDER={"runtime","touch","input","color","vision","network","task"}
local TITLES={
  runtime="Lua Runtime",touch="Touch Engine",input="Input Engine",
  color="Color Engine",vision="Vision Core",network="Network & JSON",
  task="Task Stability"
}
local REPORT="/var/mobile/Library/NKTouch/tmp/testlab-last.json"
local MAX_DETAIL=240

local function safe(v)
  local s=tostring(v==nil and "" or v)
  return s:gsub("[%c]"," "):sub(1,MAX_DETAIL)
end
local function validInt(n,lo,hi)
  return type(n)=="number" and n==n and n%1==0 and n>=lo and n<=hi
end
local function screenSize(raw)
  local a,b=tostring(raw or ""):match("^%s*(%d+%.?%d*)%s*;;%s*(%d+%.?%d*)%s*$")
  local w,h=tonumber(a),tonumber(b)
  if not w or not h or w<200 or h<300 or w>10000 or h>10000 then
    return nil,"invalid physical-pixel screen dimensions"
  end
  return math.floor(w+.5),math.floor(h+.5)
end
local function runId(s)
  return type(s)=="string" and #s>=4 and #s<=64
    and s:match("^[a-zA-Z0-9_-]+$") ~= nil
end
local function statusPriority(s)
  return ({FAIL=4,WARN=3,PASS=2,SKIP=1})[s] or 0
end

local function reporter(nk,selected,id,now,reportPath,mode,clockType)
  local startedClock=now()
  local report={
    version=M.VERSION, run_id=id, started_at=os.date("!%Y-%m-%dT%H:%M:%SZ"),
    selected=selected, groups={}, tests={},
    mode=mode or "read_only_default", visual_confirmation=false,
    coverage="PARTIAL", clock_type=clockType or "unknown",
    pass=0, fail=0, warn=0, skip=0, status="SKIP"
  }
  for _,name in ipairs(selected) do
    report.groups[name]={title=TITLES[name],status="SKIP",
      pass=0,fail=0,warn=0,skip=0}
  end
  local function record(group,test,status,detail,ms)
    assert(statusPriority(status)>0,"invalid Lab status")
    local message=safe(detail)
    local g=assert(report.groups[group],"unknown Lab group")
    local measured=tonumber(ms) or 0
    if measured~=measured or measured==math.huge or measured==-math.huge then
      measured=0
    end
    local item={group=group,name=test,status=status,detail=message,
                ms=math.max(0,math.floor(measured))}
    report.tests[#report.tests+1]=item
    local key=status:lower()
    g[key]=g[key]+1
    report[key]=report[key]+1
    if statusPriority(status)>statusPriority(g.status) then
      g.status=status
    end
    print(("[NKLAB][%s] %s/%s ms=%d %s"):format(
      status,group,test,item.ms,message))
  end
  local function check(group,test,fn)
    local start=now()
    local ok,status,detail=pcall(fn)
    if not ok then
      record(group,test,"FAIL","lua_exception="..safe(status),now()-start)
      return
    end
    if status~="PASS" and status~="WARN" and status~="SKIP"
        and status~="FAIL" then
      record(group,test,"FAIL","invalid test result",now()-start)
      return
    end
    record(group,test,status,detail,now()-start)
  end
  local function finish()
    report.finished_at=os.date("!%Y-%m-%dT%H:%M:%SZ")
    if report.fail>0 then report.status="FAIL"
    elseif report.warn>0 then report.status="WARN"
    elseif report.pass>0 then report.status="PASS"
    else report.status="SKIP" end
    -- PASS means the executed checks passed. A SKIP still means incomplete
    -- coverage; successful HID/text dispatch is not visual confirmation.
    report.coverage=(report.skip>0) and "PARTIAL" or "FULL"
    -- Reliability Report: measured timings of individual checks, NOT
    -- gesture accuracy or successful execution of an entire automation.
    -- No history or fabricated success rates from unexecuted SKIP tests.
    local elapsed=(tonumber(now()) or 0)-(tonumber(startedClock) or 0)
    if elapsed~=elapsed or elapsed<0 or elapsed==math.huge then elapsed=0 end
    local durations={}
    local groupTimes={}
    local slowest=nil
    for _,name in ipairs(selected) do groupTimes[name]={} end
    local allSum=0
    for _,test in ipairs(report.tests) do
      durations[#durations+1]=test.ms
      allSum=allSum+test.ms
      local list=groupTimes[test.group]
      list[#list+1]=test.ms
      if not slowest or test.ms>slowest.ms then
        slowest={group=test.group,name=test.name,ms=test.ms}
      end
    end
    local function metrics(times)
      local n=#times
      if n==0 then return {checks=0,total_ms=0,avg_check_ms=0,
                           p95_check_ms=0,max_check_ms=0} end
      table.sort(times)
      local sum=0
      for _,ms in ipairs(times) do sum=sum+ms end
      -- Nearest-rank p95 across different checks in THIS run only.
      -- It does not estimate the p95 latency of an individual API.
      return {checks=n,total_ms=sum,
              avg_check_ms=math.floor(sum/n*100+0.5)/100,
              p95_check_ms=times[math.max(1,math.ceil(n*.95))],
              max_check_ms=times[n]}
    end
    report.timing=metrics(durations)
    report.timing.elapsed_ms=math.floor(elapsed)
    report.timing.slowest_check=slowest
    for _,name in ipairs(selected) do
      local group=report.groups[name]
      group.timing=metrics(groupTimes[name])
      local executed=group.pass+group.warn+group.fail
      group.executed=executed
      -- Semantic label avoids confusing unit-check success with
      -- user-interface accuracy or field insertion verification.
      group.check_pass_rate_pct=executed>0 and
          math.floor(group.pass/executed*10000+0.5)/100 or nil
    end
    local jsonOk,json=pcall(require,"nkjson")
    if jsonOk and json and json.encode and reportPath then
      local encoded,encodingErr=json.encode(report)
      if encoded then
        -- No user-controlled path. Atomic replacement protects the UI from
        -- partial JSON while an active task is writing its final report.
        local temp=reportPath.."."..id..".tmp"
        local f,openErr=io.open(temp,"wb")
        if f then
          local wrote,writeErr=f:write(encoded)
          f:close()
          if wrote then
            local moved,moveErr=os.rename(temp,reportPath)
            if not moved then
              os.remove(temp)
              print("[NKLAB][WARN] report/write "..safe(moveErr))
            end
          else
            os.remove(temp)
            print("[NKLAB][WARN] report/write "..safe(writeErr))
          end
        else print("[NKLAB][WARN] report/open "..safe(openErr)) end
      else print("[NKLAB][WARN] report/json "..safe(encodingErr)) end
    else
      print("[NKLAB][WARN] report unavailable (nkjson or path)")
    end
    print(("[NKLAB][SUMMARY] run=%s status=%s pass=%d fail=%d warn=%d skip=%d"):format(
      id,report.status,report.pass,report.fail,report.warn,report.skip))
    return report
  end
  return check,finish
end

local function makeGroups(nk,opts,check)
  local function test(group,name,fn) check(group,name,fn) end
  local function good(ok,err,code)
    if ok~=nil and ok~=false then return "PASS" end
    return "FAIL",safe(code or "").." "..safe(err or "native dispatch error")
  end
  local function invalidReturn(value,_,code)
    return value==nil and code=="INVALID"
  end
  local function assertForeground(expected)
    if type(expected)~="string" or #expected<5
        or not expected:find(".",1,true) then
      return nil,"explicit bundle ID required"
    end
    local actual,err,code=nk.foreground()
    if not actual then return nil,"foreground unavailable: "..safe(code or err) end
    if actual~=expected then return nil,"wrong foreground app: "..safe(actual) end
    return true
  end
  local function pixelPoint(x,y,w,h)
    return validInt(x,0,w-1) and validInt(y,0,h-1)
  end
  local function dimensions()
    local raw,err,code=nk.screen()
    if not raw then return nil,nil,safe(code or err) end
    local w,h=screenSize(raw)
    if not w then return nil,nil,h end
    return w,h
  end
  local handlers={}

  handlers.runtime=function()
    test("runtime","lua_54",function()
      return _VERSION=="Lua 5.4" and "PASS" or "FAIL",_VERSION
    end)
    test("runtime","nk_api",function()
      return type(nk)=="table" and type(nk.screen)=="function"
           and type(nk.inputText)=="function" and "PASS" or "FAIL",
             "Lua bridge exported"
    end)
    test("runtime","native_direct",function()
      if nk.DIRECT then return "PASS","native nkcore direct" end
      return "WARN","CLI fallback or native core unavailable"
    end)
    test("runtime","lua_syntax",function()
      local fn,err=load("local total=0; for i=1,10 do total=total+i end; return total")
      if not fn then return "FAIL",err end
      return fn()==55 and "PASS" or "FAIL","compile and execute Lua"
    end)
  end

  handlers.touch=function()
    test("touch","invalid_coords_fail_closed",function()
      if invalidReturn(nk.tap(-1,0)) and invalidReturn(nk.hold(-1,0,200))
          and invalidReturn(nk.swipe(0,0,-1,5,250)) then
        return "PASS","bad coordinates rejected before HID dispatch"
      end
      return "FAIL","touch invalid coordinates not safely rejected"
    end)
    test("touch","invalid_path_fail_closed",function()
      if type(nk.path)~="function" then return "FAIL","nk.path unavailable" end
      if invalidReturn(nk.path({{x=0,y=0,t=0},
              {x=10,y=10,t=0}})) then
        return "PASS","nonmonotonic path rejected"
      end
      return "FAIL","invalid path was not rejected by Lua wrapper"
    end)
    test("touch","interactive_gestures",function()
      local cfg=opts.touch
      if type(cfg)~="table" or cfg.enabled~=true then
        return "SKIP","disabled; explicit opt-in required"
      end
      -- A second explicit confirmation is required. Simply flipping
      -- enabled=true must NOT make default (0,0) coordinates actionable.
      if cfg.confirmed~=true then
        return "FAIL","set confirmed=true only after configuring the test screen"
      end
      local fg,fe=assertForeground(cfg.bundle)
      if not fg then return "FAIL",fe end
      local w,h,dimErr=dimensions()
      if not w then return "FAIL",dimErr end
      if type(cfg.tap)~="table" or type(cfg.hold)~="table"
          or type(cfg.swipe)~="table"
          or not pixelPoint(cfg.tap.x,cfg.tap.y,w,h)
          or not pixelPoint(cfg.hold.x,cfg.hold.y,w,h)
          or not pixelPoint(cfg.swipe.x1,cfg.swipe.y1,w,h)
          or not pixelPoint(cfg.swipe.x2,cfg.swipe.y2,w,h)
          or not validInt(cfg.hold.ms,100,2000)
          or not validInt(cfg.swipe.ms,100,2000) then
        return "FAIL","configure all safe pixel coordinates before enabling"
      end
      local a,e,c=nk.tap(cfg.tap.x,cfg.tap.y)
      if not a then return "FAIL","tap: "..safe(c or e) end
      local slept,se,sc=nk.sleep(350)
      if not slept then return "FAIL","delay after tap: "..safe(sc or se) end
      local stays,foregroundErr=assertForeground(cfg.bundle)
      if not stays then return "FAIL","after tap: "..foregroundErr end
      a,e,c=nk.hold(cfg.hold.x,cfg.hold.y,cfg.hold.ms)
      if not a then return "FAIL","hold: "..safe(c or e) end
      slept,se,sc=nk.sleep(350)
      if not slept then return "FAIL","delay after hold: "..safe(sc or se) end
      stays,foregroundErr=assertForeground(cfg.bundle)
      if not stays then return "FAIL","after hold: "..foregroundErr end
      a,e,c=nk.swipe(cfg.swipe.x1,cfg.swipe.y1,cfg.swipe.x2,
                        cfg.swipe.y2,cfg.swipe.ms)
      if not a then return "FAIL","swipe: "..safe(c or e) end
      return "WARN","3 commands dispatched; visually verify target app"
    end)
  end

  handlers.input=function()
    test("input","reject_invalid_text",function()
      if invalidReturn(nk.inputText("")) then
        return "PASS","empty text rejected without inserting"
      end
      return "FAIL","empty inputText was not rejected"
    end)
    test("input","reject_password_ocr",function()
      if type(nk.inputPassword)~="function" then
        return "FAIL","inputPassword unavailable"
      end
      local ok,err,code=nk.inputPassword("TEST_ONLY",{
         verify={x=0,y=0,w=40,h=40}})
      if ok==nil and code=="SECURE" then
        return "PASS","password OCR forbidden"
      end
      return "FAIL","secure input verification guard missing"
    end)
    test("input","interactive_input_text",function()
      local cfg=opts.input
      if type(cfg)~="table" or cfg.enabled~=true then
        return "SKIP","disabled; no text inserted"
      end
      -- A second explicit confirmation is required. Simply flipping
      -- enabled=true must NOT make default (0,0) coordinates actionable.
      if cfg.confirmed~=true then
        return "FAIL","set confirmed=true only after configuring the test screen"
      end
      local fg,fe=assertForeground(cfg.bundle)
      if not fg then return "FAIL",fe end
      local w,h,dimErr=dimensions()
      if not w then return "FAIL",dimErr end
      if not pixelPoint(cfg.x,cfg.y,w,h) then
        return "FAIL","configure input field tap coordinate in physical pixels"
      end
      local text=cfg.text
      if type(text)~="string" or #text==0 or #text>256
          or not utf8.len(text) then
        return "FAIL","use a short NONSECRET test string"
      end
      local verify
      if type(cfg.verify)=="table" then
        local v=cfg.verify
        if not pixelPoint(v.x,v.y,w,h)
           or not validInt(v.w,1,w) or not validInt(v.h,1,h)
           or v.x+v.w>w or v.y+v.h>h then
          return "FAIL","invalid optional OCR verification rectangle"
        end
        verify={x=v.x,y=v.y,w=v.w,h=v.h,expected=text}
      end
      local tapped,e,c=nk.tap(cfg.x,cfg.y)
      if not tapped then return "FAIL","focus tap: "..safe(c or e) end
      local slept,se,sc=nk.sleep(400)
      if not slept then return "FAIL","delay after focus tap: "..safe(sc or se) end
      local still,focusErr=assertForeground(cfg.bundle)
      if not still then return "FAIL","after focus tap: "..focusErr end
      -- Absolutely no retry, including when OCR result is ambiguous.
      local ok,meta,code=nk.inputText(text,verify and {verify=verify} or {})
      if ok and type(meta)=="table" and meta.verified then
        return "PASS","text verified by OCR (no retry)"
      end
      if ok then return "WARN","text dispatched; check editor content" end
      if code=="UNVERIFIED" then
        return "WARN","text dispatched but OCR unverified; no retry"
      end
      return "FAIL","input dispatch: "..safe(code or meta)
    end)
  end

  handlers.color=function()
    test("color","screen_pixel_dimensions",function()
      local w,h,err=dimensions()
      if not w then return "FAIL",err end
      return "PASS",("physical_pixels=%dx%d"):format(w,h)
    end)
    local sampled,x,y
    test("color","get_color",function()
      local w,h,err=dimensions()
      if not w then return "FAIL",err end
      x,y=math.floor(w/2),math.floor(h/2)
      local c,ce,cc=nk.getColor(x,y)
      if not c then return "FAIL",safe(cc or ce) end
      if type(c)~="table" or not validInt(c.red,0,255)
         or not validInt(c.green,0,255) or not validInt(c.blue,0,255) then
        return "FAIL","invalid RGB 0..255 from native"
      end
      local packed=c.red*65536+c.green*256+c.blue
      if c.packed~=packed then
        return "FAIL","getColor packed RGB mismatch"
      end
      sampled=c
      return "PASS",("x=%d y=%d rgb=%d,%d,%d"):format(
           x,y,c.red,c.green,c.blue)
    end)
    test("color","match_color",function()
      if not sampled then return "SKIP","getColor prerequisite failed" end
      local matched,actual,code=nk.matchColor(x,y,sampled.red,
                     sampled.green,sampled.blue,8)
      if matched==nil then return "FAIL",safe(code or actual) end
      if type(actual)~="table" or not validInt(actual.red,0,255)
          or not validInt(actual.green,0,255)
          or not validInt(actual.blue,0,255) then
        return "FAIL","matchColor missing valid observed RGB"
      end
      local delta=math.max(math.abs(actual.red-sampled.red),
                           math.abs(actual.green-sampled.green),
                           math.abs(actual.blue-sampled.blue))
      if matched==false then
        return "WARN","pixel changed between captures; max_channel_delta="..delta
      end
      if delta>8 then
        return "FAIL","matchColor claimed true outside RGB tolerance"
      end
      return "PASS","matches within RGB tolerance=8; max_channel_delta="..delta
    end)
    test("color","find_color_1x1",function()
      if not sampled then return "SKIP","getColor prerequisite failed" end
      local t=8
      local hit,err,code=nk.findColor(x,y,1,1,
        math.max(0,sampled.red-t),math.min(255,sampled.red+t),
        math.max(0,sampled.green-t),math.min(255,sampled.green+t),
        math.max(0,sampled.blue-t),math.min(255,sampled.blue+t),0)
      if not hit then
        if code=="NOT_FOUND" then
          return "WARN","pixel may have changed between captures"
        end
        return "FAIL",safe(code or err)
      end
      if hit.x~=x or hit.y~=y then
        return "FAIL","findColor returned unexpected pixel coordinate"
      end
      if not validInt(hit.red,0,255) or not validInt(hit.green,0,255)
         or not validInt(hit.blue,0,255) then
        return "FAIL","findColor returned invalid or missing RGB"
      end
      local delta=math.max(math.abs(hit.red-sampled.red),
                           math.abs(hit.green-sampled.green),
                           math.abs(hit.blue-sampled.blue))
      if delta>t then
        return "FAIL","findColor returned RGB outside requested tolerance"
      end
      return "PASS","single-pixel lookup; max_channel_delta="..delta
    end)
  end

  handlers.vision=function()
    -- Capture exactly ONCE for all Vision tests in this group.
    -- No new screenshot between getColor, findColor, OCR and findImage.
    local frameData,frameError
    test("vision","single_frame_multiple_reads",function()
      if type(nk.withFrame)~="function" then
        return "FAIL","Vision Core missing"
      end
      local info,err,code=nk.withFrame(function(frame)
        local size=assert(frame:info())
        assert(size.width>0 and size.height>0,"invalid image metadata")
        local x,y=math.floor(size.width/2),math.floor(size.height/2)
        local c=assert(frame:getColor(x,y))
        local hit=assert(frame:findColor(x,y,1,1,c.red,c.red,
                             c.green,c.green,c.blue,c.blue,0))
        assert(hit.x==x and hit.y==y,"frozen findColor mismatch")
        local again=assert(frame:getColor(x,y))
        assert(again.packed==c.packed,"immutable frame changed")
        local data={info=size}
        local text,e,c=frame:ocr(0,0,size.width,math.min(size.height,240),"")
        if text==nil then data.ocrErr=safe(c or e or "Vision OCR failed")
        else data.ocrBytes=#text end
        local template=opts.vision and opts.vision.template
        if template~=nil then
          if type(template)~="string" or template=="" or
              template:find("[\r\n]") then
            data.templateErr="invalid template image path"
            data.templateCode="INVALID"
          else
            local image,imageErr,imageCode=frame:findImage(template,2,0.8,0.8)
            data.template=image
            data.templateErr=safe(imageCode or imageErr)
            data.templateCode=imageCode
          end
        end
        return data
      end)
      if not info then
        frameError=safe(code or err)
        return "FAIL",frameError
      end
      frameData=info
      return "PASS",("one screenshot %dx%d; color/findColor/repeat/OCR"):format(
               info.info.width,info.info.height)
    end)
    test("vision","frame_screen_dimensions",function()
      if not frameData then return "SKIP",frameError or "frame prerequisite failed" end
      local w,h,err=dimensions()
      if not w then return "FAIL",err end
      local v=frameData.info
      if v.width~=w or v.height~=h then
        return "WARN",("frame=%dx%d screen=%dx%d (rotation/scale?)"):format(
                      v.width,v.height,w,h)
      end
      return "PASS",("screenshot and device agree: %dx%d pixels"):format(w,h)
    end)
    test("vision","ocr_from_same_frame",function()
      if not frameData then return "SKIP",frameError or "frame prerequisite failed" end
      if frameData.ocrErr then return "FAIL",frameData.ocrErr end
      return "PASS","OCR bytes="..frameData.ocrBytes.." from same JPEG"
    end)
    test("vision","template_from_same_frame",function()
      local path=opts.vision and opts.vision.template
      if not path then return "SKIP","no explicit template image configured" end
      if not frameData then return "SKIP",frameError or "frame prerequisite failed" end
      if frameData.templateCode=="INVALID" then
        return "FAIL",frameData.templateErr
      end
      if not frameData.template then
        if frameData.templateCode=="NOT_FOUND" then
          return "WARN","template not visible in frozen frame"
        end
        return "FAIL",frameData.templateErr or "image matcher error"
      end
      return "PASS","template found in same frozen frame"
    end)
  end

  handlers.network=function()
    test("network","json_roundtrip",function()
      local json=require("nkjson")
      local encoded,err=json.encode({hello="Xin chào",enabled=true,
                                 items=json.array({1,2,3})})
      if not encoded then return "FAIL",err end
      local decoded,e=json.decode(encoded)
      if not decoded or e or decoded.hello~="Xin chào"
          or decoded.enabled~=true or decoded.items[3]~=3 then
        return "FAIL",safe(e or "JSON roundtrip mismatch")
      end
      return "PASS","UTF-8, arrays and booleans"
    end)
    test("network","invalid_url_no_request",function()
      local http=nk.http or require("nknet")
      local value,err,code=http.request({url="file:///etc/passwd"})
      if value==nil and code=="INVALID" then
        return "PASS","file:// rejected before network dispatch"
      end
      return "FAIL","HTTP invalid URL guard missing"
    end)
    test("network","live_https_get",function()
      local cfg=opts.network
      if not cfg or cfg.enabled~=true then
        return "SKIP","no external network by default"
      end
      local http=nk.http or require("nknet")
      -- Never use user-supplied tokens/URLs in the built-in public test.
      local result,err,code=http.get("https://example.com",{
                           timeout_ms=5000,max_bytes=8192})
      if not result then return "WARN","HTTPS failed: "..safe(code or err) end
      if type(result.status)~="number" then
        return "FAIL","invalid HTTP status response"
      end
      return "PASS","HTTPS status="..result.status
    end)
  end

  handlers.task=function()
    test("task","ipc_ping",function()
      local ok,err,code=nk.ping()
      if not ok then return "FAIL",safe(code or err) end
      return "PASS","SpringBoard IPC reachable"
    end)
    test("task","foreground_consistency",function()
      local fg,err,code=nk.foreground()
      if type(fg)~="string" or fg=="" then
        return "FAIL",safe(code or err)
      end
      return "PASS","foreground bundle available"
    end)
    test("task","bounded_sleep",function()
      local ok,err,code=nk.sleep(40)
      if not ok then return "FAIL",safe(code or err) end
      return "PASS","40ms delay returned"
    end)
    test("task","read_only_stress",function()
      if type(nk.stress)~="function" or not nk.DIRECT then
        return "SKIP","native read-only stress requires direct nkcore"
      end
      local result,err,code=nk.stress(5)
      if not result then return "FAIL",safe(code or err) end
      if result.failures~=0 then
        return "FAIL","read-only stress failures="..tostring(result.failures)
      end
      return "PASS","5 screen reads with no failures"
    end)
    test("task","stop_is_not_called",function()
      -- Stopping the running Test Lab worker would make its own report
      -- unreliable, so no stop/cleanup is performed by self-tests.
      return "SKIP","stop/cleanup require separate manual supervisor test"
    end)
  end
  return handlers
end

function M.run(opts,dependencies)
  opts=opts or {}
  if type(opts)~="table" then error("Test Lab options must be a table",0) end
  dependencies=dependencies or {}
  local nk=dependencies.nk or require("nktouch_v7")
  local now=dependencies.now
  local clockType=dependencies.now and "mock_clock" or "cpu_time_only"
  if not now then
    local ok,core=pcall(require,"nkcore")
    if ok and type(core)=="table" and type(core.nowMs)=="function" then
      now=core.nowMs
      clockType="monotonic_native_ms"
    else
      -- os.clock counts CPU time, NOT wall clock. Never present fallback
      -- values as true end-to-end latency after nk.sleep/network requests.
      now=function()return math.floor(os.clock()*1000) end
    end
  end
  local id=opts.run_id or ("manual_"..os.date("!%Y%m%d_%H%M%S"))
  if not runId(id) then error("invalid Test Lab run ID",0) end
  local requested=opts.selected
  if requested==nil then requested=ORDER end
  if type(requested)~="table" then error("selected must be an array",0) end
  local wanted={}
  for index,name in ipairs(requested) do
    if not TITLES[name] or wanted[name] then
      error("unknown or duplicated Test Lab group at "..index,0)
    end
    wanted[name]=true
  end
  if #requested==0 then error("at least one Test Lab group required",0) end
  local groups={}
  for _,key in ipairs(ORDER) do
    if wanted[key] then groups[#groups+1]=key end
  end
  local reportPath=dependencies.reportPath
  if reportPath==nil then reportPath=REPORT end
  if reportPath==false then reportPath=nil end
  local mode=((type(opts.touch)=="table" and opts.touch.enabled==true)
      or (type(opts.input)=="table" and opts.input.enabled==true)
      or (type(opts.network)=="table" and opts.network.enabled==true))
      and "opt_in_requested" or "read_only_default"
  local check,finish=reporter(nk,groups,id,now,reportPath,mode,clockType)
  local handlers=makeGroups(nk,opts,check)
  print(("[NKLAB] version=%s run=%s selected=%s mode=read-only-default"):format(
    M.VERSION,id,table.concat(groups,",")))
  for _,key in ipairs(groups) do
    local ok,err=pcall(handlers[key])
    if not ok then
      check(key,"group_exception",function()
        return "FAIL",safe(err)
      end)
    end
  end
  return finish()
end

M.GROUPS=ORDER
M.TITLES=TITLES
M.REPORT_PATH=REPORT
return M
