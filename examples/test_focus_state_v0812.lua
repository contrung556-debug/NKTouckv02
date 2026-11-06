-- NKTouch v0.8.12 native focus-state sample. READ ONLY.
-- It observes the foreground app's first responder; it never types or taps.
local nk=require("nktouch_v7")
local result,why,kind,detail=nk.waitForInputFocus({
  bundle="com.apple.mobilenotes",
  stable_reads=2,max_reads=8,interval_ms=250,timeout_ms=4000
})
if result then
  print(("[NKFOCUS812][PASS] state=%s reads=%d stable=%d elapsed_ms=%d"):format(
    result.state,result.reads,result.stable_reads,result.elapsed_ms))
else
  print(("[NKFOCUS812][%s] code=%s reads=%s; no input sent"):format(
    kind=="FOCUS_UNSTABLE" and "UNCERTAIN" or "FAIL",
    tostring(kind),tostring(detail and detail.reads)))
  if kind~="FOCUS_UNSTABLE" then print("[NKFOCUS812][DETAIL] "..tostring(why)) end
end
