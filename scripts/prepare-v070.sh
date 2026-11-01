#!/usr/bin/env bash
set -euo pipefail
SRC="${1:-upstream}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NATIVE="$ROOT/runtime/nktouch-native"
TASK="$ROOT/runtime/nktask"
CTL_V7="$ROOT/runtime/nktouchctl-v7"
CTL_CORE="$ROOT/runtime/nktouchctl"
LUA_BIN="$ROOT/runtime/lua54"
LUAC_BIN="$ROOT/runtime/luac54"
LUA_RUNNER="$ROOT/runtime/nktouch-lua"
LUA_README="$ROOT/runtime/LUA_README.txt"

[[ -d "$SRC" ]] || { echo "Missing upstream source: $SRC" >&2; exit 1; }
[[ -x "$NATIVE" ]] || { echo "Missing compiled native helper: $NATIVE" >&2; exit 1; }
[[ -x "$TASK" ]] || { echo "Missing compiled task engine: $TASK" >&2; exit 1; }
[[ -f "$CTL_V7" ]] || { echo "Missing V7 control wrapper: $CTL_V7" >&2; exit 1; }
[[ -f "$CTL_CORE" ]] || { echo "Missing V6.4 core control script: $CTL_CORE" >&2; exit 1; }
[[ -x "$LUA_BIN" ]] || { echo "Missing bundled Lua interpreter: $LUA_BIN" >&2; exit 1; }
[[ -x "$LUAC_BIN" ]] || { echo "Missing bundled Lua compiler: $LUAC_BIN" >&2; exit 1; }
[[ -f "$LUA_RUNNER" ]] || { echo "Missing Lua launcher: $LUA_RUNNER" >&2; exit 1; }
[[ -f "$LUA_README" ]] || { echo "Missing Lua upstream README/license notice: $LUA_README" >&2; exit 1; }

