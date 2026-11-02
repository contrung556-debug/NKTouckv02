#!/usr/bin/env python3
from pathlib import Path
import re
import sys

if len(sys.argv) != 2:
    raise SystemExit('usage: apply-v07532-recorder-spawn-fix.py <upstream-dir>')

root = Path(sys.argv[1])
settings = root / 'zxtouch/zxtouch/Settings/SettingsPageViewController.m'
if not settings.exists():
    raise SystemExit('missing prepared SettingsPageViewController.m')

s = settings.read_text()
start = s.find('static NSString *NKRecorderV3Run(NSArray<NSString *> *arguments, int *exitCode) {')
end = s.find('\n}\n\nstatic NSArray<NSDictionary*> *NKRecorderV3ParseTimeline', start)
if start < 0 or end < 0:
    raise SystemExit('Recorder V3 runner block not found')
end += 2

new_runner = r'''static NSString *NKRecorderV3Run(NSArray<NSString *> *arguments, int *exitCode) {
    NSArray<NSString *> *args = arguments ?: @[];
    NSArray<NSString *> *shellCandidates=@[@"/var/jb/bin/sh",@"/var/jb/usr/bin/sh",@"/bin/sh"];
    NSString *shell=nil;
    for(NSString *candidate in shellCandidates){if([[NSFileManager defaultManager]isExecutableFileAtPath:candidate]){shell=candidate;break;}}
    if(!shell){if(exitCode)*exitCode=127;return @"Không tìm thấy shell để chạy Recorder.";}
    int p[2] = {-1,-1};
    if (pipe(p) != 0) { if(exitCode)*exitCode=126; return @"Không tạo được pipe Recorder."; }
    posix_spawn_file_actions_t a; posix_spawn_file_actions_init(&a);
    posix_spawn_file_actions_adddup2(&a,p[1],STDOUT_FILENO);
    posix_spawn_file_actions_adddup2(&a,p[1],STDERR_FILENO);
    posix_spawn_file_actions_addclose(&a,p[0]); posix_spawn_file_actions_addclose(&a,p[1]);
    char **argv=calloc(args.count+3,sizeof(char*));
    argv[0]=strdup(shell.UTF8String);
    argv[1]=strdup(NKRecorderV3Tool.UTF8String);
    for(NSUInteger i=0;i<args.count;i++)argv[i+2]=strdup(args[i].UTF8String);
    argv[args.count+2]=NULL;
    pid_t pid=0;int spawn=posix_spawn(&pid,shell.UTF8String,&a,NULL,argv,environ);
    posix_spawn_file_actions_destroy(&a);close(p[1]);for(NSUInteger i=0;i<args.count+2;i++)free(argv[i]);free(argv);
    if(spawn!=0){close(p[0]);if(exitCode)*exitCode=spawn;return[NSString stringWithFormat:@"Không chạy được shell Recorder (%d).",spawn];}
    NSMutableData *data=[NSMutableData data];uint8_t buf[4096];ssize_t n=0;
    while((n=read(p[0],buf,sizeof(buf)))>0){[data appendBytes:buf length:(NSUInteger)n];if(data.length>524288)break;}close(p[0]);
    int status=0;waitpid(pid,&status,0);int code=WIFEXITED(status)?WEXITSTATUS(status):125;if(exitCode)*exitCode=code;
    NSString *text=[[NSString alloc]initWithData:data encoding:NSUTF8StringEncoding];return text.length?text:(code==0?@"OK":[NSString stringWithFormat:@"Recorder lỗi (%d).",code]);
}'''

s = s[:start] + new_runner + s[end:]
marker = '// V0.7.5.3.2 Recorder spawn fix: execute nkrecorder through an available trusted shell.\n'
anchor = '// V0.7.5.3.1 Recorder hotfix: rootless shell path + visible runtime diagnostics.\n'
if marker not in s:
    s = s.replace(anchor, anchor + marker, 1) if anchor in s else marker + s
s = s.replace('NKTouch 0.7.5.3.1', 'NKTouch 0.7.5.3.2')
s = s.replace('nkLabel:@"0.7.5.3.1"', 'nkLabel:@"0.7.5.3.2"')
s = s.replace('text:@"0.7.5.3.1"', 'text:@"0.7.5.3.2"')
settings.write_text(s)

print('Applied NKTouch v0.7.5.3.2 Recorder shell-spawn fix')
