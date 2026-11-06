# NKTouch Roadmap — after v0.8.9

## Current baseline
Sileo currently serves v0.8.9. Keep it as the stable rollback point while testing development builds.

## v0.8.10 — Runtime Self-Test (artifact built; device validation pending)
- Add an in-app, read-only Lua sample that checks module load, runtime, screen dimensions, sleep, io.popen output and process exit status.
- Optionally run only `cranectl --list com.facebook.Facebook`; never create or switch a container.
- The artifact-only rootless candidate built successfully. Install it on the iPhone and collect the `[NKRT810]` log.
- Release gate: confirm runtime checks and repeat the failing second-loop UI scenario before considering Sileo.

## v0.8.11 — Vision and UI-state reliability (source work in progress)
- Add Vietnamese OCR normalization and a bounded stable-label wait; the sample logs state labels and counts, never recognized text.
- Validate OCR regions against current screen geometry and fail closed on ambiguous labels.
- Keep color verification tied to screen evidence; verify behavior against real app screens before packaging.

## v0.8.12 — Touch and InputText reliability
- Check focus and dispatch result, preserve at-most-once input behavior, and report field-level verification clearly.
- Cover Unicode and transitions between consecutive form fields without blind retry.
- Keep tests safe by default; explicit opt-in for real touches.

## v0.9.0 — Smart Lua Engine
- Add a small state-driven runner that combines existing Vision, Touch, and Input APIs.
- Require explicit allowed actions, bounded retries, deadlines, and clear stop states.
- Start with user-authored scripts and deterministic rules; keep AI planning optional and reviewable.

## v0.9.x — Script Studio and diagnostics
- Improve sample browsing, logs, error explanations, and export/import.
- Add a dry-run/inspection mode before expanding automation behavior.

## v1.0 — Stability release
- Freeze public API and package format after compatibility review.
- Require repeated on-device regression runs, install/upgrade/rollback checks, and documented limits.

No development candidate is published to Sileo until the iPhone release gate passes.
