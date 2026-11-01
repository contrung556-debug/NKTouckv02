#!/usr/bin/env bash
set -euo pipefail

SRC="${1:-upstream}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NATIVE="$ROOT/runtime/nktouch-native"

[[ -d "$SRC" ]] || { echo "Missing upstream source: $SRC" >&2; exit 1; }
[[ -x "$NATIVE" ]] || { echo "Missing compiled native helper: $NATIVE" >&2; exit 1; }

# Package branding. Internal ZXTouch service identifiers stay unchanged so the
# pinned GPL core and local socket protocol remain compatible.
python3 - "$SRC/control" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1]); s = p.read_text()
repl = {
    "Package: com.zjx.ioscontrol": "Package: com.nk.nktouch",
    "Name: ZXTouch": "Name: NKTouch",
    "Version: 1.0.1": "Version: 0.4.0",
    "Description: ZXTouch Main Application (iOS 15-18)": "Description: NKTouch v0.4 native rootless automation framework (GPL ZXTouch core)",
    "Maintainer: Jason Z": "Maintainer: NKTouch",
    "Author: Jason Z": "Author: NKTouch + ZXTouch contributors",
}
for a,b in repl.items(): s = s.replace(a,b)
if "Conflicts:" not in s: s += "Conflicts: com.nk.topstatus, com.zjx.ioscontrol\n"
p.write_text(s)
PY

SETTINGS="$SRC/zxtouch/zxtouch/Settings/SettingsPageViewController.m"
if [[ -f "$SETTINGS" ]]; then
python3 - "$SETTINGS" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); s=p.read_text()
s=s.replace('ZXTouch Rootless 1.0.1','NKTouch 0.4').replace('NKTouch 0.3','NKTouch 0.4').replace('NKTouch 0.2','NKTouch 0.4')
s=s.replace('iOS 15-18 port by Epic0001','ZXTouch GPL core • NKTouch native layer').replace('iOS 15-17 port by Epic0001','ZXTouch GPL core • NKTouch native layer')
p.write_text(s)
PY
fi

# Status overlay integration.
cp "$ROOT/patches/NKStatusOverlay.xm" "$SRC/pccontrol/NKStatusOverlay.xm"
python3 - "$SRC/pccontrol/Makefile" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); s=p.read_text(); needle='pccontrol_FILES = Tweak.xm'
if 'NKStatusOverlay.xm' not in s:
    if needle not in s: raise SystemExit('Unable to patch pccontrol Makefile')
    s=s.replace(needle,'pccontrol_FILES = Tweak.xm NKStatusOverlay.xm',1)
p.write_text(s)
PY
python3 - "$SRC/pccontrol/Tweak.xm" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); s=p.read_text()
if 'NKStatusOverlayStart' not in s:
    marker='#include "TouchIndicator/TouchIndicatorWindow.h"\n'
    if marker not in s: raise SystemExit('Unable to find Tweak.xm import marker')
    s=s.replace(marker,marker+'\nextern "C" void NKStatusOverlayStart(void);\n',1)
    old='dispatch_async(dispatch_get_main_queue(), ^{\n        ZXDashboardReloadConfiguration();\n    });'
    new='dispatch_async(dispatch_get_main_queue(), ^{\n        NKStatusOverlayStart();\n        ZXDashboardReloadConfiguration();\n    });'
    if old not in s: raise SystemExit('Unable to find Tweak.xm ctor marker')
    s=s.replace(old,new,1)
p.write_text(s)
PY

# V4 screenshot socket task. The pinned core already owns the screenshot engine;
# NKTouch only exposes it through unused task id 29 and returns the saved PNG path.
python3 - "$SRC/pccontrol/Task.h" "$SRC/pccontrol/Task.xm" <<'PY'
from pathlib import Path
import sys
h=Path(sys.argv[1]); x=Path(sys.argv[2])
hs=h.read_text(); xs=x.read_text()
if 'TASK_NK_SCREENSHOT' not in hs:
    needle='#define TASK_COLOR_SEARCHER 28\n'
    if needle not in hs: raise SystemExit('Task.h marker missing')
    hs=hs.replace(needle,needle+'#define TASK_NK_SCREENSHOT 29\n',1)
    h.write_text(hs)
if 'taskType == TASK_NK_SCREENSHOT' not in xs:
    needle='    else if (taskType == TASK_UPDATE_CACHE)\n'
    if needle not in xs: raise SystemExit('Task.xm marker missing')
    block='''    else if (taskType == TASK_NK_SCREENSHOT)\n    {\n        @autoreleasepool {\n            NSString *path = [Screen screenShotAlwaysUp];\n            if (path.length == 0)\n                notifyClient((UInt8*)"-1;;Screenshot failed\\r\\n", writeStreamRef);\n            else\n                notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\\r\\n", path] UTF8String], writeStreamRef);\n        }\n    }\n'''
    xs=xs.replace(needle,block+needle,1)
    x.write_text(xs)
PY

# Runtime files.
mkdir -p "$SRC/layout/usr/bin" "$SRC/layout/usr/libexec/nktouch" "$SRC/layout/usr/share/nktouch/lua" "$SRC/layout/usr/share/nktouch" "$SRC/layout/usr/share/doc/nktouch"
cp "$ROOT/runtime/nktouchctl" "$SRC/layout/usr/bin/nktouchctl"
cp "$NATIVE" "$SRC/layout/usr/libexec/nktouch/nktouch-native"
cp "$ROOT/runtime/nktouchctl.py" "$SRC/layout/usr/share/nktouch/nktouchctl.py"
cp "$ROOT/lua/nktouch.lua" "$SRC/layout/usr/share/nktouch/lua/nktouch.lua"
cp "$ROOT/NOTICE.md" "$SRC/layout/usr/share/doc/nktouch/NOTICE.md"
printf '%s\n' 'NKTouch 0.4.0' > "$SRC/layout/usr/share/doc/nktouch/VERSION"
chmod 755 "$SRC/layout/usr/bin/nktouchctl" "$SRC/layout/usr/libexec/nktouch/nktouch-native" "$SRC/layout/usr/share/nktouch/nktouchctl.py"

python3 - "$SRC/layout/DEBIAN/postinst" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); s=p.read_text()
block='''\n# NKTouch runtime state\nmkdir -p /var/mobile/Library/NKTouch\ntouch /var/mobile/Library/NKTouch/events.log\nchown -R mobile:mobile /var/mobile/Library/NKTouch\nchmod 755 /var/mobile/Library/NKTouch\nchmod 666 /var/mobile/Library/NKTouch/events.log 2>/dev/null || true\n'''
if '# NKTouch runtime state' not in s: s=s.replace('\nexit 0\n',block+'\nexit 0\n')
p.write_text(s)
PY

echo "--- NKTouch v0.4 package ---"
cat "$SRC/control"
grep -n 'TASK_NK_SCREENSHOT' "$SRC/pccontrol/Task.h" "$SRC/pccontrol/Task.xm"
file "$SRC/layout/usr/libexec/nktouch/nktouch-native"
