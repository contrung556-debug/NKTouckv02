#!/usr/bin/env bash
# v0.8.2 candidate: SAME-JPEG IPC to existing SpringBoard OCR service.
# Bundle only. Never publish to Sileo before device validation.
set -euo pipefail
[[ $# -eq 1 ]] || { echo 'usage: prepare-v0802-release.sh <upstream>' >&2; exit 2; }
SRC="$1"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
test -d "$SRC"
bash "$ROOT/scripts/prepare-v0801-release.sh" "$SRC"

LIB="$SRC/layout/usr/share/nktouch/lua"
CTL="$SRC/layout/usr/bin/nktouchctl"
UI="$SRC/zxtouch/zxtouch/Settings/SettingsPageViewController.m"
CONTROL="$SRC/control"
VERSION="$SRC/layout/usr/share/doc/nktouch/VERSION"

python3 - "$CONTROL" "$VERSION" "$CTL" "$UI" "$LIB/nktestlab.lua" <<'PY'
from pathlib import Path
import sys
control,version,ctl,ui,lab=map(Path,sys.argv[1:])
def exact(path,old,new):
    text=path.read_text()
    n=text.count(old)
    if n!=1: raise SystemExit(f"{path}: expected one {old!r}, got {n}")
    path.write_text(text.replace(old,new,1))
exact(control,"Version: 0.8.1","Version: 0.8.2")
exact(control,
    "Description: NKTouch v0.8.1 same-frame OCR CVPixelBuffer compatibility beta (JPEG/ROI/rev1/CPU fallback), retains Integrated Lua SDK; device OCR fix unverified",
    "Description: NKTouch v0.8.2 same-JPEG OCR IPC beta: immutable frame sent to existing SpringBoard Vision service; device validation pending")
exact(ctl,'PACKAGE_VERSION="0.8.1"','PACKAGE_VERSION="0.8.2"')
exact(version,"NKTouch 0.8.1 OCR CVPixelBuffer Compatibility Beta",
              "NKTouch 0.8.2 Same-Frame OCR IPC Beta")
with version.open("a") as f:
    f.write("""
v0.8.2 candidate. On-device v0.8.1 failed all three in-process Vision OCR
backends (NSOSStatusErrorDomain -6662), while live SpringBoard OCR succeeded.
Adds in-memory bounded base64 JPEG bridge task 31, decoding only previously
captured frame bytes in the existing OCR service. No new screenshot and no
arbitrary file read in privileged service. Old API/logic retained as fallback.
On-device SpringBoard stability, OCR accuracy and transfer latency UNVERIFIED.
""")
s=ui.read_text().replace("NKTouch 0.8.1","NKTouch 0.8.2")
s=s.replace('nkLabel:@"0.8.1"','nkLabel:@"0.8.2"')
s=s.replace('text:@"0.8.1"','text:@"0.8.2"')
s=s.replace("-- NKTouch Test Lab v0.8.1-beta","-- NKTouch Test Lab v0.8.2-beta")
ui.write_text(s)
exact(lab,"-- NKTouch Test Lab v0.8.1-beta",
          "-- NKTouch Test Lab v0.8.2-beta")
exact(lab,'local M={VERSION="0.8.1-beta"}',
          'local M={VERSION="0.8.2-beta"}')
PY
grep -Fxq 'Version: 0.8.2' "$CONTROL"
grep -Fq 'NKTouch 0.8.2 Same-Frame OCR IPC Beta' "$VERSION"
grep -Fq 'PACKAGE_VERSION="0.8.2"' "$CTL"
grep -Fq 'NKTouch Test Lab v0.8.2-beta' "$LIB/nktestlab.lua"
grep -Fq 'backend=after and after.ocr_backend' "$LIB/nktestlab.lua"
test ! -e "$SRC/layout/var/jb"
echo 'NKTouch v0.8.2 candidate staged (artifact only, no Sileo publication)'
