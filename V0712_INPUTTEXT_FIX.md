# NKTouch v0.7.12 — inputText compatibility fix

## Why inputText appeared broken in v0.7.11

The regular \`nk.inputText(value)\` alias still pointed to the legacy
\`nk.text\` transport, while the Unicode-safe native path had a different
entrypoint: \`nk.inputTextV2(value)\`. Editor-run scripts also did not
automatically register the unqualified AutoTouch global \`inputText\`,
despite the target-app bootstrap already importing \`nktouch\`.

## Fix

- \`nk.inputText(text)\` now delegates to \`nk.inputTextV2(text)\` by default.
- \`inputText(text)\` works in scripts launched from NKTouch's Lua Editor
  because the bootstrap calls \`nk.installAutoTouchCompat()\` before
  loading the user script.
- \`nk.inputTextV2(text,{mode="keyboard"})\` remains an explicit option
  when direct first-responder insertion isn't supported by the app.
- \`nk.text(text)\` and \`nk.legacyInputText(text)\` keep access to the
  old transport for deliberate compatibility use. They are never used
  as an automatic fallback after a failed/unverified input.
- The return of \`inputText\` confirms dispatch, **not** acceptance by
  the target application's text field. Password input remains unverified.
- Only ordinary nonsecret test strings should be used: cross-process
  distributed notifications are not a confidential password channel.

## Reproduce / test on device

\`\`\`lua
local nk=require("nktouch_v7")
nk.tap(200,300) -- select an editable text field, adapt coordinates
nk.sleep(500)
local ok,meta,code=nk.inputText("Xin chao NKTouch")
print("inputText:",ok,meta and meta.status or meta,code)

-- Global-style call also works from the NKTouch editor:
-- inputText("Xin chao")
\`\`\`

If the command prints \`dispatched\` but the field stays empty, the target
app may not have a focused UIKeyInput view or the injected receiver may not
be active. Try \`nk.inputTextV2("test",{mode="keyboard"})\` **only after**
checking the field is empty to avoid duplicate text. Capture the Task Center
log and target app/iOS version for deeper receiver debugging.

The version is a build-tested candidate until confirmed on-device.
