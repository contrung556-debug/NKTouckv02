from pathlib import Path
import shutil, subprocess, unittest

ROOT=Path(__file__).resolve().parents[1]
MODULE=ROOT/"lua/nkvision_state.lua"
SAMPLE=ROOT/"examples/test_vision_state_v0811.lua"
STAGE=ROOT/"scripts/stage-v0811-vision-state.sh"

class VisionState811(unittest.TestCase):
    def test_normalization_and_wait_are_bounded_read_only(self):
        source=MODULE.read_text()
        for marker in ('VERSION="0.8.11-beta"','function M.normalize(text)',
                       'function M.waitFor(nk,options)','STATE_UNCERTAIN',
                       'AMBIGUOUS','ocr_text_included=false'):
            self.assertIn(marker,source)
        for forbidden in ('nk.tap(', 'nk.inputText(', 'nk.openApp(',
                          'os.execute(', 'io.popen('):
            self.assertNotIn(forbidden,source)
        sample=SAMPLE.read_text()
        self.assertIn('nk.waitForOCRState({',sample)
        self.assertIn('no action taken',sample)
        self.assertNotIn('nk.tap(',sample)
        self.assertNotIn('nk.inputText(',sample)

    @unittest.skipUnless(shutil.which('lua5.4') or shutil.which('lua'),
                         'Lua 5.4 required')
    def test_lua_state_gate(self):
        lua=shutil.which('lua5.4') or shutil.which('lua')
        run=subprocess.run([lua,'tests/lua_v0811_vision_state.lua'],cwd=ROOT,
                           text=True,capture_output=True,timeout=10)
        self.assertEqual(run.returncode,0,run.stdout+run.stderr)
        self.assertIn('[NKVISION811][HOST] PASS',run.stdout)

if __name__=="__main__":
    unittest.main()
