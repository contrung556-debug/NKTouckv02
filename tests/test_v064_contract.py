from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class HardenedDirectLuaContract(unittest.TestCase):
    def test_runtime_version_and_health_commands(self):
        s = (ROOT / "runtime" / "nktouchctl").read_text()
        self.assertIn('VERSION="0.6.4"', s)
        self.assertIn('LUA_CORE_VERSION="0.6.3"', s)
        self.assertIn('benchmark)', s)
        self.assertIn('stress)', s)
        self.assertIn('lua_stress=ok', s)
        self.assertIn('direct-hardened', s)

    def test_protocol_core_is_intentionally_unchanged(self):
        s = (ROOT / "runtime" / "nkcore.c").read_text()
        self.assertIn('#define NKCORE_VERSION "0.6.3"', s)
        self.assertIn('#define NK_NATIVE_VERSION "0.6.0"', s)
        self.assertIn('#define TASK_TEMPLATE_MATCH 21', s)
        self.assertIn('#define TASK_COLOR_PICKER 23', s)
        self.assertIn('#define TASK_OCR 27', s)
        self.assertIn('#define TASK_COLOR_SEARCH 28', s)
        self.assertIn('#define TASK_SCREENSHOT 30', s)
        self.assertNotIn('#define TASK_SCREENSHOT 29', s)

    def test_lua_read_retry_and_side_effect_policy(self):
        s = (ROOT / "lua" / "nktouch.lua").read_text()
        self.assertIn('M.VERSION="0.6.4"', s)
        self.assertIn('local function classify(err)', s)
        self.assertIn('local function readCall', s)
        self.assertIn('local function sideCall', s)
        self.assertIn('function M.retryConfig()', s)
        self.assertIn('return sideCall("tap",core.tap', s)
        self.assertIn('return sideCall("swipe",core.swipe', s)
        self.assertIn('return sideCall("text",core.text', s)
        self.assertIn('return readCall("screen",core.screen)', s)
        self.assertIn('return readCall("foreground",core.foreground)', s)
        self.assertIn('return readCall("getColor",core.getColor', s)
        self.assertIn('function M.benchmark', s)
        self.assertIn('function M.stress', s)

    def test_package_version(self):
        s = (ROOT / "scripts" / "prepare-v064.sh").read_text()
        self.assertIn('Version: 0.6.4', s)
        self.assertIn('NKTouch 0.6.4 Hardened Direct Lua', s)
        self.assertIn('Embedded nkcore 0.6.3', s)
        self.assertIn('Read-only reconnect retry enabled', s)


if __name__ == "__main__":
    unittest.main()
