#!/usr/bin/env bash
# Stage NKTouch v0.7.13 Notes InputText self-test over v0.7.12 fix.
set -euo pipefail
[[ $# -eq 1 ]] || { echo 'usage: prepare-v0713-notes-input-selftest.sh <staged-upstream>' >&2; exit 2; }
SRC="$1"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
test -d "$SRC"
bash "$ROOT/scripts/prepare-v0712-inputtext-fix.sh" "$SRC"
mkdir -p "$SRC/layout/usr/share/nktouch/examples"
install -m 0644 "$ROOT/examples/test_inputtext_notes.lua" "$SRC/layout/usr/share/nktouch/examples/test_inputtext_notes.lua"
python3 "$ROOT/scripts/apply-v0713-notes-input-selftest.py" "$SRC"
python3 - "$SRC/control" "$SRC/layout/usr/share/doc/nktouch/VERSION" "$SRC/layout/usr/bin/nktouchctl" "$SRC/zxtouch/zxtouch/Settings/SettingsPageViewController.m" <<'PY'
from pathlib import Path
import sys
control,version,ctl,ui=map(Path,sys.argv[1:])
c=control.read_text()
assert c.count("Version: 0.7.12")==1,"expected v0.7.12 staged baseline"
c=c.replace("Version: 0.7.12","Version: 0.7.13",1)
for line in c.splitlines():
    if line.startswith("Description:"):
        c=c.replace(line,"Description: NKTouch v0.7.13 Notes InputText Selftest - built-in guided Lua example in Samples; retains v0.7.12 InputText Fix and v0.7.11 Target Apps",1)
        break
control.write_text(c)
v=version.read_text()
assert v.count("NKTouch 0.7.12 InputText Fix")==1
v=v.replace("NKTouch 0.7.12 InputText Fix","NKTouch 0.7.13 Notes InputText Selftest",1)
v+="""Built-in example: Lua Workspace > Samples > test_inputtext_notes.lua
Auto-install sample only if missing; keep existing user edits
Default sample target: Apple Notes (com.apple.mobilenotes)
Steps: openApp > waitApp > tap New Note > tap editor > inputText
Logs include per-stage results; OCR verification is advisory (no auto retry)
UI layout differs by iOS: edit tap coordinates in the example if needed
"""
version.write_text(v)
s=ctl.read_text()
assert s.count('PACKAGE_VERSION="0.7.12"')==1
ctl.write_text(s.replace('PACKAGE_VERSION="0.7.12"','PACKAGE_VERSION="0.7.13"',1))
u=ui.read_text()
u=u.replace("NKTouch 0.7.12","NKTouch 0.7.13")
u=u.replace('nkLabel:@"0.7.12"','nkLabel:@"0.7.13"')
u=u.replace('text:@"0.7.12"','text:@"0.7.13"')
ui.write_text(u)
PY
LIB="$SRC/layout/usr/share/nktouch/lua/nktouch.lua"
UI="$SRC/zxtouch/zxtouch/Settings/SettingsPageViewController.m"
SAMPLE="$SRC/layout/usr/share/nktouch/examples/test_inputtext_notes.lua"
grep -Fxq 'Version: 0.7.13' "$SRC/control"
grep -Fxq 'NKTouch 0.7.13 Notes InputText Selftest' "$SRC/layout/usr/share/doc/nktouch/VERSION"
grep -Fq 'PACKAGE_VERSION="0.7.13"' "$SRC/layout/usr/bin/nktouchctl"
grep -Fq 'function M.inputText(value,options)' "$LIB"
grep -Fq 'return M.inputTextV2(value,options)' "$LIB"
grep -Fq 'nk.installAutoTouchCompat()' "$UI"
grep -Fq 'NKTargetForScript(sampleName)' "$UI"
grep -Fq 'com.apple.mobilenotes' "$UI"
grep -Fq 'initWithScriptName:@"test_inputtext_notes.lua"' "$UI"
grep -Fq 'nk.waitApp(NOTES_ID, 10000, 250)' "$SAMPLE"
grep -Fq 'nk.inputText(TEST_TEXT)' "$SAMPLE"
grep -Fq 'TARGET_NOT_FOREGROUND' "$UI"
test -s "$SAMPLE"
echo 'NKTouch 0.7.13 Notes InputText example staged successfully'
