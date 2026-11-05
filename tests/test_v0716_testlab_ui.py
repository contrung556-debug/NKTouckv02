"""Static UIKit staging checks for NKTouch Test Lab (no iOS compilation)."""
from pathlib import Path
import subprocess
import tempfile
import unittest
import json
import re
import shutil

ROOT=Path(__file__).resolve().parents[1]
PATCH=ROOT/"scripts/apply-v0716-testlab-ui.py"
VIEW=ROOT/"patches/NKTestLabUIViewController.m.inc"

class TestLabUIKit(unittest.TestCase):
    def test_appends_test_lab_to_existing_workspace(self):
        fixture='''
static BOOL NKSaveTarget(NSString *script, NSString *bundle, NSString *name);
#pragma mark - Dashboard
@implementation NKLuaWorkspaceViewController
- (void)viewDidLoad {
[stack addArrangedSubview:header];[stack addArrangedSubview:hero];[stack addArrangedSubview:r1];[stack addArrangedSubview:r2];[stack addArrangedSubview:status];
}
- (void)openWorkspace { [self.navigationController pushViewController:[[NSClassFromString(@"NKLuaLibraryViewController") alloc] init] animated:YES]; }
@end
#pragma mark - Library
- (void)nkShowSamples {
    [menu addAction:[UIAlertAction actionWithTitle:@"Huỷ" style:UIAlertActionStyleCancel handler:nil]];
}
if(ip.row==self.scripts.count+1){[self nkShowSamples];return;}
#pragma mark - Editor
'''
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/"zxtouch/zxtouch/Settings/SettingsPageViewController.m"
            p.parent.mkdir(parents=True)
            p.write_text(fixture)
            r=subprocess.run(["python3",str(PATCH),d],
                             capture_output=True,text=True)
            self.assertEqual(r.returncode,0,r.stdout+r.stderr)
            s=p.read_text()
            for key in ("NKLuaTestLabViewController","nkOpenTestLab",
                        "Test Lab • 7 nhóm","labCreateRunner","labShowReport",
                        "testlab-last.json","nktestlab_%@.lua",
                        "initWithScriptName:filename",
                        "[stack addArrangedSubview:testlab]"):
                self.assertIn(key,s)
            self.assertEqual(s.count("@interface NKLuaTestLabViewController"),1)
            self.assertLess(s.index("@implementation NKLuaTestLabViewController"),
                            s.index("#pragma mark - Editor"))
            # A duplicate injection is detected before app builds.
            duplicate=subprocess.run(["python3",str(PATCH),d],
                                     capture_output=True,text=True)
            self.assertNotEqual(duplicate.returncode,0)

    def test_safe_generated_script_contract(self):
        s=VIEW.read_text()
        self.assertIn("selected={%@}",s)
        self.assertIn("enabled=false",s)
        self.assertIn("(void)NKScripts()",s)
        self.assertIn("if ([fs fileExistsAtPath:path])",s)
        self.assertIn("NKSaveTarget(filename",s)
        self.assertIn("lab.run(opts)",s)
        self.assertIn("labRefreshSummary",s)
        self.assertIn("NSJSONSerialization",s)
        self.assertNotIn("nk.tap(",s)
        self.assertNotIn("nk.inputText(",s)


    @unittest.skipUnless(shutil.which("lua") and shutil.which("luac"),
                         "Host Lua compiler needed")
    def test_generated_editor_script_compiles_and_is_read_only(self):
        s=VIEW.read_text()
        start=s.index("NSString *script=[NSString stringWithFormat:")
        end=s.index('runID,runID,[quoted componentsJoinedByString:@","]];',start)
        body=s[start:end]
        for line in body.splitlines()[1:]:
            if line.strip().startswith('"'):
                self.fail("Objective-C adjacent generated script literals must be @\"...\"")
        strings=re.findall(r'@"((?:\\.|[^"\\])*)"',body)
        self.assertGreater(len(strings),12)
        template="".join(json.loads('"'+part+'"') for part in strings)
        self.assertEqual(template.count("%@"),3)
        script=template.replace("%@","lab_test_1234",1).replace(
            "%@","lab_test_1234",1).replace(
            "%@",'"runtime","touch","input","color","vision","network","task"',1)
        with tempfile.TemporaryDirectory() as temp:
            script_file=Path(temp)/"generated.lua"
            script_file.write_text(script)
            syntax=subprocess.run(["luac","-p",str(script_file)],
                       capture_output=True,text=True)
            self.assertEqual(syntax.returncode,0,syntax.stdout+syntax.stderr)
            harness=Path(temp)/"harness.lua"
            harness.write_text(r'''
package.preload.nktestlab=function()
 return {run=function(opts)
  assert(opts.run_id=="lab_test_1234")
  assert(#opts.selected==5)
  assert(opts.touch.enabled==false and opts.input.enabled==false)
  assert(opts.network.enabled==false)
  assert(opts.memory.loops==10)
  print("GENERATED_LUA_SAFE")
  return {fail=0}
 end}
end
dofile(arg[1])
''')
            run=subprocess.run(["lua",str(harness),str(script_file)],
                         capture_output=True,text=True,timeout=10)
            self.assertEqual(run.returncode,0,run.stdout+run.stderr)
            self.assertIn("GENERATED_LUA_SAFE",run.stdout)


if __name__=="__main__":
    unittest.main()
