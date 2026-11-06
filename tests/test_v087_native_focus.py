"""v0.8.7 Native UIKit Focus: fail closed, preserve v0.8.6 / v0.8.5."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]
PATCH=ROOT/"scripts/apply-v087-focus-probe.py"
STAGE=ROOT/"scripts/stage-v087-input-reliability.sh"
C=ROOT/"runtime/nkcore.c"
LIB=ROOT/"lua/nkinput_pro.lua"
BUILD=ROOT/".github/workflows/build-v087-native-input.yml"

class NativeFocus087(unittest.TestCase):
    def test_readonly_native_query_protocol(self):
        code=C.read_text()
        for marker in ('static int l_focused_input(', 'query overflow',
                       'request_task(TASK_TEXT,body,reply',
                       'strcmp(answer,"1")', 'strcmp(answer,"0")',
                       '{"focusedInput", l_focused_input}'):
            self.assertIn(marker,code)
        self.assertIn('"10;;%s"',code)
        # Focus probe may not mutate text; inputTextV2 remains a separate API.
        focus=code.split('static int l_focused_input(',1)[1].split('static int l_text(',1)[0]
        self.assertNotIn('l_input_text_v2(',focus)
        self.assertNotIn('text_action(',focus)
        self.assertNotIn('sleep_us(',focus)

    def test_pinned_native_hook_roundtrip_and_fail_closed_timeout(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp)
            (root/'pccontrol').mkdir()
            (root/'appdelegate').mkdir()
            (root/'pccontrol/UIKeyboard.xm').write_text(
                '#include "UIKeyboard.h"\n'
                '#import <UIKit/UIKit.h>\n'
                '#import <Foundation/NSDistributedNotificationCenter.h>\n'
                '#define TASK_GET_TEXT_FROM_CLIPBOARD 6\n'
                'NSString* inputTextFromRawData(UInt8 *eventData, NSError **error)\n'
                '{\n'
                ' NSArray *data=@[];\n'
                ' int taskType=8;\n'
                '    // Forward to appdelegate tweak injected in the frontmost app.\n'
                ' return @"";\n}\n')
            (root/'appdelegate/UIKeyboard.xm').write_text(
                '#import <UIKit/UIKit.h>\n'
                '#import <Foundation/NSDistributedNotificationCenter.h>\n'
                'static UIView *NKInputV2FocusedView(UIView *view, NSUInteger depth) {\n'
                ' if (!view) return nil; return view;\n}\n'
                '%hook UIKeyboardImpl\n'
                ' - (void)handleKeyboardNotification:(NSNotification *)notification {\n'
                ' NSDictionary *data=notification.userInfo;\n'
                ' int taskId=[data[@"task_id"] intValue];\n'
                '        if (taskId == INSERT_TEXT && [data[@"nk_input_v2"] boolValue]) {\n'
                ' }\n'
                ' else if (taskId == INSERT_TEXT) { }\n'
                ' }\n%end\n')
            p=subprocess.run(['python3',str(PATCH),str(root)],cwd=ROOT,
                             capture_output=True,text=True,timeout=20)
            self.assertEqual(p.returncode,0,p.stdout+p.stderr)
            sender=(root/'pccontrol/UIKeyboard.xm').read_text()
            receiver=(root/'appdelegate/UIKeyboard.xm').read_text()
            for token in ('NKInputFocusProbeWaiter',
                          'dispatch_semaphore_wait(signal',
                          '700*NSEC_PER_MSEC',
                          'FOCUS_PROBE_TIMEOUT',
                          'FOCUS_UNSAFE_THREAD',
                          '@"nk_focus_request_id"',
                          '@"nk_focus_bundle"',
                          'deliverImmediately:NO'):
                self.assertIn(token,sender)
            for token in ('NKInputV87RespondToFocusProbe',
                          '[focused respondsToSelector:@selector(insertText:)]',
                          'NKInputV2FocusedView(window,0)',
                          'window.isKeyWindow',
                          'UISceneActivationStateForegroundActive',
                          '@"nk_focus_ready"',
                          '@"com.nk.nktouch.input.focus.reply"'):
                self.assertIn(token,receiver)
            self.assertIn('else if (taskId == INSERT_TEXT && [data[@"nk_input_v2"] boolValue])',receiver)
            self.assertNotIn('insertText:content',receiver.split('NKInputV87RespondToFocusProbe(',1)[1].split('%hook',1)[0])
            twice=subprocess.run(['python3',str(PATCH),str(root)],cwd=ROOT,
                                 capture_output=True,text=True)
            self.assertNotEqual(twice.returncode,0,"native hook patch should refuse double injection")

    def test_stage_086_to_087_pins_and_keeps_existing_paths(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp)
            def put(rel,text):
                f=root/rel
                f.parent.mkdir(parents=True,exist_ok=True)
                f.write_text(text)
            put('control','''Package: com.nk.nktouch
Version: 0.8.6
Description: NKTouch v0.8.6 Touch Color Precision beta: same-frame multi-point RGB guards, validated pixel geometry, opt-in guarded touch; retains Native Input Pro and OCR diagnostics
''')
            put('layout/usr/bin/nktouchctl','PACKAGE_VERSION="0.8.6"\n')
            put('layout/usr/share/doc/nktouch/VERSION',
                'NKTouch 0.8.6 Touch Color Precision Beta\n')
            put('layout/usr/share/nktouch/lua/nktestlab.lua',
                '-- NKTouch Test Lab v0.8.6-beta\nlocal M={VERSION="0.8.6-beta"}\n')
            put('layout/usr/share/nktouch/lua/nkinput_pro.lua',LIB.read_text())
            put('layout/usr/share/nktouch/lua/nkprecision.lua',
                (ROOT/'lua/nkprecision.lua').read_text())
            put('layout/usr/share/nktouch/lua/nktouch.lua',
                '''local M={}
function M.inputSafe(value,options) end
function M.precisionTapIfMatch(options) end
function M.inputPassword(value,options)
end
return M
''')
            put('zxtouch/zxtouch/Settings/SettingsPageViewController.m',
                'NKTouch 0.8.6 nkLabel:@"0.8.6"; -- NKTouch Test Lab v0.8.6-beta\n'
                '@{@"file":@"test_precision_touch_v086.lua", @"bundle":@"com.apple.mobilenotes"}\n'
                '@{@"title":@"Touch • Chạm khi khớp màu", @"file":@"test_precision_touch_v086.lua"}\n')
            put('pccontrol/UIKeyboard.xm',
                'NSString* inputTextFromRawData(UInt8 *eventData, NSError **error)\n'
                '{\n NSArray *data=@[]; int taskType=8;\n'
                '    // Forward to appdelegate tweak injected in the frontmost app.\n'
                ' return @"";\n}\n')
            put('appdelegate/UIKeyboard.xm',
                'static UIView *NKInputV2FocusedView(UIView *view, NSUInteger depth) {return view;}\n'
                '%hook UIKeyboardImpl\n'
                '- (void)handleKeyboardNotification:(NSNotification *)notification {\n'
                ' NSDictionary *data=notification.userInfo;\n'
                ' int taskId=[data[@"task_id"] intValue];\n'
                '        if (taskId == INSERT_TEXT && [data[@"nk_input_v2"] boolValue]) { }\n'
                '}\n%end\n')
            run=subprocess.run(['bash',str(STAGE),str(root)],cwd=ROOT,
                               capture_output=True,text=True,timeout=20)
            self.assertEqual(run.returncode,0,run.stdout+run.stderr)
            src=(root/'layout/usr/share/nktouch/lua/nktouch.lua').read_text()
            self.assertIn('function M.focusedInput(bundle)',src)
            self.assertIn('function M.inputSafe(value,options)',src)
            self.assertIn('function M.precisionTapIfMatch(options)',src)
            self.assertIn('Version: 0.8.7',(root/'control').read_text())
            self.assertIn('PACKAGE_VERSION="0.8.7"',
                          (root/'layout/usr/bin/nktouchctl').read_text())
            self.assertIn('NKInputFocusProbeWaiter',
                          (root/'pccontrol/UIKeyboard.xm').read_text())
            ui=(root/'zxtouch/zxtouch/Settings/SettingsPageViewController.m').read_text()
            self.assertIn('Input • Kiểm tra focus UIKit',ui)
            self.assertIn('Input • Strict Native (opt-in)',ui)
            self.assertIn('ENABLE_REAL_INPUT=false',
                          (root/'layout/usr/share/nktouch/examples/test_input_strict_v087.lua').read_text())
            again=subprocess.run(['bash',str(STAGE),str(root)],cwd=ROOT,
                                 capture_output=True,text=True)
            self.assertNotEqual(again.returncode,0,"stage must not reapply to 0.8.7")

    def test_build_is_artifact_only_and_reuses_086(self):
        src=BUILD.read_text()
        for marker in ('runs-on: macos-15','NK_VERSION: 0.8.7',
                       'NKTouch-v0.8.7-native-input-rootless',
                       'bash scripts/stage-v086-precision.sh upstream',
                       'bash scripts/stage-v087-input-reliability.sh upstream',
                       'lua tests/lua_v087_focus.lua',
                       'tests/test_v087_native_focus.py',
                       'l_focused_input',
                       'IOMobileFramebuffer.framework/IOMobileFramebuffer.tbd',
                       'iPhoneOS16.5.sdk.tar.xz'):
            self.assertIn(marker,src)
        for forbidden in ('publish-beta-to-sileo:','refs/heads/sileo-repo',
                          'publish-v086-sileo.sh'):
            self.assertNotIn(forbidden,src)

    @unittest.skipUnless(shutil.which('lua5.4') or shutil.which('lua'),'Lua 5.4 required')
    def test_strict_input_mock(self):
        binary=shutil.which('lua5.4') or shutil.which('lua')
        p=subprocess.run([binary,'tests/lua_v087_focus.lua'],
                         cwd=ROOT,capture_output=True,text=True,timeout=20)
        self.assertEqual(p.returncode,0,p.stdout+p.stderr)
        self.assertIn('[NK087][HOST] PASS',p.stdout)

if __name__=="__main__": unittest.main()
