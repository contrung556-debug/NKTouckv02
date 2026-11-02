#!/usr/bin/env bash
set -euo pipefail
SRC="${1:-upstream}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

[[ -d "$SRC" ]] || { echo "Missing upstream source: $SRC" >&2; exit 1; }

# Retain the fully tested v0.7.4.3 shell/UX and all earlier runtime layers.
bash "$ROOT/scripts/prepare-v0743-stability.sh" "$SRC"

CONTROL="$SRC/control"
VERSION_FILE="$SRC/layout/usr/share/doc/nktouch/VERSION"
EDITOR="$SRC/layout/usr/bin/nkeditor"
SETTINGS="$SRC/zxtouch/zxtouch/Settings/SettingsPageViewController.m"
SCENE="$SRC/zxtouch/zxtouch/SceneDelegate.m"

python3 - "$CONTROL" "$VERSION_FILE" "$EDITOR" "$SETTINGS" "$SCENE" <<'PY'
from pathlib import Path
import re
import sys

control = Path(sys.argv[1])
version_file = Path(sys.argv[2])
editor = Path(sys.argv[3])
settings = Path(sys.argv[4])
scene = Path(sys.argv[5])

# Package/app-facing release metadata.
s = control.read_text()
s = s.replace('Version: 0.7.4.3', 'Version: 0.7.4.4', 1)
s = s.replace(
    'Description: NKTouch v0.7.4.3 stability release over v0.7.4 Network/API with Lua Workspace, Task Bundle, Script Editor, Recorder V2, task engine and hardened direct Lua runtime (GPL ZXTouch core)',
    'Description: NKTouch v0.7.4.4 video check fix with direct Lua syntax/task execution, compact editor navigation and retained v0.7.4.3 shell UX (GPL ZXTouch core)'
)
if 'Version: 0.7.4.4' not in s:
    raise SystemExit('Unable to set package version 0.7.4.4')
control.write_text(s)

v = version_file.read_text()
v = v.replace('NKTouch 0.7.4.3 Stability', 'NKTouch 0.7.4.4 Video Check Fix', 1)
if 'Video fix: direct luac54 check path + direct nktask lifecycle from the app UI' not in v:
    v = v.rstrip() + '\nVideo fix: direct luac54 check path + direct nktask lifecycle from the app UI\nEditor UX: compact file title, truthful check errors, restored NKTouch tab label\n'
version_file.write_text(v)

# Make the CLI editor dependency model truthful as well. A syntax check should
# not fail merely because the API catalog or task engine is unavailable.
e = editor.read_text()
e = e.replace('VERSION="0.7.2"', 'VERSION="0.7.4.4"', 1)
old_need = '''need_runtime() {
  [ -x "$LUAC" ] || { echo "NKTouch Editor: missing Lua compiler: $LUAC" >&2; exit 4; }
  [ -x "$TASK" ] || { echo "NKTouch Editor: missing task engine: $TASK" >&2; exit 4; }
  [ -r "$API" ] || { echo "NKTouch Editor: missing API catalog: $API" >&2; exit 4; }
}
'''
new_need = '''need_syntax_runtime() {
  [ -x "$LUAC" ] || { echo "NKTouch Editor: missing Lua compiler: $LUAC" >&2; exit 4; }
}

need_task_runtime() {
  [ -x "$TASK" ] || { echo "NKTouch Editor: missing task engine: $TASK" >&2; exit 4; }
}

need_api_runtime() {
  [ -r "$API" ] || { echo "NKTouch Editor: missing API catalog: $API" >&2; exit 4; }
}

need_runtime() {
  need_syntax_runtime
  need_task_runtime
  need_api_runtime
}
'''
if old_need not in e:
    raise SystemExit('nkeditor need_runtime marker missing')
e = e.replace(old_need, new_need, 1)

