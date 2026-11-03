#!/usr/bin/env bash
set -euo pipefail
SRC="${1:-upstream}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

[[ -d "$SRC" ]] || { echo "Missing upstream source: $SRC" >&2; exit 1; }

# Start from the proven Recorder V5 hardware-stop build.
bash "$ROOT/scripts/prepare-v0755-recorder-v5-volume.sh" "$SRC"
python3 "$ROOT/scripts/apply-v0756-control-foundation.py" "$SRC"

CONTROL="$SRC/control"
VERSION_FILE="$SRC/layout/usr/share/doc/nktouch/VERSION"
SETTINGS="$SRC/zxtouch/zxtouch/Settings/SettingsPageViewController.m"
RUNNER="$SRC/zxtouch-runner/main.m"
TRIGGER="$SRC/nktouch-trigger/Tweak.xm"
CTL="$SRC/layout/usr/bin/nktouchctl"

python3 - "$CONTROL" "$VERSION_FILE" <<'PY'
from pathlib import Path
import sys
control=Path(sys.argv[1]); version_file=Path(sys.argv[2])
s=control.read_text()
s=s.replace('Version: 0.7.5.5','Version: 0.7.5.6',1)
for line in s.splitlines():
    if line.startswith('Description:'):
        s=s.replace(line,'Description: NKTouch v0.7.5.6 Control Foundation with Recorder V5 global Volume Down stop, SpringBoard hotkey dispatcher, accepted/success/failure feedback, haptics, package-wide version reporting and retained Editor/Task/Network stack',1)
        break
control.write_text(s)

v=version_file.read_text()
v=v.replace('NKTouch 0.7.5.5 Recorder V5 Volume Trigger','NKTouch 0.7.5.6 Control Foundation',1)
extra='''Control Foundation: SpringBoard hotkey dispatcher isolates hardware detection from recorder work
Feedback: REC STOPPING / REC SAVED / REC ERROR with haptic acknowledgement
Runner protocol: active recorder -> accepted notification -> finish -> success/failure notification
Version reporting: nktouchctl version returns package version; version --all reports retained component versions
Recorder V5 semantics retained: hold Volume Down 0.5s to Stop + Lua from any app
Touch-point indicator is intentionally deferred to Recorder V6 HID layer; no fake SpringBoard touch overlay
'''
if 'Control Foundation: SpringBoard hotkey dispatcher' not in v:
    v=v.rstrip()+'\n'+extra
version_file.write_text(v)
PY

grep -q '^Version: 0.7.5.6$' "$CONTROL"
grep -q '^NKTouch 0.7.5.6 Control Foundation$' "$VERSION_FILE"
grep -q 'NKHotkeyActionRecorderFinish' "$TRIGGER"
grep -q 'NKDispatchHotkeyAction' "$TRIGGER"
grep -q 'REC STOPPING' "$TRIGGER"
grep -q 'REC SAVED' "$TRIGGER"
grep -q 'REC ERROR' "$TRIGGER"
grep -q 'UINotificationFeedbackGenerator' "$TRIGGER"
grep -q 'kNKRecorderAcceptedNotification' "$RUNNER"
grep -q 'kNKRecorderCompletedOKNotification' "$RUNNER"
grep -q 'kNKRecorderCompletedFailedNotification' "$RUNNER"
grep -q 'notify_post(kNKRecorderAcceptedNotification)' "$RUNNER"
grep -q 'kNKRecorderCompletedOKNotification : kNKRecorderCompletedFailedNotification' "$RUNNER"
grep -q '0.7.5.6' "$SETTINGS"
grep -q 'rung xác nhận' "$SETTINGS"
grep -q 'PACKAGE_VERSION="0.7.5.6"' "$CTL"
grep -q 'version --all' "$CTL"

# Source staging must remain scheme-neutral; Theos alone applies /var/jb.
test ! -e "$SRC/layout/var/jb"

echo "--- NKTouch v0.7.5.6 Control Foundation package ---"
cat "$CONTROL"
cat "$VERSION_FILE"
