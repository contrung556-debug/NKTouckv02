# NKTouch v0.4 Native

NKTouch is a rootless iOS automation project for jailbroken devices. v0.4 keeps the pinned GPL ZXTouch SpringBoard engine and expands the native control layer so common automation tasks no longer need Python 3.

## v0.4 highlights

- Native `tap`, `hold`, `swipe`, app launch, record and stop
- Native text input through ZXTouch keyboard task 24
- Show/hide keyboard, move cursor and delete text
- Paste text and get/set clipboard
- Native screenshot command using the existing ZXTouch screenshot engine
- Native screen size, foreground app, orientation, scale, device info, battery and runtime status
- Expanded Lua helper with action and query APIs
- Existing compact status/progress overlay remains integrated
- Python helper is retained only as an emergency fallback for older V3-compatible commands

## Architecture

```text
Lua / shell script
      |
      v
 nktouchctl
      |
      v
 native C client --> TCP 127.0.0.1:6000 --> ZXTouch SpringBoard core
```

V4 exposes screenshot through NKTouch task `29`; the actual screenshot implementation remains the screenshot engine already present in the pinned ZXTouch core.

## Build

Use branch `v0.4-native`:

**Actions → Build NKTouch v0.4 Native → Run workflow**

Artifact:

```text
NKTouch-v0.4-native-rootless
```

Package:

```text
com.nk.nktouch_0.4.0_rootless.deb
```

## Quick test

```sh
nktouchctl backend
nktouchctl ping
nktouchctl screen
nktouchctl foreground
nktouchctl battery
```

Expected backend:

```text
native 0.4.0
```

Touch:

```sh
nktouchctl tap 200 400
nktouchctl hold 200 400 700
nktouchctl swipe 200 650 200 250 500
```

Keyboard / clipboard:

```sh
nktouchctl text "Xin chào"
nktouchctl keyboard show
nktouchctl cursor -1
nktouchctl delete 1
nktouchctl paste "NKTouch V4"
nktouchctl clipboard-set "abc123"
nktouchctl clipboard-get
```

Screenshot / device:

```sh
nktouchctl screenshot
nktouchctl orientation
nktouchctl scale
nktouchctl device
nktouchctl battery
nktouchctl runtime
```

`screenshot` prints the PNG path returned by the SpringBoard screenshot engine.

## Lua helper

```lua
local nk = dofile('/var/jb/usr/share/nktouch/lua/nktouch.lua')

nk.status(20, 'Bắt đầu')
nk.tap(200, 400)
nk.inputText('Xin chào')
local shot = nk.screenshot()
local app = nk.foreground()
local battery = nk.battery()
nk.success('Xong')
```

Useful V4 APIs include `text/inputText`, `showKeyboard`, `hideKeyboard`, `moveCursor`, `delete`, `paste`, `getClipboard`, `setClipboard`, `screenshot`, `screen`, `foreground`, `orientation`, `scale`, `device`, `battery`, and `runtime`.

### Protocol note

The ZXTouch socket protocol is line-based and uses `;;` as a field separator. V4 therefore rejects text containing CR/LF or the literal delimiter `;;` instead of sending an ambiguous packet.

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

## License

GPL-3.0. See `LICENSE` and `NOTICE.md`. Upstream ZXTouch attribution is retained.
