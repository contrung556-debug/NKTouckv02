# NKTouch v0.7.14 — Apple Notes screen format hotfix

## Regression observed on iPhone

The built-in 0.7.13 Notes inputText test stopped before opening Notes:

    [NKINPUT][NOTES][SCREEN] OK
    SCREEN_FORMAT: ... nk.screen(): 750.000000;;1334.000000

The 0.7.13 Lua example only recognized integer-formatted values such as
\`750;;1334\`. The native \`nk.screen()\` returns pixel dimensions as
decimal-formatted text on some devices, for example
\`750.000000;;1334.000000\`.

This was a **test script parsing bug**, not evidence that text insertion
failed. No inputText command had executed in the provided failed run.

## Changes

- Corrected Lua dimension parser to accept both integer and decimal numeric
  values in \`width;;height\` format, whitespace and strict separators.
- Added regression coverage for real \`750.000000;;1334.000000\`,
  \`390;;844\`, malformed values, and mock Notes automation sequence.
- Added updated built-in template \`test_inputtext_notes_v2.lua\`.
- The 0.7.13 \`test_inputtext_notes.lua\` remains unchanged. To respect user
  edits, a separate v2 script is copied on first open of Lua Workspace.
- **Samples** points to the fixed v2 template; first-install target is
  **Apple Notes** (Bundle ID \`com.apple.mobilenotes\`).
- No change to the native inputText engine or touch backend in this release.

## Retest on device

Update NKTouch to v0.7.14. Open Notes to the *notes list* first (not an
important existing note), then open NKTouch → Lua Workspace → Samples →
\`test_inputtext_notes_v2.lua\` → Chạy. Adjust the two tap positions at
the top of the script if the Notes UI differs by iOS version.

The script should now print \`[NKINPUT][NOTES][SCREEN_SIZE] 750x1334\` and
continue to \`WAIT_APP\`, \`TAP_NEW_NOTE\`, \`TAP_EDITOR\`,
and \`INPUT_TEXT\`. A \`dispatched\` input is not proof the note accepted
the text; check the note itself and OCR result. No automatic retry is used.

The corrected sample is intended to diagnose the next genuine device-level
issue, if any. Never use the test while viewing valuable note contents,
because static tap coordinates vary across screen layout and OS versions.
