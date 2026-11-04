#!/usr/bin/env bash
set -euo pipefail
SRC="$1"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[[ -d "$SRC" ]] || { echo 'missing upstream directory' >&2; exit 1; }

# Retain green v0.7.8.1 Core Self-Test UI, Recorder V6 and safe color backend.
bash "$ROOT/scripts/prepare-v0781-core-selftest-hotfix.sh" "$SRC"
LIB="$SRC/layout/usr/share/nktouch/lua"
CTL="$SRC/layout/usr/bin/nktouchctl"
UI="$SRC/zxtouch/zxtouch/Settings/SettingsPageViewController.m"
install -m 0644 "$ROOT/lua/nktouch.lua" "$LIB/nktouch.lua"
install -m 0644 "$ROOT/lua/nkvision.lua" "$LIB/nkvision.lua"
install -m 0644 "$ROOT/lua/nkvision_selftest.lua" "$LIB/nkvision_selftest.lua"

python3 - "$SRC/control" "$SRC/layout/usr/share/doc/nktouch/VERSION" "$CTL" "$UI" <<'PY'
from pathlib import Path
import sys
control,version,ctl,ui=map(Path,sys.argv[1:])
c=control.read_text()
if c.count("Version: 0.7.8.1")!=1:
    raise SystemExit("expected v0.7.8.1 source baseline")
c=c.replace("Version: 0.7.8.1","Version: 0.7.9",1)
for line in c.splitlines():
    if line.startswith("Description:"):
        c=c.replace(line,"Description: NKTouch 0.7.9 Vision Core: explicit reusable screenshot frames for RGB, image templates and Vision OCR, keeping v0.7.8.1 hotfix/Recorder V6",1)
        break
control.write_text(c)
v=version.read_text()
v=v.replace("NKTouch 0.7.8.1 Lua Core Self-Test Hotfix",
            "NKTouch 0.7.9 Vision Core",1)
v+="""Vision API: nk.captureFrame() and nk.withFrame(function(frame)...end)
Frame operations: info/getColor/findColor/findImage/ocr/save/close
Frame snapshot: one screen JPEG, decoded once, immutable per-task lifetime
Memory: max 96MB decoded RGBA image + bounded grayscale/template buffers
Safety: no implicit screen refresh, no retry, script controls frame lifetime
Color fidelity: JPEG snapshot can differ from raw live getColor; use tolerance
Legacy APIs: live getColor/findColor/findImage/ocr/screenshot unaffected
On-device diagnostics: nktouchctl vision-selftest
"""
version.write_text(v)
s=ctl.read_text()
if s.count('PACKAGE_VERSION="0.7.8.1"')!=1:
    raise SystemExit("expected v0.7.8.1 shell runtime")
s=s.replace('PACKAGE_VERSION="0.7.8.1"','PACKAGE_VERSION="0.7.9"',1)
anchor='SELFTEST="/var/jb/usr/share/nktouch/lua/nkcore_selftest.lua"'
if anchor not in s: raise SystemExit("core test CLI anchor missing")
s=s.replace(anchor,anchor+'\nVISIONTEST="/var/jb/usr/share/nktouch/lua/nkvision_selftest.lua"',1)
anchor='  core-selftest)\n'
if anchor not in s: raise SystemExit("core selftest case anchor missing")
s=s.replace(anchor,'''  vision-selftest)
    need_task
    test -r "$VISIONTEST" || { echo "Vision Core selftest missing" >&2; exit 4; }
    exec "$TASK" start "$VISIONTEST" --timeout 90
    ;;
'''+anchor,1)
s=s.replace('  nktouchctl core-selftest [--ocr] [--image PATH] [--touch x y]',
            '  nktouchctl core-selftest [--ocr] [--image PATH] [--touch x y]\n  nktouchctl vision-selftest')
ctl.write_text(s)
u=ui.read_text().replace("NKTouch 0.7.8.1","NKTouch 0.7.9")
u=u.replace('nkLabel:@"0.7.8.1"','nkLabel:@"0.7.9"')
u=u.replace('text:@"0.7.8.1"','text:@"0.7.9"')
ui.write_text(u)
PY

grep -Fxq "Version: 0.7.9" "$SRC/control"
grep -Fxq "NKTouch 0.7.9 Vision Core" "$SRC/layout/usr/share/doc/nktouch/VERSION"
grep -Fq 'PACKAGE_VERSION="0.7.9"' "$CTL"
grep -Fq 'vision-selftest)' "$CTL"
grep -Fq 'exec "$TASK" start "$VISIONTEST" --timeout 90' "$CTL"
grep -Fq 'function M.captureFrame()' "$LIB/nktouch.lua"
grep -Fq 'function M.withFrame(callback)' "$LIB/nktouch.lua"
grep -Fq 'function M.capture(nk)' "$LIB/nkvision.lua"
grep -Fq 'function M.withFrame(nk, callback)' "$LIB/nkvision.lua"
grep -Fq '[VISION][SUMMARY] status=PASS' "$LIB/nkvision_selftest.lua"
grep -Fq 'Doctor (optional)' "$UI"
grep -Fq 'BOOL pass=wrote&&cc==0&&rc==0&&' "$UI"
grep -Fq 'NKColorCopyPixels' "$SRC/pccontrol/ColorPicker.xm"
grep -Fq 'NKHotkeyActionRecorderFinish' "$SRC/nktouch-trigger/Tweak.xm"
test ! -e "$SRC/layout/var/jb"
echo 'NKTouch 0.7.9 Vision Core source staged; legacy API and recorder retained'
