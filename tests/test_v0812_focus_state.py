from pathlib import Path
import shutil, subprocess, unittest

ROOT=Path(__file__).resolve().parents[1]
MODULE=ROOT/"lua/nkfocus_state.lua"
SAMPLE=ROOT/"examples/test_focus_state_v0812.lua"
STAGE=ROOT/"scripts/stage-v0812-focus-state.sh"

class FocusState812(unittest.TestCase):
    def test_module_is_bounded_read_only_and_fail_closed(self):
        source=MODULE.read_text()
        for marker in ('VERSION="0.8.12-beta"','function M.waitFor(nk,options)',
                       'FOCUS_UNSTABLE','FOCUS_PROBE_UNAVAILABLE',
                       'action_taken=false','stable_reads','timeout_ms'):
            self.assertIn(marker,source)
        for forbidden in ('nk.tap(', 'nk.inputText(', 'nk.openApp(',
                          'os.execute(', 'io.popen('):
            self.assertNotIn(forbidden,source)
        sample=SAMPLE.read_text()
        self.assertIn('nk.waitForInputFocus({',sample)
        for forbidden in ('nk.tap(', 'nk.inputText(', 'nk.openApp('):
            self.assertNotIn(forbidden,sample)

    def test_stage_wires_public_api_and_test_lab(self):
        source=STAGE.read_text()
        for marker in ('Version: 0.8.11','Version: 0.8.12',
                       'function M.waitForInputFocus(options)',
                       'test_focus_state_v0812.lua',
                       'Input • Focus ổn định (read-only)'):
            self.assertIn(marker,source)

    @unittest.skipUnless(shutil.which('lua5.4') or shutil.which('lua'),
                         'Lua 5.4 required')
    def test_lua_focus_wait(self):
        lua=shutil.which('lua5.4') or shutil.which('lua')
        run=subprocess.run([lua,'tests/lua_v0812_focus_state.lua'],cwd=ROOT,
                           text=True,capture_output=True,timeout=10)
        self.assertEqual(run.returncode,0,run.stdout+run.stderr)
        self.assertIn('[NKFOCUS812][HOST] PASS',run.stdout)

if __name__=="__main__":
    unittest.main()
