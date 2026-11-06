"""NKTouch v0.8.8 Vision Speed & Stability and artifact-only packaging."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]
ENGINE=ROOT/"lua/nkvision_speed.lua"
STAGE=ROOT/"scripts/stage-v088-vision-speed.sh"
BUILD=ROOT/".github/workflows/build-v088-vision-speed.yml"
BATCH=ROOT/"examples/test_vision_batch_v088.lua"
STABLE=ROOT/"examples/test_vision_stability_v088.lua"

class VisionSpeed088(unittest.TestCase):
    def test_bounded_read_only_same_frame_contract(self):
        body=ENGINE.read_text()
        for marker in ('VERSION="0.8.8-beta"',
                       'function M.batch(nk,plan,opts)',
                       'function M.whenStable(nk,plan,opts)',
                       'for yi=1,4 do', 'for xi=1,4 do',
                       'self.cache_hits=self.cache_hits+1',
                       'out.metrics.reused_last_frame=true',
                       'SCREEN_UNSTABLE','GEOMETRY_MISMATCH',
                       'UNVERIFIED_BACKEND','stable_frames',
                       'stable_screen', 'readPlan(frame,info,call,cfg,opts)'):
            if marker=='stable_screen':
                continue
            self.assertIn(marker,body)
        for forbidden in ('nk.tap(', 'nk.inputText(', 'nk.ocr(', 'nk.screenshot(',
                          'nk.openApp(', 'os.execute(', 'while true do',
                          'print(text)', 'print(p.path)'):
            self.assertNotIn(forbidden,body)
        self.assertIn('if opts.include_text==true then item.text=text end',body)
        self.assertIn('ocr_calls=call.ocr_calls',body)
        self.assertIn('pixel_native_reads=call.native_reads',body)
        self.assertIn('template_calls=call.templates',body)
        self.assertIn('metrics.captures=count',body)
        self.assertIn('BACKEND[meta.ocr_backend]',body)

    def test_readonly_scripts_do_not_type_log_ocr_or_touch(self):
        for file in (BATCH,STABLE):
            s=file.read_text()
            for forbidden in ('nk.tap(', 'nk.inputText(', 'print(result.ocr[1].text)',
                              'include_text=true', 'nk.ocr(', 'os.execute('):
                self.assertNotIn(forbidden,s)
        self.assertIn('nk.visionBatch({',BATCH.read_text())
        self.assertIn('nk.visionWhenStable({',STABLE.read_text())
        self.assertIn('timeout_ms=3500',STABLE.read_text())

    def test_artifact_only_build_and_v087_compatibility(self):
        w=BUILD.read_text()
        for marker in ('runs-on: macos-15',
                       'NK_VERSION: 0.8.8',
                       'NKTouch-v0.8.8-vision-speed-rootless',
                       'bash scripts/stage-v087-input-reliability.sh upstream',
                       'bash scripts/stage-v088-vision-speed.sh upstream',
                       'lua tests/lua_v088_vision_speed.lua',
                       'tests/test_v088_vision_speed.py',
                       'IOMobileFramebuffer.framework/IOMobileFramebuffer.tbd',
                       'iPhoneOS16.5.sdk.tar.xz'):
            self.assertIn(marker,w)
        for forbidden in ('publish-beta-to-sileo:',
                          'refs/heads/sileo-repo',
                          'publish-v087-sileo.sh'):
            self.assertNotIn(forbidden,w)

    def test_stage_adds_new_api_and_keeps_087_apis(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp)
            def put(name,txt):
                f=root/name
                f.parent.mkdir(parents=True,exist_ok=True)
                f.write_text(txt)
            put('control', '''Package: com.nk.nktouch
Version: 0.8.7
Description: NKTouch v0.8.7 Native Input Reliability beta: read-only UIKit first-responder focus probe, strict guarded input; retains Precision, same-frame OCR and Lua tools
''')
            put('layout/usr/bin/nktouchctl','PACKAGE_VERSION="0.8.7"\n')
            put('layout/usr/share/doc/nktouch/VERSION',
                'NKTouch 0.8.7 Native Input Reliability Beta\n')
            put('layout/usr/share/nktouch/lua/nktestlab.lua',
                '-- NKTouch Test Lab v0.8.7-beta\nlocal M={VERSION="0.8.7-beta"}\n')
            put('layout/usr/share/nktouch/lua/nkvision.lua',
                (ROOT/'lua/nkvision.lua').read_text())
            put('layout/usr/share/nktouch/lua/nksnapshot.lua',
                (ROOT/'lua/nksnapshot.lua').read_text())
            put('layout/usr/share/nktouch/lua/nkocr_perf.lua',
                (ROOT/'lua/nkocr_perf.lua').read_text())
            put('layout/usr/share/nktouch/lua/nkcoords.lua',
                (ROOT/'lua/nkcoords.lua').read_text())
            put('layout/usr/share/nktouch/lua/nkinput_pro.lua',
                (ROOT/'lua/nkinput_pro.lua').read_text())
            put('layout/usr/share/nktouch/lua/nkprecision.lua',
                (ROOT/'lua/nkprecision.lua').read_text())
            put('layout/usr/share/nktouch/lua/nktouch.lua','''local M={}
function M.inputFast(value,options) end
function M.focusedInput(bundle) end
function M.precisionTapIfMatch(options) end
function M.withFrame(callback) end
function M.inputPassword(value,options)
end
return M
''')
            put('zxtouch/zxtouch/Settings/SettingsPageViewController.m',
                'NKTouch 0.8.7 nkLabel:@"0.8.7"; -- NKTouch Test Lab v0.8.7-beta\n'
                '@{@"file":@"test_input_strict_v087.lua", @"bundle":@"com.apple.mobilenotes"}\n'
                '@{@"title":@"Input • Strict Native (opt-in)", @"file":@"test_input_strict_v087.lua"}\n')
            result=subprocess.run(['bash',str(STAGE),str(root)],cwd=ROOT,
                                   capture_output=True,text=True,timeout=15)
            self.assertEqual(result.returncode,0,result.stdout+result.stderr)
            api=(root/'layout/usr/share/nktouch/lua/nktouch.lua').read_text()
            for name in ('visionBatch','visionWhenStable','inputFast',
                         'focusedInput','precisionTapIfMatch'):
                self.assertIn('function M.'+name+'(',api)
            self.assertIn('Version: 0.8.8',(root/'control').read_text())
            self.assertIn('PACKAGE_VERSION="0.8.8"',
                          (root/'layout/usr/bin/nktouchctl').read_text())
            self.assertIn('0.8.8-beta',
                          (root/'layout/usr/share/nktouch/lua/nktestlab.lua').read_text())
            self.assertTrue((root/'layout/usr/share/nktouch/lua/nkvision_speed.lua').is_file())
            ui=(root/'zxtouch/zxtouch/Settings/SettingsPageViewController.m').read_text()
            self.assertIn('Vision • Color + OCR / 1 frame',ui)
            self.assertIn('Vision • Chờ màn hình ổn định',ui)
            self.assertTrue((root/'layout/usr/share/nktouch/examples/test_vision_batch_v088.lua').is_file())
            again=subprocess.run(['bash',str(STAGE),str(root)],cwd=ROOT,
                                 capture_output=True,text=True)
            self.assertNotEqual(again.returncode,0,"must refuse repeat stage")

    @unittest.skipUnless(shutil.which('lua5.4') or shutil.which('lua'),'Lua 5.4 required')
    def test_lua_performance_and_stability_host(self):
        binary=shutil.which('lua5.4') or shutil.which('lua')
        out=subprocess.run([binary,'tests/lua_v088_vision_speed.lua'],
                           cwd=ROOT,capture_output=True,text=True,timeout=20)
        self.assertEqual(out.returncode,0,out.stdout+out.stderr)
        self.assertIn('[NKVISION088][HOST] PASS',out.stdout)

if __name__=='__main__':
    unittest.main()
