#!/usr/bin/env bash
# NKTouch 0.8.10 Runtime Self-Test overlay after v0.8.9.
# Candidate artifact only; no Sileo publish or native supervisor change.
set -euo pipefail
[[ $# -eq 1 ]] || { echo 'usage: stage-v0810-runtime-selftest.sh <staged-upstream>' >&2; exit 2; }
SRC="$1"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EXAMPLES="$SRC/layout/usr/share/nktouch/examples"
CONTROL="$SRC/control"
CTL="$SRC/layout/usr/bin/nktouchctl"
VERSION="$SRC/layout/usr/share/doc/nktouch/VERSION"
UI="$SRC/zxtouch/zxtouch/Settings/SettingsPageViewController.m"
LAB="$SRC/layout/usr/share/nktouch/lua/nktestlab.lua"
for p in "$CONTROL" "$CTL" "$VERSION" "$UI" "$LAB" "$SRC/layout/usr/bin/nktask"; do test -s "$p"; done
grep -Fxq 'Version: 0.8.9' "$CONTROL"
grep -Fq 'PACKAGE_VERSION="0.8.9"' "$CTL"
grep -Fq 'NKTouch Test Lab v0.8.9-beta' "$LAB"
mkdir -p "$EXAMPLES"
install -m 0644 "$ROOT/examples/test_runtime_selftest_v0810.lua" "$EXAMPLES/test_runtime_selftest_v0810.lua"
python3 - "$CONTROL" "$CTL" "$VERSION" "$UI" "$LAB" <<'PY'
from pathlib import Path
import sys
control,ctl,version,ui,lab=map(Path,sys.argv[1:])
def exactly(path,old,new):
    data=path.read_text()
    if data.count(old)!=1:
        raise SystemExit(f"{path}: expected one {old!r}, got {data.count(old)}")
    path.write_text(data.replace(old,new,1))
exactly(control,"Version: 0.8.9","Version: 0.8.10")
exactly(control,
  "Description: NKTouch v0.8.9 Runtime Reliability beta: cooperative Lua deadlines, cancel checks, once-only mutation guard, LIFO cleanup and private diagnostics; retains Vision, Native Input and Precision",
  "Description: NKTouch v0.8.10 Runtime Self-Test beta: Lua and io.popen diagnostics with read-only cranectl list sample; retains v0.8.9 Runtime, Vision, Native Input and Precision")
exactly(ctl,'PACKAGE_VERSION="0.8.9"','PACKAGE_VERSION="0.8.10"')
exactly(version,"NKTouch 0.8.9 Runtime Reliability Beta",
                "NKTouch 0.8.10 Runtime Self-Test Beta")
with version.open("a") as out:
    out.write("""
v0.8.10: adds an in-app, read-only Lua/runtime self-test sample. Checks module
loading, runtime/screen/sleep, io.popen output+exit status, and optional
cranectl --list. It never creates or switches a container. Real-device
validation is required before any Sileo release.
""")
exactly(lab,'-- NKTouch Test Lab v0.8.9-beta',
            '-- NKTouch Test Lab v0.8.10-beta')
exactly(lab,'local M={VERSION="0.8.9-beta"}',
            'local M={VERSION="0.8.10-beta"}')
src=ui.read_text()
src=src.replace("NKTouch 0.8.9","NKTouch 0.8.10")
src=src.replace('nkLabel:@"0.8.9"','nkLabel:@"0.8.10"')
src=src.replace('text:@"0.8.9"','text:@"0.8.10"')
src=src.replace('-- NKTouch Test Lab v0.8.9-beta','-- NKTouch Test Lab v0.8.10-beta')
installer='@{@"file":@"test_runtime_guard_readonly_v089.lua", @"bundle":@"com.apple.mobilenotes"}'
menu='@{@"title":@"Runtime • Deadline / Dọn tài nguyên", @"file":@"test_runtime_guard_readonly_v089.lua"}'
if src.count(installer)!=1: raise SystemExit("v0.8.9 Samples installer changed")
if src.count(menu)!=1: raise SystemExit("v0.8.9 Samples menu changed")
src=src.replace(installer,
    '@{@"file":@"test_runtime_selftest_v0810.lua", @"bundle":@"com.apple.mobilenotes"},\n        '+installer,1)
src=src.replace(menu,
    '@{@"title":@"Runtime • Tự kiểm tra Lua / io.popen", @"file":@"test_runtime_selftest_v0810.lua"},\n        '+menu,1)
ui.write_text(src)
PY
grep -Fxq 'Version: 0.8.10' "$CONTROL"
grep -Fq 'PACKAGE_VERSION="0.8.10"' "$CTL"
grep -Fq 'test_runtime_selftest_v0810.lua' "$UI"
grep -Fq 'Runtime • Tự kiểm tra Lua / io.popen' "$UI"
test -s "$EXAMPLES/test_runtime_selftest_v0810.lua"
test ! -e "$SRC/layout/var/jb"
echo '[NKRT810] staged read-only Runtime Self-Test sample; native supervisor intact; Sileo unchanged'
