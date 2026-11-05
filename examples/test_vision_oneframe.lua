-- NKTouch v0.7.15 - Vision Core Self-Test.
-- Safe, read-only. Captures ONE immutable frame and reuses it for
-- getColor/findColor/repeat getColor, then closes it.
local path="/var/jb/usr/share/nktouch/lua/nkvision_selftest.lua"
local run,err=loadfile(path,"t")
if not run then error("VISION_SELFTEST_NOT_INSTALLED: "..tostring(err),0) end
return run()
