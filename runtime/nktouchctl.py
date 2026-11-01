#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later

import json
import sys
import time


def die(msg, code=2):
    print(f"NKTouch: {msg}", file=sys.stderr)
    raise SystemExit(code)


def as_float(value, name):
    try:
        return float(value)
    except Exception:
        die(f"{name} không hợp lệ: {value}")


def as_int(value, name):
    try:
        return int(float(value))
    except Exception:
        die(f"{name} không hợp lệ: {value}")


try:
    from zxtouch.client import zxtouch
    from zxtouch.touchtypes import TOUCH_DOWN, TOUCH_MOVE, TOUCH_UP
except Exception as exc:
    die(f"không import được ZXTouch Python client: {exc}. Cài Procursus python3 rồi cài lại NKTouch.", 3)


def connect():
    try:
        return zxtouch("127.0.0.1")
    except Exception as exc:
        die(f"không kết nối được automation core ở 127.0.0.1:6000: {exc}", 4)


def touch_event(dev, kind, finger, x, y):
    dev.touch(kind, finger, x, y)


def cmd_tap(args):
    if len(args) != 2:
        die("tap cần: x y")
    x, y = map(float, args)
    d = connect()
    touch_event(d, TOUCH_DOWN, 1, x, y)
    time.sleep(0.045)
    touch_event(d, TOUCH_UP, 1, x, y)
    print("ok")


def cmd_hold(args):
    if len(args) != 3:
        die("hold cần: x y ms")
    x = as_float(args[0], "x")
    y = as_float(args[1], "y")
    ms = max(0, as_int(args[2], "ms"))
    d = connect()
    touch_event(d, TOUCH_DOWN, 1, x, y)
    time.sleep(ms / 1000.0)
    touch_event(d, TOUCH_UP, 1, x, y)
    print("ok")


def cmd_swipe(args):
    if len(args) != 5:
        die("swipe cần: x1 y1 x2 y2 ms")
    x1, y1, x2, y2 = [as_float(v, n) for v, n in zip(args[:4], ["x1", "y1", "x2", "y2"])]
    ms = max(32, as_int(args[4], "ms"))
    d = connect()
    duration = ms / 1000.0
    steps = max(2, min(120, int(duration / 0.016)))
    touch_event(d, TOUCH_DOWN, 1, x1, y1)
    start = time.monotonic()
    for i in range(1, steps):
        t = i / steps
        x = x1 + (x2 - x1) * t
        y = y1 + (y2 - y1) * t
        target = start + duration * t
        delay = target - time.monotonic()
        if delay > 0:
            time.sleep(delay)
        touch_event(d, TOUCH_MOVE, 1, x, y)
    end_target = start + duration
    delay = end_target - time.monotonic()
    if delay > 0:
        time.sleep(delay)
    touch_event(d, TOUCH_UP, 1, x2, y2)
    print("ok")


def cmd_openapp(args):
    if len(args) != 1:
        die("openapp cần bundle-id")
    d = connect()
    result = d.switch_to_app(args[0])
    print(json.dumps({"ok": bool(result[0]), "result": result[1]}, ensure_ascii=False, default=str))
    if not result[0]:
        raise SystemExit(5)


def cmd_record(args):
    if len(args) != 1 or args[0] not in ("start", "stop"):
        die("record cần start hoặc stop")
    d = connect()
    result = d.start_touch_recording() if args[0] == "start" else d.stop_touch_recording()
    print(json.dumps({"ok": bool(result[0]), "result": result[1]}, ensure_ascii=False, default=str))
    if not result[0]:
        raise SystemExit(5)


def cmd_stop(args):
    if args:
        die("stop không nhận tham số")
    d = connect()
    result = d.force_stop_script_play()
    print(json.dumps({"ok": bool(result[0]), "result": result[1]}, ensure_ascii=False, default=str))
    if not result[0]:
        raise SystemExit(5)


def cmd_screen(args):
    if args:
        die("screen không nhận tham số")
    d = connect()
    result = d.get_screen_size()
    print(json.dumps({"ok": bool(result[0]), "result": result[1]}, ensure_ascii=False, default=str))
    if not result[0]:
        raise SystemExit(5)


def cmd_foreground(args):
    if args:
        die("foreground không nhận tham số")
    d = connect()
    # Upstream exposes foreground app via device-info. Method names changed across
    # historical forks, so probe supported public client methods instead of
    # hard-failing the entire wrapper.
    candidates = ["get_foreground_app", "get_foreground_application", "get_foreground_app_bundle_id"]
    for name in candidates:
        fn = getattr(d, name, None)
        if callable(fn):
            result = fn()
            print(json.dumps({"ok": bool(result[0]), "result": result[1]}, ensure_ascii=False, default=str))
            if not result[0]:
                raise SystemExit(5)
            return
    die("client hiện tại chưa có helper foreground ổn định; dùng dashboard Device để xem app foreground", 6)


COMMANDS = {
    "tap": cmd_tap,
    "hold": cmd_hold,
    "swipe": cmd_swipe,
    "openapp": cmd_openapp,
    "record": cmd_record,
    "stop": cmd_stop,
    "screen": cmd_screen,
    "foreground": cmd_foreground,
}


def main():
    if len(sys.argv) < 2:
        die("thiếu command")
    cmd = sys.argv[1]
    fn = COMMANDS.get(cmd)
    if fn is None:
        die(f"command không hỗ trợ: {cmd}")
    fn(sys.argv[2:])


if __name__ == "__main__":
    main()
