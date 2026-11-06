-- NKTouch 0.8.9 Runtime Reliability (READ ONLY).
-- Demonstrates bounded read checkpoints and safe cleanup without any touch,
-- typing, OCR text, screenshots or network modification.
local nk=require("nktouch_v7")
local session,err,code=nk.runtimeSession({
  deadline_ms=4000,max_steps=8,max_resources=4
})
if not session then
  print("[NKRUNTIME089][FAIL] "..tostring(code));return
end
local ok,meta,raw=session:run(function(ctx)
  assert(ctx:defer("test_cleanup",function() return true end))
  local pass,screen=ctx:step("read",function()
    return nk.screen()
  end)
  if not pass then return false end
  local ready=ctx:checkpoint()
  if not ready then return false end
  local sleepOK=ctx:sleep(100)
  if not sleepOK then return false end
  return true
end)
if not ok then
  print("[NKRUNTIME089][BLOCK] "..tostring(code))
  return
end
local report=meta.summary
print(("[NKRUNTIME089][PASS] status=%s steps=%d closed=%s cleanup_errors=%d"):format(
  report.status,report.steps,tostring(report.closed),report.cleanup_failures))
-- Diagnostic snapshot contains operation categories only; no values.
