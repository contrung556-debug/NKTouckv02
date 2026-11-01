// NKTouch v0.7.0 native task supervisor
// SPDX-License-Identifier: GPL-3.0-or-later
#ifndef _POSIX_C_SOURCE
#define _POSIX_C_SOURCE 200809L
#endif
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <signal.h>
#include <spawn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#define VERSION "0.7.0"
#define BASE "/var/mobile/Library/NKTouch"
#define TASKS BASE "/tasks"
#define ACTIVE TASKS "/active"
#define LUA "/var/jb/usr/bin/nktouch-lua"
#define LUAC "/var/jb/usr/libexec/nktouch/luac54"
#define ENGINE "/var/jb/usr/bin/nktask"
#define OVERLAY BASE "/status.state"
#define DEFAULT_TIMEOUT 0L
#define MAX_TIMEOUT 86400L
#define MAX_TAIL_BYTES (1024 * 1024)

extern char **environ;

typedef struct {
    char id[96];
    char state[32];
    char script[PATH_MAX];
    char log_path[PATH_MAX];
    pid_t child_pid;
    long started_at;
    long ended_at;
    long timeout_sec;
    int exit_code;
    int signal_no;
} task_state;

static long now_sec(void) { return (long)time(NULL); }
static void sleep_ms(long ms) {
    struct timespec t = { ms / 1000, (ms % 1000) * 1000000L };
    while (nanosleep(&t, &t) && errno == EINTR) {}
}
static int path_for(char *out, size_t cap, const char *id, const char *suffix) {
    int n = snprintf(out, cap, "%s/%s.%s", TASKS, id, suffix);
    return n > 0 && (size_t)n < cap ? 0 : -1;
}
static int safe_value(const char *s) {
    return s && *s && !strchr(s, '\n') && !strchr(s, '\r');
}
static int ensure_dirs(void) {
    if (mkdir(BASE, 0755) && errno != EEXIST) return -1;
    if (mkdir(TASKS, 0755) && errno != EEXIST) return -1;
    return 0;
}
static int alive(pid_t pid) {
    if (pid <= 1) return 0;
    if (kill(pid, 0) == 0) return 1;
    return errno == EPERM;
}
static void init_state(task_state *s) {
    memset(s, 0, sizeof(*s));
    snprintf(s->state, sizeof(s->state), "unknown");
    s->exit_code = -1;
}
static int terminal_state(const char *s) {
    return !strcmp(s, "success") || !strcmp(s, "failed") || !strcmp(s, "stopped") || !strcmp(s, "timeout");
}
static int write_atomic_text(const char *path, const char *text, mode_t mode) {
    char tmp[PATH_MAX];
    int n = snprintf(tmp, sizeof(tmp), "%s.tmp.%ld", path, (long)getpid());
    if (n <= 0 || (size_t)n >= sizeof(tmp)) return -1;
    int fd = open(tmp, O_WRONLY | O_CREAT | O_TRUNC, mode);
    if (fd < 0) return -1;
    size_t len = strlen(text), off = 0;
    while (off < len) {
        ssize_t w = write(fd, text + off, len - off);
        if (w < 0) { if (errno == EINTR) continue; close(fd); unlink(tmp); return -1; }
        off += (size_t)w;
    }
    if (fsync(fd)) { close(fd); unlink(tmp); return -1; }
    if (close(fd)) { unlink(tmp); return -1; }
    if (rename(tmp, path)) { unlink(tmp); return -1; }
    return 0;
}
static int save_state(const task_state *s) {
    char path[PATH_MAX], buf[PATH_MAX * 2 + 512];
    if (path_for(path, sizeof(path), s->id, "state")) return -1;
    int n = snprintf(buf, sizeof(buf),
        "id=%s\nstate=%s\nscript=%s\nlog=%s\nchild_pid=%ld\nstarted_at=%ld\nended_at=%ld\ntimeout_sec=%ld\nexit_code=%d\nsignal=%d\n",
        s->id, s->state, s->script, s->log_path, (long)s->child_pid,
        s->started_at, s->ended_at, s->timeout_sec, s->exit_code, s->signal_no);
    if (n <= 0 || (size_t)n >= sizeof(buf)) return -1;
    return write_atomic_text(path, buf, 0644);
}
static void set_string(char *dst, size_t cap, const char *src) {
    if (!src) src = "";
    snprintf(dst, cap, "%s", src);
}
static int load_state(const char *id, task_state *s) {
    char path[PATH_MAX], line[PATH_MAX + 128];
    if (!safe_value(id) || path_for(path, sizeof(path), id, "state")) return -1;
    FILE *f = fopen(path, "r");
    if (!f) return -1;
    init_state(s);
    set_string(s->id, sizeof(s->id), id);
    while (fgets(line, sizeof(line), f)) {
        char *nl = strpbrk(line, "\r\n"); if (nl) *nl = 0;
        char *eq = strchr(line, '='); if (!eq) continue; *eq++ = 0;
        if (!strcmp(line, "state")) set_string(s->state, sizeof(s->state), eq);
        else if (!strcmp(line, "script")) set_string(s->script, sizeof(s->script), eq);
        else if (!strcmp(line, "log")) set_string(s->log_path, sizeof(s->log_path), eq);
        else if (!strcmp(line, "child_pid")) s->child_pid = (pid_t)strtol(eq, NULL, 10);
        else if (!strcmp(line, "started_at")) s->started_at = strtol(eq, NULL, 10);
        else if (!strcmp(line, "ended_at")) s->ended_at = strtol(eq, NULL, 10);
        else if (!strcmp(line, "timeout_sec")) s->timeout_sec = strtol(eq, NULL, 10);
        else if (!strcmp(line, "exit_code")) s->exit_code = (int)strtol(eq, NULL, 10);
        else if (!strcmp(line, "signal")) s->signal_no = (int)strtol(eq, NULL, 10);
    }
    fclose(f);
    return 0;
}
static int read_active(char *id, size_t cap) {
    FILE *f = fopen(ACTIVE, "r");
    if (!f) return -1;
    if (!fgets(id, (int)cap, f)) { fclose(f); return -1; }
    fclose(f);
    char *nl = strpbrk(id, "\r\n"); if (nl) *nl = 0;
    return safe_value(id) ? 0 : -1;
}
static void clear_active_if(const char *id) {
    char cur[96];
    if (!read_active(cur, sizeof(cur)) && !strcmp(cur, id)) unlink(ACTIVE);
}
static int active_is_live(void) {
    char id[96]; task_state s;
    if (read_active(id, sizeof(id))) return 0;
    if (load_state(id, &s)) return 1;
    if (terminal_state(s.state)) { unlink(ACTIVE); return 0; }
    if (s.child_pid > 1 && !alive(s.child_pid) && strcmp(s.state, "starting") == 0) return 1;
    if (s.child_pid > 1 && !alive(s.child_pid)) { unlink(ACTIVE); return 0; }
    return 1;
}
static int claim_active(const char *id) {
    if (active_is_live()) return -2;
    unlink(ACTIVE);
    int fd = open(ACTIVE, O_WRONLY | O_CREAT | O_EXCL, 0644);
    if (fd < 0) return -1;
    dprintf(fd, "%s\n", id);
    close(fd);
    return 0;
}
static void overlay(const char *style, int pct, const char *message) {
    char text[512], tmp[PATH_MAX];
    if (pct < 0) pct = 0; if (pct > 100) pct = 100;
    char clean[256]; size_t j = 0;
    for (size_t i = 0; message && message[i] && j + 1 < sizeof(clean); i++) {
        char c = message[i]; clean[j++] = (c == '\n' || c == '\r' || c == '|') ? ' ' : c;
    }
    clean[j] = 0;
    snprintf(text, sizeof(text), "%s|%d|%s|%ld\n", style, pct, clean, now_sec());
    snprintf(tmp, sizeof(tmp), "%s.tmp.%ld", OVERLAY, (long)getpid());
    if (!write_atomic_text(tmp, text, 0666)) { rename(tmp, OVERLAY); chmod(OVERLAY, 0666); }
}
static int syntax_check(const char *script) {
    pid_t pid; int st = 0;
    char *av[] = { (char *)LUAC, (char *)"-p", (char *)script, NULL };
    int rc = posix_spawn(&pid, LUAC, NULL, NULL, av, environ);
    if (rc) return -1;
    while (waitpid(pid, &st, 0) < 0) if (errno != EINTR) return -1;
    return WIFEXITED(st) && WEXITSTATUS(st) == 0 ? 0 : -1;
}
static int spawn_detached_worker(char *const av[], pid_t *pid_out) {
    posix_spawn_file_actions_t fa; posix_spawnattr_t attr;
    if (posix_spawn_file_actions_init(&fa)) return -1;
    posix_spawn_file_actions_addopen(&fa, STDIN_FILENO, "/dev/null", O_RDONLY, 0);
    posix_spawn_file_actions_addopen(&fa, STDOUT_FILENO, "/dev/null", O_WRONLY, 0);
    posix_spawn_file_actions_addopen(&fa, STDERR_FILENO, "/dev/null", O_WRONLY, 0);
    if (posix_spawnattr_init(&attr)) { posix_spawn_file_actions_destroy(&fa); return -1; }
#ifdef POSIX_SPAWN_SETPGROUP
    short flags = POSIX_SPAWN_SETPGROUP;
    posix_spawnattr_setflags(&attr, flags);
    posix_spawnattr_setpgroup(&attr, 0);
#endif
    pid_t pid = 0;
    int rc = posix_spawn(&pid, ENGINE, &fa, &attr, av, environ);
    posix_spawnattr_destroy(&attr); posix_spawn_file_actions_destroy(&fa);
    if (rc) { errno = rc; return -1; }
    if (pid_out) *pid_out = pid;
    return 0;
}
static int parse_timeout(const char *s, long *out) {
    char *e = NULL; errno = 0; long v = strtol(s, &e, 10);
    if (errno || !e || *e || v < 0 || v > MAX_TIMEOUT) return -1;
    *out = v; return 0;
}
static int cmd_start(int ac, char **av) {
    if (ac < 1) { fprintf(stderr, "Usage: nktask start <script.lua> [--timeout SEC] [-- args...]\n"); return 2; }
    const char *script = av[0];
    if (!safe_value(script)) return 2;
    struct stat st;
    if (stat(script, &st) || !S_ISREG(st.st_mode) || access(script, R_OK)) {
        fprintf(stderr, "NKTask: script not readable: %s\n", script); return 2;
    }
    long timeout = DEFAULT_TIMEOUT; int argi = 1;
    if (argi + 1 < ac && !strcmp(av[argi], "--timeout")) {
        if (parse_timeout(av[argi + 1], &timeout)) { fprintf(stderr, "NKTask: timeout must be 0-%ld seconds\n", MAX_TIMEOUT); return 2; }
        argi += 2;
    }
    if (argi < ac && !strcmp(av[argi], "--")) argi++;
    if (syntax_check(script)) { fprintf(stderr, "NKTask: Lua syntax check failed\n"); return 3; }
    if (ensure_dirs()) { perror("NKTask mkdir"); return 4; }
    char id[96]; snprintf(id, sizeof(id), "T%ld-%ld", now_sec(), (long)getpid());
    int claim = claim_active(id);
    if (claim == -2) { char cur[96] = "unknown"; (void)read_active(cur, sizeof(cur)); fprintf(stderr, "NKTask: another task is active: %s\n", cur); return 8; }
    if (claim) { perror("NKTask active"); return 4; }
    task_state s; init_state(&s);
    set_string(s.id, sizeof(s.id), id); set_string(s.state, sizeof(s.state), "starting");
    set_string(s.script, sizeof(s.script), script); s.started_at = now_sec(); s.timeout_sec = timeout;
    if (path_for(s.log_path, sizeof(s.log_path), id, "log") || save_state(&s)) { clear_active_if(id); return 4; }
    char timeout_s[32]; snprintf(timeout_s, sizeof(timeout_s), "%ld", timeout);
    int extra = ac - argi;
    char **wav = calloc((size_t)extra + 6, sizeof(char *));
    if (!wav) { clear_active_if(id); return 4; }
    int k = 0; wav[k++] = (char *)ENGINE; wav[k++] = (char *)"--worker"; wav[k++] = id; wav[k++] = timeout_s; wav[k++] = (char *)script;
    for (int i = argi; i < ac; i++) wav[k++] = av[i]; wav[k] = NULL;
    pid_t wp = 0;
    int rc = spawn_detached_worker(wav, &wp); free(wav);
    if (rc) { set_string(s.state, sizeof(s.state), "failed"); s.ended_at = now_sec(); s.exit_code = 127; save_state(&s); clear_active_if(id); perror("NKTask worker"); return 5; }
    printf("task_id=%s\nstate=starting\nworker_pid=%ld\nlog=%s\n", id, (long)wp, s.log_path);
    overlay("normal", 0, "NKTouch task starting");
    return 0;
}
static int spawn_lua(task_state *s, int ac, char **av, pid_t *pid_out) {
    int fd = open(s->log_path, O_WRONLY | O_CREAT | O_TRUNC, 0666);
    if (fd < 0) return -1;
    dprintf(fd, "[NKTask] id=%s runtime=%s script=%s started=%ld\n", s->id, VERSION, s->script, s->started_at);
    posix_spawn_file_actions_t fa; posix_spawnattr_t attr;
    if (posix_spawn_file_actions_init(&fa)) { close(fd); return -1; }
    posix_spawn_file_actions_addopen(&fa, STDIN_FILENO, "/dev/null", O_RDONLY, 0);
    posix_spawn_file_actions_adddup2(&fa, fd, STDOUT_FILENO);
    posix_spawn_file_actions_adddup2(&fa, fd, STDERR_FILENO);
    posix_spawn_file_actions_addclose(&fa, fd);
    if (posix_spawnattr_init(&attr)) { posix_spawn_file_actions_destroy(&fa); close(fd); return -1; }
#ifdef POSIX_SPAWN_SETPGROUP
    short flags = POSIX_SPAWN_SETPGROUP;
    posix_spawnattr_setflags(&attr, flags); posix_spawnattr_setpgroup(&attr, 0);
#endif
    char **lav = calloc((size_t)ac + 2, sizeof(char *));
    if (!lav) { posix_spawnattr_destroy(&attr); posix_spawn_file_actions_destroy(&fa); close(fd); return -1; }
    lav[0] = (char *)LUA; for (int i = 0; i < ac; i++) lav[i + 1] = av[i]; lav[ac + 1] = NULL;
    setenv("NKTOUCH_TASK_ID", s->id, 1); setenv("NKTOUCH_TASK_LOG", s->log_path, 1); setenv("NKTOUCH_TASK_HOME", TASKS, 1);
    pid_t pid = 0; int rc = posix_spawn(&pid, LUA, &fa, &attr, lav, environ);
    free(lav); posix_spawnattr_destroy(&attr); posix_spawn_file_actions_destroy(&fa); close(fd);
    if (rc) { errno = rc; return -1; }
    *pid_out = pid; return 0;
}
static int cmd_worker(int ac, char **av) {
    if (ac < 3) return 2;
    const char *id = av[0]; long timeout = 0;
    if (!safe_value(id) || parse_timeout(av[1], &timeout)) return 2;
    task_state s; init_state(&s); set_string(s.id, sizeof(s.id), id); set_string(s.script, sizeof(s.script), av[2]);
    s.started_at = now_sec(); s.timeout_sec = timeout; path_for(s.log_path, sizeof(s.log_path), id, "log");
    pid_t child = 0;
    if (spawn_lua(&s, ac - 2, av + 2, &child)) {
        set_string(s.state, sizeof(s.state), "failed"); s.ended_at = now_sec(); s.exit_code = 127; save_state(&s); clear_active_if(id); overlay("error", 0, "Task failed to start"); return 5;
    }
    s.child_pid = child; set_string(s.state, sizeof(s.state), "running"); save_state(&s); overlay("normal", 0, "NKTouch task running");
    long deadline = timeout > 0 ? s.started_at + timeout : 0, paused_at = 0; int timed_out = 0; int st = 0;
    for (;;) {
        pid_t r = waitpid(child, &st, WNOHANG);
        if (r == child) break;
        if (r < 0 && errno != EINTR) { st = 0; break; }
        task_state cur;
        if (!load_state(id, &cur)) {
            if (!strcmp(cur.state, "paused")) { if (!paused_at) paused_at = now_sec(); }
            else if (paused_at) { if (deadline) deadline += now_sec() - paused_at; paused_at = 0; }
        }
        if (deadline && !paused_at && now_sec() >= deadline) {
            timed_out = 1; kill(child, SIGTERM); sleep_ms(800); if (alive(child)) kill(child, SIGKILL);
        }
        sleep_ms(100);
    }
    s.ended_at = now_sec(); s.child_pid = 0;
    task_state cur; int stopping = (!load_state(id, &cur) && !strcmp(cur.state, "stopping"));
    if (timed_out) { set_string(s.state, sizeof(s.state), "timeout"); s.exit_code = 124; }
    else if (stopping) { set_string(s.state, sizeof(s.state), "stopped"); s.exit_code = 143; }
    else if (WIFEXITED(st)) { s.exit_code = WEXITSTATUS(st); set_string(s.state, sizeof(s.state), s.exit_code == 0 ? "success" : "failed"); }
    else if (WIFSIGNALED(st)) { s.signal_no = WTERMSIG(st); s.exit_code = 128 + s.signal_no; set_string(s.state, sizeof(s.state), "failed"); }
    else { s.exit_code = 1; set_string(s.state, sizeof(s.state), "failed"); }
    save_state(&s); clear_active_if(id);
    if (!strcmp(s.state, "success")) overlay("success", 100, "NKTouch task completed");
    else if (!strcmp(s.state, "stopped")) overlay("warning", 0, "NKTouch task stopped");
    else if (!strcmp(s.state, "timeout")) overlay("warning", 0, "NKTouch task timed out");
    else overlay("error", 0, "NKTouch task failed");
    return 0;
}
static int resolve_id(const char *arg, char *id, size_t cap) {
    if (arg && *arg) { if (!safe_value(arg)) return -1; snprintf(id, cap, "%s", arg); return 0; }
    return read_active(id, cap);
}
static int print_state(const task_state *s) {
    printf("id=%s\nstate=%s\nscript=%s\nlog=%s\nchild_pid=%ld\nstarted_at=%ld\nended_at=%ld\ntimeout_sec=%ld\nexit_code=%d\nsignal=%d\n",
        s->id, s->state, s->script, s->log_path, (long)s->child_pid, s->started_at, s->ended_at, s->timeout_sec, s->exit_code, s->signal_no);
    return 0;
}
static int cmd_status(const char *arg) {
    char id[96]; task_state s;
    if (resolve_id(arg, id, sizeof(id))) { puts("state=idle"); return 0; }
    if (load_state(id, &s)) { fprintf(stderr, "NKTask: unknown task: %s\n", id); return 6; }
    if (!terminal_state(s.state) && s.child_pid > 1 && !alive(s.child_pid) && strcmp(s.state, "starting")) {
        set_string(s.state, sizeof(s.state), "failed"); s.ended_at = now_sec(); s.exit_code = 125; save_state(&s); clear_active_if(id);
    }
    return print_state(&s);
}
static int update_control(const char *arg, const char *want) {
    char id[96]; task_state s;
    if (resolve_id(arg, id, sizeof(id)) || load_state(id, &s)) { fprintf(stderr, "NKTask: no active/known task\n"); return 6; }
    if (s.child_pid <= 1 || !alive(s.child_pid)) { fprintf(stderr, "NKTask: task is not running\n"); return 7; }
    if (!strcmp(want, "pause")) {
        if (strcmp(s.state, "running")) { fprintf(stderr, "NKTask: pause requires running state\n"); return 7; }
        if (kill(s.child_pid, SIGSTOP)) { perror("NKTask pause"); return 5; }
        set_string(s.state, sizeof(s.state), "paused"); save_state(&s); overlay("warning", 0, "NKTouch task paused"); puts("state=paused"); return 0;
    }
    if (!strcmp(want, "resume")) {
        if (strcmp(s.state, "paused")) { fprintf(stderr, "NKTask: resume requires paused state\n"); return 7; }
        if (kill(s.child_pid, SIGCONT)) { perror("NKTask resume"); return 5; }
        set_string(s.state, sizeof(s.state), "running"); save_state(&s); overlay("normal", 0, "NKTouch task running"); puts("state=running"); return 0;
    }
    if (!strcmp(want, "stop")) {
        if (!strcmp(s.state, "paused")) (void)kill(s.child_pid, SIGCONT);
        set_string(s.state, sizeof(s.state), "stopping"); save_state(&s);
        if (kill(s.child_pid, SIGTERM) && errno != ESRCH) { perror("NKTask stop"); return 5; }
        for (int i = 0; i < 20 && alive(s.child_pid); i++) sleep_ms(100);
        if (alive(s.child_pid)) (void)kill(s.child_pid, SIGKILL);
        puts("state=stopping"); return 0;
    }
    return 2;
}
static int cmd_list(void) {
    DIR *d = opendir(TASKS); if (!d) { if (errno == ENOENT) return 0; perror("NKTask list"); return 4; }
    struct dirent *e; int count = 0;
    while ((e = readdir(d))) {
        size_t n = strlen(e->d_name); if (n <= 6 || strcmp(e->d_name + n - 6, ".state")) continue;
        char id[96]; size_t m = n - 6; if (m >= sizeof(id)) continue; memcpy(id, e->d_name, m); id[m] = 0;
        task_state s; if (!load_state(id, &s)) { printf("%s\t%s\t%s\n", s.id, s.state, s.script); count++; }
    }
    closedir(d); if (!count) puts("no_tasks"); return 0;
}
static int cmd_tail(const char *arg, long lines) {
    char id[96]; task_state s;
    if (resolve_id(arg, id, sizeof(id)) || load_state(id, &s)) { fprintf(stderr, "NKTask: no active/known task\n"); return 6; }
    if (lines < 1 || lines > 1000) return 2;
    FILE *f = fopen(s.log_path, "rb"); if (!f) { perror("NKTask log"); return 4; }
    if (fseek(f, 0, SEEK_END)) { fclose(f); return 4; }
    long size = ftell(f); if (size < 0) { fclose(f); return 4; }
    long start = size > MAX_TAIL_BYTES ? size - MAX_TAIL_BYTES : 0;
    if (fseek(f, start, SEEK_SET)) { fclose(f); return 4; }
    size_t len = (size_t)(size - start); char *buf = malloc(len + 1); if (!buf) { fclose(f); return 4; }
    len = fread(buf, 1, len, f); fclose(f); buf[len] = 0;
    size_t pos = len, seen = 0;
    while (pos > 0 && seen < (size_t)lines) { pos--; if (buf[pos] == '\n' && pos + 1 < len) seen++; }
    if (seen >= (size_t)lines && buf[pos] == '\n') pos++;
    fwrite(buf + pos, 1, len - pos, stdout); if (len && buf[len - 1] != '\n') putchar('\n'); free(buf); return 0;
}
static int cmd_doctor(void) {
    int fail = 0;
    printf("task_engine=%s\n", VERSION);
    if (!ensure_dirs() && access(TASKS, W_OK) == 0) puts("task_dir=writable"); else { puts("task_dir=failed"); fail = 1; }
    if (access(LUA, X_OK) == 0) puts("lua_runner=ok"); else { puts("lua_runner=missing"); fail = 1; }
    if (access(LUAC, X_OK) == 0) puts("lua_checker=ok"); else { puts("lua_checker=missing"); fail = 1; }
    char id[96]; if (!read_active(id, sizeof(id))) printf("active_task=%s\n", id); else puts("active_task=none");
    return fail;
}
static void usage(FILE *f) {
    fprintf(f,
        "NKTask v%s - NKTouch Lua task manager\n\n"
        "start <script.lua> [--timeout SEC] [-- args...]\n"
        "status [TASK_ID]\n"
        "pause [TASK_ID] | resume [TASK_ID] | stop [TASK_ID]\n"
        "list\n"
        "logs [TASK_ID] [LINES]\n"
        "doctor | version\n\n"
        "Only one screen-control task may be active at a time. History is retained per task.\n", VERSION);
}
int main(int argc, char **argv) {
    signal(SIGPIPE, SIG_IGN);
    if (ensure_dirs()) { perror("NKTask init"); return 4; }
    if (argc >= 2 && !strcmp(argv[1], "--worker")) return cmd_worker(argc - 2, argv + 2);
    if (argc < 2) { usage(stderr); return 2; }
    const char *c = argv[1];
    if (!strcmp(c, "version")) { puts(VERSION); return 0; }
    if (!strcmp(c, "doctor")) return cmd_doctor();
    if (!strcmp(c, "start")) return cmd_start(argc - 2, argv + 2);
    if (!strcmp(c, "status")) return cmd_status(argc >= 3 ? argv[2] : NULL);
    if (!strcmp(c, "pause")) return update_control(argc >= 3 ? argv[2] : NULL, "pause");
    if (!strcmp(c, "resume")) return update_control(argc >= 3 ? argv[2] : NULL, "resume");
    if (!strcmp(c, "stop")) return update_control(argc >= 3 ? argv[2] : NULL, "stop");
    if (!strcmp(c, "list")) return cmd_list();
    if (!strcmp(c, "logs")) {
        long lines = 50; if (argc >= 4 && parse_timeout(argv[3], &lines)) return 2; if (lines > 1000) return 2;
        return cmd_tail(argc >= 3 ? argv[2] : NULL, lines);
    }
    if (!strcmp(c, "help") || !strcmp(c, "-h") || !strcmp(c, "--help")) { usage(stdout); return 0; }
    fprintf(stderr, "NKTask: unknown command: %s\n", c); usage(stderr); return 2;
}
