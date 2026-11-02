#!/usr/bin/env bash
set -euo pipefail
SRC="${1:-upstream}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

[[ -d "$SRC" ]] || { echo "Missing upstream source: $SRC" >&2; exit 1; }

bash "$ROOT/scripts/prepare-v07531-recorder-hotfix.sh" "$SRC"
python3 "$ROOT/scripts/apply-v07532-recorder-spawn-fix.py" "$SRC"

CONTROL="$SRC/control"
VERSION_FILE="$SRC/layout/usr/share/doc/nktouch/VERSION"
SETTINGS="$SRC/zxtouch/zxtouch/Settings/SettingsPageViewController.m"

python3 - "$CONTROL" "$VERSION_FILE" <<'PY'
from pathlib import Path
import sys
control=Path(sys.argv[1]); version_file=Path(sys.argv[2])
s=control.read_text()
s=s.replace('Version: 0.7.5.3.1','Version: 0.7.5.3.2',1)
for line in s.splitlines():
    if line.startswith('Description:'):
        s=s.replace(line,'Description: NKTouch v0.7.5.3.2 Recorder V3 spawn fix using trusted shell execution with rootless path fallback, visible diagnostics, Editor Pro, Task Center and direct lua54 runtime',1)
        break
control.write_text(s)

v=version_file.read_text().replace('NKTouch 0.7.5.3.1 Recorder Hotfix','NKTouch 0.7.5.3.2 Recorder Spawn Fix',1)
extra='''Recorder spawn fix: UI launches nkrecorder through a trusted shell instead of spawning the script directly
Shell fallback: /var/jb/bin/sh -> /var/jb/usr/bin/sh -> /bin/sh
Recorder diagnostics remain visible in the app UI
Editor Pro / Recorder V3 / Task Center / Self Test retained
'''
if 'Recorder spawn fix: UI launches nkrecorder through a trusted shell' not in v:
    v=v.rstrip()+'\n'+extra
version_file.write_text(v)
PY

grep -q '^Version: 0.7.5.3.2$' "$CONTROL"
grep -q '^NKTouch 0.7.5.3.2 Recorder Spawn Fix$' "$VERSION_FILE"
grep -q 'shellCandidates=@\[@"/var/jb/bin/sh",@"/var/jb/usr/bin/sh",@"/bin/sh"\]' "$SETTINGS"
grep -q 'isExecutableFileAtPath:candidate' "$SETTINGS"
grep -q 'posix_spawn(&pid,shell.UTF8String' "$SETTINGS"
grep -q 'argv\[1\]=strdup(NKRecorderV3Tool.UTF8String)' "$SETTINGS"
if grep -q 'posix_spawn(&pid,NKRecorderV3Tool.UTF8String' "$SETTINGS"; then
  echo 'Recorder still spawns script directly' >&2
  exit 1
fi

echo "--- NKTouch v0.7.5.3.2 Recorder Spawn Fix package ---"
cat "$CONTROL"
cat "$VERSION_FILE"
