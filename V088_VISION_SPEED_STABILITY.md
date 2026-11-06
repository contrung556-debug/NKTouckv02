# NKTouch v0.8.8 — Vision Speed & Screen Stability (artifact-only candidate)

Source branch: `v0.8.8-vision-speed-stability-dev`.
Base: Sileo v0.8.7 Native Input Reliability. This build produces a rootless
`.deb` artifact and **does not** update the Sileo repository.

## Audit: what's already in NKTouch

- `nk.captureFrame()` and `nk.withFrame(fn)` have existed since Vision Core 0.7.9.
  The native frame owns a decoded screenshot and frees RGBA/CGImage resources
  on `close()`, even when the Lua callback returns an error.
- `nksnapshot.capture(plan)` (0.8.0) already supports multiple pixel, Color,
  template and OCR queries on **one screenshot**. Do not add a duplicate
  screenshot service or claim one-frame processing is a new native invention.
- `nkocr_perf.ocrIfStable` (0.8.3) already samples 9 pixels on two frames,
  and calls OCR on the second frame only after those samples match. This is
  a **heuristic** and does not prove every spinner or animation is finished.
- v0.8.2 OCR backend attempts IPC via SpringBoard using the existing JPEG
  crop from the captured frame. If unavailable, native Vision OCR can run on
  that **same frame**, never another screenshot. Both are recognized backends.
- v0.8.7 Input Pro, v0.8.6 Precision and earlier Lua/Recorder APIs remain
  unchanged in this candidate.

## New v0.8.8 SDK

### One-frame batch

`nk.visionBatch({pixels={...},colors={...},ocr={...},templates={...}},opts)`

Allows 0..32 pixels, 0..12 Color regions, 0..2 OCR regions, and 0..4
template images per request. Exact native Color/image ROI contracts apply,
including RGB range and per-template confidence and geometry checking.

**Optimization:** duplicate pixel coordinates are cached within the
captured frame; repeated pixel probes cost one native pixel fetch each.
Counts of native pixel reads, cache hits, Color searches, OCR calls, image
searches and capture latency are returned. Avoid mistaking dispatch elapsed
time for a benchmark against AutoTouch or the legacy capture implementation.

`result.metrics.captures` is **1** for each batch. No automatic fallback to
live OCR/screenshot on a failed same-frame request. OCR results are kept
private by default: only returned in-memory with `include_text=true`.
No OCR content is written to debug logs.

### Guarded stable-screen snapshot

`nk.visionWhenStable(plan,{
  stable_frames=3,max_captures=6,interval_ms=200,
  tolerance=6,timeout_ms=3500,watch_points={...}
})`

Performs bounded **read-only** captures. Each uses a 4×4 grid of 16
pixel locations plus up to 16 custom watch points. Consecutive captures
must have identical physical dimensions and all measured RGB channel
changes within `tolerance` for the configured count (2..4). On the **final
already sampled frame**, the engine executes the requested Color, Image
and OCR batch immediately. This avoids an extra screenshot and avoids
OCR work on sample-unstable frames.

Limits: 2..8 captures, 100..1500ms interval, 200..15000ms timeout,
tolerance 0..40 RGB/channel. Time checks occur between synchronous
operations; a slow native screenshot or OCR cannot be interrupted midcall.
If the samples do not stabilize, `nil, error, "SCREEN_UNSTABLE", details`
is returned with capture count, without any OCR attempt.

**Important:** this is pixel-sampling stability, NOT reliable detection
of all spinners, modals, navigation states or web page loading. An
animation outside sample points can go unnoticed. A separate app-specific
UI state condition is still necessary for actions that matter.

### Example

```lua
local nk=require("nktouch_v7")
local result,reason,code=nk.visionWhenStable({
  pixels={{x=120,y=140},{x=120,y=140}},
  ocr={{x=0,y=0,w=300,h=180}},
},{
  max_captures=6,stable_frames=3,interval_ms=200,
  timeout_ms=3500,tolerance=6
})
if not result then
  print("Vision gate: "..tostring(code))
else
  print(result.status,result.metrics.captures,
        result.metrics.pixel_cache_hits)
end
```

## Validation and release gate

- [x] Host checks verify Lua syntax, one-frame batching, cache deduplication,
  pixel geometry, backend selection, OCR privacy, screen-changed / timeout
  failure, bounded captures, no touch/input, no live OCR or double capture.
- [x] Previous v0.8.7 Focus, v0.8.6 Touch/Color, v0.8.5 Input and v0.8.3
  OCR regression suite remains part of CI.
- [ ] Rootless artifact built on patched iPhoneOS16.5 SDK and inspected.
- [ ] Actual iPhone runs Vision Batch / Stability Samples under multiple
  navigation transitions, including a spinner inside a custom watch region.
- [ ] Actual iPhone memory benchmark over 10/50/100 captures, with P50/P95
  latency and process resident memory (RSS) vs. v0.8.7.
- [ ] Confirm Recorder, InputText, Color and native focus after installing
  the candidate.
- [ ] Explicit approval before updating Sileo to v0.8.8.

This is not a measured speed claim until device benchmark results exist.
