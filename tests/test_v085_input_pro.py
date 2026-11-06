"""NKTouch v0.8.5 Input Engine Pro: versioned source + package overlay tests."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]
SRC=ROOT/"lua/nkinput_pro.lua"
STAGE=ROOT/"scripts/stage-v085-input-pro.sh"
BUILD=ROOT/".github/workflows/build-v085-input-pro.yml"
BENCH=ROOT/"examples/test_input_fast_v085.lua"
SAFE=ROOT/"examples/test_input_safe_v085.lua"

class InputEngineProTests(unittest.TestCase):
    def test_fast_path_is_native_single_dispatch_without_ocr(self):
        source=SRC.read_text()
        self.assertIn('M={VERSION="0.8.5-beta"}',source)
        for expected in ('function M.fast(', 'function M.safe(', 'function M.keyboard(',
                         'nk.inputTextV2', 'mode=mode', 'DISPATCH_UNCERTAIN',
                         'DUPLICATE_BLOCKED', 'FOCUS_PROBE_UNAVAILABLE',
                         'FOCUS_NOT_CONFIRMED', 'WRONG_APP', 'OUT_OF_BOUNDS',
                         'MAX_BYTES=8192', 'attempts=1,ocr_used=false'):
            self.assertIn(expected,source)
        for forbidden in ('nk.ocr(', 'nk.screenshot(', 'nk.paste(', 'nk.inputPassword(',
                          'nk.showKeyboard(', 'nk.openApp(', 'io.popen(', 'os.execute('):
            self.assertNotIn(forbidden,source)
        self.assertNotIn('print(s)',source)
        self.assertNotIn('print(text)',source)
        self.assertIn('verified=false',source)
        self.assertIn('focus_verified=focusVerified',source)
        self.assertIn('result~=true',source)

    def test_demos_are_off_by_default_and_use_no_ocr(self):
        for file in (BENCH,SAFE):
            src=file.read_text()
            self.assertIn('ENABLE_REAL_INPUT=false',src)
            self.assertNotIn('nk.ocr(',src)
            self.assertNotIn('print("NKTouch Fast Input thử',src)
        self.assertIn('nk.inputFast(',BENCH.read_text())
        self.assertIn('core.nowMs()',BENCH.read_text())
        self.assertIn('nk.inputSafe(',SAFE.read_text())
        self.assertIn('onceKey="demo.notes.field1"',SAFE.read_text())

    def test_source_workflow_is_artifact_only_and_pinned_to_good_083(self):
        src=BUILD.read_text()
        for expected in ('runs-on: macos-15',
                         'NK_VERSION: 0.8.5',
                         'NKTouch-v0.8.5-input-pro-rootless',
                         'bash scripts/stage-v083-ocr-perf.sh upstream',
                         'bash scripts/stage-v085-input-pro.sh upstream',
                         'lua tests/lua_v085_input_pro.lua',
                         'python3 -m unittest tests/test_v085_input_pro.py',
                         'IOMobileFramebuffer.framework/IOMobileFramebuffer.tbd',
                         'iPhoneOS16.5.sdk.tar.xz'):
            self.assertIn(expected,src)
        for forbidden in ('publish-beta-to-sileo:', 'publish-v083-sileo.sh',
                          'refs/heads/sileo-repo','runs-on: macos-14'):
            self.assertNotIn(forbidden,src)

    def test_staging_updates_exactly_one_api_menu_and_version(self):
        with tempfile.TemporaryDirectory() as dirname:
            root=Path(dirname)
            def put(rel,txt):
                path=root/rel
                path.parent.mkdir(parents=True,exist_ok=True)
                path.write_text(txt)
            put("control",'''Package: com.nk.nktouch
Version: 0.8.3
Description: NKTouch v0.8.3 OCR performance and stability experimental beta; retains validated v0.8.2 same-frame SpringBoard OCR IPC
''')
            put("layout/usr/bin/nktouchctl",'PACKAGE_VERSION="0.8.3"\n')
            put("layout/usr/share/doc/nktouch/VERSION",
                'NKTouch 0.8.3 OCR Performance and Stability Beta\n')
            put("layout/usr/share/nktouch/lua/nktestlab.lua",
                '-- NKTouch Test Lab v0.8.3-beta\nlocal M={VERSION="0.8.3-beta"}\n')
            staged=(ROOT/"lua/nktouch.lua").read_text().replace(
                'M.inputText=M.text','M.legacyInputText=M.text',1)
            staged=staged.replace('function M.inputPassword(value,options)\n',
                                  'function M.inputText(value,options)\n'
                                  '  return M.inputTextV2(value,options)\nend\n'
                                  'function M.inputPassword(value,options)\n',1)
            put("layout/usr/share/nktouch/lua/nktouch.lua",staged)
            put("layout/usr/share/nktouch/lua/nkinput_v2.lua",
                (ROOT/"lua/nkinput_v2.lua").read_text())
            put("zxtouch/zxtouch/Settings/SettingsPageViewController.m",
                'NKTouch 0.8.3 nkLabel:@"0.8.3"; -- NKTouch Test Lab v0.8.3-beta\n'
                '@{@"file":@"test_gestures_optin.lua"}\n'
                '@{@"title":@"Tap / Hold / Swipe • tuỳ chọn", @"file":@"test_gestures_optin.lua"}\n')
            run=subprocess.run(['bash',str(STAGE),str(root)],cwd=ROOT,
                               text=True,capture_output=True)
            self.assertEqual(run.returncode,0,run.stdout+run.stderr)
            staged=(root/"layout/usr/share/nktouch/lua/nktouch.lua").read_text()
            self.assertIn('function M.inputFast(value,options)',staged)
            self.assertIn('function M.inputSafe(value,options)',staged)
            self.assertIn('function M.inputKeyboard(value,options)',staged)
            self.assertIn('return M.inputTextV2(value,options)',staged)
            self.assertIn('M.legacyInputText=M.text',staged)
            self.assertIn('Version: 0.8.5',(root/"control").read_text())
            self.assertIn('0.8.5-beta',(root/"layout/usr/share/nktouch/lua/nktestlab.lua").read_text())
            self.assertTrue((root/"layout/usr/share/nktouch/lua/nkinput_pro.lua").is_file())
            ui=(root/"zxtouch/zxtouch/Settings/SettingsPageViewController.m").read_text()
            self.assertIn('Input Pro • Safe',ui)
            self.assertIn('test_input_fast_v085.lua',ui)
            again=subprocess.run(['bash',str(STAGE),str(root)],cwd=ROOT,
                                 capture_output=True,text=True)
            self.assertNotEqual(again.returncode,0,"must reject repeat version overlay")

    @unittest.skipUnless(shutil.which("lua5.4") or shutil.which("lua"),"Lua 5.4 required")
    def test_lua_input_security_contract(self):
        binary=shutil.which("lua5.4") or shutil.which("lua")
        out=subprocess.run([binary,'tests/lua_v085_input_pro.lua'],
                           cwd=ROOT,text=True,capture_output=True,timeout=30)
        self.assertEqual(out.returncode,0,out.stdout+out.stderr)
        self.assertIn("[NKINPUT_PRO][HOST] PASS",out.stdout)

if __name__=="__main__":
    unittest.main()
