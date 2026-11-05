# NKTouch v0.8.2 — One-frame OCR IPC Candidate

**Issue proven on iPhone in v0.8.0/v0.8.1:** Three in-process Vision OCR paths return `NSOSStatusErrorDomain:-6662 Failed to create CVPixelBuffer`. The separate live OCR RPC via the existing SpringBoard service returns text. Touch/Color/Memory preflight checks pass; Touch and Input mutation tests were skipped.

## Mechanism

1. `frame` remains an immutable previously captured screenshot.
2. `frame:ocr(x,y,w,h,language)` crops only that frame to the requested rectangle and encodes that crop as bounded JPEG (maximum 1 MiB; no second screenshot).
3. Localhost socket task `31` transfers bounded base64 JPEG + rectangle metadata into the **already used SpringBoard service**.
4. Service decodes JPEG in memory, invokes its existing `VKOcrManager` OCR backend and returns plain recognized text. It never accepts file paths and never captures a new screenshot.
5. `frame:info().ocr_backend` returns `SERVICE_JPEG_SAME_FRAME` on success, `NATIVE_FRAME` if fallback succeeds, or `NONE` before success. Test Lab prints the backend explicitly; no false PASS.
6. If service is missing/unavailable, the existing native OCR paths remain a fallback with honest error reporting. The rest of the Lua API remains unchanged.

## Boundaries and device risk

- The service runs inside SpringBoard as part of the existing rootless tweak. Even a successful CI build cannot guarantee device stability. **Do not auto-publish this experiment to Sileo** until the user has tested and approved it.
- Sending a screenshot region from Lua to the SpringBoard service is within the local device; no external network/upload is used.
- The bridge reads no arbitrary files, writes no JPEG files and does not log OCR contents.
- Maximum JPEG crop: 1 MiB. Maximum base64 input: 1,400,000 characters. Output: at most 16 KiB of UTF-8 text.
- Sileo current v0.8.1 should remain installable, providing an immediate rollback option.

## Suggested iPhone test (read-only)

1. Back up script files and install the artifact-only v0.8.2 beta on a test jailbreak device.
2. **Respring** so the newly compiled service task is loaded in SpringBoard.
3. Display a static page with large legible text (such as the Safari page in the user's test video).
4. Open NKTouch Test Lab, run default 5 core groups; inspect `ocr/frame_ocr`, `ocr/live_ocr`, `ocr/backend_comparison` and `[NKTask][EXIT]`.
5. Expected success: `ocr/frame_ocr PASS ... backend=SERVICE_JPEG_SAME_FRAME`, OCR text length positive, all Memory/Color checks still PASS, `exit_code=0 signal=0` if the test script returns cleanly.
6. If SpringBoard crashes/restarts or UI stops responding, immediately rollback to NKTouch v0.8.1; do **not** continue stress-testing.
7. If the Test Lab reports `backend=NATIVE_FRAME` or `ocr/frame_ocr FAIL`, do not declare the IPC path fixed; inspect the service integration and rootless permissions.

**Note:** PASS from CI only proves source and package integrity, not iPhone OCR correctness or long-term stability.

## Post-log hardening (5 November 2026)

- Fixed service task 31 parsing of newline-terminated base64 IPC frames:
  trim the socket CR/LF terminator before strict base64 decoding. No
  arbitrary unknown-character ignoring.
- Added read-only `nkvision_native.probeCVPixelBuffer(width,height)` to
  separately test 420f allocation in the Lua worker. The result is diagnostic:
  an allocation PASS does **not** establish OCR success, and failure is WARN.
- Exposed opt-in `nk.ocrWithFallback(x,y,w,h,languages)`. First it tries
  OCR on one immutable frame. Only if that path fails may it perform
  separate live-screen OCR, returning metadata
  `{backend="OCR_FALLBACK_LIVE",same_frame=false,recaptured=true}`.
  Calling `frame:ocr()` remains strict and never recaptures.
- Test Lab now distinguishes Frame OCR FAIL from live fallback availability.
  The generated Test Lab script requests foreground NKTouch
  (`com.zjx.zxtouch`) after reporting, even on group failure. It logs a
  restore *request*, not verified visual focus.
- Host-only checks: `tests/test_v0802_ocr_recovery.py` and
  `tests/lua_v0802_ocr_fallback.lua`. Real-device OCR and SpringBoard
  stability are **not** verified; artifact-only build, no Sileo publish.

Expected additional diagnostic output:
`[NKLAB][PASS/WARN] ocr/pixelbuffer_420f_probe ... 420f status=...`
and `[NKLAB][RESTORE] request_accepted ...` or `WARN ...`.

### Second review: upstream behavior and diagnosis

The pinned upstream `pccontrol/SocketServer.xm` already removes CRLF
before handing a null-terminated command to `processTask`; stripping
newlines again in task 31 is defense in depth, **not a proven root-cause fix**.
The upstream `Process.xm` launch command ACK does not validate the
SpringBoard launch return value, so Test Lab now uses a bounded
`nk.waitApp("com.zjx.zxtouch",2200,250)` check before logging
`foreground_verified`; otherwise it logs `request_sent_foreground_unverified`.

The 420f probe compares `plain`, `IOSurface`, and
`IOSurface + MetalCompatibility` allocations, each released
immediately. Test Lab also records CGImage bits-per-pixel/bitmap-info
separately. **CGImage format does not reveal Vision's private internal
CVPixelBuffer allocation attributes.** Pass/fail of these allocation probes
must not be reported as successful text recognition.

`ocrWithFallback()` preserves `frame_error_code` and, if the original
error contains `NSOSStatusErrorDomain:-6662`, also sets
`frame_error_osstatus=-6662`. A fallback is an intentional, separately
captured live OCR operation and cannot satisfy same-frame OCR tests.

The new IPC task 31 is limited to loopback socket clients; no new remote
OCR endpoint is authorized. Existing rootless package on Sileo is untouched.
This revision needs a **new iOS CI artifact** and on-device verification;
an earlier artifact's successful CI does not validate these later commits.
