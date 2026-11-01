// NKTouch Lua process shim for jailbroken iOS.
// SPDX-License-Identifier: GPL-3.0-or-later
#define _POSIX_C_SOURCE 200809L
#include "lua-ios-shim.h"

#include <errno.h>
#include <spawn.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

extern char **environ;

struct nk_child {
    FILE *stream;
    pid_t pid;
    struct nk_child *next;
};

static struct nk_child *g_children = NULL;

static const char *nk_shell(void) {
    if (access("/var/jb/bin/sh", X_OK) == 0) return "/var/jb/bin/sh";
    return "/bin/sh";
}

static int wait_child(pid_t pid) {
    int status = -1;
    pid_t r;
    do {
        r = waitpid(pid, &status, 0);
    } while (r < 0 && errno == EINTR);
    return r < 0 ? -1 : status;
}

int nktouch_lua_system(const char *cmd) {
    const char *shell = nk_shell();
    if (!cmd) return access(shell, X_OK) == 0 ? 1 : 0;

    char *const argv[] = {(char *)shell, (char *)"-c", (char *)cmd, NULL};
    pid_t pid = -1;
    int rc = posix_spawn(&pid, shell, NULL, NULL, argv, environ);
    if (rc != 0) {
        errno = rc;
        return -1;
    }
    return wait_child(pid);
}

FILE *nktouch_lua_popen(void *lua_state, const char *cmd, const char *mode) {
    (void)lua_state;
    if (!cmd || !mode || (mode[0] != 'r' && mode[0] != 'w')) {
        errno = EINVAL;
        return NULL;
    }

    int fds[2];
    if (pipe(fds) != 0) return NULL;

    posix_spawn_file_actions_t actions;
    int rc = posix_spawn_file_actions_init(&actions);
    if (rc != 0) {
        close(fds[0]); close(fds[1]); errno = rc; return NULL;
    }

    int parent_fd = -1;
    if (mode[0] == 'r') {
        rc = posix_spawn_file_actions_adddup2(&actions, fds[1], STDOUT_FILENO);
        if (rc == 0) rc = posix_spawn_file_actions_addclose(&actions, fds[0]);
        if (rc == 0) rc = posix_spawn_file_actions_addclose(&actions, fds[1]);
        parent_fd = fds[0];
    } else {
        rc = posix_spawn_file_actions_adddup2(&actions, fds[0], STDIN_FILENO);
        if (rc == 0) rc = posix_spawn_file_actions_addclose(&actions, fds[0]);
        if (rc == 0) rc = posix_spawn_file_actions_addclose(&actions, fds[1]);
        parent_fd = fds[1];
    }

    if (rc != 0) {
        posix_spawn_file_actions_destroy(&actions);
        close(fds[0]); close(fds[1]); errno = rc; return NULL;
    }

    const char *shell = nk_shell();
    char *const argv[] = {(char *)shell, (char *)"-c", (char *)cmd, NULL};
    pid_t pid = -1;
    rc = posix_spawn(&pid, shell, &actions, NULL, argv, environ);
    posix_spawn_file_actions_destroy(&actions);

    if (mode[0] == 'r') close(fds[1]); else close(fds[0]);
    if (rc != 0) {
        close(parent_fd);
        errno = rc;
        return NULL;
    }

    FILE *stream = fdopen(parent_fd, mode[0] == 'r' ? "r" : "w");
    if (!stream) {
        close(parent_fd);
        (void)wait_child(pid);
        return NULL;
    }

    struct nk_child *node = (struct nk_child *)malloc(sizeof(*node));
    if (!node) {
        fclose(stream);
        (void)wait_child(pid);
        errno = ENOMEM;
        return NULL;
    }
    node->stream = stream;
    node->pid = pid;
    node->next = g_children;
    g_children = node;
    return stream;
}

int nktouch_lua_pclose(void *lua_state, FILE *stream) {
    (void)lua_state;
    if (!stream) { errno = EINVAL; return -1; }

    struct nk_child **pp = &g_children;
    struct nk_child *node = NULL;
    while (*pp) {
        if ((*pp)->stream == stream) {
            node = *pp;
            *pp = node->next;
            break;
        }
        pp = &(*pp)->next;
    }

    int close_rc = fclose(stream);
    if (!node) return close_rc == 0 ? 0 : -1;

    pid_t pid = node->pid;
    free(node);
    int status = wait_child(pid);
    if (close_rc != 0 && status == 0) return -1;
    return status;
}
