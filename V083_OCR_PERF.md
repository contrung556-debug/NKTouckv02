# NKTouch v0.8.3 — OCR Performance & Stability (artifact-only candidate)

## Scope

Forked from the verified **NKTouch v0.8.2** source. Keep ZXTouch-based
SpringBoard IPC, HID/touch, InputText, Color and existing Lua SDK unchanged.
The v0.8.2 on-device Test Lab reported **16 PASS, 0 FAIL, 1 WARN and 2 SKIP**,
including `frame_ocr PASS backend=SERVICE_JPEG_SAME_FRAME`, and successful
`foreground_verified` return. The WARN was a diagnostic:
420f plain=0, IOSurface=-6662, Metal=-6662. A standard plain allocation
working is not evidence that internal Vision/IOSurface works in Lua.

## What's new

* `lua/nkocr_perf.lua` — read-only opt-in module; `benchmark()` measures
  3–20 same-frame OCR attempts, with 0–3 warm-ups. It requires a native
  monotonic clock (or an injected monotonic clock in host tests). Never
  substitute `os.clock` CPU time and call it end-to-end latency. Report
  successful-call count, failures, min/mean/P50/P95/max (milliseconds).
* `live_runs` is an optional **separate-capture** baseline; never combine it
  with or mislabel it as same-frame.
* `memory_frames` can be 0, 10, 50 or 100, measuring Lua process RSS
  before/after explicit frame release. Memory results are observational;
  one test cannot establish whether there is a persistent leak.
* `ocrIfStable()` compares **nine sampled image pixels** between two captured
  frames. It OCRs only the second snapshot when those samples remain within
  the configured RGB tolerance; otherwise returns `SCREEN_UNSTABLE` and
  **does not OCR**. This is a heuristic; it cannot prove the spinner is gone,
  detect all animation, or replace a proper UI state check.
* Lua Workspace Samples gets two new items without overwriting existing
  scripts: **OCR • Benchmark 10 lần** and **OCR • Kiểm tra màn hình ổn định**.

No taps, text insertion, web requests or sensitive OCR text logs are performed
by these diagnostics. The selected screen is not changed by the benchmark.
The benchmark is **opt-in only**, never appended to the default 5-core suite.

## On-device supervised test

After a successful artifact-only iOS build, install the generated rootless
`.deb` on an existing compatible jailbreak. Create a new Lua sample script
from the Samples menu, then show a **non-sensitive screen with visible text**
before running. The benchmark script defaults to 10 measured frame OCR
attempts, 2 warm-ups, 3 separate live OCR attempts, 50 read-only memory frames.
Logs print `[NKPERF]` with P50/P95 and RSS delta. Verify `status=PASS` or
investigate failures; check there are no unexpected SpringBoard crashes or
memory growth. Run `test_ocr_stability_v083.lua` once on a static screen and
once while changing UI to verify `SCREEN_UNSTABLE` behavior.

**Safety and release status:** Candidate branch
`v0.8.3-ocr-perf-stability-dev`. The only build workflow for this branch
uploads an artifact; it does **not** publish to Sileo. v0.8.2 remains the
latest published release until the new candidate is verified on device.
