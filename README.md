# NKTouch v0.6.4 Hardened Direct Runtime

NKTouch v0.6.4 keeps the proven V6.3 direct Lua architecture and hardens the runtime before V7. The SpringBoard protocol and embedded `nkcore` remain unchanged; reliability improvements are added around direct read-only operations so we do not risk duplicate taps, swipes, app launches, or text input.

## What V6.4 adds

- Runtime version `0.6.4` on top of tested `nkcore 0.6.3`
- Read-only direct calls classify errors as `CONNECT`, `TRANSPORT`, `TIMEOUT`, `NOT_FOUND`, `CORE`, `INVALID`, or `UNKNOWN`
- Transient read-only transport failures reconnect/retry with a bounded count (`NKTOUCH_READ_RETRIES`, default 2, max 4)
- Side-effecting calls remain single-attempt only: tap, hold, swipe, text, paste, app launch, clipboard write, toast, and post-detection taps are never auto-retried
- `waitApp`, image/color waits, and OCR text waits inherit the hardened read primitives
- `nktouchctl benchmark [N]` compares direct Lua reads with CLI subprocess reads
- `nktouchctl stress [N]` performs repeated read-only socket calls and reports failures, throughput, and Lua memory delta
- `selftest` now includes a small read-only direct stress probe
- CI executes the V6.4 Lua helper on a host-built Lua+nkcore binary before cross-compiling for iOS
- New V6.4 contract tests enforce retry safety and unchanged protocol IDs

## Versions

```text
NKTouch runtime: 0.6.4
Native CLI:      0.6.0
Embedded nkcore: 0.6.3
Bundled Lua:     5.4.9
```

Keeping `nkcore` at 0.6.3 is intentional: V6.3 passed device testing, including direct color reads and `selftest`. V6.4 hardens the Lua runtime around that tested native protocol implementation instead of changing the core again.

## Architecture

```text
.lua script
   |
   v
bundled Lua 5.4.9
   |
   +--> nktouch.lua 0.6.4
   |       |
   |       +--> read-only: classify -> bounded retry/reconnect
   |       +--> side effects: exactly one attempt
   |       |
   |       v
   +--> embedded nkcore 0.6.3
           |
           v
     TCP 127.0.0.1:6000
           |
           v
     ZXTouch GPL core
```

## First device test

```sh
nktouchctl backend
nktouchctl lua-version
nktouchctl doctor full
nktouchctl selftest
```

Healthy output should include:

```text
version=0.6.4
lua_api=ok:0.6.3:direct-hardened
lua_direct=ok
lua_stress=ok
result=PASS
```

## Benchmark

```sh
nktouchctl benchmark 20
```

It reports total/per-call time for direct Lua and CLI reads plus the observed speedup and Lua memory delta. The benchmark only reads screen metadata; it does not tap or type.

## Stress test

```sh
nktouchctl stress 100
```

The stress test repeatedly reads screen/foreground state and reports:

```text
iterations=100
failures=0
elapsed_ms=...
ops_per_sec=...
memory_delta_kb=...
```

Use a larger count only after the default test passes. The maximum accepted count is 2000.

## Error handling

Direct read APIs keep the familiar return style while adding a third error code:

```lua
local value, message, code = nk.screen()
if not value then
    print(code, message)
end
```

You can also classify an error explicitly:

```lua
local e = nk.classifyError("connect failed")
print(e.code, e.transient) -- CONNECT true
```

## Safety rule

V6.4 never automatically repeats an operation that can change user state. For example, a failed `nk.tap()` returns the error instead of trying a second tap. Automatic reconnect/retry is reserved for read-only operations such as screen/device queries, OCR, image/color lookup, and clipboard reads.

## Build

Branch:

```text
v0.6.4-hardening
```

Artifact:

```text
NKTouch-v0.6.4-hardening-rootless
```

Package:

```text
com.nk.nktouch_0.6.4_rootless.deb
```

## Protocol safety

The pinned core task IDs are unchanged:

```text
22 toast
23 color picker
27 OCR
28 color search
29 prompt input
30 screenshot
```

V6.4 introduces no new SpringBoard task ID.

## License

NKTouch/ZXTouch code remains GPL-3.0 with upstream attribution retained. Bundled Lua 5.4.9 keeps its upstream license notice in the package.
