#!/usr/bin/env bash
set -euo pipefail
SRC="${1:-upstream}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

[[ -d "$SRC" ]] || { echo "Missing upstream source: $SRC" >&2; exit 1; }
[[ -f "$ROOT/patches/NKLuaWorkspace.m.inc" ]] || { echo "Missing Lua Workspace UX patch" >&2; exit 1; }
[[ -f "$ROOT/scripts/apply-v741-video-ux.py" ]] || { echo "Missing V7.4.1 video UX transformer" >&2; exit 1; }

python3 "$ROOT/scripts/apply-v741-video-ux.py" "$ROOT/patches/NKLuaWorkspace.m.inc"

# The CLI syntax is: logs [TASK_ID] [LINES]. When there is no task ID,
# appending "100" would be interpreted as TASK_ID="100". Keep the default
# active-task lookup in that case, and only append the line count with an ID.
python3 - "$ROOT/patches/NKLuaWorkspace.m.inc" <<'PY'
from pathlib import Path
import re
import sys

p = Path(sys.argv[1])
s = p.read_text()
pattern = re.compile(
    r'(?m)^(?P<i>[ \t]*)if \(tid\.length\) \[a addObject:tid\];\n'
    r'[ \t]*\[a addObject:@"100"\];$'
)

def repl(m):
    i = m.group('i')
    return (
        f'{i}if (tid.length) {{\n'
        f'{i}    [a addObject:tid];\n'
        f'{i}    [a addObject:@"100"];\n'
        f'{i}}}'
    )

s2, count = pattern.subn(repl, s, count=1)
if count == 0:
    fixed = re.search(
        r'(?s)if \(tid\.length\) \{\s*'
        r'\[a addObject:tid\];\s*'
        r'\[a addObject:@"100"\];\s*\}',
        s,
    )
    if not fixed:
        raise SystemExit('Could not locate v0.7.4.1 Logs argument block')
else:
    p.write_text(s2)
PY

# Regression guard: a bare "logs 100" must never be generated again.
if grep -Fq 'if (tid.length) [a addObject:tid];' "$ROOT/patches/NKLuaWorkspace.m.inc"; then
    echo "Invalid Logs argument layout: line count can become task ID" >&2
    exit 1
fi

bash "$ROOT/scripts/prepare-v074.sh" "$SRC"

SETTINGS="$SRC/zxtouch/zxtouch/Settings/SettingsPageViewController.m"
[[ -f "$SETTINGS" ]] || { echo "Missing SettingsPageViewController.m" >&2; exit 1; }

python3 - "$SETTINGS" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
s=p.read_text()
old='''    Class workspaceClass = NSClassFromString(@"NKLuaWorkspaceViewController");
    if (!workspaceClass) {
        [Util showAlertBoxWithOneOption:self title:@"Lua Workspace"
            message:@"Lua Workspace UI is unavailable in this build."
            buttonString:@"OK"];
        return;
    }
    UIViewController *workspaceController = [[workspaceClass alloc] init];
    [self.navigationController pushViewController:workspaceController animated:YES];'''
new='''    Class workspaceClass = NSClassFromString(@"NKLuaLibraryViewController");
    if (!workspaceClass) {
        [Util showAlertBoxWithOneOption:self title:@"Lua Workspace"
            message:@"Lua Workspace UI is unavailable in this build."
            buttonString:@"OK"];
        return;
    }
    UIViewController *workspaceController = [[workspaceClass alloc] init];
    workspaceController.hidesBottomBarWhenPushed = YES;
    [self.navigationController pushViewController:workspaceController animated:YES];'''
if old not in s:
    raise SystemExit('Unable to convert Settings entry to direct Lua Workspace library')
s=s.replace(old,new,1)
p.write_text(s)
PY

grep -q 'V7.4.1 video UX hotfix' "$SETTINGS"
grep -q 'NSClassFromString(@"NKLuaLibraryViewController")' "$SETTINGS"
grep -q 'workspaceController.hidesBottomBarWhenPushed = YES' "$SETTINGS"
grep -q 'Gần đây' "$SETTINGS"
grep -q 'trailingSwipeActionsConfigurationForRowAtIndexPath' "$SETTINGS"
grep -q 'OCR (chủ động)' "$SETTINGS"
grep -q 'startTaskPolling' "$SETTINGS"
grep -q 'Cú pháp hợp lệ' "$SETTINGS"

echo "NKTouch V7.4.1 video UX hotfix prepared"