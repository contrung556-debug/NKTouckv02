# NKTouch v0.7.7 — Lua Core Reliability / Color Engine

## Priority
This release prioritizes **running Lua scripts reliably** and getting **pixel/color results right**, not expanding Recorder. It inherits the GitHub Actions green v0.7.6 Gesture Engine and retains V5 global Volume Down stop without behavior changes.

## Color pipeline
- `patches/NKColorPickerSafe.xm` replaces the unchecked upstream `ColorPicker.xm` during staging. It preserves ZXTouch SpringBoard task IDs and wire messages (`TASK_COLOR_PICKER=23`, `TASK_COLOR_SEARCHER=28`).
- Validates all coordinates, RGB ranges and skip values as unsigned integers, not permissive partial string conversions.
- Checks screenshot creation, image dimensions, safe bitmap allocations, CoreGraphics contexts, and memory limits before reading a pixel.
- `getColor` reports a clear error for out-of-bounds or unavailable screenshots; never returns fabricated black RGB after a failed crop.
- `findColor` scans a bounded rectangle, clips oversize regions, searches with inclusive RGB min/max, and returns the existing no-match sentinel `-1;;-1;;-1;;-1;;-1`.
- The embedded Lua native bridge validates RGB components returned by the core, distinguishing no match from malformed data.
- A failed intermediate swipe sends a best-effort release event instead of silently leaving the finger down. Touch actions are never automatically retried.

## Coordinate contract
`getColor(x,y)`, `findColor(x,y,w,h,...)`, and the existing ZXTouch simulated touch interface take **physical screen pixel coordinates**. For retina devices, these are **not UIKit points**. Screen rotation/native pixel transforms need on-device testing; v0.7.7 does not silently assume a landscape transform or auto-scale coordinates.

A screenshot saved as JPEG can differ slightly in RGB values due to compression. Use the direct screenshot/pixel engine for exact RGB checks, and a small tolerance when matching dynamic app colors.

## Lua APIs
Existing calls are unchanged:

```lua
local nk = require("nktouch_v7")
local color = assert(nk.getColor(120, 440))
local hit = nk.findColor(100, 100, 300, 400, 245, 255, 70, 90, 30, 50, 0)
```

New calls:

```lua
-- true|false, sampledColor  OR  nil, err, kind
local matched, sample = nk.matchColor(120, 440, 255, 80, 40, 10)

-- hitTable OR nil, err, kind
local hit, err, code = nk.waitColorMatch(
    255, 80, 40, 10,
    {x=100, y=200, w=300, h=400},
    5000, 200
)
if hit then assert(nk.tap(hit.x,hit.y)) end
```

Timeout: 0–300,000 ms, scan interval: 50–10,000 ms, tolerance: 0–255 per channel. Errors are not converted into color mismatches.

## Verification and release rules
The v0.7.7 workflow runs host Lua contract tests, prior Recorder/Task tests, builds the iOS app/native Lua binaries and the rootless SpringBoard tweak, then verifies package content. **CI success does not prove physical device accuracy.**

On a jailbroken iPhone, test a static solid-color image at known pixels (including all four edges), check portrait and rotation behavior, change screen brightness, try `matchColor` true and false cases, `waitColorMatch` timeouts, then run scripts repeatedly and check stop/error handling.

Publish as stable only after on-device validation; retain a v0.7.6 `.deb` for rollback. Recorder feature work is deferred until the Lua runtime/color/image stack is solid.
