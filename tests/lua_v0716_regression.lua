-- NKTouch v0.7.16 Regression Gate: no-device report comparison tests.
package.path="lua/?.lua;"..package.path
local compare=require("nkregression").compare
local lab=require("nktestlab")
local function report(status,clock,lat)
  return {selected={"runtime"},clock_type=clock,
    tests={{group="runtime",name="probe",status=status,ms=lat}}}
end
local r=compare(report("PASS","mock_clock",100),nil)
assert(r.status=="NO_BASELINE" and not r.comparable and not r.release_ready)
r=compare(report("WARN","mock_clock",100),report("PASS","mock_clock",20))
assert(r.status=="REGRESSION" and #r.regressions==1)
assert(r.regressions[1].check=="runtime/probe")
assert(r.regressions[1].from=="PASS" and r.regressions[1].to=="WARN")
assert(not r.release_ready)
r=compare(report("PASS","monotonic_native_ms",60),
          report("PASS","monotonic_native_ms",10))
assert(r.status=="LATENCY_WARNING" and #r.latency_warnings==1)
r=compare(report("PASS","mock_clock",60),
          report("PASS","monotonic_native_ms",10))
assert(r.status=="NO_REGRESSION_OBSERVED")
r=compare({selected={"vision"},tests={}},report("PASS","mock_clock",10))
assert(r.status=="NOT_COMPARABLE")
r=compare(report("PASS","mock_clock",10),report("FAIL","mock_clock",10))
assert(r.status=="NO_REGRESSION_OBSERVED" and #r.improvements==1)

local missing=compare(
 {selected={"runtime"},tests={{group="runtime",name="kept",status="PASS",ms=5}}},
 {selected={"runtime"},tests={{group="runtime",name="kept",status="PASS",ms=5},
                              {group="runtime",name="vanished",status="PASS",ms=5}}})
assert(missing.status=="REGRESSION" and #missing.regressions==1)
assert(missing.regressions[1].to=="MISSING")
local path=assert(arg[1],"temporary report path required")
local now=0
local nk={
  DIRECT=true,
  screen=function()return "750.000000;;1334.000000"end,
  inputText=function()return true end
}
local opts={selected={"runtime"},run_id="history_run_first"}
local first=lab.run(opts,{nk=nk,now=function() now=now+5;return now end,
  reportPath=path})
assert(first.regression and first.regression.status=="NO_BASELINE")
nk.DIRECT=false
opts.run_id="history_run_second"
local second=lab.run(opts,{nk=nk,now=function() now=now+5;return now end,
  reportPath=path})
assert(second.regression.status=="REGRESSION")
assert(second.regression.comparable and #second.regression.regressions==1)
local file=assert(io.open(path,"rb"))
local bytes=file:read("*a");file:close()
local stored=assert(require("nkjson").decode(bytes))
assert(stored.run_id=="history_run_second")
assert(stored.regression.status=="REGRESSION")
assert(stored.regression.release_ready==false)
print("[NKLAB][REGRESSION] PASS: real JSON comparison and atomic replacement")
