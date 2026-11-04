# NKTouch v0.7.10 — Input Engine v2 (experimental)

Input v2 is opt-in. The old nk.inputText and nk.text calls remain unchanged.

## Examples

    local nk=require("nktouch_v7")
    nk.tap(200,300) -- choose the field first
    nk.sleep(350)
    local ok,meta=nk.inputTextV2("Xin chào tiếng Việt 😀\nDòng 2;;được")
    assert(ok, "cannot dispatch text")
    print(meta.status,meta.verified) -- dispatched, false

For a password:

    local ok,meta=nk.inputPassword("Mật_khẩu_rất_dài_123!")
    assert(ok) -- transport accepted; target field still unverified

For visual verification of an ordinary, non-secret field:

    local ok,metaOrError,code=nk.inputTextV2("Xin chào",{
        verify={x=30,y=180,w=400,h=70,expected="Xin chào"},
        settleMs=350
    })
    if not ok then print("Not confirmed:",code) end

Fallback for a focused field that refuses direct UIKeyInput (explicit only):

    nk.inputTextV2("Ví dụ", {mode="keyboard"})

DO NOT run fallback automatically after an unverified dispatch; it may duplicate
partially inserted text. A successful return with status=dispatched only proves
the SpringBoard command accepted the event; it does not establish what the
app actually displayed. OCR can give additional evidence for visible text, but
it is fallible (animations, diacritics, pixel rotation, masked fields).

## What changed

- Task 8 (direct) and Task 9 (explicit keyboard fallback) use base64-encoded
  UTF-8 for the existing CRLF-delimited socket stream, avoiding truncation
  on newlines, emoji or the legacy ';;' delimiter.
- Bound: at most 8192 UTF-8 bytes per request, no NUL, strict UTF-8
  decoding, one dispatch per API call, no automatic retries.
- Foreground-only, focused UIKeyInput receiver; duplicate notifications
  deduplicated by request ID (up to the recent 128 IDs per process).
- Default method uses first responder. Explicit keyboard fallback uses
  UIKeyboardImpl. No clipboard handling in v2.
- Secure mode bypasses OCR and does not log or copy password text.
  Neither the native transport nor the new API deliberately logs payload contents.
- SECURITY LIMITATION: base64 is **not encryption**. The retained upstream
  architecture forwards text through cross-process distributed notifications,
  so this experimental mode is **not a confidential password transport**.
  Avoid production credentials until a scoped/verified recipient IPC exists.
- Opt-in verification with a pixel OCR rectangle; returns UNVERIFIED if
  not confirmed, *without* resending text.

## Limitations

Some custom editors, WKWebView variants, protected fields and apps without
the injected keyboard hook may ignore the notification. The sender cannot
synchronously confirm app-level delivery. Password content is never read
back, so success must be checked manually by the user or application state.
Input focus must be set before calling. No accessibility bypass included.

## Deployment

Build on v0.7.10-input-engine-v2. Verify green CI and use the rootless .deb
artifact for explicit on-device testing. DO NOT automatically publish to Sileo.
Retain v0.7.8.1 as the stable source until tests on iPhone succeed.
