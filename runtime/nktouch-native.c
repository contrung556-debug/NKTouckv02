// NKTouch v0.5 native automation client
// SPDX-License-Identifier: GPL-3.0-or-later
#ifndef _POSIX_C_SOURCE
#define _POSIX_C_SOURCE 200809L
#endif
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

#define NK_VERSION "0.5.0"
#define PORT 6000
#define FINGER 1
#define TASK_TOUCH 10
#define TASK_OPEN_APP 11
#define TASK_RECORD_START 14
#define TASK_RECORD_STOP 15
#define TASK_FORCE_STOP 20
#define TASK_TEMPLATE_MATCH 21
#define TASK_TEXT 24
#define TASK_DEVICE 25
#define TASK_OCR 27
#define TASK_SCREENSHOT 30
#define TOUCH_UP 0
#define TOUCH_DOWN 1
#define TOUCH_MOVE 2
#define MAX_TEXT 16384
#define MAX_SCREENSHOT_BYTES (50ULL * 1024ULL * 1024ULL)

static void usage(FILE *f) {
    fprintf(f,
      "NKTouch native v%s\n"
      "tap x y | hold x y ms | swipe x1 y1 x2 y2 ms | openapp bundle-id\n"
      "record start|stop | stop | ping | version | sleep MS\n"
      "text TEXT | keyboard show|hide | cursor OFFSET | delete COUNT | paste TEXT\n"
      "clipboard-get | clipboard-set TEXT\n"
      "screenshot [PATH] | find-image PATH [maxTry confidence scale]\n"
      "wait-image PATH TIMEOUT_MS [INTERVAL_MS confidence] | tap-image PATH TIMEOUT_MS [INTERVAL_MS confidence]\n"
      "ocr x y width height [languages] | wait-app bundle-id TIMEOUT_MS [INTERVAL_MS]\n"
      "screen | foreground | orientation | scale | device | battery | runtime\n", NK_VERSION);
}

static int parse_double(const char *s, const char *name, double *out) {
    char *e = NULL; errno = 0; double v = strtod(s, &e);
    if (errno || !e || *e || !isfinite(v)) {
        fprintf(stderr, "NKTouch: invalid %s: %s\n", name, s); return -1;
    }
    *out = v; return 0;
}

static int parse_long(const char *s, const char *name, long lo, long hi, long *out) {
    char *e = NULL; errno = 0; long v = strtol(s, &e, 10);
    if (errno || !e || *e || v < lo || v > hi) {
        fprintf(stderr, "NKTouch: invalid %s: %s\n", name, s); return -1;
    }
    *out = v; return 0;
}

static int validate_text(const char *s) {
    size_t n = strlen(s);
    if (n > MAX_TEXT || strchr(s, '\r') || strchr(s, '\n') || strstr(s, ";;")) {
        fprintf(stderr, "NKTouch: value must be <= %d bytes and cannot contain CR/LF or ';;'\n", MAX_TEXT);
        return -1;
    }
    return 0;
}

static int connect_core(void) {
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) { perror("NKTouch socket"); return -1; }
#ifdef SO_NOSIGPIPE
    int one = 1; (void)setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof(one));
#endif
    struct timeval tv = {3, 0};
    (void)setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
    (void)setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));
    struct sockaddr_in a; memset(&a, 0, sizeof(a));
    a.sin_family = AF_INET; a.sin_port = htons(PORT);
    (void)inet_pton(AF_INET, "127.0.0.1", &a.sin_addr);
    if (connect(fd, (struct sockaddr *)&a, sizeof(a)) != 0) {
        fprintf(stderr, "NKTouch: cannot connect 127.0.0.1:%d: %s\n", PORT, strerror(errno));
        close(fd); return -1;
    }
    return fd;
}

static int send_all(int fd, const char *p, size_t n) {
    while (n) {
        ssize_t w = send(fd, p, n, 0);
        if (w < 0) { if (errno == EINTR) continue; perror("NKTouch send"); return -1; }
        if (!w) return -1;
        p += w; n -= (size_t)w;
    }
    return 0;
}

