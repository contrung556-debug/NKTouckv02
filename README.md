# NKTouch v0.3 Native

NKTouch is a rootless iOS automation project for jailbroken devices. v0.3 keeps the proven GPL ZXTouch SpringBoard touch engine internally, but replaces the Python dependency for core automation commands with a small compiled native client.

## What changed in v0.3

- Native C client connects directly to ZXTouch at `127.0.0.1:6000`
- `tap`, `hold` and `swipe` no longer require Python 3
- `openapp`, touch recording start/stop and force-stop also run through the native client
- `nktouchctl backend` shows which backend is active
- `nktouchctl ping` checks whether the local automation service is reachable
- Python helper remains only as a compatibility fallback for commands not yet ported (`screen`, `foreground`)
- Existing compact status/progress overlay remains integrated
- Existing Lua API stays compatible

## Architecture

```text
Lua / shell script
      |
      v
 nktouchctl
      |
      +--> native C client --> TCP 127.0.0.1:6000 --> ZXTouch SpringBoard core
      |
      +--> Python fallback (screen / foreground only for now)
```

The native touch packet format follows the pinned GPL ZXTouch source used by this project.

## Build on GitHub

Use branch `v0.3-native` and run:

**Actions → Build NKTouch v0.3 Native → Run workflow**

The workflow:

1. Fetches the pinned ZXTouch rootless source.
2. Cross-compiles `runtime/nktouch-native.c` for iOS arm64.
3. Signs the native helper with `ldid`.
4. Applies the NKTouch v0.3 layer.
5. Builds the iOS app and rootless tweak package.
6. Uploads artifact `NKTouch-v0.3-native-rootless`.

The resulting package is:

```text
com.nk.nktouch_0.3.0_rootless.deb
```

## Quick test after installation

From NewTerm:

```sh
nktouchctl backend
nktouchctl ping
```

Expected backend:

```text
native 0.3.0
```

Status overlay:

```sh
nktouchctl status 25 "Khởi động"
nktouchctl status 55 "Đang xử lý"
nktouchctl success "Hoàn tất"
```

Native touch tests — no Python 3 required:

```sh
nktouchctl tap 200 400
nktouchctl hold 200 400 700
nktouchctl swipe 200 650 200 250 500
```

Native application/control tests:

```sh
nktouchctl openapp com.apple.mobilesafari
nktouchctl record start
nktouchctl record stop
nktouchctl stop
```

Compatibility commands currently using the Python fallback:

```sh
nktouchctl screen
nktouchctl foreground
```

## Files on device

```text
/var/mobile/Library/NKTouch/status.state
/var/mobile/Library/NKTouch/events.log
/var/mobile/Library/NKTouch/heartbeat
/var/jb/usr/bin/nktouchctl
/var/jb/usr/libexec/nktouch/nktouch-native
/var/jb/usr/share/nktouch/nktouchctl.py
/var/jb/usr/share/nktouch/lua/nktouch.lua
```

## Lua helper

```lua
local nk = dofile('/var/jb/usr/share/nktouch/lua/nktouch.lua')

nk.status(20, 'Bắt đầu')
nk.tap(200, 400)
nk.swipe(200, 650, 200, 250, 500)
nk.success('Xong')
```

`nk.tap`, `nk.hold`, `nk.swipe`, `nk.openApp`, recording and stop now route through the native backend when v0.3 is installed.

## License

GPL-3.0. See `LICENSE` and `NOTICE.md`. The native client implements the socket/task protocol used by the pinned GPL ZXTouch core; upstream attribution remains in `NOTICE.md`.
