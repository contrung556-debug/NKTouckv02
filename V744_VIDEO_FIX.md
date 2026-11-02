# NKTouch v0.7.4.4 — Video Check Fix

Device-video fixes over v0.7.4.3:

- App UI syntax Check invokes bundled `luac54` directly.
- App UI Run/Status/Stop/Logs invoke `nktask` directly.
- `nkeditor check` no longer depends on task engine or API catalog.
- UI distinguishes a real Lua syntax error from a checker/runtime launch error.
- Editor uses a compact navigation title while the Scripts library keeps its large title.
- NKTouch tab item explicitly restores normal title/image positioning.
- All v0.7.4.3 shell UX, v0.7.4.1 filters/samples/logs fixes, Network/API, Task Bundle, Recorder V2 and Lua 5.4.9 are retained.
