from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class StandaloneLuaContract(unittest.TestCase):
    def test_runtime_version_and_lua_commands(self):
        s = (ROOT / "runtime" / "nktouchctl").read_text()
        self.assertIn('VERSION="0.6.2"', s)
        self.assertIn('LUA_VERSION="5.4.9"', s)
        self.assertIn('LUA_RUNNER="/var/jb/usr/bin/nktouch-lua"', s)
        self.assertIn('lua) run_lua "$@"', s)
        self.assertIn('lua-check) check_lua "$@"', s)
        self.assertIn('lua-version)', s)
        self.assertIn('lua_runtime=ok', s)
        self.assertIn('Side-effecting commands: single attempt only.', s)

    def test_lua_launcher_bootstraps_nktouch(self):
        s = (ROOT / "runtime" / "nktouch-lua").read_text()
        self.assertIn('/var/jb/usr/libexec/nktouch/lua54', s)
        self.assertIn('LUA_PATH=', s)
        self.assertIn('require("nktouch")', s)
        self.assertIn('installAutoTouchCompat()', s)
        self.assertIn('--plain', s)

    def test_lua_api_version_and_compat(self):
        s = (ROOT / "lua" / "nktouch.lua").read_text()
        self.assertIn('M.VERSION="0.6.2"', s)
        self.assertIn('M.NATIVE_VERSION="0.6.0"', s)
        self.assertIn('M.LUA_VERSION="5.4.9"', s)
        self.assertIn('_G.tap=M.tap', s)
        self.assertIn('_G.swipe=M.swipe', s)
        self.assertIn('_G.inputText=M.inputText', s)
        self.assertIn('_G.usleep=', s)
        self.assertIn('_G.getColor=', s)

    def test_package_bundles_lua(self):
        s = (ROOT / "scripts" / "prepare-v062.sh").read_text()
        self.assertIn('Version: 0.6.2', s)
        self.assertIn('NKTouch 0.6.2 Standalone Lua', s)
        self.assertIn('lua54', s)
        self.assertIn('luac54', s)
        self.assertIn('nktouch-lua', s)
        self.assertIn('LUA_README.txt', s)

    def test_native_protocol_unchanged(self):
        s = (ROOT / "runtime" / "nktouch-native.c").read_text()
        self.assertIn('#define NK_VERSION "0.6.0"', s)
        self.assertIn('#define TASK_SCREENSHOT 30', s)
        self.assertNotIn('#define TASK_SCREENSHOT 29', s)


if __name__ == "__main__":
    unittest.main()