old_check_file = '''check_file() {
  file="$1"
  if "$LUAC" -p "$file"; then
    echo "syntax=ok"
    echo "script=$file"
    return 0
  fi
  echo "syntax=error" >&2
  echo "script=$file" >&2
  return 7
}
'''
new_check_file = '''check_file() {
  file="$1"
  out="$("$LUAC" -p "$file" 2>&1)"
  rc=$?
  if [ "$rc" -eq 0 ]; then
    echo "syntax=ok"
    echo "script=$file"
    return 0
  fi
  [ -z "$out" ] || printf '%s\\n' "$out" >&2
  if [ "$rc" -eq 1 ]; then
    echo "syntax=error" >&2
    echo "script=$file" >&2
    return 7
  fi
  echo "checker=error:$rc" >&2
  echo "script=$file" >&2
  return 4
}
'''
if old_check_file not in e:
    raise SystemExit('nkeditor check_file marker missing')
e = e.replace(old_check_file, new_check_file, 1)

old_check_cmd = '''  check)
    [ "$#" -eq 1 ] || { echo "usage: nktouchctl editor check <name>" >&2; exit 2; }
    mkdir_state
    need_runtime
    file="$(need_script "$1")" || exit $?
    check_file "$file"
    ;;
'''
new_check_cmd = old_check_cmd.replace('    need_runtime\n', '    need_syntax_runtime\n')
if old_check_cmd not in e:
    raise SystemExit('nkeditor check command marker missing')
e = e.replace(old_check_cmd, new_check_cmd, 1)

old_run_cmd = '''  run)
    [ "$#" -ge 1 ] || { echo "usage: nktouchctl editor run <name> [--timeout SEC] [-- args...]" >&2; exit 2; }
    mkdir_state
    need_runtime
    file="$(need_script "$1")" || exit $?
    shift
    "$LUAC" -p "$file" || { echo "NKTouch Editor: refusing to run script with syntax errors" >&2; exit 7; }
    exec "$TASK" start "$file" "$@"
    ;;
'''
new_run_cmd = old_run_cmd.replace('    need_runtime\n', '    need_syntax_runtime\n    need_task_runtime\n')
if old_run_cmd not in e:
    raise SystemExit('nkeditor run command marker missing')
e = e.replace(old_run_cmd, new_run_cmd, 1)
for cmd in ('status', 'pause', 'resume', 'stop', 'logs'):
    old = f'''  {cmd})\n    need_runtime\n    exec "$TASK" {cmd} "$@"\n    ;;\n'''
    new = old.replace('    need_runtime\n', '    need_task_runtime\n')
    if old not in e:
        raise SystemExit(f'nkeditor {cmd} marker missing')
    e = e.replace(old, new, 1)
editor.write_text(e)

u = settings.read_text()
marker = '// V7.4.4 video check fix: direct checker/task lifecycle + compact editor title + truthful errors.\n'
if marker not in u:
    anchor = '// V7.4.3 stability release: synchronized package/app metadata; V7.4.1 UX fixes retained.\n'
    if anchor in u:
        u = u.replace(anchor, anchor + marker, 1)
    else:
        u = marker + u

u = u.replace('NKTouch 0.7.4.3', 'NKTouch 0.7.4.4')
u = u.replace('text:@"7.4.3"', 'text:@"7.4.4"')

