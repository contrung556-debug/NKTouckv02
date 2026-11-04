// NKTouch v0.6.3 embedded Lua native bindings
// SPDX-License-Identifier: GPL-3.0-or-later
#ifndef _POSIX_C_SOURCE
#define _POSIX_C_SOURCE 200809L
#endif

#include "lua.h"
#include "lauxlib.h"

#include <arpa/inet.h>
#include <errno.h>
#include <math.h>
#include <netinet/in.h>
#include <signal.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <time.h>
#include <unistd.h>

#define NKCORE_VERSION "0.6.3"
#define NK_NATIVE_VERSION "0.6.0"
#define PORT 6000
#define FINGER 1
#define TASK_TOUCH 10
#define TASK_OPEN_APP 11
#define TASK_RECORD_START 14
#define TASK_RECORD_STOP 15
#define TASK_FORCE_STOP 20
#define TASK_TEMPLATE_MATCH 21
#define TASK_TOAST 22
#define TASK_COLOR_PICKER 23
#define TASK_TEXT 24
#define TASK_DEVICE 25
#define TASK_OCR 27
#define TASK_COLOR_SEARCH 28
#define TASK_SCREENSHOT 30
#define TOUCH_UP 0
#define TOUCH_DOWN 1
#define TOUCH_MOVE 2
#define MAX_TEXT 16384
#define MAX_SCREENSHOT_BYTES (50ULL * 1024ULL * 1024ULL)

static void set_err(char *err, size_t cap, const char *fmt, ...) {
    if (!err || !cap) return;
    va_list ap;
    va_start(ap, fmt);
    (void)vsnprintf(err, cap, fmt, ap);
    va_end(ap);
}

static int push_error(lua_State *L, const char *msg) {
    lua_pushnil(L);
    lua_pushstring(L, msg && *msg ? msg : "NKTouch native error");
    return 2;
}

static int validate_text_value(const char *s, char *err, size_t errcap) {
    size_t n = strlen(s);
    if (n > MAX_TEXT || strchr(s, '\r') || strchr(s, '\n') || strstr(s, ";;")) {
        set_err(err, errcap, "value must be <= %d bytes and cannot contain CR/LF or ';;'", MAX_TEXT);
        return -1;
    }
    return 0;
}

static int connect_core(char *err, size_t errcap) {
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) {
        set_err(err, errcap, "socket: %s", strerror(errno));
        return -1;
    }
#ifdef SO_NOSIGPIPE
    int one = 1;
    (void)setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof(one));
#endif
    struct timeval tv = {3, 0};
    (void)setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
    (void)setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));

    struct sockaddr_in a;
    memset(&a, 0, sizeof(a));
    a.sin_family = AF_INET;
    a.sin_port = htons(PORT);
    (void)inet_pton(AF_INET, "127.0.0.1", &a.sin_addr);
    if (connect(fd, (struct sockaddr *)&a, sizeof(a)) != 0) {
        set_err(err, errcap, "connect 127.0.0.1:%d: %s", PORT, strerror(errno));
        close(fd);
        return -1;
    }
    return fd;
}

static int send_all(int fd, const char *p, size_t n, char *err, size_t errcap) {
    while (n) {
        ssize_t w = send(fd, p, n, 0);
        if (w < 0) {
            if (errno == EINTR) continue;
            set_err(err, errcap, "send: %s", strerror(errno));
            return -1;
        }
        if (w == 0) {
            set_err(err, errcap, "send returned 0");
            return -1;
        }
        p += w;
        n -= (size_t)w;
    }
    return 0;
}

static int recv_line(int fd, char *buf, size_t cap, char *err, size_t errcap) {
    size_t i = 0;
    while (i + 1 < cap) {
        ssize_t r = recv(fd, buf + i, 1, 0);
        if (r < 0) {
            if (errno == EINTR) continue;
            set_err(err, errcap, "recv: %s", strerror(errno));
            return -1;
        }
        if (r == 0) break;
        if (buf[i++] == '\n') break;
    }
    buf[i] = 0;
    while (i && (buf[i - 1] == '\n' || buf[i - 1] == '\r')) buf[--i] = 0;
    if (!i) {
        set_err(err, errcap, "empty reply from core");
        return -1;
    }
    return 0;
}

