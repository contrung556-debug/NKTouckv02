#!/usr/bin/env bash
set -euo pipefail
SRC="${1:-upstream}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

[[ -d "$SRC" ]] || { echo "Missing upstream source: $SRC" >&2; exit 1; }

# Retain all 7.4.5 UX/check/bootstrap fixes. The task engine binary must have
# already been rebuilt from the v7.4.6-patched runtime/nktask.c by CI.
bash "$ROOT/scripts/prepare-v0745-task-bootstrap-fix.sh" "$SRC"

CONTROL="$SRC/control"
VERSION_FILE="$SRC/layout/usr/share/doc/nktouch/VERSION"
SETTINGS="$SRC/zxtouch/zxtouch/Settings/SettingsPageViewController.m"
TASK_BIN="$SRC/layout/usr/bin/nktask"

python3 - "$CONTROL" "$VERSION_FILE" "$SETTINGS" <<'PY'
from pathlib import Path
import sys

control=Path(sys.argv[1]); version_file=Path(sys.argv[2]); settings=Path(sys.argv[3])

s=control.read_text()
s=s.replace('Version: 0.7.4.5','Version: 0.7.4.6',1)
s=s.replace(
    'Description: NKTouch v0.7.4.5 task bootstrap fix with runtime diagnostics, direct Lua syntax/task execution and retained NKTouch shell UX (GPL ZXTouch core)',
    'Description: NKTouch v0.7.4.6 direct Lua spawn fix removing shell-wrapper dependency, with runtime diagnostics and retained NKTouch UX (GPL ZXTouch core)'
)
if 'Version: 0.7.4.6' not in s:
    raise SystemExit('Unable to set package version 0.7.4.6')
control.write_text(s)

v=version_file.read_text()
v=v.replace('NKTouch 0.7.4.5 Task Bootstrap Fix','NKTouch 0.7.4.6 Direct Lua Spawn Fix',1)
extra='Runtime fix: nktask launches bundled lua54 directly; no /var/jb/bin/sh dependency\nRuntime diagnostics: spawn failures include executable / errno / error text in task log\nCore task supervisor contract remains V7.0 (0.7.0)\n'
if 'Runtime fix: nktask launches bundled lua54 directly' not in v:
    v=v.rstrip()+'\n'+extra
version_file.write_text(v)

u=settings.read_text()
u=u.replace('NKTouch 0.7.4.5','NKTouch 0.7.4.6')
u=u.replace('text:@"7.4.5"','text:@"7.4.6"')
marker='// V7.4.6 direct Lua spawn fix: nktask -> lua54, no shell-wrapper dependency.\n'
if marker not in u:
    anchor='// V7.4.5 task bootstrap fix: optional compat hook + terminal runtime diagnostics.\n'
    if anchor in u: u=u.replace(anchor,anchor+marker,1)
    else: u=marker+u
settings.write_text(u)
PY

test -x "$TASK_BIN"
# Check the packaged binary itself, not only source text.
strings "$TASK_BIN" | grep -Fq '/var/jb/usr/libexec/nktouch/lua54'
if strings "$TASK_BIN" | grep -Fq '/var/jb/usr/bin/nktouch-lua'; then
    echo 'Regression: packaged nktask still depends on shell wrapper' >&2
    exit 1
fi
strings "$TASK_BIN" | grep -Fq 'spawn_failed executable='
strings "$TASK_BIN" | grep -Fq '0.7.0'

grep -q '^Version: 0.7.4.6$' "$CONTROL"
grep -q '^NKTouch 0.7.4.6 Direct Lua Spawn Fix$' "$VERSION_FILE"
grep -q 'V7.4.6 direct Lua spawn fix' "$SETTINGS"

echo "--- NKTouch v0.7.4.6 direct Lua spawn package ---"
cat "$CONTROL"
cat "$VERSION_FILE"
