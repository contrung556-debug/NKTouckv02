-- NKTouch v0.8.7 opt-in strict Native Input sample in Notes.
-- OFF by default. Before enabling, open Notes and calibrate focus pixel.
-- NO OCR; will type only if the app and native UIKit focus both confirm.
local ENABLE_REAL_INPUT=false
if not ENABLE_REAL_INPUT then
  print("[NKFOCUS][SKIP] Enable manually after reviewing note and coordinates")
  return
end
local nk=require("nktouch_v7")
local ok,receipt,code=nk.inputSafe("NKTouch v0.8.7 Unicode: Nguyễn 🌻 123",{
  bundle="com.apple.mobilenotes",
  focus={x=350,y=400}, -- must calibrate on the actual device in physical pixels
  settleMs=150,
  requireFocusProof=true,
  onceKey="test.notes.v087.field1"
})
if not ok then
  print("[NKFOCUS][BLOCK] "..tostring(code).."; no automatic retry")
  return
end
print("[NKFOCUS][DISPATCHED] "..tostring(receipt.status)
  .." focus_verified="..tostring(receipt.focus_verified))
-- An ACK proves dispatch, not final text insertion. Check Notes manually.
