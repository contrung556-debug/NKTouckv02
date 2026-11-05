#!/usr/bin/env bash
# NKTouch v0.8.1 OCR buffer compatibility beta; overlay on known-good 0.8.0.
# Never auto-publish to Sileo. This fixes code paths, not proven device behavior.
set -euo pipefail
[[ $# -eq 1 ]] || { echo 'usage: prepare-v0801-release.sh <staged-upstream>' >&2; exit 2; }
SRC="$1"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
test -d "$SRC"
bash "$ROOT/scripts/prepare-v0800-release.sh" "$SRC"

LIB="$SRC/layout/usr/share/nktouch/lua"
CTL="$SRC/layout/usr/bin/nktouchctl"
UI="$SRC/zxtouch/zxtouch/Settings/SettingsPageViewController.m"
CONTROL="$SRC/control"
VERSION="$SRC/layout/usr/share/doc/nktouch/VERSION"
EXAMPLES="$SRC/layout/usr/share/nktouch/examples"

python3 - "$CONTROL" "$VERSION" "$CTL" "$UI" "$LIB/nktestlab.lua" <<'PY'
from pathlib import Path
import sys
control,version,ctl,ui,lab=map(Path,sys.argv[1:])
def exact(path,old,new):
    source=path.read_text()
    n=source.count(old)
    if n!=1:
        raise SystemExit(f"{path}: {old!r} expected exactly once, got {n}")
    path.write_text(source.replace(old,new,1))

exact(control,"Version: 0.8.0","Version: 0.8.1")
exact(control,"Description: NKTouch v0.8.0 Integrated Lua SDK beta: Test Lab OCR Color Touch InputText Memory, diagnostics, snapshot batching, safe actions and reports; device validation pending",
              "Description: NKTouch v0.8.1 same-frame OCR CVPixelBuffer compatibility beta (JPEG/ROI/rev1/CPU fallback), retains Integrated Lua SDK; device OCR fix unverified")
exact(ctl,'PACKAGE_VERSION="0.8.0"','PACKAGE_VERSION="0.8.1"')
exact(version,"NKTouch 0.8.0 Integrated Lua SDK Beta",
              "NKTouch 0.8.1 OCR CVPixelBuffer Compatibility Beta")
with version.open("a") as f:
    f.write("""
v0.8.1 beta: on-device v0.8.0 Test Lab showed native OCR failing to
allocate 420f CVPixelBuffer (-6662), despite separate live OCR succeeding.
Preserve immutable JPEG in each frame and all old Vision APIs. Add third
VNImageRequestHandler initWithData compatibility path with normalized
bottom-left ROI, older text-recognition revision and CPU-only/fast mode.
Never recapture for frame OCR; do not claim live OCR means same-frame PASS.
This is a hypothesis to test on real iPhone, NOT a confirmed -6662 fix.
""")
uiSrc=ui.read_text()
uiSrc=uiSrc.replace("NKTouch 0.8.0","NKTouch 0.8.1")
uiSrc=uiSrc.replace('nkLabel:@"0.8.0"','nkLabel:@"0.8.1"')
uiSrc=uiSrc.replace('text:@"0.8.0"','text:@"0.8.1"')
uiSrc=uiSrc.replace("-- NKTouch Test Lab v0.8.0-beta","-- NKTouch Test Lab v0.8.1-beta")
ui.write_text(uiSrc)
exact(lab,"-- NKTouch Test Lab v0.8.0-beta",
          "-- NKTouch Test Lab v0.8.1-beta")
exact(lab,'local M={VERSION="0.8.0-beta"}',
          'local M={VERSION="0.8.1-beta"}')
PY

mkdir -p "$EXAMPLES"
install -m 0644 "$ROOT/examples/test_ocr_sameframe_0801.lua" \
  "$EXAMPLES/test_ocr_sameframe_0801.lua"
grep -Fxq 'Version: 0.8.1' "$CONTROL"
grep -Fq 'PACKAGE_VERSION="0.8.1"' "$CTL"
grep -Fq 'NKTouch 0.8.1 OCR CVPixelBuffer Compatibility Beta' "$VERSION"
grep -Fq 'NKTouch Test Lab v0.8.1-beta' "$LIB/nktestlab.lua"
test -s "$EXAMPLES/test_ocr_sameframe_0801.lua"
test -s "$LIB/nksdk.lua"
test ! -e "$SRC/layout/var/jb"
echo 'NKTouch v0.8.1 OCR source staged; no Sileo publishing'
