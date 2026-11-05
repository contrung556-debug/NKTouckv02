#!/usr/bin/env bash
# NKTouch v0.7.19 Five-Core Test Lab integration (artifact only).
set -euo pipefail
[[ $# -eq 1 ]] || { echo 'usage: prepare-v0719-release.sh <staged-upstream>' >&2; exit 2; }
SRC="$1"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
test -d "$SRC"
bash "$ROOT/scripts/prepare-v0718-release.sh" "$SRC"

LIB="$SRC/layout/usr/share/nktouch/lua"
CTL="$SRC/layout/usr/bin/nktouchctl"
UI="$SRC/zxtouch/zxtouch/Settings/SettingsPageViewController.m"
CONTROL="$SRC/control"
VERSION="$SRC/layout/usr/share/doc/nktouch/VERSION"

python3 - "$CONTROL" "$VERSION" "$CTL" "$UI" "$LIB/nktestlab.lua" <<'PY'
from pathlib import Path
import sys
control,version,ctl,ui,lab=map(Path,sys.argv[1:])
def exact(p,old,new):
    s=p.read_text()
    n=s.count(old)
    if n!=1: raise SystemExit(f"{p}: expected one {old!r}, found {n}")
    p.write_text(s.replace(old,new,1))

exact(control,'Version: 0.7.18','Version: 0.7.19')
s=control.read_text()
s=s.replace(
'Description: NKTouch v0.7.18 Vision OCR CIImage/revision2 compatibility beta (device validation pending); retains v0.7.17 Memory Core and InputText',
'Description: NKTouch v0.7.19 Five-Core Test Lab (OCR Color Touch InputText Memory), detailed PASS/FAIL/WARN logs and reports; read-only default, device validation pending')
control.write_text(s)
exact(ctl,'PACKAGE_VERSION="0.7.18"','PACKAGE_VERSION="0.7.19"')
exact(version,'NKTouch 0.7.18 Vision OCR Compatibility Beta',
              'NKTouch 0.7.19 Five-Core Test Lab Beta')
with version.open("a") as f:
    f.write("""
v0.7.19: Five-core Lab quick preset with separate native-frame/live OCR
diagnostics and bounded 10-30 Vision frame/RSS checks. Prior seven groups
remain selectable. Touch and InputText are read-only preflight by default;
interactive dispatch remains double-opt-in and foreground-guarded. One
atomic JSON report with PASS/FAIL/WARN/SKIP details plus Task Center logs.
Not certified for physical iPhone touch or OCR until device testing.
""")
s=ui.read_text().replace('NKTouch 0.7.18','NKTouch 0.7.19')
s=s.replace('nkLabel:@"0.7.18"','nkLabel:@"0.7.19"')
s=s.replace('text:@"0.7.18"','text:@"0.7.19"')
s=s.replace('Test Lab • 7 nhóm','Test Lab • 5 lõi + nâng cao')
s=s.replace('7 nhóm lệnh • kiểm tra an toàn','5 nhóm lõi • 4 nhóm nâng cao')
ui.write_text(s)
exact(lab,'-- NKTouch Test Lab v0.7.18-dev',
          '-- NKTouch Test Lab v0.7.19-dev')
exact(lab,'local M={VERSION="0.7.18-dev"}',
          'local M={VERSION="0.7.19-dev"}')
PY

grep -Fxq 'Version: 0.7.19' "$CONTROL"
grep -Fq 'PACKAGE_VERSION="0.7.19"' "$CTL"
grep -Fq 'NKTouch 0.7.19 Five-Core Test Lab Beta' "$VERSION"
grep -Fq 'NKTouch Test Lab v0.7.19-dev' "$LIB/nktestlab.lua"
grep -Fq 'handlers.ocr=function()' "$LIB/nktestlab.lua"
grep -Fq 'handlers.memory=function()' "$LIB/nktestlab.lua"
grep -Fq 'labSelectCorePreset' "$UI"
grep -Fq 'memory={loops=10}' "$UI"
grep -Fq 'Test Lab • 5 lõi + nâng cao' "$UI"
test ! -e "$SRC/layout/var/jb"
echo 'NKTouch v0.7.19 Five-Core Test Lab staged; artifact only, no Sileo publication'
