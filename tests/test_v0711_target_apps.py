"""NKTouch Target Apps v0.7.11 static and staging-contract tests."""
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]

class TargetAppsContract(unittest.TestCase):
    def test_patch_is_valid_python(self):
        s=ROOT.joinpath("scripts/apply-v0711-target-apps.py").read_text()
        compile(s,"apply-v0711-target-apps.py","exec")

    def test_target_is_explicit_and_per_script(self):
        s=ROOT.joinpath("scripts/apply-v0711-target-apps.py").read_text()
        self.assertIn("NKTargetAppsPath",s)
        self.assertIn("target_apps.plist",s)
        self.assertIn("NKTargetForScript(self.scriptName)",s)
        self.assertIn("NKSaveTarget(self.script",s)
        self.assertIn("NKTargetAppPickerViewController",s)
        self.assertIn('@"LSApplicationWorkspace"',s)
        self.assertIn("Bundle ID",s)

    def test_worker_first_and_safe_stop(self):
        s=ROOT.joinpath("scripts/apply-v0711-target-apps.py").read_text()
        self.assertIn('targetRun?@"/var/jb/usr/bin/nktask":NKLuaEditorTool',s)
        self.assertIn('NSString *wrapper=[w nkTargetWrapper]',s)
        self.assertIn('if(!wrapper){[w nkSelectTargetApp];return;}',s)
        self.assertIn("nk.openApp(%@)",s)
        self.assertIn("nk.waitApp(%@,8000,200)",s)
        self.assertIn("TARGET_NOT_FOREGROUND",s)
        self.assertLess(s.index("nk.waitApp(%@,8000,200)"),s.index("loadfile(%@"))
        self.assertIn("return run()",s)

    def test_prepare_retains_input_engine_v2(self):
        s=ROOT.joinpath("scripts/prepare-v0711-target-apps.sh").read_text()
        self.assertIn("prepare-v0710-input-engine-v2.sh",s)
        self.assertIn("Version: 0.7.11",s)
        self.assertIn('function M.inputTextV2',s)
        self.assertIn('function M.captureFrame()',s)

    def test_patch_smoke_fixture(self):
        fake='''static NSString *NKLuaRun(NSArray<NSString *> *arguments, int *exitCode) {
    NSUInteger argc = arguments.count + 2;
    char **argv = calloc(argc, sizeof(char *));
    argv[0] = strdup(NKLuaEditorTool.UTF8String);
    for (NSUInteger i=0;i<arguments.count;i++) argv[i+1] = strdup(arguments[i].UTF8String);
    argv[arguments.count+1] = NULL;
    int spawnCode = posix_spawn(&pid, NKLuaEditorTool.UTF8String, &a, NULL, argv, environ);
    for (NSUInteger i=0;i<arguments.count+1;i++) free(argv[i]);
}
static NSArray<NSString *> *NKScripts(void) { return @[]; }
#pragma mark - Editor
@implementation NKLuaEditorViewController
- (void)viewDidLoad {
    [super viewDidLoad];self.title=self.scriptName;self.view.backgroundColor=NKBG();
}
- (void)runTapped {
    [w command:@[@"run",w.scriptName] state:@"● Đang khởi động…" done:^(int rc,NSString *ro){}];
}
@end
'''
        with tempfile.TemporaryDirectory() as t:
            p=Path(t)/"zxtouch/zxtouch/Settings/SettingsPageViewController.m"
            p.parent.mkdir(parents=True)
            p.write_text(fake)
            result=subprocess.run(["python3",str(ROOT/"scripts/apply-v0711-target-apps.py"),t],capture_output=True,text=True)
            self.assertEqual(result.returncode,0,result.stderr)
            changed=p.read_text()
            self.assertIn("target-run",changed)
            self.assertIn("TARGET_NOT_FOREGROUND",changed)
            self.assertIn('NSString *wrapper=[w nkTargetWrapper]',changed)
            self.assertIn("NKTargetAppPickerViewController",changed)
            self.assertIn("BOOL targetRun=arguments.count==2",changed)
            self.assertIn("for (NSUInteger i=0;i<effective.count;i++)",changed)

if __name__=="__main__":
    unittest.main()
