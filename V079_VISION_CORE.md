# NKTouch 0.7.9 — Vision Core (experimental, opt-in)

## Why

The legacy live getColor, findColor, findImage and OCR APIs may each request
a fresh screen capture. Vision Core instead captures ONE screen JPEG, decodes
it once, and reuses an immutable frame for all these operations. No new
background daemon, IPC command, or SpringBoard hooks.

## Example

    local nk = require("nktouch")
    local frame, err, code = nk.captureFrame()
    assert(frame, tostring(code).." "..tostring(err))

    local info = frame:info()
    local c = frame:getColor(200, 300)
    local hit = frame:findColor(0, 0, info.width, info.height,
                               0, 255, 0, 120, 0, 100, 1)
    local image = frame:findImage("/var/mobile/Library/NKTouch/button.png", 2, 0.8, 0.8)
    local text = frame:ocr(0, 0, info.width, info.height, "")
    frame:close()

Or automatically close the frame, including on callback errors:

    local color, err, code = nk.withFrame(function(frame)
        local info = frame:info()
        return frame:getColor(math.floor(info.width/2), math.floor(info.height/2))
    end)

Existing nk.getColor, nk.findColor, nk.findImage, nk.ocr and screenshot APIs
are UNCHANGED. Nothing caches an old screen implicitly. After a tap, swipe
or screen transition, call nk.captureFrame again.

## Contracts and limitations

- Coordinates are JPEG screenshot physical pixels. No automatic rotation
  mapping. Coordinates may differ from touch positions on rotated screens.
- Screenshot is JPEG. RGB may differ from raw live getColor owing to JPEG
  compression. Multiple reads from the same frame are deterministic.
- findImage uses new bounded normalized grayscale correlation and multiscale
  search. It is not byte-for-byte identical to the retained upstream matcher;
  verify matching precision on a known device target.
- OCR uses Apple's Vision framework on a chosen region of the captured frame.
  Languages are optionally comma-delimited, e.g. "en-US". Empty text is
  returned as an empty string; backend problems are reported explicitly.
- Native raster max 96MB, with additional bounded grayscale, JPEG and
  template buffers. Close frames promptly. There is no global stale cache.
- Temporary screenshot JPEG is removed immediately after loading. Use
  frame:save(path) to save it intentionally.
- Script execution, Recorder V6, v0.7.8.1 hotfix, network API, all legacy
  live-screen behavior and old command protocols are retained.

## Test on iPhone

    nktouchctl vision-selftest
    nktouchctl task status
    nktouchctl task logs

The device smoke test uses exactly one screenshot and verifies pixel
consistency across getColor/findColor/getColor in an immutable frame.
It never taps. Log must contain [VISION][SUMMARY] status=PASS.

## Release protocol

Independent branch v0.7.9-vision-core, workflow build-v079-vision-core.yml.
Retained Python/Lua contract tests + Objective-C cross-compilation + rootless
package checks. NO AUTOMATIC SILEO DEPLOYMENT. Validate pixel, OCR and image
matching on a real jailbroken device before release. Retain 0.7.8.1 rollback.
