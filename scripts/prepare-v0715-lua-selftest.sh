#!/usr/bin/env bash
# NKTouch v0.7.15 - batched Lua Function Self-Test suite.
# All changes staged before a single final iOS build; retain 0.7.14 and older.
set -euo pipefail
[[ $# -eq 1 ]] || { echo 'usage: prepare-v0715-lua-selftest.sh <staged-upstream>' >&2; exit 2; }
SRC="$1"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
test -d "$SRC"
bash "$ROOT/scripts/prepare-v0714-notes-screenfix.sh" "$SRC"
DST="$SRC/layout/usr/share/nktouch/examples"
mkdir -p "$DST"
for name in test_core_readonly.lua test_vision_oneframe.lua test_gestures_optin.lua; do
  install -m 0644 "$ROOT/examples/$name" "$DST/$name"
done
python3 "$ROOT/scripts/apply-v0715-selftest-suite.py" "$SRC"
python3 - "$SRC/control" "$SRC/layout/usr/share/doc/nktouch/VERSION" "$SRC/layout/usr/bin/nktouchctl" "$SRC/zxtouch/zxtouch/Settings/SettingsPageViewController.m" <<'PY'
from pathlib import Path
import sys
control,version,ctl,ui=map(Path,sys.argv[1:])
c=control.read_text()
assert c.count("Version: 0.7.14")==1
c=c.replace("Version: 0.7.14","Version: 0.7.15",1)
for line in c.splitlines():
    if line.startswith("Description:"):
        c=c.replace(line,"Description: NKTouch v0.7.15 Lua Function Self-Test - built-in Core, one-frame Vision, Notes InputText and opt-in Gesture tests; retains v0.7.14 fixes",1)
        break
control.write_text(c)
v=version.read_text()
assert v.count("NKTouch 0.7.14 Notes Screen Fix")==1
v=v.replace("NKTouch 0.7.14 Notes Screen Fix","NKTouch 0.7.15 Lua Function Self-Test",1)
v+="""Samples: Core (read-only), Vision (single capture), Notes InputText, Gesture (opt-in)
Bundled Lua scripts copied only if missing, never overwrite edits
Core/Vision default to Safari; Gesture has no default target and sends no touches
Log conventions: [NKCORE], [VISION], [NKINPUT][NOTES], [NKTEST]
Native engine and existing APIs unchanged; build and publish only after all validations
"""
version.write_text(v)
s=ctl.read_text()
assert s.count('PACKAGE_VERSION="0.7.14"')==1
ctl.write_text(s.replace('PACKAGE_VERSION="0.7.14"','PACKAGE_VERSION="0.7.15"',1))
u=ui.read_text()
u=u.replace("NKTouch 0.7.14","NKTouch 0.7.15")
u=u.replace('nkLabel:@"0.7.14"','nkLabel:@"0.7.15"')
u=u.replace('text:@"0.7.14"','text:@"0.7.15"')
ui.write_text(u)
PY

UI="$SRC/zxtouch/zxtouch/Settings/SettingsPageViewController.m"
DOC="$SRC/layout/usr/share/doc/nktouch/VERSION"
grep -Fxq 'Version: 0.7.15' "$SRC/control"
grep -Fxq 'NKTouch 0.7.15 Lua Function Self-Test' "$DOC"
grep -Fq 'PACKAGE_VERSION="0.7.15"' "$SRC/layout/usr/bin/nktouchctl"
grep -Fq 'nkShowSamples' "$UI"
grep -Fq 'test_core_readonly.lua' "$UI"
grep -Fq 'test_vision_oneframe.lua' "$UI"
grep -Fq 'test_gestures_optin.lua' "$UI"
grep -Fq 'test_inputtext_notes_v2.lua' "$UI"
grep -Fq 'function M.inputText(value,options)' "$SRC/layout/usr/share/nktouch/lua/nktouch.lua"
for name in test_core_readonly.lua test_vision_oneframe.lua test_gestures_optin.lua test_inputtext_notes_v2.lua; do
  test -s "$DST/$name"
done
echo 'NKTouch 0.7.15 Lua Self-Test suite staged: no build triggered by this script'