static char *payload(char *r) {
    if (!strncmp(r, "0;;", 3)) return r + 3;
    return r[0] == '0' ? r + 1 : r;
}

static int request_task(int task, const char *body, char *reply, size_t replycap, char *err, size_t errcap) {
    int fd = connect_core(err, errcap);
    if (fd < 0) return -1;

    size_t len = strlen(body ? body : "");
    size_t cap = len + 16;
    char *packet = (char *)malloc(cap);
    if (!packet) {
        close(fd);
        set_err(err, errcap, "out of memory");
        return -1;
    }
    int n = snprintf(packet, cap, "%02d%s\r\n", task, body ? body : "");
    int rc = (n > 0 && (size_t)n < cap) ? send_all(fd, packet, (size_t)n, err, errcap) : -1;
    free(packet);
    if (!rc) rc = recv_line(fd, reply, replycap, err, errcap);
    close(fd);
    if (rc) return -1;
    if (reply[0] != '0') {
        set_err(err, errcap, "core error: %s", reply);
        return -1;
    }
    return 0;
}

static int action_task(lua_State *L, int task, const char *body) {
    char reply[4096], err[512] = {0};
    if (request_task(task, body, reply, sizeof(reply), err, sizeof(err))) return push_error(L, err);
    lua_pushboolean(L, 1);
    return 1;
}

static int query_task(lua_State *L, int task, const char *body) {
    char reply[32768], err[512] = {0};
    if (request_task(task, body, reply, sizeof(reply), err, sizeof(err))) return push_error(L, err);
    lua_pushstring(L, payload(reply));
    return 1;
}

static long long now_us(void) {
    struct timespec t;
    if (clock_gettime(CLOCK_MONOTONIC, &t)) return 0;
    return (long long)t.tv_sec * 1000000LL + t.tv_nsec / 1000LL;
}

static void sleep_us(long long us) {
    if (us <= 0) return;
    struct timespec t = {(time_t)(us / 1000000LL), (long)((us % 1000000LL) * 1000LL)};
    while (nanosleep(&t, &t) && errno == EINTR) {}
}

static int coord(double v, int *out) {
    if (!isfinite(v) || v < 0 || v > 9999.9) return -1;
    long n = lround(v * 10.0);
    if (n < 0 || n > 99999) return -1;
    *out = (int)n;
    return 0;
}

static int touch_packet(int fd, int type, double x, double y, char *err, size_t errcap) {
    int sx, sy;
    char p[64];
    if (coord(x, &sx) || coord(y, &sy)) {
        set_err(err, errcap, "coordinate out of range");
        return -1;
    }
    int n = snprintf(p, sizeof(p), "101%d%02d%05d%05d\r\n", type, FINGER, sx, sy);
    if (n <= 0 || (size_t)n >= sizeof(p)) {
        set_err(err, errcap, "touch packet overflow");
        return -1;
    }
    return send_all(fd, p, (size_t)n, err, errcap);
}

static int tap_point(double x, double y, long ms, char *err, size_t errcap) {
    int fd = connect_core(err, errcap);
    if (fd < 0) return -1;
    int rc = touch_packet(fd, TOUCH_DOWN, x, y, err, errcap);
    if (!rc) {
        sleep_us(ms * 1000LL);
        rc = touch_packet(fd, TOUCH_UP, x, y, err, errcap);
    }
    close(fd);
    return rc;
}

static int l_version(lua_State *L) {
    lua_pushliteral(L, NKCORE_VERSION);
    return 1;
}

static int l_native_version(lua_State *L) {
    lua_pushliteral(L, NK_NATIVE_VERSION);
    return 1;
}

static int l_now_ms(lua_State *L) {
    lua_pushinteger(L, (lua_Integer)(now_us() / 1000LL));
    return 1;
}

static int l_ping(lua_State *L) {
    char err[512] = {0};
    int fd = connect_core(err, sizeof(err));
    if (fd < 0) return push_error(L, err);
    close(fd);
    lua_pushboolean(L, 1);
    return 1;
}

static int l_sleep(lua_State *L) {
    lua_Integer ms = luaL_checkinteger(L, 1);
    luaL_argcheck(L, ms >= 0 && ms <= 300000, 1, "milliseconds out of range");
    sleep_us((long long)ms * 1000LL);
    lua_pushboolean(L, 1);
    return 1;
}

