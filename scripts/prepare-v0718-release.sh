#!/usr/bin/env bash
# NKTouch v0.7.18 OCR CIImage compatibility candidate. Artifact-only until device test.
set -euo pipefail
[[ $# -eq 1 ]] || { echo 'usage: prepare-v0718-release.sh <staged-upstream>' >&2; exit 2; }
SRC="$1"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
test -d "$SRC"
bash "$ROOT/scripts/prepare-v0717-release.sh" "$SRC"

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
def strict_replace(path,old,new):
    s=path.read_text()
    n=s.count(old)
    if n!=1: raise SystemExit(f'{path}: expected one {old!r}, found {n}')
    path.write_text(s.replace(old,new,1))

strict_replace(control,'Version: 0.7.17','Version: 0.7.18')
s=control.read_text()
s=s.replace(
 'Description: NKTouch v0.7.17 Stability and Memory Core beta (device crash/RSS verification pending); retains InputText and seven-group Test Lab',
 'Description: NKTouch v0.7.18 Vision OCR CIImage/revision2 compatibility beta (device validation pending); retains v0.7.17 Memory Core and InputText')
control.write_text(s)
strict_replace(ctl,'PACKAGE_VERSION="0.7.17"','PACKAGE_VERSION="0.7.18"')
strict_replace(version,'NKTouch 0.7.17 Stability and Memory Core Beta',
 'NKTouch 0.7.18 Vision OCR Compatibility Beta')
with version.open('a') as f:
    f.write("""
v0.7.18: On immutable frames, OCR first attempts CIImage+revision2 for
compatibility with existing live OCR implementation, then CGImage as a
read-only fallback. On error returns Vision NSError domain/code safely.
No new capture, tap or text injection; device validation still required.
""")
s=ui.read_text().replace('NKTouch 0.7.17','NKTouch 0.7.18')
s=s.replace('nkLabel:@"0.7.17"','nkLabel:@"0.7.18"')
s=s.replace('text:@"0.7.17"','text:@"0.7.18"')
ui.write_text(s)
strict_replace(lab,'-- NKTouch Test Lab v0.7.17-dev',
                      '-- NKTouch Test Lab v0.7.18-dev')
strict_replace(lab,'local M={VERSION="0.7.17-dev"}',
                      'local M={VERSION="0.7.18-dev"}')
PY
mkdir -p "$EXAMPLES"
install -m 0644 "$ROOT/examples/test_v0717_ocr_diagnostics_readonly.lua" "$EXAMPLES/test_v0717_ocr_diagnostics_readonly.lua"
install -m 0644 "$ROOT/examples/test_v0717_memory_ocr_readonly.lua" "$EXAMPLES/test_v0717_memory_ocr_readonly.lua"
grep -Fxq 'Version: 0.7.18' "$CONTROL"
grep -Fq 'PACKAGE_VERSION="0.7.18"' "$CTL"
grep -Fq 'NKTouch 0.7.18 Vision OCR Compatibility Beta' "$VERSION"
grep -Fq 'NKTouch Test Lab v0.7.18-dev' "$LIB/nktestlab.lua"
test -s "$EXAMPLES/test_v0717_ocr_diagnostics_readonly.lua"
test -s "$EXAMPLES/test_v0717_memory_ocr_readonly.lua"
test ! -e "$SRC/layout/var/jb"
echo 'NKTouch v0.7.18 OCR beta staged; build artifact only, no Sileo publication'
