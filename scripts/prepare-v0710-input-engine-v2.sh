#!/usr/bin/env bash
# Stage NKTouch 0.7.10 Input Engine v2 over retained Vision Core v0.7.9.
set -euo pipefail
SRC="$1"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[[ -d "$SRC" ]] || { echo "Missing staged upstream" >&2; exit 1; }
bash "$ROOT/scripts/prepare-v079-vision-core.sh" "$SRC"
python3 "$ROOT/scripts/apply-input-engine-v2.py" "$SRC"
LIB="$SRC/layout/usr/share/nktouch/lua"
CTL="$SRC/layout/usr/bin/nktouchctl"
UI="$SRC/zxtouch/zxtouch/Settings/SettingsPageViewController.m"
install -m 0644 "$ROOT/lua/nkinput_v2.lua" "$LIB/nkinput_v2.lua"
python3 - "$SRC/control" "$SRC/layout/usr/share/doc/nktouch/VERSION" "$CTL" "$UI" <<'PY'
from pathlib import Path
import sys
control,version,ctl,ui=map(Path,sys.argv[1:])
c=control.read_text()
assert c.count("Version: 0.7.9")==1,"expected v0.7.9 package baseline"
c=c.replace("Version: 0.7.9","Version: 0.7.10",1)
for line in c.splitlines():
    if line.startswith("Description:"):
        c=c.replace(line,"Description: NKTouch v0.7.10 Input Engine v2 - opt-in Unicode safe input, password protection and OCR verification; retains v0.7.9 Vision Core",1)
        break
control.write_text(c)
v=version.read_text()
assert v.count("NKTouch 0.7.9 Vision Core")==1
v=v.replace("NKTouch 0.7.9 Vision Core","NKTouch 0.7.10 Input Engine v2",1)
v+="""Input v2: nk.inputTextV2(text,options), nk.inputPassword(text,options)
IPC: base64 UTF-8 single-frame command 8 (direct) or 9 (keyboard fallback)
No implicit retry or automatic clipboard usage
Input task ACK: delivery to IPC only; not confirmation of text in target app
Verification: opt-in OCR region for nonsensitive text; never for passwords
Legacy API: nk.inputText(text) unchanged
"""
version.write_text(v)
c=ctl.read_text()
assert c.count('PACKAGE_VERSION="0.7.9"')==1
ctl.write_text(c.replace('PACKAGE_VERSION="0.7.9"','PACKAGE_VERSION="0.7.10"',1))
u=ui.read_text().replace("NKTouch 0.7.9","NKTouch 0.7.10")
u=u.replace('nkLabel:@"0.7.9"','nkLabel:@"0.7.10"')
u=u.replace('text:@"0.7.9"','text:@"0.7.10"')
ui.write_text(u)
PY

grep -Fxq "Version: 0.7.10" "$SRC/control"
grep -Fxq "NKTouch 0.7.10 Input Engine v2" "$SRC/layout/usr/share/doc/nktouch/VERSION"
grep -Fq 'PACKAGE_VERSION="0.7.10"' "$CTL"
grep -Fq 'nk.inputTextV2' "$SRC/layout/usr/share/doc/nktouch/VERSION"
grep -Fq 'function M.inputTextV2' "$LIB/nktouch.lua"
grep -Fq 'function M.inputPassword' "$LIB/nktouch.lua"
grep -Fq 'M.inputText=M.text' "$LIB/nktouch.lua"
grep -Fq 'function M.input(nk,text,opts)' "$LIB/nkinput_v2.lua"
grep -Fq 'nk_input_v2_id' "$SRC/pccontrol/UIKeyboard.xm"
grep -Fq 'NKInputV2FocusedView' "$SRC/appdelegate/UIKeyboard.xm"
grep -Fq 'Vision API:' "$SRC/layout/usr/share/doc/nktouch/VERSION"
grep -Fq 'NKColorCopyPixels' "$SRC/pccontrol/ColorPicker.xm"
grep -Fq 'NKHotkeyActionRecorderFinish' "$SRC/nktouch-trigger/Tweak.xm"
test ! -e "$SRC/layout/var/jb"
echo 'NKTouch 0.7.10 Input Engine v2 staged; Vision Core and old APIs preserved'
