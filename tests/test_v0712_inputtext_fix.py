"""NKTouch v0.7.12 inputText regression tests: real staged-source patch."""
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
PATCH = ROOT / "scripts/apply-v0712-inputtext-fix.py"

class InputTextFixTests(unittest.TestCase):
    def test_patch_compiles(self):
        compile(PATCH.read_text(),str(PATCH),"exec")

    def stage(self):
        fake = tempfile.TemporaryDirectory()
        root = Path(fake.name)
        lua = root/"layout/usr/share/nktouch/lua/nktouch.lua"
        ui = root/"zxtouch/zxtouch/Settings/SettingsPageViewController.m"
        lua.parent.mkdir(parents=True)
        ui.parent.mkdir(parents=True)
        src = (ROOT/"lua/nktouch.lua").read_text()
        self.assertIn("M.inputText=M.text",src)
        lua.write_text(src)
        ui.write_text('''NSString *lua=[NSString stringWithFormat:
      @"-- NKTouch Target App bootstrap v0.7.11\\n"
      @"local nk=require('nktouch')\\n"
      @"os.remove(%@)\\n"
      @"local ok,err,code=nk.openApp(%@)\\n"
      @"local run=assert(loadfile(%@,'t'))\\n"
      @"return run()\\n"];
''')
        return fake, lua, ui

    def test_inputtext_routes_to_v2_without_legacy_retry(self):
        fake,lua,ui=self.stage()
        with fake:
            result=subprocess.run(["python3",str(PATCH),fake.name],
                                  text=True,capture_output=True)
            self.assertEqual(result.returncode,0,result.stderr)
            patched=lua.read_text()
            self.assertIn("M.legacyInputText=M.text",patched)
            self.assertNotIn("M.inputText=M.text",patched)
            self.assertIn("function M.inputText(value,options)\n  return M.inputTextV2(value,options)",patched)
            self.assertIn('function M.inputTextV2(value,options)',patched)
            self.assertIn("_G.inputText=M.inputText",patched)
            self.assertNotIn('return M.text(value)',patched)
            generated=ui.read_text()
            self.assertIn('@"nk.installAutoTouchCompat()\\n"',generated)
            self.assertLess(generated.index("nk.installAutoTouchCompat()"),
                            generated.index("loadfile(%@"))

    def test_patch_fails_closed_on_wrong_baseline(self):
        fake,lua,ui=self.stage()
        with fake:
            lua.write_text(lua.read_text().replace("M.inputText=M.text","M.inputText=M.other"))
            result=subprocess.run(["python3",str(PATCH),fake.name],
                                  text=True,capture_output=True)
            self.assertNotEqual(result.returncode,0)

    def test_stage_script_preserves_previous_version(self):
        script=(ROOT/"scripts/prepare-v0712-inputtext-fix.sh").read_text()
        self.assertIn("prepare-v0711-target-apps.sh",script)
        self.assertIn("apply-v0712-inputtext-fix.py",script)
        self.assertIn("Version: 0.7.12",script)

if __name__=="__main__":
    unittest.main()
