"""NKTouch v0.8.1 Vision OCR -6662 compatibility regression gates.

These are source invariants and ROI math tests. Only the physical iPhone
can prove CoreVideo allocation in the Lua runtime actually succeeds.
"""
from pathlib import Path
import re
import unittest

ROOT=Path(__file__).resolve().parents[1]

class OCRBufferFallback(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.all=(ROOT/"runtime/nkvision.m").read_text()
        cls.ocr=cls.all.split("static int nv_ocr(lua_State *L) {",1)[1].split("static int nv_score(",1)[0]

    def test_retains_existing_same_capture_strategies(self):
        src=self.ocr
        self.assertIn("initWithCIImage:ciImage",src)
        self.assertIn("initWithCGImage:crop",src)
        self.assertIn("CGImageRelease(crop)",src)
        self.assertIn("req.revision=2",src)
        self.assertLess(src.index("initWithCIImage:ciImage"),src.index("initWithCGImage:crop"))
        self.assertLess(src.index("initWithCGImage:crop"),src.index("initWithData:originalJPEG"))

    def test_third_backend_is_same_jpeg_no_second_capture(self):
        src=re.sub(r"//[^\n]*","",self.ocr)
        self.assertIn("NSData *originalJPEG=(__bridge NSData *)f->jpeg",src)
        self.assertIn("initWithData:originalJPEG options:@{}",src)
        self.assertIn("jpegRequest.revision=1",src)
        self.assertIn("jpegRequest.usesCPUOnly=YES",src)
        self.assertIn("VNRequestTextRecognitionLevelFast",src)
        self.assertIn("if (!success)",src)
        for forbidden in ("TASK_SCREENSHOT","nk.screenshot","nk.ocr(","tap(","inputText(","posix_spawn","system(","request_task("):
            self.assertNotIn(forbidden,src)

    def test_roi_correctly_flips_y_for_vision(self):
        src=self.ocr
        self.assertIn("(CGFloat)x/(CGFloat)f->w",src)
        self.assertIn("(CGFloat)(f->h-(size_t)y-(size_t)h)/(CGFloat)f->h",src)
        self.assertIn("jpegRequest.regionOfInterest=CGRectMake(rx,ry,rw,rh)",src)
        def roi(x,y,w,h,W,H):
            assert 0<=x and x+w<=W and 0<=y and y+h<=H
            return (x/W,(H-y-h)/H,w/W,h/H)
        self.assertEqual(roi(0,0,750,220,750,1334), (0,1114/1334,1,220/1334))
        self.assertEqual(roi(0,1114,750,220,750,1334),(0,0,1,220/1334))
        self.assertEqual(roi(0,0,750,1334,750,1334),(0,0,1,1))
        # Subrect: center X, proper bounding fractions
        self.assertEqual(roi(100,300,200,250,750,1334),
                         (100/750,784/1334,200/750,250/1334))

    def test_failure_includes_all_backend_errors_but_not_recognized_text(self):
        src=self.ocr
        self.assertIn("Vision OCR failed (CIImage/rev2: %@; CGImage: %@; JPEG/ROI/rev1/CPU: %@)",src)
        self.assertIn('return nv_error(L,[message UTF8String],"OCR")',src)
        self.assertIn("nv_ocr_failure_detail(jpegError,jpegException)",src)
        self.assertNotIn("NSLog(",src)
        self.assertIn("[result UTF8String]",src)

    def test_version_bump_and_safety(self):
        stage=(ROOT/"scripts/prepare-v0801-release.sh").read_text()
        self.assertIn("prepare-v0800-release.sh",stage)
        self.assertIn('Version: 0.8.1',stage)
        self.assertNotIn("sileo-repo",stage)
        self.assertNotIn("dpkg-deb",stage)
        wf=(ROOT/".github/workflows/build-v0801-ocr-buffer.yml").read_text()
        self.assertIn("NK_VERSION: 0.8.1",wf)
        self.assertIn("NK_BUILD: 80100",wf)
        self.assertIn("test_v0801_ocr_buffer.py",wf)
        self.assertIn("release/v0801-build-ready.txt",wf)
        self.assertIn("NKTouch-v0.8.1-ocr-buffer-rootless",wf)

if __name__=="__main__":
    unittest.main()
