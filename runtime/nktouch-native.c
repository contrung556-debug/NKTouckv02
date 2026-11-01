// NKTouch v0.3 native control client
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Talks directly to the local ZXTouch SpringBoard service on 127.0.0.1:6000.
// Protocol is compatible with the upstream GPL ZXTouch task/socket format.

#include <arpa/inet.h>
#include <errno.h>
#include <math.h>
#include <netinet/in.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <time.h>
#include <unistd.h>

#define NK_HOST "127.0.0.1"
#define NK_PORT 6000
#define NK_VERSION "0.3.0"
#define NK_FINGER 1
#define NK_RECV_TIMEOUT_SEC 2

#define TASK_TOUCH 10
#define TASK_OPEN_APP 11
#define TASK_RECORD_START 14
#define TASK_RECORD_STOP 15
#define TASK_FORCE_STOP 20

#define TOUCH_UP 0
#define TOUCH_DOWN 1
#define TOUCH_MOVE 2

static void usage(FILE *out) {
    fprintf(out,
        "NKTouch native v%s\n"
        "Usage:\n"
        "  nktouch-native ping\n"
        "  nktouch-native tap <x> <y>\n"
        "  nktouch-native hold <x> <y> <ms>\n"
        "  nktouch-native swipe <x1> <y1> <x2> <y2> <ms>\n"
        "  nktouch-native openapp <bundle-id>\n"
        "  nktouch-native record start|stop\n"
        "  nktouch-native stop\n"
        "  nktouch-native version\n", NK_VERSION);
}

static void fail_errno(const char *what) {
    fprintf(stderr, "NKTouch native: %s: %s\n", what, strerror(errno));
}

static int parse_double(const char *s, const char *name, double *out) {
    char *end = NULL;
    errno = 0;
    double v = strtod(s, &end);
    if (errno || !end || *end != '\0' || !isfinite(v)) {
        fprintf(stderr, "NKTouch native: invalid %s: %s\n", name, s);
        return -1;
    }
    *out = v;
    return 0;
}

static int parse_ms(const char *s, int *out) {
    char *end = NULL;
    errno = 0;
    long v = strtol(s, &end, 10);
    if (errno || !end || *end != '\0' || v < 0 || v > 300000) {
        fprintf(stderr, "NKTouch native: invalid ms: %s (0..300000)\n", s);
        return -1;
    }
    *out = (int)v;
    return 0;
}

static int scale_coord(double v, const char *name, int *scaled) {
    if (v < 0.0 || v > 9999.9) {
        fprintf(stderr, "NKTouch native: %s out of protocol range: %.3f\n", name, v);
        return -1;
    }
    long n = lround(v * 10.0);
    if (n < 0 || n > 99999) {
        fprintf(stderr, "NKTouch native: %s cannot be encoded: %.3f\n", name, v);
        return -1;
    }
    *scaled = (int)n;
    return 0;
}

static int connect_core(void) {
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) {
        fail_errno("socket");
        return -1;
    }

#ifdef SO_NOSIGPIPE
    int one = 1;
    (void)setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof(one));
#endif

    struct timeval tv;
    tv.tv_sec = NK_RECV_TIMEOUT_SEC;
    tv.tv_usec = 0;
    (void)setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
    (void)setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons(NK_PORT);
    if (inet_pton(AF_INET, NK_HOST, &addr.sin_addr) != 1) {
        fprintf(stderr, "NKTouch native: invalid core address\n");
        close(fd);
        return -1;
    }

    if (connect(fd, (struct sockaddr *)&addr, sizeof(addr)) != 0) {
        fprintf(stderr, "NKTouch native: cannot connect to %s:%d: %s\n",
                NK_HOST, NK_PORT, strerror(errno));
        close(fd);
        return -1;
    }
    return fd;
}

static int send_all(int fd, const char *buf, size_t len) {
    size_t sent = 0;
    while (sent < len) {
        ssize_t n = send(fd, buf + sent, len - sent, 0);
        if (n < 0) {
            if (errno == EINTR) continue;
            fail_errno("send");
            return -1;
        }
        if (n == 0) {
            fprintf(stderr, "NKTouch native: socket closed while sending\n");
            return -1;
        }
        sent += (size_t)n;
    }
    return 0;
}

