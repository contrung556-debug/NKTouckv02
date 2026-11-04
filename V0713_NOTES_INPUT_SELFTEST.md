# NKTouch v0.7.13 — Test InputText with Apple Notes

This version includes an editable Lua example in NKTouch itself. The sample is
installed from the package the first time Lua Workspace is opened, and is
accessible either from the script list or via **Samples**.

## On-device usage

1. Update NKTouch to 0.7.13 after the green rootless build is published.
2. Open **Lua Workspace** → **Samples** → \`test_inputtext_notes.lua\`.
3. The sample is automatically associated with Apple Notes
   (\`com.apple.mobilenotes\`) when first installed. If you previously changed
   its target, choose **Ứng dụng +** and select **Ghi chú**.
4. Start the script. NKTouch launches Notes and checks that it is foreground
   before running the script. The script then logs \`SCREEN\`,
   \`OPEN_APP\`, \`WAIT_APP\`, \`TAP_NEW_NOTE\`, \`TAP_EDITOR\` and
   \`INPUT_TEXT\`.
5. It tries to create a new empty test note, focus the body and enter
   \`NKTouch InputText Test 12345\`. The OCR check reports verified or
   unverified; it **never** retries input automatically.

**Important:** Notes UI and toolbar placements vary by iOS, device and current
navigation screen. Open the Notes list view before the test. If the taps are
incorrect, edit the sample's \`NEW_NOTE_X\`, \`NEW_NOTE_Y\`,
\`BODY_X\` and \`BODY_Y\` constants to exact screen coordinates. On different
screens, an incorrect tap could edit an existing note. Don't use this sample
while viewing important note content.

## Diagnostics

- \`OPEN_APP\` error: cannot launch Notes.
- \`WAIT_APP\` error: Notes did not reach foreground within 10 seconds.
- \`SCREEN_FORMAT\` error: screen coordinates cannot be inferred; report the
  raw \`nk.screen()\` value.
- \`TAP_NEW_NOTE\` or \`TAP_EDITOR\` error: touch dispatch failed.
- \`INPUT_TEXT\` error: native text transport failed.
- \`INPUT_DISPATCHED\` with \`UNVERIFIED\`: text was dispatched but not
  confirmed inside Notes (possibly no focused editable view, different UI,
  inactive keyboard receiver, or OCR misread).

The regular \`nk.inputText\` uses Input Engine v2 from v0.7.12; successful
dispatch only acknowledges the command, not text appearance in the app.
The example uses a public nonsecret test string, not credentials.

## Engineering notes

- Packaged template: \`/var/jb/usr/share/nktouch/examples/test_inputtext_notes.lua\`.
- User-editable copy: \`/var/mobile/Library/NKTouch/scripts/test_inputtext_notes.lua\`.
- The app installs the example only if missing; it does not overwrite edits.
- The only automatic target assignment is for the freshly installed sample.
- Retains v0.7.11 target-app bootstrap and v0.7.12 inputText fix.
- CI includes host Lua mock tests verifying step order and fail-closed behavior.
- The iPhone test remains necessary: CI does not emulate Notes' actual UI.
