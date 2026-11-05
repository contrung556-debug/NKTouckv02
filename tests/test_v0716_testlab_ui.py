"""Static UIKit staging checks for NKTouch Test Lab (no iOS compilation)."""
from pathlib import Path
import subprocess
import tempfile
import unittest

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

if __name__=="__main__":
    unittest.main()
