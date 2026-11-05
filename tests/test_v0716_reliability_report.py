"""NKTouch Test Lab Reliability Report: honest timing and opt-in safety."""
from pathlib import Path
import json
import shutil
import subprocess
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]
LUA=ROOT/"lua/nktestlab.lua"

class ReliabilityReportTests(unittest.TestCase):
    @unittest.skipUnless(shutil.which("lua"),"Lua 5.4 is required")
    def test_per_group_timing_metrics_are_measured_not_invented(self):
        harness=r'''
package.path="lua/?.lua;"..package.path
local lab=require("nktestlab")
local calls=0
local nk={
  DIRECT=false,
  screen=function() return "750.000000;;1334.000000" end,
  inputText=function() error("must never send real input in read-only Test Lab") end,
  ping=function() return true end,
  foreground=function() return "com.apple.mobilesafari" end,
  sleep=function() return true end,
}
local function clock()
  calls=calls+1
  return calls*7
end
local report=lab.run({selected={"runtime","task"},run_id="reliability_mock_01"},
  {nk=nk,now=clock,reportPath=arg[1]})
assert(report.clock_type=="mock_clock")
assert(report.mode=="read_only_default" and not report.visual_confirmation)
assert(report.coverage=="PARTIAL" and report.status=="WARN")
assert(report.pass==6 and report.warn==1 and report.skip==2,
  string.format("%d/%d/%d",report.pass,report.warn,report.skip))
local t=report.timing
assert(t.checks==#report.tests and t.checks==9)
assert(t.total_ms==63 and t.avg_check_ms==7)
assert(t.p95_check_ms==7 and t.max_check_ms==7)
assert(t.elapsed_ms>=t.total_ms)
assert(t.slowest_check.ms==7)
local rt=report.groups.runtime
assert(rt.executed==4 and rt.check_pass_rate_pct==75)
assert(rt.timing.checks==4 and rt.timing.total_ms==28)
local task=report.groups.task
assert(task.executed==3 and task.timing.checks==5)
assert(task.check_pass_rate_pct==100)
assert(task.timing.total_ms==35)
print("[NKLAB][RELIABILITY] AGGREGATION_PASS")
'''
        with tempfile.TemporaryDirectory() as d:
            harness_path=Path(d)/"harness.lua";harness_path.write_text(harness)
            report=Path(d)/"report.json"
            r=subprocess.run(["lua",str(harness_path),str(report)],
                             cwd=ROOT,capture_output=True,text=True,timeout=10)
            self.assertEqual(r.returncode,0,r.stdout+r.stderr)
            self.assertIn("AGGREGATION_PASS",r.stdout)
            data=json.loads(report.read_text())
            self.assertEqual(data["timing"]["p95_check_ms"],7)
            self.assertEqual(data["groups"]["runtime"]["check_pass_rate_pct"],75)
            self.assertFalse(data["visual_confirmation"])
            self.assertEqual(data["coverage"],"PARTIAL")

    @unittest.skipUnless(shutil.which("lua"),"Lua 5.4 is required")
    def test_explicit_confirmation_prevents_default_zero_coordinate_gestures(self):
        harness=r'''
package.path="lua/?.lua;"..package.path
local lab=require("nktestlab")
local touches=0
local nk={DIRECT=true}
nk.screen=function()return "750.000000;;1334.000000"end
nk.foreground=function()return "com.apple.mobilesafari"end
nk.tap=function(x,y)
  if x<0 then return nil,"bad","INVALID" end
  touches=touches+1
  return true
end
nk.hold=function(x,y)
  if x<0 then return nil,"bad","INVALID" end
  touches=touches+1
  return true
end
nk.swipe=function(x,y,x2)
  if x2<0 then return nil,"bad","INVALID" end
  touches=touches+1
  return true
end
nk.path=function()return nil,"invalid timestamp","INVALID"end
nk.sleep=function()return true end
local touch={
  enabled=true,confirmed=false,bundle="com.apple.mobilesafari",
  tap={x=0,y=0},hold={x=0,y=0,ms=400},
  swipe={x1=0,y1=0,x2=0,y2=0,ms=500}
}
local report=lab.run({selected={"touch"},touch=touch,run_id="safe_not_confirmed"},
                     {nk=nk,reportPath=false})
assert(report.mode=="opt_in_requested" and report.fail==1 and touches==0)
touch.confirmed=true
touch.tap={x=101,y=201};touch.hold={x=102,y=202,ms=400}
touch.swipe={x1=103,y1=203,x2=104,y2=204,ms=500}
local sent=lab.run({selected={"touch"},touch=touch,run_id="safe_confirmed"},
                      {nk=nk,reportPath=false})
assert(sent.warn==1 and sent.fail==0 and touches==3)
assert(sent.mode=="opt_in_requested" and sent.visual_confirmation==false)
print("[NKLAB][RELIABILITY] DOUBLE_CONFIRMATION_PASS")
'''
        with tempfile.TemporaryDirectory() as d:
            file=Path(d)/"lab.lua";file.write_text(harness)
            r=subprocess.run(["lua",str(file)],cwd=ROOT,
                             capture_output=True,text=True,timeout=10)
            self.assertEqual(r.returncode,0,r.stdout+r.stderr)
            self.assertIn("DOUBLE_CONFIRMATION_PASS",r.stdout)

    def test_ui_displays_latency_provenance_and_no_visual_proof(self):
        ui=(ROOT/"patches/NKTestLabUIViewController.m.inc").read_text()
        for text in ("avg_check_ms","p95_check_ms","max_check_ms",
                     "elapsed_ms","clock_type","coverage","visual_confirmation",
                     "not touch accuracy","not per-API long-term latency",
                     "confirmed=false"):
            if text=="not touch accuracy":
                self.assertIn(text,ui)
            elif text=="not per-API long-term latency":
                # This phrasing is explicitly stated for each run, not guessed.
                self.assertIn("not per-API long-term latency",ui)
            else:
                self.assertIn(text,ui)

if __name__=="__main__":
    unittest.main()
