#!/usr/bin/env bash
set -euo pipefail
SRC="${1:-upstream}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[[ -d "$SRC" ]] || { echo "Missing upstream source: $SRC" >&2; exit 1; }

# Frozen known-good V6 + Control Foundation runtime, recorder, and hotkeys.
bash "$ROOT/scripts/prepare-v076-gesture-engine.sh" "$SRC"

COLOR="$SRC/pccontrol/ColorPicker.xm"
[[ -f "$COLOR" ]] || { echo 'Missing upstream ColorPicker.xm' >&2; exit 1; }
install -m 0644 "$ROOT/patches/NKColorPickerSafe.xm" "$COLOR"

# 0.7.7 is a stability release; only metadata and color backend change.
python3 - "$SRC/control" "$SRC/layout/usr/share/doc/nktouch/VERSION" "$SRC/layout/usr/bin/nktouchctl" "$SRC/zxtouch/zxtouch/Settings/SettingsPageViewController.m" <<'PY'
from pathlib import Path
import sys
control, version, ctl, settings = map(Path, sys.argv[1:])
s = control.read_text()
if 'Version: 0.7.6' not in s:
    raise SystemExit('Expected v0.7.6 source baseline')
s = s.replace('Version: 0.7.6', 'Version: 0.7.7', 1)
for line in s.splitlines():
    if line.startswith('Description:'):
        s = s.replace(line, 'Description: NKTouch v0.7.7 Lua Core Reliability: safe color sampling, bounded pixel search, strict RGB validation, matchColor/waitColorMatch and retained v0.7.6 Gesture Engine', 1)
        break
control.write_text(s)
v = version.read_text()
v = v.replace('NKTouch 0.7.6 Recorder V6 Gesture Engine',
              'NKTouch 0.7.7 Lua Core Reliability', 1)
v += """Lua Core Reliability: strict bounded RGB parsing and color error reporting
ColorPicker: safe CoreGraphics allocation/capture/coordinate checks
Color API: nk.matchColor(x,y,r,g,b,tolerance)
Color API: nk.waitColorMatch(r,g,b,tolerance,region,timeoutMs,intervalMs)
Color coordinates: native screenshot physical pixels; no implicit scaling
Recorder V6 and the V5 hotkey/runner handoff remain unchanged
"""
version.write_text(v)
c = ctl.read_text()
if 'PACKAGE_VERSION="0.7.6"' not in c:
    raise SystemExit('Expected v0.7.6 staged nktouchctl')
c = c.replace('PACKAGE_VERSION="0.7.6"', 'PACKAGE_VERSION="0.7.7"', 1)
c = c.replace('NKTouch v0.7.6 Recorder V6 Gesture Engine',
              'NKTouch v0.7.7 Lua Core Reliability', 1)
ctl.write_text(c)
u = settings.read_text().replace('NKTouch 0.7.6', 'NKTouch 0.7.7')
u = u.replace('nkLabel:@"0.7.6"', 'nkLabel:@"0.7.7"')
u = u.replace('text:@"0.7.6"', 'text:@"0.7.7"')
settings.write_text(u)
PY

grep -Fxq 'Version: 0.7.7' "$SRC/control"
grep -Fxq 'NKTouch 0.7.7 Lua Core Reliability' "$SRC/layout/usr/share/doc/nktouch/VERSION"
grep -Fq 'PACKAGE_VERSION="0.7.7"' "$SRC/layout/usr/bin/nktouchctl"
grep -Fq 'NKColorCopyPixels' "$COLOR"
grep -Fq 'COLOR_OUT_OF_BOUNDS' "$COLOR"
grep -Fq 'CGImageGetWidth' "$COLOR"
grep -Fq 'function M.matchColor' "$SRC/layout/usr/share/nktouch/lua/nktouch.lua"
grep -Fq 'function M.waitColorMatch' "$SRC/layout/usr/share/nktouch/lua/nktouch.lua"
grep -Fq 'nk.matchColor|' "$SRC/layout/usr/share/nktouch/nktouch-api.tsv"
grep -Fq 'NKHotkeyActionRecorderFinish' "$SRC/nktouch-trigger/Tweak.xm"
grep -Fq 'function M.parseRaw(path)' "$SRC/layout/usr/share/nktouch/nkgesture_v6.lua"
test ! -e "$SRC/layout/var/jb"
echo 'NKTouch v0.7.7 color reliability source validated'
