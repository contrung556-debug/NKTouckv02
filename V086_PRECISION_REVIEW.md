# NKTouch architecture audit and v0.8.6 Touch/Color Precision

Source inspected: NKTouch v0.8.5 from GitHub branch
`v0.8.5-input-engine-pro-dev`. Latest Sileo package observed before this
candidate: `com.nk.nktouch 0.8.5`, iphoneos-arm64. New candidate branch:
`v0.8.6-touch-color-precision-dev`.

## Existing functional layers

| Layer | Current implementation | Confidence |
| --- | --- | --- |
| Lua runner | Lua 5.4.9, nkcore native bridge, process supervisor and task tooling | Build + host test; on-device smoke tests remain essential |
| HID Touch | tap/hold/swipe/path, bounds protections in nkcoords and existing gesture module | Interfaces integrated; per-app gesture success not independently confirmed by dispatch ACK |
| Color | live getColor/findColor/matchColor/waitColorMatch, frame:getColor/findColor | Native frame pixel contract and host color regression checks |
| Vision/OCR | immutable captureFrame/withFrame, same-frame OCR via SpringBoard IPC | v0.8.2 device report had frame OCR PASS; v0.8.3 perf tooling included |
| Input | v2 direct Unicode packet, Fast/Safe/Keyboard APIs (v0.8.5) | Build verified; same-device AutoTouch speed parity NOT established |
| Recorder/Editor | Recorder hotkey, Lua editor, examples and Test Lab | Packaged; test each on-device before calling fully stable |
| Network/Diagnostics | HTTP/JSON helper, privacy-restricted logs and Test Lab | Packaged; crash/recovery stress beyond CI remains |

## Findings / technical debt

1. **Module/package versions differ**: retained baseline `lua/nktouch.lua`
   declares `M.VERSION="0.6.4"` whereas the package is 0.8.5/0.8.6.
   Do not silently change the legacy module's semantics; publish an explicit
   package-versus-core version API in a future compatibility release.
2. **Physical pixels versus points**: `nkcoords.lua` deliberately rejects
   guessed Retina scaling and reports frame geometry disagreement. Use the
   exact same physical-pixel coordinate contract for touch and color; no
   silent rotation or scaling.
3. **App ID and inherited code**: iOS app build still inherits
   `com.zjx.zxtouch` and parts of ZXTouch native core. The NKTouch UI
   branding does not imply the codebase is independent. Preserve licensing
   notices and audit GPL obligations before commercial redistribution.
4. **Touch and text acknowledgements**: native dispatch success is not
   equivalent to a verified UI effect. Always expose uncertainty to Lua,
   never auto-repeat a mutation after ambiguous transport errors.
5. **OCR stability**: two sampled frames/pixels can serve as a heuristic
   only. This is not reliable proof that a spinner, modal or animation ended.
6. **Source CI versus phone**: host mocks and successful iOS linking prove
   constraints and packaging, not runtime accessibility or UIKit behavior
   on every jailbroken app. Never call this release production-stable on CI
   evidence alone.

## v0.8.6 changes

`lua/nkprecision.lua` uses existing `nkcoords` and one immutable frame,
with no OCR, screenshot loops, or retries:

- `nk.precisionInspect({points={...}})`: inspect 1..16 pixel/RGB/tolerance
  specs on ONE captured frame. Reject invalid RGB/packed results and
  screen/frame geometry mismatches. Return explicit match count.
- `nk.precisionFind({region=...,color=...,skip=...})`: validate an RGB
  region match from ONE frame, including hit coordinates and color.
- `nk.precisionTapIfMatch({enabled=true,confirmed=true,bundle=...,
  tap=...,points=...})`: check proper foreground application,
  physical pixel bounds and pattern before sending exactly one touch.
- `nk.precisionTapIfFound({enabled=true,confirmed=true,bundle=...,
  region=...,color=...})`: search once, verify target app again,
  send one tap at the validated native hit.

Frames are closed by the existing `nk.withFrame` lifecycle. A match is
true only at capture time. Foreground checks cannot eliminate every race
between capture and HID dispatch. Touch receipts report
`DISPATCHED_UNVERIFIED` and never claim the app reacted.

`test_precision_colors_v086.lua` is read-only; the touch sample has
`ENABLE_REAL_TAP=false` by default.

## Acceptance before any Sileo release

- [x] Host regression validates geometry, one-frame sampling, RGB limits,
      forged native hits, app transition, touch opt-in and uncertain dispatch.
- [ ] Rootless v0.8.6 .deb CI build and package inspection.
- [ ] Manual iPhone color read-only sample, compare against physical pixels.
- [ ] Manual focus/foreground transitions and one touch in a harmless app.
- [ ] Check Recorder, Input Pro, same-frame OCR, Lua Editor regression.
- [ ] Observe crash logs, screenshot RSS, touch responsiveness over longer runs.

### Post-v0.8.6 priorities

1. v0.8.7: first-responder focus verification and deeper Native Input
   on-device reliability, without per-character OCR.
2. v0.8.8: precise Vision screen-stability metrics, benchmark P50/P95,
   avoid redundant captures.
3. v0.9: Smart Lua Runtime with bounded state checks and idempotent actions;
   never silently retry taps/text on uncertain ACK.
4. v1.0: compatibility matrix, stable Lua SDK, package/core version clarity,
   reproducible release and crash diagnostics.

This is a development report, not a claim of live device validation.
