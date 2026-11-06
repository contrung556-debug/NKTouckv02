#!/usr/bin/env bash
# NKTouch 0.8.8 Vision Speed & Stability overlay after v0.8.7.
# Artifact-only. Never modifies the Sileo branch.
set -euo pipefail
[[ $# -eq 1 ]] || { echo 'usage: stage-v088-vision-speed.sh <staged-upstream>' >&2; exit 2; }
SRC="$1"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LIB="$SRC/layout/usr/share/nktouch/lua"
EXAMPLES="$SRC/layout/usr/share/nktouch/examples"
CONTROL="$SRC/control"
CTL="$SRC/layout/usr/bin/nktouchctl"
VERSION="$SRC/layout/usr/share/doc/nktouch/VERSION"
UI="$SRC/zxtouch/zxtouch/Settings/SettingsPageViewController.m"
LAB="$LIB/nktestlab.lua"
for f in "$LIB/nktouch.lua" "$LIB/nkvision.lua" "$LIB/nksnapshot.lua" "$LIB/nkocr_perf.lua" "$LIB/nkcoords.lua" "$LIB/nkinput_pro.lua" "$LIB/nkprecision.lua" "$CTL" "$LAB" "$UI" "$CONTROL" "$VERSION"; do test -s "$f"; done
grep -Fxq 'Version: 0.8.7' "$CONTROL"
grep -Fq 'PACKAGE_VERSION="0.8.7"' "$CTL"
grep -Fq 'NKTouch Test Lab v0.8.7-beta' "$LAB"
grep -Fq 'function M.focusedInput(bundle)' "$LIB/nktouch.lua"
grep -Fq 'function M.precisionTapIfMatch(options)' "$LIB/nktouch.lua"
grep -Fq 'function M.withFrame(callback)' "$LIB/nktouch.lua"
grep -Fq 'function M.capture(plan,options)' "$LIB/nksnapshot.lua"
mkdir -p "$EXAMPLES" "$LIB"
install -m 0644 "$ROOT/lua/nkvision_speed.lua" "$LIB/nkvision_speed.lua"
install -m 0644 "$ROOT/examples/test_vision_batch_v088.lua" "$EXAMPLES/test_vision_batch_v088.lua"
install -m 0644 "$ROOT/examples/test_vision_stability_v088.lua" "$EXAMPLES/test_vision_stability_v088.lua"
python3 - "$CONTROL" "$CTL" "$VERSION" "$UI" "$LAB" "$LIB/nktouch.lua" <<'PY'
from pathlib import Path
import sys
control,ctl,version,ui,lab,api=map(Path,sys.argv[1:])
def exactly(f,old,new):
    s=f.read_text()
    if s.count(old)!=1: raise SystemExit(f"{f}: expected one {old!r}, got {s.count(old)}")
    f.write_text(s.replace(old,new,1))
exactly(control,'Version: 0.8.7','Version: 0.8.8')
exactly(control,
  'Description: NKTouch v0.8.7 Native Input Reliability beta: read-only UIKit first-responder focus probe, strict guarded input; retains Precision, same-frame OCR and Lua tools',
  'Description: NKTouch v0.8.8 Vision Speed Stability beta: one-frame Color/OCR/Image batch with cached pixels, bounded stable-screen gate; retains Native Input and Precision')
exactly(ctl,'PACKAGE_VERSION="0.8.7"','PACKAGE_VERSION="0.8.8"')
exactly(version,'NKTouch 0.8.7 Native Input Reliability Beta',
                'NKTouch 0.8.8 Vision Speed and Screen Stability Beta')
with version.open("a") as out:
    out.write("""
v0.8.8: Vision batch performs Color, Image and OCR using ONE immutable frame.
Pixel reads are cached for repeated coordinates. Monotonic timings and native
pixel read/capture counts are returned without OCR/private content by default.
Stable-screen gate samples 4x4 grid plus optional watch points across bounded
captures; OCR/Color/Image run ONLY on the final stable sampled frame, never a
fresh third capture. Screens with changing pixels skip OCR. Not a spinner proof.
No implicit live OCR fallback, no HID or input, no unbounded retries.
All v0.8.7 Native Focus, v0.8.6 Precision, Recorder and old Lua APIs retained.
Device benchmark/long-run memory validation pending before Sileo release.
""")
exactly(lab,'-- NKTouch Test Lab v0.8.7-beta',
            '-- NKTouch Test Lab v0.8.8-beta')
exactly(lab,'local M={VERSION="0.8.7-beta"}',
            'local M={VERSION="0.8.8-beta"}')
anchor='function M.inputPassword(value,options)\n'
methods='''-- v0.8.8: read-only one-frame batch and stable-screen gate.
M.VISION_SPEED_VERSION="0.8.8-beta"
function M.visionBatch(plan,options)
  return require("nkvision_speed").batch(M,plan,options)
end
function M.visionWhenStable(plan,options)
  return require("nkvision_speed").whenStable(M,plan,options)
end
'''
exactly(api,anchor,methods+anchor)
s=ui.read_text()
s=s.replace('NKTouch 0.8.7','NKTouch 0.8.8')
s=s.replace('nkLabel:@"0.8.7"','nkLabel:@"0.8.8"')
s=s.replace('text:@"0.8.7"','text:@"0.8.8"')
s=s.replace('-- NKTouch Test Lab v0.8.7-beta','-- NKTouch Test Lab v0.8.8-beta')
installer='@{@"file":@"test_input_strict_v087.lua", @"bundle":@"com.apple.mobilenotes"}'
menu='@{@"title":@"Input • Strict Native (opt-in)", @"file":@"test_input_strict_v087.lua"}'
assert s.count(installer)==1, "v0.8.7 Samples installer changed"
assert s.count(menu)==1, "v0.8.7 Samples menu changed"
s=s.replace(installer,
  '@{@"file":@"test_vision_batch_v088.lua", @"bundle":@"com.apple.mobilenotes"},\n'
  '        @{@"file":@"test_vision_stability_v088.lua", @"bundle":@"com.apple.mobilenotes"},\n'
  '        '+installer,1)
s=s.replace(menu,
  '@{@"title":@"Vision • Color + OCR / 1 frame", @"file":@"test_vision_batch_v088.lua"},\n'
  '        @{@"title":@"Vision • Chờ màn hình ổn định", @"file":@"test_vision_stability_v088.lua"},\n'
  '        '+menu,1)
ui.write_text(s)
PY
grep -Fxq 'Version: 0.8.8' "$CONTROL"
grep -Fq 'PACKAGE_VERSION="0.8.8"' "$CTL"
grep -Fq 'NKTouch Test Lab v0.8.8-beta' "$LAB"
grep -Fq 'function M.visionBatch(plan,options)' "$LIB/nktouch.lua"
grep -Fq 'function M.visionWhenStable(plan,options)' "$LIB/nktouch.lua"
grep -Fq 'function M.inputFast(value,options)' "$LIB/nktouch.lua"
grep -Fq 'function M.precisionTapIfMatch(options)' "$LIB/nktouch.lua"
grep -Fq 'function M.focusedInput(bundle)' "$LIB/nktouch.lua"
grep -Fq 'test_vision_batch_v088.lua' "$UI"
grep -Fq 'test_vision_stability_v088.lua' "$UI"
test ! -e "$SRC/layout/var/jb"
echo '[NKVISION088] staged read-only one-frame batch + bounded stability; Sileo untouched'
