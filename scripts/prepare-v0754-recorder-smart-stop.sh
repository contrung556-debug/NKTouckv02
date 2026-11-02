#!/usr/bin/env bash
set -euo pipefail
SRC="${1:-upstream}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

[[ -d "$SRC" ]] || { echo "Missing upstream source: $SRC" >&2; exit 1; }

bash "$ROOT/scripts/prepare-v07533-recorder-status-fix.sh" "$SRC"
python3 "$ROOT/scripts/apply-v0754-recorder-smart-stop.py" "$SRC"

CONTROL="$SRC/control"
VERSION_FILE="$SRC/layout/usr/share/doc/nktouch/VERSION"
SETTINGS="$SRC/zxtouch/zxtouch/Settings/SettingsPageViewController.m"
REC="$SRC/layout/usr/bin/nkrecorder"
EXPORTER="$SRC/layout/usr/share/nktouch/nkrecorder.lua"

python3 - "$CONTROL" "$VERSION_FILE" "$REC" <<'PY'
from pathlib import Path
import sys
control=Path(sys.argv[1]); version_file=Path(sys.argv[2]); rec=Path(sys.argv[3])
s=control.read_text()
s=s.replace('Version: 0.7.5.3.3','Version: 0.7.5.4',1)
for line in s.splitlines():
    if line.startswith('Description:'):
        s=s.replace(line,'Description: NKTouch v0.7.5.4 Recorder V4 Smart Stop with auto-stop on return, tail trim, automatic Lua generation/open Editor, Recorder V3 timeline editing, Editor Pro, Task Center and direct lua54 runtime',1)
        break
control.write_text(s)

v=version_file.read_text().replace('NKTouch 0.7.5.3.3 Recorder Status Fix','NKTouch 0.7.5.4 Recorder V4 Smart Stop',1)
extra='''Recorder V4 Smart Stop: leave NKTouch to record, return to NKTouch to stop automatically
Smart trim: removes the final control/return touch from the generated timeline
Auto Lua: Stop immediately creates the managed Lua script and opens Editor
Manual Stop uses the same one-step finish flow; paused recordings trim zero actions
Recorder V3 timeline edit/replay remains available after generation
Editor Pro / Task Center / Self Test / direct lua54 runtime retained
'''
if 'Recorder V4 Smart Stop: leave NKTouch to record' not in v:
    v=v.rstrip()+'\n'+extra
version_file.write_text(v)

r=rec.read_text()
for old in ('VERSION="0.7.5.2"','VERSION="0.7.5.3.1"','VERSION="0.7.5.3.2"','VERSION="0.7.5.3.3"'):
    if old in r:
        r=r.replace(old,'VERSION="0.7.5.4"',1)
        break
r=r.replace('NKTouch Recorder V3 v0.7.5.3.1','NKTouch Recorder V4 v0.7.5.4')
r=r.replace('NKTouch Recorder V3 v0.7.5.2','NKTouch Recorder V4 v0.7.5.4')
rec.write_text(r)
PY

chmod 0755 "$REC"

grep -q '^Version: 0.7.5.4$' "$CONTROL"
grep -q '^NKTouch 0.7.5.4 Recorder V4 Smart Stop$' "$VERSION_FILE"
grep -q '^VERSION="0.7.5.4"$' "$REC"
grep -q '^  finish)' "$REC"
grep -q 'trim-tail' "$REC"
grep -q 'script=$script' "$REC"
grep -q 'local VERSION = "0.7.5.4"' "$EXPORTER"
grep -q 'local function trim_tail(path, count)' "$EXPORTER"
grep -q 'cmd == "trim-tail"' "$EXPORTER"
grep -q 'Recorder V4' "$SETTINGS"
grep -q 'smartStopArmed' "$SETTINGS"
grep -q 'UIApplicationDidEnterBackgroundNotification' "$SETTINGS"
grep -q 'UIApplicationDidBecomeActiveNotification' "$SETTINGS"
grep -q 'smartFinishWithTrim' "$SETTINGS"
grep -q 'Quay lại NKTouch = Stop + Lua' "$SETTINGS"
grep -q 'Rebuild Lua' "$SETTINGS"
grep -q 'shellCandidates=@\[@"/var/jb/bin/sh",@"/var/jb/usr/bin/sh",@"/bin/sh"\]' "$SETTINGS"

echo "--- NKTouch v0.7.5.4 Recorder V4 Smart Stop package ---"
cat "$CONTROL"
cat "$VERSION_FILE"
