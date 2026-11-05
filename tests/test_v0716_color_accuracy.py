"""Regression tests for Color Engine false-positive protection and Vision dimensions."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]

class ColorPrecision(unittest.TestCase):
    @unittest.skipUnless(shutil.which("lua"), "Lua 5.4 required")
    def test_backend_cannot_pass_wrong_rgb_or_packed_values(self):
        harness=r'''
package.path="lua/?.lua;"..package.path
local lab=require("nktestlab")
local nk={DIRECT=true}
local packed=12*65536+30*256+42
nk.screen=function()return "750.000000;;1334.000000"end
nk.getColor=function()return {red=12,green=30,blue=42,packed=packed}end
nk.matchColor=function()return true,{red=12,green=30,blue=42}end
nk.findColor=function(x,y)
 return {x=x,y=y,red=240,green=30,blue=42}
end
local r=lab.run({selected={"color"},run_id="bad_rgb_response"},
                {nk=nk,reportPath=false})
assert(r.fail==1 and r.pass==3,r.pass.."/"..r.fail)
assert(r.status=="FAIL")
assert(r.tests[4].name=="find_color_1x1")
assert(r.tests[4].detail:find("outside requested tolerance"))
packed=1
r=lab.run({selected={"color"},run_id="bad_packed_response"},
          {nk=nk,reportPath=false})
assert(r.fail>=1 and r.tests[2].status=="FAIL")
assert(r.tests[2].detail:find("packed RGB mismatch"))
print("[NKLAB][COLOR] FALSE_POSITIVES_REJECTED")
'''
        with tempfile.TemporaryDirectory() as temp:
            p=Path(temp)/"color.lua";p.write_text(harness)
            r=subprocess.run(["lua",str(p)],cwd=ROOT,
                             capture_output=True,text=True,timeout=10)
            self.assertEqual(r.returncode,0,r.stdout+r.stderr)
            self.assertIn("FALSE_POSITIVES_REJECTED",r.stdout)

    @unittest.skipUnless(shutil.which("lua"), "Lua 5.4 required")
    def test_one_frame_with_dimensions_mismatch_is_warn_not_false_pass(self):
        harness=r'''
package.path="lua/?.lua;"..package.path
local lab=require("nktestlab")
local captures=0
local nk={DIRECT=true}
nk.screen=function()return "750.000000;;1334.000000"end
nk.withFrame=function(callback)
 captures=captures+1
 local frame={
  info=function() return {width=390,height=844,bytes=10000} end,
  getColor=function()return {red=3,green=4,blue=5,packed=3*65536+4*256+5}end,
  findColor=function(_,x,y)return {x=x,y=y}end,
  ocr=function()return "sample"end
 }
 return callback(frame)
end
local r=lab.run({selected={"vision"},run_id="screen_mismatch_01"},
               {nk=nk,reportPath=false})
assert(captures==1,"Vision must use exactly one screenshot")
assert(r.warn==1 and r.fail==0 and r.coverage=="PARTIAL")
assert(r.groups.vision.status=="WARN")
assert(r.tests[2].name=="frame_screen_dimensions")
assert(r.tests[2].detail:find("calibration required",1,true))
print("[NKLAB][VISION] ONE_FRAME_MISMATCH_WARN")
'''
        with tempfile.TemporaryDirectory() as temp:
            p=Path(temp)/"vision.lua";p.write_text(harness)
            r=subprocess.run(["lua",str(p)],cwd=ROOT,
                             capture_output=True,text=True,timeout=10)
            self.assertEqual(r.returncode,0,r.stdout+r.stderr)
            self.assertIn("ONE_FRAME_MISMATCH_WARN",r.stdout)

if __name__=="__main__":
    unittest.main()
