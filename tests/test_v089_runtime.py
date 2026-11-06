"""NKTouch v0.8.9 Runtime Reliability: separate cooperative Lua and hard nktask contracts."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]
MODULE=ROOT/"lua/nkruntime_guard.lua"
STAGE=ROOT/"scripts/stage-v089-runtime.sh"
BUILD=ROOT/".github/workflows/build-v089-runtime.yml"
READONLY=ROOT/"examples/test_runtime_guard_readonly_v089.lua"
WRITE=ROOT/"examples/test_runtime_guard_write_optin_v089.lua"

class Runtime089(unittest.TestCase):
    def test_cooperative_guard_has_protected_lifecycle_and_no_secrets_in_events(self):
        s=MODULE.read_text()
        for marker in ('VERSION="0.8.9-beta"',
                       'function M.create(opts)',
                       'function M.run(callback,options)',
                       'function session:checkpoint()',
                       'function session:step(kind,callback,options)',
                       'function session:sleep(ms)',
                       'function session:defer(name,callback)',
                       'function session:finish()',
                       'function session:snapshot()',
                       'DEADLINE_EXCEEDED','DUPLICATE_BLOCKED',
                       'DISPATCH_UNCERTAIN','CANCEL_UNKNOWN',
                       'CLEANUP_FAILED','STEP_LIMIT',
                       'state.keys[key]=true',
                       'state.closed=true',
                       'for i=#state.resources,1,-1 do',
                       'table.pack(pcall(callback))',
                       'math.min(100,ms-used,remaining)'):
            self.assertIn(marker,s)
        for forbidden in ('os.execute(', 'nk.tap(', 'nk.inputText(',
                          'print(text)', 'print(callback)', 'os.remove(',
                          'debug.sethook(', 'kill(', 'native restart'):
            self.assertNotIn(forbidden,s)
        self.assertIn('safeCode(code)',s)
        self.assertIn('kind="COOPERATIVE_GUARD"',s)
        self.assertIn('Native task supervisor controls hard stop/timeout',s)

    def test_samples_are_readonly_or_disabled(self):
        a=READONLY.read_text()
        b=WRITE.read_text()
        self.assertIn('nk.runtimeSession({',a)
        self.assertIn('ctx:step("read"',a)
        for prohibited in ('nk.tap(', 'nk.inputText(', 'nk.ocr(', 'os.execute('):
            self.assertNotIn(prohibited,a)
        self.assertIn('ENABLE_REAL_TAP=false',b)
        self.assertIn('onceKey="notes.test.tap1"',b)
        self.assertIn('ctx:step("write"',b)
        self.assertIn('confirmed=true',b)

    def test_artifact_only_build_preserves_existing_native_supervisor(self):
        w=BUILD.read_text()
        for marker in ('runs-on: macos-15','NK_VERSION: 0.8.10',
                       'NKTouch-v0.8.10-runtime-selftest-rootless',
                       'bash scripts/stage-v088-vision-speed.sh upstream',
                       'bash scripts/stage-v089-runtime.sh upstream',
                       'lua tests/lua_v089_runtime_guard.lua',
                       'tests/test_v089_runtime.py',
                       'IOMobileFramebuffer.framework/IOMobileFramebuffer.tbd',
                       'iPhoneOS16.5.sdk.tar.xz'):
            self.assertIn(marker,w)
        for forbidden in ('publish-beta-to-sileo:', 'refs/heads/sileo-repo',
                          'publish-v088-sileo.sh'):
            self.assertNotIn(forbidden,w)

    def test_stage_to_v089_keeps_v088_vision_input_precision(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp)
            def put(name,text):
                f=root/name
                f.parent.mkdir(parents=True,exist_ok=True)
                f.write_text(text)
            put('control','''Package: com.nk.nktouch
Version: 0.8.8
Description: NKTouch v0.8.8 Vision Speed Stability beta: one-frame Color/OCR/Image batch with cached pixels, bounded stable-screen gate; retains Native Input and Precision
''')
            put('layout/usr/bin/nktouchctl','PACKAGE_VERSION="0.8.8"\n')
            put('layout/usr/bin/nktask','supervisor binary mock')
            put('layout/usr/share/doc/nktouch/VERSION',
                'NKTouch 0.8.8 Vision Speed and Screen Stability Beta\n')
            put('layout/usr/share/nktouch/lua/nktestlab.lua',
                '-- NKTouch Test Lab v0.8.8-beta\nlocal M={VERSION="0.8.8-beta"}\n')
            for module in ('nkvision_speed','nkvision','nkinput_pro','nkprecision',
                           'nkdiagnostics','nkmemory'):
                put('layout/usr/share/nktouch/lua/'+module+'.lua',
                    (ROOT/'lua'/f'{module}.lua').read_text())
            put('layout/usr/share/nktouch/lua/nktouch.lua',
                '''local M={}
function M.visionBatch(plan,options) end
function M.visionWhenStable(plan,options) end
function M.inputSafe(value,options) end
function M.focusedInput(bundle) end
function M.precisionTapIfMatch(options) end
function M.inputPassword(value,options)
end
return M
''')
            put('zxtouch/zxtouch/Settings/SettingsPageViewController.m',
                'NKTouch 0.8.8 nkLabel:@"0.8.8"; -- NKTouch Test Lab v0.8.8-beta\n'
                '@{@"file":@"test_vision_stability_v088.lua", @"bundle":@"com.apple.mobilenotes"}\n'
                '@{@"title":@"Vision • Chờ màn hình ổn định", @"file":@"test_vision_stability_v088.lua"}\n')
            r=subprocess.run(['bash',str(STAGE),str(root)],cwd=ROOT,
                             capture_output=True,text=True,timeout=15)
            self.assertEqual(r.returncode,0,r.stdout+r.stderr)
            public=(root/'layout/usr/share/nktouch/lua/nktouch.lua').read_text()
            for name in ('runtimeSession','runGuarded','visionBatch',
                         'visionWhenStable','inputSafe','focusedInput','precisionTapIfMatch'):
                self.assertIn('function M.'+name+'(',public)
            self.assertIn('Version: 0.8.9',(root/'control').read_text())
            self.assertIn('PACKAGE_VERSION="0.8.9"',
                          (root/'layout/usr/bin/nktouchctl').read_text())
            self.assertIn('0.8.9-beta',
                          (root/'layout/usr/share/nktouch/lua/nktestlab.lua').read_text())
            self.assertTrue((root/'layout/usr/bin/nktask').is_file())
            self.assertTrue((root/'layout/usr/share/nktouch/lua/nkruntime_guard.lua').is_file())
            ui=(root/'zxtouch/zxtouch/Settings/SettingsPageViewController.m').read_text()
            self.assertIn('Runtime • Deadline / Dọn tài nguyên',ui)
            self.assertIn('Runtime • Chạm chống trùng (opt-in)',ui)
            ex=root/'layout/usr/share/nktouch/examples/test_runtime_guard_write_optin_v089.lua'
            self.assertIn('ENABLE_REAL_TAP=false',ex.read_text())
            once=subprocess.run(['bash',str(STAGE),str(root)],cwd=ROOT,
                                capture_output=True,text=True)
            self.assertNotEqual(once.returncode,0,'staging twice must be rejected')

    @unittest.skipUnless(shutil.which('lua5.4') or shutil.which('lua'),'Lua 5.4 required')
    def test_lua_mock_deadline_cancel_cleanup_and_secrets(self):
        cmd=shutil.which('lua5.4') or shutil.which('lua')
        r=subprocess.run([cmd,'tests/lua_v089_runtime_guard.lua'],cwd=ROOT,
                         capture_output=True,text=True,timeout=25)
        self.assertEqual(r.returncode,0,r.stdout+r.stderr)
        self.assertIn('[NKRUNTIME089][HOST] PASS',r.stdout)

if __name__=='__main__':
    unittest.main()
