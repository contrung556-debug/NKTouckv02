"""NKTouch v0.8.3 OCR Performance Lab source contracts (not device evidence)."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
MOD = ROOT / "lua/nkocr_perf.lua"
STAGE = ROOT / "scripts/stage-v083-ocr-perf.sh"
BUILD = ROOT / ".github/workflows/build-v083-ocr-perf.yml"


class OCRPerfReleaseTests(unittest.TestCase):
    def test_bounded_readonly_module_with_true_monotonic_timing(self):
        s = MOD.read_text()
        self.assertIn("function M.benchmark(opts,deps)", s)
        self.assertIn("function M.ocrIfStable(opts,deps)", s)
        self.assertIn("core.nowMs", s)
        self.assertIn("CLOCK_UNAVAILABLE", s)
        self.assertIn("math.ceil(#values*p)", s)
        self.assertIn("p95_ms", s)
        self.assertIn("memory_frames=0/10/50/100", s)
        self.assertIn("SCREEN_UNSTABLE", s)
        self.assertIn("UNVERIFIED_BACKEND", s)
        self.assertIn("SERVICE_JPEG_SAME_FRAME", s)
        self.assertIn("OCR is performed on the SECOND captured frame", s)
        self.assertNotIn("os.clock", s)
        for forbidden in ("nk.tap(", "nk.inputText(", "nk.swipe(", "os.execute(", "io.popen(", "writeToFile:"):
            self.assertNotIn(forbidden, s)
        self.assertNotIn("print(text)", s)

    def test_sample_scripts_do_not_log_ocr_content(self):
        perf = (ROOT / "examples/test_ocr_perf_v083.lua").read_text()
        stable = (ROOT / "examples/test_ocr_stability_v083.lua").read_text()
        self.assertIn("runs=10", perf)
        self.assertIn("memory_frames=50", perf)
        self.assertIn("meta.captures", stable)
        self.assertNotIn("print(text)", stable)
        self.assertNotIn("print(text)", perf)

    def test_artifact_build_only_and_retains_same_frame_core(self):
        source = BUILD.read_text()
        self.assertIn("v0.8.3-ocr-perf-stability-dev", source)
        self.assertIn("NK_VERSION: 0.8.3", source)
        self.assertIn("runs-on: macos-15", source)
        self.assertNotIn("runs-on: macos-14", source)
        self.assertIn("NKTouch-v0.8.3-ocr-perf-rootless", source)
        # Inspect the *packaged* 0.8.3 binary, not stale version 0.8.2.
        self.assertIn('grep -Fq "PACKAGE_VERSION=\\\"$NK_VERSION\\\"" "$CTL_BIN"', source)
        self.assertNotIn('grep -Fq \'PACKAGE_VERSION="0.8.2"\' "$CTL_BIN"', source)
        # Theos installer failed on a malformed remote 16.5 SDK tarball.
        self.assertIn('SDK_PATH="$(xcrun --sdk iphoneos --show-sdk-path)"', source)
        self.assertIn('ln -s "$SDK_PATH"', source)
        self.assertIn('SDK_VERSION="$(xcrun --sdk iphoneos --show-sdk-version)"', source)
        self.assertIn('"TARGET=iphone:clang:${NK_THEOS_SDK_VERSION}:15.0"', source)
        self.assertIn('NK_THEOS_SDK_VERSION=$SDK_VERSION', source)
        self.assertIn("make clean package THEOS_PACKAGE_SCHEME=rootless FINALPACKAGE=1 \\", source)
        self.assertNotIn("make clean package THEOS_PACKAGE_SCHEME=rootless FINALPACKAGE=1 \\\\", source)
        self.assertNotIn("bin/install-theos", source)
        self.assertIn("bash scripts/stage-v083-ocr-perf.sh upstream", source)
        self.assertIn("lua tests/lua_v083_perf.lua", source)
        self.assertIn("scripts/prepare-v0802-release.sh", source)
        self.assertIn("scripts/apply-v0802-ocr-ipc.py", source)
        self.assertNotIn("publish-beta-to-sileo:", source)
        self.assertNotIn("publish-v0802-sileo.sh", source)
        self.assertNotIn("refs/heads/sileo-repo", source)

    def test_staging_overlay_pins_package_version_and_keeps_old_tests(self):
        content = STAGE.read_text()
        self.assertIn("bash", content)
        self.assertNotIn("git push", content)
        self.assertNotIn("make package", content)
        self.assertIn('Version: 0.8.3', content)
        self.assertIn("nkocr_perf.lua", content)
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            def put(rel, text):
                f = root / rel
                f.parent.mkdir(parents=True, exist_ok=True)
                f.write_text(text)
            put("control", """Package: com.nk.nktouch
Version: 0.8.2
Description: NKTouch v0.8.2 same-JPEG OCR IPC beta: immutable frame sent to existing SpringBoard Vision service; device validation pending
""")
            put("layout/usr/bin/nktouchctl", 'PACKAGE_VERSION="0.8.2"\n')
            put("layout/usr/share/doc/nktouch/VERSION", "NKTouch 0.8.2 Same-Frame OCR IPC Beta\n")
            put("layout/usr/share/nktouch/lua/nktestlab.lua",
                '-- NKTouch Test Lab v0.8.2-beta\nlocal M={VERSION="0.8.2-beta"}\n')
            put("zxtouch/zxtouch/Settings/SettingsPageViewController.m",
                'nkLabel:@"0.8.2"; // NKTouch 0.8.2\n'
                '@{@"file":@"test_gestures_optin.lua"}\n'
                '@{@"title":@"Tap / Hold / Swipe • tuỳ chọn", @"file":@"test_gestures_optin.lua"}\n')
            cp = subprocess.run(["bash", str(STAGE), str(root)], cwd=ROOT,
                                capture_output=True, text=True)
            self.assertEqual(cp.returncode, 0, cp.stdout + cp.stderr)
            self.assertIn("Version: 0.8.3", (root/"control").read_text())
            self.assertIn("0.8.3-beta", (root/"layout/usr/share/nktouch/lua/nktestlab.lua").read_text())
            self.assertTrue((root/"layout/usr/share/nktouch/lua/nkocr_perf.lua").is_file())
            self.assertTrue((root/"layout/usr/share/nktouch/examples/test_ocr_stability_v083.lua").is_file())
            self.assertIn("test_ocr_perf_v083.lua",
                          (root/"zxtouch/zxtouch/Settings/SettingsPageViewController.m").read_text())
            again = subprocess.run(["bash", str(STAGE), str(root)], cwd=ROOT,
                                   capture_output=True, text=True)
            self.assertNotEqual(again.returncode, 0, "must never silently restage twice")

    @unittest.skipUnless(shutil.which("lua") or shutil.which("lua5.4"), "Lua 5.4 required")
    def test_deterministic_lua_mock(self):
        lua = shutil.which("lua5.4") or shutil.which("lua")
        cp = subprocess.run([lua, "tests/lua_v083_perf.lua"], cwd=ROOT,
                            capture_output=True, text=True, timeout=30)
        self.assertEqual(cp.returncode, 0, cp.stdout + cp.stderr)
        self.assertIn("[NKPERF][HOST] PASS", cp.stdout)


if __name__ == "__main__":
    unittest.main()
