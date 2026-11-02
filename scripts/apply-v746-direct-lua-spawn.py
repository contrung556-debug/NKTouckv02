#!/usr/bin/env python3
from pathlib import Path
import sys

p = Path(sys.argv[1] if len(sys.argv) > 1 else "runtime/nktask.c")
s = p.read_text()

# Keep the proven V7.0 task-supervisor version contract intact. v0.7.4.6 is the
# package/app release; this patch only changes how that supervisor launches Lua.
replacements = [
    ('#define LUA "/var/jb/usr/bin/nktouch-lua"', '#define LUA "/var/jb/usr/libexec/nktouch/lua54"\n#define LUA_PATH_VALUE "/var/jb/usr/share/nktouch/lua/?.lua;/var/jb/usr/share/nktouch/lua/?/init.lua;;"\n#define LUA_BOOTSTRAP "local m=require(\\\"nktouch_v7\\\"); _G.nk=m; if type(m.installAutoTouchCompat)==\\\"function\\\" then m.installAutoTouchCompat() end"'),
    ('char **lav = calloc((size_t)ac + 2, sizeof(char *));', 'char **lav = calloc((size_t)ac + 4, sizeof(char *));'),
    ('lav[0] = (char *)LUA; for (int i = 0; i < ac; i++) lav[i + 1] = av[i]; lav[ac + 1] = NULL;', 'lav[0] = (char *)LUA; lav[1] = (char *)"-e"; lav[2] = (char *)LUA_BOOTSTRAP; for (int i = 0; i < ac; i++) lav[i + 3] = av[i]; lav[ac + 3] = NULL;'),
    ('setenv("NKTOUCH_TASK_ID", s->id, 1); setenv("NKTOUCH_TASK_LOG", s->log_path, 1); setenv("NKTOUCH_TASK_HOME", TASKS, 1);', 'setenv("LUA_PATH", LUA_PATH_VALUE, 1); setenv("NKTOUCH_TASK_ID", s->id, 1); setenv("NKTOUCH_TASK_LOG", s->log_path, 1); setenv("NKTOUCH_TASK_HOME", TASKS, 1);'),
    ('pid_t pid = 0; int rc = posix_spawn(&pid, LUA, &fa, &attr, lav, environ);\n    free(lav); posix_spawnattr_destroy(&attr); posix_spawn_file_actions_destroy(&fa); close(fd);\n    if (rc) { errno = rc; return -1; }', 'pid_t pid = 0; int rc = posix_spawn(&pid, LUA, &fa, &attr, lav, environ);\n    if (rc) dprintf(fd, "[NKTask] spawn_failed executable=%s errno=%d error=%s\\n", LUA, rc, strerror(rc));\n    free(lav); posix_spawnattr_destroy(&attr); posix_spawn_file_actions_destroy(&fa); close(fd);\n    if (rc) { errno = rc; return -1; }'),
]

for old, new in replacements:
    count = s.count(old)
    if count != 1:
        raise SystemExit(f"marker mismatch ({count}): {old[:100]}")
    s = s.replace(old, new, 1)

# Human-readable guard comment mirrors the escaped C string below, making the
# safety invariant obvious to reviewers and easy for CI to assert literally.
guard_comment = '// V7.4.6 bootstrap guard: type(m.installAutoTouchCompat)=="function"\n'
header = '// NKTouch v0.7.0 native task supervisor\n'
if guard_comment not in s:
    if header not in s:
        raise SystemExit('task supervisor header missing')
    s = s.replace(header, header + guard_comment, 1)

if '#define VERSION "0.7.0"' not in s:
    raise SystemExit('V7.0 task-supervisor version contract changed unexpectedly')
if '/var/jb/usr/bin/nktouch-lua' in s:
    raise SystemExit('shell wrapper path still present in task engine')
for marker in (
    '#define LUA "/var/jb/usr/libexec/nktouch/lua54"',
    'LUA_PATH_VALUE',
    'LUA_BOOTSTRAP',
    'type(m.installAutoTouchCompat)',
    'spawn_failed executable=',
):
    if marker not in s:
        raise SystemExit(f'missing post-patch marker: {marker}')

p.write_text(s)
print('Applied NKTouch v0.7.4.6 direct Lua spawn fix; V7.0 supervisor contract retained')