# Core UI actions now invoke the native compiler/task supervisor directly.
# This removes the shell/editor wrapper from Check/Run/Status/Stop/Logs and
# fixes the valid-script -> "Lỗi cú pháp" failure seen in the device video.
run_pattern = re.compile(
    r'static NSString \*NKLuaRun\(NSArray<NSString \*> \*arguments, int \*exitCode\) \{.*?\n\}\n\nstatic NSArray<NSString \*> \*NKScripts',
    re.S,
)
new_run = r'''static NSString * const NKLuaCompilerTool = @"/var/jb/usr/libexec/nktouch/luac54";
static NSString * const NKLuaTaskTool = @"/var/jb/usr/bin/nktask";

static NSString *NKLuaRun(NSArray<NSString *> *arguments, int *exitCode) {
    NSArray<NSString *> *spawnArgs = arguments ?: @[];
    NSString *tool = NKLuaEditorTool;
    BOOL syntaxCheck = NO;
    if (arguments.count > 0) {
        NSString *cmd = arguments[0];
        if ([cmd isEqualToString:@"check"] && arguments.count == 2) {
            syntaxCheck = YES;
            tool = NKLuaCompilerTool;
            NSString *path = [NKLuaScriptsPath stringByAppendingPathComponent:[arguments[1] lastPathComponent] ?: @""];
            spawnArgs = @[@"-p", path];
        } else if ([cmd isEqualToString:@"run"] && arguments.count >= 2) {
            tool = NKLuaTaskTool;
            NSMutableArray<NSString *> *a = [NSMutableArray arrayWithObject:@"start"];
            NSString *path = [NKLuaScriptsPath stringByAppendingPathComponent:[arguments[1] lastPathComponent] ?: @""];
            [a addObject:path];
            if (arguments.count > 2) [a addObjectsFromArray:[arguments subarrayWithRange:NSMakeRange(2, arguments.count - 2)]];
            spawnArgs = a;
        } else if ([@[@"status", @"pause", @"resume", @"stop", @"logs"] containsObject:cmd]) {
            tool = NKLuaTaskTool;
            spawnArgs = arguments;
        }
    }

    int p[2] = {-1,-1};
    if (pipe(p) != 0) { if (exitCode) *exitCode = 126; return @"Unable to create command pipe."; }
    posix_spawn_file_actions_t a; posix_spawn_file_actions_init(&a);
    posix_spawn_file_actions_adddup2(&a, p[1], STDOUT_FILENO);
    posix_spawn_file_actions_adddup2(&a, p[1], STDERR_FILENO);
    posix_spawn_file_actions_addclose(&a, p[0]); posix_spawn_file_actions_addclose(&a, p[1]);
    NSUInteger argc = spawnArgs.count + 2;
    char **argv = calloc(argc, sizeof(char *));
    argv[0] = strdup(tool.UTF8String);
    for (NSUInteger i=0;i<spawnArgs.count;i++) argv[i+1] = strdup(spawnArgs[i].UTF8String);
    argv[spawnArgs.count+1] = NULL;
    pid_t pid = 0; int spawnCode = posix_spawn(&pid, tool.UTF8String, &a, NULL, argv, environ);
    posix_spawn_file_actions_destroy(&a); close(p[1]);
    for (NSUInteger i=0;i<spawnArgs.count+1;i++) free(argv[i]); free(argv);
    if (spawnCode != 0) {
        close(p[0]); if (exitCode) *exitCode=spawnCode;
        return [NSString stringWithFormat:@"Unable to launch %@ (%d).",tool.lastPathComponent,spawnCode];
    }
    NSMutableData *data=[NSMutableData data]; uint8_t buf[4096]; ssize_t n=0;
    while ((n=read(p[0],buf,sizeof(buf)))>0) { [data appendBytes:buf length:(NSUInteger)n]; if(data.length>524288)break; }
    close(p[0]); int status=0; waitpid(pid,&status,0); int raw=WIFEXITED(status)?WEXITSTATUS(status):125;
    int code=(syntaxCheck && raw==1)?7:raw;
    if(exitCode)*exitCode=code;
    NSString *text=[[NSString alloc]initWithData:data encoding:NSUTF8StringEncoding];
    return text.length?text:(code==0?@"OK":[NSString stringWithFormat:@"Command failed (%d).",code]);
}

static NSArray<NSString *> *NKScripts'''
u, count = run_pattern.subn(new_run, u, count=1)
if count != 1:
    raise SystemExit(f'Unable to replace NKLuaRun with direct native lifecycle, count={count}')

