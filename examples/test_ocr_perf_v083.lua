-- NKTouch v0.8.3 opt-in, read-only OCR profiling.
-- Each same-frame OCR attempt captures exactly once; live OCR is separate.
-- Run on a screen with visible text. No tap, input or network request.
local perf=require("nkocr_perf")
local result,err,code=perf.benchmark({
  runs=10,         -- 3..20 measured frame OCR calls
  warmup=2,        -- 0..3 unmeasured warm-ups
  roi_height=220,  -- physical pixels, top of screen
  live_runs=3,     -- separate captures, for reference only
  memory_frames=50,-- 50 captured frames with explicit close/release
  pause_ms=100
})
if not result then error("NKPERF setup "..tostring(code).." "..tostring(err),0) end
perf.printReport(result)
if result.status=="FAIL" then
  error("NKPERF failures observed; inspect codes, not OCR text",0)
end
-- A single run cannot prove OCR accuracy or absence of memory leaks.
