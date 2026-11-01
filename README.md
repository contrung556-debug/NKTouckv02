# NKTouch v0.6.1 Stable

NKTouch is a rootless iOS automation project for jailbroken devices. v0.6.1 is a hardening release built on the proven V6 native engine. It keeps V6 vision/color/OCR features intact and focuses on safer retries, diagnostics, cleanup and a more predictable Lua API.

## What changed from V6

- Runtime wrapper version `0.6.1`; native engine remains the tested `0.6.0` engine
- Read-only transport failures can retry a small bounded number of times
- Side-effecting actions such as tap, text, paste, open-app and tap-image/tap-color are never auto-retried
- `doctor quick` for fast health checks
- `doctor full` additionally verifies screenshot capture and temporary-file writing
- `selftest` performs non-destructive runtime checks and reports `result=PASS` or `result=FAIL`
- `cleanup` removes only NKTouch-owned diagnostic/temp files
- Runtime state now has a dedicated `/var/mobile/Library/NKTouch/tmp` directory
- Lua `os.execute`/`io.popen` results are normalized to predictable success/error values
- Lua helpers added for `selftest`, `cleanup` and doctor modes
- Generated Python bytecode is removed from the repository and ignored
- CI includes a V6.1 runtime contract test and protocol guards

## Existing V6 capabilities retained

- Native touch, hold and swipe
- App launch / foreground / wait-app
- Keyboard, text, cursor, delete, paste and clipboard
- Screenshot
- Image matching: `find-image`, `wait-image`, `tap-image`
- OCR and `wait-text`
- Color picker/search: `pixel`, `find-color`, `wait-color`, `tap-color`
- Toast feedback
- Shell script runner
- Lua compatibility helpers

## Architecture

```text
Lua / shell script
      |
      v
 nktouchctl 0.6.1 Stable
      |
      v
 native C engine 0.6.0 --> TCP 127.0.0.1:6000 --> ZXTouch SpringBoard core
```

The stable wrapper intentionally does not auto-retry commands that may cause duplicate user actions.

## Build

Branch:

```text
v0.6.1-stable
```

Artifact:

```text
NKTouch-v0.6.1-stable-rootless
```

Package:

```text
com.nk.nktouch_0.6.1_rootless.deb
```

## Recommended health test

```sh
nktouchctl backend
nktouchctl ping
nktouchctl doctor
nktouchctl doctor full
nktouchctl selftest
```

Expected backend format:

```text
native 0.6.0 (runtime 0.6.1)
```

A healthy full self-test ends with:

```text
result=PASS
```

## Cleanup

NKTouch diagnostics use:

```text
/var/mobile/Library/NKTouch/tmp
```

Clean only NKTouch diagnostic/temp files with:

```sh
nktouchctl cleanup
```

The command does not delete user screenshots or template images stored elsewhere.

## Retry behavior

Read-only operations such as screen/device queries, OCR, pixel/color queries and screenshots can retry transport errors. Default attempts: 2.

Override for debugging:

```sh
NKTOUCH_READ_RETRIES=1 nktouchctl screen
```

Allowed range is clamped to 1-4 attempts.

The following categories are deliberately single-attempt:

```text
tap / hold / swipe / openapp / text / paste / clipboard-set
tap-image / tap-color / toast / record / stop
```

This prevents a transient acknowledgement failure from turning into a double tap or duplicate text entry.

## Vision examples

```sh
nktouchctl screenshot /var/mobile/shot.jpg
nktouchctl find-image /var/mobile/button.png
nktouchctl wait-image /var/mobile/button.png 5000 250 0.85
nktouchctl tap-image /var/mobile/button.png 5000 250 0.85
nktouchctl pixel 100 100
nktouchctl ocr 0 0 750 1334 "vi-VN,,en-US"
nktouchctl wait-text 0 0 750 1334 "Tiếp tục" 5000 300 "vi-VN,,en-US"
```

## Lua health example

```lua
local nk = dofile('/var/jb/usr/share/nktouch/lua/nktouch.lua')

local report = nk.doctor('full')
print(report or 'doctor failed')

local test = nk.selftest()
print(test or 'selftest failed')
```

`nk.VERSION` is `0.6.1`. `nk.NATIVE_VERSION` documents the stable native engine baseline as `0.6.0`.

## Protocol safety

The pinned core defines:

```text
22 toast
23 color picker
27 OCR
28 color search
29 prompt input
30 screenshot
```

The build fails if these IDs move. V6.1 does not introduce a new protocol task ID.

## License

GPL-3.0. See `LICENSE` and `NOTICE.md`. Upstream ZXTouch attribution is retained.
