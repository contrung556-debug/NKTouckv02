local VERSION = "0.7.3"
local MAGIC = "NKTASK1"
local MAX_FILES = 128
local MAX_FILE = 16 * 1024 * 1024
local MAX_TOTAL = 32 * 1024 * 1024
local MAX_SCRIPT = 1024 * 1024

local function die(msg, code)
  io.stderr:write("NKBundle: " .. tostring(msg) .. "\n")
  os.exit(code or 1)
end

local function safe_name(s)
  if type(s) ~= "string" or s == "" or #s > 80 then return false end
  if s:sub(1,1) == "." or s:find("..", 1, true) then return false end
  return s:match("^[A-Za-z0-9][A-Za-z0-9._%-]*$") ~= nil
end

local function safe_asset(s)
  if type(s) ~= "string" or s == "" or #s > 120 then return false end
  if s:sub(1,1) == "." or s:find("..", 1, true) then return false end
  return s:match("^[A-Za-z0-9][A-Za-z0-9._%-]*$") ~= nil
end

local function basename(path)
  return (path:gsub("/+$", ""):match("([^/]+)$"))
end

local function read_file(path, limit)
  local f, err = io.open(path, "rb")
  if not f then return nil, err end
  local data = f:read("*a")
  f:close()
  if not data then return nil, "read failed" end
  if #data > (limit or MAX_FILE) then return nil, "file too large" end
  return data
end

local function fnv1a(data)
  local h = 2166136261
  for i = 1, #data do
    h = ((h ~ data:byte(i)) * 16777619) & 0xffffffff
  end
  return string.format("%08x", h)
end

local function parse_header(f)
  local magic = f:read("*l")
  if magic ~= MAGIC then return nil, "bad magic" end
  local name_line = f:read("*l")
  local version_line = f:read("*l")
  local files_line = f:read("*l")
  local blank = f:read("*l")
  if not name_line or not version_line or not files_line or blank ~= "" then return nil, "truncated header" end
  local name = name_line:match("^name=(.+)$")
  local version = tonumber(version_line:match("^version=(%d+)$"))
  local count = tonumber(files_line:match("^files=(%d+)$"))
  if not safe_name(name) then return nil, "invalid bundle name" end
  if version ~= 1 then return nil, "unsupported bundle version" end
  if not count or count < 1 or count > MAX_FILES then return nil, "invalid file count" end
  return {name=name, version=version, count=count}
end

local function valid_entry_path(path)
  if path == "script.lua" then return true end
  local asset = path:match("^assets/([^/]+)$")
  return asset and safe_asset(asset) or false
end

local function read_entry(f, total)
  local line = f:read("*l")
  if not line then return nil, "truncated entry header" end
  local path, size_s, hash = line:match("^ENTRY\t([^\t]+)\t(%d+)\t([0-9a-fA-F]+)$")
  local size = tonumber(size_s)
  if not path or not size or #hash ~= 8 then return nil, "invalid entry header" end
  if not valid_entry_path(path) then return nil, "unsafe entry path: " .. tostring(path) end
  local limit = path == "script.lua" and MAX_SCRIPT or MAX_FILE
  if size < 0 or size > limit then return nil, "entry too large: " .. path end
  if total + size > MAX_TOTAL then return nil, "bundle exceeds total size limit" end
  local data = f:read(size)
  if not data or #data ~= size then return nil, "truncated entry data: " .. path end
  local nl = f:read(1)
  if nl ~= "\n" then return nil, "missing entry terminator: " .. path end
  local got = fnv1a(data)
  if got:lower() ~= hash:lower() then return nil, "checksum mismatch: " .. path end
  return {path=path, size=size, hash=got, data=data}, nil, total + size
end