static int l_tap(lua_State *L) {
    double x = luaL_checknumber(L, 1);
    double y = luaL_checknumber(L, 2);
    lua_Integer ms = luaL_optinteger(L, 3, 45);
    luaL_argcheck(L, ms >= 0 && ms <= 300000, 3, "hold milliseconds out of range");
    char err[512] = {0};
    if (tap_point(x, y, (long)ms, err, sizeof(err))) return push_error(L, err);
    lua_pushboolean(L, 1);
    return 1;
}

// V6 path playback uses ONE continuous touch contact for every sampled point.
// The Lua argument is an array of {x=..., y=..., t=msSinceDown} points.
// No automatic retries: repeating a partially delivered gesture is unsafe.
typedef struct { double x, y; lua_Integer t; } NKPathPoint;
#define NK_PATH_MAX_POINTS 256

static int l_path(lua_State *L) {
    luaL_checktype(L, 1, LUA_TTABLE);
    size_t count = lua_rawlen(L, 1);
    luaL_argcheck(L, count >= 2 && count <= NK_PATH_MAX_POINTS, 1,
                  "path must contain 2..256 points");
    NKPathPoint points[NK_PATH_MAX_POINTS];
    lua_Integer last_t = -1;
    for (size_t i = 0; i < count; ++i) {
        lua_rawgeti(L, 1, (lua_Integer)i + 1);
        luaL_checktype(L, -1, LUA_TTABLE);
        lua_getfield(L, -1, "x");
        double x = luaL_checknumber(L, -1);
        lua_pop(L, 1);
        lua_getfield(L, -1, "y");
        double y = luaL_checknumber(L, -1);
        lua_pop(L, 1);
        lua_getfield(L, -1, "t");
        lua_Integer ms = luaL_checkinteger(L, -1);
        lua_pop(L, 2);
        int sx, sy;
        luaL_argcheck(L, coord(x, &sx) == 0 && coord(y, &sy) == 0, 1,
                      "path coordinates out of range");
        luaL_argcheck(L, ms >= 0 && ms <= 300000, 1,
                      "path time out of range");
        luaL_argcheck(L, (i == 0 && ms == 0) || (i > 0 && ms > last_t), 1,
                      "path timestamps must increase from zero");
        points[i].x = x;
        points[i].y = y;
        points[i].t = ms;
        last_t = ms;
    }

    char err[512] = {0};
    int fd = connect_core(err, sizeof(err));
    if (fd < 0) return push_error(L, err);
    if (touch_packet(fd, TOUCH_DOWN, points[0].x, points[0].y, err, sizeof(err))) {
        close(fd);
        return push_error(L, err);
    }
    double last_x = points[0].x, last_y = points[0].y;
    long long start = now_us();
    for (size_t i = 1; i < count; ++i) {
        long long wait = start + (long long)points[i].t * 1000LL - now_us();
        if (wait > 0) sleep_us(wait);
        // Send the final MOVE as well: lifting at a distant endpoint without
        // a MOVE can make a two-point path behave like a tap.
        if (touch_packet(fd, TOUCH_MOVE, points[i].x, points[i].y, err, sizeof(err))) {
            char release_err[128] = {0};
            (void)touch_packet(fd, TOUCH_UP, last_x, last_y, release_err, sizeof(release_err));
            close(fd);
            return push_error(L, err);
        }
        last_x = points[i].x; last_y = points[i].y;
    }
    if (touch_packet(fd, TOUCH_UP, last_x, last_y, err, sizeof(err))) {
        close(fd);
        return push_error(L, err);
    }
    close(fd);
    lua_pushboolean(L, 1);
    return 1;
}

