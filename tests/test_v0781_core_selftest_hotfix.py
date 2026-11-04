from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]

class SelfTestFalseFailHotfixTests(unittest.TestCase):
    def test_ui_does_not_gate_lua_core_pass_on_full_doctor(self):
        script = (ROOT / "scripts/apply-v078-core-selftest-ui.py").read_text()
        self.assertIn("doctor_gate='BOOL pass=wrote&&cc==0&&dc==0&&rc==0&&'", script)
        self.assertIn("method = method.replace(doctor_gate, 'BOOL pass=wrote&&cc==0&&rc==0&&', 1)", script)
        self.assertIn("Doctor (optional)", script)
        self.assertIn("status=PASS", script)

    def test_package_version_and_retain_core(self):
        s = (ROOT / "scripts/prepare-v0781-core-selftest-hotfix.sh").read_text()
        self.assertIn("prepare-v078-core-selftest.sh", s)
        self.assertIn("Version: 0.7.8.1", s)
        self.assertIn('PACKAGE_VERSION="0.7.8.1"', s)
        self.assertIn("Core Self-Test false-fail hotfix verified", s)
        self.assertIn("test -f", s)
        self.assertIn("test ! -e", s)

if __name__ == "__main__":
    unittest.main()