# Compact editor title: keep the large "Scripts" title in the library, but use
# the normal navigation title for a file so more vertical room is left for code.
old_editor_start = '[super viewDidLoad];self.title=self.scriptName;self.view.backgroundColor=NKBG();if(@available(iOS 13.0,*))self.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;'
new_editor_start = '[super viewDidLoad];self.title=self.scriptName;self.navigationItem.largeTitleDisplayMode=UINavigationItemLargeTitleDisplayModeNever;self.view.backgroundColor=NKBG();if(@available(iOS 13.0,*))self.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;'
if old_editor_start not in u:
    raise SystemExit('Editor viewDidLoad marker missing')
u = u.replace(old_editor_start, new_editor_start, 1)

old_check = '- (void)checkTapped{if(![self save])return;__weak typeof(self)w=self;[self command:@[@"check",self.scriptName] state:@"Đang kiểm tra…" done:^(int c,NSString *o){w.console.text=o;[w setSyntaxText:(c==0?@"Cú pháp hợp lệ":@"Lỗi cú pháp") color:(c==0?NKGreen():NKRed()) icon:(c==0?@"checkmark.circle.fill":@"xmark.circle.fill")];if(c!=0){NSInteger l=[w line:o];if(l!=NSNotFound)[w jump:l];}}];}'
new_check = '- (void)checkTapped{if(![self save])return;__weak typeof(self)w=self;[self command:@[@"check",self.scriptName] state:@"Đang kiểm tra…" done:^(int c,NSString *o){w.console.text=o;if(c==0){[w setSyntaxText:@"Cú pháp hợp lệ" color:NKGreen() icon:@"checkmark.circle.fill"];return;}NSInteger l=[w line:o];if(c==7){NSString *m=l!=NSNotFound?[NSString stringWithFormat:@"Lỗi cú pháp • dòng %ld",(long)l]:@"Lỗi cú pháp";[w setSyntaxText:m color:NKRed() icon:@"xmark.circle.fill"];if(l!=NSNotFound)[w jump:l];return;}[w setSyntaxText:@"Không thể kiểm tra" color:NKRed() icon:@"exclamationmark.triangle.fill"];UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Bộ kiểm tra Lua lỗi" message:(o.length?o:@"Không thể chạy luac54 trên thiết bị.") preferredStyle:UIAlertControllerStyleAlert];[a addAction:[UIAlertAction actionWithTitle:@"Đóng" style:UIAlertActionStyleCancel handler:nil]];[w presentViewController:a animated:YES completion:nil];}];}'
if old_check not in u:
    raise SystemExit('Transformed checkTapped marker missing')
u = u.replace(old_check, new_check, 1)