static int l_swipe(lua_State *L) {
    double x1 = luaL_checknumber(L, 1), y1 = luaL_checknumber(L, 2);
    double x2 = luaL_checknumber(L, 3), y2 = luaL_checknumber(L, 4);
    lua_Integer ms = luaL_optinteger(L, 5, 400);
    luaL_argcheck(L, ms >= 32 && ms <= 300000, 5, "milliseconds out of range");

    char err[512] = {0};
    int fd = connect_core(err, sizeof(err));
    if (fd < 0) return push_error(L, err);
    if (touch_packet(fd, TOUCH_DOWN, x1, y1, err, sizeof(err))) {
        close(fd);
        return push_error(L, err);
    }
    int steps = (int)(ms / 16);
    if (steps < 2) steps = 2;
    if (steps > 120) steps = 120;
    long long start = now_us(), dur = (long long)ms * 1000LL;
    for (int i = 1; i < steps; i++) {
        long long target = start + (dur * i) / steps;
        long long wait = target - now_us();
        if (wait > 0) sleep_us(wait);
        double t = (double)i / (double)steps;
        if (touch_packet(fd, TOUCH_MOVE, x1 + (x2 - x1) * t, y1 + (y2 - y1) * t, err, sizeof(err))) {
            close(fd);
            return push_error(L, err);
        }
    }
    long long wait = start + dur - now_us();
    if (wait > 0) sleep_us(wait);
    if (touch_packet(fd, TOUCH_UP, x2, y2, err, sizeof(err))) {
        close(fd);
        return push_error(L, err);
    }
    close(fd);
    lua_pushboolean(L, 1);
    return 1;
}

static int l_open_app(lua_State *L) {
    const char *bundle = luaL_checkstring(L, 1);
    char err[512] = {0};
    if (!*bundle || strlen(bundle) > 500 || validate_text_value(bundle, err, sizeof(err))) return push_error(L, err[0] ? err : "invalid bundle id");
    return action_task(L, TASK_OPEN_APP, bundle);
}

static int l_stop(lua_State *L) {
    (void)L;
    return action_task(L, TASK_FORCE_STOP, "");
}

static int l_record_start(lua_State *L) {
    return action_task(L, TASK_RECORD_START, "");
}

static int l_record_stop(lua_State *L) {
    return action_task(L, TASK_RECORD_STOP, "");
}

static int text_action(lua_State *L, int sub, const char *text) {
    char err[512] = {0};
    if (validate_text_value(text, err, sizeof(err))) return push_error(L, err);
    size_t cap = strlen(text) + 32;
    char *body = (char *)malloc(cap);
    if (!body) return push_error(L, "out of memory");
    int n = snprintf(body, cap, "%d;;%s", sub, text);
    if (n <= 0 || (size_t)n >= cap) {
        free(body);
        return push_error(L, "text packet overflow");
    }
    int rc = action_task(L, TASK_TEXT, body);
    free(body);
    return rc;
}

static int l_text(lua_State *L) { return text_action(L, 1, luaL_checkstring(L, 1)); }
static int l_paste(lua_State *L) { return text_action(L, 5, luaL_checkstring(L, 1)); }
static int l_clipboard_set(lua_State *L) { return text_action(L, 7, luaL_checkstring(L, 1)); }

static int l_keyboard(lua_State *L) {
    int show = lua_toboolean(L, 1);
    return action_task(L, TASK_TEXT, show ? "2;;1" : "2;;0");
}

static int number_text_action(lua_State *L, int sub, lua_Integer lo, lua_Integer hi) {
    lua_Integer v = luaL_checkinteger(L, 1);
    luaL_argcheck(L, v >= lo && v <= hi, 1, "value out of range");
    char body[64];
    (void)snprintf(body, sizeof(body), "%d;;%lld", sub, (long long)v);
    return action_task(L, TASK_TEXT, body);
}

static int l_cursor(lua_State *L) { return number_text_action(L, 3, -100000, 100000); }
static int l_delete(lua_State *L) { return number_text_action(L, 4, 0, 100000); }
static int l_clipboard_get(lua_State *L) { return query_task(L, TASK_TEXT, "6"); }

static int l_device_query(lua_State *L, int sub) {
    char body[16];
    (void)snprintf(body, sizeof(body), "%d", sub);
    return query_task(L, TASK_DEVICE, body);
}

static int l_screen(lua_State *L) { return l_device_query(L, 1); }
static int l_orientation(lua_State *L) { return l_device_query(L, 2); }
static int l_scale(lua_State *L) { return l_device_query(L, 3); }
static int l_device(lua_State *L) { return l_device_query(L, 30); }
static int l_battery(lua_State *L) { return l_device_query(L, 31); }
static int l_runtime(lua_State *L) { return l_device_query(L, 32); }

