"""v0.7.18 Vision OCR reliability candidate contract checks.

Host/static tests cannot establish Vision behavior on a real iPhone.
"""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]

class OCRCIImageV0718(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = (ROOT / "runtime/nkvision.m").read_text()
        cls.fn = cls.source.split("static int nv_ocr(lua_State *L) {", 1)[1].split("static int nv_score(",1)[0]

    def test_same_frame_ciimage_first_and_old_backend_fallback(self):
        self.assertIn("#import <CoreImage/CoreImage.h>",self.source)
        self.assertIn("initWithCGImage:crop", self.fn)
        self.assertIn("initWithCIImage:ciImage", self.fn)
        self.assertIn("req.revision=2",self.fn)
        self.assertIn("if (!success)",self.fn)
        self.assertLess(self.fn.index("initWithCIImage:ciImage"),self.fn.rindex("initWithCGImage:crop"))
        self.assertIn("CGImageRelease(crop)",self.fn)

    def test_no_side_effects_or_recapture_in_ocr(self):
        implementation=re.sub(r"//[^\\n]*","",self.fn)
        for forbidden in ("TASK_SCREENSHOT","nk.screenshot","nk.ocr(","tap(","swipe(","inputText(","system(","posix_spawn","send("):
            self.assertNotIn(forbidden,implementation)
        self.assertIn('return nv_error(L,[message UTF8String],"OCR")',self.fn)

    def test_error_details_keep_domain_and_code_and_do_not_log_text(self):
        helper=self.source.split("static NSString *nv_ocr_failure_detail",1)[1].split("static int nv_ocr",1)[0]
        self.assertIn("err.domain",helper)
        self.assertIn("err.code",helper)
        self.assertIn("NSUnderlyingErrorKey",helper)
        self.assertIn("description.length>160",helper)
        self.assertNotIn("NSLog(",self.fn)
        self.assertNotIn("NSLog(",helper)

    def test_release_staging_keeps_immutable_previous_version(self):
        stage=(ROOT/"scripts/prepare-v0718-release.sh").read_text()
        self.assertIn("prepare-v0717-release.sh",stage)
        self.assertIn("'Version: 0.7.17','Version: 0.7.18'",stage)
        self.assertIn("test_v0717_ocr_diagnostics_readonly.lua",stage)
        self.assertIn("test_v0717_memory_ocr_readonly.lua",stage)

if __name__=="__main__":
    unittest.main()
