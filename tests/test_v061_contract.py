from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]

class StableRuntimeContract(unittest.TestCase):
    def test_runtime_version_and_hardening(self):
        s = (ROOT / "runtime" / "nktouchctl").read_text()
        self.assertIn('VERSION="0.6.1"', s)
        self.assertIn('run_native_read()', s)
        self.assertIn('doctor()', s)
        self.assertIn('selftest()', s)
        self.assertIn('cleanup_tmp()', s)
        self.assertIn('Side-effecting commands: single attempt only.', s)
        self.assertIn('tap|hold|swipe|openapp|stop|record|text|keyboard|cursor|delete|paste|clipboard-set|toast|tap-image|tap-color', s)

    def test_native_protocol_stays_on_v06_engine(self):
        s = (ROOT / "runtime" / "nktouch-native.c").read_text()
        self.assertIn('#define NK_VERSION "0.6.0"', s)
        self.assertIn('#define TASK_TOAST 22', s)
        self.assertIn('#define TASK_COLOR_PICKER 23', s)
        self.assertIn('#define TASK_OCR 27', s)
        self.assertIn('#define TASK_COLOR_SEARCH 28', s)
        self.assertIn('#define TASK_SCREENSHOT 30', s)
        self.assertNotIn('#define TASK_SCREENSHOT 29', s)

    def test_lua_health_api(self):
        s = (ROOT / "lua" / "nktouch.lua").read_text()
        self.assertIn('M.VERSION="0.6.1"', s)
        self.assertIn('M.NATIVE_VERSION="0.6.0"', s)
        self.assertIn('function M.selftest()', s)
        self.assertIn('function M.cleanup()', s)
        self.assertIn('local function status_ok', s)

    def test_package_version(self):
        s = (ROOT / "scripts" / "prepare-v061.sh").read_text()
        self.assertIn('Version: 0.6.1', s)
        self.assertIn('NKTouch 0.6.1 Stable', s)
        self.assertIn('/var/mobile/Library/NKTouch/tmp', s)

if __name__ == "__main__":
    unittest.main()
