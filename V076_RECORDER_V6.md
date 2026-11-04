# NKTouch v0.7.6 — Recorder V6 / Gesture Engine

## Goal
Upgrade the proven v0.7.5.6 Control Foundation recorder with **continuous single-finger touch trajectories**, while retaining Recorder V5 hardware stop (hold Volume Down 0.5 s), acceptance/saved/error feedback, mobile runner, Editor Pro, network and tasks.

## How it works
- The upstream ZXTouch HID recorder still captures events. V6 parses real 101... touch down/move/up packets and 18... microsecond timing gaps. No invented HID injection or simulated live capture.
- `lua/nkgesture_v6.lua` classifies **tap, hold, swipe and drag**, saves a bounded 11th `path` column in `.nktl` as `x,y,t;x,y,t;...`, and generates `nk.path({...})` for trajectories with intermediate points.
- Native `nkcore.path` replays the points on **one uninterrupted contact** (down → moves → up) with monotonic millisecond timestamps. This is different from chaining several independent swipe calls.
- The exporter retains V4 `trim-tail`, editing/moving/deleting actions, and can read older 10-column timelines. Editing a path gesture's coordinates/type/duration deliberately clears its old path so replay never silently uses incompatible data.
- SpringBoard hotkey, runner notifications, and V5 zero-trim hardware stop stay unchanged.

## Supported versus not yet supported
- ✅ Single-finger tap, hold, straight/curved swipe, long drag and per-point timing.
- ✅ Maximum 256 sampled points per gesture, 300,000 ms duration; files/rows validated before writing.
- ✅ Older `.nktl` rows render with the original swipe fallback.
- ⚠️ Overlapping multi-finger contacts are **not** replayed simultaneously. Their gestures are excluded from the exported timeline and count as ignored, rather than being falsely represented as independent fingers.
- ⚠️ No live touch-dot overlay. Showing an indicator tied to actual HID events still requires validated device-side event observation.
- ⚠️ The iPhone runtime and UI must be tested on a jailbroken device; GitHub Actions checks compile/package and synthetic HID fixtures only.

## Test
Run the GitHub Actions workflow `build-v076-recorder-v6.yml` on branch `v0.7.6-recorder-v6-gesture-engine`. It runs retained V5/V6 checks, synthetic raw HID fixtures with host Lua, builds the iOS app and Theos tweak, and validates the rootless `.deb` layout.

Install only when the workflow is green, and keep a known-good v0.7.5.6 package for rollback.
