#!/usr/bin/env bash
set -euo pipefail
SRC="${1:-upstream}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

[[ -d "$SRC" ]] || { echo "Missing upstream source: $SRC" >&2; exit 1; }
[[ -f "$ROOT/runtime/nkbundle" ]] || { echo "Missing Task Bundle controller" >&2; exit 1; }
[[ -f "$ROOT/lua/nkbundle.lua" ]] || { echo "Missing Task Bundle Lua container" >&2; exit 1; }

# Reuse V7.2 in full: task supervisor, Recorder V2 and Script Editor stay intact.
bash "$ROOT/scripts/prepare-v072.sh" "$SRC"

python3 - "$SRC/control" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); s=p.read_text()
s=s.replace('Version: 0.7.2','Version: 0.7.3')
s=s.replace(
    'Description: NKTouch v0.7.2 Script Editor with Recorder V2, task engine and hardened direct Lua runtime (GPL ZXTouch core)',
    'Description: NKTouch v0.7.3 Task Bundle with Script Editor, Recorder V2, task engine and hardened direct Lua runtime (GPL ZXTouch core)'
)
if 'Version: 0.7.3' not in s:
    raise SystemExit('Unable to set package version 0.7.3')
p.write_text(s)
PY

SETTINGS="$SRC/zxtouch/zxtouch/Settings/SettingsPageViewController.m"
if [[ -f "$SETTINGS" ]]; then
python3 - "$SETTINGS" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); s=p.read_text().replace('NKTouch 0.7.2','NKTouch 0.7.3')
s=s.replace('ZXTouch GPL core • NKTouch Script Editor','ZXTouch GPL core • NKTouch Task Bundle')
p.write_text(s)
PY
fi

mkdir -p "$SRC/layout/usr/bin" "$SRC/layout/usr/share/nktouch"
cp "$ROOT/runtime/nktouchctl-v7" "$SRC/layout/usr/bin/nktouchctl"
cp "$ROOT/runtime/nkbundle" "$SRC/layout/usr/bin/nkbundle"
cp "$ROOT/lua/nkbundle.lua" "$SRC/layout/usr/share/nktouch/nkbundle.lua"
chmod 755 "$SRC/layout/usr/bin/nktouchctl" "$SRC/layout/usr/bin/nkbundle"
chmod 644 "$SRC/layout/usr/share/nktouch/nkbundle.lua"

python3 - "$SRC/layout/DEBIAN/postinst" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); s=p.read_text()
old='mkdir -p /var/mobile/Library/NKTouch /var/mobile/Library/NKTouch/tmp /var/mobile/Library/NKTouch/tasks /var/mobile/Library/NKTouch/recordings /var/mobile/Library/NKTouch/recorder /var/mobile/Library/NKTouch/scripts'
new=old+' /var/mobile/Library/NKTouch/assets /var/mobile/Library/NKTouch/bundles'
if new not in s:
    if old not in s: raise SystemExit('Unable to extend NKTouch state directories for bundles')
    s=s.replace(old,new,1)
oldchmod='chmod 755 /var/mobile/Library/NKTouch /var/mobile/Library/NKTouch/tmp /var/mobile/Library/NKTouch/tasks /var/mobile/Library/NKTouch/recordings /var/mobile/Library/NKTouch/recorder /var/mobile/Library/NKTouch/scripts'
newchmod=oldchmod+' /var/mobile/Library/NKTouch/assets /var/mobile/Library/NKTouch/bundles'
if newchmod not in s:
    if oldchmod not in s: raise SystemExit('Unable to extend NKTouch state permissions for bundles')
    s=s.replace(oldchmod,newchmod,1)
p.write_text(s)
PY

cat > "$SRC/layout/usr/share/doc/nktouch/VERSION" <<'EOF'
NKTouch 0.7.3 Task Bundle
V7.2 Script Editor retained
V7.1 Recorder V2 retained
V7.0 single-active-task supervisor retained
V6.4 hardened direct Lua runtime retained
Native engine 0.6.0
Embedded nkcore 0.6.3
Lua 5.4.9
Bundle format: NKTASK1 (.nktask)
Managed scripts: /var/mobile/Library/NKTouch/scripts
Managed assets: /var/mobile/Library/NKTouch/assets
Managed bundles: /var/mobile/Library/NKTouch/bundles
Import safety: fixed entry paths / size limits / FNV-1a corruption checks / Lua syntax validation / no automatic overwrite
OCR remains explicit/on-demand only
EOF

# V7.3 is a local file-management layer. It allocates no new SpringBoard protocol IDs.
grep -q '^#define TASK_TOUCH_RECORDING_START 14$' "$SRC/pccontrol/Task.h"
grep -q '^#define TASK_TOUCH_RECORDING_STOP 15$' "$SRC/pccontrol/Task.h"
grep -q '^#define TASK_TEXT_RECOGNIZER 27$' "$SRC/pccontrol/Task.h"
grep -q '^#define TASK_PROMPT_INPUT 29$' "$SRC/pccontrol/Task.h"
grep -q '^#define TASK_SCREENSHOT 30$' "$SRC/pccontrol/Task.h"

test -x "$SRC/layout/usr/bin/nkbundle"
test -f "$SRC/layout/usr/share/nktouch/nkbundle.lua"
grep -q 'MAGIC = "NKTASK1"' "$SRC/layout/usr/share/nktouch/nkbundle.lua"

echo "--- NKTouch v0.7.3 Task Bundle package ---"
cat "$SRC/control"
cat "$SRC/layout/usr/share/doc/nktouch/VERSION"
