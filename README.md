# NKTouch v0.7.4 Network/API

NKTouch V7 remains script-first and on-demand. V7.4 adds native HTTP/HTTPS and JSON APIs for Lua scripts while preserving the V7.0 Task Engine, V7.1 Recorder V2, V7.2 Script Editor, V7.3 Task Bundle format, and the existing V6.4 automation API.

```text
Lua script
  -> nk.http / nk.json
  -> native Foundation HTTP helper
  -> system TLS validation

Lua script
  -> existing nk.* automation API
  -> nkcore / SpringBoard automation core
```

## V7.4 adds

- `nk.http.request(opts)` for explicit HTTP/HTTPS requests
- `nk.http.get(url, opts)`
- `nk.http.post(url, body, opts)`
- `nk.http.download(url, path, opts)`
- `nk.http.upload(url, path, opts)`
- `nk.json.encode(value)` / `nk.json.decode(text)`
- `nk.json.array(table)` / `nk.json.object(table)` to disambiguate empty or tagged tables
- Native iOS Foundation networking; runtime requests do not depend on curl or Python
- Streamed response writes with a hard 32 MiB ceiling
- Request bodies limited to 16 MiB
- Per-request timeout and response-size limits
- HTTP methods: GET, POST, PUT, PATCH, DELETE, HEAD, OPTIONS
- System TLS certificate validation with no trust bypass
- HTTPS redirects are never downgraded to cleartext HTTP
- Cookies are not persisted automatically
- No automatic request retry
- Temporary request metadata is not printed with authorization headers or tokens
- OCR remains explicit/on-demand only

## Versions retained

```text
NKTouch package/runtime: 0.7.4
Network/API:             0.7.4
Task Bundle:             0.7.3 retained
Script Editor:           0.7.2 retained
Recorder V2:             0.7.1 retained
Task Engine:             0.7.0 retained
V6.4 Lua API:            retained
Embedded nkcore:         0.6.3
Bundled Lua:             5.4.9
```

## Load V7.4 from Lua

```lua
local nk = require("nktouch_v7")

assert(nk.NETWORK_VERSION == "0.7.4")
assert(nk.http.VERSION == "0.7.4")
assert(nk.json.VERSION == "0.7.4")
```

The normal `nktouch-lua` runner preloads the V7 wrapper, so managed scripts keep the existing `nk.*` API and also gain `nk.http` and `nk.json`.

## GET JSON

```lua
local nk = require("nktouch_v7")

local res, err, kind = nk.http.get("https://your-api.example/health", {
  headers = {
    ["Accept"] = "application/json",
  },
  timeout_ms = 10000,
  max_bytes = 1024 * 1024,
  decode_json = true,
})

if not res then
  error((kind or "NETWORK") .. ": " .. tostring(err))
end

print("HTTP", res.status)
if res.json then
  print(nk.json.encode(res.json))
end
```

## POST JSON

Passing a Lua table as the second argument to `nk.http.post` sends JSON and automatically adds `Content-Type: application/json` unless the caller already supplied a content type.

```lua
local nk = require("nktouch_v7")

local res, err, kind = nk.http.post("https://your-api.example/items", {
  name = "demo",
  enabled = true,
  tags = nk.json.array({"ios", "lua"}),
}, {
  headers = {
    ["Accept"] = "application/json",
    ["Authorization"] = "Bearer <token>",
  },
  timeout_ms = 15000,
  decode_json = true,
})

if not res then
  error((kind or "NETWORK") .. ": " .. tostring(err))
end

print("HTTP", res.status, "bytes", res.bytes)
```

## Generic request

```lua
local res, err, kind = nk.http.request({
  url = "https://your-api.example/items/123",
  method = "PATCH",
  headers = { ["Accept"] = "application/json" },
  json = { enabled = false },
  timeout_ms = 15000,
  max_bytes = 2 * 1024 * 1024,
  decode_json = true,
})
```

`body`, `json`, and `body_file` are explicit request-body choices. `body` and `json` cannot be combined, and `body_file` cannot be combined with either of them.

## Response object

Successful transport returns a response table even for HTTP error statuses:

```text
res.ok            true for HTTP 2xx/3xx
res.status        HTTP status code
res.bytes         response body bytes written
res.content_type  MIME type when available
res.url           final URL after allowed redirects
res.body          response body for in-memory requests
res.json          decoded JSON when decode_json=true
res.path          destination path for download requests
```

Transport, validation, file, limit, and JSON failures return:

```lua
nil, message, kind
```

The `kind` value identifies categories such as `INVALID`, `IO`, `LIMIT`, `JSON`, `EXISTS`, or `NETWORK`.

## Download and upload

```lua
local nk = require("nktouch_v7")

local r1 = assert(nk.http.download(
  "https://your-api.example/file.bin",
  "/var/mobile/Library/NKTouch/file.bin",
  { max_bytes = 32 * 1024 * 1024 }
))

local r2 = assert(nk.http.upload(
  "https://your-api.example/upload",
  "/var/mobile/Library/NKTouch/file.bin",
  { method = "PUT", headers = { ["Content-Type"] = "application/octet-stream" } }
))
```

Downloads do not overwrite an existing destination unless `overwrite=true` is explicitly set.

## Local health check

V7.4 does not make a background or external probe during doctor checks.

```sh
nktouchctl network doctor
nktouchctl network version
nktouchctl backend
nktouchctl doctor full
nktouchctl selftest
```

The network doctor reports the local helper state, system TLS validation mode, and on-demand behavior only.

## Existing V7 workflow retained

```sh
# Recorder V2
nktouchctl recorder start
nktouchctl recorder stop my-flow

# Script Editor
nktouchctl editor import /var/mobile/Library/NKTouch/recordings/my-flow.lua my-flow
nktouchctl editor check my-flow

# V7.3 bundle
nktouchctl bundle export my-flow /var/mobile/Library/NKTouch/my-flow.nktask

# Run through the Task Engine
nktouchctl editor run my-flow --timeout 30
```

Only one screen-control task can be active at a time. Network calls occur only when the running Lua script calls `nk.http`.

## Security choices

- System trust validation is used for HTTPS; V7.4 contains no certificate/trust bypass.
- HTTPS redirects cannot downgrade to HTTP.
- Request headers and bearer/API tokens are not echoed by the network wrapper.
- Cookies are not persisted automatically by the Foundation session.
- Response size and request body size are bounded.
- No automatic retry is performed, which avoids repeating side-effecting POST/PATCH/DELETE requests unexpectedly.
- OCR is not coupled to networking and remains explicit/on-demand only.

## Protocol safety

V7.4 allocates no new SpringBoard task IDs. Existing protocol IDs remain unchanged, including recorder start/stop `14`/`15`, OCR `27`, prompt input `29`, and screenshot `30`.

## Build

Branch:

```text
v0.7.4-network-api
```

Artifact:

```text
NKTouch-v0.7.4-network-api-rootless
```

Package:

```text
com.nk.nktouch_0.7.4_rootless.deb
```

The V7.4 workflow compiles the native HTTP helper for iOS arm64, smoke-tests JSON and the Lua network wrapper, runs retained V7 contract tests, builds the iOS app, and produces the rootless package.

## License

NKTouch/ZXTouch code remains GPL-3.0 with upstream attribution retained. Bundled Lua 5.4.9 keeps its upstream license notice in the package.
