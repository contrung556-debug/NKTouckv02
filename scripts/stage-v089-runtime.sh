#!/usr/bin/env bash
# NKTouch 0.8.9 Runtime Reliability overlay after v0.8.8.
# Candidate only: no Sileo mutation, no native supervisor replacement.
set -euo pipefail
[[ $# -eq 1 ]] || { echo 'usage: stage-v089-runtime.sh <staged-upstream>' >&2; exit 2; }
SRC="$1"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LIB="$SRC/layout/usr/share/nktouch/lua"
EXAMPLES="$SRC/layout/usr/share/nktouch/examples"
CONTROL="$SRC/control"
CTL="$SRC/layout/usr/bin/nktouchctl"
VERSION="$SRC/layout/usr/share/doc/nktouch/VERSION"
UI="$SRC/zxtouch/zxtouch/Settings/SettingsPageViewController.m"
LAB="$LIB/nktestlab.lua"
for p in "$LIB/nktouch.lua" "$LIB/nkvision_speed.lua" "$LIB/nkvision.lua" "$LIB/nkinput_pro.lua" "$LIB/nkprecision.lua" "$LIB/nkdiagnostics.lua" "$LIB/nkmemory.lua" "$CTL" "$VERSION" "$UI" "$LAB" "$CONTROL"; do test -s "$p"; done
grep -Fxq 'Version: 0.8.8' "$CONTROL"
grep -Fq 'PACKAGE_VERSION="0.8.8"' "$CTL"
grep -Fq 'NKTouch Test Lab v0.8.8-beta' "$LAB"
grep -Fq 'function M.visionBatch(plan,options)' "$LIB/nktouch.lua"
grep -Fq 'function M.focusedInput(bundle)' "$LIB/nktouch.lua"
test -s "$SRC/layout/usr/bin/nktask"
mkdir -p "$LIB" "$EXAMPLES"
install -m 0644 "$ROOT/lua/nkruntime_guard.lua" "$LIB/nkruntime_guard.lua"
install -m 0644 "$ROOT/examples/test_runtime_guard_readonly_v089.lua" "$EXAMPLES/test_runtime_guard_readonly_v089.lua"
install -m 0644 "$ROOT/examples/test_runtime_guard_write_optin_v089.lua" "$EXAMPLES/test_runtime_guard_write_optin_v089.lua"

python3 - "$CONTROL" "$CTL" "$VERSION" "$UI" "$LAB" "$LIB/nktouch.lua" <<'PY'
from pathlib import Path
import sys
control,ctl,version,ui,lab,api=map(Path,sys.argv[1:])
def exactly(path,old,new):
    data=path.read_text()
    if data.count(old)!=1:
        raise SystemExit(f"{path}: expected one {old!r}, got {data.count(old)}")
    path.write_text(data.replace(old,new,1))
exactly(control,"Version: 0.8.8","Version: 0.8.9")
exactly(control,
  "Description: NKTouch v0.8.8 Vision Speed Stability beta: one-frame Color/OCR/Image batch with cached pixels, bounded stable-screen gate; retains Native Input and Precision",
  "Description: NKTouch v0.8.9 Runtime Reliability beta: cooperative Lua deadlines, cancel checks, once-only mutation guard, LIFO cleanup and private diagnostics; retains Vision, Native Input and Precision")
exactly(ctl,'PACKAGE_VERSION="0.8.8"','PACKAGE_VERSION="0.8.9"')
exactly(version,"NKTouch 0.8.8 Vision Speed and Screen Stability Beta",
                "NKTouch 0.8.9 Runtime Reliability Beta")
with version.open("a") as out:
    out.write("""
v0.8.9: cooperative Lua guard for deadlines and optional cancellation checks
BETWEEN script actions; native nktask still enforces hard process stop/timeout.
Explicit write onceKey reserved before dispatch; no blind mutation retry.
Registered finalizers run LIFO on regular Lua completion or caught errors,
NOT after SIGKILL/native crash. Structured diagnostics do not retain user
arguments, secrets, OCR content, callback results or raw exceptions.
Every existing v0.8.8 Vision, v0.8.7 Native Focus, v0.8.6 Precision,
Recorder, Touch and Input Lua API is preserved. Device testing pending.
""")
exactly(lab,'-- NKTouch Test Lab v0.8.8-beta',
            '-- NKTouch Test Lab v0.8.9-beta')
exactly(lab,'local M={VERSION="0.8.8-beta"}',
            'local M={VERSION="0.8.9-beta"}')
anchor='function M.inputPassword(value,options)\n'
methods='''-- v0.8.9 cooperative Runtime Guard. Not a hard real-time watchdog.
M.RUNTIME_GUARD_VERSION="0.8.9-beta"
function M.runtimeSession(options)
  return require("nkruntime_guard").create(options)
end
function M.runGuarded(callback,options)
  return require("nkruntime_guard").run(callback,options)
end
'''
exactly(api,anchor,methods+anchor)
src=ui.read_text()
src=src.replace('NKTouch 0.8.8','NKTouch 0.8.9')
src=src.replace('nkLabel:@"0.8.8"','nkLabel:@"0.8.9"')
src=src.replace('text:@"0.8.8"','text:@"0.8.9"')
src=src.replace('-- NKTouch Test Lab v0.8.8-beta','-- NKTouch Test Lab v0.8.9-beta')
installer='@{@"file":@"test_vision_stability_v088.lua", @"bundle":@"com.apple.mobilenotes"}'
menu='@{@"title":@"Vision • Chờ màn hình ổn định", @"file":@"test_vision_stability_v088.lua"}'
assert src.count(installer)==1, "v0.8.8 Samples installer changed"
assert src.count(menu)==1, "v0.8.8 Samples menu changed"
src=src.replace(installer,
  '@{@"file":@"test_runtime_guard_readonly_v089.lua", @"bundle":@"com.apple.mobilenotes"},\n'
  '        @{@"file":@"test_runtime_guard_write_optin_v089.lua", @"bundle":@"com.apple.mobilenotes"},\n'
  '        '+installer,1)
src=src.replace(menu,
  '@{@"title":@"Runtime • Deadline / Dọn tài nguyên", @"file":@"test_runtime_guard_readonly_v089.lua"},\n'
  '        @{@"title":@"Runtime • Chạm chống trùng (opt-in)", @"file":@"test_runtime_guard_write_optin_v089.lua"},\n'
  '        '+menu,1)
ui.write_text(src)
PY
grep -Fxq 'Version: 0.8.9' "$CONTROL"
grep -Fq 'PACKAGE_VERSION="0.8.9"' "$CTL"
grep -Fq 'NKTouch Test Lab v0.8.9-beta' "$LAB"
grep -Fq 'function M.runtimeSession(options)' "$LIB/nktouch.lua"
grep -Fq 'function M.runGuarded(callback,options)' "$LIB/nktouch.lua"
grep -Fq 'function M.visionWhenStable(plan,options)' "$LIB/nktouch.lua"
grep -Fq 'function M.focusedInput(bundle)' "$LIB/nktouch.lua"
grep -Fq 'function M.inputSafe(value,options)' "$LIB/nktouch.lua"
grep -Fq 'function M.precisionTapIfMatch(options)' "$LIB/nktouch.lua"
grep -Fq 'test_runtime_guard_readonly_v089.lua' "$UI"
grep -Fq 'test_runtime_guard_write_optin_v089.lua' "$UI"
test ! -e "$SRC/layout/var/jb"
echo '[NKRUNTIME089] staged cooperative Lua guard; nktask supervisor intact; Sileo unchanged'
