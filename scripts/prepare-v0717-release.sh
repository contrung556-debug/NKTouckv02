#!/usr/bin/env bash
# NKTouch v0.7.17 Stability & Memory Core beta staging.
# Packaging only. NEVER publishes to Sileo.
set -euo pipefail
[[ $# -eq 1 ]] || { echo 'usage: prepare-v0717-release.sh <staged-upstream>' >&2; exit 2; }
SRC="$1"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
test -d "$SRC"

# Preserve the exact v0.7.16 proven UI / InputText / touch foundation.
bash "$ROOT/scripts/prepare-v0716-release.sh" "$SRC"
LIB="$SRC/layout/usr/share/nktouch/lua"
CTL="$SRC/layout/usr/bin/nktouchctl"
UI="$SRC/zxtouch/zxtouch/Settings/SettingsPageViewController.m"
CONTROL="$SRC/control"
VERSION="$SRC/layout/usr/share/doc/nktouch/VERSION"
EXAMPLES="$SRC/layout/usr/share/nktouch/examples"

python3 - "$CONTROL" "$VERSION" "$CTL" "$UI" "$LIB/nktestlab.lua" <<'PY'
from pathlib import Path
import sys
control,version,ctl,ui,lab=map(Path,sys.argv[1:])
def strict_replace(path,old,new):
    s=path.read_text()
    count=s.count(old)
    if count!=1:
        raise SystemExit(f'{path}: expected one {old!r}, found {count}')
    path.write_text(s.replace(old,new,1))
strict_replace(control,'Version: 0.7.16','Version: 0.7.17')
s=control.read_text()
s=s.replace('Description: NKTouch v0.7.16 Test Lab and seven-engine reliability beta (device verification pending); retains earlier v0.7.15 functionality',
            'Description: NKTouch v0.7.17 Stability and Memory Core beta (device crash/RSS verification pending); retains InputText and seven-group Test Lab')
control.write_text(s)
strict_replace(ctl,'PACKAGE_VERSION="0.7.16"','PACKAGE_VERSION="0.7.17"')
strict_replace(version,'NKTouch 0.7.16 Seven-Group Test Lab Beta',
               'NKTouch 0.7.17 Stability and Memory Core Beta')
with version.open('a') as out:
    out.write('''
v0.7.17 beta: Vision OCR filters unsupported requested language codes,
    falls back to automatic recognition on the SAME captured frame
    (without extra tap/screenshot); decoded RGB and grayscale allocate
    lazily; frame:close reclaims native image buffers. Includes process
    RSS metrics distinct from Lua heap (nkmemory.lua), plus read-only
    shutdown probe for post-FINISH SIGSEGV.
    Tested in CI; on-device crash cause and memory RSS still require proof.
    No automatic cache eviction or background-app killing.
''')
s=ui.read_text()
s=s.replace('NKTouch 0.7.16','NKTouch 0.7.17')
s=s.replace('nkLabel:@"0.7.16"','nkLabel:@"0.7.17"')
s=s.replace('text:@"0.7.16"','text:@"0.7.17"')
ui.write_text(s)
strict_replace(lab,'-- NKTouch Test Lab v0.7.16-dev',
                  '-- NKTouch Test Lab v0.7.17-dev')
strict_replace(lab,'local M={VERSION="0.7.16-dev"}',
                  'local M={VERSION="0.7.17-dev"}')
PY
mkdir -p "$EXAMPLES"
install -m 0644 "$ROOT/examples/test_lua_exit_probe_readonly.lua" "$EXAMPLES/test_lua_exit_probe_readonly.lua"
test -s "$LIB/nkmemory.lua"
test -s "$LIB/nkvision.lua"
test -s "$EXAMPLES/test_lua_exit_probe_readonly.lua"
grep -Fxq 'Version: 0.7.17' "$CONTROL"
grep -Fxq 'NKTouch 0.7.17 Stability and Memory Core Beta' "$VERSION"
grep -Fq 'PACKAGE_VERSION="0.7.17"' "$CTL"
grep -Fq 'NKTouch Test Lab v0.7.17-dev' "$LIB/nktestlab.lua"
grep -Fq 'function M.inputText(value,options)' "$LIB/nktouch.lua"
grep -Fq 'NKLuaTestLabViewController' "$UI"
test ! -e "$SRC/layout/var/jb"
echo "NKTouch v0.7.17 source staging ready: ARTIFACT ONLY, no Sileo publishing"
