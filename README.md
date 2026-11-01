# NKTouch v0.4 Standalone Lua

NKTouch is a rootless iOS automation project for jailbroken devices. v0.4 keeps the proven native V3 touch path and adds a bundled standalone Lua runtime so `.lua` automation scripts can run without AutoTouch and without Python 3.

## What changed in v0.4

- Bundled standalone Lua 5.4.9 runtime compiled for iOS arm64
- New `nktouch-run <script.lua> [args...]`
- New `nktouchctl run <script.lua> [args...]`
- New `nktouchctl lua-version`
- Automatic Lua bootstrap through `LUA_INIT`
- `nk` module is available automatically in scripts started by `nktouch-run`
- AutoTouch-style globals are installed automatically:
  - `tap(x, y)`
  - `hold(x, y, ms)`
  - `swipe(x1, y1, x2, y2, ms)`
  - `appRun(bundleId)`
  - `sleep(seconds)`
  - `usleep(microseconds)`
  - `setTopStatus(percent, message)`
  - `hideTopStatus()`
  - `log(message)`
- Native V3 commands remain available: app launch, screen info, foreground app, record start/stop, force stop, ping
- No AutoTouch, Python package or external Lua package is required for normal V4 execution

## Architecture

```text
.lua script
    |
    v
nktouch-run
    |
    +--> bundled Lua 5.4.9
    |       |
    |       +--> nktouch.lua / AutoTouch compatibility globals
    |                    |
    v                    v
 nktouchctl ------> native C client
                         |
                         v
               TCP 127.0.0.1:6000
                         |
                         v
               ZXTouch SpringBoard core
```

## Build on GitHub

Use branch `v0.4-lua` and run:

**Actions → Build NKTouch v0.4 Lua → Run workflow**

The workflow:

1. Fetches the pinned ZXTouch rootless source.
2. Cross-compiles the NKTouch native client for iOS arm64.
3. Downloads Lua 5.4.9 from `lua.org` and verifies its pinned SHA-256.
4. Builds a host Lua copy to syntax-check NKTouch modules.
5. Cross-compiles the standalone Lua runtime for iOS arm64 and signs it with `ldid`.
6. Applies the V4 package layer.
7. Runs upstream tests and builds the iOS app/tweak package.
8. Uploads artifact `NKTouch-v0.4-lua-rootless`.

The resulting package is:

```text
com.nk.nktouch_0.4.0_rootless.deb
```

## Quick test after installation

From NewTerm:

```sh
nktouchctl backend
nktouchctl ping
nktouchctl lua-version
```

Then run the bundled safe demo:

```sh
nktouch-run /var/jb/usr/share/nktouch/lua/examples/demo.lua
```

or:

```sh
nktouchctl run /var/jb/usr/share/nktouch/lua/examples/demo.lua
```

## Your own standalone script

Create `/var/mobile/test.lua`:

```lua
setTopStatus(10, "Bắt đầu")

appRun("com.apple.mobilesafari")
sleep(1)
tap(200, 400)
swipe(200, 650, 200, 250, 500)

setTopStatus(90, "Gần xong")
usleep(200000)
nk.success("Hoàn tất")
```

Run it directly:

```sh
nktouch-run /var/mobile/test.lua
```

No `require`, `dofile`, AutoTouch or Python is needed when a script is started with `nktouch-run` because the bootstrap loads NKTouch automatically.

## Native CLI remains available

```sh
nktouchctl tap 200 400
nktouchctl hold 200 400 700
nktouchctl swipe 200 650 200 250 500
nktouchctl openapp com.apple.mobilesafari
nktouchctl screen
nktouchctl foreground
nktouchctl record start
nktouchctl record stop
nktouchctl stop
```

## Files on device

```text
/var/mobile/Library/NKTouch/status.state
/var/mobile/Library/NKTouch/events.log
/var/mobile/Library/NKTouch/heartbeat
/var/jb/usr/bin/nktouchctl
/var/jb/usr/bin/nktouch-run
/var/jb/usr/libexec/nktouch/nktouch-native
/var/jb/usr/libexec/nktouch/lua
/var/jb/usr/share/nktouch/lua/bootstrap.lua
/var/jb/usr/share/nktouch/lua/nktouch.lua
/var/jb/usr/share/nktouch/lua/examples/demo.lua
```

The old Python helper is still retained only as an emergency compatibility fallback for an incomplete upgrade. It is not part of the normal V4 execution path.

## V4 scope

V4 focuses on making Lua scripts independent from AutoTouch. It does not yet recreate every AutoTouch API. Unsupported APIs should be added explicitly to the NKTouch compatibility layer instead of silently faking behavior.

## License

GPL-3.0. See `LICENSE` and `NOTICE.md`. The native client implements the socket/task protocol used by the pinned GPL ZXTouch core; upstream attribution remains in `NOTICE.md`.
