# NKTouch v0.7.16-dev — Consolidated 7-Group Reliability Batch

> **DEV ONLY:** Source changes and Linux/host regression tests. No iOS IPA,
> no rootless .deb, and no Sileo publication. Public Sileo remains v0.7.15.
> Device-accuracy claims MUST wait for real iPhone Test Lab evidence.

## Summary — one development batch

| Group | Implementation improvements | Automated evidence | Required iPhone verification |
|---|---|---|---|
| **Touch** | Validate tap and both swipe endpoints **before** sending TOUCH_DOWN; require explicit physical-screen bounds; opt-in gestures require foreground bundle and confirmation | Host-compiled \`nkcore\` malformed-coordinate tests; \`nkcoords\` boundary/Retina tests; Test Lab mocks | Tap/hold/swipe/path positions, actual pixel-vs-point/orientation, no duplicate touches |
| **InputText** | Native v2 dispatch cannot silently fall back/retry; uncertainty from native exceptions returns DISPATCH_UNCERTAIN; OCR/sleep exceptions return UNVERIFIED after only one dispatch; secure password OCR disallowed | \`lua_v0716_input_json_hardening.lua\` (Vietnamese, emoji, Unicode combining characters, 8192-byte boundary, invalid UTF-8, secret/OCR guard, exactly one dispatch) | Text appears once in multiple applications, focus/keyboard, password field tests using **dummy** text |
| **Color** | Validate packed RGB, observed tolerance, exact 1×1 position, reject bogus color and no-match replies | \`test_v0716_color_accuracy.py\`, native test preflight, existing CLI parser tests | Compare physical RGB with reference on static and moving screens |
| **Vision** | One immutable snapshot reused across pixel searches, OCR and optional template search; always close frame; remove temporary screenshot even on callback or decoding error | \`lua_v0716_vision_lifecycle.lua\` checks capture count, auto-close and no temp leaks | JPEG color variance, OCR quality, image matching false positives, memory under longer sessions |
| **Lua Runtime / Task** | Explicit read-only retry and monotonic deadlines; bounded optional 20–1000 screen-read stress; idle cleanup and stop/timeout handling exercised in an isolated native supervisor | \`test_v0716_task_supervisor_host.py\` runs actual **Linux-host** nktask success/stop/timeout/idle flows, \`lua_v0716_coords_stability.lua\` | On-device worker stop/pause/resume, interrupted IPC and long-run stability/RAM |
| **HTTP & JSON** | URL/header/control validation (reject NUL, CR/LF, nonfinite or fractional limits); downloads use unique sibling temp files and atomically replace only on **HTTP 2xx**. Existing files survive transport failures and 404 responses. JSON rejects invalid UTF-8, duplicate keys, oversized inputs and overflow numbers. | \`lua_v0716_http_atomic.lua\` simulates failing/success HTTP helper without real network; \`lua_v0716_input_json_hardening.lua\` | Real HTTPS/TLS, deadlines, uploads and large payload behavior with non-secret test content |
| **Test Lab** | Seven-group selectable UI, safe default, per-test PASS/FAIL/WARN/SKIP, measured durations, atomic JSON report, explicit coverage and previous-run regressions | \`test_v0716_testlab_runner.py\`, \`test_v0716_reliability_report.py\`, \`lua_v0716_regression.lua\`, UIKit staging fixture tests | Full UI compile, Sileo update only after release gate, seven group results on physical iPhone |

## Release gate

Run \`python3 scripts/check-v0716-readiness.py\`. Expected **state=BLOCKED**
until the user has personally verified the seven group results on a rootless
iPhone. Even when all evidence exists, a separate release review is required.
The readiness script cannot build/publish by itself.

### Quality-policy details

1. **Never infer actual touch success from a native dispatch ACK.**
   Verify target UI state separately.
2. **Never retry uncertain mutations automatically** (tap, hold, swipe, text,
   password, uploads/POST). Polling retries are reserved for explicitly
   read-only probes and are capped by attempts and wall-clock bounds.
3. **No automatic Retina conversion.** Physical pixels are the canonical
   coordinate unit; point-to-pixel transformation needs an explicit scale.
4. **A successful subset is not proof all 81 APIs passed.** The catalog is
   checked for source coverage, but device evidence remains pending.
5. **Never overwrite user-edited Lua scripts.** The Test Lab creates unique
   filenames. Report replacement is atomic and explicitly marked diagnostic.
6. **Do not use live account passwords in tests.** Nonsecret sample text only.

## Fast validation

- Workflow: \`.github/workflows/validate-v0716-testlab.yml\` (Linux host only).
- Run status: see \`Actions\` for the latest dev-branch run.
- iOS/UIKit compilation: **not performed**.
- .deb build: **not performed**.
- Sileo v0.7.16: **not published**.

After one clean aggregate CI run, prepare **one** iOS release-candidate build
for *device verification*, not an automatic Sileo upload. Publish only after
the device Test Lab and relevant real-world automation flows pass.