local function load_bundle(path, keep_data)
  local f, err = io.open(path, "rb")
  if not f then return nil, err end
  local meta, herr = parse_header(f)
  if not meta then f:close(); return nil, herr end
  local entries, seen, total, script_count = {}, {}, 0, 0
  for _ = 1, meta.count do
    local e, eerr, new_total = read_entry(f, total)
    if not e then f:close(); return nil, eerr end
    total = new_total
    if seen[e.path] then f:close(); return nil, "duplicate entry: " .. e.path end
    seen[e.path] = true
    if e.path == "script.lua" then script_count = script_count + 1 end
    if not keep_data then e.data = nil end
    entries[#entries+1] = e
  end
  if script_count ~= 1 then f:close(); return nil, "bundle must contain exactly one script.lua" end
  if f:read(1) ~= nil then f:close(); return nil, "unexpected trailing data" end
  f:close()
  meta.entries, meta.total = entries, total
  return meta
end

local function pack(args)
  local name, script, out = args[1], args[2], args[3]
  if not safe_name(name) then die("invalid bundle name", 2) end
  if not script or not out then die("usage: nkbundle.lua pack <name> <script.lua> <out.nktask> [asset ...]", 2) end

  local files = {}
  local script_data, err = read_file(script, MAX_SCRIPT)
  if not script_data then die("script read failed: " .. tostring(err), 5) end
  files[#files+1] = {path="script.lua", data=script_data}

  local seen, total = { ["script.lua"] = true }, #script_data
  for i = 4, #args do
    local path = args[i]
    local base = basename(path or "")
    if not safe_asset(base) then die("unsafe asset name: " .. tostring(base), 2) end
    local rel = "assets/" .. base
    if seen[rel] then die("duplicate asset name: " .. base, 3) end
    local data, aerr = read_file(path, MAX_FILE)
    if not data then die("asset read failed: " .. tostring(path) .. ": " .. tostring(aerr), 5) end
    total = total + #data
    if total > MAX_TOTAL then die("bundle exceeds 32 MiB limit", 6) end
    seen[rel] = true
    files[#files+1] = {path=rel, data=data}
    if #files > MAX_FILES then die("too many files", 6) end
  end

  local f, ferr = io.open(out, "wb")
  if not f then die("cannot create output: " .. tostring(ferr), 5) end
  f:write(MAGIC, "\n")
  f:write("name=", name, "\n")
  f:write("version=1\n")
  f:write("files=", tostring(#files), "\n\n")
  for _, e in ipairs(files) do
    local hash = fnv1a(e.data)
    f:write("ENTRY\t", e.path, "\t", tostring(#e.data), "\t", hash, "\n")
    f:write(e.data, "\n")
  end
  f:close()
  io.write("bundle=", out, "\nname=", name, "\nfiles=", #files, "\nbytes=", total, "\n")
end

local function inspect(path)
  local meta, err = load_bundle(path, false)
  if not meta then die(err, 7) end
  io.write("format=NKTASK1\nname=", meta.name, "\nversion=", meta.version, "\nfiles=", meta.count, "\nbytes=", meta.total, "\n")
  for _, e in ipairs(meta.entries) do
    io.write(e.path, "\t", e.size, "\t", e.hash, "\n")
  end
end

local function bundle_name(path)
  local meta, err = load_bundle(path, false)
  if not meta then die(err, 7) end
  io.write(meta.name, "\n")
end

local function extract(path, dir)
  if not path or not dir then die("usage: nkbundle.lua extract <bundle.nktask> <stage-dir>", 2) end
  local meta, err = load_bundle(path, true)
  if not meta then die(err, 7) end
  for _, e in ipairs(meta.entries) do
    local target
    if e.path == "script.lua" then target = dir .. "/script.lua"
    else target = dir .. "/assets/" .. e.path:match("^assets/(.+)$") end
    local f, ferr = io.open(target, "wb")
    if not f then die("cannot write staged entry: " .. tostring(ferr), 5) end
    f:write(e.data)
    f:close()
  end
  io.write("name=", meta.name, "\nfiles=", meta.count, "\nbytes=", meta.total, "\n")
end

local cmd = arg[1]
local args = {}
for i = 2, #arg do args[#args+1] = arg[i] end

if cmd == "version" then
  print(VERSION)
elseif cmd == "pack" then
  pack(args)
elseif cmd == "inspect" then
  inspect(args[1])
elseif cmd == "name" then
  bundle_name(args[1])
elseif cmd == "extract" then
  extract(args[1], args[2])
else
  die("commands: version | pack | inspect | name | extract", 2)
end
