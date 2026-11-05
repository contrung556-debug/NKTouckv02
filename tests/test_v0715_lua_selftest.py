"""NKTouch v0.7.15: bundled Lua Self-Test suite and release batching guards."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]
PATCH=ROOT/"scripts/apply-v0715-selftest-suite.py"
PREP=ROOT/"scripts/prepare-v0715-lua-selftest.sh"
CORE=ROOT/"examples/test_core_readonly.lua"
VISION=ROOT/"examples/test_vision_oneframe.lua"
GESTURE=ROOT/"examples/test_gestures_optin.lua"
WORKFLOW=ROOT/".github/workflows/build-v0715-lua-selftest.yml"

class LuaFunctionSelftest(unittest.TestCase):
    def test_read_only_examples(self):
        core=CORE.read_text()
        vision=VISION.read_text()
        self.assertIn("/var/jb/usr/share/nktouch/lua/nkcore_selftest.lua",core)
        self.assertIn("arg={}",core)
        self.assertIn("/var/jb/usr/share/nktouch/lua/nkvision_selftest.lua",vision)
        self.assertIn("return run()",vision)
        # The wrapped core and vision scripts already exist in the package.
        self.assertTrue((ROOT/"lua/nkcore_selftest.lua").is_file())
        self.assertTrue((ROOT/"lua/nkvision_selftest.lua").is_file())

    def test_gestures_are_explicit_opt_in_and_failsafe(self):
        text=GESTURE.read_text()
        for part in ('ENABLE_GESTURES=false','EXPECTED_BUNDLE=""',
                     'TAP_X,TAP_Y=nil,nil','HOLD_X,HOLD_Y=nil,nil',
                     'SWIPE_X1,SWIPE_Y1=nil,nil','SWIPE_X2,SWIPE_Y2=nil,nil',
                     'nk.waitApp(EXPECTED_BUNDLE,2000,200)',
                     'nk.tap(TAP_X,TAP_Y)','nk.hold(HOLD_X,HOLD_Y,HOLD_MS)',
                     'nk.swipe(SWIPE_X1,SWIPE_Y1,SWIPE_X2,SWIPE_Y2,SWIPE_MS)',
                     '(%d+%.?%d*)%s*;;%s*(%d+%.?%d*)',
                     'status=SKIP'):
            self.assertIn(part,text)
        self.assertLess(text.index('if not ENABLE_GESTURES then'),
                        text.index('nk.tap(TAP_X,TAP_Y)'))
        self.assertLess(text.index('point("SWIPE_END"'),
                        text.index('nk.tap(TAP_X,TAP_Y)'))

    def test_ui_patch_fixture_and_no_overwrite(self):
        compile(PATCH.read_text(),str(PATCH),"exec")
        with tempfile.TemporaryDirectory() as tmp:
            ui=Path(tmp)/"zxtouch/zxtouch/Settings/SettingsPageViewController.m"
            ui.parent.mkdir(parents=True)
            ui.write_text('''
#pragma mark - Library
@implementation NKLuaLibraryViewController
- (void)viewDidLoad {
    NSString *sampleName=@"test_inputtext_notes_v2.lua";
    NSString *samplePath=NKPath(sampleName);
    NSFileManager *sampleFS=[NSFileManager defaultManager];
    if (![sampleFS fileExistsAtPath:samplePath]) {
      // Retained v0.7.14 Notes template
    }
}
- (void)tableView:(UITableView*)tv didSelectRowAtIndexPath:(NSIndexPath*)ip{(void)tv;if(ip.row==self.scripts.count+1){[self.navigationController pushViewController:[[NKLuaEditorViewController alloc]initWithScriptName:@"test_inputtext_notes_v2.lua"] animated:YES];return;} }
@end
#pragma mark - Editor
''')
            r=subprocess.run(["python3",str(PATCH),tmp],capture_output=True,text=True)
            self.assertEqual(r.returncode,0,r.stdout+r.stderr)
            output=ui.read_text()
            for part in ('nkShowSamples','test_core_readonly.lua',
                         'test_vision_oneframe.lua','test_gestures_optin.lua',
                         'test_inputtext_notes_v2.lua','com.apple.mobilesafari',
                         'copyItemAtPath:source toPath:testPath',
                         'if (![sampleFS fileExistsAtPath:testPath])',
                         'if (bundle.length && !NKTargetForScript(testName))'):
                self.assertIn(part,output)
            self.assertIn('if(ip.row==self.scripts.count+1){[self nkShowSamples];return;}',output)
            self.assertEqual(output.count('nkShowSamples {'),1)
            self.assertNotIn('NKSaveTarget(testName,@"com.apple.mobilenotes"',output)

    def test_prepare_deploys_bundle_and_retains_version(self):
        s=PREP.read_text()
        self.assertIn("prepare-v0714-notes-screenfix.sh",s)
        for name in ("test_core_readonly.lua","test_vision_oneframe.lua",
                     "test_gestures_optin.lua","test_inputtext_notes_v2.lua"):
            self.assertIn(name,s)
        self.assertIn("Version: 0.7.15",s)
        self.assertIn("apply-v0715-selftest-suite.py",s)

    def test_expensive_build_only_on_ready_marker(self):
        text=WORKFLOW.read_text()
        self.assertIn("workflow_dispatch:",text)
        self.assertIn("v0.7.15-lua-selftest-suite",text)
        self.assertIn("- release/v0715-build-ready.txt",text)
        self.assertNotIn("- lua/nktouch.lua",text.split("jobs:",1)[0])
        self.assertIn("prepare-v0715-lua-selftest.sh upstream",text)
        self.assertIn("tests/test_v0715_lua_selftest.py",text)
        self.assertIn("publish-v0715-sileo.sh",text)
        self.assertIn("needs: build-rootless",text)

    @unittest.skipUnless(shutil.which("lua"),"host Lua not installed")
    def test_gesture_default_sends_no_touch(self):
        harness=r'''
package.preload.nktouch_v7=function()
 return {tap=function()error("unsafe tap")end,
         hold=function()error("unsafe hold")end,
         swipe=function()error("unsafe swipe")end}
end
dofile(arg[1])
print("SAFE_GESTURE_DEFAULT_OK")
'''
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/"test.lua";p.write_text(harness)
            r=subprocess.run(["lua",str(p),str(GESTURE)],capture_output=True,text=True,timeout=10)
            self.assertEqual(r.returncode,0,r.stdout+r.stderr)
            self.assertIn("status=SKIP",r.stdout)
            self.assertIn("SAFE_GESTURE_DEFAULT_OK",r.stdout)

    @unittest.skipUnless(shutil.which("lua"),"host Lua not installed")
    def test_gestures_dispatch_once_after_validation(self):
        source=GESTURE.read_text()
        replacements={
            "ENABLE_GESTURES=false":"ENABLE_GESTURES=true",
            'EXPECTED_BUNDLE=""':'EXPECTED_BUNDLE="com.apple.mobilenotes"',
            "TAP_X,TAP_Y=nil,nil":"TAP_X,TAP_Y=120,250",
            "HOLD_X,HOLD_Y=nil,nil":"HOLD_X,HOLD_Y=180,350",
            "SWIPE_X1,SWIPE_Y1=nil,nil":"SWIPE_X1,SWIPE_Y1=150,450",
            "SWIPE_X2,SWIPE_Y2=nil,nil":"SWIPE_X2,SWIPE_Y2=300,500",
        }
        for old,new in replacements.items():
            self.assertIn(old,source)
            source=source.replace(old,new,1)
        harness=r'''
local events={}
local mock={}
mock.screen=function()return "750.000000;;1334.000000"end
mock.foreground=function()return "com.apple.mobilenotes"end
mock.waitApp=function(app,timeout,poll)
 assert(app=="com.apple.mobilenotes" and timeout==2000 and poll==200)
 events[#events+1]="wait"
 return true
end
mock.tap=function(x,y)
 assert(x==120 and y==250)
 events[#events+1]="tap";return true
end
mock.hold=function(x,y,ms)
 assert(x==180 and y==350 and ms==400)
 events[#events+1]="hold";return true
end
mock.swipe=function(x,y,x2,y2,ms)
 assert(x==150 and y==450 and x2==300 and y2==500 and ms==600)
 events[#events+1]="swipe";return true
end
mock.sleep=function()return true end
package.preload.nktouch_v7=function()return mock end
dofile(arg[1])
assert(table.concat(events,",")=="wait,tap,hold,swipe",table.concat(events,","))
print("GESTURES_ONCE_OK")
'''
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/"harness.lua";p.write_text(harness)
            script=Path(d)/"optin.lua";script.write_text(source)
            r=subprocess.run(["lua",str(p),str(script)],capture_output=True,text=True,timeout=10)
            self.assertEqual(r.returncode,0,r.stdout+r.stderr)
            self.assertIn("GESTURES_ONCE_OK",r.stdout)
            self.assertIn("status=DISPATCHED",r.stdout)

if __name__=="__main__":
    unittest.main()
