-- NKTouch v0.8.7 READ ONLY focus probe in Notes. Does not type or tap.
-- Open Notes, place the caret inside an editable field, then run this script.
local nk=require("nktouch_v7")
local TARGET="com.apple.mobilenotes"
local active=nk.foreground()
if active~=TARGET then
  print("[NKFOCUS][SKIP] Open Notes first, foreground="..tostring(active))
  return
end
local yes,err,code=nk.focusedInput(TARGET)
if yes==true then
  print("[NKFOCUS][PASS] UIKit UIKeyInput first responder detected")
elseif yes==false then
  print("[NKFOCUS][NO_FOCUS] App foreground; no confirmed UIKit first responder")
else
  print("[NKFOCUS][UNKNOWN] "..tostring(code).." (no text attempted)")
end
-- Read-only confirmation is a snapshot; focus may change after this query.
