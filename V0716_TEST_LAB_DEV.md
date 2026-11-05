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
