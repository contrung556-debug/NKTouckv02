#!/usr/bin/env bash
set -euo pipefail
SRC="${1:-upstream}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

[[ -d "$SRC" ]] || { echo "Missing upstream source: $SRC" >&2; exit 1; }
[[ -x "$ROOT/runtime/nkhttp" ]] || { echo "Missing built native HTTP helper" >&2; exit 1; }
[[ -f "$ROOT/runtime/nknetwork" ]] || { echo "Missing Network/API controller" >&2; exit 1; }
[[ -f "$ROOT/lua/nkjson.lua" ]] || { echo "Missing JSON codec" >&2; exit 1; }
[[ -f "$ROOT/lua/nknet.lua" ]] || { echo "Missing Lua network API" >&2; exit 1; }
[[ -f "$ROOT/lua/nktouch_v7.lua" ]] || { echo "Missing V7 Lua extension layer" >&2; exit 1; }

# Reuse V7.3 in full: bundle/editor/recorder/task layers stay intact.
bash "$ROOT/scripts/prepare-v073.sh" "$SRC"

python3 - "$SRC/control" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); s=p.read_text()
s=s.replace('Version: 0.7.3','Version: 0.7.4')
s=s.replace(
    'Description: NKTouch v0.7.3 Task Bundle with Script Editor, Recorder V2, task engine and hardened direct Lua runtime (GPL ZXTouch core)',
    'Description: NKTouch v0.7.4 Network/API with Task Bundle, Script Editor, Recorder V2, task engine and hardened direct Lua runtime (GPL ZXTouch core)'
)
if 'Version: 0.7.4' not in s: raise SystemExit('Unable to set package version 0.7.4')
p.write_text(s)
PY

SETTINGS="$SRC/zxtouch/zxtouch/Settings/SettingsPageViewController.m"
if [[ -f "$SETTINGS" ]]; then
python3 - "$SETTINGS" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); s=p.read_text().replace('NKTouch 0.7.3','NKTouch 0.7.4')
s=s.replace('ZXTouch GPL core • NKTouch Task Bundle','ZXTouch GPL core • NKTouch Network/API')
p.write_text(s)
PY
fi

mkdir -p "$SRC/layout/usr/bin" "$SRC/layout/usr/libexec/nktouch" "$SRC/layout/usr/share/nktouch/lua"
cp "$ROOT/runtime/nktouchctl-v7" "$SRC/layout/usr/bin/nktouchctl"
cp "$ROOT/runtime/nknetwork" "$SRC/layout/usr/bin/nknetwork"
cp "$ROOT/runtime/nkhttp" "$SRC/layout/usr/libexec/nktouch/nkhttp"
cp "$ROOT/runtime/nktouch-lua" "$SRC/layout/usr/bin/nktouch-lua"
cp "$ROOT/lua/nkjson.lua" "$SRC/layout/usr/share/nktouch/lua/nkjson.lua"
cp "$ROOT/lua/nknet.lua" "$SRC/layout/usr/share/nktouch/lua/nknet.lua"
cp "$ROOT/lua/nktouch_v7.lua" "$SRC/layout/usr/share/nktouch/lua/nktouch_v7.lua"
cp "$ROOT/runtime/nktouch-api.tsv" "$SRC/layout/usr/share/nktouch/nktouch-api.tsv"
chmod 755 "$SRC/layout/usr/bin/nktouchctl" "$SRC/layout/usr/bin/nknetwork" "$SRC/layout/usr/bin/nktouch-lua" "$SRC/layout/usr/libexec/nktouch/nkhttp"
chmod 644 "$SRC/layout/usr/share/nktouch/lua/nkjson.lua" "$SRC/layout/usr/share/nktouch/lua/nknet.lua" "$SRC/layout/usr/share/nktouch/lua/nktouch_v7.lua" "$SRC/layout/usr/share/nktouch/nktouch-api.tsv"

python3 - "$SRC/layout/DEBIAN/postinst" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); s=p.read_text()
old='mkdir -p /var/mobile/Library/NKTouch /var/mobile/Library/NKTouch/tmp /var/mobile/Library/NKTouch/tasks /var/mobile/Library/NKTouch/recordings /var/mobile/Library/NKTouch/recorder /var/mobile/Library/NKTouch/scripts /var/mobile/Library/NKTouch/assets /var/mobile/Library/NKTouch/bundles'
new=old+' /var/mobile/Library/NKTouch/tmp/network'
if new not in s:
    if old not in s: raise SystemExit('Unable to extend NKTouch state directories for network')
    s=s.replace(old,new,1)
oldchmod='chmod 755 /var/mobile/Library/NKTouch /var/mobile/Library/NKTouch/tmp /var/mobile/Library/NKTouch/tasks /var/mobile/Library/NKTouch/recordings /var/mobile/Library/NKTouch/recorder /var/mobile/Library/NKTouch/scripts /var/mobile/Library/NKTouch/assets /var/mobile/Library/NKTouch/bundles'
newchmod=oldchmod+' /var/mobile/Library/NKTouch/tmp/network'
if newchmod not in s:
    if oldchmod not in s: raise SystemExit('Unable to extend NKTouch state permissions for network')
    s=s.replace(oldchmod,newchmod,1)
p.write_text(s)
PY

cat > "$SRC/layout/usr/share/doc/nktouch/VERSION" <<'EOF'
NKTouch 0.7.4 Network/API
V7.3 Task Bundle retained
V7.2 Script Editor retained
V7.1 Recorder V2 retained
V7.0 single-active-task supervisor retained
V6.4 hardened direct Lua runtime retained
Native engine 0.6.0
Embedded nkcore 0.6.3
Lua 5.4.9
Network: native NSURLSession HTTP/HTTPS, explicit/on-demand only, no automatic retry
TLS: iOS system certificate validation; HTTPS redirects may not downgrade to HTTP
Request body limit: 16 MiB
Response stream limit: 32 MiB
Secrets: headers/body are passed through temporary files, not nkhttp argv
JSON: bundled bounded pure-Lua codec with explicit json.null
OCR remains explicit/on-demand only
EOF

# V7.4 adds a local helper executable only. It allocates no SpringBoard protocol IDs.
grep -q '^#define TASK_TOUCH_RECORDING_START 14$' "$SRC/pccontrol/Task.h"
grep -q '^#define TASK_TOUCH_RECORDING_STOP 15$' "$SRC/pccontrol/Task.h"
grep -q '^#define TASK_TEXT_RECOGNIZER 27$' "$SRC/pccontrol/Task.h"
grep -q '^#define TASK_PROMPT_INPUT 29$' "$SRC/pccontrol/Task.h"
grep -q '^#define TASK_SCREENSHOT 30$' "$SRC/pccontrol/Task.h"

test -x "$SRC/layout/usr/libexec/nktouch/nkhttp"
test -x "$SRC/layout/usr/bin/nknetwork"
test -f "$SRC/layout/usr/share/nktouch/lua/nkjson.lua"
test -f "$SRC/layout/usr/share/nktouch/lua/nknet.lua"
test -f "$SRC/layout/usr/share/nktouch/lua/nktouch_v7.lua"
grep -q 'nk.http.request' "$SRC/layout/usr/share/nktouch/nktouch-api.tsv"

echo "--- NKTouch v0.7.4 Network/API package ---"
cat "$SRC/control"
cat "$SRC/layout/usr/share/doc/nktouch/VERSION"
