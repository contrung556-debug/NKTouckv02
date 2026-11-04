# NKTouch 0.7.8.1 — Core Self-Test UI hotfix

The build of v0.7.8 was green, including rootless packaging and artifact upload. An inspection of the on-device Core Self-Test UI revealed a false-failure condition: the overall Self-Test PASS was gated on the status of a general `doctor` command, which also checks optional unrelated recorder, bundle and network components.

This hotfix preserves the real Lua checks, task exit status and `[NKCORE][SUMMARY] status=PASS` requirement, but treats the general Doctor result as **informational**, not as a pass/fail condition for Lua Core reliability.

Changes: `scripts/apply-v078-core-selftest-ui.py`, `scripts/prepare-v0781-core-selftest-hotfix.sh`, contract regression test and GitHub Actions workflow. No changes to touch injection, ColorPicker, the Lua runtime or Recorder.

**Important:** This is one confirmed UI logic issue, not proof that it caused any specific user's on-device failure. Other errors require the iPhone screenshot, Core Self-Test result dialog or Task Center logs to diagnose. CI success checks compilation/packaging and synthetic Lua tests, not full behavior on-device.

Workflow: `.github/workflows/build-v0781-core-selftest-hotfix.yml` on `v0.7.8.1-core-selftest-hotfix`.
