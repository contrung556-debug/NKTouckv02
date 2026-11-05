"""Source-level safety checks for v0.8.2 OCR recovery and app restoration.

These checks do not claim real-device OCR success.
"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]

class OCRRecovery(unittest.TestCase):
    def test_ipc_trims_only_newlines_before_strict_base64(self):
        task = (ROOT / "patches/NKFrameOCRTask.xm.inc").read_text()
        self.assertIn("stringByTrimmingCharactersInSet:", task)
        self.assertIn("[NSCharacterSet newlineCharacterSet]", task)
        self.assertIn("initWithBase64EncodedString:encoded options:0", task)
        self.assertNotIn("NSDataBase64DecodingIgnoreUnknownCharacters", task)
        self.assertNotIn("Screen createScreenShotCGImageRef", task)

    def test_standalone_corevideo_probe_has_no_capture(self):
        source = (ROOT / "runtime/nkvision.m").read_text()
        probe = source.split("static int nv_probe_cv_pixel_buffer(", 1)[1].split(
            "static const luaL_Reg nv_module[]", 1)[0]
        self.assertIn("CVPixelBufferCreate(", probe)
        self.assertIn("kCVPixelFormatType_420YpCbCr8BiPlanarFullRange", probe)
        self.assertIn("CVPixelBufferRelease(pb)", probe)
        self.assertIn('"probeCVPixelBuffer",nv_probe_cv_pixel_buffer', source)
        for forbidden in ("Screen createScreenShot", "screenshot(", "writeToFile:"):
            self.assertNotIn(forbidden, probe)
        build = (ROOT / ".github/workflows/build-v0802-frame-ipc.yml").read_text()
        self.assertIn("-framework CoreVideo", build)

    def test_fallback_is_a_separate_opt_in_api(self):
        lua = (ROOT / "lua/nktouch.lua").read_text()
        self.assertIn("function M.ocrWithFallback(", lua)
        self.assertIn('backend="OCR_FALLBACK_LIVE"', lua)
        self.assertIn("same_frame=false", lua)
        self.assertIn("recaptured=true", lua)
        lab = (ROOT / "lua/nktestlab.lua").read_text()
        self.assertIn('"pixelbuffer_420f_probe"', lab)
        self.assertIn("probeCVPixelBuffer(pw,ph)", lab)
        self.assertIn("FRAME_OCR_BROKEN; OCR_FALLBACK_LIVE available", lab)
        self.assertIn('return "FAIL","FRAME_OCR_BROKEN', lab)

    def test_lab_restores_after_results_before_raising(self):
        ui = (ROOT / "patches/NKTestLabUIViewController.m.inc").read_text()
        section = ui.split("- (void)labCreateRunner {",1)[1]
        self.assertIn('@"local ran,result=pcall(lab.run,opts)', section)
        self.assertIn("pcall(nk.openApp,", section)
        self.assertIn("com.zjx.zxtouch", section)
        self.assertIn("[NKLAB][RESTORE]", section)
        self.assertLess(section.index('pcall(nk.openApp,'),
                        section.index('if not ran then error(result,0) end'))
        self.assertLess(section.index('pcall(nk.openApp,'),
                        section.index('if result.fail>0 then error'))

if __name__ == "__main__":
    unittest.main()
