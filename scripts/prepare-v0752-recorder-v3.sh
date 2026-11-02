#!/usr/bin/env bash
set -euo pipefail
SRC="${1:-upstream}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

[[ -d "$SRC" ]] || { echo "Missing upstream source: $SRC" >&2; exit 1; }

# Freeze the proven 0.7.5.1 Sileo baseline (7.4.7 app/runtime) and only layer
# Recorder V3 + 0.7.5.2 package metadata on top.
bash "$ROOT/scripts/prepare-v0747-daily-driver.sh" "$SRC"

CONTROL="$SRC/control"
VERSION_FILE="$SRC/layout/usr/share/doc/nktouch/VERSION"
SETTINGS="$SRC/zxtouch/zxtouch/Settings/SettingsPageViewController.m"
RECORDER="$SRC/layout/usr/bin/nkrecorder"
EXPORTER="$SRC/layout/usr/share/nktouch/nkrecorder.lua"

install -m 0755 "$ROOT/runtime/nkrecorder-v3" "$RECORDER"
install -m 0644 "$ROOT/lua/nkrecorder_v3.lua" "$EXPORTER"
python3 "$ROOT/scripts/apply-v0752-recorder-v3.py" "$SRC"

python3 - "$CONTROL" "$VERSION_FILE" <<'PY'
from pathlib import Path
import sys
control=Path(sys.argv[1]); version_file=Path(sys.argv[2])

s=control.read_text()
s=s.replace('Version: 0.7.4.7','Version: 0.7.5.2',1)
for old in (
    'Description: NKTouch v0.7.4.7 Daily Driver with Self Test, Task Center, improved Logs UX and retained v0.7.4.6 direct Lua runtime baseline (GPL ZXTouch core)',
    'Description: NKTouch v0.7.4.7 Daily Driver with Self Test, Task Center, improved Logs UX and retained v0.7.4.6 direct Lua runtime baseline (GPL ZXTouch core)',
):
    if old in s:
        s=s.replace(old,'Description: NKTouch v0.7.5.2 Recorder V3 with record/pause/resume, editable touch timeline, test replay, Lua conversion, Task Center and retained direct lua54 runtime (GPL ZXTouch core)',1)
        break
if 'Version: 0.7.5.2' not in s:
    raise SystemExit('Unable to set package version 0.7.5.2')
control.write_text(s)

v=version_file.read_text()
v=v.replace('NKTouch 0.7.4.7 Daily Driver','NKTouch 0.7.5.2 Recorder V3',1)
extra='''Recorder V3: real HID tap/hold/swipe recording with pause/resume segments
Timeline: editable .nktl actions (type, delay, duration, coordinates, order)
Replay: one-tap Test through nktask and direct lua54 runtime
Convert: render timeline directly into NKTouch managed Lua scripts
Runtime baseline: 0.7.5.1 / 7.4.7 Daily Driver behavior retained
'''
if 'Recorder V3: real HID tap/hold/swipe' not in v:
    v=v.rstrip()+'\n'+extra
version_file.write_text(v)
PY

chmod 0755 "$RECORDER"

grep -q '^Version: 0.7.5.2$' "$CONTROL"
grep -q '^NKTouch 0.7.5.2 Recorder V3$' "$VERSION_FILE"
grep -q '^VERSION="0.7.5.2"$' "$RECORDER"
grep -q 'pause)' "$RECORDER"
grep -q 'resume)' "$RECORDER"
grep -q 'inspect)' "$RECORDER"
grep -q 'edit)' "$RECORDER"
grep -q 'render)' "$RECORDER"
grep -q 'test)' "$RECORDER"
grep -q 'Recorder V3 exporter v0.7.5.2' "$EXPORTER"
grep -q 'V0.7.5.2 Recorder V3' "$SETTINGS"
grep -q 'NKRecorderV3ViewController' "$SETTINGS"
grep -q 'Convert → Lua' "$SETTINGS"

echo "--- NKTouch v0.7.5.2 Recorder V3 package ---"
cat "$CONTROL"
cat "$VERSION_FILE"
