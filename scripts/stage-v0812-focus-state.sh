#!/usr/bin/env bash
# Stage v0.8.12 focus reliability on top of the v0.8.11 vision-state overlay.
set -euo pipefail
[[ $# -eq 1 ]] || { echo 'usage: stage-v0812-focus-state.sh <staged-upstream>' >&2; exit 2; }
SRC="$1"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LIB="$SRC/layout/usr/share/nktouch/lua"
EXAMPLES="$SRC/layout/usr/share/nktouch/examples"
CONTROL="$SRC/control"
CTL="$SRC/layout/usr/bin/nktouchctl"
VERSION="$SRC/layout/usr/share/doc/nktouch/VERSION"
UI="$SRC/zxtouch/zxtouch/Settings/SettingsPageViewController.m"
LAB="$LIB/nktestlab.lua"
for p in "$CONTROL" "$CTL" "$VERSION" "$UI" "$LAB" "$LIB/nktouch.lua"; do test -s "$p"; done
grep -Fxq 'Version: 0.8.11' "$CONTROL"
grep -Fq 'PACKAGE_VERSION="0.8.11"' "$CTL"
grep -Fq 'NKTouch Test Lab v0.8.11-beta' "$LAB"
grep -Fq 'function M.waitForOCRState(options)' "$LIB/nktouch.lua"
mkdir -p "$LIB" "$EXAMPLES"
install -m 0644 "$ROOT/lua/nkfocus_state.lua" "$LIB/nkfocus_state.lua"
install -m 0644 "$ROOT/examples/test_focus_state_v0812.lua" "$EXAMPLES/test_focus_state_v0812.lua"

python3 - "$CONTROL" "$CTL" "$VERSION" "$UI" "$LAB" "$LIB/nktouch.lua" <<'PY'
from pathlib import Path
import sys
control,ctl,version,ui,lab,api=map(Path,sys.argv[1:])
def exactly(path,old,new):
    data=path.read_text(); count=data.count(old)
    if count!=1: raise SystemExit(f"{path}: expected one {old!r}, got {count}")
    path.write_text(data.replace(old,new,1))
exactly(control,"Version: 0.8.11","Version: 0.8.12")
exactly(control,
  "Description: NKTouch v0.8.11 Vision State Stability beta: Vietnamese OCR normalization and bounded stable-label wait; retains Runtime Self-Test, Vision, Native Input and Precision",
  "Description: NKTouch v0.8.12 OCR State + Native Focus Reliability beta: stable Vietnamese OCR labels and bounded first-responder gate; retains Runtime, Vision, Native Input and Precision")
exactly(ctl,'PACKAGE_VERSION="0.8.11"','PACKAGE_VERSION="0.8.12"')
exactly(version,"NKTouch 0.8.11 Vision State Stability Beta",
                "NKTouch 0.8.12 OCR State + Native Focus Reliability Beta")
with version.open("a") as out:
    out.write("""
v0.8.12 adds a bounded read-only native first-responder state gate. It requires
repeated confirmed focus, returns explicit uncertainty codes, and never types,
taps, launches apps, or retries mutations. Device validation pending.
""")
exactly(lab,'-- NKTouch Test Lab v0.8.11-beta',
            '-- NKTouch Test Lab v0.8.12-beta')
exactly(lab,'local M={VERSION="0.8.11-beta"}',
            'local M={VERSION="0.8.12-beta"}')
api_src=api.read_text()
if api_src.count('function M.waitForOCRState(options)')!=1:
    raise SystemExit("v0.8.11 public OCR API anchor changed")
anchor='function M.runScript(path,...)\n'
if api_src.count(anchor)!=1: raise SystemExit("public runScript anchor changed")
methods='''-- v0.8.12 bounded, read-only native first-responder gate.
M.FOCUS_STATE_VERSION="0.8.12-beta"
function M.waitForInputFocus(options)
  return require("nkfocus_state").waitFor(M,options)
end

'''
api.write_text(api_src.replace(anchor,methods+anchor,1))
src=ui.read_text()
for old,new in (("NKTouch 0.8.11","NKTouch 0.8.12"),
                ('nkLabel:@"0.8.11"','nkLabel:@"0.8.12"'),
                ("-- NKTouch Test Lab v0.8.11-beta","-- NKTouch Test Lab v0.8.12-beta")):
    if old not in src: raise SystemExit(f"UI version marker missing: {old}")
    src=src.replace(old,new)
installer='@{@"file":@"test_vision_state_v0811.lua", @"bundle":@"com.apple.mobilenotes"}'
menu='@{@"title":@"Vision • OCR trạng thái ổn định", @"file":@"test_vision_state_v0811.lua"}'
if src.count(installer)!=1 or src.count(menu)!=1:
    raise SystemExit("v0.8.11 Sample Lab registry changed")
src=src.replace(installer,
    '@{@"file":@"test_focus_state_v0812.lua", @"bundle":@"com.apple.mobilenotes"},\n        '+installer,1)
src=src.replace(menu,
    '@{@"title":@"Input • Focus ổn định (read-only)", @"file":@"test_focus_state_v0812.lua"},\n        '+menu,1)
ui.write_text(src)
PY

grep -Fxq 'Version: 0.8.12' "$CONTROL"
grep -Fq 'PACKAGE_VERSION="0.8.12"' "$CTL"
grep -Fq 'function M.waitForOCRState(options)' "$LIB/nktouch.lua"
grep -Fq 'function M.waitForInputFocus(options)' "$LIB/nktouch.lua"
grep -Fq 'Input • Focus ổn định (read-only)' "$UI"
test -s "$EXAMPLES/test_vision_state_v0811.lua"
test -s "$EXAMPLES/test_focus_state_v0812.lua"
test -s "$LIB/nkvision_state.lua"
test -s "$LIB/nkfocus_state.lua"
test ! -e "$SRC/layout/var/jb"
echo '[NKFOCUS812] staged OCR-state + bounded read-only native focus gate'
