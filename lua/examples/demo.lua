-- NKTouch v0.4 standalone Lua demo
-- Run with: nktouch-run /var/jb/usr/share/nktouch/lua/examples/demo.lua

setTopStatus(10, "Lua V4 bắt đầu")
log("demo.lua started")

-- Native backend health check.
nk.ping()

setTopStatus(45, "Đang test Lua runtime")
sleep(0.4)

-- Uncomment on-device when you want to test an actual touch.
-- tap(200, 400)
-- swipe(200, 650, 200, 250, 500)
-- appRun("com.apple.mobilesafari")

setTopStatus(85, "Gần xong")
usleep(200000)

nk.success("Lua V4 hoạt động")
log("demo.lua finished")
