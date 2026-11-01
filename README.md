# NKTouch v0.6.3 Direct Lua Native

NKTouch v0.6.3 keeps the standalone Lua 5.4.9 runtime from V6.2 and removes most per-action shell overhead. The bundled Lua interpreter now statically embeds an `nkcore` C module that talks directly to the pinned ZXTouch SpringBoard core over TCP `127.0.0.1:6000`.

## What V6.3 changes

- Embedded `nkcore 0.6.3` is registered directly in Lua's built-in library table; no `dlopen` or separate `.so` is required
- `nktouch.lua` automatically detects `nkcore` and sets `nk.DIRECT=true`
- Primary automation calls now use Lua -> C -> SpringBoard core directly instead of spawning `nktouchctl` for every action
- Direct native Lua primitives include touch, swipe, app launch, text/keyboard/clipboard, screenshot, image matching, pixel/color search, OCR, toast and device queries
- `waitApp`, `waitImage`, `tapImage`, `waitColor`, `tapColor` and `waitText` use Lua loops built on direct C primitives and a monotonic native timer
- Status overlay, logs, `doctor`, `selftest`, cleanup and shell-script launching intentionally remain shell-backed because they manage runtime files/processes
- Host CI smoke-tests `require('nkcore')` before cross-compiling the iOS binary
- iOS CI verifies that `nkcore` and version `0.6.3` are embedded in the final arm64 Lua executable
- V6.1 safety rule remains: CLI side-effecting commands are not auto-retried

## Versions

```text
NKTouch runtime: 0.6.3
Native CLI:      0.6.0
Lua native core: 0.6.3
Bundled Lua:     5.4.9
```

The separate `nktouch-native` CLI intentionally remains on the tested V6 protocol baseline. V6.3 adds a second in-process client used by Lua; both speak the same pinned SpringBoard protocol.

## Architecture

```text
.lua script
   |
   v
nktouch-lua / nktouchctl lua
   |
   v
bundled Lua 5.4.9
   |
   +--> nktouch.lua
   |       |
   |       +--> nkcore C module (direct path)
   |               |
   |               v
   |       TCP 127.0.0.1:6000
   |               |
   |               v
   |        ZXTouch SpringBoard core
   |
   `--> nktouchctl only for status/log/doctor/process helpers
```

## Direct APIs

These APIs use `nkcore` directly when V6.3 is installed:

```text
ping / sleep
tap / hold / swipe
openApp / waitApp / stop / recordStart / recordStop
text / inputText / keyboard / cursor / delete / paste
getClipboard / setClipboard
screenshot
findImage / waitImage / tapImage
getColor / findColor / waitColor / tapColor
ocr / waitText
toast / hideToast
screen / foreground / orientation / scale / device / battery / runtime
```

## Build

Branch:

```text
v0.6.3-native-lua
```

Artifact:

```text
NKTouch-v0.6.3-native-lua-rootless
```

Package:

```text
com.nk.nktouch_0.6.3_rootless.deb
```

## Health test

```sh
nktouchctl backend
nktouchctl lua-version
nktouchctl doctor full
nktouchctl selftest
```

Expected healthy markers:

```text
lua_api=ok:0.6.3:direct
lua_direct=ok
result=PASS
```

Check direct mode manually:

```sh
nktouchctl lua -e 'print("runtime",nk.VERSION,"direct",nk.DIRECT,"core",nk.coreVersion())'
```

Expected:

```text
runtime  0.6.3  direct  true  core  0.6.3
```

## Example Lua script

```lua
print('NKTouch:', nk.VERSION, 'direct:', nk.DIRECT)

local screen, err = nk.screen()
print('screen:', screen or err)

local c = nk.getColor(100, 100)
if c then
    print('RGB:', c.red, c.green, c.blue)
end

local hit = nk.waitImage('/var/mobile/button.png', 5000, 250, 0.82)
if hit then
    nk.tap(hit.x + hit.width/2, hit.y + hit.height/2)
end
```

## AutoTouch-style compatibility

The default launcher still installs the small compatibility layer:

```lua
tap(200, 400)
usleep(500000)
inputText('Xin chào từ NKTouch')
local color = getColor(100, 100)
```

These helpers now benefit from the direct `nkcore` path when possible.

## Plain Lua mode

```sh
/var/jb/usr/bin/nktouch-lua --plain /var/mobile/plain.lua
```

Even in plain mode the statically embedded module can be loaded explicitly:

```lua
local core = require('nkcore')
print(core.VERSION, core.DIRECT)
```

## Safety and compatibility

V6.3 does not add a new SpringBoard protocol task ID. It continues to verify the pinned core IDs:

```text
21 template match
22 toast
23 color picker
24 text/clipboard
25 device/app state
27 OCR
28 color search
29 prompt input
30 screenshot
```

Touch/image/color coordinates remain in the physical-pixel coordinate system used by the SpringBoard core.

## Remaining foundation work

V6.3 removes most Lua subprocess overhead. Before V7, the next useful hardening step is device testing of the direct path, especially image/OCR/color loops and failure behavior when the SpringBoard core restarts. Network/HTTP and AI orchestration remain intentionally deferred until the local automation foundation is proven stable.

## License

NKTouch/ZXTouch code remains GPL-3.0 with upstream attribution retained. The bundled Lua interpreter is built from the official Lua 5.4.9 source archive; its upstream README/license notice is included in the package.
