# NKTouch v0.7.2 Script Editor

NKTouch V7 stays script-first. V7.0 added the single-active-task supervisor, V7.1 added Recorder V2, and V7.2 adds an on-device Script Editor workspace so scripts can be created, checked, inspected, edited, completed from the local API catalog, and launched without a computer.

```text
Recorder V2 -> Lua script -> Script Editor -> Task Engine -> hardened Lua runtime -> nkcore -> SpringBoard core
```

## V7.2 adds

- `nktouchctl editor ...` and alias `nktouchctl script ...`
- Managed scripts under `/var/mobile/Library/NKTouch/scripts`
- Safe script names that cannot escape the managed workspace
- Starter templates: `blank`, `tap`, `image`, `color`, `ocr`
- Mandatory `luac` syntax validation before a managed script is executed
- Syntax validation after generated templates, imports, snippets, and append edits
- Automatic rollback of append/snippet edits if they introduce Lua syntax errors
- Local searchable NKTouch API catalog; no network required
- Prefix completion with `editor complete`
- Ready-to-paste examples with `editor snippet`
- Run/status/pause/resume/stop/logs controls delegated to the proven V7.0 task engine
- Interactive editing through `nano`, `micro`, `vim`, or `vi` when one is already installed
- Recorder V2 and all previous native APIs retained unchanged
- OCR remains explicit/on-demand only; the editor does not run OCR in the background

## Versions

```text
NKTouch package/runtime: 0.7.2
Script Editor:           0.7.2
Recorder V2:             0.7.1 retained
Task engine:             0.7.0 retained
V6.4 Lua API:            retained
Native CLI:              0.6.0
Embedded nkcore:         0.6.3
Bundled Lua:             5.4.9
```

## First script

Create a blank script:

```sh
nktouchctl editor new demo blank
```

Or start from a template:

```sh
nktouchctl editor new image-test image
nktouchctl editor new color-test color
nktouchctl editor new ocr-test ocr
```

Inspect and syntax-check:

```sh
nktouchctl editor show demo
nktouchctl editor check demo
```

If `nano`, `micro`, `vim`, or `vi` is installed:

```sh
nktouchctl editor edit demo
```

The editor automatically checks syntax again when the interactive editor exits.

## API help and completion

List the local API catalog:

```sh
nktouchctl editor api
```

Search by API name, signature, category, or description:

```sh
nktouchctl editor api image
nktouchctl editor api swipe
nktouchctl editor api clipboard
```

Prefix completion:

```sh
nktouchctl editor complete nk.wait
nktouchctl editor complete nk.tap
```

Print a ready-to-paste example:

```sh
nktouchctl editor snippet tap
nktouchctl editor snippet waitImage
```

Append a catalog snippet to a managed script and syntax-check it immediately:

```sh
nktouchctl editor snippet tap demo
```

## Quick editing without a text editor

Append one Lua line:

```sh
nktouchctl editor append demo 'must(nk.tap(120, 450))'
```

If the appended line causes a syntax error, V7.2 restores the previous script automatically.

Clone or import scripts:

```sh
nktouchctl editor clone demo demo-copy
nktouchctl editor import /var/mobile/Library/NKTouch/recordings/my-flow.lua recorded-flow
```

Delete requires an explicit flag:

```sh
nktouchctl editor delete demo-copy --yes
```

## Run controls

Run a managed script:

```sh
nktouchctl editor run demo --timeout 30
```

Inspect or control the current task:

```sh
nktouchctl editor status
nktouchctl editor pause
nktouchctl editor resume
nktouchctl editor logs
nktouchctl editor stop
```

V7.2 checks the Lua syntax before handing the script to `nktask`. The V7.0 rule still applies: only one screen-control task can be active at a time.

## Recorder V2 workflow retained

```sh
nktouchctl recorder start
# perform taps / holds / swipes
nktouchctl recorder stop my-flow
nktouchctl editor import /var/mobile/Library/NKTouch/recordings/my-flow.lua my-flow
nktouchctl editor check my-flow
nktouchctl editor run my-flow --timeout 30
```

Recorder V2 continues to replay keyboard input as the physical taps that were recorded instead of guessing semantic characters.

## Health check

```sh
nktouchctl backend
nktouchctl doctor full
nktouchctl selftest
nktouchctl editor doctor
nktouchctl recorder doctor
nktouchctl task doctor
```

Expected V7.2 backend adds an editor line while retaining the older layers:

```text
runtime=0.7.2
task-engine=0.7.0
recorder=0.7.1
editor=0.7.2
```

## State paths

```text
/var/mobile/Library/NKTouch/scripts      managed Script Editor workspace
/var/mobile/Library/NKTouch/tasks        task state/history/logs
/var/mobile/Library/NKTouch/recorder     active recorder marker/state
/var/mobile/Library/NKTouch/recordings   Recorder V2 generated Lua scripts
```

## Safety choices

- Managed script names reject path separators and traversal-like names.
- Generated/imported scripts are syntax-checked before they enter normal run flow.
- Side-effecting native actions remain non-retryable by the direct Lua runtime.
- API help/completion is local metadata and does not execute a script.
- OCR templates are examples only; OCR runs only when the user explicitly executes a script that calls `nk.ocr` or `nk.waitText`.
- V7.2 does not expose arbitrary shell execution through the editor command set.

## Existing V6.4 capabilities retained

- Tap / hold / swipe
- App launch / foreground / wait-app
- Text / keyboard / cursor / delete / paste / clipboard
- Screenshot
- Image matching and tap-image
- Color read/search/wait/tap
- Explicit OCR and wait-text
- Direct embedded `nkcore`
- Bounded retry for safe read-only operations
- `doctor`, `selftest`, `benchmark`, `stress`

## Roadmap after V7.2

- V7.3 Import/export task bundles
- V7.4 HTTP/HTTPS + JSON networking
- Later: richer visual script UI once the script/recorder/task foundation is proven on real devices

## Build

Branch:

```text
v0.7.2-script-editor
```

Artifact:

```text
NKTouch-v0.7.2-script-editor-rootless
```

Package:

```text
com.nk.nktouch_0.7.2_rootless.deb
```

## Protocol safety

V7.2 allocates no new SpringBoard task IDs. Recorder remains `14`/`15`, OCR remains `27`, prompt input remains `29`, and screenshot remains `30`.

## License

NKTouch/ZXTouch code remains GPL-3.0 with upstream attribution retained. Bundled Lua 5.4.9 keeps its upstream license notice in the package.
