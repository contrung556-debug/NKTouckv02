# NKTouch v0.8.3 — External App Test & OCR IPC (Beta)

**Scope:** a new optional read-only test workflow on top of the v0.8.2 same-frame JPEG OCR IPC candidate. Versioned rootless `.deb` artifact is built in GitHub Actions; not automatically published to Sileo.

## User workflow
1. Open NKTouch → **Test Lab**.
2. Tap **Test ứng dụng khác • 5 lõi** and confirm the read-only privacy warning.
3. Choose Safari, Facebook or another installed target app. If "Không chọn ứng dụng" is selected, test launch is rejected.
4. The existing `nktask` supervisor starts a separate Lua process, then that worker opens the selected app and checks it is foreground. It waits **5 seconds**, checking the bundle ID every second.
5. Five core groups run in the target app: OCR, Color, Touch (preflight only), InputText (preflight only), Memory. The new `opts.external` mode forbids opt-in gestures/input/network.
6. Return to NKTouch → **Test Lab → Báo cáo**, or use **Task Center** for task logs. Report includes expected/observed foreground, stability and actual same-frame OCR backend.

This is **not** a user-interface success guarantee: gestures and typed input are never dispatched in default External App Test. The expected OCR success marker, if the local service works, is `ocr/frame_ocr PASS ... backend=SERVICE_JPEG_SAME_FRAME`.

## Reliability rules
- External tests fail closed if the requested app is not foreground, changes between groups, or is lost during settling.
- The generated script is unique and won't overwrite an existing script.
- The editor and prior `nktouch_v7` Lua API retain their existing behavior.
- OCR contents/screenshots are never copied into the report; only byte counts, backend identifiers, image dimensions, and test status are logged.
- Existing Test Lab is unchanged if external mode is not requested.
- An error in app opening/settling appears in Task Center; a Test Lab report may not yet exist if the worker fails before calling `lab.run`.

## Physical iPhone acceptance
- Verify the selected app stays foreground while NKTouch test executes independently.
- Verify `[NKLAB][EXTERNAL]` shows the correct bundle ID and a stable foreground.
- Verify Color, Memory and preflight checks pass with `signal=0`, and no touch/input side effects.
- Verify the `ocr_backend` and frame OCR result on a known static page, separately from `live_ocr`.
- Return to NKTouch and confirm a new report exists and can be copied.
- If SpringBoard crashes/resprings after installation, downgrade to released v0.8.1; the OCR IPC tweak remains experimental.

**Build CI/source tests cannot certify physical iPhone behavior. Do not auto-publish to Sileo before device validation.**
