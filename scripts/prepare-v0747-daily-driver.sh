#!/usr/bin/env bash
set -euo pipefail
SRC="${1:-upstream}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

[[ -d "$SRC" ]] || { echo "Missing upstream source: $SRC" >&2; exit 1; }

# 7.4.6 is the frozen runtime baseline: direct lua54 spawn, no shell-wrapper
# dependency. 7.4.7 adds only daily-driver UI/diagnostics on top.
bash "$ROOT/scripts/prepare-v0746-direct-lua-spawn.sh" "$SRC"
python3 "$ROOT/scripts/apply-v747-daily-driver.py" "$SRC"

CONTROL="$SRC/control"
VERSION_FILE="$SRC/layout/usr/share/doc/nktouch/VERSION"
SETTINGS="$SRC/zxtouch/zxtouch/Settings/SettingsPageViewController.m"
TASK_BIN="$SRC/layout/usr/bin/nktask"

python3 - "$CONTROL" "$VERSION_FILE" <<'PY'
from pathlib import Path
import sys
control=Path(sys.argv[1]); version_file=Path(sys.argv[2])

s=control.read_text()
s=s.replace('Version: 0.7.4.6','Version: 0.7.4.7',1)
s=s.replace(
    'Description: NKTouch v0.7.4.6 direct Lua spawn fix removing shell-wrapper dependency, with runtime diagnostics and retained NKTouch UX (GPL ZXTouch core)',
    'Description: NKTouch v0.7.4.7 Daily Driver with Self Test, Task Center, improved Logs UX and retained v0.7.4.6 direct Lua runtime baseline (GPL ZXTouch core)'
)
if 'Version: 0.7.4.7' not in s:
    raise SystemExit('Unable to set package version 0.7.4.7')
control.write_text(s)

v=version_file.read_text()
v=v.replace('NKTouch 0.7.4.6 Direct Lua Spawn Fix','NKTouch 0.7.4.7 Daily Driver',1)
extra='Daily Driver: one-tap end-to-end Self Test (luac54 -> nktask -> lua54 -> logs)\nTask Center: task history, state, logs, copy and stop controls\nEditor UX: auto-scroll logs and Copy Log action\nRuntime baseline: V7.4.6 direct Lua spawn retained unchanged\n'
if 'Daily Driver: one-tap end-to-end Self Test' not in v:
    v=v.rstrip()+'\n'+extra
version_file.write_text(v)
PY

# Runtime invariants: 7.4.7 must not regress the 7.4.6 direct-spawn fix.
test -x "$TASK_BIN"
strings "$TASK_BIN" | grep -Fq '/var/jb/usr/libexec/nktouch/lua54'
strings "$TASK_BIN" | grep -Fq 'spawn_failed executable='
strings "$TASK_BIN" | grep -Fq '0.7.0'
if strings "$TASK_BIN" | grep -Fq '/var/jb/usr/bin/nktouch-lua'; then
    echo 'Regression: packaged nktask uses shell wrapper' >&2
    exit 1
fi

grep -q '^Version: 0.7.4.7$' "$CONTROL"
grep -q '^NKTouch 0.7.4.7 Daily Driver$' "$VERSION_FILE"
grep -q 'V7.4.7 daily driver' "$SETTINGS"
grep -q 'Task Center' "$SETTINGS"
grep -q 'Self Test' "$SETTINGS"
grep -q 'NKTaskCenterViewController' "$SETTINGS"
grep -q '\[SELFTEST\] task=ok' "$SETTINGS"
grep -q 'copyCurrentLog' "$SETTINGS"

echo "--- NKTouch v0.7.4.7 Daily Driver package ---"
cat "$CONTROL"
cat "$VERSION_FILE"
