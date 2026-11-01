# NKTouch v0.7.1 Recorder V2

NKTouch V7 remains script-first: Lua is the automation language, V7.0 provides the task supervisor, and V7.1 adds a recorder that turns real screen gestures into editable Lua instead of introducing a second automation language.

```text
Recorder V2 -> Lua script -> Task Engine -> hardened Lua runtime -> nkcore -> SpringBoard core
```

## V7.1 adds

- Recorder V2 using the existing HID recorder tasks `14` / `15`
- `nktouchctl recorder start|status|stop|export|latest|list|doctor`
- Raw HID timing converted to `nk.tap`, `nk.hold`, `nk.swipe`, and `nk.sleep`
- Recorder startup delay trimmed; delays between gestures retained
- Tap vs hold classification with movement and duration thresholds
- Swipe duration preserved and bounded by native safety limits
- Generated scripts are normal editable `.lua` files under `/var/mobile/Library/NKTouch/recordings`
- Existing `.bdl` / `.raw` recordings can be exported again without recording a new session
- Fix for the legacy recorder start double-response: Task 14 now has one framed socket response for NKTouch builds
- Keyboard typing is replayed from the physical taps that were recorded; Recorder V2 deliberately does not guess semantic text or keyboard layout
- OCR remains explicit/on-demand only; Recorder V2 never launches OCR

## Versions

```text
NKTouch package/runtime: 0.7.1
Recorder V2:            0.7.1
Task engine:             0.7.0 retained
V6.4 Lua API:            retained
Native CLI:              0.6.0
Embedded nkcore:         0.6.3
Bundled Lua:             5.4.9
```

## Record and replay

Start recording:

```sh
nktouchctl recorder start
```

Perform the taps, long presses, swipes, and keyboard taps you want to capture, then stop and export automatically:

```sh
nktouchctl recorder stop my-flow
```

The generated script is saved as:

```text
/var/mobile/Library/NKTouch/recordings/my-flow.lua
```

Inspect recorder state and recent scripts:

```sh
nktouchctl recorder status
nktouchctl recorder latest
nktouchctl recorder list
```

Export an older recording manually:

```sh
nktouchctl recorder export /var/mobile/Library/ZXTouch/scripts/recording/YYMMDDHHMMSS.bdl recovered-flow
```

Run the exported script through the V7 task engine:

```sh
nktouchctl task start /var/mobile/Library/NKTouch/recordings/my-flow.lua
```

Pause, resume, inspect, or stop it:

```sh
nktouchctl task status
nktouchctl task pause
nktouchctl task resume
nktouchctl task logs
nktouchctl task stop
```

## Generated Lua

Recorder V2 generates normal Lua such as:

```lua
local nk = require("nktouch")

nk.tap(120.0, 300.0)
nk.sleep(500)
nk.swipe(100.0, 700.0, 100.0, 250.0, 320)
```

The exporter keeps inter-gesture timing, classifies stationary long presses as `nk.hold`, and uses a single high-level `nk.swipe` for a recorded drag. Raw point count remains in comments so a future higher-fidelity path recorder can upgrade the same format without breaking scripts.

## Keyboard behavior

The HID recorder sees finger movement, not the semantic character produced by the active keyboard. V7.1 therefore records keyboard typing as the exact screen taps the user performed. It does **not** infer `nk.text("...")`, because doing so would be wrong when the keyboard layout, language, shift state, prediction bar, or third-party keyboard changes.

## Task Engine retained from V7.0

- Native `nktask` supervisor
- Background Lua task execution
- One active screen-control task at a time to prevent competing taps/swipes
- `start`, `status`, `pause`, `resume`, `stop`, `list`, and `logs`
- Optional wall-clock timeout per task
- Timeout does not count paused time
- Lua syntax validation with bundled `luac` before launch
- Per-task state, history, and stdout/stderr logs under `/var/mobile/Library/NKTouch/tasks`
- Side-effecting actions are never automatically retried

## Existing V6.4 capabilities retained

- Tap / hold / swipe
- App launch / foreground / wait-app
- Text / keyboard / cursor / delete / paste / clipboard
- Screenshot
- Image matching and tap-image
- Color read/search/wait/tap
- OCR and wait-text when explicitly called
- Direct embedded `nkcore`
- Bounded retry for safe read-only operations
- `doctor`, `selftest`, `benchmark`, `stress`

## Health check

```sh
nktouchctl backend
nktouchctl doctor full
nktouchctl selftest
nktouchctl task doctor
nktouchctl recorder doctor
```

## State paths

```text
/var/mobile/Library/NKTouch/tasks       task state/history/logs
/var/mobile/Library/NKTouch/recorder    active recorder marker/state
/var/mobile/Library/NKTouch/recordings  generated Lua scripts
```

The underlying GPL recorder still creates its raw `.bdl` bundles in the upstream-compatible ZXTouch recording directory; NKTouch reads those bundles and exports the editable Lua result into the NKTouch state tree.

## Roadmap after V7.1

- V7.2 Script editor: syntax check, autocomplete, run controls, inline API help
- V7.3 Import/export task bundles
- V7.4 HTTP/HTTPS + JSON networking
- Later recorder work can add higher-fidelity curved paths and optional semantic input hooks only when they can be made reliable

A drag-and-drop flow builder remains deferred until the script/task/recorder foundation is proven on real devices.

## Build

Branch:

```text
v0.7.1-recorder-v2
```

Artifact:

```text
NKTouch-v0.7.1-recorder-v2-rootless
```

Package:

```text
com.nk.nktouch_0.7.1_rootless.deb
```

## Protocol safety

V7.1 does not allocate new SpringBoard task IDs. It reuses recorder start/stop `14`/`15`; OCR remains `27`, prompt input remains `29`, and screenshot remains `30`.

## License

NKTouch/ZXTouch code remains GPL-3.0 with upstream attribution retained. Bundled Lua 5.4.9 keeps its upstream license notice in the package.
