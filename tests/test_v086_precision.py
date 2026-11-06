"""NKTouch v0.8.6: one-frame Touch/Color Precision and rootless release guards."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]
MODULE=ROOT/"lua/nkprecision.lua"
STAGE085=ROOT/"scripts/stage-v085-input-pro.sh"
STAGE086=ROOT/"scripts/stage-v086-precision.sh"
BUILD=ROOT/".github/workflows/build-v086-precision.yml"
READONLY=ROOT/"examples/test_precision_colors_v086.lua"
TOUCH=ROOT/"examples/test_precision_touch_v086.lua"

class Precision086(unittest.TestCase):
    def test_module_contract(self):
        s=MODULE.read_text()
        for marker in ('VERSION="0.8.6-beta"',
                       'function M.inspect(nk,opts)',
                       'function M.find(nk,opts)',
                       'function M.tapIfMatch(nk,opts)',
                       'function M.tapIfFound(nk,opts)',
                       'geometry_verified=true',
                       'DISPATCHED_UNVERIFIED',
                       'GEOMETRY_MISMATCH',
                       'COLOR_MISMATCH',
                       'DISPATCH_UNCERTAIN',
                       'not match.matches',
                       'nk.tap,x,y'):
            if marker=='not match.matches':
                continue
            self.assertIn(marker,s)
        self.assertIn('not match.matches',s)
        self.assertIn('type(frame)~="userdata"',s)
        self.assertIn('require("nkcoords").inspectFrame',s)
        self.assertIn('type(frame.findColor)~="function"',s)
        self.assertIn('opts.enabled~=true or opts.confirmed~=true',s)
        for forbidden in ('nk.ocr(', 'nk.screenshot(', 'nk.inputText(',
                          'nk.paste(', 'nk.openApp(', 'os.execute(',
                          'nk.waitColor(', 'while true do'):
            self.assertNotIn(forbidden,s)

    def test_samples_are_safe_by_default(self):
        r=READONLY.read_text()
        t=TOUCH.read_text()
        self.assertIn('nk.precisionInspect({points=points})',r)
        self.assertNotIn('nk.tap(',r)
        self.assertIn('ENABLE_REAL_TAP=false',t)
        self.assertIn('enabled=true,confirmed=true',t)
        self.assertIn('nk.precisionTapIfMatch({',t)
        self.assertNotIn('nk.ocr(',r+t)

    def test_build_is_artifact_only(self):
        w=BUILD.read_text()
        for expected in ('runs-on: macos-15','NK_VERSION: 0.8.6',
                         'NKTouch-v0.8.6-precision-rootless',
                         'bash scripts/stage-v085-input-pro.sh upstream',
                         'bash scripts/stage-v086-precision.sh upstream',
                         'lua tests/lua_v086_precision.lua',
                         'python3 -m unittest tests/test_v086_precision.py',
                         'IOMobileFramebuffer.framework/IOMobileFramebuffer.tbd',
                         'iPhoneOS16.5.sdk.tar.xz'):
            self.assertIn(expected,w)
        for forbidden in ('publish-beta-to-sileo:', 'refs/heads/sileo-repo',
                          'publish-v085-sileo.sh', 'runs-on: macos-14'):
            self.assertNotIn(forbidden,w)

    def test_stage_v085_to_v086_compatibility(self):
        with tempfile.TemporaryDirectory() as dirname:
            root=Path(dirname)
            def put(path,body):
                file=root/path
                file.parent.mkdir(parents=True,exist_ok=True)
                file.write_text(body)
            put('control', '''Package: com.nk.nktouch
Version: 0.8.3
Description: NKTouch v0.8.3 OCR performance and stability experimental beta; retains validated v0.8.2 same-frame SpringBoard OCR IPC
''')
            put('layout/usr/bin/nktouchctl','PACKAGE_VERSION="0.8.3"\n')
            put('layout/usr/share/doc/nktouch/VERSION',
                'NKTouch 0.8.3 OCR Performance and Stability Beta\n')
            put('layout/usr/share/nktouch/lua/nktestlab.lua',
                '-- NKTouch Test Lab v0.8.3-beta\nlocal M={VERSION="0.8.3-beta"}\n')
            put('layout/usr/share/nktouch/lua/nkcoords.lua',
                (ROOT/'lua/nkcoords.lua').read_text())
            base=(ROOT/'lua/nktouch.lua').read_text().replace(
                'M.inputText=M.text','M.legacyInputText=M.text',1)
            base=base.replace('function M.inputPassword(value,options)\n',
                'function M.inputText(value,options)\n'
                '  return M.inputTextV2(value,options)\nend\n'
                'function M.inputPassword(value,options)\n',1)
            put('layout/usr/share/nktouch/lua/nktouch.lua',base)
            put('layout/usr/share/nktouch/lua/nkinput_v2.lua',
                (ROOT/'lua/nkinput_v2.lua').read_text())
            put('zxtouch/zxtouch/Settings/SettingsPageViewController.m',
                'NKTouch 0.8.3 nkLabel:@"0.8.3"; -- NKTouch Test Lab v0.8.3-beta\n'
                '@{@"file":@"test_gestures_optin.lua"}\n'
                '@{@"title":@"Tap / Hold / Swipe • tuỳ chọn", @"file":@"test_gestures_optin.lua"}\n')
            for script in (STAGE085,STAGE086):
                run=subprocess.run(['bash',str(script),str(root)],cwd=ROOT,
                                   capture_output=True,text=True,timeout=20)
                self.assertEqual(run.returncode,0,run.stdout+run.stderr)
            source=(root/'layout/usr/share/nktouch/lua/nktouch.lua').read_text()
            for method in ('precisionInspect','precisionFind','precisionTapIfMatch',
                           'precisionTapIfFound','inputFast','inputSafe','inputKeyboard'):
                self.assertIn('function M.'+method+'(',source)
            self.assertIn('return M.inputTextV2(value,options)',source)
            self.assertIn('Version: 0.8.6',(root/'control').read_text())
            self.assertIn('PACKAGE_VERSION="0.8.6"',
                          (root/'layout/usr/bin/nktouchctl').read_text())
            self.assertIn('0.8.6-beta',
                          (root/'layout/usr/share/nktouch/lua/nktestlab.lua').read_text())
            self.assertTrue((root/'layout/usr/share/nktouch/lua/nkprecision.lua').is_file())
            self.assertTrue((root/'layout/usr/share/nktouch/lua/nkinput_pro.lua').is_file())
            ui=(root/'zxtouch/zxtouch/Settings/SettingsPageViewController.m').read_text()
            self.assertIn('Color • Nhiều điểm / 1 frame',ui)
            self.assertIn('Touch • Chạm khi khớp màu',ui)
            again=subprocess.run(['bash',str(STAGE086),str(root)],cwd=ROOT,
                                 capture_output=True,text=True)
            self.assertNotEqual(again.returncode,0)

    @unittest.skipUnless(shutil.which('lua5.4') or shutil.which('lua'),'requires Lua')
    def test_lua_mock(self):
        binary=shutil.which('lua5.4') or shutil.which('lua')
        p=subprocess.run([binary,'tests/lua_v086_precision.lua'],cwd=ROOT,
                         text=True,capture_output=True,timeout=30)
        self.assertEqual(p.returncode,0,p.stdout+p.stderr)
        self.assertIn('[NKPRECISION][HOST] PASS',p.stdout)

if __name__=='__main__': unittest.main()
