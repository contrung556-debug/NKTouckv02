# NKTouch Memory Core — Dev Optimization (2026-11-05)

**Not yet a Sileo release.** Current public Sileo package remains v0.7.16.
These changes have been implemented on \`v0.7.16-command-hardening-dev\`
and covered by fast Linux/Lua tests. iOS compilation and physical-device
memory profiling are still pending.

## What is actually released?

- Existing \`nkvision.withFrame()\` closes the frame immediately after its
  callback, regardless of success/failure.
- New change: it performs a bounded incremental Lua garbage-collector
  step after native frame closure. Full GC does not run after every frame.
- New change: the native \`nkvision_native\` frame opens JPEG/CGImage
  without allocating either decoded RGBA or grayscale upfront.
  - \`frame:ocr()\` can use CGImage without the extra bitmaps.
  - \`frame:getColor()\` and \`frame:findColor()\` lazily allocate RGBA.
  - \`frame:findImage()\` lazily allocates RGBA and grayscale.
  - \`frame:close()\` and userdata \`__gc\` release any buffers actually
    allocated, plus CGImage and retained JPEG.
  - \`frame:info()\` now exposes \`rgba_bytes\` and \`gray_bytes\` as **owned
    bitmap allocations only**. These are not a measure of full process RSS.

On a 750x1334 frame, avoided allocations can total approximately
\`750*1334*(4+1) = 5,002,500 bytes\` (about 4.77 MiB) **for an OCR-only frame**
relative to the old eager RGBA+grayscale implementation. This is an
allocation-avoidance estimate, not a measured decrease in iPhone RSS;
Vision/CoreGraphics may allocate other buffers internally.

## Lua-only memory API (available after a future build)

\`\`\`lua
local memory=require("nkmemory")
local before=assert(memory.stats())
local partial=assert(memory.release({mode="step",step_kb=128}))
-- When a script is FINISHED with large temporary tables:
local full=assert(memory.release({mode="full"}))
print(("Lua heap %.1f -> %.1f KiB"):format(
    full.lua_kb_before,full.lua_kb_after))
\`\`\`

This module reports **LUA_HEAP_ONLY** and explicitly cannot claim to
free kernel memory, other applications, or a separate NKTouch service.
Open native image buffers require \`frame:close()\`, not Lua GC alone.

## Regression tests (no iOS build)

- \`tests/test_v0716_memory_core.py\`: verifies lazy native allocation,
  guaranteed frame close, 120 successful/failing frame lifetimes with
  temporary screenshot removal, and Lua GC.
- \`.github/workflows/validate-v0716-testlab.yml\`: runs fast tests.

## For current Sileo v0.7.16 users

The downloadable Facebook v10 script keeps NKTouch v0.7.16 compatibility.
It performs incremental **Lua** collection between OCR polls and full
Lua collection after completion/error. It does not depend on \`nkmemory\`
or require installing a package update.

**Do not attempt to reclaim RAM by killing SpringBoard, launching
unbounded garbage-collection loops, removing active screenshot files,
or restarting the touch daemon while a gesture is executing.** An
individual Lua worker process already returns its process memory to
iOS when it exits.

## Device verification to do before publishing

Use repeated 100–500 frame experiments and memory gauges to measure
actual peak RSS and whether the service recovers after each run. Test
both OCR-only and mixed OCR/getColor/findColor/findImage in one frame.
Retest Unicode InputText and long-running scripts for stability.
