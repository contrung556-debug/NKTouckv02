# NKTouch v0.6 Vision

NKTouch is a rootless iOS automation project for jailbroken devices. v0.6 builds on the V5 native runtime and adds native color vision, text waits and toast feedback while keeping the pinned GPL ZXTouch SpringBoard engine.

## v0.6 highlights

- Everything from V5: native touch, app control, keyboard, clipboard, screenshot, image matching, OCR, waits and script runner
- Native `pixel` color picker through upstream task 23
- Native `find-color`, `wait-color` and `tap-color` through upstream task 28
- `wait-text` polls the native OCR engine until requested text appears or timeout occurs
- Native toast feedback through upstream task 22
- Lua helpers for color vision, text waits and toast
- AutoTouch compatibility helper now exposes `getColor(x,y)` as packed `0xRRGGBB`
- Protocol guard verifies task IDs 22/23/27/28/29/30 against the pinned core
- Touch/image/color coordinates use the same physical-pixel coordinate system used by the SpringBoard core

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
                                         |-> image match / screenshot
                                         |-> OCR / wait-text
                                         |-> color picker / color search
                                         `-> toast
```

## Build

Branch: `v0.6-vision`

Artifact:

```text
NKTouch-v0.6-vision-rootless
```

Package:

```text
com.nk.nktouch_0.6.0_rootless.deb
```

## Quick test

```sh
nktouchctl backend
nktouchctl ping
nktouchctl doctor
nktouchctl pixel 100 100
```

Expected backend:

```text
native 0.6.0
```

## Color vision

Read one pixel:

```sh
nktouchctl pixel 100 100
```

Output:

```text
red;;green;;blue
```

Find a color range inside a region:

```sh
nktouchctl find-color 0 0 1170 2532 200 255 200 255 200 255 2
```

Output on success:

```text
x;;y;;red;;green;;blue
```

Wait for or tap the first matching pixel:

```sh
nktouchctl wait-color 0 0 1170 2532 200 255 200 255 200 255 5000 200 2
nktouchctl tap-color  0 0 1170 2532 200 255 200 255 200 255 5000 200 2
```

## Text wait

Wait until OCR in a region contains text:

```sh
nktouchctl wait-text 0 0 1170 2532 "Tiếp tục" 5000 300 "vi-VN,,en-US"
```

A timeout exits non-zero, making it suitable for shell-script flow control.

## Toast

```sh
nktouchctl toast success 2 "Hoàn tất"
nktouchctl toast warning 2 "Đang chờ"
nktouchctl toast hide
```

Types: `error`, `warning`, `message`, `success`.

## Existing image/OCR APIs

```sh
nktouchctl screenshot /var/mobile/shot.jpg
nktouchctl find-image /var/mobile/button.png
nktouchctl wait-image /var/mobile/button.png 5000 250 0.85
nktouchctl tap-image /var/mobile/button.png 5000 250 0.85
nktouchctl ocr 0 0 1170 2532 "vi-VN,,en-US"
```

## Lua example

```lua
local nk = dofile('/var/jb/usr/share/nktouch/lua/nktouch.lua')

nk.toast('message', 'Đang tìm nút', 2)

local c = nk.getColor(100, 100)
if c then
    nk.log(string.format('RGB %d %d %d', c.red, c.green, c.blue))
end

local hit = nk.waitColor(0, 0, 1170, 2532,
    200, 255, 200, 255, 200, 255,
    5000, 200, 2)

if hit then
    nk.tap(hit.x, hit.y)
end

local text = nk.waitText(0, 0, 1170, 2532,
    'Tiếp tục', 5000, 300, 'vi-VN,,en-US')

if text then nk.success('Đã thấy chữ') end
```

## Script runtime

```sh
nktouchctl check /var/mobile/task.sh
nktouchctl run /var/mobile/task.sh
```

No Python 3 is required for V6 native APIs or shell-script execution.

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

V6's build fails if these task IDs move, preventing the screenshot collision that existed in V4.

## License

GPL-3.0. See `LICENSE` and `NOTICE.md`. Upstream ZXTouch attribution is retained.
