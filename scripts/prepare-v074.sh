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
[[ -f "$ROOT/patches/NKLuaWorkspace.m.inc" ]] || { echo "Missing Lua Workspace UX patch" >&2; exit 1; }

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
python3 - "$SETTINGS" "$ROOT/patches/NKLuaWorkspace.m.inc" <<'PY'
from pathlib import Path
import sys

p=Path(sys.argv[1])
workspace=Path(sys.argv[2]).read_text()
s=p.read_text()

s=s.replace('NKTouch 0.7.3','NKTouch 0.7.4')
s=s.replace('ZXTouch GPL core • NKTouch Task Bundle','ZXTouch GPL core • NKTouch Network/API')

if 'NKTouch Lua Workspace UX layer (V7.4)' not in s:
    icon_marker='- (NSString *)iconNameForCellTitle:(NSString *)title {\n'
    if icon_marker not in s:
        raise SystemExit('Unable to locate Settings icon mapping for Lua Workspace')
    s=s.replace(
        icon_marker,
        icon_marker+'    if ([title containsString:@"Lua Workspace"]) return @"chevron.left.forwardslash.chevron.right";\n',
        1
    )

    script_marker='''        @[
            @{@"type": @(SETTING_CELL_SWITCH), @"title": NSLocalizedString(@"switchAppBeforePlaying", nil),'''
    workspace_cell='''        @[
            @{@"type": @(SETTING_CELL_ENTRY), @"title": @"Lua Workspace", @"secondary_title": @"Edit • Check • Run • Logs", @"row_click_handler": NSStringFromSelector(@selector(handleLuaWorkspaceTap:))},
            @{@"type": @(SETTING_CELL_SWITCH), @"title": NSLocalizedString(@"switchAppBeforePlaying", nil),'''
    count=s.count(script_marker)
    if count != 2:
        raise SystemExit(f'Expected 2 Script section markers, found {count}')
    s=s.replace(script_marker, workspace_cell)

    end_marker='\n@end'
    pos=s.rfind(end_marker)
    if pos < 0:
        raise SystemExit('Unable to locate SettingsPageViewController @end')
    handler=r'''
- (void)handleLuaWorkspaceTap:(TableViewCellWithEntry *)cell {
    (void)cell;
    Class workspaceClass = NSClassFromString(@"NKLuaWorkspaceViewController");
    if (!workspaceClass) {
        [Util showAlertBoxWithOneOption:self title:@"Lua Workspace"
            message:@"Lua Workspace UI is unavailable in this build."
            buttonString:@"OK"];
        return;
    }
    UIViewController *workspaceController = [[workspaceClass alloc] init];
    [self.navigationController pushViewController:workspaceController animated:YES];
}

'''
    s=s[:pos]+handler+s[pos:]
    s=s.rstrip()+"\n\n"+workspace.rstrip()+"\n"

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
Lua Workspace: native on-device Edit -> Check -> Run -> Logs UX
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

# V7.4 adds local helpers/UI only. It allocates no SpringBoard protocol IDs.
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

if [[ -f "$SETTINGS" ]]; then
    grep -q 'Lua Workspace' "$SETTINGS"
    grep -q 'NKLuaWorkspaceViewController' "$SETTINGS"
    grep -q 'Edit • Check • Run • Logs' "$SETTINGS"
fi

echo "--- NKTouch v0.7.4 Network/API package ---"
cat "$SRC/control"
cat "$SRC/layout/usr/share/doc/nktouch/VERSION"
