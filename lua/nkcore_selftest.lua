-- NKTouch Core Self-Test v0.7.8
-- GPL-3.0-or-later. Read-only by default, no network, no recorder activity.
-- Runs as managed Lua through nktask; do not infer success from an API existing.
package.path = "/var/jb/usr/share/nktouch/lua/?.lua;" .. package.path

local core_ok, native = pcall(require, "nkcore")
local now = (core_ok and type(native) == "table" and type(native.nowMs) == "function")
    and native.nowMs or function() return math.floor(os.clock() * 1000) end
local COUNTS = {PASS=0, FAIL=0, WARN=0, SKIP=0}
local function safe(v)
    return tostring(v or ""):gsub("[\r\n\t]", " "):sub(1, 180)
end
local function emit(kind, name, ms, details)
    COUNTS[kind] = COUNTS[kind] + 1
    print(("[NKCORE][%s] %s ms=%d %s"):format(
        kind, safe(name), math.max(0, math.floor(ms or 0)), safe(details)))
end
local function check(name, callback)
    local start = now()
    local ok, good, detail, kind = pcall(callback)
    local elapsed = now() - start
    if not ok then
        emit("FAIL", name, elapsed, "lua_exception=" .. safe(good))
        return nil
    end
    if good == "SKIP" then
        emit("SKIP", name, elapsed, detail)
        return nil
    end
    if good == "WARN" then
        emit("WARN", name, elapsed, detail)
        return nil
    end
    if good == nil or good == false then
        emit("FAIL", name, elapsed, (kind and kind .. " " or "") .. safe(detail))
        return nil
    end
    emit("PASS", name, elapsed, detail)
    return good
end
local function fail_summary()
    local status = COUNTS.FAIL == 0 and "PASS" or "FAIL"
    print(("[NKCORE][SUMMARY] status=%s pass=%d fail=%d warn=%d skip=%d"):format(
        status, COUNTS.PASS, COUNTS.FAIL, COUNTS.WARN, COUNTS.SKIP))
    return COUNTS.FAIL == 0
end

local opts = {touch=false, x=nil, y=nil, image=nil, ocr=false}
local argv = arg or {}
local index = 1
while index <= #argv do
    local value = argv[index]
    if value == "--touch" then
        opts.touch = true
        opts.x = tonumber(argv[index + 1])
        opts.y = tonumber(argv[index + 2])
        index = index + 3
    elseif value == "--image" then
        opts.image = argv[index + 1]
        index = index + 2
    elseif value == "--ocr" then
        opts.ocr = true
        index = index + 1
    else
        print("[NKCORE][ERROR] invalid self-test option=" .. safe(value))
        os.exit(2)
    end
end
if opts.touch and not (opts.x and opts.y and opts.x >= 0 and opts.y >= 0
        and opts.x < 10000 and opts.y < 10000 and opts.x % 1 == 0
        and opts.y % 1 == 0) then
    print("[NKCORE][ERROR] --touch requires valid physical pixel coordinates x y")
    os.exit(2)
end

print("[NKCORE] version=0.7.8 mode=" .. (opts.touch and "touch-opt-in" or "read-only"))
local imported, nk = pcall(require, "nktouch_v7")
if not imported or type(nk) ~= "table" then
    emit("FAIL", "lua_runtime", 0, "require(nktouch_v7) " .. safe(nk))
    fail_summary()
    os.exit(1)
end

check("lua_runtime", function()
    local test = 0
    for i = 1, 150 do test = test + i end
    return test == 11325, "Lua=" .. _VERSION .. " direct=" .. tostring(nk.DIRECT)
end)
check("core_direct", function()
    if not nk.DIRECT then return false, "native nkcore unavailable", "NO_DIRECT" end
    return true, "native nkcore connected"
end)
check("ping", function()
    local result, err, kind = nk.ping()
    return result, err or "IPC ping accepted", kind
end)
local width, height
check("screen", function()
    local size, err, kind = nk.screen()
    if not size then return nil, err, kind end
    local w, h = tostring(size):match("^%s*(%d+%.?%d*);;(%d+%.?%d*)%s*$")
    width, height = tonumber(w), tonumber(h)
    if not width or not height or width < 1 or height < 1
       or width > 10000 or height > 10000 then
        return nil, "malformed physical pixel screen size: " .. safe(size), "INVALID"
    end
    width, height = math.floor(width), math.floor(height)
    return true, ("physical_pixels=%dx%d"):format(width, height)
end)
check("orientation", function()
    local value, err, kind = nk.orientation()
    if value == nil then return nil, err, kind end
    if not tonumber(value) then return nil, "unparseable orientation", "INVALID" end
    return true, "orientation=" .. safe(value)
end)
check("scale", function()
    local value, err, kind = nk.scale()
    if value == nil then return nil, err, kind end
    local n=tonumber(value)
    if not n or n < 1 or n > 5 then return nil, "invalid scale", "INVALID" end
    return true, "screen_scale=" .. n
end)
check("foreground", function()
    local value, err, kind = nk.foreground()
    if type(value) ~= "string" or value == "" then
        return nil, err or "invalid foreground bundle", kind or "INVALID"
    end
    return true, "foreground=" .. safe(value)
end)
check("sleep", function()
    local started = now()
    local ok,err,kind = nk.sleep(40)
    if not ok then return nil, err, kind end
    local elapsed = now() - started
    if elapsed < 30 or elapsed > 2000 then
        return nil, "expected 40ms sleep, measured " .. elapsed .. "ms", "TIMING"
    end
    return true, "slept_ms=" .. elapsed
end)

