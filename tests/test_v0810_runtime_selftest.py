"""Contract tests for the v0.8.10 read-only Runtime Self-Test sample."""
from pathlib import Path
import unittest

ROOT=Path(__file__).resolve().parents[1]
SAMPLE=ROOT/"examples/test_runtime_selftest_v0810.lua"
STAGE=ROOT/"scripts/stage-v0810-runtime-selftest.sh"
BUILD=ROOT/".github/workflows/build-v089-runtime.yml"

class RuntimeSelfTest810(unittest.TestCase):
    def test_sample_checks_runtime_without_mutating_ui_or_containers(self):
        s=SAMPLE.read_text()
        for marker in ('require, "nktouch_v7"', 'nk.runtime', 'nk.screen',
                       'nk.sleep', 'io.popen', 'cranectl.list',
                       'NKTOUCH_IOPOPEN_OK', '--list', '[NKRT810]'):
            self.assertIn(marker,s)
        for prohibited in ('nk.tap(', 'nk.inputText(', 'nk.ocr(',
                           '--create', '--switch', 'os.execute(',
                           'io.popen(user', 'print(processResult.output)'):
            self.assertNotIn(prohibited,s)

    def test_sample_is_registered_and_staged_for_installed_samples_ui(self):
        s=STAGE.read_text()
        for marker in ('examples/test_runtime_selftest_v0810.lua',
                       'test_runtime_selftest_v0810.lua',
                       'Runtime • Tự kiểm tra Lua / io.popen',
                       'Version: 0.8.10', 'PACKAGE_VERSION="0.8.10"',
                       'test ! -e "$SRC/layout/var/jb"'):
            self.assertIn(marker,s)
        w=BUILD.read_text()
        for marker in ('NK_VERSION: 0.8.10',
                       'bash scripts/stage-v0810-runtime-selftest.sh upstream',
                       'tests/test_v0810_runtime_selftest.py',
                       'NKTouch-v0.8.10-runtime-selftest-rootless'):
            self.assertIn(marker,w)
        for forbidden in ('publish-beta-to-sileo:', 'refs/heads/sileo-repo'):
            self.assertNotIn(forbidden,w)

if __name__=="__main__":
    unittest.main()
