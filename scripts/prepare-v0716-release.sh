#!/usr/bin/env bash
# NKTouch 0.7.16: release candidate staging from v0.7.15 + dev hardening.
# Does not itself compile, publish or modify a previous Sileo package.
set -euo pipefail
[[ $# -eq 1 ]] || { echo 'usage: prepare-v0716-release.sh <staged-upstream>' >&2; exit 2; }
SRC="$1"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
test -d "$SRC"

bash "$ROOT/scripts/stage-v0716-testlab-dev.sh" "$SRC"
LIB="$SRC/layout/usr/share/nktouch/lua"
UI="$SRC/zxtouch/zxtouch/Settings/SettingsPageViewController.m"
CONTROL="$SRC/control"
VERSION="$SRC/layout/usr/share/doc/nktouch/VERSION"
CTL="$SRC/layout/usr/bin/nktouchctl"

python3 - "$CONTROL" "$VERSION" "$CTL" "$UI" <<'PY'
from pathlib import Path
import sys
control, version, ctl, ui = (Path(x) for x in sys.argv[1:])
c=control.read_text()
assert c.count("Version: 0.7.15")==1,"unexpected source package version"
c=c.replace("Version: 0.7.15","Version: 0.7.16",1)
for line in c.splitlines():
    if line.startswith("Description:"):
        c=c.replace(line,"Description: NKTouch v0.7.16 Test Lab and seven-engine reliability beta (device verification pending); retains earlier v0.7.15 functionality",1)
        break
control.write_text(c)
v=version.read_text()
assert v.count("NKTouch 0.7.15 Lua Function Self-Test")==1
v=v.replace("NKTouch 0.7.15 Lua Function Self-Test",
            "NKTouch 0.7.16 Seven-Group Test Lab Beta",1)
v += """
v0.7.16: Lua Test Lab with 7 selectable groups, Reliability Report, native
touch input preflight, screenshot/frame guards, bounded read-only retries,
strict UTF-8 input/JSON parsing, atomic HTTP downloads, comparison with
previous Test Lab results. CI checked on Linux/macOS; iPhone test pending.
Touch/Input/network test mutations require manual confirmed=true opt-in.
Earlier stable package v0.7.15 retained in Sileo for rollback.
"""
version.write_text(v)
s=ctl.read_text()
assert s.count('PACKAGE_VERSION="0.7.15"')==1
ctl.write_text(s.replace('PACKAGE_VERSION="0.7.15"',
                         'PACKAGE_VERSION="0.7.16"',1))
s=ui.read_text()
s=s.replace("NKTouch 0.7.15","NKTouch 0.7.16")
s=s.replace('nkLabel:@"0.7.15"','nkLabel:@"0.7.16"')
s=s.replace('text:@"0.7.15"','text:@"0.7.16"')
ui.write_text(s)
PY
grep -Fxq 'Version: 0.7.16' "$CONTROL"
grep -Fxq 'NKTouch 0.7.16 Seven-Group Test Lab Beta' "$VERSION"
grep -Fq 'PACKAGE_VERSION="0.7.16"' "$CTL"
grep -Fq 'NKLuaTestLabViewController' "$UI"
grep -Fq 'nktestlab_%@.lua' "$UI"
grep -Fq 'labShowReport' "$UI"
grep -Fq 'function M.inputText(value,options)' "$LIB/nktouch.lua"
grep -Fq 'require("nkcommand_contract").install(M)' "$LIB/nktouch.lua"
for name in nktestlab nkcoords nkstability nkregression nkinput_v2 nkvision nknet nkjson nkcommand_contract; do
  test -s "$LIB/$name.lua"
done
test -s "$SRC/layout/usr/share/nktouch/examples/test_core_readonly.lua"
test -s "$SRC/layout/usr/share/nktouch/examples/test_vision_oneframe.lua"
test -s "$SRC/layout/usr/share/nktouch/examples/test_inputtext_notes_v2.lua"
test ! -e "$SRC/layout/var/jb"
echo 'NKTouch v0.7.16 source stage ready for one iOS build (beta, device test pending)'
