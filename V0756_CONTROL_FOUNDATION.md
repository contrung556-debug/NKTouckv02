# NKTouch 0.7.5.6 — Control Foundation

Baseline: proven 0.7.5.5 Recorder V5 Volume Trigger.

## Adds

- SpringBoard `NKHotkeyAction` dispatcher instead of a one-purpose recorder callback.
- Recorder hardware-stop acknowledgement protocol:
  - `recorder.accepted`
  - `recorder.completed.ok`
  - `recorder.completed.failed`
- Haptic + compact SpringBoard feedback pill:
  - `REC STOPPING…`
  - `✓ REC SAVED`
  - `REC ERROR`
- `nktouchctl version` reports package `0.7.5.6`.
- `nktouchctl version --all` reports the retained component versions separately.

## Retained behavior

- Hold Volume Down for 0.5 seconds to Stop + Lua from any app.
- Short Volume Down presses are passed to iOS normally.
- SpringBoard does not read recorder files and does not execute `nkrecorder`.
- `zxtouch-runner` verifies Recorder is active before acknowledging a hotkey.
- Recorder V5 timeline/render/manual-stop behavior is unchanged.
- Rootless layout remains scheme-neutral before Theos packaging.

## Intentionally deferred to Recorder V6

A real touch indicator is **not** faked in SpringBoard. Touch points must come from the actual HID capture path so multi-touch/finger identity remain correct. Recorder V6 will connect the indicator to the HID/gesture layer together with raw `touchDown/touchMove/touchUp` and gesture classification.
