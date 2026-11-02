#!/usr/bin/env python3
from pathlib import Path
import sys

if len(sys.argv) != 2:
    raise SystemExit('usage: apply-v0755-recorder-v5-volume.py <upstream-dir>')

root = Path(sys.argv[1])
repo = Path(__file__).resolve().parents[1]
settings = root / 'zxtouch/zxtouch/Settings/SettingsPageViewController.m'
runner = root / 'zxtouch-runner/main.m'
makefile = root / 'Makefile'
trigger_template = repo / 'patches/NKTouchRecorderTrigger.xm'
for p in (settings, runner, makefile, trigger_template):
    if not p.exists():
        raise SystemExit(f'missing required file: {p}')

# ---------------------------------------------------------------------------
# 1. SpringBoard-only hardware trigger subproject.
# ---------------------------------------------------------------------------
mk = makefile.read_text()
old_projects = 'SUBPROJECTS = appdelegate zxtouch-binary zxtouch-runner pccontrol'
new_projects = 'SUBPROJECTS = appdelegate zxtouch-binary zxtouch-runner pccontrol nktouch-trigger'
if new_projects not in mk:
    if old_projects not in mk:
        raise SystemExit('top-level SUBPROJECTS marker missing')
    mk = mk.replace(old_projects, new_projects, 1)
makefile.write_text(mk)

trigger_dir = root / 'nktouch-trigger'
trigger_dir.mkdir(exist_ok=True)
(trigger_dir / 'Tweak.xm').write_text(trigger_template.read_text())
(trigger_dir / 'Makefile').write_text('''include $(THEOS)/makefiles/common.mk

TWEAK_NAME = NKTouchRecorderTrigger
NKTouchRecorderTrigger_FILES = Tweak.xm
NKTouchRecorderTrigger_CFLAGS = -fobjc-arc -O2 -DNDEBUG
NKTouchRecorderTrigger_FRAMEWORKS = UIKit QuartzCore

include $(THEOS_MAKE_PATH)/tweak.mk
''')
(trigger_dir / 'NKTouchRecorderTrigger.plist').write_text('{ Filter = { Bundles = ( "com.apple.springboard" ); }; }\n')

# ---------------------------------------------------------------------------
# 2. Reuse the existing mobile zxtouch-runner daemon for Recorder finish work.
#    SpringBoard only posts a Darwin notification. This stays compatible with
#    iOS 18+ where SpringBoard itself may be unable to exec jbroot programs.
# ---------------------------------------------------------------------------
r = runner.read_text()
if '#include <notify.h>' not in r:
    r = r.replace('#import <Foundation/Foundation.h>\n', '#import <Foundation/Foundation.h>\n#include <notify.h>\n', 1)

const_anchor = 'static NSString *const kSecretPath = @"/var/mobile/Library/ZXTouch/config/tweak/runner.secret";\n'
const_block = '''static NSString *const kSecretPath = @"/var/mobile/Library/ZXTouch/config/tweak/runner.secret";

// NKTouch Recorder V5: SpringBoard posts only this Darwin notification. The
// existing mobile runner performs the bounded finish/render work out-of-process.
static const char *kNKRecorderVolumeHoldNotification = "com.nk.nktouch.recorder.volume-down-hold";
static const char *kNKRecorderCompletedNotification = "com.nk.nktouch.recorder.completed";
static NSString *const kNKRecorderStateDir = @"/var/mobile/Library/NKTouch/recorder-v3";
static NSString *const kNKRecorderModePath = @"/var/mobile/Library/NKTouch/recorder-v3/mode";
static NSString *const kNKRecorderCompletionPath = @"/var/mobile/Library/NKTouch/recorder-v3/volume_completed";
static NSString *const kNKRecorderFinishLogPath = @"/var/mobile/Library/NKTouch/recorder-v3/volume_finish.log";
static int gNKRecorderNotifyToken = 0;
static dispatch_queue_t gNKRecorderQueue;
'''
if 'kNKRecorderVolumeHoldNotification' not in r:
    if const_anchor not in r:
        raise SystemExit('runner secret constant marker missing')
    r = r.replace(const_anchor, const_block, 1)

