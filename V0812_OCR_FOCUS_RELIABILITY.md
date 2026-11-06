# NKTouch v0.8.12 OCR State + Native Focus Reliability

Candidate based on the existing v0.8.11 Vision State branch.

## Included

- v0.8.11 Vietnamese OCR normalization and bounded stable-label wait.
- v0.8.12 bounded native first-responder state wait.
- Test Lab examples are read-only: no app launch, tap, typing, or mutation.
- The existing Input Engine remains the only input dispatcher. Its one-shot safeguards are preserved.

## Validation

- Host tests cover stable focus, unstable focus, unknown focus, invalid options, and no-action behavior.
- The device sample requires the user to open Notes and focus a text field manually.
- Candidate deb must be built from the pinned v0.8.12 branch; Sileo publication remains separate.
- Device validation is pending.