static int recv_line(int fd, char *buf, size_t cap) {
    if (cap < 2) return -1;
    size_t used = 0;
    while (used + 1 < cap) {
        ssize_t n = recv(fd, buf + used, 1, 0);
        if (n < 0) {
            if (errno == EINTR) continue;
            fprintf(stderr, "NKTouch native: core response timeout/error: %s\n", strerror(errno));
            return -1;
        }
        if (n == 0) break;
        if (buf[used++] == '\n') break;
    }
    buf[used] = '\0';
    return used ? 0 : -1;
}

static int send_task_wait(int fd, int task, const char *payload) {
    char packet[1024];
    int n = snprintf(packet, sizeof(packet), "%02d%s\r\n", task, payload ? payload : "");
    if (n <= 0 || (size_t)n >= sizeof(packet)) {
        fprintf(stderr, "NKTouch native: task payload too long\n");
        return -1;
    }
    if (send_all(fd, packet, (size_t)n) != 0) return -1;

    char response[1024];
    if (recv_line(fd, response, sizeof(response)) != 0) return -1;
    if (response[0] != '0') {
        fprintf(stderr, "NKTouch native: core rejected task %02d: %s", task, response);
        if (!strchr(response, '\n')) fputc('\n', stderr);
        return -1;
    }
    return 0;
}

static int send_touch(int fd, int type, int finger, double x, double y) {
    if (type < TOUCH_UP || type > TOUCH_MOVE || finger < 0 || finger > 19) {
        fprintf(stderr, "NKTouch native: invalid touch event\n");
        return -1;
    }

    int sx = 0, sy = 0;
    if (scale_coord(x, "x", &sx) != 0 || scale_coord(y, "y", &sy) != 0) return -1;

    // Upstream format:
    // task(2) + count(1) + type(1) + finger(2) + x*10(5) + y*10(5) + CRLF
    char packet[64];
    int n = snprintf(packet, sizeof(packet), "101%d%02d%05d%05d\r\n",
                     type, finger, sx, sy);
    if (n <= 0 || (size_t)n >= sizeof(packet)) return -1;
    return send_all(fd, packet, (size_t)n);
}

static long long monotonic_us(void) {
    struct timespec ts;
    if (clock_gettime(CLOCK_MONOTONIC, &ts) != 0) return 0;
    return (long long)ts.tv_sec * 1000000LL + ts.tv_nsec / 1000LL;
}

static void sleep_us_safe(long long us) {
    if (us <= 0) return;
    struct timespec req;
    req.tv_sec = (time_t)(us / 1000000LL);
    req.tv_nsec = (long)((us % 1000000LL) * 1000LL);
    while (nanosleep(&req, &req) != 0 && errno == EINTR) {}
}

static void sleep_until_us(long long target) {
    long long now = monotonic_us();
    if (target > now) sleep_us_safe(target - now);
}

static int cmd_tap(int argc, char **argv) {
    if (argc != 2) return 2;
    double x, y;
    if (parse_double(argv[0], "x", &x) || parse_double(argv[1], "y", &y)) return 2;
    int fd = connect_core();
    if (fd < 0) return 4;
    int ok = send_touch(fd, TOUCH_DOWN, NK_FINGER, x, y);
    if (ok == 0) {
        sleep_us_safe(45000);
        ok = send_touch(fd, TOUCH_UP, NK_FINGER, x, y);
    }
    close(fd);
    if (ok != 0) return 5;
    puts("ok");
    return 0;
}

static int cmd_hold(int argc, char **argv) {
    if (argc != 3) return 2;
    double x, y;
    int ms;
    if (parse_double(argv[0], "x", &x) || parse_double(argv[1], "y", &y) || parse_ms(argv[2], &ms)) return 2;
    int fd = connect_core();
    if (fd < 0) return 4;
    int ok = send_touch(fd, TOUCH_DOWN, NK_FINGER, x, y);
    if (ok == 0) {
        sleep_us_safe((long long)ms * 1000LL);
        ok = send_touch(fd, TOUCH_UP, NK_FINGER, x, y);
    }
    close(fd);
    if (ok != 0) return 5;
    puts("ok");
    return 0;
}

