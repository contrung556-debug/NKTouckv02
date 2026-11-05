"""v0.8.2: immutable screenshot ROI OCR through existing SpringBoard service.

Host/source invariants only. Real SpringBoard injection and CVPixelBuffer
behavior require on-device testing; no fake PASS is inferred from these tests.
"""
from pathlib import Path
import subprocess
import tempfile
import unittest
import re

ROOT=Path(__file__).resolve().parents[1]

class FrameOCRIPC(unittest.TestCase):
    def test_native_bridge_only_uses_existing_frame_region(self):
        source=(ROOT/"runtime/nkvision.m").read_text()
        bridge=source.split("static NSString *nv_ocr_service_jpeg(",1)[1].split(
            "static int nv_ocr(lua_State *L) {",1)[0]
        self.assertIn("CGImageCreateWithImageInRect(f->image",bridge)
        self.assertIn("CGImageDestinationCreateWithData(",bridge)
        self.assertIn('CFSTR("public.jpeg")',bridge)
        self.assertIn("CGImageDestinationFinalize(dest)",bridge)
        self.assertIn("jpeg.length>1024*1024",bridge)
        self.assertIn("encoded.length>1400000",bridge)
        self.assertIn('@"31%lld;;%lld;;%lld;;%lld;;%@;;%@\\r\\n"',bridge)
        self.assertIn("127.0.0.1",bridge)
        self.assertIn("htons(6000)",bridge)
        for forbidden in ("nk.screenshot","Screen createScreenShotCGImageRef",
                          "system(","posix_spawn(","dataWithContentsOfFile:",
                          "writeToFile:","TASK_SCREENSHOT"):
            self.assertNotIn(forbidden,bridge)

    def test_backend_provenance_and_fallback_are_explicit(self):
        source=(ROOT/"runtime/nkvision.m").read_text()
        ocr=source.split("static int nv_ocr(lua_State *L) {",1)[1].split(
            "static int nv_score(",1)[0]
        self.assertIn("nv_ocr_service_jpeg(f,x,y,w,h,language,len)",ocr)
        self.assertIn("if (bridgeText != nil)",ocr)
        self.assertIn("f->ocr_backend=1",ocr)
        self.assertIn("f->ocr_backend=2",ocr)
        self.assertLess(ocr.index("nv_ocr_service_jpeg("),ocr.index("CGImageCreateWithImageInRect"))
        self.assertIn('f->ocr_backend==1 ? "SERVICE_JPEG_SAME_FRAME"',source)
        self.assertIn('lua_setfield(L,-2,"ocr_backend")',source)
        lab=(ROOT/"lua/nktestlab.lua").read_text()
        self.assertIn('backend=after and after.ocr_backend',lab)
        self.assertIn('frame OCR bytes=%d backend=%s',lab)
        self.assertIn("FRAME_OCR_BROKEN",lab)

    def test_server_is_bounded_read_only_and_never_recaptures(self):
        task=(ROOT/"patches/NKFrameOCRTask.xm.inc").read_text()
        self.assertIn("TASK_NK_FRAME_OCR",task)
        self.assertIn("initWithBase64EncodedString:encoded options:0",task)
        self.assertIn("encoded.length<=1400000",task)
        self.assertIn("jpeg.length<=1024*1024",task)
        self.assertIn("CGImageSourceCreateWithData(",task)
        self.assertIn("initWithCGImage:image",task)
        self.assertIn("NK_FRAME_OCR_UNAVAILABLE",task)
        self.assertIn('@"0;;%@\\r\\n"',task)
        self.assertNotIn("Screen createScreenShotCGImageRef",task)
        self.assertNotIn("dataWithContentsOfFile:",task)
        self.assertNotIn("writeToFile:",task)
        self.assertNotIn("NSLog(",task)

    def test_upstream_patcher_fails_closed_and_adds_exact_one_task(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/"pccontrol"
            p.mkdir(parents=True)
            (p/"Task.h").write_text("#define TASK_SCREENSHOT 30\n")
            (p/"Task.xm").write_text(
                "#include <TextRecognization/TextRecognizer.h>\n"
                "    else if (taskType == TASK_COLOR_SEARCHER)\n"
            )
            (p/"Makefile").write_text("pccontrol_FRAMEWORKS = UIKit AssetsLibrary AVFoundation\n")
            cmd=["python3",str(ROOT/"scripts/apply-v0802-ocr-ipc.py"),d]
            first=subprocess.run(cmd,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
            self.assertEqual(first.returncode,0,first.stderr)
            task=(p/"Task.xm").read_text()
            self.assertEqual(task.count("TASK_NK_FRAME_OCR"),1)
            self.assertIn("#import <ImageIO/ImageIO.h>",task)
            self.assertIn("NK_FRAME_OCR_UNAVAILABLE",task)
            self.assertIn("Vision CoreImage ImageIO UIKit", (p/"Makefile").read_text())
            self.assertIn("TASK_NK_FRAME_OCR 31",(p/"Task.h").read_text())
            second=subprocess.run(cmd,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
            self.assertNotEqual(second.returncode,0,"patch should fail on second attempt")

    def test_release_is_candidate_only(self):
        stage=(ROOT/"scripts/prepare-v0802-release.sh").read_text()
        self.assertIn("prepare-v0801-release.sh",stage)
        self.assertIn("Version: 0.8.2",stage)
        self.assertNotIn("sileo-repo",stage)
        self.assertNotIn("dpkg-deb",stage)
        wf=(ROOT/".github/workflows/build-v0802-frame-ipc.yml").read_text()
        for val in ("NK_VERSION: 0.8.2","NK_BUILD: 80200",
                    "release/v0802-build-ready.txt",
                    "scripts/apply-v0802-ocr-ipc.py",
                    "NKTouch-v0.8.2-frame-ipc-rootless",
                    "tests/test_v0802_ocr_ipc.py"):
            self.assertIn(val,wf)
        self.assertNotIn("publish-sileo",wf)

if __name__=="__main__": unittest.main()
