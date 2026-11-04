#!/usr/bin/env bash
set -euo pipefail
SRC="${1:-upstream}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
bash "$ROOT/scripts/prepare-v078-core-selftest.sh" "$SRC"

python3 - "$SRC/control" "$SRC/layout/usr/share/doc/nktouch/VERSION" "$SRC/layout/usr/bin/nktouchctl" "$SRC/zxtouch/zxtouch/Settings/SettingsPageViewController.m" <<'PY'
from pathlib import Path
import sys
control, version, ctl, ui = map(Path, sys.argv[1:])
c=control.read_text()
assert c.count("Version: 0.7.8")==1
c=c.replace("Version: 0.7.8","Version: 0.7.8.1",1)
for line in c.splitlines():
    if line.startswith("Description:"):
        c=c.replace(line, "Description: NKTouch 0.7.8.1 Core Self-Test UI hotfix; doctor is informational and Lua Core PASS uses actual task outcome",1)
        break
control.write_text(c)
v=version.read_text().replace("NKTouch 0.7.8 Lua Core Self-Test","NKTouch 0.7.8.1 Lua Core Self-Test Hotfix",1)
v+="Self-Test UI: optional doctor no longer changes Core PASS/FAIL result\n"
version.write_text(v)
s=ctl.read_text()
assert s.count('PACKAGE_VERSION="0.7.8"')==1
ctl.write_text(s.replace('PACKAGE_VERSION="0.7.8"','PACKAGE_VERSION="0.7.8.1"',1))
u=ui.read_text().replace("NKTouch 0.7.8", "NKTouch 0.7.8.1")
u=u.replace('nkLabel:@"0.7.8"', 'nkLabel:@"0.7.8.1"')
u=u.replace('text:@"0.7.8"', 'text:@"0.7.8.1"')
ui.write_text(u)
PY

grep -Fxq "Version: 0.7.8.1" "$SRC/control"
grep -Fq 'PACKAGE_VERSION="0.7.8.1"' "$SRC/layout/usr/bin/nktouchctl"
grep -Fq 'Doctor (optional)' "$SRC/zxtouch/zxtouch/Settings/SettingsPageViewController.m"
grep -Fq 'BOOL pass=wrote&&cc==0&&rc==0&&' "$SRC/zxtouch/zxtouch/Settings/SettingsPageViewController.m"
if grep -Fq 'BOOL pass=wrote&&cc==0&&dc==0&&rc==0&&' "$SRC/zxtouch/zxtouch/Settings/SettingsPageViewController.m"; then
    echo 'ERROR: original false-fail predicate remains' >&2
    exit 1
fi
test -f "$SRC/layout/usr/share/nktouch/lua/nkcore_selftest.lua"
test ! -e "$SRC/layout/var/jb"
echo 'NKTouch 0.7.8.1 Core Self-Test false-fail hotfix verified'
