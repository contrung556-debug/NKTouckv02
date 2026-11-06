#!/usr/bin/env bash
# NKTouch 0.8.11 Vision State Stability overlay after v0.8.10.
# Candidate source only; keep stable Sileo release untouched.
set -euo pipefail
[[ $# -eq 1 ]] || { echo 'usage: stage-v0811-vision-state.sh <staged-upstream>' >&2; exit 2; }
SRC="$1"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LIB="$SRC/layout/usr/share/nktouch/lua"
EXAMPLES="$SRC/layout/usr/share/nktouch/examples"
CONTROL="$SRC/control"
CTL="$SRC/layout/usr/bin/nktouchctl"
VERSION="$SRC/layout/usr/share/doc/nktouch/VERSION"
UI="$SRC/zxtouch/zxtouch/Settings/SettingsPageViewController.m"
LAB="$LIB/nktestlab.lua"
for p in "$CONTROL" "$CTL" "$VERSION" "$UI" "$LAB" "$LIB/nktouch.lua" "$SRC/layout/usr/bin/nktask"; do test -s "$p"; done
grep -Fxq 'Version: 0.8.10' "$CONTROL"
grep -Fq 'PACKAGE_VERSION="0.8.10"' "$CTL"
grep -Fq 'NKTouch Test Lab v0.8.10-beta' "$LAB"
mkdir -p "$LIB" "$EXAMPLES"
install -m 0644 "$ROOT/lua/nkvision_state.lua" "$LIB/nkvision_state.lua"
install -m 0644 "$ROOT/examples/test_vision_state_v0811.lua" "$EXAMPLES/test_vision_state_v0811.lua"

python3 - "$CONTROL" "$CTL" "$VERSION" "$UI" "$LAB" "$LIB/nktouch.lua" <<'PY'
from pathlib import Path
import sys
control,ctl,version,ui,lab,api=map(Path,sys.argv[1:])
def exactly(path,old,new):
    data=path.read_text()
    if data.count(old)!=1:
        raise SystemExit(f"{path}: expected one {old!r}, got {data.count(old)}")
    path.write_text(data.replace(old,new,1))
exactly(control,"Version: 0.8.10","Version: 0.8.11")
exactly(control,
  "Description: NKTouch v0.8.10 Runtime Self-Test beta: Lua and io.popen diagnostics with read-only cranectl list sample; retains v0.8.9 Runtime, Vision, Native Input and Precision",
  "Description: NKTouch v0.8.11 Vision State Stability beta: Vietnamese OCR normalization and bounded stable-label wait; retains Runtime Self-Test, Vision, Native Input and Precision")
exactly(ctl,'PACKAGE_VERSION="0.8.10"','PACKAGE_VERSION="0.8.11"')
exactly(version,"NKTouch 0.8.10 Runtime Self-Test Beta",
                "NKTouch 0.8.11 Vision State Stability Beta")
with version.open("a") as out:
    out.write("""
v0.8.11: bounded live-OCR state gate with Vietnamese diacritic and common
OCR-substitution normalization. Requires repeated matching labels; reports
ambiguous/uncertain states without exposing OCR text. Read-only sample only.
No tap, InputText, app launch or account submission. Device validation pending.
""")
exactly(lab,'-- NKTouch Test Lab v0.8.10-beta',
            '-- NKTouch Test Lab v0.8.11-beta')
exactly(lab,'local M={VERSION="0.8.10-beta"}',
            'local M={VERSION="0.8.11-beta"}')
api_src=api.read_text()
anchor='function M.runScript(path,...)\n'
if api_src.count(anchor)!=1: raise SystemExit("public runScript anchor changed")
methods='''-- v0.8.11 read-only live OCR state gate.
M.VISION_STATE_VERSION="0.8.11-beta"
function M.normalizeOCR(text)
  return require("nkvision_state").normalize(text)
end
function M.waitForOCRState(options)
  return require("nkvision_state").waitFor(M,options)
end

'''
api.write_text(api_src.replace(anchor,methods+anchor,1))
src=ui.read_text()
src=src.replace("NKTouch 0.8.10","NKTouch 0.8.11")
src=src.replace('nkLabel:@"0.8.10"','nkLabel:@"0.8.11"')
src=src.replace('text:@"0.8.10"','text:@"0.8.11"')
src=src.replace('-- NKTouch Test Lab v0.8.10-beta','-- NKTouch Test Lab v0.8.11-beta')
installer='@{@"file":@"test_runtime_selftest_v0810.lua", @"bundle":@"com.apple.mobilenotes"}'
menu='@{@"title":@"Runtime • Tự kiểm tra Lua / io.popen", @"file":@"test_runtime_selftest_v0810.lua"}'
if src.count(installer)!=1: raise SystemExit("v0.8.10 Samples installer changed")
if src.count(menu)!=1: raise SystemExit("v0.8.10 Samples menu changed")
src=src.replace(installer,
    '@{@"file":@"test_vision_state_v0811.lua", @"bundle":@"com.apple.mobilenotes"},\n        '+installer,1)
src=src.replace(menu,
    '@{@"title":@"Vision • OCR trạng thái ổn định", @"file":@"test_vision_state_v0811.lua"},\n        '+menu,1)
ui.write_text(src)
PY
grep -Fxq 'Version: 0.8.11' "$CONTROL"
grep -Fq 'PACKAGE_VERSION="0.8.11"' "$CTL"
grep -Fq 'function M.waitForOCRState(options)' "$LIB/nktouch.lua"
grep -Fq 'test_vision_state_v0811.lua' "$UI"
grep -Fq 'Vision • OCR trạng thái ổn định' "$UI"
test -s "$EXAMPLES/test_vision_state_v0811.lua"
test -s "$LIB/nkvision_state.lua"
test ! -e "$SRC/layout/var/jb"
echo '[NKVISION811] staged bounded read-only OCR state gate; Sileo unchanged'
