-- NKTouch v0.8.11 OCR State sample. READ ONLY.
-- This sample observes one existing screen; it never taps or types.
local nk=require("nktouch_v7")
local raw,err,code=nk.screen()
if not raw then
  print("[NKVISION811][SKIP] screen "..tostring(code or err))
  return
end
local sw,sh=tostring(raw):match("^%s*(%d+%.?%d*)%s*;;%s*(%d+%.?%d*)%s*$")
sw,sh=tonumber(sw),tonumber(sh)
if not sw or not sh or sw<320 or sh<600 then
  print("[NKVISION811][SKIP] invalid screen geometry")
  return
end

local normalized,normalizeErr,normalizeCode=nk.normalizeOCR(
  "Nhập tên để tạo Tài khoản Meta")
if normalized~="nhaptendetaotaikhoanmeta" then
  print("[NKVISION811][FAIL] normalize code="..tostring(normalizeCode)
    .." detail="..tostring(normalizeErr))
  return
end
print("[NKVISION811][PASS] Vietnamese OCR normalization")
-- The labels below are examples for Facebook onboarding. Edit phrases to
-- match another app. OCR text is never printed or returned by default.
local result,why,kind,detail=nk.waitForOCRState({
  x=0,y=0,w=math.floor(sw),h=math.floor(sh),
  labels={
    name_form={"nhap ten de tao tai khoan","ban ten gi"},
    facebook_join={"tham gia facebook"}
  },
  stable_reads=2,max_reads=8,interval_ms=300,timeout_ms=4000
})
if result then
  print(("[NKVISION811][PASS] stable_state=%s reads=%d elapsed_ms=%d"):format(
    result.state,result.reads,result.elapsed_ms))
else
  print(("[NKVISION811][%s] code=%s reads=%s last=%s; no action taken"):format(
    kind=="STATE_UNCERTAIN" and "UNCERTAIN" or "FAIL",
    tostring(kind),tostring(detail and detail.reads),
    tostring(detail and detail.last_state)))
  if kind~="STATE_UNCERTAIN" then print("[NKVISION811][DETAIL] "..tostring(why)) end
end
