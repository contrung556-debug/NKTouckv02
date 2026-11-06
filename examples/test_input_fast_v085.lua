-- NKTouch Input Engine Pro v0.8.5: optional manual benchmark.
-- The single native direct input request is fast; there is NO OCR.
-- Before enabling: open Notes, select a non-sensitive editable field.
-- This sample is OFF by default and never types by itself.
local ENABLE_REAL_INPUT=false
if not ENABLE_REAL_INPUT then
  print("[NKINPUT][SKIP] Manual Notes focus and ENABLE_REAL_INPUT required")
  return
end
local nk=require("nktouch_v7")
local app=nk.foreground()
if app~="com.apple.mobilenotes" then
  error("[NKINPUT] WRONG_APP: open Notes and focus an editable field",0)
end
local core=require("nkcore")
local start=core.nowMs()
local ok,result,code=nk.inputFast("NKTouch Fast Input thử tiếng Việt 🇻🇳\n",{})
local elapsed=core.nowMs()-start
if not ok then
  print("[NKINPUT][FAIL] code="..tostring(code).." elapsed_ms="..tostring(elapsed))
  return
end
print(("[NKINPUT][PASS] mode=%s bytes=%d dispatch_ms=%d verified=%s"):format(
  result.mode,result.bytes,elapsed,tostring(result.verified)))
-- A dispatch ACK is NOT proof the target app accepted the string.
