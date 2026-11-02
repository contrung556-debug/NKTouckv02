#!/usr/bin/env bash
set -euo pipefail
SRC="${1:-upstream}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

[[ -d "$SRC" ]] || { echo "Missing upstream source: $SRC" >&2; exit 1; }

bash "$ROOT/scripts/prepare-v07532-recorder-spawn-fix.sh" "$SRC"
python3 "$ROOT/scripts/apply-v07533-recorder-status-fix.py" "$SRC"

CONTROL="$SRC/control"
VERSION_FILE="$SRC/layout/usr/share/doc/nktouch/VERSION"
SETTINGS="$SRC/zxtouch/zxtouch/Settings/SettingsPageViewController.m"
REC="$SRC/layout/usr/bin/nkrecorder"

python3 - "$CONTROL" "$VERSION_FILE" <<'PY'
from pathlib import Path
import sys
control=Path(sys.argv[1]); version_file=Path(sys.argv[2])
s=control.read_text()
s=s.replace('Version: 0.7.5.3.2','Version: 0.7.5.3.3',1)
for line in s.splitlines():
    if line.startswith('Description:'):
        s=s.replace(line,'Description: NKTouch v0.7.5.3.3 Recorder V3 status hotfix with correct zero exit on valid recording state, trusted shell execution, Editor Pro, Task Center and direct lua54 runtime',1)
        break
control.write_text(s)

v=version_file.read_text().replace('NKTouch 0.7.5.3.2 Recorder Spawn Fix','NKTouch 0.7.5.3.3 Recorder Status Fix',1)
extra='''Recorder status fix: valid idle/recording/paused status now exits 0 even when no previous timeline exists
Prevents false RECORDER LỖI while HID recorder is actively recording
Recorder trusted-shell spawn fix retained
Editor Pro / Task Center / Self Test retained
'''
if 'Recorder status fix: valid idle/recording/paused status now exits 0' not in v:
    v=v.rstrip()+'\n'+extra
version_file.write_text(v)
PY

grep -q '^Version: 0.7.5.3.3$' "$CONTROL"
grep -q '^NKTouch 0.7.5.3.3 Recorder Status Fix$' "$VERSION_FILE"
grep -q 'if \[ -n "$last" \]; then echo "latest=$last"; fi' "$REC"
grep -A12 '^  status)' "$REC" | grep -q 'exit 0'
grep -q 'V0.7.5.3.3 Recorder status fix' "$SETTINGS"
grep -q 'shellCandidates=@\[@"/var/jb/bin/sh",@"/var/jb/usr/bin/sh",@"/bin/sh"\]' "$SETTINGS"

echo "--- NKTouch v0.7.5.3.3 Recorder Status Fix package ---"
cat "$CONTROL"
cat "$VERSION_FILE"