static int recv_line(int fd, char *buf, size_t cap) {
    size_t i = 0;
    while (i + 1 < cap) {
        ssize_t r = recv(fd, buf + i, 1, 0);
        if (r < 0) { if (errno == EINTR) continue; return -1; }
        if (!r) break;
        if (buf[i++] == '\n') break;
    }
    buf[i] = 0;
    while (i && (buf[i-1] == '\n' || buf[i-1] == '\r')) buf[--i] = 0;
    return i ? 0 : -1;
}

static char *payload(char *r) {
    if (!strncmp(r, "0;;", 3)) return r + 3;
    return r[0] == '0' ? r + 1 : r;
}

static int request_internal(int task, const char *body, char *reply, size_t reply_cap, int noisy) {
    int fd = connect_core(); if (fd < 0) return -1;
    size_t len = strlen(body ? body : ""), cap = len + 16;
    char *packet = malloc(cap);
    if (!packet) { close(fd); return -1; }
    int n = snprintf(packet, cap, "%02d%s\r\n", task, body ? body : "");
    int ok = (n > 0 && (size_t)n < cap) ? send_all(fd, packet, (size_t)n) : -1;
    free(packet);
    if (!ok) ok = recv_line(fd, reply, reply_cap);
    close(fd);
    if (ok) {
        if (noisy) fprintf(stderr, "NKTouch: no valid reply from core\n");
        return -1;
    }
    if (reply[0] != '0') {
        if (noisy) fprintf(stderr, "NKTouch: core error: %s\n", reply);
        return -1;
    }
    return 0;
}

static int request(int task, const char *body, char *reply, size_t reply_cap) {
    return request_internal(task, body, reply, reply_cap, 1);
}

static int action(int task, const char *body) {
    char r[4096];
    if (request(task, body, r, sizeof(r))) return 5;
    puts("ok"); return 0;
}

static int query(int task, const char *body) {
    char r[32768];
    if (request(task, body, r, sizeof(r))) return 5;
    puts(payload(r)); return 0;
}

static int coord(double v, int *out) {
    if (v < 0 || v > 9999.9) return -1;
    long n = lround(v * 10.0); if (n < 0 || n > 99999) return -1;
    *out = (int)n; return 0;
}

static int touch(int fd, int type, double x, double y) {
    int sx, sy; char p[64];
    if (coord(x, &sx) || coord(y, &sy)) { fprintf(stderr, "NKTouch: coordinate out of range\n"); return -1; }
    int n = snprintf(p, sizeof(p), "101%d%02d%05d%05d\r\n", type, FINGER, sx, sy);
    return (n > 0 && (size_t)n < sizeof(p)) ? send_all(fd, p, (size_t)n) : -1;
}

static long long now_us(void) {
    struct timespec t; if (clock_gettime(CLOCK_MONOTONIC, &t)) return 0;
    return (long long)t.tv_sec * 1000000LL + t.tv_nsec / 1000LL;
}

static void sleep_us(long long us) {
    if (us <= 0) return;
    struct timespec t = {(time_t)(us/1000000LL), (long)((us%1000000LL)*1000LL)};
    while (nanosleep(&t, &t) && errno == EINTR) {}
}

static int tap_point(double x, double y, long ms) {
    int fd = connect_core(); if (fd < 0) return 4;
    int ok = touch(fd, TOUCH_DOWN, x, y);
    if (!ok) { sleep_us(ms * 1000LL); ok = touch(fd, TOUCH_UP, x, y); }
    close(fd); return ok ? 5 : 0;
}

static int tap_cmd(int ac, char **av, int hold) {
    if (ac != (hold ? 3 : 2)) return 2;
    double x,y; long ms = 45;
    if (parse_double(av[0],"x",&x) || parse_double(av[1],"y",&y)) return 2;
    if (hold && parse_long(av[2],"ms",0,300000,&ms)) return 2;
    int rc = tap_point(x, y, ms);
    if (!rc) puts("ok");
    return rc;
}

