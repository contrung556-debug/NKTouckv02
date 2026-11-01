# NKTouch v0.7.0 Script/Task Engine

NKTouch V7 starts with a deliberately small task-management layer instead of inventing a second flow language. Lua remains the automation language; V7.0 makes Lua scripts easier and safer to run, pause, resume, stop, inspect, and reuse.

## Product direction

V7 is script-first:

```text
Recorder (later) -> Lua script -> Task Engine -> hardened Lua runtime -> nkcore -> SpringBoard core
```

Users who know Lua can write scripts directly. Recorder V2 will later generate the same Lua, so beginner and advanced users share one runtime instead of maintaining two automation engines.

## V7.0 adds

- Native `nktask` supervisor
- Background Lua task execution
- One active screen-control task at a time to prevent competing taps/swipes
- `start`, `status`, `pause`, `resume`, `stop`, `list`, and `logs`
- Optional wall-clock timeout per task
- Timeout does not count time while the task is paused
- Lua syntax validation with bundled `luac` before a task is started
- Separate task state and log files under `/var/mobile/Library/NKTouch/tasks`
- Completed task history retained by task ID
- Task stdout/stderr captured to its own log
- Status overlay updates for running/paused/completed/stopped/timeout/failure
- Existing V6.4 hardened direct-Lua runtime retained unchanged
- Existing safety rule retained: side-effecting native actions are never automatically retried
- OCR remains an explicit on-demand API; V7.0 does not run OCR in the background

## Versions

```text
NKTouch package/runtime: 0.7.0
Task engine:             0.7.0
V6.4 Lua API:            retained
Native CLI:              0.6.0
Embedded nkcore:         0.6.3
Bundled Lua:             5.4.9
```

## Task commands

Start a script:

```sh
nktouchctl task start /var/mobile/test.lua
```

Start with a timeout and script arguments:

```sh
nktouchctl task start /var/mobile/test.lua --timeout 3600 -- arg1 arg2
```

Inspect the active task:

```sh
nktouchctl task status
```

Pause and resume:

```sh
nktouchctl task pause
nktouchctl task resume
```

Stop:

```sh
nktouchctl task stop
```

Task history and logs:

```sh
nktouchctl task list
nktouchctl task logs TASK_ID 100
nktouchctl task status TASK_ID
```

`nktask ...` can also be called directly with the same subcommands.

## State model

A task moves through these states:

```text
starting -> running -> success
                  -> failed
                  -> timeout
running -> paused -> running
running/paused -> stopping -> stopped
```

Each task stores:

```text
id
state
script
log
child_pid
started_at
ended_at
timeout_sec
exit_code
signal
```

## Why only one active task?

The restriction is intentional for V7.0. Two scripts controlling the same screen could tap different buttons, type into the wrong field, or fight over the foreground app. Finished task history can contain many tasks, but only one screen-control task may be active.

## OCR policy

OCR is not a service or watcher in V7.0. A script calls it only when needed:

```lua
local text = nk.ocr(100, 200, 500, 120)
```

No task-manager loop automatically invokes OCR. This keeps RAM/CPU use predictable and leaves the decision to script authors.

## Existing V6.4 capabilities retained

- Tap / hold / swipe
- App launch / foreground / wait-app
- Text / keyboard / cursor / delete / paste / clipboard
- Screenshot
- Image matching and tap-image
- Color read/search/wait/tap
- OCR and wait-text when explicitly called
- Direct embedded `nkcore`
- Read-only bounded reconnect/retry
- No automatic retry for side-effecting actions
- `doctor`, `selftest`, `benchmark`, `stress`

## Health check

```sh
nktouchctl backend
nktouchctl doctor full
nktouchctl selftest
nktouchctl task doctor
```

The V7 wrapper reports the task-engine health in addition to the existing V6.4 runtime checks.

## Roadmap after V7.0

- V7.1 Recorder V2: record touch/text/timing and generate Lua
- V7.2 Script editor: syntax check, autocomplete, run controls, inline API help
- V7.3 Import/export task bundles
- V7.4 HTTP/HTTPS + JSON networking

A drag-and-drop flow builder is intentionally deferred until the script/task experience is proven.

## Build

Branch:

```text
v0.7.0-task-engine
```

Artifact:

```text
NKTouch-v0.7.0-task-engine-rootless
```

Package:

```text
com.nk.nktouch_0.7.0_rootless.deb
```

## Protocol safety

V7.0 adds orchestration only. The SpringBoard task IDs remain unchanged, including OCR `27` and screenshot `30`.

## License

NKTouch/ZXTouch code remains GPL-3.0 with upstream attribution retained. Bundled Lua 5.4.9 keeps its upstream license notice in the package.
