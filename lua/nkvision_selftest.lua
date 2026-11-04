-- NKTouch v0.7.9 Vision Core on-device smoke test.
-- One screenshot, multiple deterministic reads; never taps or navigates.
package.path="/var/jb/usr/share/nktouch/lua/?.lua;"..package.path
local nk=require("nktouch_v7")
local start=type(nk.captureFrame)=="function" and true or false
assert(start, "[VISION][FAIL] NKTouch v0.7.9 API not installed")
local native=assert(require("nkvision_native"),"[VISION][FAIL] native module missing")
assert(type(native.open)=="function","[VISION][FAIL] native module not linked")
local frame,err,code=nk.captureFrame()
assert(frame, "[VISION][FAIL] capture "..tostring(code).." "..tostring(err))
local ok, msg=pcall(function()
    local info=assert(frame:info())
    assert(info.width>0 and info.height>0 and info.immutable,"invalid frame metadata")
    local x=math.floor(info.width/2)
    local y=math.floor(info.height/2)
    local rgb=assert(frame:getColor(x,y))
    assert(rgb.red>=0 and rgb.red<=255 and rgb.green>=0 and rgb.green<=255
        and rgb.blue>=0 and rgb.blue<=255,"RGB outside 0-255")
    local hit,err,kind=frame:findColor(x,y,1,1,rgb.red,rgb.red,
                                    rgb.green,rgb.green,rgb.blue,rgb.blue,0)
    assert(hit, tostring(kind).." "..tostring(err))
    assert(hit.x==x and hit.y==y,"color search missed frozen pixel")
    local second=assert(frame:getColor(x,y))
    assert(rgb.packed==second.packed,"immutable screenshot changed")
    local absent,notFound,why=frame:findColor(x,y,1,1,
                  0,math.max(0,rgb.red-1),0,math.max(0,rgb.green-1),
                  0,math.max(0,rgb.blue-1),0)
    -- A black (0,0,0) pixel may match this range. Test negative lookup
    -- separately only if all channels are nonzero.
    if rgb.red>0 and rgb.green>0 and rgb.blue>0 then
       assert(absent==nil and why=="NOT_FOUND","expected NOT_FOUND")
    end
    print(("[VISION][PASS] one_screenshot=1 immutable_queries=3 width=%d height=%d rgb=%d,%d,%d jpeg_bytes=%d"):format(
        info.width,info.height,rgb.red,rgb.green,rgb.blue,info.bytes))
end)
local closed,closeErr=pcall(frame.close,frame)
if not closed or closeErr~=true then error("[VISION][FAIL] close failed") end
if not ok then error("[VISION][FAIL] "..tostring(msg)) end
print("[VISION][SUMMARY] status=PASS")