static int swipe_cmd(int ac, char **av) {
    if(ac!=5)return 2;
    double x1,y1,x2,y2; long ms;
    if(parse_double(av[0],"x1",&x1)||parse_double(av[1],"y1",&y1)||
       parse_double(av[2],"x2",&x2)||parse_double(av[3],"y2",&y2)||
       parse_long(av[4],"ms",32,300000,&ms)) return 2;
    int fd=connect_core(); if(fd<0)return 4;
    if(touch(fd,TOUCH_DOWN,x1,y1)){close(fd);return 5;}
    int steps=(int)(ms/16); if(steps<2)steps=2; if(steps>120)steps=120;
    long long start=now_us(), dur=ms*1000LL;
    for(int i=1;i<steps;i++){
        long long target=start+(dur*i)/steps, wait=target-now_us(); if(wait>0)sleep_us(wait);
        double t=(double)i/steps;
        if(touch(fd,TOUCH_MOVE,x1+(x2-x1)*t,y1+(y2-y1)*t)){close(fd);return 5;}
    }
    long long wait=start+dur-now_us(); if(wait>0)sleep_us(wait);
    int ok=touch(fd,TOUCH_UP,x2,y2); close(fd); if(ok)return 5; puts("ok"); return 0;
}

static int text_action(int sub, const char *text) {
    if(validate_text(text)) return 2;
    size_t cap=strlen(text)+32; char *b=malloc(cap); if(!b)return 5;
    int n=snprintf(b,cap,"%d;;%s",sub,text);
    int rc=(n>0&&(size_t)n<cap)?action(TASK_TEXT,b):5; free(b); return rc;
}

static int number_action(int sub, const char *s, const char *name, long lo, long hi) {
    long v; char b[64]; if(parse_long(s,name,lo,hi,&v))return 2;
    (void)snprintf(b,sizeof(b),"%d;;%ld",sub,v); return action(TASK_TEXT,b);
}

static int device_query(int sub) { char b[16]; (void)snprintf(b,sizeof(b),"%d",sub); return query(TASK_DEVICE,b); }

static int foreground_value(char *out, size_t cap, int noisy) {
    char r[4096];
    if(request_internal(TASK_DEVICE,"32",r,sizeof(r),noisy))return -1;
    char *p=payload(r), *s=strstr(p,";;"); if(s)*s=0;
    if (strlen(p) + 1 > cap) return -1;
    memcpy(out, p, strlen(p)+1); return 0;
}

static int foreground(void) {
    char b[1024]; if (foreground_value(b,sizeof(b),1)) return 5;
    puts(b); return 0;
}

static int screenshot_cmd(int ac, char **av) {
    if (ac > 1) return 2;
    const char *path = ac == 1 ? av[0] : "/var/mobile/Library/NKTouch/screenshot.jpg";
    if (!path[0] || strchr(path, '\r') || strchr(path, '\n')) return 2;
    int fd = connect_core(); if (fd < 0) return 4;
    if (send_all(fd, "30\r\n", 4)) { close(fd); return 5; }
    char header[256];
    if (recv_line(fd, header, sizeof(header))) {
        fprintf(stderr, "NKTouch: screenshot header failed\n"); close(fd); return 5;
    }
    if (header[0] != '0') {
        fprintf(stderr, "NKTouch: screenshot error: %s\n", header); close(fd); return 5;
    }
    unsigned long long bytes = 0;
    if (sscanf(header, "0;;image/jpeg;;%llu", &bytes) != 1 || bytes == 0 || bytes > MAX_SCREENSHOT_BYTES) {
        fprintf(stderr, "NKTouch: invalid screenshot header: %s\n", header); close(fd); return 5;
    }
    FILE *f = fopen(path, "wb");
    if (!f) { fprintf(stderr, "NKTouch: cannot write %s: %s\n", path, strerror(errno)); close(fd); return 5; }
    unsigned char buf[16384];
    unsigned long long left = bytes;
    int rc = 0;
    while (left) {
        size_t want = left < sizeof(buf) ? (size_t)left : sizeof(buf);
        ssize_t n = recv(fd, buf, want, 0);
        if (n < 0) { if (errno == EINTR) continue; rc = 5; break; }
        if (!n) { rc = 5; break; }
        if (fwrite(buf, 1, (size_t)n, f) != (size_t)n) { rc = 5; break; }
        left -= (unsigned long long)n;
    }
    if (fclose(f) != 0) rc = 5;
    close(fd);
    if (rc) { unlink(path); fprintf(stderr, "NKTouch: incomplete screenshot\n"); return rc; }
    puts(path); return 0;
}

