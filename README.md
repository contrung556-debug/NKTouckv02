# NKTouch v0.5 Runtime

NKTouch is a rootless iOS automation project for jailbroken devices. v0.5 keeps the pinned GPL ZXTouch SpringBoard engine, fixes the V4 screenshot task collision, and turns the native layer into a more complete automation runtime with image matching, OCR, waits, health checks and shell-script execution without requiring Python 3 for the new APIs.

## v0.5 highlights

- Keeps native touch, swipe, app launch, keyboard, clipboard and device APIs from V4
- Fixes screenshot protocol: uses upstream `TASK_SCREENSHOT = 30` instead of colliding with `TASK_PROMPT_INPUT = 29`
- Saves the upstream binary JPEG screenshot directly to a requested path
- Native template matching with `find-image`
- Polling primitives: `wait-image`, `tap-image`, `wait-app`, `sleep`
- Native OCR through the pinned core's Vision text recognizer
- `doctor` health report for native helper, SpringBoard core, screen and foreground app
- Shell script runner with `check` and `run`; no Python is required for V5 scripts
- Lua API for vision, waits, OCR and script execution
- Existing compact status/progress overlay remains integrated

## Architecture

```text
Lua / shell script
      |
      v
 nktouchctl
      |
      v
 native C client --> TCP 127.0.0.1:6000 --> ZXTouch SpringBoard core
                                         |-> touch / keyboard
                                         |-> screenshot task 30
                                         |-> template match task 21
                                         `-> OCR task 27
```

## Build

Use branch `v0.5-runtime`:

**Actions → Build NKTouch v0.5 Runtime → Run workflow**

Artifact:

```text
NKTouch-v0.5-runtime-rootless
```

Package:

```text
com.nk.nktouch_0.5.0_rootless.deb
```

## Quick test

```sh
nktouchctl backend
nktouchctl ping
nktouchctl doctor
nktouchctl screen
nktouchctl foreground
```

Expected backend:

```text
native 0.5.0
```

## Touch / app / wait

```sh
nktouchctl tap 200 400
nktouchctl hold 200 400 700
nktouchctl swipe 200 650 200 250 500
nktouchctl openapp com.apple.mobilesafari
nktouchctl wait-app com.apple.mobilesafari 5000
nktouchctl sleep 500
```

## Keyboard / clipboard

```sh
nktouchctl text "Xin chào"
nktouchctl keyboard show
nktouchctl cursor -1
nktouchctl delete 1
nktouchctl paste "NKTouch V5"
nktouchctl clipboard-set "abc123"
nktouchctl clipboard-get
```

## Screenshot / vision

```sh
nktouchctl screenshot
nktouchctl screenshot /var/mobile/shot.jpg
nktouchctl find-image /var/mobile/button.png
nktouchctl find-image /var/mobile/button.png 2 0.85 0.8
nktouchctl wait-image /var/mobile/button.png 5000 250 0.85
nktouchctl tap-image /var/mobile/button.png 5000 250 0.85
```

A successful image match prints:

```text
x;;y;;width;;height
```

`tap-image` waits for the template and taps its center. A wait timeout exits non-zero instead of silently continuing.

The default screenshot path is:

```text
/var/mobile/Library/NKTouch/screenshot.jpg
```

## OCR

OCR an area of the current screen:

```sh
nktouchctl ocr 0 0 390 844
nktouchctl ocr 0 0 390 844 "vi-VN,,en-US"
```

Multiple recognition languages use the upstream `,,` separator.

## Shell script runtime

Validate a script without running it:

```sh
nktouchctl check /var/mobile/my-script.sh
```

Run it:

```sh
nktouchctl run /var/mobile/my-script.sh
```

Inside a script NKTouch exports `NKTOUCHCTL` and `NKTOUCH_HOME`:

```sh
#!/var/jb/bin/sh
set -eu
CTL="${NKTOUCHCTL:-/var/jb/usr/bin/nktouchctl}"

"$CTL" status 10 "Mở Safari"
"$CTL" openapp com.apple.mobilesafari
"$CTL" wait-app com.apple.mobilesafari 5000
"$CTL" sleep 300
"$CTL" success "Safari sẵn sàng"
```

## Lua helper

```lua
local nk = dofile('/var/jb/usr/share/nktouch/lua/nktouch.lua')

nk.status(10, 'Mở app')
nk.openApp('com.apple.mobilesafari')
nk.waitApp('com.apple.mobilesafari', 5000)

local rect = nk.waitImage('/var/mobile/button.png', 5000, 250, 0.85)
if rect then
    nk.tap(rect.x + rect.width / 2, rect.y + rect.height / 2)
end

local text = nk.ocr(0, 0, 390, 844, 'vi-VN,,en-US')
nk.success('Xong')
```

Useful V5 APIs include `findImage`, `waitImage`, `tapImage`, `ocr`, `waitApp`, `sleep`, `doctor`, `runScript` plus all V4 touch, text, clipboard and device APIs.

## Protocol safety

The pinned ZXTouch core defines `TASK_PROMPT_INPUT = 29` and `TASK_SCREENSHOT = 30`. V5's build explicitly verifies both IDs and fails if a conflicting custom screenshot task is present. Text protocol fields also reject CR/LF and the literal `;;` delimiter when that would make a packet ambiguous.

## Files on device

```text
/var/mobile/Library/NKTouch/status.state
/var/mobile/Library/NKTouch/events.log
/var/mobile/Library/NKTouch/heartbeat
/var/mobile/Library/NKTouch/screenshot.jpg
/var/jb/usr/bin/nktouchctl
/var/jb/usr/libexec/nktouch/nktouch-native
/var/jb/usr/share/nktouch/nktouchctl.py
/var/jb/usr/share/nktouch/lua/nktouch.lua
```

## License

GPL-3.0. See `LICENSE` and `NOTICE.md`. Upstream ZXTouch attribution is retained.
