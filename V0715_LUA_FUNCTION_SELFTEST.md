# NKTouch v0.7.15 — Batched Lua Function Self-Test

## Goal

A single release after multiple source changes. GitHub Actions no longer performs
a slow iOS/Theos build on every commit to this version branch. It starts only:
- By explicit workflow_dispatch, or
- When the final \`release/v0715-build-ready.txt\` marker is committed.

All source files, tests, scripts, staging code, docs, and publishing code are
prepared *before* the final release marker. This avoids a separate expensive
build for each edit. Successful CI publishes exactly the new rootless deb to the
existing Sileo source; v0.7.14 is preserved as a known prior package.

## Lua Workspace → Samples

The built-in Samples menu has four options:

1. **Core • màu / ảnh / hệ thống** → \`test_core_readonly.lua\`.
   Uses the retained \`nkcore_selftest.lua\` to test native IPC, screen size,
   foreground, orientation, scale, sleep, getColor/matchColor/findColor,
   screenshot, and optional checks. Read-only by default; forced empty CLI
   args prevent accidentally enabling the legacy --touch option.
2. **Vision • 1 ảnh, nhiều phép tìm** → \`test_vision_oneframe.lua\`.
   Calls the retained \`nkvision_selftest.lua\`: one immutable screenshot is
   reused to verify pixel color, exact color search and repeat pixel access.
3. **InputText • thử trên Ghi chú** → \`test_inputtext_notes_v2.lua\`.
   Opens Apple Notes, waits for foreground, taps and sends nonsecret test text.
   It may create a new note. UI positions vary by iOS and need calibration.
4. **Tap / Hold / Swipe • tuỳ chọn** → \`test_gestures_optin.lua\`.
   **Disabled by default.** Edit the script to set \`ENABLE_GESTURES=true\`,
   set the bundle ID and physical-pixel coordinates. Before any touch, it
   validates all fields, screen bounds and foreground app. Commands run once,
   without automatic retry. Test only on your own disposable app screen.

The first install copies each test from
\`/var/jb/usr/share/nktouch/examples/\` into
\`/var/mobile/Library/NKTouch/scripts/\`.
Existing user-edited scripts are **never overwritten**.

Core/Vision test scripts initially bind to Safari as a harmless read-only app
target. The gesture test has NO default app and won't send touches until
the user explicitly configures it.

## Output

- Core: \`[NKCORE][SUMMARY] status=PASS/FAIL\` with PASS/FAIL/WARN/SKIP details.
- Vision: \`[VISION][SUMMARY] status=PASS\` or error.
- Notes: \`[NKINPUT][NOTES][...] INPUT_DISPATCHED / VERIFIED_BY_OCR / UNVERIFIED\`.
- Gestures: \`[NKTEST][PASS|FAIL|SKIP|SUMMARY]\`. Dispatch acknowledgments
  **do not** confirm visual behavior in the target application.

## Efficient development strategy

Lua code under \`/var/mobile/Library/NKTouch/scripts/\` can be edited and
run directly in the app — no rebuild or Sileo update is needed for ordinary
Lua script edits. Rebuild only when changing native APIs, tweak hooks, package
contents, or the NKTouch application UI.

For subsequent development batches, make commits to a release branch with
the heavy build gated by one final ready marker, run fast static/Lua tests
while editing, then publish once when the release candidate is stable.

## Tests

\`tests/test_v0715_lua_selftest.py\` includes:
- Inherited Core/Vision module existence and read-only wrapper checks.
- UI Samples menu staging and per-script user-file preservation.
- Safe-by-default gesture test, opt-in single dispatch, screen pixel bounds,
  foreground checks, and no hidden retries.
- Exact build-trigger restriction to release marker (or manual dispatch).
- Package and version contract checks in the release workflow.

On-device tests are still required to prove real UIKit touch injection works:
CI only checks source contracts, host Lua logic and iOS compilation.
