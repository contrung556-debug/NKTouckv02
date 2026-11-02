#!/usr/bin/env bash
set -euo pipefail
SRC="${1:-upstream}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

[[ -d "$SRC" ]] || { echo "Missing upstream source: $SRC" >&2; exit 1; }

# Keep the full 7.4.4 Check/Run fix and all earlier UX/runtime layers.
bash "$ROOT/scripts/prepare-v0744-video-check-fix.sh" "$SRC"

CONTROL="$SRC/control"
VERSION_FILE="$SRC/layout/usr/share/doc/nktouch/VERSION"
SETTINGS="$SRC/zxtouch/zxtouch/Settings/SettingsPageViewController.m"
RUNNER="$SRC/layout/usr/bin/nktouch-lua"

python3 - "$CONTROL" "$VERSION_FILE" "$SETTINGS" <<'PY'
from pathlib import Path
import sys

control=Path(sys.argv[1]); version_file=Path(sys.argv[2]); settings=Path(sys.argv[3])

s=control.read_text()
s=s.replace('Version: 0.7.4.4','Version: 0.7.4.5',1)
s=s.replace(
    'Description: NKTouch v0.7.4.4 video check fix with direct Lua syntax/task execution, compact editor navigation and retained v0.7.4.3 shell UX (GPL ZXTouch core)',
    'Description: NKTouch v0.7.4.5 task bootstrap fix with runtime diagnostics, direct Lua syntax/task execution and retained NKTouch shell UX (GPL ZXTouch core)'
)
if 'Version: 0.7.4.5' not in s:
    raise SystemExit('Unable to set package version 0.7.4.5')
control.write_text(s)

v=version_file.read_text()
v=v.replace('NKTouch 0.7.4.4 Video Check Fix','NKTouch 0.7.4.5 Task Bootstrap Fix',1)
extra='Runtime fix: optional AutoTouch compatibility bootstrap; no nil-hook crash\nDiagnostics: terminal task logs include state / exit code / signal in the app UI\n'
if 'Runtime fix: optional AutoTouch compatibility bootstrap' not in v:
    v=v.rstrip()+'\n'+extra
version_file.write_text(v)

u=settings.read_text()
u=u.replace('NKTouch 0.7.4.4','NKTouch 0.7.4.5')
u=u.replace('text:@"7.4.4"','text:@"7.4.5"')
marker='// V7.4.5 task bootstrap fix: optional compat hook + terminal runtime diagnostics.\n'
if marker not in u:
    anchor='// V7.4.4 video check fix: direct checker/task lifecycle + compact editor title + truthful errors.\n'
    if anchor in u: u=u.replace(anchor,anchor+marker,1)
    else: u=marker+u

old='else if([v isEqualToString:@"failed"]||[v isEqualToString:@"timeout"]){self.runState.text=[v isEqualToString:@"timeout"]?@"● Hết thời gian":@"● Tác vụ lỗi";self.runState.textColor=NKRed();[self.progress setProgress:0 animated:YES];[self stopTaskPolling];}'
new='else if([v isEqualToString:@"failed"]||[v isEqualToString:@"timeout"]){NSString*exit=d[@"exit_code"]?:@"?";self.runState.text=[v isEqualToString:@"timeout"]?@"● Hết thời gian":[NSString stringWithFormat:@"● Lỗi runtime • exit %@",exit];self.runState.textColor=NKRed();[self.progress setProgress:0 animated:YES];[self stopTaskPolling];}'
if old not in u:
    raise SystemExit('terminal runState marker missing')
u=u.replace(old,new,1)

old_logs='if(!NKTaskStateIsActive(v)&&self.taskID.length){NSString*tid=self.taskID;dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{int lc=0;NSString*logs=NKLuaRun(@[@"logs",tid,@"100"],&lc);dispatch_async(dispatch_get_main_queue(),^{if(w&&lc==0)w.console.text=logs;});});}'
new_logs='if(!NKTaskStateIsActive(v)&&self.taskID.length){NSString*tid=self.taskID;NSString*terminalState=[state copy];NSString*exitCode=[d[@"exit_code"] copy]?:@"?";NSString*signalNo=[d[@"signal"] copy]?:@"0";dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{int lc=0;NSString*logs=NKLuaRun(@[@"logs",tid,@"100"],&lc);dispatch_async(dispatch_get_main_queue(),^{if(!w)return;if(lc==0){NSString*shown=logs?:@"";if(([terminalState.lowercaseString isEqualToString:@"failed"]||[terminalState.lowercaseString isEqualToString:@"timeout"])&&![shown containsString:@"[NKTouch] terminal"]){shown=[shown stringByAppendingFormat:@"\\n[NKTouch] terminal state=%@ exit_code=%@ signal=%@\\n",terminalState,exitCode,signalNo];}w.console.text=shown;}else{w.console.text=[NSString stringWithFormat:@"[NKTouch] Không đọc được log task %@ (code=%d).\\nstate=%@ exit_code=%@ signal=%@",tid,lc,terminalState,exitCode,signalNo];}});});}'
if old_logs not in u:
    raise SystemExit('terminal logs marker missing')
u=u.replace(old_logs,new_logs,1)

settings.write_text(u)
PY

# The fixed runner is copied into layout by the retained preparation chain.
test -x "$RUNNER"
grep -Fq 'type(m.installAutoTouchCompat)=="function"' "$RUNNER"
if grep -Fq '; m.installAutoTouchCompat()' "$RUNNER"; then
    echo 'Regression: AutoTouch compat hook is still called unconditionally' >&2
    exit 1
fi

grep -q '^Version: 0.7.4.5$' "$CONTROL"
grep -q '^NKTouch 0.7.4.5 Task Bootstrap Fix$' "$VERSION_FILE"
grep -q 'V7.4.5 task bootstrap fix' "$SETTINGS"
grep -q 'Lỗi runtime • exit' "$SETTINGS"
grep -q '\[NKTouch\] terminal state=' "$SETTINGS"

echo "--- NKTouch v0.7.4.5 task bootstrap fix package ---"
cat "$CONTROL"
cat "$VERSION_FILE"
