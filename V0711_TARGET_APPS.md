# NKTouch v0.7.11 — User Target Apps (beta)

The user selects the target iOS application for each Lua script. Start should not
fire touch or text commands against the still-open NKTouch editor when no app is configured.

## Usage

1. Open NKTouch -> Lua Workspace -> a script.
2. Tap **Ứng dụng +** in the top-right.
3. Search installed apps and tap the desired app. Optionally tap **+** to enter
   a Bundle ID manually if LaunchServices cannot enumerate it.
4. Press **Chạy**. NKTouch validates syntax and starts an isolated nktask worker.
5. The worker opens the chosen app and waits up to 8 seconds for its Bundle ID
   to become the foreground application. Only then is the Lua script loaded.
6. If activation/foreground verification fails, the task exits before the
   original script executes. See Task Center / Logs for the error.

The target_apps.plist file lives under /var/mobile/Library/NKTouch/ and maps
script filenames to their selected application Bundle ID and name. This is
device-local configuration rather than source code injected into user scripts.

## Architecture and safety

- The user picks an app; there is no implicit selection of the foreground app.
- LaunchServices enumeration is used dynamically; this private iOS API may vary
  across versions, so manual Bundle ID entry is provided as a fallback.
- The syntax-check, nktask, Task Center and Logs contract remains in place.
- A temporary Lua bootstrap under /var/mobile/Library/NKTouch/tmp/targets calls
  nk.openApp, then nk.waitApp, then loadfile(user_script). The bootstrap removes
  itself at the beginning of worker execution (best effort).
- The worker starts before NKTouch is backgrounded, avoiding a UI suspension
  race that could otherwise prevent Lua from ever running.
- Verifying the foreground Bundle ID does not prove an input field is ready.
  Scripts still need to focus fields and verify their own expected UI states.
- Existing Input Engine v2 remains unchanged; no implicit text/tap retries.
- Existing v0.7.10 and v0.7.8.1 branches remain untouched.
- The beta workflow builds a deb artifact only and does NOT publish to Sileo.

## Build and validation

GitHub Actions -> Build NKTouch v0.7.11 Target Apps -> Run workflow.

On a jailbroken device: bind a harmless test script to Safari; press Start;
verify Safari becomes foreground before script actions. Next bind a bogus
Bundle ID and verify no Lua actions execute. Inspect Task Center / Logs.

Experimental until CI and on-device rootless tests confirm full compatibility.
