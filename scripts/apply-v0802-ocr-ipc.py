#!/usr/bin/env python3
"""Install the one-frame JPEG OCR IPC handler in pinned upstream ZXTouch.

No arbitrary path access; caller sends bounded base64 JPEG bytes, server
decodes only in memory, and Vision executes in existing OCR service.
"""
from pathlib import Path
import sys

def replace_once(path: Path, before: str, after: str):
    s=path.read_text()
    count=s.count(before)
    if count!=1:
        raise SystemExit(f"{path}: expected exactly one injection anchor, got {count}")
    path.write_text(s.replace(before,after,1))

def main():
    if len(sys.argv)!=2:
        raise SystemExit("usage: apply-v0802-ocr-ipc.py <upstream checkout>")
    root=Path(__file__).resolve().parents[1]
    up=Path(sys.argv[1]).resolve()
    task=up/"pccontrol/Task.xm"
    header=up/"pccontrol/Task.h"
    makefile=up/"pccontrol/Makefile"
    for p in (task,header,makefile):
        if not p.is_file(): raise SystemExit(f"Missing pinned upstream file: {p}")

    replace_once(header,
                 "#define TASK_SCREENSHOT 30",
                 "#define TASK_SCREENSHOT 30\n#define TASK_NK_FRAME_OCR 31")
    replace_once(task,
                 "#include <TextRecognization/TextRecognizer.h>",
                 '#include <TextRecognization/TextRecognizer.h>\n'
                 '#import <TextRecognization/VKOcrManager.h>\n'
                 '#import <ImageIO/ImageIO.h>')
    include=(root/"patches/NKFrameOCRTask.xm.inc").read_text()
    if not include.strip().startswith("else if (taskType == TASK_NK_FRAME_OCR)"):
        raise SystemExit("Frame OCR task snippet invalid")
    replace_once(task,
                 "    else if (taskType == TASK_COLOR_SEARCHER)",
                 include + "    else if (taskType == TASK_COLOR_SEARCHER)")
    replace_once(makefile,
                 "pccontrol_FRAMEWORKS = UIKit AssetsLibrary",
                 "pccontrol_FRAMEWORKS = Vision CoreImage ImageIO UIKit AssetsLibrary")
    final=task.read_text()
    for marker in (
        "TASK_NK_FRAME_OCR",
        "initWithBase64EncodedString:encoded options:0",
        "initWithCGImage:image",
        "NK_FRAME_OCR_UNAVAILABLE",
        "notifyClient((UInt8 *)[reply UTF8String],writeStreamRef)",
    ):
        if marker not in final:
            raise SystemExit(f"Injected OCR missing {marker}")
    # The new branch cannot invent an extra screenshot or access arbitrary
    # files from SpringBoard based on untrusted client input.
    if ("Screen createScreenShotCGImageRef" in include or
        "dataWithContentsOfFile:" in include or
        "writeToFile:" in include):
        raise SystemExit("Frame OCR IPC must not recapture/read/write files")
    print("NKTouch v0.8.2 existing-frame OCR IPC task installed; no Sileo publication")

if __name__=="__main__":
    main()
