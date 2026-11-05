# NKTouch v0.7.16-dev — Test Lab (7 existing API groups)

**Development only.** The patch lives on
\`v0.7.16-command-hardening-dev\`; it has NOT been built into an iOS app
and has NOT been published to Sileo. The current Sileo package stays v0.7.15.

## Product design

Test Lab uses the existing NKTouch Lua Editor and managed nktask worker.
It deliberately does **not** create a second runner, background service,
or IPC protocol.

It is discoverable in two places:
- Lua Workspace dashboard → **NKTouch Test Lab**
- Lua Library → **Samples → Test Lab • 7 nhóm**

The screen has seven selectable checkmark rows, a **Tạo bài kiểm tra →
Lua Editor** primary action, last-run status (including PARTIAL coverage), and
**Báo cáo** to inspect/copy per-test results. Each start creates a unique file
such as \`nktestlab_8a54d8b1f765.lua\`; it never overwrites user-edited scripts.
The default target app is Safari, editable with **Ứng dụng +**.

The generated Lua script has a unique run ID and the chosen group list.
It is not executed until the user taps **Chạy** in the regular Lua Editor.
Normal syntax checking, stop, Task Center and logs remain available.

## Seven groups

| ID | Group | Read-only checks | Optional mutations |
|---|---|---|---|
| runtime | Lua Runtime | Lua 5.4, API load, syntax execution, direct core | None |
| touch | Touch Engine | Invalid tap/hold/swipe/path rejected before dispatch | Tap/Hold/Swipe only with enabled=true, matching foreground Bundle ID and all pixel coordinates |
| input | Input Engine | Empty text rejected, password OCR prohibited | Focus a field and send one nonsecret test string, optional OCR confirmation, no retry |
| color | Color Engine | screen dimensions, center getColor, matchColor and findColor 1×1 | None |
| vision | Vision Core | Exactly ONE immutable frame used for repeated pixels, findColor, OCR and optional template image matching; auto-close | None |
| network | Network & JSON | Unicode JSON roundtrip, reject file:// URL without sending network request | A bounded HTTPS request to example.com only after enabled=true |
| task | Task Stability | ping, foreground, bounded sleep, 5 direct screen reads | stop/cleanup intentionally SKIP to avoid terminating the test |

## Execution / reporting contract

- \`[NKLAB][PASS|FAIL|WARN|SKIP] group/test ms=... details\` per check.
- \`[NKLAB][SUMMARY] run=<id> status=... pass=... fail=... warn=... skip=...\`.
- Atomic JSON report: \`/var/mobile/Library/NKTouch/tmp/testlab-last.json\`.
- Report includes \`version\`, \`run_id\`, \`selected\`, per-group counters,
  per-test details and timing, overall \`status\`, \`coverage=FULL/PARTIAL\`,
  \`mode=read_only_default\`, \`visual_confirmation=false\`.
- PASS only means **executed checks** passed. It never claims the target
  application visibly reacted to a touch/input operation. A mixed PASS+SKIP
  run has \`coverage=PARTIAL\`.
- A failure in one group is recorded and does not prevent the next group
  from being checked, except if the task is externally stopped.

## Interactive opt-in

The generated script is editable. Tap/Hold/Swipe and InputText are disabled:
\`touch.enabled=false\` and \`input.enabled=false\`. For interactive tests,
the user must explicitly set them \`true\`, enter the matching foreground
bundle identifier, and provide all physical pixel coordinates inside the
screen. They must also choose the correct target app in the Editor.

The runner validates the target app and all parameters **before** starting
touch dispatch; after a tap or hold, it rechecks the foreground app before
the next action. Input is sent only once. It never automatically retries text,
tap, hold or swipe after an uncertain acknowledgement. No real passwords or
secret values should be entered in the Lab.

External HTTP is disabled (\`network.enabled=false\`). Opting in only calls
\`https://example.com\` with a 5s timeout and 8KB max response.

## Development / verification

Source:
- \`lua/nktestlab.lua\` — 7 groups, run isolation, reporter, atomic JSON.
- \`patches/NKTestLabUIViewController.m.inc\` — mobile Lab UI.
- \`scripts/apply-v0716-testlab-ui.py\` — inject dashboard, Samples menu and controller in staged source.
- \`scripts/stage-v0716-testlab-dev.sh\` — stage with the preexisting v0.7.16 command hardening and earlier v0.7.15 patches; **no build**.
- \`tests/test_v0716_testlab_runner.py\` — Lua mocks, read-only default, report, fail-isolation and touch/input opt-in.
- \`tests/test_v0716_testlab_ui.py\` — UI patch anchors and generated Lua syntax.
- \`.github/workflows/validate-v0716-testlab.yml\` — Linux Lua 5.4/Python checks only.

This workflow does **not** use Xcode, macOS, Theos or dpkg-deb, and does not
publish anything. A future release may be built once after the existing
command-hardening work and the Test Lab have been checked together.

## Still pending

1. iOS/UIKit compilation of the new controller (intentionally not performed
   because no build was requested).
2. On-device Test Lab flow: menu, generated script, Editor, Task Center, JSON
   report and clipboard copy.
3. Real pixel precision/orientation, OCR and native frame performance.
4. Interactive touch/input in a disposable target application with user
   visual confirmation. No offline test can prove actual touch accuracy.

## Command Reliability + Color Precision development batch (November 5, 2026)

Added a **Reliability Report** calculated from the checks that actually ran:

- Overall timings: \`elapsed_ms\`, \`checks\`, \`total_ms\`, \`avg_check_ms\`,
  \`p95_check_ms\`, \`max_check_ms\` and \`slowest_check\`.
- Per-group: \`timing\` and \`check_pass_rate_pct\`. The denominator only includes
  executed PASS/WARN/FAIL checks; SKIPs remain visible in \`coverage=PARTIAL\`.
- \`clock_type=monotonic_native_ms\` when the direct core clock is available;
  \`cpu_time_only\` when only the Lua \`os.clock\` fallback exists; injected
  test clocks are labeled \`mock_clock\`. CPU time is never presented as
  wall-clock latency.
- These timings are of **heterogeneous checks** in one run. Their p95 is
  **not** per-API latency across multiple runs and is **not** evidence of
  accuracy on the touchscreen.
- Report keeps \`visual_confirmation=false\`. An opt-in dispatch results in
  WARN until visual/appropriate OCR evidence exists.
- Reports are written atomically to the latest-run JSON path; viewer displays
  metrics, evidence limitations, group timings, and detailed errors.

**Safety improvement:** opt-in Touch/Input now also requires
\`confirmed=true\` after configuring a safe screen and nonsecret input fields.
The generated scripts default to \`enabled=false,confirmed=false\`. Merely
changing \`enabled\` without confirmation does **not** send touches.

**Color reliability improvements:**

- \`getColor\` must return RGB 0–255 and consistent \`packed\` RGB.
- \`matchColor\` cannot report PASS if its observed color exceeds the requested
  tolerance, even if its Boolean response says true.
- A 1-pixel \`findColor\` must return both the requested coordinate and RGB
  inside the specified tolerance; wrong values cause FAIL instead of a false
  positive.
- Vision compares its frozen frame's pixel dimensions against \`nk.screen()\`
  **without recapturing**. Screen/rotation/scale disagreement is WARN, not a
  false PASS. OCR and optional template recognition still share one frame.

Fast CI:
- \`tests/test_v0716_reliability_report.py\`: timing aggregates,
  deterministic mock clock and double opt-in confirmation.
- \`tests/test_v0716_color_accuracy.py\`: wrong-color false positives and
  one-frame/screen dimension disagreement.
- Previous Lua Test Lab and command-contract regressions remain in the same
  Ubuntu-only workflow.

**Still not performed:** Xcode/Theos compile, on-device pixel precision
measurement, gesture visual verification, or Sileo publication. User requested
that all current commands be hardened before a consolidated build.


## Consolidated hardening batch — 5 November 2026

The v0.7.16-dev code batch now includes, alongside the seven original groups:

1. **Native Touch preflight:** malformed tap coordinates and *both* swipe endpoints
   are refused before opening the touch socket. This is backed by a host-compiled
   \`nkcore\` Lua module test. It is NOT evidence of accurate UIKit gesture replay.
2. **Coordinate/Retina audit:** \`nkcoords.screen\`, \`point\`, \`path\` and
   \`inspectFrame\` only accept explicit units/bounds. Point-to-pixel conversion
   requires an explicitly supplied scale; screenshot size and screen size
   mismatches trigger warnings, never automatic rotation/rescaling.
3. **Color/Vision integrity:** Test Lab verifies packed RGB, observed channel
   tolerances, exact 1×1 search position and frame-vs-screen geometry. One
   immutable Vision frame is still reused across color/OCR/template checks.
   No-match / nonfinite native image replies no longer masquerade as hits.
4. **Long-run guardrails:** \`nkstability.pollRead\` retries only explicitly
   read-only probes, with a monotonic clock, deadlines, attempt caps and
   transient-error classification. \`sampleRead\` measures up to 30 safe
   read probes; it requires an actual native monotonic clock for device timing.
   Interactive HID and text actions never get automatic retries.
5. **Regression comparison:** \`nkregression.compare\` detects check status
   deterioration, missing tests and native monotonic timing drift. Test Lab
   compares against the previous bounded JSON file *before* atomic replacement,
   and includes the result in its report. A check PASS is not equivalent to
   visible automation success. Regression comparisons are diagnostic only.
6. **Release readiness review:** \`scripts/check-v0716-readiness.py\` returns
   \`BLOCKED\` until there is user-recorded on-device evidence for the seven
   groups and a separate human review. This script cannot publish anything.

### Developer verification

The development-only GitHub workflow
\`validate-v0716-testlab.yml\` runs Linux Lua 5.4, gcc native-module preflight
checks and the existing regression suite. The native module is compiled
for the CI Linux host **only**, never as an iOS package.

Run the key checks locally with a Linux Lua 5.4 environment:

\`\`\`sh
lua tests/lua_v0716_coords_stability.lua
lua tests/lua_v0716_regression.lua /tmp/nktestlab-regression.json
python3 -m unittest tests/test_v0716_native_preflight.py -v
python3 -m unittest tests/test_v0716_testlab_runner.py -v
python3 scripts/check-v0716-readiness.py
\`\`\`

### Remaining blockers (must NOT be marked PASS in source-only tests)

- iOS/UIKit final compilation of Test Lab UI has not yet happened.
- Actual device foreground/screen-size calibration and physical HID touch accuracy.
- Live screenshot RGB/camera compression effects, Vision OCR and template hit accuracy.
- Real InputText focus/confirmation in target applications other than tested Notes.
- Long-duration memory, stop, task-kill, interrupted IPC and foreground-switch behavior.
- User review of all seven group results on their own iPhone.

The existing Sileo release is **v0.7.15**. This dev branch has no v0.7.16
build workflow, release-ready marker, or Sileo publisher.
