-- NKTouch exit-crash isolation test. NO taps, input, OCR, or mutations.
-- If [NKEXIT][DONE] appears but nktask reports exit 139 signal 11,
-- investigate Lua shutdown / native module __gc and collect the .ips crash log.
pcall(function()io.stdout:setvbuf("no")end)
print("[NKEXIT][BOOT] "..tostring(_VERSION))
local ok,nk=pcall(require,"nktouch_v7")
if not ok then
  io.stderr:write("[NKEXIT][LOAD_FAIL] "..tostring(nk).."\n")
  os.exit(2,false)
end
print("[NKEXIT][LOAD_OK]")
local ran,screen,err,code=pcall(nk.screen)
print("[NKEXIT][SCREEN] call="..tostring(ran).." got_screen="..
  tostring(type(screen)=="string").." code="..tostring(code))
print("[NKEXIT][DONE] normal return; check NKTask exit code")
pcall(function()io.stdout:flush()end)
-- Intentionally return. Do not use the workaround here.
