# NKTouch v0.7.8 — Lua Core Self-Test

Adds real on-device Lua API diagnostics while retaining v0.7.7 Color Engine
and v0.7.6 Recorder.

## Run inside NKTouch
From the Lua Workspace dashboard choose **Core Self-Test**.
The existing single-active-task supervisor runs the test. The app displays a
summary based on the actual task result and [NKCORE][SUMMARY] status=PASS.
Full per-API PASS, FAIL, WARN and SKIP entries are available in Task Center logs.

Read-only default tests:
- Lua runtime, direct nkcore availability, IPC ping
- Screen dimensions (physical pixels), orientation, scale, foreground app
- Sleep timing
- getColor validation at a center pixel
- matchColor and findColor in the same physical 1-by-1 pixel region
- waitColorMatch with bounded timeout
- Screenshot capture, size verification and temporary file cleanup

No blind tapping, swiping, holding, recording, app switching or network
requests. The test creates and removes only its own temporary screenshot.

## Terminal usage

    nktouchctl core-selftest
    nktouchctl task status
    nktouchctl task logs

Optional checks are separate and must be explicitly selected:

    nktouchctl core-selftest --ocr --image /var/mobile/Library/NKTouch/assets/template.png

An optional touch test deliberately taps the specified physical-pixel point:

    nktouchctl core-selftest --touch 200 300

Do NOT enable touch checks unless the target is safe. The test confirms
command dispatch, not that the UI handled the touch correctly.

## Interpreting results
- PASS: API returned expected shape/value within the tested contract.
- FAIL: API returned invalid data, backend/transport failed, or a contract broke.
- WARN: display changed between frames, image absent, or touch result not observable.
- SKIP: optional test not requested or its prerequisites were unavailable.

Report contains elapsed milliseconds for each check. Timing is measured with
native monotonic clock where available. Color samples on animated screens
may legitimately change and produce WARN rather than false FAIL.

GitHub Actions runs mock Lua pass/fail tests plus retained CI and rootless
packaging, but cannot prove real-world iPhone pixel/touch accuracy.

Retain v0.7.7 as rollback while validating v0.7.8 on a jailbreak device.
