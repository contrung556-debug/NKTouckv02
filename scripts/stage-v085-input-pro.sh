#!/usr/bin/env bash
# NKTouch 0.8.5 Input Engine Pro overlay on the known-good v0.8.3 package.
# Must run AFTER stage-v083-ocr-perf.sh. Artifact only; no Sileo publisher.
set -euo pipefail
[[ $# -eq 1 ]] || { echo 'usage: stage-v085-input-pro.sh <staged-upstream>' >&2; exit 2; }
SRC="$1"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LIB="$SRC/layout/usr/share/nktouch/lua"
EXAMPLES="$SRC/layout/usr/share/nktouch/examples"
CONTROL="$SRC/control"
CTL="$SRC/layout/usr/bin/nktouchctl"
VERSION="$SRC/layout/usr/share/doc/nktouch/VERSION"
UI="$SRC/zxtouch/zxtouch/Settings/SettingsPageViewController.m"
LAB="$LIB/nktestlab.lua"
for p in "$LIB/nktouch.lua" "$LIB/nkinput_v2.lua" "$LAB" "$CTL" "$CONTROL" "$VERSION" "$UI"; do
  test -s "$p"
done
grep -Fxq 'Version: 0.8.3' "$CONTROL"
grep -Fq 'PACKAGE_VERSION="0.8.3"' "$CTL"
grep -Fq 'NKTouch Test Lab v0.8.3-beta' "$LAB"
grep -Fq 'function M.inputText(value,options)' "$LIB/nktouch.lua"
grep -Fq 'M.legacyInputText=M.text' "$LIB/nktouch.lua"
grep -Fq 'return M.inputTextV2(value,options)' "$LIB/nktouch.lua"
mkdir -p "$LIB" "$EXAMPLES"
install -m 0644 "$ROOT/lua/nkinput_pro.lua" "$LIB/nkinput_pro.lua"
install -m 0644 "$ROOT/examples/test_input_fast_v085.lua" "$EXAMPLES/test_input_fast_v085.lua"
install -m 0644 "$ROOT/examples/test_input_safe_v085.lua" "$EXAMPLES/test_input_safe_v085.lua"

python3 - "$CONTROL" "$CTL" "$VERSION" "$UI" "$LAB" "$LIB/nktouch.lua" <<'PY'
from pathlib import Path
import sys
control,ctl,version,ui,lab,nktouch=map(Path,sys.argv[1:])
def exactly(path,old,new):
    data=path.read_text()
    count=data.count(old)
    if count!=1:
        raise SystemExit(f"{path}: expected one {old!r}, got {count}")
    path.write_text(data.replace(old,new,1))

exactly(control,"Version: 0.8.3","Version: 0.8.5")
exactly(control,
  "Description: NKTouch v0.8.3 OCR performance and stability experimental beta; retains validated v0.8.2 same-frame SpringBoard OCR IPC",
  "Description: NKTouch v0.8.5 Input Engine Pro beta: one-packet native Fast Input, guarded Safe Input and explicit Keyboard mode; retains v0.8.3 OCR performance diagnostics")
exactly(ctl,'PACKAGE_VERSION="0.8.3"','PACKAGE_VERSION="0.8.5"')
exactly(version,"NKTouch 0.8.3 OCR Performance and Stability Beta",
                "NKTouch 0.8.5 Native Input Engine Pro Beta")
with version.open("a") as out:
    out.write("""
v0.8.5: preserve v0.8.3 OCR + ZXTouch-core compatibility.
Fast is a single direct UTF-8/native v2 packet; no OCR, screenshot or
keyboard character tapping. Safe is opt-in with foreground + coordinates
preflight, one focus tap, second foreground check, process-local onceKey
guard and NO automatic resend on delivery ambiguity. A tap does not prove
first-responder focus. Strict focus mode fails closed if native probe is
absent. Keyboard is explicit, never automatic. Device verification pending.
""")
exactly(lab,"-- NKTouch Test Lab v0.8.3-beta",
            "-- NKTouch Test Lab v0.8.5-beta")
exactly(lab,'local M={VERSION="0.8.3-beta"}',
            'local M={VERSION="0.8.5-beta"}')
src=nktouch.read_text()
anchor="function M.inputPassword(value,options)\n"
assert src.count(anchor)==1, "v0.8.5 input alias anchor mismatch"
api='''-- Input Engine Pro v0.8.5: no OCR and no implicit fallback.
M.INPUT_PRO_VERSION="0.8.5-beta"
function M.inputFast(value,options)
  return require("nkinput_pro").fast(M,value,options)
end
function M.inputSafe(value,options)
  return require("nkinput_pro").safe(M,value,options)
end
function M.inputKeyboard(value,options)
  return require("nkinput_pro").keyboard(M,value,options)
end
'''
nktouch.write_text(src.replace(anchor,api+anchor,1))
src=ui.read_text()
src=src.replace("NKTouch 0.8.3","NKTouch 0.8.5")
src=src.replace('nkLabel:@"0.8.3"','nkLabel:@"0.8.5"')
src=src.replace('text:@"0.8.3"','text:@"0.8.5"')
src=src.replace("-- NKTouch Test Lab v0.8.3-beta",
                "-- NKTouch Test Lab v0.8.5-beta")
installer='@{@"file":@"test_gestures_optin.lua"}'
menu='@{@"title":@"Tap / Hold / Swipe • tuỳ chọn", @"file":@"test_gestures_optin.lua"}'
assert src.count(installer)==1, "one built-in Samples installer required"
assert src.count(menu)==1, "one built-in Samples menu required"
src=src.replace(installer,
    '@{@"file":@"test_input_fast_v085.lua", @"bundle":@"com.apple.mobilenotes"},\n'
    '        @{@"file":@"test_input_safe_v085.lua", @"bundle":@"com.apple.mobilenotes"},\n'
    '        '+installer,1)
src=src.replace(menu,
    '@{@"title":@"Input Pro • Native Fast", @"file":@"test_input_fast_v085.lua"},\n'
    '        @{@"title":@"Input Pro • Safe", @"file":@"test_input_safe_v085.lua"},\n'
    '        '+menu,1)
ui.write_text(src)
PY
test -s "$LIB/nkinput_pro.lua"
grep -Fxq 'Version: 0.8.5' "$CONTROL"
grep -Fq 'PACKAGE_VERSION="0.8.5"' "$CTL"
grep -Fq 'NKTouch Test Lab v0.8.5-beta' "$LAB"
grep -Fq 'function M.inputSafe(value,options)' "$LIB/nktouch.lua"
grep -Fq 'return M.inputTextV2(value,options)' "$LIB/nktouch.lua"
grep -Fq 'test_input_safe_v085.lua' "$UI"
test ! -e "$SRC/layout/var/jb"
echo 'NKTouch v0.8.5 Input Engine Pro artifact-only package staged; Sileo untouched'