static int build_match_body(const char *path, int has_opts, int max_try, double confidence, double scale, char **out) {
    if (validate_text(path)) return -1;
    size_t cap = strlen(path) + 128;
    char *b = malloc(cap); if (!b) return -1;
    int n;
    if (has_opts) n = snprintf(b, cap, "%s;;%d;;%.4f;;%.4f", path, max_try, confidence, scale);
    else n = snprintf(b, cap, "%s", path);
    if (n <= 0 || (size_t)n >= cap) { free(b); return -1; }
    *out = b; return 0;
}

static int parse_match_reply(char *r, double *x, double *y, double *w, double *h) {
    char *p = payload(r);
    return sscanf(p, "%lf;;%lf;;%lf;;%lf", x, y, w, h) == 4 ? 0 : -1;
}

static int find_image_once(const char *path, int has_opts, int max_try, double confidence, double scale,
                           double *x, double *y, double *w, double *h, int noisy) {
    char *body = NULL, r[4096];
    if (build_match_body(path, has_opts, max_try, confidence, scale, &body)) return -1;
    int rc = request_internal(TASK_TEMPLATE_MATCH, body, r, sizeof(r), noisy);
    free(body);
    if (rc) return -1;
    return parse_match_reply(r, x, y, w, h);
}

static int find_image_cmd(int ac, char **av) {
    if (ac != 1 && ac != 4) return 2;
    int max_try = 2; double confidence = 0.8, scale = 0.8;
    if (ac == 4) {
        long m;
        if (parse_long(av[1],"maxTry",0,8,&m) || parse_double(av[2],"confidence",&confidence) ||
            parse_double(av[3],"scale",&scale) || confidence <= 0 || confidence > 1 ||
            scale <= 0.05 || scale >= 1.0) return 2;
        max_try = (int)m;
    }
    double x,y,w,h;
    if (find_image_once(av[0], ac==4, max_try, confidence, scale, &x,&y,&w,&h,1)) return 6;
    printf("%.2f;;%.2f;;%.2f;;%.2f\n", x,y,w,h); return 0;
}

static int wait_image_common(int ac, char **av, int tap_after) {
    if (ac < 2 || ac > 4) return 2;
    long timeout, interval = 250;
    double confidence = 0.8;
    if (parse_long(av[1],"timeout_ms",0,300000,&timeout)) return 2;
    if (ac >= 3 && parse_long(av[2],"interval_ms",50,10000,&interval)) return 2;
    if (ac >= 4 && (parse_double(av[3],"confidence",&confidence) || confidence <= 0 || confidence > 1)) return 2;
    long long deadline = now_us() + timeout * 1000LL;
    for (;;) {
        double x,y,w,h;
        if (!find_image_once(av[0], 1, 2, confidence, 0.8, &x,&y,&w,&h,0)) {
            if (tap_after) {
                int rc = tap_point(x + w/2.0, y + h/2.0, 45);
                if (rc) return rc;
                puts("ok");
            } else {
                printf("%.2f;;%.2f;;%.2f;;%.2f\n", x,y,w,h);
            }
            return 0;
        }
        if (now_us() >= deadline) {
            fprintf(stderr, "NKTouch: timeout waiting for image: %s\n", av[0]);
            return 7;
        }
        sleep_us(interval * 1000LL);
    }
}

static int wait_app_cmd(int ac, char **av) {
    if (ac < 2 || ac > 3 || validate_text(av[0])) return 2;
    long timeout, interval = 200;
    if (parse_long(av[1],"timeout_ms",0,300000,&timeout)) return 2;
    if (ac == 3 && parse_long(av[2],"interval_ms",50,10000,&interval)) return 2;
    long long deadline = now_us() + timeout * 1000LL;
    for (;;) {
        char b[1024];
        if (!foreground_value(b,sizeof(b),0) && !strcmp(b,av[0])) { puts("ok"); return 0; }
        if (now_us() >= deadline) { fprintf(stderr, "NKTouch: timeout waiting for app: %s\n", av[0]); return 7; }
        sleep_us(interval * 1000LL);
    }
}