static int l_foreground(lua_State *L) {
    char reply[4096], err[512] = {0};
    if (request_task(TASK_DEVICE, "32", reply, sizeof(reply), err, sizeof(err))) return push_error(L, err);
    char *p = payload(reply), *sep = strstr(p, ";;");
    if (sep) *sep = 0;
    lua_pushstring(L, p);
    return 1;
}

static int l_screenshot(lua_State *L) {
    const char *path = luaL_optstring(L, 1, "/var/mobile/Library/NKTouch/screenshot.jpg");
    if (!*path || strchr(path, '\r') || strchr(path, '\n')) return push_error(L, "invalid screenshot path");
    char err[512] = {0};
    int fd = connect_core(err, sizeof(err));
    if (fd < 0) return push_error(L, err);
    if (send_all(fd, "30\r\n", 4, err, sizeof(err))) {
        close(fd);
        return push_error(L, err);
    }
    char header[256];
    if (recv_line(fd, header, sizeof(header), err, sizeof(err))) {
        close(fd);
        return push_error(L, err);
    }
    if (header[0] != '0') {
        set_err(err, sizeof(err), "screenshot core error: %s", header);
        close(fd);
        return push_error(L, err);
    }
    unsigned long long bytes = 0;
    if (sscanf(header, "0;;image/jpeg;;%llu", &bytes) != 1 || bytes == 0 || bytes > MAX_SCREENSHOT_BYTES) {
        close(fd);
        return push_error(L, "invalid screenshot header");
    }
    FILE *f = fopen(path, "wb");
    if (!f) {
        set_err(err, sizeof(err), "cannot write %s: %s", path, strerror(errno));
        close(fd);
        return push_error(L, err);
    }
    unsigned char buf[16384];
    unsigned long long left = bytes;
    int failed = 0;
    while (left) {
        size_t want = left < sizeof(buf) ? (size_t)left : sizeof(buf);
        ssize_t n = recv(fd, buf, want, 0);
        if (n < 0) {
            if (errno == EINTR) continue;
            failed = 1;
            break;
        }
        if (!n || fwrite(buf, 1, (size_t)n, f) != (size_t)n) {
            failed = 1;
            break;
        }
        left -= (unsigned long long)n;
    }
    if (fclose(f) != 0) failed = 1;
    close(fd);
    if (failed) {
        unlink(path);
        return push_error(L, "incomplete screenshot");
    }
    lua_pushstring(L, path);
    return 1;
}

static void push_rect(lua_State *L, double x, double y, double w, double h) {
    lua_createtable(L, 0, 4);
    lua_pushnumber(L, x); lua_setfield(L, -2, "x");
    lua_pushnumber(L, y); lua_setfield(L, -2, "y");
    lua_pushnumber(L, w); lua_setfield(L, -2, "width");
    lua_pushnumber(L, h); lua_setfield(L, -2, "height");
}

static int l_find_image(lua_State *L) {
    const char *path = luaL_checkstring(L, 1);
    lua_Integer maxtry = luaL_optinteger(L, 2, 2);
    double confidence = luaL_optnumber(L, 3, 0.8);
    double scale = luaL_optnumber(L, 4, 0.8);
    luaL_argcheck(L, maxtry >= 0 && maxtry <= 8, 2, "maxTry out of range");
    luaL_argcheck(L, confidence > 0 && confidence <= 1, 3, "confidence out of range");
    luaL_argcheck(L, scale > 0.05 && scale < 1.0, 4, "scale out of range");
    char err[512] = {0};
    if (validate_text_value(path, err, sizeof(err))) return push_error(L, err);
    size_t cap = strlen(path) + 128;
    char *body = (char *)malloc(cap);
    if (!body) return push_error(L, "out of memory");
    int n = snprintf(body, cap, "%s;;%lld;;%.4f;;%.4f", path, (long long)maxtry, confidence, scale);
    if (n <= 0 || (size_t)n >= cap) {
        free(body);
        return push_error(L, "image packet overflow");
    }
    char reply[4096];
    int rc = request_task(TASK_TEMPLATE_MATCH, body, reply, sizeof(reply), err, sizeof(err));
    free(body);
    if (rc) return push_error(L, err);
    double x, y, w, h;
    if (sscanf(payload(reply), "%lf;;%lf;;%lf;;%lf", &x, &y, &w, &h) != 4) return push_error(L, "invalid image-match reply");
    push_rect(L, x, y, w, h);
    return 1;
}

