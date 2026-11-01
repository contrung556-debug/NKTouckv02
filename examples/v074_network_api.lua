-- NKTouch v0.7.4 Network/API example
-- This file is an example only. Replace the placeholder URLs before running.
local nk = require("nktouch_v7")

local function must(res, err, kind)
  if not res then
    error((kind or "ERROR") .. ": " .. tostring(err), 0)
  end
  return res
end

-- GET + automatic JSON decode.
local health = must(nk.http.get("https://your-api.example/health", {
  headers = {
    ["Accept"] = "application/json",
  },
  timeout_ms = 10000,
  max_bytes = 1024 * 1024,
  decode_json = true,
}))

print("GET status", health.status, "bytes", health.bytes)
if health.json then
  print("GET JSON", assert(nk.json.encode(health.json)))
end

-- POST a Lua table as JSON.
local created = must(nk.http.post("https://your-api.example/items", {
  name = "demo",
  enabled = true,
  tags = nk.json.array({"ios", "lua"}),
}, {
  headers = {
    ["Accept"] = "application/json",
    ["Authorization"] = "Bearer <token>",
  },
  timeout_ms = 15000,
  max_bytes = 2 * 1024 * 1024,
  decode_json = true,
}))

print("POST status", created.status, "bytes", created.bytes)
if created.json then
  print("POST JSON", assert(nk.json.encode(created.json)))
end
