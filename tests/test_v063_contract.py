from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class DirectLuaContract(unittest.TestCase):
    def test_runtime_version(self):
        s = (ROOT / "runtime" / "nktouchctl").read_text()
        self.assertIn('VERSION="0.6.3"', s)
        self.assertIn('LUA_CORE_VERSION="0.6.3"', s)
        self.assertIn('lua_direct=ok', s)
        self.assertIn('direct-lua', s)

    def test_embedded_native_module_protocol(self):
        s = (ROOT / "runtime" / "nkcore.c").read_text()
        self.assertIn('#define NKCORE_VERSION "0.6.3"', s)
        self.assertIn('#define NK_NATIVE_VERSION "0.6.0"', s)
        self.assertIn('#define TASK_TEMPLATE_MATCH 21', s)
        self.assertIn('#define TASK_COLOR_PICKER 23', s)
        self.assertIn('#define TASK_TEXT 24', s)
        self.assertIn('#define TASK_DEVICE 25', s)
        self.assertIn('#define TASK_OCR 27', s)
        self.assertIn('#define TASK_COLOR_SEARCH 28', s)
        self.assertIn('#define TASK_SCREENSHOT 30', s)
        self.assertNotIn('#define TASK_SCREENSHOT 29', s)
        self.assertIn('luaopen_nkcore', s)

    def test_lua_prefers_direct_module(self):
        s = (ROOT / "lua" / "nktouch.lua").read_text()
        self.assertIn('M.VERSION="0.6.3"', s)
        self.assertIn('pcall(require,"nkcore")', s)
        self.assertIn('M.DIRECT=core~=nil', s)
        self.assertIn('if core then return core.tap', s)
        self.assertIn('if core then return core.screenshot', s)
        self.assertIn('if core then return core.ocr', s)
        self.assertIn('coreWait', s)

    def test_package_version(self):
        s = (ROOT / "scripts" / "prepare-v063.sh").read_text()
        self.assertIn('Version: 0.6.3', s)
        self.assertIn('NKTouch 0.6.3 Direct Lua Native', s)
        self.assertIn('Embedded nkcore 0.6.3', s)


if __name__ == "__main__":
    unittest.main()
