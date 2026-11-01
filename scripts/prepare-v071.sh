#!/usr/bin/env bash
set -euo pipefail
SRC="${1:-upstream}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

[[ -d "$SRC" ]] || { echo "Missing upstream source: $SRC" >&2; exit 1; }
[[ -f "$ROOT/runtime/nkrecorder" ]] || { echo "Missing Recorder V2 controller" >&2; exit 1; }
[[ -f "$ROOT/lua/nkrecorder.lua" ]] || { echo "Missing Recorder V2 exporter" >&2; exit 1; }

# Reuse the proven V7.0 package assembly first, then add only the Recorder V2
# delta. This deliberately leaves the V6.4 direct Lua core and V7 task engine
# untouched.
bash "$ROOT/scripts/prepare-v070.sh" "$SRC"

python3 - "$SRC/control" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); s=p.read_text()
s=s.replace('Version: 0.7.0','Version: 0.7.1')
s=s.replace(
    'Description: NKTouch v0.7.0 script/task engine with hardened direct Lua runtime (GPL ZXTouch core)',
    'Description: NKTouch v0.7.1 Recorder V2 with script/task engine and hardened direct Lua runtime (GPL ZXTouch core)'
)
if 'Version: 0.7.1' not in s:
    raise SystemExit('Unable to set package version 0.7.1')
p.write_text(s)
PY

SETTINGS="$SRC/zxtouch/zxtouch/Settings/SettingsPageViewController.m"
if [[ -f "$SETTINGS" ]]; then
python3 - "$SETTINGS" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); s=p.read_text().replace('NKTouch 0.7.0','NKTouch 0.7.1')
s=s.replace('ZXTouch GPL core • NKTouch V7 task engine','ZXTouch GPL core • NKTouch Recorder V2')
p.write_text(s)
PY
fi

# Upstream's recorder used to write the recording directory asynchronously to
# the same socket after Task.xm had already returned the normal task-14 reply.
# That creates two responses on one request. NKTouch discovers the freshly
# created .bdl directory from disk, so Task.xm should own the only socket reply.
RECORD="$SRC/pccontrol/Record.xm"
python3 - "$RECORD" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); s=p.read_text()
marker='NKTouch v0.7.1: Task.xm owns the single socket response for task 14.'
if marker not in s:
    lines=s.splitlines()
    hits=[]
    for i,line in enumerate(lines):
        compact=''.join(line.split())
        if ('notifyClient' in line and 'scriptDirectory' in line and
                'requestClient' in line and 'UTF8String' in line):
            hits.append(i)
    if len(hits) != 1:
        candidates=[f'{i+1}: {line}' for i,line in enumerate(lines)
                    if 'scriptDirectory' in line or ('notifyClient' in line and 'requestClient' in line)]
        raise SystemExit('Unable to uniquely patch legacy recorder socket response. Candidates:\n' + '\n'.join(candidates[:20]))
    i=hits[0]
    indent=lines[i][:len(lines[i])-len(lines[i].lstrip())]
    lines[i:i+1]=[
        indent + '// ' + marker,
        indent + '// nkrecorder discovers this synchronously-created bundle from disk.',
        indent + '(void)requestClient;',
    ]
    s='\n'.join(lines) + ('\n' if s.endswith('\n') else '')
p.write_text(s)
PY

mkdir -p "$SRC/layout/usr/bin" "$SRC/layout/usr/share/nktouch"
cp "$ROOT/runtime/nktouchctl-v7" "$SRC/layout/usr/bin/nktouchctl"
cp "$ROOT/runtime/nkrecorder" "$SRC/layout/usr/bin/nkrecorder"
cp "$ROOT/lua/nkrecorder.lua" "$SRC/layout/usr/share/nktouch/nkrecorder.lua"
chmod 755 "$SRC/layout/usr/bin/nktouchctl" "$SRC/layout/usr/bin/nkrecorder"
chmod 644 "$SRC/layout/usr/share/nktouch/nkrecorder.lua"

python3 - "$SRC/layout/DEBIAN/postinst" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); s=p.read_text()
s=s.replace(
    'mkdir -p /var/mobile/Library/NKTouch /var/mobile/Library/NKTouch/tmp /var/mobile/Library/NKTouch/tasks',
    'mkdir -p /var/mobile/Library/NKTouch /var/mobile/Library/NKTouch/tmp /var/mobile/Library/NKTouch/tasks /var/mobile/Library/NKTouch/recordings /var/mobile/Library/NKTouch/recorder'
)
s=s.replace(
    'chmod 755 /var/mobile/Library/NKTouch /var/mobile/Library/NKTouch/tmp /var/mobile/Library/NKTouch/tasks',
    'chmod 755 /var/mobile/Library/NKTouch /var/mobile/Library/NKTouch/tmp /var/mobile/Library/NKTouch/tasks /var/mobile/Library/NKTouch/recordings /var/mobile/Library/NKTouch/recorder'
)
p.write_text(s)
PY

cat > "$SRC/layout/usr/share/doc/nktouch/VERSION" <<'EOF'
NKTouch 0.7.1 Recorder V2
V7.0 single-active-task supervisor retained
V6.4 hardened direct Lua runtime retained
Native engine 0.6.0
Embedded nkcore 0.6.3
Lua 5.4.9
Recorder source: real HID timing from task 14/15
Recorder export: nk.tap / nk.hold / nk.swipe / nk.sleep
Keyboard input is replayed as physical taps; semantic text is not guessed
OCR remains explicit/on-demand only
EOF

# Protocol IDs are unchanged. Recorder V2 uses the existing task 14/15 pair.
grep -q '^#define TASK_TOUCH_RECORDING_START 14$' "$SRC/pccontrol/Task.h"
grep -q '^#define TASK_TOUCH_RECORDING_STOP 15$' "$SRC/pccontrol/Task.h"
grep -q '^#define TASK_SHOW_TOAST 22$' "$SRC/pccontrol/Task.h"
grep -q '^#define TASK_COLOR_PICKER 23$' "$SRC/pccontrol/Task.h"
grep -q '^#define TASK_TEXT_RECOGNIZER 27$' "$SRC/pccontrol/Task.h"
grep -q '^#define TASK_COLOR_SEARCHER 28$' "$SRC/pccontrol/Task.h"
grep -q '^#define TASK_PROMPT_INPUT 29$' "$SRC/pccontrol/Task.h"
grep -q '^#define TASK_SCREENSHOT 30$' "$SRC/pccontrol/Task.h"
grep -q 'NKTouch v0.7.1: Task.xm owns the single socket response for task 14.' "$RECORD"
! grep -Eq 'notifyClient.*scriptDirectory.*requestClient' "$RECORD"

echo "--- NKTouch v0.7.1 Recorder V2 package ---"
cat "$SRC/control"
cat "$SRC/layout/usr/share/doc/nktouch/VERSION"
