"""NKTouch 0.7.13 built-in Notes inputText example smoke tests."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]
PATCH=ROOT/"scripts/apply-v0713-notes-input-selftest.py"
SAMPLE=ROOT/"examples/test_inputtext_notes.lua"

class NotesInputSelfTest(unittest.TestCase):
    def test_example_contract(self):
        content=SAMPLE.read_text()
        for part in ('com.apple.mobilenotes','function testInputTextNotes()',
                     'nk.openApp(NOTES_ID)','nk.waitApp(NOTES_ID, 10000, 250)',
                     'nk.tap(createX, createY)','nk.tap(bodyX, bodyY)',
                     'nk.inputText(TEST_TEXT)','WRONG_APP',
                     'UNVERIFIED','NKINPUT'):
            self.assertIn(part,content)
        self.assertLess(content.index('nk.waitApp(NOTES_ID, 10000, 250)'),
                        content.index('nk.tap(createX, createY)'))
        self.assertLess(content.index('nk.tap(bodyX, bodyY)'),
                        content.index('nk.inputText(TEST_TEXT)'))

    def test_ui_install_and_samples_route(self):
        compile(PATCH.read_text(),str(PATCH),"exec")
        with tempfile.TemporaryDirectory() as d:
            ui=Path(d)/"zxtouch/zxtouch/Settings/SettingsPageViewController.m"
            ui.parent.mkdir(parents=True)
            ui.write_text('''#pragma mark - Library
@implementation NKLuaLibraryViewController
- (void)viewDidLoad {
    if(NKScripts().count==0)[NKStarter() writeToFile:NKPath(@"main.lua") atomically:YES encoding:NSUTF8StringEncoding error:nil];
}
- (void)tableView:(UITableView*)tv didSelectRowAtIndexPath:(NSIndexPath*)ip{(void)tv;if(ip.row<self.scripts.count){[self.navigationController pushViewController:[[NKLuaEditorViewController alloc]initWithScriptName:self.scripts[ip.row]] animated:YES];}else if(ip.row==self.scripts.count){[self.navigationController pushViewController:[[NSClassFromString(@"NKLuaToolsViewController") alloc]init] animated:YES];}}
@end
#pragma mark - Editor
static BOOL NKSaveTarget(NSString *s, NSString *b, NSString *n){return YES;}
''')
            r=subprocess.run(["python3",str(PATCH),d],capture_output=True,text=True)
            self.assertEqual(r.returncode,0,r.stderr)
            output=ui.read_text()
            for key in ('static BOOL NKSaveTarget(NSString *script, NSString *bundle, NSString *name);',
                        'test_inputtext_notes.lua','/var/jb/usr/share/nktouch/examples/',
                        'NKTargetForScript(sampleName)',
                        'NKSaveTarget(sampleName,@"com.apple.mobilenotes",@"Ghi chú")',
                        'initWithScriptName:@"test_inputtext_notes.lua"'):
                self.assertIn(key,output)
            self.assertLess(output.index('static BOOL NKSaveTarget(NSString *script,'),
                            output.index('@implementation NKLuaLibraryViewController'))

    def test_staging_contract(self):
        stage=(ROOT/"scripts/prepare-v0713-notes-input-selftest.sh").read_text()
        for key in ('prepare-v0712-inputtext-fix.sh',
                    'examples/test_inputtext_notes.lua',
                    'apply-v0713-notes-input-selftest.py',
                    'Version: 0.7.13','nk.inputText(TEST_TEXT)'):
            self.assertIn(key,stage)

    @unittest.skipUnless(shutil.which("lua"), "host Lua unavailable")
    def test_lua_mock_happy_path_and_no_duplicate_input(self):
        harness=r'''
local events={}
local mock={}
local active="com.apple.springboard"
mock.screen=function()return "390;;844"end
mock.foreground=function()return active end
mock.openApp=function(bundle)table.insert(events,"open");active=bundle;return true end
mock.waitApp=function(bundle,ms,interval)table.insert(events,"wait");return active==bundle end
mock.sleep=function(ms)table.insert(events,"sleep");return true end
mock.tap=function(x,y)assert(x>0 and y>0);table.insert(events,"tap");return true end
mock.inputText=function(text)
 assert(text=="NKTouch InputText Test 12345")
 table.insert(events,"input")
 return true,{sent=true,status="dispatched"}
end
mock.ocr=function()return "NKTouch InputText Test 12345" end
package.preload.nktouch_v7=function()return mock end
dofile(arg[1])
local summary=table.concat(events,",")
assert(summary=="open,wait,sleep,tap,sleep,tap,sleep,input,sleep",summary)
print("NOTES_SELFTEST_MOCK_PASS")
'''
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/"harness.lua";p.write_text(harness)
            r=subprocess.run(["lua",str(p),str(SAMPLE)],capture_output=True,text=True,timeout=10)
            self.assertEqual(r.returncode,0,r.stdout+r.stderr)
            self.assertIn("VERIFIED_BY_OCR",r.stdout)
            self.assertIn("NOTES_SELFTEST_MOCK_PASS",r.stdout)

    @unittest.skipUnless(shutil.which("lua"), "host Lua unavailable")
    def test_lua_wait_failure_has_no_tap_or_input(self):
        harness=r'''
local mock={}
mock.screen=function()return "390;;844"end
mock.foreground=function()return "com.apple.springboard"end
mock.openApp=function()return true end
mock.waitApp=function()return nil,"timeout","TIMEOUT"end
mock.sleep=function()return true end
mock.tap=function()error("tap must not occur")end
mock.inputText=function()error("input must not occur")end
package.preload.nktouch_v7=function()return mock end
local ok,err=pcall(dofile,arg[1])
assert(not ok and tostring(err):find("WAIT_APP",1,true))
print("NOTES_SELFTEST_FAIL_CLOSED_PASS")
'''
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/"harness.lua";p.write_text(harness)
            r=subprocess.run(["lua",str(p),str(SAMPLE)],capture_output=True,text=True,timeout=10)
            self.assertEqual(r.returncode,0,r.stdout+r.stderr)
            self.assertIn("NOTES_SELFTEST_FAIL_CLOSED_PASS",r.stdout)

if __name__=="__main__":
    unittest.main()
