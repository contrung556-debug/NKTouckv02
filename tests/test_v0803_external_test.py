"""v0.8.3 External App Test: source contract + mock Lua behavior.

These tests cannot claim that opening a real app or the Vision IPC succeeds
on-device. The generated task and its foreground gate require an iPhone test.
"""
from pathlib import Path
import subprocess
import tempfile
import unittest
import shutil

ROOT=Path(__file__).resolve().parents[1]

class ExternalAppTest(unittest.TestCase):
    def test_ui_creates_independent_managed_readonly_worker(self):
        s=(ROOT/"patches/NKExternalAppLabMethods.m.inc").read_text()
        for x in ("labChooseExternalApp", "labStartExternalRunner",
                  "NKTargetAppPickerViewController", "NKTargetValidID(bundle)",
                  'NKLuaRun(@[@"target-run",path]', "nk.openApp(bundle)",
                  "nk.waitApp(bundle,8000,200)", "nk.sleep(1000)",
                  "external={enabled=true,expected_bundle=bundle}",
                  "memory={loops=10}", "touch={enabled=false}",
                  "input={enabled=false}", "network={enabled=false}"):
            self.assertIn(x,s)
        self.assertNotIn("nk.tap(",s)
        self.assertNotIn("nk.inputText(",s)
        self.assertIn("if ([fs fileExistsAtPath:path])",s)
        self.assertIn("writeToFile:path atomically:YES",s)
        self.assertIn("dispatch_get_global_queue(",s)

    def test_ui_patch_respects_prior_lab_and_reports_external_state(self):
        ui=(ROOT/"patches/NKTestLabUIViewController.m.inc").read_text()
        with tempfile.TemporaryDirectory() as temp:
            target=Path(temp)/"zxtouch/zxtouch/Settings"
            target.mkdir(parents=True)
            file=target/"SettingsPageViewController.m"
            stub=("static NSString *NKLuaRun(NSArray *arguments,int *code);\n"
                  "static NSString *NKLuaRun(NSArray *arguments,int *code) {return @\"ok\";}\n"
                  "if ([cmd isEqualToString:@\"target-run\"] && arguments.count == 2) {}\n"
                  "static BOOL NKTargetValidID(NSString *bundle) {return YES;}\n"
                  "@interface NKTargetAppPickerViewController : NSObject @end\n"
                  + ui + "\n")
            file.write_text(stub)
            command=["python3",str(ROOT/"scripts/apply-v0803-external-test.py"),temp]
            p=subprocess.run(command,text=True,capture_output=True)
            self.assertEqual(p.returncode,0,p.stderr)
            output=file.read_text()
            self.assertIn("Test ứng dụng khác • 5 lõi",output)
            self.assertIn("labStartExternalRunner",output)
            self.assertIn('external[@"expected_bundle"]',output)
            self.assertIn("constraintEqualToAnchor:external.topAnchor",output)
            self.assertEqual(output.count("- (void)labChooseExternalApp {"),1)
            again=subprocess.run(command,text=True,capture_output=True)
            self.assertNotEqual(again.returncode,0)

    @unittest.skipUnless(shutil.which("lua"),"Lua 5.4 unavailable")
    def test_external_foreground_gate_and_read_only_contract(self):
        harness=r'''
package.path="lua/?.lua;"..package.path
local lab=require("nktestlab")
local function make(fg)
  local counts={touch=0,foreground=0}
  local mock={DIRECT=true}
  mock.foreground=function()
    counts.foreground=counts.foreground+1
    if type(fg)=="function" then return fg(counts.foreground) end
    return fg
  end
  mock.screen=function() return "750;;1334" end
  mock.tap=function(x) counts.touch=counts.touch+1; return nil,"invalid","INVALID" end
  mock.hold=function() return nil,"invalid","INVALID" end
  mock.swipe=function() return nil,"invalid","INVALID" end
  mock.path=function() return nil,"invalid","INVALID" end
  return mock,counts
end
local opts={selected={"touch"},run_id="external_good",
   external={enabled=true,expected_bundle="com.apple.mobilesafari"},
   touch={enabled=false},input={enabled=false},network={enabled=false}}
local mock,c=make("com.apple.mobilesafari")
local r=lab.run(opts,{nk=mock,reportPath=false,now=function()return 1234 end})
assert(r.status=="PASS",r.status)
assert(r.mode=="external_read_only")
assert(r.external.verified==true)
assert(r.external.foreground_start=="com.apple.mobilesafari")
assert(r.external.foreground_end=="com.apple.mobilesafari")
assert(r.external.observation=="FOREGROUND_STABLE")
assert(r.pass==3 and r.skip==1)
assert(c.touch==1) -- only deliberately invalid coordinates, never dispatched
mock,c=make("com.apple.Preferences")
local bad=lab.run(opts,{nk=mock,reportPath=false,now=function()return 1234 end})
assert(bad.status=="FAIL")
assert(bad.external.verified==false)
assert(bad.external.observation=="FOREGROUND_MISMATCH")
assert(c.touch==0) -- no test methods dispatched if foreground mismatch
mock,c=make(function(n)
  if n>=3 then return "com.apple.Preferences" end
  return "com.apple.mobilesafari"
end)
local drift=lab.run(opts,{nk=mock,reportPath=false,now=function()return 1234 end})
assert(drift.status=="FAIL")
assert(drift.external.observation=="FOREGROUND_CHANGED")
local ok,err=pcall(lab.run,{
  selected={"touch"},run_id="external_unsafe",
  external={enabled=true,expected_bundle="com.apple.mobilesafari"},
  touch={enabled=true,confirmed=true}
},{nk=mock,reportPath=false})
assert(not ok and tostring(err):find("strictly read-only",1,true))
print("PASS v0.8.3 mock Lab guarded against wrong/changed app and touch opt-in")
'''
        x=subprocess.run(["lua","-e",harness],cwd=ROOT,capture_output=True,text=True)
        self.assertEqual(x.returncode,0,x.stdout+"\n"+x.stderr)

    def test_version_bump_is_safe_staging_only(self):
        s=(ROOT/"scripts/prepare-v0803-release.sh").read_text()
        self.assertIn("prepare-v0802-release.sh",s)
        self.assertIn("apply-v0803-external-test.py",s)
        self.assertIn("Version: 0.8.3",s)
        self.assertIn('external_read_only',s)
        self.assertNotIn("sileo-repo",s)
        w=(ROOT/".github/workflows/build-v0803-external-test.yml").read_text()
        for x in ("NK_VERSION: 0.8.3","NK_BUILD: 80300",
                  "release/v0803-build-ready.txt",
                  "prepare-v0803-release.sh",
                  "test_v0803_external_test.py",
                  "NKTouch-v0.8.3-external-test-rootless"):
            self.assertIn(x,w)

if __name__=="__main__": unittest.main()