local sampleX, sampleY
if width and height then
    sampleX, sampleY = math.floor(width / 2), math.floor(height / 2)
end
local sampled
check("getColor", function()
    if not sampleX then return "SKIP", "valid screen dimensions required" end
    local c,err,kind = nk.getColor(sampleX, sampleY)
    if not c then return nil,err,kind end
    for _,v in ipairs({c.red,c.green,c.blue}) do
        if type(v)~="number" or v<0 or v>255 or v%1~=0 then
            return nil, "color outside 0..255", "INVALID"
        end
    end
    sampled=c
    return true, ("point=%d,%d rgb=%d,%d,%d"):format(sampleX,sampleY,c.red,c.green,c.blue)
end)
check("matchColor", function()
    if not sampled then return "SKIP", "getColor must pass" end
    local match,actual,kind = nk.matchColor(sampleX,sampleY,
                    sampled.red,sampled.green,sampled.blue,8)
    if match == nil then return nil, actual, kind end
    if match == false then return "WARN", "screen color changed between samples" end
    return true, "RGB within tolerance=8"
end)
check("findColor", function()
    if not sampled then return "SKIP", "getColor must pass" end
    local tol=8
    local rmin,rmax=math.max(0,sampled.red-tol),math.min(255,sampled.red+tol)
    local gmin,gmax=math.max(0,sampled.green-tol),math.min(255,sampled.green+tol)
    local bmin,bmax=math.max(0,sampled.blue-tol),math.min(255,sampled.blue+tol)
    local hit,err,kind=nk.findColor(sampleX,sampleY,1,1,
                       rmin,rmax,gmin,gmax,bmin,bmax,0)
    if not hit then
        if kind=="NOT_FOUND" then return "WARN", "screen pixel changed during lookup" end
        return nil,err,kind
    end
    if hit.x ~= sampleX or hit.y ~= sampleY then
        return nil, ("wrong coordinates: %s,%s"):format(hit.x,hit.y), "COORDINATE"
    end
    return true, ("found=%d,%d"):format(hit.x,hit.y)
end)
check("waitColorMatch", function()
    if not sampled then return "SKIP", "getColor must pass" end
    local hit,err,kind=nk.waitColorMatch(sampled.red,sampled.green,sampled.blue,12,
             {x=sampleX,y=sampleY,w=1,h=1},0,100)
    if not hit then
        if kind=="NOT_FOUND" or kind=="TIMEOUT" then
            return "WARN", "sample was dynamic or changed"
        end
        return nil,err,kind
    end
    if hit.x~=sampleX or hit.y~=sampleY then
        return nil, "unexpected wait-color coordinates", "COORDINATE"
    end
    return true, "waitColorMatch 1x1"
end)

local task_id=tostring(os.getenv("NKTOUCH_TASK_ID") or "manual")
if not task_id:match("^[%w_-]+$") then task_id="manual" end
local shot="/var/mobile/Library/NKTouch/tmp/core-selftest-"..task_id..".jpg"
check("screenshot", function()
    local result,err,kind=nk.screenshot(shot)
    if not result then return nil,err,kind end
    if result ~= shot then return nil, "screenshot returned unexpected path", "INVALID" end
    local file=io.open(shot,"rb")
    if not file then return nil,"screenshot missing after success","IO" end
    local bytes=file:seek("end") or 0
    file:close()
    os.remove(shot)
    if bytes<100 then return nil,"screenshot too small: "..bytes,"INVALID" end
    return true,"jpg_bytes="..bytes
end)

if opts.image then
    check("findImage", function()
        if #opts.image > 500 or opts.image:find("[\r\n]") then
            return nil,"invalid image path","INVALID"
        end
        local file=io.open(opts.image,"rb")
        if not file then return nil,"image template file missing","IO" end
        file:close()
        local match,err,kind=nk.findImage(opts.image,1,0.8,0.8)
        if not match then
            if kind=="NOT_FOUND" then return "WARN","image template not visible" end
            return nil,err,kind
        end
        return true,("match=%.0f,%.0f"):format(match.x,match.y)
    end)
else
    emit("SKIP","findImage",0,"add --image <template-path> to test matching")
end

if opts.ocr then
    check("ocr",function()
        if not width then return "SKIP", "valid screen dimensions required" end
        local text,err,kind=nk.ocr(0,0,width,height,"")
        if type(text)~="string" then return nil,err or "OCR unavailable",kind end
        return true,"ocr_bytes="..#text
    end)
else
    emit("SKIP","ocr",0,"add --ocr to test on-device OCR")
end

if opts.touch then
    check("tap",function()
        if not width or opts.x >= width or opts.y >= height then
            return nil, "tap coordinates outside screen", "COORDINATE"
        end
        local ok,err,kind=nk.tap(opts.x,opts.y)
        if not ok then return nil,err,kind end
        return "WARN","touch command accepted; cannot verify resulting UI without calibration"
    end)
else
    emit("SKIP","tap",0,"read-only default; use --touch x y for explicit opt-in")
end
emit("SKIP","swipe",0,"no blind swipe in self-test")
emit("SKIP","hold",0,"no blind hold in self-test")

if not fail_summary() then os.exit(1) end
