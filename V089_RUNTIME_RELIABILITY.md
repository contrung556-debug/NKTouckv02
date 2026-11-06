# NKTouch v0.8.9 — Runtime Reliability (artifact candidate)

Development branch: `v0.8.9-runtime-reliability-dev`.
Production Sileo remains v0.8.8. This candidate is **not** automatically
published to Sileo.

## Architecture audit (important to avoid a duplicate engine)

- The existing **native `nktask` supervisor** already supports start,
  process termination, `stop`, timeout and task status files. It is the
  only mechanism that can impose a process-level hard stop if a Lua
  script loops indefinitely or a native call blocks.
- `nkstability.pollRead` handles bounded *read-only* retries, not input or
  HID actions.
- `nkdiagnostics` provides opt-in checkpoints with a sanitized event
  history. `nkmemory` reports Lua heap and optional process RSS; Lua
  GC does not necessarily release resident pages held by the OS.
- `nk.withFrame` closes immutable native Vision frames after callbacks;
  do not replace this lifecycle with unbounded screenshot caching.
- The old public `nk.runtime()` reports runtime metadata; **v0.8.9 keeps
  that API intact**. New APIs use distinct names.

## Added APIs

`nk.runtimeSession(options)` creates a cooperative Lua session:

- `deadline_ms` defaults to 120000; valid 100–600000.
- `max_steps` defaults to 100; valid 1–1000.
- `max_resources` defaults to 32; valid 1–64.
- `max_events` defaults to 80; valid 5–120.
- `cancelled=function() return boolean end` is an optional *read-only*
  cancellation source; an exception or nonboolean result fails closed.
- The runtime requires native monotonic time and sleep; tests may inject
  `now` and `sleep`. No default wall-clock scheduling is assumed.

`session:checkpoint()` checks deadline, cancellation and monotonic clock.
`session:sleep(ms)` uses bounded chunks of at most 100 ms, checking
cancellation/deadline between chunks. **It cannot interrupt a synchronous
native call already running.**

`session:step("read", function() ... end)` invokes one read-only callback.
The return data is sent to the script caller and is **never** stored in
the diagnostic event history. For actions that change state use:

```lua
local session = assert(nk.runtimeSession({deadline_ms=4000,max_steps=8}))
local ok,receipt,code = session:step("write",function()
  return nk.tap(350,400)
end,{confirmed=true,onceKey="notes.test.tap1"})
local closed,summary=session:finish()
```

Every write requires explicit `confirmed=true` and a per-target safe
ASCII `onceKey` (1–64 chars), reserved *before* dispatch.
A native transport error or unacknowledged call returns
`DISPATCH_UNCERTAIN`, and the same key remains reserved for the
lifetime of the Lua session. The engine **never retries** a write.
Write acknowledgment is reported as `DISPATCHED_UNVERIFIED`, not
proof the target UI responded.

`session:defer("safe_label", cleanupFn)` registers at most 64 cleanup
callbacks. `session:finish()` runs them last-in-first-out, exactly once,
and reports `CLEANUP_FAILED` when one fails. `session:run(fn)` and
`nk.runGuarded(fn,options)` run a protected callback and automatically
call `finish()`. An explicitly returned `false`/`nil` or a failed child
step is reported as an error (`CALLBACK_REJECTED` or the recorded step
code); it is never silently promoted to `FINISHED`. Hard kill,
memory crash and sudden process exit **cannot
guarantee Lua cleanup**; native `nktask` handles process lifecycle.

`session:snapshot()` reports only step count, status categories,
deadline, safe error codes and cleanup counts. It contains **no** typed
text, OCR results, callback arguments, read returns or raw exception
messages. An event history is bounded to a fixed count.

## Compatibility and release checks

- [x] GitHub host tests for successful/ambiguous writes, reused onceKey,
  Lua exception redaction, cancel, timeout, step count, segmented sleep,
  LIFO cleanup and double-finish.
- [x] Existing native `nktask` host tests for start/success/stop/timeout.
- [x] Host regressions for v0.8.8 Vision, v0.8.7 focus,
  v0.8.6 Touch/Color, v0.8.5 Input and v0.8.3 OCR.
- [ ] Build and inspect the rootless v0.8.9 candidate.
- [ ] On-device test: stop a long-running read-only script from the app,
  inspect logs; run Native timeout, test ordinary completion and cleanup.
- [ ] On-device test: 10/50/100 Vision captures with memory/RSS/P50/P95
  monitoring; confirm no regression in Input, Recorder and OCR.
- [ ] Only then consider a v0.8.9 Sileo publication.

Avoid claiming that a cooperative deadline or a `pcall` catches SIGKILL
or a blocked kernel/native operation. Use native process supervision as
the final safety mechanism.
