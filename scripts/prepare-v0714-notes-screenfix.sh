#!/usr/bin/env bash
# NKTouch v0.7.14: fix Apple Notes sample screen dimensions parsing.
set -euo pipefail
[[ $# -eq 1 ]] || { echo 'usage: prepare-v0714-notes-screenfix.sh <staged-upstream>' >&2; exit 2; }
SRC="$1"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
test -d "$SRC"
bash "$ROOT/scripts/prepare-v0713-notes-input-selftest.sh" "$SRC"
install -m 0644 "$ROOT/examples/test_inputtext_notes_v2.lua" "$SRC/layout/usr/share/nktouch/examples/test_inputtext_notes_v2.lua"
python3 "$ROOT/scripts/apply-v0714-notes-screenfix.py" "$SRC"
python3 - "$SRC/control" "$SRC/layout/usr/share/doc/nktouch/VERSION" "$SRC/layout/usr/bin/nktouchctl" "$SRC/zxtouch/zxtouch/Settings/SettingsPageViewController.m" <<'PY'
from pathlib import Path
import sys
control,version,ctl,ui=map(Path,sys.argv[1:])
c=control.read_text()
assert c.count("Version: 0.7.13")==1
c=c.replace("Version: 0.7.13","Version: 0.7.14",1)
for line in c.splitlines():
    if line.startswith("Description:"):
        c=c.replace(line,"Description: NKTouch v0.7.14 Notes Screen Fix - supports decimal screen sizes and preserves user-edited Lua samples; retains v0.7.13 Notes test and v0.7.12 InputText Fix",1)
        break
control.write_text(c)
v=version.read_text()
assert v.count("NKTouch 0.7.13 Notes InputText Selftest")==1
v=v.replace("NKTouch 0.7.13 Notes InputText Selftest","NKTouch 0.7.14 Notes Screen Fix",1)
v+="""Notes inputText v2: accepts screen dimensions like 750.000000;;1334.000000
New sample: Lua Workspace > Samples > test_inputtext_notes_v2.lua
Old sample kept for user edits, never overwritten
Built-in example only; no native input/touch changes
"""
version.write_text(v)
s=ctl.read_text()
assert s.count('PACKAGE_VERSION="0.7.13"')==1
ctl.write_text(s.replace('PACKAGE_VERSION="0.7.13"','PACKAGE_VERSION="0.7.14"',1))
u=ui.read_text()
u=u.replace("NKTouch 0.7.13","NKTouch 0.7.14")
u=u.replace('nkLabel:@"0.7.13"','nkLabel:@"0.7.14"')
u=u.replace('text:@"0.7.13"','text:@"0.7.14"')
ui.write_text(u)
PY
LIB="$SRC/layout/usr/share/nktouch/lua/nktouch.lua"
UI="$SRC/zxtouch/zxtouch/Settings/SettingsPageViewController.m"
SAMPLE="$SRC/layout/usr/share/nktouch/examples/test_inputtext_notes_v2.lua"
grep -Fxq 'Version: 0.7.14' "$SRC/control"
grep -Fxq 'NKTouch 0.7.14 Notes Screen Fix' "$SRC/layout/usr/share/doc/nktouch/VERSION"
grep -Fq 'PACKAGE_VERSION="0.7.14"' "$SRC/layout/usr/bin/nktouchctl"
grep -Fq 'function M.inputText(value,options)' "$LIB"
grep -Fq 'NKSaveTarget(sampleName,@"com.apple.mobilenotes",@"Ghi chú")' "$UI"
grep -Fq 'test_inputtext_notes_v2.lua' "$UI"
grep -Fq '(%d+%.?%d*)' "$SAMPLE"
grep -Fq 'nk.inputText(TEST_TEXT)' "$SAMPLE"
test -s "$SRC/layout/usr/share/nktouch/examples/test_inputtext_notes.lua"
test -s "$SAMPLE"
echo 'NKTouch 0.7.14 Notes Screen Fix staged; existing v1 samples preserved'