static int l_get_color(lua_State *L) {
    lua_Integer x = luaL_checkinteger(L, 1), y = luaL_checkinteger(L, 2);
    luaL_argcheck(L, x >= 0 && x <= 10000, 1, "x out of range");
    luaL_argcheck(L, y >= 0 && y <= 10000, 2, "y out of range");
    char body[64], reply[256], err[512] = {0};
    (void)snprintf(body, sizeof(body), "%lld;;%lld", (long long)x, (long long)y);
    if (request_task(TASK_COLOR_PICKER, body, reply, sizeof(reply), err, sizeof(err))) return push_error(L, err);
    long r, g, b;
    if (sscanf(payload(reply), "%ld;;%ld;;%ld", &r, &g, &b) != 3) return push_error(L, "invalid color reply");
    lua_createtable(L, 0, 4);
    lua_pushinteger(L, r); lua_setfield(L, -2, "red");
    lua_pushinteger(L, g); lua_setfield(L, -2, "green");
    lua_pushinteger(L, b); lua_setfield(L, -2, "blue");
    lua_pushinteger(L, (lua_Integer)(r * 65536L + g * 256L + b)); lua_setfield(L, -2, "packed");
    return 1;
}

static int l_find_color(lua_State *L) {
    long v[11];
    for (int i = 0; i < 10; i++) v[i] = (long)luaL_checkinteger(L, i + 1);
    v[10] = (long)luaL_optinteger(L, 11, 0);
    luaL_argcheck(L, v[0] >= 0 && v[0] <= 10000, 1, "x out of range");
    luaL_argcheck(L, v[1] >= 0 && v[1] <= 10000, 2, "y out of range");
    luaL_argcheck(L, v[2] >= 0 && v[2] <= 10000, 3, "width out of range");
    luaL_argcheck(L, v[3] >= 0 && v[3] <= 10000, 4, "height out of range");
    for (int i = 4; i < 10; i++) luaL_argcheck(L, v[i] >= 0 && v[i] <= 255, i + 1, "color component out of range");
    luaL_argcheck(L, v[4] <= v[5] && v[6] <= v[7] && v[8] <= v[9], 5, "invalid min/max color range");
    luaL_argcheck(L, v[10] >= 0 && v[10] <= 1000, 11, "skip out of range");

    char body[256], reply[512], err[512] = {0};
    int n = snprintf(body, sizeof(body), "1;;%ld;;%ld;;%ld;;%ld;;%ld;;%ld;;%ld;;%ld;;%ld;;%ld;;%ld",
                     v[0], v[1], v[2], v[3], v[4], v[5], v[6], v[7], v[8], v[9], v[10]);
    if (n <= 0 || (size_t)n >= sizeof(body)) return push_error(L, "color packet overflow");
    if (request_task(TASK_COLOR_SEARCH, body, reply, sizeof(reply), err, sizeof(err))) return push_error(L, err);
    long x, y, r, g, b;
    if (sscanf(payload(reply), "%ld;;%ld;;%ld;;%ld;;%ld", &x, &y, &r, &g, &b) != 5 || x < 0 || y < 0)
        return push_error(L, "color not found");
    lua_createtable(L, 0, 6);
    lua_pushinteger(L, x); lua_setfield(L, -2, "x");
    lua_pushinteger(L, y); lua_setfield(L, -2, "y");
    lua_pushinteger(L, r); lua_setfield(L, -2, "red");
    lua_pushinteger(L, g); lua_setfield(L, -2, "green");
    lua_pushinteger(L, b); lua_setfield(L, -2, "blue");
    lua_pushinteger(L, (lua_Integer)(r * 65536L + g * 256L + b)); lua_setfield(L, -2, "packed");
    return 1;
}

