#!/usr/bin/env bash
set -euo pipefail
SRC="${1:-upstream}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

[[ -d "$SRC" ]] || { echo "Missing upstream source: $SRC" >&2; exit 1; }

bash "$ROOT/scripts/prepare-v0753-editor-pro.sh" "$SRC"
python3 "$ROOT/scripts/apply-v07531-recorder-hotfix.py" "$SRC"

CONTROL="$SRC/control"
VERSION_FILE="$SRC/layout/usr/share/doc/nktouch/VERSION"
SETTINGS="$SRC/zxtouch/zxtouch/Settings/SettingsPageViewController.m"
RECORDER="$SRC/layout/usr/bin/nkrecorder"

python3 - "$CONTROL" "$VERSION_FILE" <<'PY'
from pathlib import Path
import sys
control=Path(sys.argv[1]); version_file=Path(sys.argv[2])
s=control.read_text()
s=s.replace('Version: 0.7.5.3','Version: 0.7.5.3.1',1)
for line in s.splitlines():
    if line.startswith('Description:'):
        s=s.replace(line,'Description: NKTouch v0.7.5.3.1 Recorder V3 hotfix with corrected rootless shell launcher, visible recorder diagnostics, Editor Pro, Recorder V3, Task Center and retained direct lua54 runtime',1)
        break
control.write_text(s)

v=version_file.read_text().replace('NKTouch 0.7.5.3 Editor Pro','NKTouch 0.7.5.3.1 Recorder Hotfix',1)
extra='''Recorder hotfix: nkrecorder uses /var/jb/usr/bin/sh on rootless bootstrap
Recorder diagnostics: status failure is shown in Recorder UI instead of hanging on Loading
Editor Pro / Recorder V3 / Task Center / Self Test retained
Runtime baseline: nktask direct lua54 remains unchanged
'''
if 'Recorder hotfix: nkrecorder uses /var/jb/usr/bin/sh' not in v:
    v=v.rstrip()+'\n'+extra
version_file.write_text(v)
PY

grep -q '^Version: 0.7.5.3.1$' "$CONTROL"
grep -q '^NKTouch 0.7.5.3.1 Recorder Hotfix$' "$VERSION_FILE"
head -n1 "$RECORDER" | grep -Fx '#!/var/jb/usr/bin/sh'
grep -q '^VERSION="0.7.5.3.1"$' "$RECORDER"
grep -q 'V0.7.5.3.1 Recorder hotfix' "$SETTINGS"
grep -q 'RECORDER LỖI' "$SETTINGS"
grep -q 'Không chạy được nkrecorder' "$SETTINGS"
grep -q 'V0.7.5.3 Editor Pro' "$SETTINGS"
grep -q 'Recorder V3' "$SETTINGS"

echo "--- NKTouch v0.7.5.3.1 Recorder Hotfix package ---"
cat "$CONTROL"
cat "$VERSION_FILE"
