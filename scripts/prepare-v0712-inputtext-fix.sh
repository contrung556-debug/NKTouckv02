#!/usr/bin/env bash
# Stage NKTouch v0.7.12 InputText Fix over retained v0.7.11 Target Apps.
set -euo pipefail
[[ $# -eq 1 ]] || { echo 'usage: prepare-v0712-inputtext-fix.sh <staged-upstream>' >&2; exit 2; }
SRC="$1"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
test -d "$SRC"
bash "$ROOT/scripts/prepare-v0711-target-apps.sh" "$SRC"
python3 "$ROOT/scripts/apply-v0712-inputtext-fix.py" "$SRC"
python3 - "$SRC/control" "$SRC/layout/usr/share/doc/nktouch/VERSION" "$SRC/layout/usr/bin/nktouchctl" "$SRC/zxtouch/zxtouch/Settings/SettingsPageViewController.m" <<'PY'
from pathlib import Path
import sys
control,version,ctl,ui=map(Path,sys.argv[1:])
c=control.read_text()
assert c.count("Version: 0.7.11")==1
c=c.replace("Version: 0.7.11","Version: 0.7.12",1)
for line in c.splitlines():
    if line.startswith("Description:"):
        c=c.replace(line,"Description: NKTouch v0.7.12 InputText Fix - Unicode safe inputText default and AutoTouch global in Lua editor; retains v0.7.11 Target Apps",1)
        break
control.write_text(c)
v=version.read_text()
assert v.count("NKTouch 0.7.11 Target Apps")==1
v=v.replace("NKTouch 0.7.11 Target Apps","NKTouch 0.7.12 InputText Fix",1)
v+="""InputText fix: nk.inputText(text) -> nk.inputTextV2(text) without retry
Lua Editor bootstrap: nk.installAutoTouchCompat() before loadfile(script)
Globals: inputText(text) exposed to scripts launched through editor
Legacy escape hatch: nk.text(text), nk.legacyInputText(text)
Input dispatch ACK is NOT proof that target field accepted text
"""
version.write_text(v)
s=ctl.read_text()
assert s.count('PACKAGE_VERSION="0.7.11"')==1
ctl.write_text(s.replace('PACKAGE_VERSION="0.7.11"','PACKAGE_VERSION="0.7.12"',1))
u=ui.read_text()
u=u.replace("NKTouch 0.7.11","NKTouch 0.7.12")
u=u.replace('nkLabel:@"0.7.11"','nkLabel:@"0.7.12"')
u=u.replace('text:@"0.7.11"','text:@"0.7.12"')
ui.write_text(u)
PY
LIB="$SRC/layout/usr/share/nktouch/lua/nktouch.lua"
UI="$SRC/zxtouch/zxtouch/Settings/SettingsPageViewController.m"
grep -Fxq 'Version: 0.7.12' "$SRC/control"
grep -Fxq 'NKTouch 0.7.12 InputText Fix' "$SRC/layout/usr/share/doc/nktouch/VERSION"
grep -Fq 'PACKAGE_VERSION="0.7.12"' "$SRC/layout/usr/bin/nktouchctl"
grep -Fq 'function M.inputText(value,options)' "$LIB"
grep -Fq 'return M.inputTextV2(value,options)' "$LIB"
grep -Fq 'M.legacyInputText=M.text' "$LIB"
if grep -Fq 'M.inputText=M.text' "$LIB"; then echo 'legacy default still active' >&2; exit 1; fi
grep -Fq 'nk.installAutoTouchCompat()' "$UI"
grep -Fq 'TARGET_NOT_FOREGROUND' "$UI"
grep -Fq 'function M.captureFrame()' "$LIB"
echo 'NKTouch 0.7.12 InputText Fix staged successfully'