static int cmd_swipe(int argc, char **argv) {
    if (argc != 5) return 2;
    double x1, y1, x2, y2;
    int ms;
    if (parse_double(argv[0], "x1", &x1) || parse_double(argv[1], "y1", &y1) ||
        parse_double(argv[2], "x2", &x2) || parse_double(argv[3], "y2", &y2) ||
        parse_ms(argv[4], &ms)) return 2;
    if (ms < 32) ms = 32;

    int fd = connect_core();
    if (fd < 0) return 4;
    if (send_touch(fd, TOUCH_DOWN, NK_FINGER, x1, y1) != 0) {
        close(fd);
        return 5;
    }

    int steps = ms / 16;
    if (steps < 2) steps = 2;
    if (steps > 120) steps = 120;
    long long start = monotonic_us();
    long long duration_us = (long long)ms * 1000LL;

    for (int i = 1; i < steps; ++i) {
        double t = (double)i / (double)steps;
        sleep_until_us(start + (duration_us * i) / steps);
        double x = x1 + (x2 - x1) * t;
        double y = y1 + (y2 - y1) * t;
        if (send_touch(fd, TOUCH_MOVE, NK_FINGER, x, y) != 0) {
            close(fd);
            return 5;
        }
    }

    sleep_until_us(start + duration_us);
    int ok = send_touch(fd, TOUCH_UP, NK_FINGER, x2, y2);
    close(fd);
    if (ok != 0) return 5;
    puts("ok");
    return 0;
}

static int cmd_simple_task(int task, const char *payload) {
    int fd = connect_core();
    if (fd < 0) return 4;
    int ok = send_task_wait(fd, task, payload);
    close(fd);
    if (ok != 0) return 5;
    puts("ok");
    return 0;
}

int main(int argc, char **argv) {
    signal(SIGPIPE, SIG_IGN);

    if (argc < 2) {
        usage(stderr);
        return 2;
    }

    const char *cmd = argv[1];
    if (strcmp(cmd, "version") == 0) {
        printf("%s\n", NK_VERSION);
        return 0;
    }
    if (strcmp(cmd, "ping") == 0) {
        int fd = connect_core();
        if (fd < 0) return 4;
        close(fd);
        puts("ok");
        return 0;
    }
    if (strcmp(cmd, "tap") == 0) {
        int rc = cmd_tap(argc - 2, argv + 2);
        if (rc == 2) fprintf(stderr, "Usage: nktouch-native tap <x> <y>\n");
        return rc;
    }
    if (strcmp(cmd, "hold") == 0) {
        int rc = cmd_hold(argc - 2, argv + 2);
        if (rc == 2) fprintf(stderr, "Usage: nktouch-native hold <x> <y> <ms>\n");
        return rc;
    }
    if (strcmp(cmd, "swipe") == 0) {
        int rc = cmd_swipe(argc - 2, argv + 2);
        if (rc == 2) fprintf(stderr, "Usage: nktouch-native swipe <x1> <y1> <x2> <y2> <ms>\n");
        return rc;
    }
    if (strcmp(cmd, "openapp") == 0) {
        if (argc != 3 || argv[2][0] == '\0' || strlen(argv[2]) > 500) {
            fprintf(stderr, "Usage: nktouch-native openapp <bundle-id>\n");
            return 2;
        }
        return cmd_simple_task(TASK_OPEN_APP, argv[2]);
    }
    if (strcmp(cmd, "record") == 0) {
        if (argc != 3) {
            fprintf(stderr, "Usage: nktouch-native record start|stop\n");
            return 2;
        }
        if (strcmp(argv[2], "start") == 0) return cmd_simple_task(TASK_RECORD_START, "");
        if (strcmp(argv[2], "stop") == 0) return cmd_simple_task(TASK_RECORD_STOP, "");
        fprintf(stderr, "Usage: nktouch-native record start|stop\n");
        return 2;
    }
    if (strcmp(cmd, "stop") == 0) {
        if (argc != 2) {
            fprintf(stderr, "Usage: nktouch-native stop\n");
            return 2;
        }
        return cmd_simple_task(TASK_FORCE_STOP, "");
    }

    usage(stderr);
    return 2;
}