static int l_ocr(lua_State *L) {
    double x = luaL_checknumber(L, 1), y = luaL_checknumber(L, 2);
    double w = luaL_checknumber(L, 3), h = luaL_checknumber(L, 4);
    const char *lang = luaL_optstring(L, 5, "");
    luaL_argcheck(L, x >= 0, 1, "x out of range");
    luaL_argcheck(L, y >= 0, 2, "y out of range");
    luaL_argcheck(L, w > 0, 3, "width must be > 0");
    luaL_argcheck(L, h > 0, 4, "height must be > 0");
    char err[512] = {0};
    if (validate_text_value(lang, err, sizeof(err))) return push_error(L, err);
    size_t cap = strlen(lang) + 192;
    char *body = (char *)malloc(cap);
    if (!body) return push_error(L, "out of memory");
    int n = snprintf(body, cap, "1;;%.2f,,%.2f,,%.2f,,%.2f;;;;0.03125;;0;;%s;;1;;", x, y, w, h, lang);
    if (n <= 0 || (size_t)n >= cap) {
        free(body);
        return push_error(L, "OCR packet overflow");
    }
    char reply[32768];
    int rc = request_task(TASK_OCR, body, reply, sizeof(reply), err, sizeof(err));
    free(body);
    if (rc) return push_error(L, err);
    lua_pushstring(L, payload(reply));
    return 1;
}

static int toast_type(const char *s) {
    if (!strcmp(s, "error") || !strcmp(s, "1")) return 1;
    if (!strcmp(s, "warning") || !strcmp(s, "warn") || !strcmp(s, "2")) return 2;
    if (!strcmp(s, "message") || !strcmp(s, "info") || !strcmp(s, "3")) return 3;
    if (!strcmp(s, "success") || !strcmp(s, "4")) return 4;
    return -1;
}

static int l_toast(lua_State *L) {
    const char *kind = luaL_checkstring(L, 1);
    lua_Integer seconds = luaL_optinteger(L, 2, 2);
    const char *msg = luaL_optstring(L, 3, "");
    int type = toast_type(kind);
    luaL_argcheck(L, type > 0, 1, "invalid toast type");
    luaL_argcheck(L, seconds >= 1 && seconds <= 60, 2, "seconds out of range");
    char err[512] = {0};
    if (validate_text_value(msg, err, sizeof(err))) return push_error(L, err);
    size_t cap = strlen(msg) + 64;
    char *body = (char *)malloc(cap);
    if (!body) return push_error(L, "out of memory");
    int n = snprintf(body, cap, "%d;;%s;;%lld;;0", type, msg, (long long)seconds);
    if (n <= 0 || (size_t)n >= cap) {
        free(body);
        return push_error(L, "toast packet overflow");
    }
    int rc = action_task(L, TASK_TOAST, body);
    free(body);
    return rc;
}

static int l_toast_hide(lua_State *L) {
    return action_task(L, TASK_TOAST, "0;;;;0;;0");
}

static const luaL_Reg nkcore_funcs[] = {
    {"version", l_version},
    {"nativeVersion", l_native_version},
    {"nowMs", l_now_ms},
    {"ping", l_ping},
    {"sleep", l_sleep},
    {"tap", l_tap},
    {"hold", l_tap},
    {"swipe", l_swipe},
    {"path", l_path},
    {"openApp", l_open_app},
    {"stop", l_stop},
    {"recordStart", l_record_start},
    {"recordStop", l_record_stop},
    {"text", l_text},
    {"paste", l_paste},
    {"keyboard", l_keyboard},
    {"cursor", l_cursor},
    {"delete", l_delete},
    {"getClipboard", l_clipboard_get},
    {"setClipboard", l_clipboard_set},
    {"screen", l_screen},
    {"foreground", l_foreground},
    {"orientation", l_orientation},
    {"scale", l_scale},
    {"device", l_device},
    {"battery", l_battery},
    {"runtime", l_runtime},
    {"screenshot", l_screenshot},
    {"findImage", l_find_image},
    {"getColor", l_get_color},
    {"findColor", l_find_color},
    {"ocr", l_ocr},
    {"toast", l_toast},
    {"hideToast", l_toast_hide},
    {NULL, NULL}
};

LUAMOD_API int luaopen_nkcore(lua_State *L) {
    signal(SIGPIPE, SIG_IGN);
    luaL_newlib(L, nkcore_funcs);
    lua_pushliteral(L, NKCORE_VERSION);
    lua_setfield(L, -2, "VERSION");
    lua_pushliteral(L, NK_NATIVE_VERSION);
    lua_setfield(L, -2, "NATIVE_VERSION");
    lua_pushboolean(L, 1);
    lua_setfield(L, -2, "DIRECT");
    return 1;
}