runner_functions = r'''
static BOOL NKRecorderModeIsActive(void)
{
    NSString *mode = [[NSString stringWithContentsOfFile:kNKRecorderModePath
                                                encoding:NSUTF8StringEncoding
                                                   error:nil]
                      stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return [mode isEqualToString:@"recording"] || [mode isEqualToString:@"paused"];
}

static void NKWriteRecorderCompletion(NSString *output, int code)
{
    [[NSFileManager defaultManager] createDirectoryAtPath:kNKRecorderStateDir
                              withIntermediateDirectories:YES attributes:nil error:nil];
    NSMutableString *result = [NSMutableString stringWithString:output ?: @""];
    if (result.length && ![result hasSuffix:@"\n"]) [result appendString:@"\n"];
    [result appendFormat:@"exit_code=%d\ntrigger=volume_down_hold\n", code];
    NSString *tmp = [kNKRecorderCompletionPath stringByAppendingString:@".tmp"];
    if ([result writeToFile:tmp atomically:YES encoding:NSUTF8StringEncoding error:nil]) {
        [[NSFileManager defaultManager] removeItemAtPath:kNKRecorderCompletionPath error:nil];
        [[NSFileManager defaultManager] moveItemAtPath:tmp toPath:kNKRecorderCompletionPath error:nil];
    }
    notify_post(kNKRecorderCompletedNotification);
}

static void NKFinishRecorderFromVolumeHold(void)
{
    @autoreleasepool {
        // A second hold queued while the first one is finishing becomes a no-op
        // because finish clears the mode/session state.
        if (!NKRecorderModeIsActive()) return;

        [[NSFileManager defaultManager] createDirectoryAtPath:kNKRecorderStateDir
                                  withIntermediateDirectories:YES attributes:nil error:nil];
        unlink(kNKRecorderFinishLogPath.fileSystemRepresentation);

        posix_spawn_file_actions_t actions;
        posix_spawn_file_actions_init(&actions);
        posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0);
        posix_spawn_file_actions_addopen(&actions, STDOUT_FILENO, kNKRecorderFinishLogPath.fileSystemRepresentation,
                                         O_WRONLY | O_CREAT | O_TRUNC, 0644);
        posix_spawn_file_actions_addopen(&actions, STDERR_FILENO, kNKRecorderFinishLogPath.fileSystemRepresentation,
                                         O_WRONLY | O_CREAT | O_APPEND, 0644);

        char *argv[] = {
            (char *)"sh",
            (char *)"/var/jb/usr/bin/nkrecorder",
            (char *)"finish",
            (char *)"0",
            NULL
        };
        pid_t pid = 0;
        int spawnError = posix_spawn(&pid, gShellPath, &actions, NULL, argv, environ);
        posix_spawn_file_actions_destroy(&actions);

        if (spawnError != 0) {
            NKWriteRecorderCompletion([NSString stringWithFormat:@"state=error\nerror=spawn_failed_%d\nlog=%@\n",
                                       spawnError, kNKRecorderFinishLogPath], 126);
            return;
        }

        int status = 0;
        pid_t waited;
        do { waited = waitpid(pid, &status, 0); } while (waited < 0 && errno == EINTR);
        int code = 125;
        if (waited == pid) {
            if (WIFEXITED(status)) code = WEXITSTATUS(status);
            else if (WIFSIGNALED(status)) code = 128 + WTERMSIG(status);
        }

        NSString *output = [NSString stringWithContentsOfFile:kNKRecorderFinishLogPath
                                                     encoding:NSUTF8StringEncoding error:nil] ?: @"";
        if (code != 0 && ![output containsString:@"state="]) {
            output = [NSString stringWithFormat:@"state=error\nerror=finish_failed\nlog=%@\n%@",
                      kNKRecorderFinishLogPath, output];
        }
        NKWriteRecorderCompletion(output, code);
    }
}

static void NKRegisterRecorderHardwareTrigger(void)
{
    gNKRecorderQueue = dispatch_queue_create("com.nk.nktouch.recorder.volume", DISPATCH_QUEUE_SERIAL);
    notify_register_dispatch(kNKRecorderVolumeHoldNotification, &gNKRecorderNotifyToken, gNKRecorderQueue, ^(int token) {
        (void)token;
        NKFinishRecorderFromVolumeHold();
    });
}

'''
if 'static void NKRegisterRecorderHardwareTrigger(void)' not in r:
    anchor = 'static int connectToTweak(void)\n'
    pos = r.find(anchor)
    if pos < 0:
        raise SystemExit('runner connectToTweak marker missing')
    r = r[:pos] + runner_functions + r[pos:]

