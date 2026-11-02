#!/usr/bin/env bash
set -euo pipefail
SRC="${1:-upstream}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

[[ -d "$SRC" ]] || { echo "Missing upstream source: $SRC" >&2; exit 1; }

# Retain the proven V4 recorder/timeline/editor stack, then replace the primary
# stop mechanism with an AutoTouch-style global hardware trigger.
bash "$ROOT/scripts/prepare-v0754-recorder-smart-stop.sh" "$SRC"

# V4's refreshStatus body can differ slightly depending on which Recorder hotfix
# supplied the status-error branch. Normalize only the method prologue so the V5
# completion poll can be layered without depending on the rest of that body.
python3 - "$SRC/zxtouch/zxtouch/Settings/SettingsPageViewController.m" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); s=p.read_text()
sig='- (void)refreshStatus{'
if sig not in s:
    raise SystemExit('Recorder refreshStatus signature missing')
start=s.index(sig)
window=s[start:start+160]
if 'if(self.smartFinishing)return;' not in window:
    s=s[:start]+s[start:].replace(sig, sig+'if(self.smartFinishing)return;', 1)
p.write_text(s)
PY

python3 "$ROOT/scripts/apply-v0755-recorder-v5-volume.py" "$SRC"

CONTROL="$SRC/control"
VERSION_FILE="$SRC/layout/usr/share/doc/nktouch/VERSION"
SETTINGS="$SRC/zxtouch/zxtouch/Settings/SettingsPageViewController.m"
RUNNER="$SRC/zxtouch-runner/main.m"
TRIGGER="$SRC/nktouch-trigger/Tweak.xm"
ROOT_MAKEFILE="$SRC/Makefile"

python3 - "$CONTROL" "$VERSION_FILE" <<'PY'
from pathlib import Path
import sys
control=Path(sys.argv[1]); version_file=Path(sys.argv[2])
s=control.read_text()
s=s.replace('Version: 0.7.5.4','Version: 0.7.5.5',1)
for line in s.splitlines():
    if line.startswith('Description:'):
        s=s.replace(line,'Description: NKTouch v0.7.5.5 Recorder V5 with AutoTouch-style global Volume Down hold stop, SpringBoard-to-runner handoff, clean zero-trim hardware finish, automatic Lua generation/open Editor and retained Recorder V4 timeline tools',1)
        break
control.write_text(s)

v=version_file.read_text().replace('NKTouch 0.7.5.4 Recorder V4 Smart Stop','NKTouch 0.7.5.5 Recorder V5 Volume Trigger',1)
extra='''Recorder V5: hold Volume Down for 0.5s to stop from any app
SpringBoard trigger: hardware detection only; no recorder work runs inside SpringBoard
Runner handoff: Darwin notification -> existing mobile zxtouch-runner daemon
Clean hardware finish: finish 0, so no Stop/return touch is trimmed or guessed
Short Volume Down presses remain normal and the system receives balanced down/up events
Return to NKTouch never stops an active recording by itself
Completion marker: generated timeline/Lua is consumed and opened by Recorder UI
Manual on-screen Stop remains available as the V4 trim-one fallback
Recorder V4/V3 timeline editing, replay, Editor Pro, Task Center and direct lua54 retained
'''
if 'Recorder V5: hold Volume Down for 0.5s' not in v:
    v=v.rstrip()+'\n'+extra
version_file.write_text(v)
PY

grep -q '^Version: 0.7.5.5$' "$CONTROL"
grep -q '^NKTouch 0.7.5.5 Recorder V5 Volume Trigger$' "$VERSION_FILE"
grep -q 'nktouch-trigger' "$ROOT_MAKEFILE"
grep -q 'SBVolumeHardwareButton' "$TRIGGER"
grep -q 'volumeDecreasePress:' "$TRIGGER"
grep -q 'NKRecorderHoldDelay = 0.5' "$TRIGGER"
grep -q 'com.nk.nktouch.recorder.volume-down-hold' "$TRIGGER"
grep -q '%orig;' "$TRIGGER"
grep -q 'kNKRecorderVolumeHoldNotification' "$RUNNER"
grep -q 'NKRegisterRecorderHardwareTrigger' "$RUNNER"
grep -q 'notify_register_dispatch' "$RUNNER"
grep -q '/var/jb/usr/bin/nkrecorder' "$RUNNER"
grep -q '"finish"' "$RUNNER"
grep -q '"0"' "$RUNNER"
grep -q 'volume_completed' "$RUNNER"
grep -q 'Recorder V5' "$SETTINGS"
grep -q 'Giữ Volume ↓ 0.5s = Stop + Lua' "$SETTINGS"
grep -q 'checkHardwareCompletion' "$SETTINGS"
grep -q 'nkRecorderDidBecomeActive.*checkHardwareCompletion' "$SETTINGS"
if grep -q 'nkRecorderDidBecomeActive.*smartFinishWithTrim:1' "$SETTINGS"; then
  echo 'V5 regression: foreground still auto-stops recorder' >&2
  exit 1
fi
grep -q 'Rebuild Lua' "$SETTINGS"
grep -q 'shellCandidates=@\[@"/var/jb/bin/sh",@"/var/jb/usr/bin/sh",@"/bin/sh"\]' "$SETTINGS"

echo "--- NKTouch v0.7.5.5 Recorder V5 Volume Trigger package ---"
cat "$CONTROL"
cat "$VERSION_FILE"
