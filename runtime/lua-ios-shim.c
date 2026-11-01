// iOS-safe replacement for Lua's default system() backend.
// Jailbroken/rootless iOS still supports posix_spawn, while the public iOS SDK
// marks system() unavailable at compile time.

#include "lua-ios-shim.h"

#include <errno.h>
#include <spawn.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

extern char **environ;

static const char *nk_shell_path(void) {
    if (access("/var/jb/bin/sh", X_OK) == 0) return "/var/jb/bin/sh";
    if (access("/bin/sh", X_OK) == 0) return "/bin/sh";
    return NULL;
}

int nk_lua_system(const char *command) {
    const char *shell = nk_shell_path();
    if (command == NULL) return shell != NULL;
    if (shell == NULL) {
        errno = ENOENT;
        return -1;
    }

    pid_t pid = 0;
    char *const argv[] = {
        (char *)shell,
        (char *)"-c",
        (char *)command,
        NULL,
    };

    int spawn_rc = posix_spawn(&pid, shell, NULL, NULL, argv, environ);
    if (spawn_rc != 0) {
        errno = spawn_rc;
        return -1;
    }

    int status = 0;
    for (;;) {
        pid_t rc = waitpid(pid, &status, 0);
        if (rc == pid) return status;
        if (rc < 0 && errno == EINTR) continue;
        return -1;
    }
}
