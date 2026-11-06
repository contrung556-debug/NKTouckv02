-- NKTouch Input Engine Pro v0.8.5: optional Safe Input to Notes.
-- OFF by default; update the focus coordinates after inspecting the screen.
-- All coordinates are physical screen pixels (same as nk.screen()).
-- Safe mode verifies foreground BEFORE and AFTER one focus tap,
-- but a focus tap is not native first-responder proof.
local ENABLE_REAL_INPUT=false
if not ENABLE_REAL_INPUT then
  print("[NKINPUT][SKIP] Manual Notes edit field and ENABLE_REAL_INPUT required")
  return
end
local nk=require("nktouch_v7")
local ok,result,code=nk.inputSafe("NKTouch Safe Input thử nghiệm",{
  bundle="com.apple.mobilenotes",
  focus={x=350,y=400},  -- REPLACE with Notes input coordinates on this device
  settleMs=150,
  onceKey="demo.notes.field1"
})
if not ok then
  print("[NKINPUT][FAIL] code="..tostring(code).." (no automatic retry)")
  return
end
print(("[NKINPUT][PASS] status=%s foreground_checked=%s focus_verified=%s"):format(
  result.status,tostring(result.foreground_verified),tostring(result.focus_verified)))
-- Focus_verified=false without a native focus probe; no OCR used.
