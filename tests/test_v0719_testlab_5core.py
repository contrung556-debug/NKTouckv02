"""NKTouch v0.7.19 Five-Core Test Lab host tests (NOT on-device evidence)."""
from pathlib import Path
import json
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
LAB = ROOT / "lua/nktestlab.lua"
UI = ROOT / "patches/NKTestLabUIViewController.m.inc"
STAGE = ROOT / "scripts/prepare-v0719-release.sh"

class FiveCoreLab(unittest.TestCase):
    def test_ui_has_exact_five_core_default_and_advanced(self):
        ui = UI.read_text()
        lua = LAB.read_text()
        self.assertIn('addObjectsFromArray:@[@"ocr",@"color",@"touch",@"input",@"memory"]', ui)
        self.assertIn('labSelectCorePreset',ui)
        self.assertIn('memory={loops=10}',ui)
        self.assertIn('labShowReport',ui)
        self.assertIn('testlab-last.json',ui)
        self.assertIn('[NKLAB][SUMMARY]',lua)
        for name in ("ocr","color","touch","input","memory"):
            self.assertIn(f'handlers.{name}=function()',lua)
        self.assertIn('handlers.vision=function()',lua)
        self.assertIn('LEGACY_DEFAULT',lua)
        self.assertIn('mode="full"',lua)
        self.assertIn('FRAME_OCR_BROKEN',lua)
        self.assertIn('RSS_warm=',lua)
        self.assertNotIn('nk.inputText(text)',ui)
        self.assertNotIn('nk.tap(',ui)
        self.assertIn('testlab-last.json',ui)
        stage=STAGE.read_text()
        self.assertIn("prepare-v0718-release.sh",stage)
        self.assertIn("'Version: 0.7.18','Version: 0.7.19'",stage)
        self.assertNotIn("sileo-repo",stage)
        self.assertNotIn("dpkg-deb",stage)

    @unittest.skipUnless(shutil.which("lua"),"Host Lua 5.4 required")
    def test_five_core_mock_pass_and_realistic_ocr_failure(self):
        harness = r'''
package.path="lua/?.lua;"..package.path
local lab=require("nktestlab")
local mode=arg[2]
local frames,touches,inputWrites,liveCalls=0,0,0,0
local memSamples=0
package.loaded.nkmemory=nil
package.preload.nkmemory=function()
  return {
    stats=function()
      memSamples=memSamples+1
      return {lua_kb=150+memSamples,
        process_rss_available=true,
        process_rss_bytes=8388608+memSamples*4096}
    end,
    release=function(o)
      assert(o.mode=="full")
      return {lua_kb_before=192,lua_kb_after=160}
    end
  }
end
local rgb={red=25,green=75,blue=125,packed=25*65536+75*256+125}
local nk={DIRECT=true}
nk.screen=function()return "750.000000;;1334.000000"end
nk.getColor=function()return rgb end
nk.matchColor=function()return true,rgb end
nk.findColor=function(x,y) return {x=x,y=y,red=25,green=75,blue=125} end
nk.tap=function(x,y)
  if x<0 then return nil,"negative x","INVALID" end
  touches=touches+1;return true
end
nk.hold=function(x,y,duration)
  if x<0 then return nil,"negative x","INVALID" end
  touches=touches+1;return true
end
nk.swipe=function(x,y,x2)
  if x2<0 then return nil,"bad endpoint","INVALID" end
  touches=touches+1;return true
end
nk.path=function()return nil,"nonmonotonic","INVALID"end
nk.inputText=function(text)
  if text=="" then return nil,"empty","INVALID" end
  inputWrites=inputWrites+1;return true
end
nk.inputPassword=function(text,opts)
  assert(opts.verify)
  return nil,"password OCR forbidden","SECURE"
end
nk.ocr=function()
  liveCalls=liveCalls+1
  return "visible text"
end
nk.withFrame=function(callback)
  frames=frames+1
  local rgba=0
  local frame={
    info=function()
      return {width=750,height=1334,rgba_bytes=rgba,gray_bytes=0}
    end,
    getColor=function()
      rgba=750*1334*4
      return rgb
    end,
    ocr=function()
      if mode=="frame_broken" then
        return nil,"Vision NSError domain=VNErrorDomain code=12","OCR"
      end
      return "visible text"
    end
  }
  return callback(frame)
end
local result=lab.run({
  run_id="five_core_"..mode,
  selected={"ocr","color","touch","input","memory"},
  memory={loops=10},
  touch={enabled=false,confirmed=false},
  input={enabled=false,confirmed=false}
},{nk=nk,reportPath=arg[1],now=function()return 100 end})
assert(#result.selected==5)
assert(result.groups.memory.status=="PASS",result.groups.memory.status)
assert(result.groups.touch.status=="PASS")
assert(result.groups.input.status=="PASS")
assert(frames==11, "expected one OCR frame plus 10 memory frames")
assert(touches==0 and inputWrites==0,"default Lab must not mutate apps")
assert(liveCalls==1)
local summary={}
for _,row in ipairs(result.tests) do summary[row.name]=row end
assert(summary.frame_ocr and summary.live_ocr and summary.backend_comparison)
assert(summary.vision_frame_stress and summary.lua_gc)
if mode=="frame_broken" then
  assert(result.status=="FAIL" and result.fail>=2)
  assert(summary.frame_ocr.status=="FAIL")
  assert(summary.backend_comparison.status=="FAIL")
  assert(summary.live_ocr.status=="PASS")
  assert(summary.frame_ocr.detail:find("VNErrorDomain",1,true))
else
  assert(result.status=="PASS" and result.fail==0)
  assert(summary.frame_ocr.status=="PASS")
end
print("[NKLAB_719][HOST] "..mode.." "..result.status)
'''
        for mode in ("healthy","frame_broken"):
            with self.subTest(mode=mode), tempfile.TemporaryDirectory() as d:
                script=Path(d)/"harness.lua";script.write_text(harness)
                report=Path(d)/"report.json"
                result=subprocess.run(["lua",str(script),str(report),mode],
                    cwd=ROOT,capture_output=True,text=True,timeout=25)
                self.assertEqual(result.returncode,0,result.stdout+result.stderr)
                self.assertIn("[NKLAB_719][HOST]",result.stdout)
                data=json.loads(report.read_text())
                self.assertEqual(len(data["selected"]),5)
                self.assertEqual(data["status"],"FAIL" if mode=="frame_broken" else "PASS")
                self.assertTrue(data["tests"])
                self.assertIn("timing",data)
                self.assertIn("groups",data)

if __name__=="__main__":
    unittest.main()