old_run_handler = '- (void)runTapped{if(![self save])return;self.taskID=nil;__weak typeof(self)w=self;[self command:@[@"check",self.scriptName] state:@"Đang kiểm tra…" done:^(int c,NSString *o){if(c!=0){w.console.text=o;[w setSyntaxText:@"Lỗi cú pháp" color:NKRed() icon:@"xmark.circle.fill"];NSInteger l=[w line:o];if(l!=NSNotFound)[w jump:l];return;}[w setSyntaxText:@"Cú pháp hợp lệ" color:NKGreen() icon:@"checkmark.circle.fill"];[w command:@[@"run",w.scriptName] state:@"● Đang khởi động…" done:^(int rc,NSString *ro){w.console.text=ro;if(rc==0){w.taskID=NKParseKV(ro)[@"task_id"];w.mode.selectedSegmentIndex=1;[w modeChanged];[w startTaskPolling];}else{w.runState.text=@"● Chạy lỗi";w.runState.textColor=NKRed();[w.progress setProgress:0 animated:YES];}}];}];}'
new_run_handler = '- (void)runTapped{if(![self save])return;self.taskID=nil;__weak typeof(self)w=self;[self command:@[@"check",self.scriptName] state:@"Đang kiểm tra…" done:^(int c,NSString *o){if(c!=0){w.console.text=o;NSInteger l=[w line:o];if(c==7){NSString *m=l!=NSNotFound?[NSString stringWithFormat:@"Lỗi cú pháp • dòng %ld",(long)l]:@"Lỗi cú pháp";[w setSyntaxText:m color:NKRed() icon:@"xmark.circle.fill"];if(l!=NSNotFound)[w jump:l];}else{[w setSyntaxText:@"Không thể kiểm tra" color:NKRed() icon:@"exclamationmark.triangle.fill"];UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Không thể chạy" message:(o.length?o:@"Bộ kiểm tra Lua không khởi động được.") preferredStyle:UIAlertControllerStyleAlert];[a addAction:[UIAlertAction actionWithTitle:@"Đóng" style:UIAlertActionStyleCancel handler:nil]];[w presentViewController:a animated:YES completion:nil];}return;}[w setSyntaxText:@"Cú pháp hợp lệ" color:NKGreen() icon:@"checkmark.circle.fill"];[w command:@[@"run",w.scriptName] state:@"● Đang khởi động…" done:^(int rc,NSString *ro){w.console.text=ro;if(rc==0){w.taskID=NKParseKV(ro)[@"task_id"];w.mode.selectedSegmentIndex=1;[w modeChanged];[w startTaskPolling];}else{w.runState.text=@"● Chạy lỗi";w.runState.textColor=NKRed();[w.progress setProgress:0 animated:YES];UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Chạy script lỗi" message:(ro.length?ro:@"nktask không khởi động được.") preferredStyle:UIAlertControllerStyleAlert];[a addAction:[UIAlertAction actionWithTitle:@"Đóng" style:UIAlertActionStyleCancel handler:nil]];[w presentViewController:a animated:YES completion:nil];}}];}];}'
if old_run_handler not in u:
    raise SystemExit('Transformed runTapped marker missing')
u = u.replace(old_run_handler, new_run_handler, 1)
settings.write_text(u)

# The first tab already has the right title logically, but the video shows the
# label hidden while Settings is visible. Reset item positioning explicitly.
z = scene.read_text()
old_tab = 'nav.tabBarItem.title = @"NKTouch";\n                    if (@available(iOS 13.0, *)) nav.tabBarItem.image = [UIImage systemImageNamed:@"terminal.fill"];'
new_tab = 'nav.tabBarItem.title = @"NKTouch";\n                    nav.tabBarItem.imageInsets = UIEdgeInsetsZero;\n                    nav.tabBarItem.titlePositionAdjustment = UIOffsetZero;\n                    nav.tabBarItem.accessibilityLabel = @"NKTouch";\n                    if (@available(iOS 13.0, *)) { nav.tabBarItem.image = [UIImage systemImageNamed:@"terminal.fill"]; nav.tabBarItem.selectedImage = [UIImage systemImageNamed:@"terminal.fill"]; }'
if old_tab not in z:
    raise SystemExit('SceneDelegate NKTouch tab marker missing')
z = z.replace(old_tab, new_tab, 1)
scene.write_text(z)
PY

chmod 755 "$EDITOR"

grep -q '^Version: 0.7.4.4$' "$CONTROL"
grep -q '^NKTouch 0.7.4.4 Video Check Fix$' "$VERSION_FILE"
grep -q 'need_syntax_runtime' "$EDITOR"
grep -q 'need_task_runtime' "$EDITOR"
grep -q 'V7.4.4 video check fix' "$SETTINGS"
grep -q 'NKLuaCompilerTool' "$SETTINGS"
grep -q 'NKLuaTaskTool' "$SETTINGS"
grep -q 'UINavigationItemLargeTitleDisplayModeNever' "$SETTINGS"
grep -q 'Bộ kiểm tra Lua lỗi' "$SETTINGS"
grep -q 'titlePositionAdjustment = UIOffsetZero' "$SCENE"

echo "--- NKTouch v0.7.4.4 video check fix package ---"
cat "$CONTROL"
cat "$VERSION_FILE"
