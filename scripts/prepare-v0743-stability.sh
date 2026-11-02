#!/usr/bin/env bash
set -euo pipefail
SRC="${1:-upstream}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

[[ -d "$SRC" ]] || { echo "Missing upstream source: $SRC" >&2; exit 1; }

# Keep every tested v0.7.4.1 behavior, including the Logs-without-taskID fix
# and the resilient .deb collection compatibility hook.
bash "$ROOT/scripts/prepare-v0741-video-ux.sh" "$SRC"

CONTROL="$SRC/control"
VERSION_FILE="$SRC/layout/usr/share/doc/nktouch/VERSION"
SETTINGS="$SRC/zxtouch/zxtouch/Settings/SettingsPageViewController.m"
SCENE="$SRC/zxtouch/zxtouch/SceneDelegate.m"

python3 - "$CONTROL" "$VERSION_FILE" "$SETTINGS" <<'PY'
from pathlib import Path
import sys

control = Path(sys.argv[1])
version_file = Path(sys.argv[2])
settings = Path(sys.argv[3])

s = control.read_text()
s = s.replace('Version: 0.7.4.1', 'Version: 0.7.4.3', 1)
s = s.replace(
    'Description: NKTouch v0.7.4.1 UI/UX polish over v0.7.4 Network/API with Task Bundle, Script Editor, Recorder V2, task engine and hardened direct Lua runtime (GPL ZXTouch core)',
    'Description: NKTouch v0.7.4.3 stability release over v0.7.4 Network/API with Lua Workspace, Task Bundle, Script Editor, Recorder V2, task engine and hardened direct Lua runtime (GPL ZXTouch core)'
)
if 'Version: 0.7.4.3' not in s:
    raise SystemExit('Unable to set package version 0.7.4.3')
control.write_text(s)

v = version_file.read_text()
v = v.replace('NKTouch 0.7.4.1 UI/UX', 'NKTouch 0.7.4.3 Stability', 1)
if 'Release: package/app version metadata synchronized by CI' not in v:
    v = v.rstrip() + '\nRelease: package/app version metadata synchronized by CI\n'
version_file.write_text(v)

if settings.exists():
    u = settings.read_text()
    u = u.replace('NKTouch 0.7.4.1', 'NKTouch 0.7.4.3')
    u = u.replace('NKTouch UI/UX 7.4.1', 'NKTouch UI/UX 7.4.3')
    marker = '// V7.4.3 stability release: synchronized package/app metadata; V7.4.1 UX fixes retained.\n'
    if marker not in u:
        anchor = '// V7.4.1 video UX hotfix: direct workspace, real filters/samples/task state.\n'
        if anchor in u:
            u = u.replace(anchor, anchor + marker, 1)
        else:
            u = marker + u
    settings.write_text(u)
PY

# Video-review UX rebuild: replace the legacy Scripts-first shell, keep the
# proven Lua/editor/task engine, and make Home/Workspace/Settings visually one app.
python3 "$ROOT/scripts/apply-v743-shell-ux.py" "$SRC"

grep -q '^Version: 0.7.4.3$' "$CONTROL"
grep -q '^NKTouch 0.7.4.3 Stability$' "$VERSION_FILE"
grep -q 'Release: package/app version metadata synchronized by CI' "$VERSION_FILE"
grep -q 'V7.4.3 stability release' "$SETTINGS"
grep -q 'V7.4.3 shell UX rebuild' "$SETTINGS"
grep -q 'Lua Studio' "$SETTINGS"
grep -q 'vc.hidesBottomBarWhenPushed=YES' "$SETTINGS"
grep -q 'self.title = @"Cài đặt"' "$SETTINGS"
grep -q 'V7.4.3 NKTouch root shell' "$SCENE"
grep -q 'NSClassFromString(@"NKLuaWorkspaceViewController")' "$SCENE"
grep -q 'nav.tabBarItem.title = @"NKTouch"' "$SCENE"

# Guard the v0.7.4.1 Logs fix: never emit ambiguous `logs 100` when task ID is absent.
grep -Fq 'if(self.taskID.length){[args addObject:self.taskID];[args addObject:@"100"];}' "$ROOT/patches/NKLuaWorkspace.m.inc"
if grep -Fq 'if(self.taskID.length)[args addObject:self.taskID];[args addObject:@"100"];' "$ROOT/patches/NKLuaWorkspace.m.inc"; then
    echo "Regression: Logs line count can become TASK_ID" >&2
    exit 1
fi

echo "--- NKTouch v0.7.4.3 stability + shell UX package ---"
cat "$CONTROL"
cat "$VERSION_FILE"
