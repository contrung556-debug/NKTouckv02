# NKTouch v0.2

NKTouch is a rootless iOS automation project for jailbroken devices. v0.2 keeps the proven GPL ZXTouch touch engine internally and adds an NKTouch control layer around it.

## v0.2 additions

- Compact progress/status capsule in the status-bar area
- `nktouchctl` command-line control
- Status types: normal / success / warning / error / hide
- Event log and heartbeat state
- Touch helpers: tap / swipe / hold
- App foreground helper
- Touch recording start/stop helper
- Basic Lua module (`nktouch.lua`) for gradual migration from AutoTouch scripts
- Rootless GitHub Actions build

## Install/build on iPhone

1. Create a GitHub repository named `NKTouch`.
2. Upload the *contents* of this folder to the repository root.
3. Open GitHub → Actions → **Build NKTouch v0.2**.
4. Run the workflow.
5. Download artifact `NKTouch-v0.2-rootless`.
6. Install the `.deb` with Sileo/Zebra/Filza and respring when offered.

> Remove the standalone `NKTopStatus` tweak before installing v0.2 because the compact status overlay is now integrated into NKTouch.

## Quick test after installation

From NewTerm:

```sh
nktouchctl status 25 "Khởi động"
nktouchctl status 55 "Đang xử lý"
nktouchctl success "Hoàn tất"
```

Touch tests (require Procursus Python 3, same dependency used for ZXTouch Python scripts):

```sh
nktouchctl tap 200 400
nktouchctl hold 200 400 700
nktouchctl swipe 200 650 200 250 500
```

Other commands:

```sh
nktouchctl openapp com.apple.mobilesafari
nktouchctl record start
nktouchctl record stop
nktouchctl log "test log"
nktouchctl state
nktouchctl hide
```

## Files on device

```text
/var/mobile/Library/NKTouch/status.state
/var/mobile/Library/NKTouch/events.log
/var/mobile/Library/NKTouch/heartbeat
/var/jb/usr/bin/nktouchctl
/var/jb/usr/share/nktouch/nktouchctl.py
/var/jb/usr/share/nktouch/lua/nktouch.lua
```

## Lua helper

The bundled Lua module is intentionally a compatibility layer in v0.2; it does not yet ship a standalone Lua runtime. A future version will embed the runtime so NKTouch can execute `.lua` directly without AutoTouch.

Example:

```lua
local nk = dofile('/var/jb/usr/share/nktouch/lua/nktouch.lua')

nk.status(20, 'Bắt đầu')
nk.tap(200, 400)
nk.swipe(200, 650, 200, 250, 500)
nk.success('Xong')
```

## License

GPL-3.0. See `LICENSE` and `NOTICE.md`.
