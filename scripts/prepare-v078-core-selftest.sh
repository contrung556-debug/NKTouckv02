#!/usr/bin/env bash
set -euo pipefail
SRC="${1:-upstream}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[[ -d "$SRC" ]] || { echo "Missing upstream source: $SRC" >&2; exit 1; }

# Keep v0.7.7 Color Engine and the proven V6 Recorder unchanged.
bash "$ROOT/scripts/prepare-v077-lua-core-reliability.sh" "$SRC"
LIB="$SRC/layout/usr/share/nktouch/lua"
UI="$SRC/zxtouch/zxtouch/Settings/SettingsPageViewController.m"
CTL="$SRC/layout/usr/bin/nktouchctl"
test -d "$LIB"
install -m 0644 "$ROOT/lua/nkcore_selftest.lua" "$LIB/nkcore_selftest.lua"
python3 "$ROOT/scripts/apply-v078-core-selftest-ui.py" "$SRC"

python3 - "$SRC/control" "$SRC/layout/usr/share/doc/nktouch/VERSION" "$CTL" "$UI" <<'PY'
from pathlib import Path
import sys
control, version, ctl, ui = map(Path, sys.argv[1:])
c = control.read_text()
if "Version: 0.7.7" not in c:
    raise SystemExit("expected v0.7.7 source baseline")
c = c.replace("Version: 0.7.7", "Version: 0.7.8", 1)
for line in c.splitlines():
    if line.startswith("Description:"):
        c = c.replace(line, "Description: NKTouch v0.7.8 Lua Core Self-Test: on-device read-only API checks, timings and diagnostics; retained Color Engine and Recorder V6", 1)
        break
control.write_text(c)
v = version.read_text()
v = v.replace("NKTouch 0.7.7 Lua Core Reliability",
              "NKTouch 0.7.8 Lua Core Self-Test", 1)
v += """Lua Core Self-Test: real nktask Lua API probes on-device (read-only by default)
Results: [NKCORE][PASS/FAIL/WARN/SKIP] and [NKCORE][SUMMARY] in task logs
Coverage: direct core, ping, screen, orientation, scale, foreground, sleep, RGB, 1x1 findColor, waitColorMatch, screenshot
Optional: image template, OCR, and explicitly authorized --touch x y
Recoder V6/Control Foundation: no behavior changes
"""
version.write_text(v)
s = ctl.read_text()
if 'PACKAGE_VERSION="0.7.7"' not in s:
    raise SystemExit("expected staged v0.7.7 nktouchctl")
s = s.replace('PACKAGE_VERSION="0.7.7"', 'PACKAGE_VERSION="0.7.8"', 1)
s = s.replace('NKTouch v0.7.7 Lua Core Reliability', 'NKTouch v0.7.8 Lua Core Self-Test')
s = s.replace('SELFTEST="/var/jb/usr/share/nktouch/lua/nkcore_selftest.lua"\n', '')
# Dedicated on-device diagnostics command starts under existing single-task
# manager; does not run two concurrent touch workers.
anchor='cmd="${1:-help}"'
if anchor not in s: raise SystemExit("nktouchctl command marker missing")
s = s.replace(anchor, 'SELFTEST="/var/jb/usr/share/nktouch/lua/nkcore_selftest.lua"\n\n'+anchor, 1)
anchor='  task)\n    need_task'
if anchor not in s: raise SystemExit("nktouchctl task entry marker missing")
s = s.replace(anchor, '''  core-selftest)
    need_task
    test -r "$SELFTEST" || { echo "Missing Core Self-Test" >&2; exit 4; }
    exec "$TASK" start "$SELFTEST" --timeout 60 -- "$@"
    ;;
'''+anchor, 1)
s = s.replace('NKTouch v0.7.7 Lua Core Reliability',
              'NKTouch v0.7.8 Lua Core Self-Test')
s = s.replace('  nktouchctl selftest\n',
              '  nktouchctl selftest\n  nktouchctl core-selftest [--ocr] [--image PATH] [--touch x y]\n', 1)
ctl.write_text(s)
u = ui.read_text()
u = u.replace('NKTouch 0.7.7', 'NKTouch 0.7.8')
u = u.replace('nkLabel:@"0.7.7"', 'nkLabel:@"0.7.8"')
u = u.replace('text:@"0.7.7"', 'text:@"0.7.8"')
ui.write_text(u)
PY

grep -Fxq 'Version: 0.7.8' "$SRC/control"
grep -Fxq 'NKTouch 0.7.8 Lua Core Self-Test' "$SRC/layout/usr/share/doc/nktouch/VERSION"
grep -Fq 'PACKAGE_VERSION="0.7.8"' "$CTL"
grep -Fq 'core-selftest)' "$CTL"
grep -Fq 'start "$SELFTEST" --timeout 60 -- "$@"' "$CTL"
grep -Fq '[NKCORE][SUMMARY] status=PASS' "$UI"
grep -Fq 'stringWithContentsOfFile:' "$UI"
grep -Fq 'Core Self-Test' "$UI"
grep -Fq 'getColor' "$LIB/nkcore_selftest.lua"
grep -Fq 'waitColorMatch' "$LIB/nkcore_selftest.lua"
grep -Fq 'function M.matchColor' "$LIB/nktouch.lua"
grep -Fq 'NKHotkeyActionRecorderFinish' "$SRC/nktouch-trigger/Tweak.xm"
test ! -e "$SRC/layout/var/jb"
echo 'NKTouch v0.7.8 Core Self-Test prepared; existing on-device Lua engine and Recorder retained'
