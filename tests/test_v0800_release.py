"""Rootless v0.8.0 artifact integrity and compatibility source gates."""
from pathlib import Path
import unittest

ROOT=Path(__file__).resolve().parents[1]

class V0800Release(unittest.TestCase):
    def test_single_stage_inherits_v0719_without_updating_legacy_core(self):
        s=(ROOT/"scripts/prepare-v0800-release.sh").read_text()
        self.assertIn('prepare-v0719-release.sh',s)
        self.assertIn('"Version: 0.7.19","Version: 0.8.0"',s)
        self.assertIn('PACKAGE_VERSION="0.8.0"',s)
        for name in ("nkdiagnostics","nksnapshot","nkactions","nksdk"):
            self.assertIn(f'"$ROOT/lua/$name.lua"',s)
            self.assertIn(f'"$LIB/$name.lua"',s)
        self.assertIn('nk_v0800_readonly_demo.lua',s)
        self.assertIn('handlers.diagnostics=function()',s)
        self.assertIn('NKTouch 0.8.0 Integrated Lua SDK Beta',s)
        self.assertNotIn('dpkg-deb',s)
        self.assertNotIn('sileo-repo',s)
        self.assertNotIn('killall',s)

    def test_new_sdk_does_not_mutate_legacy_touch_or_input_engine(self):
        sdk=(ROOT/"lua/nksdk.lua").read_text()
        actions=(ROOT/"lua/nkactions.lua").read_text()
        snap=(ROOT/"lua/nksnapshot.lua").read_text()
        diag=(ROOT/"lua/nkdiagnostics.lua").read_text()
        self.assertNotIn("installAutoTouchCompat",sdk)
        self.assertNotIn("_G.",sdk)
        self.assertIn('enabled~=true or opts.confirmed~=true',actions)
        self.assertIn('DISPATCH_UNCERTAIN',actions)
        self.assertIn('no retry',actions.lower())
        self.assertIn('nk.withFrame(function(frame)',snap)
        self.assertIn('retry_not_found=true',snap)
        self.assertNotIn("nk.screenshot(",snap)
        self.assertIn('session.in_flight=(state=="ENTER")',diag)
        self.assertIn('last_status',diag)
        self.assertIn('task_id',diag)
        self.assertIn('exit_code',diag)
        self.assertIn('signal',diag)
        self.assertNotIn('args=',diag)
        self.assertNotIn('result_string=',diag)

    def test_build_workflow_single_artifact_gate(self):
        p=ROOT/".github/workflows/build-v0800-integrated.yml"
        self.assertTrue(p.exists(),"iOS integrated build workflow missing")
        s=p.read_text()
        self.assertIn('build-rootless:',s)
        self.assertIn('NK_VERSION: 0.8.0',s)
        self.assertIn('NK_BUILD: 80000',s)
        self.assertIn('release/v0800-build-ready.txt',s)
        self.assertIn('prepare-v0800-release.sh',s)
        self.assertIn('tests/test_v0800_integrated.py',s)
        self.assertIn('tests/test_v0800_release.py',s)
        self.assertIn('NKTouch-v0.8.0-integrated-rootless',s)
        self.assertNotIn('sileo-repo',s)
        self.assertNotIn('publish',s.lower().split('on:',1)[0])

if __name__=="__main__":
    unittest.main()
