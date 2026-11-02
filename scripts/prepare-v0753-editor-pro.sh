#!/usr/bin/env bash
set -euo pipefail
SRC="${1:-upstream}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

[[ -d "$SRC" ]] || { echo "Missing upstream source: $SRC" >&2; exit 1; }

# Freeze 0.7.5.2 Recorder V3 and layer Editor Pro only.
bash "$ROOT/scripts/prepare-v0752-recorder-v3.sh" "$SRC"
python3 "$ROOT/scripts/apply-v0753-editor-pro.py" "$SRC"

CONTROL="$SRC/control"
VERSION_FILE="$SRC/layout/usr/share/doc/nktouch/VERSION"
SETTINGS="$SRC/zxtouch/zxtouch/Settings/SettingsPageViewController.m"
TASK_BIN="$SRC/layout/usr/bin/nktask"
RECORDER="$SRC/layout/usr/bin/nkrecorder"

python3 - "$CONTROL" "$VERSION_FILE" <<'PY'
from pathlib import Path
import sys
control=Path(sys.argv[1]); version_file=Path(sys.argv[2])
s=control.read_text()
s=s.replace('Version: 0.7.5.2','Version: 0.7.5.3',1)
old='Description: NKTouch v0.7.5.2 Recorder V3 with record/pause/resume, editable touch timeline, test replay, Lua conversion, Task Center and retained direct lua54 runtime (GPL ZXTouch core)'
new='Description: NKTouch v0.7.5.3 Editor Pro with line numbers, Find/Replace, API snippets, autosave backups, Recorder V3, Task Center and retained direct lua54 runtime (GPL ZXTouch core)'
if old in s:s=s.replace(old,new,1)
if 'Version: 0.7.5.3' not in s:raise SystemExit('Unable to set package version 0.7.5.3')
control.write_text(s)

v=version_file.read_text().replace('NKTouch 0.7.5.2 Recorder V3','NKTouch 0.7.5.3 Editor Pro',1)
extra='''Editor Pro: synchronized line-number gutter for Lua source
Find/Replace: find-next and replace-all inside the active script
API snippets: keyboard accessory + NKTouch snippet menu
Autosave: one-second debounce with rolling per-script backups and restore UI
Syntax UX: existing luac54 line parsing/jump behavior retained
Recorder V3: 0.7.5.2 record/pause/resume/timeline behavior retained
Runtime baseline: direct nktask -> lua54 remains unchanged
'''
if 'Editor Pro: synchronized line-number gutter' not in v:v=v.rstrip()+'\n'+extra
version_file.write_text(v)
PY

grep -q '^Version: 0.7.5.3$' "$CONTROL"
grep -q '^NKTouch 0.7.5.3 Editor Pro$' "$VERSION_FILE"
grep -q 'V0.7.5.3 Editor Pro' "$SETTINGS"
grep -q 'setupEditorPro' "$SETTINGS"
grep -q 'updateLineNumbers' "$SETTINGS"
grep -q 'Tìm / Thay thế' "$SETTINGS"
grep -q 'NKTouch Snippets' "$SETTINGS"
grep -q 'scheduleAutosave' "$SETTINGS"
grep -q '/var/mobile/Library/NKTouch/backups' "$SETTINGS"
grep -q 'Đã tự lưu' "$SETTINGS"
grep -q 'Editor ▾' "$SETTINGS"

# Runtime + Recorder invariants from the proven baseline.
test -x "$TASK_BIN"
test -x "$RECORDER"
strings "$TASK_BIN" | grep -Fq '/var/jb/usr/libexec/nktouch/lua54'
strings "$TASK_BIN" | grep -Fq 'spawn_failed executable='
if strings "$TASK_BIN" | grep -Fq '/var/jb/usr/bin/nktouch-lua'; then
  echo 'Regression: packaged nktask uses shell wrapper' >&2
  exit 1
fi
grep -q '^VERSION="0.7.5.2"$' "$RECORDER"
grep -q 'pause)' "$RECORDER"
grep -q 'resume)' "$RECORDER"
grep -q 'render)' "$RECORDER"

echo "--- NKTouch v0.7.5.3 Editor Pro package ---"
cat "$CONTROL"
cat "$VERSION_FILE"
