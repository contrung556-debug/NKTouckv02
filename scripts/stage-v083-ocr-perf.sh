#!/usr/bin/env bash
# v0.8.3 OCR Performance Lab overlay on the VERIFIED v0.8.2 SpringBoard IPC.
# This script MUST run after prepare-v0802-release.sh and apply-v0802-ocr-ipc.py.
# Artifact only: no automatic Sileo publish, no touch/keyboard behavior changes.
set -euo pipefail
[[ $# -eq 1 ]] || { echo 'usage: stage-v083-ocr-perf.sh <staged-upstream>' >&2; exit 2; }
SRC="$1"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LIB="$SRC/layout/usr/share/nktouch/lua"
EXAMPLES="$SRC/layout/usr/share/nktouch/examples"
CONTROL="$SRC/control"
CTL="$SRC/layout/usr/bin/nktouchctl"
VERSION="$SRC/layout/usr/share/doc/nktouch/VERSION"
UI="$SRC/zxtouch/zxtouch/Settings/SettingsPageViewController.m"
LAB="$LIB/nktestlab.lua"
test -f "$CONTROL" && test -f "$CTL" && test -f "$UI" && test -f "$LAB"
grep -Fxq 'Version: 0.8.2' "$CONTROL"
grep -Fq 'PACKAGE_VERSION="0.8.2"' "$CTL"
grep -Fq 'NKTouch Test Lab v0.8.2-beta' "$LAB"
mkdir -p "$LIB" "$EXAMPLES"
install -m 0644 "$ROOT/lua/nkocr_perf.lua" "$LIB/nkocr_perf.lua"
install -m 0644 "$ROOT/examples/test_ocr_perf_v083.lua" "$EXAMPLES/test_ocr_perf_v083.lua"
install -m 0644 "$ROOT/examples/test_ocr_stability_v083.lua" "$EXAMPLES/test_ocr_stability_v083.lua"
python3 - "$CONTROL" "$CTL" "$VERSION" "$UI" "$LAB" <<'PY'
from pathlib import Path
import sys
control,ctl,version,ui,lab=map(Path,sys.argv[1:])
def once(path,old,new):
    source=path.read_text()
    count=source.count(old)
    if count!=1:
        raise SystemExit(f"{path}: expected one {old!r}, found {count}")
    path.write_text(source.replace(old,new,1))
once(control,"Version: 0.8.2","Version: 0.8.3")
once(control,
     "Description: NKTouch v0.8.2 same-JPEG OCR IPC beta: immutable frame sent to existing SpringBoard Vision service; device validation pending",
     "Description: NKTouch v0.8.3 OCR performance and stability experimental beta; retains validated v0.8.2 same-frame SpringBoard OCR IPC")
once(ctl,'PACKAGE_VERSION="0.8.2"','PACKAGE_VERSION="0.8.3"')
once(version,"NKTouch 0.8.2 Same-Frame OCR IPC Beta",
             "NKTouch 0.8.3 OCR Performance and Stability Beta")
with version.open("a") as output:
    output.write("""
v0.8.3 opt-in read-only OCR performance diagnostics: bounded 3..20 same-frame
measurements with a monotonic clock, optional separate live OCR series, and
0/10/50/100-frame memory telemetry. Two-frame nine-point screen-stability
heuristic never OCRs until sampled pixels are stable; it is NOT a proof that
an animation/spinner stopped. No OCR result strings are logged by examples.
v0.8.2 IPC / Touch / Input / Color engines unchanged. Device tests pending.
""")
s=ui.read_text()
s=s.replace("NKTouch 0.8.2","NKTouch 0.8.3")
s=s.replace('nkLabel:@"0.8.2"','nkLabel:@"0.8.3"')
s=s.replace('text:@"0.8.2"','text:@"0.8.3"')
s=s.replace("-- NKTouch Test Lab v0.8.2-beta","-- NKTouch Test Lab v0.8.3-beta")
# Append to the existing consolidated Samples menu, never create new cards.
# The initial-copy installer checks !fileExists, so user-edited Lua is safe.
installer='@{@"file":@"test_gestures_optin.lua"}'
if s.count(installer)!=1:
    raise SystemExit("v0.8.3 expected one Samples installer anchor")
s=s.replace(installer,
    '@{@"file":@"test_ocr_perf_v083.lua", @"bundle":@"com.apple.mobilesafari"},\n'
    '        @{@"file":@"test_ocr_stability_v083.lua", @"bundle":@"com.apple.mobilesafari"},\n'
    '        '+installer,1)
menu='@{@"title":@"Tap / Hold / Swipe • tuỳ chọn", @"file":@"test_gestures_optin.lua"}'
if s.count(menu)!=1:
    raise SystemExit("v0.8.3 expected one consolidated Samples menu anchor")
s=s.replace(menu,
    '@{@"title":@"OCR • Benchmark 10 lần", @"file":@"test_ocr_perf_v083.lua"},\n'
    '        @{@"title":@"OCR • Kiểm tra màn hình ổn định", @"file":@"test_ocr_stability_v083.lua"},\n'
    '        '+menu,1)
ui.write_text(s)
once(lab,"-- NKTouch Test Lab v0.8.2-beta",
         "-- NKTouch Test Lab v0.8.3-beta")
once(lab,'local M={VERSION="0.8.2-beta"}',
         'local M={VERSION="0.8.3-beta"}')
PY
grep -Fxq 'Version: 0.8.3' "$CONTROL"
grep -Fq 'PACKAGE_VERSION="0.8.3"' "$CTL"
grep -Fq 'NKTouch Test Lab v0.8.3-beta' "$LAB"
grep -Fq 'NKTouch 0.8.3 OCR Performance' "$VERSION"
test -s "$LIB/nkocr_perf.lua"
test -s "$EXAMPLES/test_ocr_perf_v083.lua"
test -s "$EXAMPLES/test_ocr_stability_v083.lua"
test ! -e "$SRC/layout/var/jb"
echo 'Staged NKTouch v0.8.3 OCR Performance candidate; Sileo source untouched'
