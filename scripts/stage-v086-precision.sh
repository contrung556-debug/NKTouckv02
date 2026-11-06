#!/usr/bin/env bash
# NKTouch v0.8.6 Touch & Color Precision overlay after v0.8.5.
# Candidate artifact only; must NOT auto-publish Sileo.
set -euo pipefail
[[ $# -eq 1 ]] || { echo 'usage: stage-v086-precision.sh <upstream>' >&2; exit 2; }
SRC="$1"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LIB="$SRC/layout/usr/share/nktouch/lua"
EXAMPLES="$SRC/layout/usr/share/nktouch/examples"
CONTROL="$SRC/control"
CTL="$SRC/layout/usr/bin/nktouchctl"
VERSION="$SRC/layout/usr/share/doc/nktouch/VERSION"
UI="$SRC/zxtouch/zxtouch/Settings/SettingsPageViewController.m"
LAB="$LIB/nktestlab.lua"
for path in "$CONTROL" "$CTL" "$VERSION" "$UI" "$LAB" "$LIB/nktouch.lua" "$LIB/nkcoords.lua" "$LIB/nkinput_pro.lua"; do
  test -s "$path"
done
grep -Fxq 'Version: 0.8.5' "$CONTROL"
grep -Fq 'PACKAGE_VERSION="0.8.5"' "$CTL"
grep -Fq 'NKTouch Test Lab v0.8.5-beta' "$LAB"
grep -Fq 'function M.inputFast(value,options)' "$LIB/nktouch.lua"
grep -Fq 'function M.inputSafe(value,options)' "$LIB/nktouch.lua"
grep -Fq 'function M.captureFrame()' "$LIB/nktouch.lua"
mkdir -p "$LIB" "$EXAMPLES"
install -m 0644 "$ROOT/lua/nkprecision.lua" "$LIB/nkprecision.lua"
install -m 0644 "$ROOT/examples/test_precision_colors_v086.lua" "$EXAMPLES/test_precision_colors_v086.lua"
install -m 0644 "$ROOT/examples/test_precision_touch_v086.lua" "$EXAMPLES/test_precision_touch_v086.lua"

python3 - "$CONTROL" "$CTL" "$VERSION" "$UI" "$LAB" "$LIB/nktouch.lua" <<'PY'
from pathlib import Path
import sys
control,ctl,version,ui,lab,api=map(Path,sys.argv[1:])
def exactly(path,old,new):
    s=path.read_text()
    if s.count(old)!=1: raise SystemExit(f"{path}: expected one {old!r}; found {s.count(old)}")
    path.write_text(s.replace(old,new,1))
exactly(control,'Version: 0.8.5','Version: 0.8.6')
exactly(control,
  'Description: NKTouch v0.8.5 Input Engine Pro beta: one-packet native Fast Input, guarded Safe Input and explicit Keyboard mode; retains v0.8.3 OCR performance diagnostics',
  'Description: NKTouch v0.8.6 Touch Color Precision beta: same-frame multi-point RGB guards, validated pixel geometry, opt-in guarded touch; retains Native Input Pro and OCR diagnostics')
exactly(ctl,'PACKAGE_VERSION="0.8.5"','PACKAGE_VERSION="0.8.6"')
exactly(version,'NKTouch 0.8.5 Native Input Engine Pro Beta',
                'NKTouch 0.8.6 Touch Color Precision Beta')
with version.open('a') as out:
    out.write("""
v0.8.6: one captured frame per pixel-pattern inspection; verifies native
frame geometry matches physical screen, all RGB values are valid and
packed colors agree. Optional region search validates returned hit.
Touch dispatch requires enabled+confirmed and correct app before and
after frame. Only one touch per request, no auto-retry and no OCR.
A correct frame or native dispatch ACK does not prove actual UI success.
Retains v0.8.5 Native Input Pro, v0.8.3 OCR, Lua 5.4 compatibility.
Device tests still required; this is an artifact-only candidate.
""")
exactly(lab,'-- NKTouch Test Lab v0.8.5-beta',
            '-- NKTouch Test Lab v0.8.6-beta')
exactly(lab,'local M={VERSION="0.8.5-beta"}',
            'local M={VERSION="0.8.6-beta"}')
anchor='function M.inputPassword(value,options)\n'
methods='''-- v0.8.6: frame-synchronized, strict physical-pixel precision.
M.PRECISION_VERSION="0.8.6-beta"
function M.precisionInspect(options)
  return require("nkprecision").inspect(M,options)
end
function M.precisionFind(options)
  return require("nkprecision").find(M,options)
end
function M.precisionTapIfMatch(options)
  return require("nkprecision").tapIfMatch(M,options)
end
function M.precisionTapIfFound(options)
  return require("nkprecision").tapIfFound(M,options)
end
'''
exactly(api,anchor,methods+anchor)
s=ui.read_text()
s=s.replace('NKTouch 0.8.5','NKTouch 0.8.6')
s=s.replace('nkLabel:@"0.8.5"','nkLabel:@"0.8.6"')
s=s.replace('text:@"0.8.5"','text:@"0.8.6"')
s=s.replace('-- NKTouch Test Lab v0.8.5-beta','-- NKTouch Test Lab v0.8.6-beta')
installer='@{@"file":@"test_input_safe_v085.lua", @"bundle":@"com.apple.mobilenotes"}'
menu='@{@"title":@"Input Pro • Safe", @"file":@"test_input_safe_v085.lua"}'
assert s.count(installer)==1, "v0.8.5 Samples installer changed"
assert s.count(menu)==1, "v0.8.5 Samples menu changed"
s=s.replace(installer,
  '@{@"file":@"test_precision_colors_v086.lua", @"bundle":@"com.apple.mobilenotes"},\n'
  '        @{@"file":@"test_precision_touch_v086.lua", @"bundle":@"com.apple.mobilenotes"},\n'
  '        '+installer,1)
s=s.replace(menu,
  '@{@"title":@"Color • Nhiều điểm / 1 frame", @"file":@"test_precision_colors_v086.lua"},\n'
  '        @{@"title":@"Touch • Chạm khi khớp màu", @"file":@"test_precision_touch_v086.lua"},\n'
  '        '+menu,1)
ui.write_text(s)
PY
grep -Fxq 'Version: 0.8.6' "$CONTROL"
grep -Fq 'PACKAGE_VERSION="0.8.6"' "$CTL"
grep -Fq 'NKTouch Test Lab v0.8.6-beta' "$LAB"
grep -Fq 'function M.precisionTapIfMatch(options)' "$LIB/nktouch.lua"
grep -Fq 'function M.inputSafe(value,options)' "$LIB/nktouch.lua"
grep -Fq 'test_precision_colors_v086.lua' "$UI"
test ! -e "$SRC/layout/var/jb"
echo '[NKPRECISION] staged 0.8.6 artifact-only candidate; Sileo untouched'
