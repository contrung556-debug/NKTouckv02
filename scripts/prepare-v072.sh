#!/usr/bin/env bash
set -euo pipefail
SRC="${1:-upstream}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

[[ -d "$SRC" ]] || { echo "Missing upstream source: $SRC" >&2; exit 1; }
[[ -f "$ROOT/runtime/nkeditor" ]] || { echo "Missing Script Editor controller" >&2; exit 1; }
[[ -f "$ROOT/runtime/nktouch-api.tsv" ]] || { echo "Missing Script Editor API catalog" >&2; exit 1; }

# Reuse V7.1 in full: this keeps the proven task supervisor, hardened direct
# Lua runtime, Recorder V2 exporter, and the recorder socket fix unchanged.
bash "$ROOT/scripts/prepare-v071.sh" "$SRC"

python3 - "$SRC/control" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); s=p.read_text()
s=s.replace('Version: 0.7.1','Version: 0.7.2')
s=s.replace(
    'Description: NKTouch v0.7.1 Recorder V2 with script/task engine and hardened direct Lua runtime (GPL ZXTouch core)',
    'Description: NKTouch v0.7.2 Script Editor with Recorder V2, task engine and hardened direct Lua runtime (GPL ZXTouch core)'
)
if 'Version: 0.7.2' not in s:
    raise SystemExit('Unable to set package version 0.7.2')
p.write_text(s)
PY

SETTINGS="$SRC/zxtouch/zxtouch/Settings/SettingsPageViewController.m"
if [[ -f "$SETTINGS" ]]; then
python3 - "$SETTINGS" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); s=p.read_text().replace('NKTouch 0.7.1','NKTouch 0.7.2')
s=s.replace('ZXTouch GPL core • NKTouch Recorder V2','ZXTouch GPL core • NKTouch Script Editor')
p.write_text(s)
PY
fi

mkdir -p "$SRC/layout/usr/bin" "$SRC/layout/usr/share/nktouch"
cp "$ROOT/runtime/nktouchctl-v7" "$SRC/layout/usr/bin/nktouchctl"
cp "$ROOT/runtime/nkeditor" "$SRC/layout/usr/bin/nkeditor"
cp "$ROOT/runtime/nktouch-api.tsv" "$SRC/layout/usr/share/nktouch/nktouch-api.tsv"
chmod 755 "$SRC/layout/usr/bin/nktouchctl" "$SRC/layout/usr/bin/nkeditor"
chmod 644 "$SRC/layout/usr/share/nktouch/nktouch-api.tsv"

python3 - "$SRC/layout/DEBIAN/postinst" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); s=p.read_text()
old='mkdir -p /var/mobile/Library/NKTouch /var/mobile/Library/NKTouch/tmp /var/mobile/Library/NKTouch/tasks /var/mobile/Library/NKTouch/recordings /var/mobile/Library/NKTouch/recorder'
new=old+' /var/mobile/Library/NKTouch/scripts'
if new not in s:
    if old not in s: raise SystemExit('Unable to extend NKTouch state directories for editor')
    s=s.replace(old,new,1)
oldchmod='chmod 755 /var/mobile/Library/NKTouch /var/mobile/Library/NKTouch/tmp /var/mobile/Library/NKTouch/tasks /var/mobile/Library/NKTouch/recordings /var/mobile/Library/NKTouch/recorder'
newchmod=oldchmod+' /var/mobile/Library/NKTouch/scripts'
if newchmod not in s:
    if oldchmod not in s: raise SystemExit('Unable to extend NKTouch state permissions for editor')
    s=s.replace(oldchmod,newchmod,1)
p.write_text(s)
PY

cat > "$SRC/layout/usr/share/doc/nktouch/VERSION" <<'EOF'
NKTouch 0.7.2 Script Editor
V7.1 Recorder V2 retained
V7.0 single-active-task supervisor retained
V6.4 hardened direct Lua runtime retained
Native engine 0.6.0
Embedded nkcore 0.6.3
Lua 5.4.9
Managed scripts: /var/mobile/Library/NKTouch/scripts
Editor: templates / syntax check / API help / completion / snippets / run controls
Recorder source: real HID timing from task 14/15
OCR remains explicit/on-demand only
EOF

# V7.2 adds no SpringBoard protocol. All proven task IDs stay unchanged.
grep -q '^#define TASK_TOUCH_RECORDING_START 14$' "$SRC/pccontrol/Task.h"
grep -q '^#define TASK_TOUCH_RECORDING_STOP 15$' "$SRC/pccontrol/Task.h"
grep -q '^#define TASK_SHOW_TOAST 22$' "$SRC/pccontrol/Task.h"
grep -q '^#define TASK_COLOR_PICKER 23$' "$SRC/pccontrol/Task.h"
grep -q '^#define TASK_TEXT_RECOGNIZER 27$' "$SRC/pccontrol/Task.h"
grep -q '^#define TASK_COLOR_SEARCHER 28$' "$SRC/pccontrol/Task.h"
grep -q '^#define TASK_PROMPT_INPUT 29$' "$SRC/pccontrol/Task.h"
grep -q '^#define TASK_SCREENSHOT 30$' "$SRC/pccontrol/Task.h"
grep -q 'NKTouch v0.7.1: Task.xm owns the single socket response for task 14.' "$SRC/pccontrol/Record.xm"

test -x "$SRC/layout/usr/bin/nkeditor"
test -f "$SRC/layout/usr/share/nktouch/nktouch-api.tsv"
grep -q '^nk.tap|' "$SRC/layout/usr/share/nktouch/nktouch-api.tsv"
grep -q '^nk.ocr|' "$SRC/layout/usr/share/nktouch/nktouch-api.tsv"

echo "--- NKTouch v0.7.2 Script Editor package ---"
cat "$SRC/control"
cat "$SRC/layout/usr/share/doc/nktouch/VERSION"