static int ocr_cmd(int ac, char **av) {
    if (ac < 4 || ac > 5) return 2;
    double x,y,w,h;
    if (parse_double(av[0],"x",&x)||parse_double(av[1],"y",&y)||
        parse_double(av[2],"width",&w)||parse_double(av[3],"height",&h)||
        x < 0 || y < 0 || w <= 0 || h <= 0) return 2;
    const char *lang = ac == 5 ? av[4] : "";
    if (validate_text(lang)) return 2;
    size_t cap = strlen(lang) + 192; char *body = malloc(cap);
    if (!body) return 5;
    int n = snprintf(body, cap, "1;;%.2f,,%.2f,,%.2f,,%.2f;;;;0.03125;;0;;%s;;1;;",
                     x,y,w,h,lang);
    int rc = (n > 0 && (size_t)n < cap) ? query(TASK_OCR, body) : 5;
    free(body); return rc;
}

int main(int argc, char **argv) {
    signal(SIGPIPE,SIG_IGN);
    if(argc<2){usage(stderr);return 2;}
    const char *c=argv[1];
    if(!strcmp(c,"version")){if(argc!=2)return 2;puts(NK_VERSION);return 0;}
    if(!strcmp(c,"ping")){if(argc!=2)return 2;int fd=connect_core();if(fd<0)return 4;close(fd);puts("ok");return 0;}
    if(!strcmp(c,"sleep")){long ms;if(argc!=3||parse_long(argv[2],"ms",0,300000,&ms))return 2;sleep_us(ms*1000LL);puts("ok");return 0;}
    if(!strcmp(c,"tap"))return tap_cmd(argc-2,argv+2,0);
    if(!strcmp(c,"hold"))return tap_cmd(argc-2,argv+2,1);
    if(!strcmp(c,"swipe"))return swipe_cmd(argc-2,argv+2);
    if(!strcmp(c,"openapp")){if(argc!=3||!argv[2][0]||strlen(argv[2])>500||validate_text(argv[2]))return 2;return action(TASK_OPEN_APP,argv[2]);}
    if(!strcmp(c,"record")){if(argc!=3)return 2;if(!strcmp(argv[2],"start"))return action(TASK_RECORD_START,"");if(!strcmp(argv[2],"stop"))return action(TASK_RECORD_STOP,"");return 2;}
    if(!strcmp(c,"stop")){if(argc!=2)return 2;return action(TASK_FORCE_STOP,"");}
    if(!strcmp(c,"text")){if(argc!=3)return 2;return text_action(1,argv[2]);}
    if(!strcmp(c,"keyboard")){if(argc!=3)return 2;if(!strcmp(argv[2],"show"))return action(TASK_TEXT,"2;;1");if(!strcmp(argv[2],"hide"))return action(TASK_TEXT,"2;;0");return 2;}
    if(!strcmp(c,"cursor")){if(argc!=3)return 2;return number_action(3,argv[2],"offset",-100000,100000);}
    if(!strcmp(c,"delete")){if(argc!=3)return 2;return number_action(4,argv[2],"count",0,100000);}
    if(!strcmp(c,"paste")){if(argc!=3)return 2;return text_action(5,argv[2]);}
    if(!strcmp(c,"clipboard-get")){if(argc!=2)return 2;return query(TASK_TEXT,"6");}
    if(!strcmp(c,"clipboard-set")){if(argc!=3)return 2;return text_action(7,argv[2]);}
    if(!strcmp(c,"screenshot"))return screenshot_cmd(argc-2,argv+2);
    if(!strcmp(c,"find-image"))return find_image_cmd(argc-2,argv+2);
    if(!strcmp(c,"wait-image"))return wait_image_common(argc-2,argv+2,0);
    if(!strcmp(c,"tap-image"))return wait_image_common(argc-2,argv+2,1);
    if(!strcmp(c,"ocr"))return ocr_cmd(argc-2,argv+2);
    if(!strcmp(c,"wait-app"))return wait_app_cmd(argc-2,argv+2);
    if(!strcmp(c,"screen")){if(argc!=2)return 2;return device_query(1);}
    if(!strcmp(c,"foreground")){if(argc!=2)return 2;return foreground();}
    if(!strcmp(c,"orientation")){if(argc!=2)return 2;return device_query(2);}
    if(!strcmp(c,"scale")){if(argc!=2)return 2;return device_query(3);}
    if(!strcmp(c,"device")){if(argc!=2)return 2;return device_query(30);}
    if(!strcmp(c,"battery")){if(argc!=2)return 2;return device_query(31);}
    if(!strcmp(c,"runtime")){if(argc!=2)return 2;return device_query(32);}
    usage(stderr);return 2;
}
