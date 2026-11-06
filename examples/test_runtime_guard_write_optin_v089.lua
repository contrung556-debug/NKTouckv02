-- NKTouch 0.8.9 mutating actions require explicit opt-in.
-- This example is DISABLED by default and uses no live credentials.
local ENABLE_REAL_TAP=false
if not ENABLE_REAL_TAP then
  print("[NKRUNTIME089][SKIP] Read the script, calibrate and enable manually")
  return
end
local nk=require("nktouch_v7")
local target="com.apple.mobilenotes"
local session,err,code=nk.runtimeSession({
  deadline_ms=3000,max_steps=3
})
if not session then print("[NKRUNTIME089][FAIL] "..tostring(code));return end
local done,meta=session:run(function(ctx)
  local allow,current=ctx:step("read",function()
    return nk.foreground()
  end)
  if not allow or current~=target then
    return false
  end
  -- One touch at a manually calibrated physical-pixel coordinate.
  -- Use a unique onceKey PER UI target. A failed write NEVER auto-retries.
  local ok,receipt,code=ctx:step("write",function()
    return nk.tap(350,400)
  end,{confirmed=true,onceKey="notes.test.tap1"})
  if not ok then return false end
  return true
end)
print(done and "[NKRUNTIME089] finished (tap is UNVERIFIED)"
           or "[NKRUNTIME089] aborted / no automatic retry")
-- For actual UI confirmation run a separate read-only Vision check.
