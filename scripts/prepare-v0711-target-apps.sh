#!/usr/bin/env bash
# NKTouch v0.7.11 user-selected target app and worker-first Lua launch.
set -euo pipefail
SRC="$1"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
test -d "$SRC"
bash "$ROOT/scripts/prepare-v0710-input-engine-v2.sh" "$SRC"
python3 "$ROOT/scripts/apply-v0711-target-apps.py" "$SRC"
python3 - "$SRC/control" "$SRC/layout/usr/share/doc/nktouch/VERSION" "$SRC/layout/usr/bin/nktouchctl" "$SRC/zxtouch/zxtouch/Settings/SettingsPageViewController.m" <<'PY'
from pathlib import Path
import sys
control,version,ctl,ui=map(Path,sys.argv[1:])
c=control.read_text()
assert c.count("Version: 0.7.10")==1,"expected v0.7.10 input baseline"
c=c.replace("Version: 0.7.10","Version: 0.7.11",1)
for line in c.splitlines():
    if line.startswith("Description:"):
        c=c.replace(line,"Description: NKTouch v0.7.11 Target Apps - per-script user-selected target app and verified foreground handoff before Lua actions; retains v0.7.10 Input Engine v2",1)
        break
control.write_text(c)
v=version.read_text()
assert v.count("NKTouch 0.7.10 Input Engine v2")==1
v=v.replace("NKTouch 0.7.10 Input Engine v2","NKTouch 0.7.11 Target Apps",1)
v+="""Target App picker: user chooses an installed app per Lua script (Bundle ID fallback)
Target map: /var/mobile/Library/NKTouch/target_apps.plist
Lua task is launched first, from nktask, before the NKTouch UI is backgrounded
Bootstrap: nk.openApp(bundle) -> nk.waitApp(bundle,8000,200) -> loadfile(script)
Fail safe: no bound app means no Start; open/foreground failure stops before tap/text
Compatibility: existing Lua source unchanged; no automatic retries or input changes
"""
version.write_text(v)
sh=ctl.read_text()
assert sh.count('PACKAGE_VERSION="0.7.10"')==1
ctl.write_text(sh.replace('PACKAGE_VERSION="0.7.10"','PACKAGE_VERSION="0.7.11"',1))
u=ui.read_text()
u=u.replace("NKTouch 0.7.10","NKTouch 0.7.11")
u=u.replace('nkLabel:@"0.7.10"','nkLabel:@"0.7.11"')
u=u.replace('text:@"0.7.10"','text:@"0.7.11"')
ui.write_text(u)
PY
UI="$SRC/zxtouch/zxtouch/Settings/SettingsPageViewController.m"
grep -Fxq 'Version: 0.7.11' "$SRC/control"
grep -Fxq 'NKTouch 0.7.11 Target Apps' "$SRC/layout/usr/share/doc/nktouch/VERSION"
grep -Fq 'PACKAGE_VERSION="0.7.11"' "$SRC/layout/usr/bin/nktouchctl"
grep -Fq 'NKTargetAppPickerViewController' "$UI"
grep -Fq 'NKTargetForScript' "$UI"
grep -Fq 'NKTargetAppsPath' "$UI"
grep -Fq 'TARGET_NOT_FOREGROUND' "$UI"
grep -Fq 'target-run' "$UI"
grep -Fq 'NSString *wrapper=[w nkTargetWrapper]' "$UI"
grep -Fq 'function M.inputTextV2' "$SRC/layout/usr/share/nktouch/lua/nktouch.lua"
grep -Fq 'function M.captureFrame()' "$SRC/layout/usr/share/nktouch/lua/nktouch.lua"
echo 'NKTouch 0.7.11 Target Apps staged; no Sileo publishing'