python3 - "$SRC/control" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); s=p.read_text()
repl={
"Package: com.zjx.ioscontrol":"Package: com.nk.nktouch",
"Name: ZXTouch":"Name: NKTouch",
"Version: 1.0.1":"Version: 0.7.0",
"Description: ZXTouch Main Application (iOS 15-18)":"Description: NKTouch v0.7.0 script/task engine with hardened direct Lua runtime (GPL ZXTouch core)",
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
for old in ('ZXTouch Rootless 1.0.1','NKTouch 0.6.4','NKTouch 0.6.3','NKTouch 0.6.2','NKTouch 0.6.1','NKTouch 0.6','NKTouch 0.5','NKTouch 0.4','NKTouch 0.3','NKTouch 0.2'):
    s=s.replace(old,'NKTouch 0.7.0')
s=s.replace('iOS 15-18 port by Epic0001','ZXTouch GPL core • NKTouch V7 task engine')
s=s.replace('iOS 15-17 port by Epic0001','ZXTouch GPL core • NKTouch V7 task engine')
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

# V7.0 adds task orchestration only. SpringBoard protocol IDs stay unchanged.
grep -q '^#define TASK_SHOW_TOAST 22$' "$SRC/pccontrol/Task.h"
grep -q '^#define TASK_COLOR_PICKER 23$' "$SRC/pccontrol/Task.h"
grep -q '^#define TASK_TEXT_RECOGNIZER 27$' "$SRC/pccontrol/Task.h"
grep -q '^#define TASK_COLOR_SEARCHER 28$' "$SRC/pccontrol/Task.h"
grep -q '^#define TASK_PROMPT_INPUT 29$' "$SRC/pccontrol/Task.h"
grep -q '^#define TASK_SCREENSHOT 30$' "$SRC/pccontrol/Task.h"

mkdir -p "$SRC/layout/usr/bin" "$SRC/layout/usr/libexec/nktouch" "$SRC/layout/usr/share/nktouch/lua" "$SRC/layout/usr/share/nktouch" "$SRC/layout/usr/share/doc/nktouch"
cp "$CTL_V7" "$SRC/layout/usr/bin/nktouchctl"
cp "$TASK" "$SRC/layout/usr/bin/nktask"
cp "$CTL_CORE" "$SRC/layout/usr/libexec/nktouch/nktouchctl-core"
cp "$LUA_RUNNER" "$SRC/layout/usr/bin/nktouch-lua"
cp "$NATIVE" "$SRC/layout/usr/libexec/nktouch/nktouch-native"
cp "$LUA_BIN" "$SRC/layout/usr/libexec/nktouch/lua54"
cp "$LUAC_BIN" "$SRC/layout/usr/libexec/nktouch/luac54"
cp "$ROOT/runtime/nktouchctl.py" "$SRC/layout/usr/share/nktouch/nktouchctl.py"
cp "$ROOT/lua/nktouch.lua" "$SRC/layout/usr/share/nktouch/lua/nktouch.lua"
cp "$ROOT/NOTICE.md" "$SRC/layout/usr/share/doc/nktouch/NOTICE.md"
cp "$LUA_README" "$SRC/layout/usr/share/doc/nktouch/LUA_README.txt"
printf '%s\n' \
  'NKTouch 0.7.0 Script/Task Engine' \
  'V6.4 hardened direct Lua runtime retained' \
  'Native engine 0.6.0' \
  'Embedded nkcore 0.6.3' \
  'Lua 5.4.9' \
  'Single active screen-control task safety' \
  'OCR remains explicit/on-demand only' \
  > "$SRC/layout/usr/share/doc/nktouch/VERSION"
chmod 755 \
  "$SRC/layout/usr/bin/nktouchctl" \
  "$SRC/layout/usr/bin/nktask" \
  "$SRC/layout/usr/bin/nktouch-lua" \
  "$SRC/layout/usr/libexec/nktouch/nktouchctl-core" \
  "$SRC/layout/usr/libexec/nktouch/nktouch-native" \
  "$SRC/layout/usr/libexec/nktouch/lua54" \
  "$SRC/layout/usr/libexec/nktouch/luac54" \
  "$SRC/layout/usr/share/nktouch/nktouchctl.py"

python3 - "$SRC/layout/DEBIAN/postinst" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); s=p.read_text()
block='''\n# NKTouch runtime/task state\nmkdir -p /var/mobile/Library/NKTouch /var/mobile/Library/NKTouch/tmp /var/mobile/Library/NKTouch/tasks\ntouch /var/mobile/Library/NKTouch/events.log\nchown -R mobile:mobile /var/mobile/Library/NKTouch\nchmod 755 /var/mobile/Library/NKTouch /var/mobile/Library/NKTouch/tmp /var/mobile/Library/NKTouch/tasks\nchmod 666 /var/mobile/Library/NKTouch/events.log 2>/dev/null || true\nrm -f /var/mobile/Library/NKTouch/tmp/doctor-* /var/mobile/Library/NKTouch/tmp/selftest-* /var/mobile/Library/NKTouch/tmp/stress-* 2>/dev/null || true\n'''
if '# NKTouch runtime/task state' not in s and '# NKTouch runtime state' not in s:
    s=s.replace('\nexit 0\n',block+'\nexit 0\n')
elif '# NKTouch runtime state' in s:
    start=s.index('# NKTouch runtime state')
    end=s.find('\nexit 0', start)
    if end < 0: raise SystemExit('Unable to replace old NKTouch postinst block')
    s=s[:start] + block.strip('\n') + '\n' + s[end:]
else:
    s=s.replace('mkdir -p /var/mobile/Library/NKTouch /var/mobile/Library/NKTouch/tmp\n','mkdir -p /var/mobile/Library/NKTouch /var/mobile/Library/NKTouch/tmp /var/mobile/Library/NKTouch/tasks\n')
p.write_text(s)
PY

echo "--- NKTouch v0.7.0 Script/Task Engine package ---"
cat "$SRC/control"
grep -nE 'TASK_SHOW_TOAST|TASK_COLOR_PICKER|TASK_TEXT_RECOGNIZER|TASK_COLOR_SEARCHER|TASK_PROMPT_INPUT|TASK_SCREENSHOT' "$SRC/pccontrol/Task.h"
file "$SRC/layout/usr/bin/nktask"
file "$SRC/layout/usr/libexec/nktouch/nktouch-native"
file "$SRC/layout/usr/libexec/nktouch/lua54"