main_anchor = '''        gGroups = [NSMutableSet set];
        resolveShell();
        prepareEnvironment();
'''
main_new = '''        gGroups = [NSMutableSet set];
        resolveShell();
        prepareEnvironment();
        NKRegisterRecorderHardwareTrigger();
'''
if 'NKRegisterRecorderHardwareTrigger();' not in r:
    if main_anchor not in r:
        raise SystemExit('runner main initialization marker missing')
    r = r.replace(main_anchor, main_new, 1)
runner.write_text(r)

# ---------------------------------------------------------------------------
# 3. Recorder UI: returning to NKTouch must NOT stop recording anymore.
#    Volume Down hold is the primary stop. Manual Stop remains the V4 fallback
#    and keeps tail-trim only for the on-screen Stop tap.
# ---------------------------------------------------------------------------
s = settings.read_text()
marker = '// V0.7.5.5 Recorder V5: AutoTouch-style Volume Down hold global stop via SpringBoard + runner.\n'
if marker not in s:
    v4marker = '// V0.7.5.4 Recorder V4: foreground smart-stop, tail trim and automatic Lua render.\n'
    s = s.replace(v4marker, v4marker + marker, 1) if v4marker in s else marker + s

# Branding/user-facing copy.
s = s.replace('self.title=@"Recorder V4";', 'self.title=@"Recorder V5";', 1)
s = s.replace('title.text=@"Ghi thông minh";', 'title.text=@"Ghi như AutoTouch";', 1)
s = s.replace('self.detailLabel.text=@"Quay lại NKTouch = Stop + Lua";', 'self.detailLabel.text=@"Giữ Volume ↓ 0.5s = Stop + Lua";', 1)
s = s.replace('UIAlertController*a=[UIAlertController alertControllerWithTitle:@"Recorder V4"', 'UIAlertController*a=[UIAlertController alertControllerWithTitle:@"Recorder V5"')

old_record = '''- (void)recordTapped{__weak typeof(self)w=self;[self run:@[@"start"] done:^(int c,NSString*o){typeof(self)self=w;if(!self)return;if(c==0){self.recState=@"recording";self.smartStopArmed=YES;self.leftAppWhileRecording=NO;self.smartFinishing=NO;[self refreshStatus];UIAlertController*a=[UIAlertController alertControllerWithTitle:@"Smart Recorder đang chạy" message:@"Sang app cần ghi và thao tác bình thường. Khi xong chỉ cần quay lại NKTouch — Recorder sẽ tự dừng, bỏ thao tác quay về, sinh Lua và mở Editor." preferredStyle:UIAlertControllerStyleAlert];if(@available(iOS 13.0,*))a.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;[a addAction:[UIAlertAction actionWithTitle:@"Bắt đầu" style:UIAlertActionStyleDefault handler:nil]];[self presentViewController:a animated:YES completion:nil];}else [self showRecorderError:o];}];}
'''
new_record = '''- (void)recordTapped{__weak typeof(self)w=self;[self run:@[@"start"] done:^(int c,NSString*o){typeof(self)self=w;if(!self)return;if(c==0){self.recState=@"recording";self.smartStopArmed=YES;self.leftAppWhileRecording=NO;self.smartFinishing=NO;[self refreshStatus];UIAlertController*a=[UIAlertController alertControllerWithTitle:@"Recorder đang chạy" message:@"Sang app cần ghi và thao tác bình thường. Khi xong, giữ Volume Down khoảng 0.5 giây để dừng. Không cần quay lại NKTouch và thao tác phím cứng không bị ghi vào Timeline." preferredStyle:UIAlertControllerStyleAlert];if(@available(iOS 13.0,*))a.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;[a addAction:[UIAlertAction actionWithTitle:@"Bắt đầu" style:UIAlertActionStyleDefault handler:nil]];[self presentViewController:a animated:YES completion:nil];}else [self showRecorderError:o];}];}
'''
if old_record not in s:
    raise SystemExit('V4 recordTapped marker missing')
