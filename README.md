# NKTouch v0.6.2 Standalone Lua

NKTouch v0.6.2 completes the next foundation step before V7: Lua scripts can now run directly from the NKTouch package on a jailbroken rootless iPhone. AutoTouch and Python 3 are not required for the normal standalone Lua/native automation path.

## What V6.2 adds

- Bundled, pinned Lua `5.4.9` interpreter compiled for iOS arm64
- Bundled `luac` syntax checker
- `nktouch-lua` standalone launcher
- `nktouchctl lua <script.lua>` to execute Lua scripts directly
- `nktouchctl lua -e '<code>'` for quick Lua commands
- `nktouchctl lua-check <script.lua>` for syntax validation before running
- `nktouchctl lua-version`
- The launcher automatically loads `require('nktouch')` as global `nk`
- A small AutoTouch compatibility layer is installed automatically: `tap`, `swipe`, `inputText`, `usleep`, `sleep`, `getColor`, `log`, `setTopStatus`, `hideTopStatus`
- `doctor full` now verifies that the bundled Lua interpreter and NKTouch Lua API both load
- `selftest` verifies the standalone Lua runtime without performing touch/input side effects
- Lua source archive is checksum-pinned in CI and its upstream README/license notice is bundled in the package

## Versions

```text
NKTouch runtime: 0.6.2
Native engine:   0.6.0
Bundled Lua:     5.4.9
```

The native engine intentionally remains on the tested V6 baseline while the runtime layer is improved around it.

## Architecture

```text
.lua script
   |
   v
nktouchctl lua / nktouch-lua
   |
   +--> bundled Lua 5.4.9
   |      |
   |      +--> global nk / AutoTouch compatibility helpers
   |                 |
   |                 v
   +-----------> nktouchctl
                     |
                     v
             native C engine 0.6.0
                     |
                     v
             TCP 127.0.0.1:6000
                     |
                     v
              ZXTouch GPL core
```

## Build

Branch:

```text
v0.6.2-lua
```

Artifact:

```text
NKTouch-v0.6.2-lua-rootless
```

Package:

```text
com.nk.nktouch_0.6.2_rootless.deb
```

## First health test

```sh
nktouchctl backend
nktouchctl lua-version
nktouchctl doctor
nktouchctl doctor full
nktouchctl selftest
```

A healthy device should finish with:

```text
lua_runtime=ok
result=PASS
```

## Run a standalone Lua script

Create `/var/mobile/test.lua`:

```lua
print('NKTouch Lua:', nk.VERSION)
print('Bundled Lua:', nk.LUA_VERSION)

local screen = nk.screen()
print('screen:', screen or 'unknown')

nk.log('Standalone Lua is running')
```

Run it:

```sh
nktouchctl lua /var/mobile/test.lua
```

No AutoTouch process is involved.

## AutoTouch-style compatibility

The default launcher preloads the compatibility helpers, so a simple script can use:

```lua
tap(200, 400)
usleep(500000)
inputText('Xin chào từ NKTouch')
```

For new scripts, prefer the explicit API because errors/results are clearer:

```lua
local ok, code = nk.tap(200, 400)
if not ok then
    nk.error('tap failed: '..tostring(code))
end
```

## Syntax check before execution

```sh
nktouchctl lua-check /var/mobile/test.lua
```

Expected result:

```text
ok
```

## Plain Lua mode

If a script should not preload NKTouch globals:

```sh
/var/jb/usr/bin/nktouch-lua --plain /var/mobile/plain.lua
```

The NKTouch module is still available through the package path if explicitly required.

## V6/V6.1 capabilities retained

- Native tap, hold and swipe
- App launch / foreground / wait-app
- Keyboard, text, cursor, delete, paste and clipboard
- Screenshot
- Image matching: `find-image`, `wait-image`, `tap-image`
- OCR and `wait-text`
- Color picker/search: `pixel`, `find-color`, `wait-color`, `tap-color`
- Toast feedback
- Shell script runner
- Bounded retries for read-only transport failures
- No automatic retry for side-effecting actions
- `doctor`, `selftest`, `cleanup`

## Important limitation

V6.2 provides a standalone Lua interpreter, but the Lua helper still reaches the native automation engine through `nktouchctl` subprocesses. Direct in-process C bindings are a later optimization. This keeps V6.2 conservative while removing the dependency on AutoTouch for running Lua scripts.

## Protocol safety

The pinned core still defines:

```text
22 toast
23 color picker
27 OCR
28 color search
29 prompt input
30 screenshot
```

V6.2 introduces no new SpringBoard protocol task ID.

## License

NKTouch/ZXTouch code remains GPL-3.0 with upstream attribution retained. The bundled Lua interpreter is built from the official Lua 5.4.9 source archive; its upstream README/license notice is included in the package.
