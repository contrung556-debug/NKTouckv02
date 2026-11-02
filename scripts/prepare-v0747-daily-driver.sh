#!/usr/bin/env bash
set -euo pipefail
SRC="${1:-upstream}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

[[ -d "$SRC" ]] || { echo "Missing upstream source: $SRC" >&2; exit 1; }

# 7.4.6 is the frozen runtime baseline: direct lua54 spawn, no shell-wrapper
# dependency. 7.4.7 adds only daily-driver UI/diagnostics on top.
bash "$ROOT/scripts/prepare-v0746-direct-lua-spawn.sh" "$SRC"

CONTROL="$SRC/control"
VERSION_FILE="$SRC/layout/usr/share/doc/nktouch/VERSION"
SETTINGS="$SRC/zxtouch/zxtouch/Settings/SettingsPageViewController.m"
TASK_BIN="$SRC/layout/usr/bin/nktask"

# Older hotfix layers produced two equivalent formatting variants of logsTapped.
# Normalize that one UI method before the 7.4.7 transform; runtime behavior is
# unchanged. This keeps the Daily Driver patch deterministic without weakening
# its regression checks.
python3 - "$SETTINGS" <<'PY'
from pathlib import Path
import re, sys
p=Path(sys.argv[1]); s=p.read_text()
method='- (void)logsTapped{__weak typeof(self)w=self;NSMutableArray*args=[NSMutableArray arrayWithObject:@"logs"];if(self.taskID.length){[args addObject:self.taskID];[args addObject:@"100"];}[self command:args state:@"Đang tải logs…" done:^(int c,NSString *o){if(c!=0){w.console.text=@"[NKTouch] Chưa có tác vụ hoặc log để hiển thị.";w.runState.text=@"Log chưa sẵn sàng";w.runState.textColor=NKMuted();} else {w.console.text=o;[w pollTaskStatus];}}];}'
pat=re.compile(r'- \(void\)logsTapped\{.*?\}\n- \(void\)viewWillDisappear:', re.S)
s,n=pat.subn(method+'\n- (void)viewWillDisappear:',s,count=1)
if n!=1:
    raise SystemExit(f'Unable to normalize logsTapped, count={n}')
p.write_text(s)
PY

python3 "$ROOT/scripts/apply-v747-daily-driver.py" "$SRC"

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