s = s.replace(old_record, new_record, 1)

# Add completion reader. The runner writes exactly one marker per hardware stop;
# deleting it before opening Editor makes this idempotent across foreground events.
completion_method = r'''- (void)checkHardwareCompletion{NSString*marker=@"/var/mobile/Library/NKTouch/recorder-v3/volume_completed";NSFileManager*fm=NSFileManager.defaultManager;if(![fm fileExistsAtPath:marker])return;NSString*o=[NSString stringWithContentsOfFile:marker encoding:NSUTF8StringEncoding error:nil]?:@"";[fm removeItemAtPath:marker error:nil];NSDictionary*d=NKParseKV(o);NSInteger code=[d[@"exit_code"] integerValue];NSString*script=d[@"script"];NSString*timeline=d[@"timeline"];self.smartStopArmed=NO;self.leftAppWhileRecording=NO;self.smartFinishing=NO;if(timeline.length)self.timelinePath=timeline;if(code==0&&script.length){self.recState=@"idle";self.stateLabel.text=@"✓ ĐÃ TẠO LUA";self.stateLabel.textColor=NKGreen();self.detailLabel.text=[NSString stringWithFormat:@"Volume ↓ • %@",script.lastPathComponent?:@"script.lua"];[self reloadTimeline];dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.18*NSEC_PER_SEC)),dispatch_get_main_queue(),^{[self openGeneratedScript:script];});}else{self.stateLabel.text=@"● LỖI HARDWARE STOP";self.stateLabel.textColor=NKRed();NSString*err=d[@"error"]?:@"Không tạo được Lua";self.detailLabel.text=[NSString stringWithFormat:@"%@ • exit %ld",err,(long)code];}}
'''
if '- (void)checkHardwareCompletion{' not in s:
    open_sig = '- (void)openGeneratedScript:(NSString*)path{'
    pos = s.find(open_sig)
    if pos < 0:
        raise SystemExit('V4 openGeneratedScript marker missing')
    s = s[:pos] + completion_method + s[pos:]

# V4 auto-stopped when NKTouch became active. V5 only consumes the daemon result;
# simply returning to the app while recording must leave the recorder running.
active_start = s.find('- (void)nkRecorderDidBecomeActive:(NSNotification*)n{')
active_end = s.find('- (void)checkHardwareCompletion{', active_start)
if active_start < 0 or active_end < 0:
    raise SystemExit('V4 foreground method marker missing')
s = s[:active_start] + '- (void)nkRecorderDidBecomeActive:(NSNotification*)n{(void)n;self.leftAppWhileRecording=NO;[self checkHardwareCompletion];[self refreshStatus];}\n' + s[active_end:]

# Polling also consumes a completion when Volume Down is held while Recorder is
# already on screen (no foreground transition occurs in that case).
refresh_old = '- (void)refreshStatus{if(self.smartFinishing)return;'
refresh_new = '- (void)refreshStatus{[self checkHardwareCompletion];if(self.smartFinishing)return;'
if refresh_old not in s:
    raise SystemExit('V4 refreshStatus marker missing')
s = s.replace(refresh_old, refresh_new, 1)

s = s.replace('NKTouch 0.7.5.4', 'NKTouch 0.7.5.5')
s = s.replace('nkLabel:@"0.7.5.4"', 'nkLabel:@"0.7.5.5"')
s = s.replace('text:@"0.7.5.4"', 'text:@"0.7.5.5"')
settings.write_text(s)

print('Applied NKTouch 0.7.5.5 Recorder V5 AutoTouch-style Volume Down hold trigger')
