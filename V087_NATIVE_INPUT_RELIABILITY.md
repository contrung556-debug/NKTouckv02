# NKTouch v0.8.7 — Native Input Reliability (pre-Sileo beta)

Base: v0.8.6 rootless package, `v0.8.7-native-input-reliability-dev`
branch. **Do not publish to Sileo from this workflow.**

## Prior architecture audit and actual limitation

The existing v0.8.5 Input Pro already sends ONE UTF-8/base64 packet to
SpringBoard, then dispatches a notification asynchronously into the
foreground app's `UIKeyboardImpl` hook. Its direct insertion path already
tries to locate `UIView.isFirstResponder` + `UIKeyInput` using
`NKInputV2FocusedView`, but the synchronous network ACK only confirms
dispatch, not insertion. So OCR is NOT necessary to type quickly, but
the old `requireFocusProof=true` check had no Native API.

v0.8.7 adds a **read-only focus query**, not a new typing method.

## Native implementation

1. Lua `nk.focusedInput(bundleID)` calls exported
   `nkcore.focusedInput(bundleID)` without retry. The target bundle ID must
   be 3–180 safe ASCII characters.
2. Native core sends task `24`, input subcommand `10;;bundleID` to
   the existing SpringBoard socket. Input subcommands `8/9` remain exactly
   the same and still acknowledge dispatch only.
3. SpringBoard generates a fresh UUID, registers a transient reply observer
   on its main queue and posts an asynchronous, *read-only* distributed
   notification with the UUID and expected app bundle to the app hook.
   The server socket worker waits at most **700 ms**, then cleans the
   observer. Missing hooks/replies/timeouts fail closed (unknown), **never
   focused**. This prevents a background wait from blocking UIKit.
4. The target app checks that the requested bundle ID matches itself,
   has a foreground-active UIWindowScene, and one key UIWindow contains a
   `UIView` where `isFirstResponder` and `UIKeyInput` are both true.
   All UIKit queries run on that process's main thread.
5. The target app responds with UUID, bundle, and a boolean only (no
   entered text, clipboard contents or OCR). SpringBoard matches UUID
   and bundle. Only an explicit positive result returns `true`; explicit
   negative returns `false`; timeout returns `nil,err,code`.

### Lua methods

| Method | Behavior |
| --- | --- |
| `nk.inputFast(text)` | Fast native direct input, unchanged, no OCR |
| `nk.inputText(text)` | Existing v2 default, unchanged |
| `nk.focusedInput("com.apple.mobilenotes")` | Read-only, true/false/nil |
| `nk.inputSafe(text,{...,requireFocusProof=true})` | Checks app, taps one coordinate, waits, checks app, native focus and app again, then sends ONE native direct input packet |
| `nk.inputKeyboard(text)` | Explicit keyboard mode only |
| `nk.precisionInspect(...)` | Retained v0.8.6 same-frame RGB |

## Safety constraints and important limitations

- **Not an atomic transaction**: UIKit focus can change between a valid
  read-only probe and the async insertion. A successful focus query cannot
  guarantee the subsequent text reached the field.
- If no `UIKeyboardImpl` exists yet in that app, or distributed
  notifications are delayed/unavailable, probe times out; this is
  `FOCUS_PROBE_UNAVAILABLE`, not a reason to resend.
- On some custom controls or web content, the actual responder may not be
  the UIView that `NKInputV2FocusedView` can inspect; such inputs may
  remain unsupported. No private selector or undocumented UIKit
  `UIWindow.firstResponder` is assumed.
- Per-field `onceKey` is mandatory in Safe Input and process-local;
  script restarts do not persist this protection.
- Native transport ACK remains `DISPATCHED_UNVERIFIED` for Fast and Safe.
  No auto-retry on uncertain packet delivery.
- No OCR, screenshot, keyboard spying, clipboard use or storing text in
  focus check messages.
- This distributed-notification probe is a functional confirmation, **not
  a security boundary against malicious injected apps**. It is nonce and
  bundle correlated but is not a cryptographically authenticated channel.

## Acceptance checklist

- [x] Lua and Python host tests on GitHub PASS for true, false, unknown,
      thrown exception, app transition, onceKey and no-duplicate guarantees.
- [ ] Rootless iOS tweak and bundled Lua binary compile and package PASS.
- [ ] Manually run **Input • Kiểm tra focus UIKit** in Notes (with and
      without cursor) and record outcomes.
- [ ] Manually enable strict sample after editing the focus pixel and
      confirm Unicode/emoji/numeric input; verify no double insertion.
- [ ] Test password field focus only with harmless test data (never print
      secrets), foreground app changes and keyboard shown/hidden.
- [ ] Verify v0.8.6 Precision, v0.8.5 Input Fast, OCR Test Lab and Recorder
      on the same phone; compare input latency with AutoTouch fairly.
- [ ] Only consider Sileo upgrade after phone testing.

### Samples

`test_focus_probe_v087.lua` is read-only by default and never types.
`test_input_strict_v087.lua` contains `ENABLE_REAL_INPUT=false`,
so manually enabling it is an explicit, test-device-only action.
