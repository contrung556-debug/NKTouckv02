#!/usr/bin/env bash
# NKTouch v0.8.0 Integrated Beta: ONE consolidated rootless build.
# Staging only. No Sileo publication, no background jobs, no deb compilation.
set -euo pipefail
[[ $# -eq 1 ]] || { echo 'usage: prepare-v0800-release.sh <staged-upstream>' >&2; exit 2; }
SRC="$1"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
test -d "$SRC"
bash "$ROOT/scripts/prepare-v0719-release.sh" "$SRC"

LIB="$SRC/layout/usr/share/nktouch/lua"
CTL="$SRC/layout/usr/bin/nktouchctl"
UI="$SRC/zxtouch/zxtouch/Settings/SettingsPageViewController.m"
CONTROL="$SRC/control"
VERSION="$SRC/layout/usr/share/doc/nktouch/VERSION"
EXAMPLES="$SRC/layout/usr/share/nktouch/examples"

for name in nkdiagnostics nksnapshot nkactions nksdk; do
  install -m 0644 "$ROOT/lua/$name.lua" "$LIB/$name.lua"
done
mkdir -p "$EXAMPLES"
install -m 0644 "$ROOT/examples/nk_v0800_readonly_demo.lua" \
  "$EXAMPLES/nk_v0800_readonly_demo.lua"
python3 - "$CONTROL" "$VERSION" "$CTL" "$UI" "$LIB/nktestlab.lua" <<'PY'
from pathlib import Path
import sys
control,version,ctl,ui,lab=map(Path,sys.argv[1:])
def strict_replace(path,old,new):
    s=path.read_text()
    count=s.count(old)
    if count!=1:
        raise SystemExit(f"{path}: expected one {old!r}, found {count}")
    path.write_text(s.replace(old,new,1))

strict_replace(control,"Version: 0.7.19","Version: 0.8.0")
s=control.read_text()
s=s.replace(
    "Description: NKTouch v0.7.19 Five-Core Test Lab (OCR Color Touch InputText Memory), detailed PASS/FAIL/WARN logs and reports; read-only default, device validation pending",
    "Description: NKTouch v0.8.0 Integrated Lua SDK beta: Test Lab OCR Color Touch InputText Memory, diagnostics, snapshot batching, safe actions and reports; device validation pending")
control.write_text(s)
strict_replace(ctl,'PACKAGE_VERSION="0.7.19"','PACKAGE_VERSION="0.8.0"')
strict_replace(version,"NKTouch 0.7.19 Five-Core Test Lab Beta",
               "NKTouch 0.8.0 Integrated Lua SDK Beta")
with version.open("a") as f:
    f.write("""
v0.8.0 beta: bundled nkdiagnostics, nksnapshot, nkactions and nksdk.
Includes one-frame Vision batch, bounded read-only waitText/waitColor,
strict opt-in guarded gestures/input, task exit/signal reading and privacy-
safe last native API checkpointing. Test Lab gains Diagnostics & Crash
as an optional group. Existing nktouch_v7 Lua API remains unchanged.
On-device accuracy and crash shutdown still require explicit testing.
""")
s=ui.read_text().replace("NKTouch 0.7.19","NKTouch 0.8.0")
s=s.replace('nkLabel:@"0.7.19"','nkLabel:@"0.8.0"')
s=s.replace('text:@"0.7.19"','text:@"0.8.0"')
s=s.replace("-- NKTouch Test Lab v0.7.19-dev","-- NKTouch Test Lab v0.8.0-beta")
ui.write_text(s)
strict_replace(lab,"-- NKTouch Test Lab v0.7.19-dev",
                   "-- NKTouch Test Lab v0.8.0-beta")
strict_replace(lab,'local M={VERSION="0.7.19-dev"}',
                   'local M={VERSION="0.8.0-beta"}')
PY

grep -Fxq 'Version: 0.8.0' "$CONTROL"
grep -Fq 'PACKAGE_VERSION="0.8.0"' "$CTL"
grep -Fq 'NKTouch 0.8.0 Integrated Lua SDK Beta' "$VERSION"
grep -Fq 'NKTouch Test Lab v0.8.0-beta' "$LIB/nktestlab.lua"
grep -Fq 'handlers.diagnostics=function()' "$LIB/nktestlab.lua"
grep -Fq 'Diagnostics & Crash' "$UI"
grep -Fq 'labSelectCorePreset' "$UI"
grep -Fq 'memory={loops=10}' "$UI"
for name in nkdiagnostics nksnapshot nkactions nksdk; do
  test -s "$LIB/$name.lua"
done
test -s "$EXAMPLES/nk_v0800_readonly_demo.lua"
test ! -e "$SRC/layout/var/jb"
echo 'NKTouch v0.8.0 integrated beta staged: artifact only, no Sileo publication'
