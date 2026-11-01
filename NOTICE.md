# NKTouch v0.4 — Notices

NKTouch v0.4 is an independent GPL-3.0-or-later automation layer built on the open-source ZXTouch Rootless project.

## ZXTouch core

- Project: ZXTouch Rootless
- Repository: https://github.com/Epic0001/zxtouchrootless
- Pinned commit used by this build: a602da112ef1a688fb2601424443abb1ccc28c63
- Rootless port maintained by Epic0001 and contributors
- Original IOS13-SimulateTouch / ZXTouch work by xuan32546 / Jason Z and contributors

The upstream copyright notices and GPL license must be preserved when redistributing modified binaries or source.

## Lua runtime

NKTouch v0.4 bundles Lua 5.4.9 from https://www.lua.org/ under the MIT license.
Copyright © 1994–2026 Lua.org, PUC-Rio.

The build verifies the official Lua source archive with a pinned SHA-256 before compiling it. The package also preserves Lua's upstream README/license documentation under `/var/jb/usr/share/doc/nktouch/lua/`.

## NKTouch additions

- compact status/progress overlay for SpringBoard
- native `nktouchctl` automation client path
- standalone `nktouch-run` Lua launcher
- automatic Lua bootstrap and AutoTouch-style compatibility globals
- state/event log files under `/var/mobile/Library/NKTouch`
- iOS `posix_spawn` shim used by the bundled Lua runtime for `os.execute`

NKTouch is not affiliated with AutoTouch.
