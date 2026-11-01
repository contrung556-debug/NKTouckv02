#!/usr/bin/env bash
set -euo pipefail
SRC="${1:-upstream}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NATIVE="$ROOT/runtime/nktouch-native"
[[ -d "$SRC" ]] || { echo "Missing upstream source: $SRC" >&2; exit 1; }
[[ -x "$NATIVE" ]] || { echo "Missing compiled native helper: $NATIVE" >&2; exit 1; }
python3 - "$SRC/control" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); s=p.read_text()
repl={
"Package: com.zjx.ioscontrol":"Package: com.nk.nktouch",
"Name: ZXTouch":"Name: NKTouch",
"Version: 1.0.1":"Version: 0.6.0",
"Description: ZXTouch Main Application (iOS 15-18)":"Description: NKTouch v0.6 native vision automation runtime (GPL ZXTouch core)",
"Maintainer: Jason Z":"Maintainer: NKTouch",
"Author: Jason Z":"Author: NKTouch + ZXTouch contributors",
}
for a,b in repl.items(): s=s.replace(a,b)
if "Conflicts:" not in s: s += "Conflicts: com.nk.topstatus, com.zjx.ioscontrol\n"
p.write_text(s)
PY
SETTINGS="$SRC/zxtouch/zxtouch/Settings/SettingsPageViewController.m"
if [[ -f "$SETTINGS" ]]; then
python3 - "$SETTINGS" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); s=p.read_text()
for old in ('ZXTouch Rootless 1.0.1','NKTouch 0.5','NKTouch 0.4','NKTouch 0.3','NKTouch 0.2'): s=s.replace(old,'NKTouch 0.6')
s=s.replace('iOS 15-18 port by Epic0001','ZXTouch GPL core • NKTouch vision runtime').replace('iOS 15-17 port by Epic0001','ZXTouch GPL core • NKTouch vision runtime')
p.write_text(s)
PY
fi
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
# Protocol guard: V6 consumes only IDs already defined by the pinned core.
grep -q '^#define TASK_SHOW_TOAST 22$' "$SRC/pccontrol/Task.h"
grep -q '^#define TASK_COLOR_PICKER 23$' "$SRC/pccontrol/Task.h"
grep -q '^#define TASK_TEXT_RECOGNIZER 27$' "$SRC/pccontrol/Task.h"
grep -q '^#define TASK_COLOR_SEARCHER 28$' "$SRC/pccontrol/Task.h"
grep -q '^#define TASK_PROMPT_INPUT 29$' "$SRC/pccontrol/Task.h"
grep -q '^#define TASK_SCREENSHOT 30$' "$SRC/pccontrol/Task.h"
mkdir -p "$SRC/layout/usr/bin" "$SRC/layout/usr/libexec/nktouch" "$SRC/layout/usr/share/nktouch/lua" "$SRC/layout/usr/share/nktouch" "$SRC/layout/usr/share/doc/nktouch"
cp "$ROOT/runtime/nktouchctl" "$SRC/layout/usr/bin/nktouchctl"
cp "$NATIVE" "$SRC/layout/usr/libexec/nktouch/nktouch-native"
cp "$ROOT/runtime/nktouchctl.py" "$SRC/layout/usr/share/nktouch/nktouchctl.py"
cp "$ROOT/lua/nktouch.lua" "$SRC/layout/usr/share/nktouch/lua/nktouch.lua"
cp "$ROOT/NOTICE.md" "$SRC/layout/usr/share/doc/nktouch/NOTICE.md"
printf '%s\n' 'NKTouch 0.6.0' > "$SRC/layout/usr/share/doc/nktouch/VERSION"
chmod 755 "$SRC/layout/usr/bin/nktouchctl" "$SRC/layout/usr/libexec/nktouch/nktouch-native" "$SRC/layout/usr/share/nktouch/nktouchctl.py"
python3 - "$SRC/layout/DEBIAN/postinst" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); s=p.read_text()
block='''\n# NKTouch runtime state\nmkdir -p /var/mobile/Library/NKTouch\ntouch /var/mobile/Library/NKTouch/events.log\nchown -R mobile:mobile /var/mobile/Library/NKTouch\nchmod 755 /var/mobile/Library/NKTouch\nchmod 666 /var/mobile/Library/NKTouch/events.log 2>/dev/null || true\n'''
if '# NKTouch runtime state' not in s: s=s.replace('\nexit 0\n',block+'\nexit 0\n')
p.write_text(s)
PY
echo "--- NKTouch v0.6 package ---"
cat "$SRC/control"
grep -nE 'TASK_SHOW_TOAST|TASK_COLOR_PICKER|TASK_TEXT_RECOGNIZER|TASK_COLOR_SEARCHER|TASK_PROMPT_INPUT|TASK_SCREENSHOT' "$SRC/pccontrol/Task.h"
file "$SRC/layout/usr/libexec/nktouch/nktouch-native"
