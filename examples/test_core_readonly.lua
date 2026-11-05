-- NKTouch v0.7.15 - Lua Core Self-Test (read-only).
-- Safe by default: no gestures, no text injection and no external requests.
-- Tests: Lua runtime, native IPC, foreground, screen, getColor, findColor,
-- matchColor, screenshot and delay. Results: [NKCORE][SUMMARY].
local path="/var/jb/usr/share/nktouch/lua/nkcore_selftest.lua"
local run,err=loadfile(path,"t")
if not run then error("SELFTEST_NOT_INSTALLED: "..tostring(err),0) end
-- Prevent inherited command line options (e.g. --touch) from enabling
-- side effects in an otherwise read-only sample.
local oldArg=arg
arg={}
local ok,result=xpcall(run,debug.traceback)
arg=oldArg
if not ok then error(result,0) end
return result
