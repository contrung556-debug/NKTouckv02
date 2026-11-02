#!/usr/bin/env bash
set -euo pipefail
SRC="${1:-upstream}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

[[ -d "$SRC" ]] || { echo "Missing upstream source: $SRC" >&2; exit 1; }
[[ -f "$ROOT/patches/NKLuaWorkspace.m.inc" ]] || { echo "Missing Lua Workspace UX patch" >&2; exit 1; }
[[ -f "$ROOT/scripts/apply-v741-video-ux.py" ]] || { echo "Missing V7.4.1 video UX transformer" >&2; exit 1; }

python3 "$ROOT/scripts/apply-v741-video-ux.py" "$ROOT/patches/NKLuaWorkspace.m.inc"

# Fix Logs argument handling after the V7.4.1 transformer has run.
# nktask syntax is: logs [TASK_ID] [LINES]. Therefore a line limit may only
# be appended when a task ID is present; otherwise `logs 100` treats 100 as ID.
python3 - "$ROOT/patches/NKLuaWorkspace.m.inc" <<'PY'
from pathlib import Path
import sys

p = Path(sys.argv[1])
s = p.read_text()
old = '- (void)logsTapped{__weak typeof(self)w=self;NSMutableArray*args=[NSMutableArray arrayWithObject:@"logs"];if(self.taskID.length)[args addObject:self.taskID];[args addObject:@"100"];[self command:args state:@"Đang tải logs…" done:^(int c,NSString *o){w.console.text=o;if(c!=0){w.runState.text=@"Log chưa sẵn sàng";w.runState.textColor=NKMuted();}else [w pollTaskStatus];}];}'
new = '- (void)logsTapped{__weak typeof(self)w=self;NSMutableArray*args=[NSMutableArray arrayWithObject:@"logs"];if(self.taskID.length){[args addObject:self.taskID];[args addObject:@"100"];}[self command:args state:@"Đang tải logs…" done:^(int c,NSString *o){if(c!=0){w.console.text=@"[NKTouch] Chưa có tác vụ hoặc log để hiển thị.";w.runState.text=@"Log chưa sẵn sàng";w.runState.textColor=NKMuted();}else{w.console.text=o;[w pollTaskStatus];}}];}'
if old in s:
    s = s.replace(old, new, 1)
elif new not in s:
    raise SystemExit('Could not locate transformed v0.7.4.1 Logs handler')
p.write_text(s)
PY

# Regression guards: never emit the ambiguous `logs 100` argument layout.
grep -Fq 'if(self.taskID.length){[args addObject:self.taskID];[args addObject:@"100"];}' "$ROOT/patches/NKLuaWorkspace.m.inc"
if grep -Fq 'if(self.taskID.length)[args addObject:self.taskID];[args addObject:@"100"];' "$ROOT/patches/NKLuaWorkspace.m.inc"; then
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
