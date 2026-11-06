# NKTouch v0.8.5 — Input Engine Pro (development candidate)

Base: successfully published NKTouch 0.8.3. Development branch:
`v0.8.5-input-engine-pro-dev`. **Not on Sileo.**

## Implementation

Native Input v2 already exists in v0.8.3: sends ONE UTF-8/base64 packet
to the foreground application. The native ACK proves dispatch, not accepted
text insertion, so we will not claim it is faster than AutoTouch without
a same-device benchmark.

- `nk.inputText("Text")`: remains the existing native v2 direct default.
- `nk.inputFast("Text")`: one native direct request, no OCR or probe.
- `nk.inputSafe("Text",{bundle="com.apple.mobilenotes",focus={x=350,y=400},onceKey="notes.field1"})`:
  check target app, physical coordinate and onceKey before any tap; tap once,
  wait bounded settle time, check app again, send exactly once.
- `nk.inputKeyboard("Text")`: explicit fallback only; no automatic retry.
- Fast/keyboard support `{secure=true}` and never log text.
- Safe accepts `settleMs=0..1500` (default 100), `secure=true` and
  `requireFocusProof=true`. The latter fails closed with
  `FOCUS_PROBE_UNAVAILABLE` when the current native backend cannot
  prove the first responder. A tap plus app check is *not* proof of focus.

Safe mode *requires* a per-field `onceKey`, reserves that key before
touch and never releases it after an uncertain error. Duplicate calls
from the same Lua process return `DUPLICATE_BLOCKED` with no second tap
or text dispatch. A key is process-local, not persistent across reboot or
new Lua tasks, and must not contain secrets. One Lua process supports
128 reserved keys.

Result `status="DISPATCHED_UNVERIFIED"` is truthful; a positive native
ack does not prove insertion. No screenshots, OCR calls or character-by-
character simulated typing are used by these three new APIs.

## Acceptance before publication

1. Host CI: all Unicode, emoji, malformed UTF-8, wrong-app,
   duplicate-key, strict focus and error cases PASS; no OCR invoked.
2. Build candidate .deb, verify package version 0.8.5, rootless layout,
   same-frame OCR still intact and both new opt-in Lua Samples included.
3. Test on iPhone with a non-sensitive Notes field, numeric/Unicode
   input, foreground switch during the focus tap and a duplicate attempt.
4. Time native dispatch with `nkcore.nowMs` and distinguish from field
   insertion latency; compare fairly against AutoTouch on same device.
5. Only after device acceptance decide on a Sileo upgrade. Preserve
   version 0.8.3 in the Sileo repository for rollback.

Samples `test_input_fast_v085.lua` and `test_input_safe_v085.lua` have
`ENABLE_REAL_INPUT=false` by default: they cannot type until edited.
