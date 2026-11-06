-- v0.8.6 Touch Precision: opt-in guarded tap, OFF by default.
-- IMPORTANT: replace bundle, tap point and pixel pattern for your target.
-- Touch and colors use *physical* screen pixel coordinates.
local ENABLE_REAL_TAP=false
if not ENABLE_REAL_TAP then
  print("[NKPRECISION][SKIP] Set ENABLE_REAL_TAP=true and calibrate first")
  return
end
local nk=require("nktouch_v7")
local ok,receipt,code=nk.precisionTapIfMatch({
  enabled=true,confirmed=true,
  bundle="com.apple.mobilenotes",
  tap={x=350,y=400},
  points={
    {x=100,y=120,r=255,g=255,b=255,tolerance=8},
    {x=110,y=120,r=255,g=255,b=255,tolerance=8}
  }
})
if not ok then
  print("[NKPRECISION][BLOCK] "..tostring(code))
  return
end
print(("[NKPRECISION][SENT] status=%s frame_checked=%s app_checked=%s"):format(
  receipt.status,tostring(receipt.sample_matched),
  tostring(receipt.foreground_verified)))
-- No automatic tap retry. DISPATCHED_UNVERIFIED is not UI success.
