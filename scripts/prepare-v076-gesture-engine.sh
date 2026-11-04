#!/usr/bin/env bash
set -euo pipefail
SRC="${1:-upstream}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[[ -d "$SRC" ]] || { echo "Missing upstream source: $SRC" >&2; exit 1; }

# Preserve the fully-tested V5 hardware stop / v0.7.5.6 Control Foundation.
bash "$ROOT/scripts/prepare-v0756-control-foundation.sh" "$SRC"

install -m 0644 "$ROOT/lua/nkgesture_v6.lua" "$SRC/layout/usr/share/nktouch/nkgesture_v6.lua"
python3 "$ROOT/scripts/apply-v076-gesture-engine.py" "$SRC"

python3 - "$SRC/control" "$SRC/layout/usr/share/doc/nktouch/VERSION" <<'PY'
from pathlib import Path
import sys
control, version_file = map(Path, sys.argv[1:])
s = control.read_text()
if "Version: 0.7.5.6" not in s:
    raise SystemExit("Control Foundation v0.7.5.6 missing")
s = s.replace("Version: 0.7.5.6", "Version: 0.7.6", 1)
for line in s.splitlines():
    if line.startswith("Description:"):
        s = s.replace(line, "Description: NKTouch v0.7.6 Recorder V6 Gesture Engine: sampled single-finger HID paths, per-point timing, continuous native replay, editable timelines, retained V5 Volume Down stop and Control Foundation", 1)
        break
control.write_text(s)

v = version_file.read_text()
v = v.replace("NKTouch 0.7.5.6 Control Foundation",
              "NKTouch 0.7.6 Recorder V6 Gesture Engine", 1)
v += """Recorder V6: real sampled single-finger HID trajectories -> editable .nktl path column
Gesture types: tap / hold / swipe / drag; timed native nk.path playback
Legacy timeline v3/v4 compatible; editing endpoints removes stale curved path
Safety: maximum 256 sampled points, bounded gesture durations; overlapping fingers ignored
Hardware stop: existing Volume Down 0.5s SpringBoard-to-runner protocol unchanged
No fabricated live touch indicator; no multi-finger simultaneous replay in V6
"""
version_file.write_text(v)
PY

EXPORTER="$SRC/layout/usr/share/nktouch/nkrecorder.lua"
GESTURE="$SRC/layout/usr/share/nktouch/nkgesture_v6.lua"
CTL="$SRC/layout/usr/bin/nktouchctl"
REC="$SRC/layout/usr/bin/nkrecorder"
TRIGGER="$SRC/nktouch-trigger/Tweak.xm"
RUNNER="$SRC/zxtouch-runner/main.m"
SETTINGS="$SRC/zxtouch/zxtouch/Settings/SettingsPageViewController.m"
LUA_API="$SRC/layout/usr/share/nktouch/lua/nktouch.lua"

grep -Fxq 'Version: 0.7.6' "$SRC/control"
grep -Fxq 'NKTouch 0.7.6 Recorder V6 Gesture Engine' "$SRC/layout/usr/share/doc/nktouch/VERSION"
grep -Fq 'PACKAGE_VERSION="0.7.6"' "$CTL"
grep -Fq 'function M.path(points)' "$LUA_API"
grep -Fq 'local VERSION = "0.7.6"' "$EXPORTER"
grep -Fq 'local gesture = dofile(' "$EXPORTER"
grep -Fq 'local function trim_tail(path, count)' "$EXPORTER"
grep -Fq 'function M.parseRaw(path)' "$GESTURE"
grep -Fq 'function M.renderLua(timeline, output)' "$GESTURE"
grep -Fq 'NKRecorderV3ViewController' "$SETTINGS"
grep -Fq 'Recorder V6' "$SETTINGS"
grep -Fq 'NKHotkeyActionRecorderFinish' "$TRIGGER"
grep -Fq 'notify_post(kNKRecorderAcceptedNotification)' "$RUNNER"
grep -Fq '  finish)' "$REC"
test ! -e "$SRC/layout/var/jb"
echo 'NKTouch v0.7.6 gesture package prepared; V5 trigger retained'
