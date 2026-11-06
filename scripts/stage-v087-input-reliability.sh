#!/usr/bin/env bash
# NKTouch v0.8.7 Native Input Reliability beta overlay on v0.8.6.
# ROOTLESS ARTIFACT ONLY. Never publish to Sileo from this script.
set -euo pipefail
[[ $# -eq 1 ]] || { echo 'usage: stage-v087-input-reliability.sh <staged-upstream>' >&2; exit 2; }
SRC="$1"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LIB="$SRC/layout/usr/share/nktouch/lua"
EXAMPLES="$SRC/layout/usr/share/nktouch/examples"
CONTROL="$SRC/control"
CTL="$SRC/layout/usr/bin/nktouchctl"
VERSION="$SRC/layout/usr/share/doc/nktouch/VERSION"
UI="$SRC/zxtouch/zxtouch/Settings/SettingsPageViewController.m"
LAB="$LIB/nktestlab.lua"
for p in "$LIB/nktouch.lua" "$LIB/nkinput_pro.lua" "$LIB/nkprecision.lua" "$LAB" "$CTL" "$CONTROL" "$VERSION" "$UI" "$SRC/pccontrol/UIKeyboard.xm" "$SRC/appdelegate/UIKeyboard.xm"; do
  test -s "$p"
done
grep -Fxq 'Version: 0.8.6' "$CONTROL"
grep -Fq 'PACKAGE_VERSION="0.8.6"' "$CTL"
grep -Fq 'NKTouch Test Lab v0.8.6-beta' "$LAB"
grep -Fq 'function M.inputSafe(value,options)' "$LIB/nktouch.lua"
grep -Fq 'function M.precisionTapIfMatch(options)' "$LIB/nktouch.lua"
grep -Fq 'NKInputV2FocusedView' "$SRC/appdelegate/UIKeyboard.xm"

# Repair ONLY native UIKit focus query; original input dispatch 8/9 intact.
mkdir -p "$EXAMPLES"
python3 "$ROOT/scripts/apply-v087-focus-probe.py" "$SRC"
install -m 0644 "$ROOT/lua/nkinput_pro.lua" "$LIB/nkinput_pro.lua"
install -m 0644 "$ROOT/examples/test_focus_probe_v087.lua" "$EXAMPLES/test_focus_probe_v087.lua"
install -m 0644 "$ROOT/examples/test_input_strict_v087.lua" "$EXAMPLES/test_input_strict_v087.lua"

python3 - "$CONTROL" "$CTL" "$VERSION" "$UI" "$LAB" "$LIB/nktouch.lua" <<'PY'
from pathlib import Path
import sys
control,ctl,version,ui,lab,api=map(Path,sys.argv[1:])
def exactly(path,old,new):
    data=path.read_text()
    if data.count(old)!=1:
        raise SystemExit(f"{path}: expected one {old!r}, got {data.count(old)}")
    path.write_text(data.replace(old,new,1))
exactly(control,"Version: 0.8.6","Version: 0.8.7")
exactly(control,
  "Description: NKTouch v0.8.6 Touch Color Precision beta: same-frame multi-point RGB guards, validated pixel geometry, opt-in guarded touch; retains Native Input Pro and OCR diagnostics",
  "Description: NKTouch v0.8.7 Native Input Reliability beta: read-only UIKit first-responder focus probe, strict guarded input; retains Precision, same-frame OCR and Lua tools")
exactly(ctl,'PACKAGE_VERSION="0.8.6"','PACKAGE_VERSION="0.8.7"')
exactly(version,"NKTouch 0.8.6 Touch Color Precision Beta",
                "NKTouch 0.8.7 Native Input Reliability Beta")
with version.open("a") as out:
    out.write("""
v0.8.7: native focus probe: SpringBoard sends a correlated, bounded, read-only
notification to foreground app's UIKit main queue. A positive reply requires
an active key window with a UIView that is first responder + UIKeyInput.
Unavailable reply fails closed. Query cannot type or capture OCR.
InputSafe(requireFocusProof=true) checks target bundle, focus and foreground
before ONE native v2 input packet, without keyboard fallback or retry.
UIKit focus may change after the probe; native ACK remains unverified dispatch.
Retains v0.8.6 Precision and v0.8.5 Input Pro. Device testing pending.
""")
exactly(lab,"-- NKTouch Test Lab v0.8.6-beta",
            "-- NKTouch Test Lab v0.8.7-beta")
exactly(lab,'local M={VERSION="0.8.6-beta"}',
            'local M={VERSION="0.8.7-beta"}')
anchor='function M.inputPassword(value,options)\n'
methods='''-- v0.8.7 Native UIKit first-responder read-only check.
-- Returns true (focus), false (explicit no focus), nil,error,code (unknown).
-- No OCR, retries, text or keyboard mutation in this query.
M.FOCUS_PROBE_VERSION="0.8.7-beta"
function M.focusedInput(bundle)
  if type(bundle)~="string" or #bundle<3 or #bundle>180 or
     not bundle:match("^[%w%._%-]+$") then
    return nil,"valid target application bundle ID required","INVALID"
  end
  if not core or type(core.focusedInput)~="function" then
    return nil,"Native UIKit focus bridge unavailable","FOCUS_PROBE_UNAVAILABLE"
  end
  local called,answer,err=pcall(core.focusedInput,bundle)
  if not called or (answer~=true and answer~=false) then
    return nil,"Native UIKit focus query unconfirmed","FOCUS_PROBE_UNAVAILABLE"
  end
  return answer
end
'''
exactly(api,anchor,methods+anchor)
src=ui.read_text()
src=src.replace("NKTouch 0.8.6","NKTouch 0.8.7")
src=src.replace('nkLabel:@"0.8.6"','nkLabel:@"0.8.7"')
src=src.replace('text:@"0.8.6"','text:@"0.8.7"')
src=src.replace("-- NKTouch Test Lab v0.8.6-beta",
                "-- NKTouch Test Lab v0.8.7-beta")
installer='@{@"file":@"test_precision_touch_v086.lua", @"bundle":@"com.apple.mobilenotes"}'
menu='@{@"title":@"Touch • Chạm khi khớp màu", @"file":@"test_precision_touch_v086.lua"}'
assert src.count(installer)==1, "v0.8.6 Samples installer changed"
assert src.count(menu)==1, "v0.8.6 Samples menu changed"
src=src.replace(installer,
    '@{@"file":@"test_focus_probe_v087.lua", @"bundle":@"com.apple.mobilenotes"},\n'
    '        @{@"file":@"test_input_strict_v087.lua", @"bundle":@"com.apple.mobilenotes"},\n'
    '        '+installer,1)
src=src.replace(menu,
    '@{@"title":@"Input • Kiểm tra focus UIKit", @"file":@"test_focus_probe_v087.lua"},\n'
    '        @{@"title":@"Input • Strict Native (opt-in)", @"file":@"test_input_strict_v087.lua"},\n'
    '        '+menu,1)
ui.write_text(src)
PY
grep -Fxq 'Version: 0.8.7' "$CONTROL"
grep -Fq 'PACKAGE_VERSION="0.8.7"' "$CTL"
grep -Fq 'NKTouch Test Lab v0.8.7-beta' "$LAB"
grep -Fq 'function M.focusedInput(bundle)' "$LIB/nktouch.lua"
grep -Fq 'function M.inputSafe(value,options)' "$LIB/nktouch.lua"
grep -Fq 'function M.precisionTapIfMatch(options)' "$LIB/nktouch.lua"
grep -Fq 'NKInputFocusProbeWaiter' "$SRC/pccontrol/UIKeyboard.xm"
grep -Fq 'NKInputV87RespondToFocusProbe' "$SRC/appdelegate/UIKeyboard.xm"
grep -Fq 'test_focus_probe_v087.lua' "$UI"
grep -Fq 'test_input_strict_v087.lua' "$UI"
test ! -e "$SRC/layout/var/jb"
echo '[NKINPUT087] Native focus reliability staged; Sileo untouched'
