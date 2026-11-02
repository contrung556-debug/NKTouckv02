-- NKTouch Recorder V3 exporter v0.7.5.2
-- SPDX-License-Identifier: GPL-3.0-or-later
-- Converts raw HID recordings to editable timelines and Lua.

local VERSION = "0.7.5.2"
local TAP_MOVE_THRESHOLD = 18.0
local HOLD_THRESHOLD_MS = 450
local MAX_ACTION_MS = 300000
local MAX_DELAY_MS = 300000
local MAX_COORD = 10000

local function round(n)
  return math.floor((tonumber(n) or 0) + 0.5)
end

local function clamp(n, lo, hi)
  n = tonumber(n)
  if not n then return nil end
  if n < lo then n = lo end
  if n > hi then n = hi end
  return n
end

local function dist(x1, y1, x2, y2)
  local dx, dy = x2 - x1, y2 - y1
  return math.sqrt(dx * dx + dy * dy)
end

local function clean_comment(s)
  return tostring(s or ""):gsub("[\r\n]", " ")
end

local function parse_raw(path)
  local f, err = io.open(path, "r")
  if not f then return nil, "cannot open raw file: " .. tostring(err) end
  local gestures, active = {}, {}
  local pending_us, ignored = 0, 0

  for rawline in f:lines() do
    local line = rawline:gsub("%s+$", "")
    local sleep_us = line:match("^18(%d+)$")
    if sleep_us then
      pending_us = pending_us + (tonumber(sleep_us) or 0)
    else
      local kind, finger, xs, ys = line:match("^101([012])(%d%d)(%d%d%d%d%d)(%d%d%d%d%d)$")
      if kind then
        local x, y = tonumber(xs) / 10.0, tonumber(ys) / 10.0
        if kind == "1" then
          if active[finger] then ignored = ignored + 1 end
          active[finger] = {
            finger = finger,
            x1 = x, y1 = y, x2 = x, y2 = y,
            idle_us = pending_us,
            duration_us = 0,
            points = 1,
            max_distance = 0,
          }
        else
          local g = active[finger]
          if not g then
            ignored = ignored + 1
          else
            g.duration_us = g.duration_us + pending_us
            g.x2, g.y2 = x, y
            g.points = g.points + 1
            g.max_distance = math.max(g.max_distance, dist(g.x1, g.y1, x, y))
            if kind == "0" then
              local duration_ms = math.max(1, round(g.duration_us / 1000.0))
              local idle_ms = math.max(0, round(g.idle_us / 1000.0))
              if #gestures == 0 then idle_ms = 0 end
              local action
              if g.max_distance <= TAP_MOVE_THRESHOLD then
                action = duration_ms >= HOLD_THRESHOLD_MS and "hold" or "tap"
              else
                action = "swipe"
              end
              gestures[#gestures + 1] = {
                action = action,
                x1 = g.x1, y1 = g.y1, x2 = g.x2, y2 = g.y2,
                idle_ms = idle_ms,
                duration_ms = duration_ms,
                points = g.points,
                finger = finger,
              }
              active[finger] = nil
            end
          end
        end
        pending_us = 0
      elseif line ~= "" then
        ignored = ignored + 1
      end
    end
  end
  f:close()
  for _ in pairs(active) do ignored = ignored + 1 end
  return gestures, ignored
end

local function normalize_action(a)
  a = tostring(a or ""):lower()
  if a == "tap" or a == "hold" or a == "swipe" then return a end
  return nil
end

local function normalize_row(g)
  local action = normalize_action(g.action)
  if not action then return nil, "invalid action" end
  local idle = clamp(round(g.idle_ms), 0, MAX_DELAY_MS)
  local duration = clamp(round(g.duration_ms), 1, MAX_ACTION_MS)
  local x1 = clamp(g.x1, 0, MAX_COORD)
  local y1 = clamp(g.y1, 0, MAX_COORD)
  local x2 = clamp(g.x2, 0, MAX_COORD)
  local y2 = clamp(g.y2, 0, MAX_COORD)
  if not (idle and duration and x1 and y1 and x2 and y2) then return nil, "invalid numeric field" end
  return {
    action = action,
    idle_ms = idle,
    duration_ms = duration,
    x1 = x1, y1 = y1, x2 = x2, y2 = y2,
    finger = tostring(g.finger or "00"),
    points = math.max(1, round(g.points or 1)),
  }
end

local function write_timeline(path, rows, source, ignored)
  local f, err = io.open(path, "w")
  if not f then return nil, "cannot write timeline: " .. tostring(err) end
  f:write("# NKTouch Recorder V3 timeline v", VERSION, "\n")
  f:write("# source=", clean_comment(source or ""), "\n")
  f:write("# ignored=", tostring(ignored or 0), "\n")
  f:write("# index\taction\tidle_ms\tduration_ms\tx1\ty1\tx2\ty2\tfinger\tpoints\n")
  for i, g in ipairs(rows) do
    local n, nerr = normalize_row(g)
    if not n then f:close(); return nil, "row " .. i .. ": " .. tostring(nerr) end
    f:write(string.format("%d\t%s\t%d\t%d\t%.1f\t%.1f\t%.1f\t%.1f\t%s\t%d\n",
      i, n.action, n.idle_ms, n.duration_ms, n.x1, n.y1, n.x2, n.y2, n.finger, n.points))
  end
  f:close()
  return true
end

local function split_tabs(line)
  local out = {}
  for part in (line .. "\t"):gmatch("(.-)\t") do out[#out + 1] = part end
  return out
end

local function read_timeline(path)
  local f, err = io.open(path, "r")
  if not f then return nil, "cannot open timeline: " .. tostring(err) end
  local rows = {}
  for line in f:lines() do
    if line ~= "" and line:sub(1, 1) ~= "#" then
      local p = split_tabs(line)
      if #p < 10 then f:close(); return nil, "malformed timeline row" end
      local row, rerr = normalize_row({
        action = p[2], idle_ms = p[3], duration_ms = p[4],
        x1 = p[5], y1 = p[6], x2 = p[7], y2 = p[8],
        finger = p[9], points = p[10],
      })
      if not row then f:close(); return nil, rerr end
      rows[#rows + 1] = row
    end
  end
  f:close()
  return rows
end

local function timeline_from_raw(raw_path, timeline_path)
  local rows, ignored_or_err = parse_raw(raw_path)
  if not rows then return nil, ignored_or_err end
  local ok, err = write_timeline(timeline_path, rows, raw_path, ignored_or_err or 0)
  if not ok then return nil, err end
  local counts = {tap = 0, hold = 0, swipe = 0}
  for _, g in ipairs(rows) do counts[g.action] = counts[g.action] + 1 end
  return {timeline = timeline_path, gestures = #rows, tap = counts.tap, hold = counts.hold, swipe = counts.swipe, ignored = ignored_or_err or 0}
end

local function inspect(path)
  local rows, err = read_timeline(path)
  if not rows then return nil, err end
  print("index\taction\tidle_ms\tduration_ms\tx1\ty1\tx2\ty2\tfinger\tpoints")
  for i, g in ipairs(rows) do
    print(string.format("%d\t%s\t%d\t%d\t%.1f\t%.1f\t%.1f\t%.1f\t%s\t%d",
      i, g.action, g.idle_ms, g.duration_ms, g.x1, g.y1, g.x2, g.y2, g.finger, g.points))
  end
  return rows
end

local function parse_assignment(s)
  local k, v = tostring(s or ""):match("^([a-zA-Z0-9_]+)=(.*)$")
  return k, v
end

local function edit(path, index, assignments)
  local rows, err = read_timeline(path)
  if not rows then return nil, err end
  index = tonumber(index)
  if not index or index < 1 or index > #rows or index ~= math.floor(index) then return nil, "index out of range" end
  local row = rows[index]
  local allowed = {action=true,idle_ms=true,duration_ms=true,x1=true,y1=true,x2=true,y2=true}
  for _, a in ipairs(assignments) do
    local k, v = parse_assignment(a)
    if not k or not allowed[k] then return nil, "invalid editable field: " .. tostring(k) end
    row[k] = v
  end
  local normalized, nerr = normalize_row(row)
  if not normalized then return nil, nerr end
  rows[index] = normalized
  local ok, werr = write_timeline(path, rows, "edited", 0)
  if not ok then return nil, werr end
  return rows[index]
end

local function delete_row(path, index)
  local rows, err = read_timeline(path)
  if not rows then return nil, err end
  index = tonumber(index)
  if not index or index < 1 or index > #rows or index ~= math.floor(index) then return nil, "index out of range" end
  table.remove(rows, index)
  local ok, werr = write_timeline(path, rows, "edited", 0)
  if not ok then return nil, werr end
  return rows
end

local function move_row(path, from_i, to_i)
  local rows, err = read_timeline(path)
  if not rows then return nil, err end
  from_i, to_i = tonumber(from_i), tonumber(to_i)
  if not from_i or not to_i or from_i ~= math.floor(from_i) or to_i ~= math.floor(to_i) then return nil, "invalid index" end
  if from_i < 1 or from_i > #rows or to_i < 1 or to_i > #rows then return nil, "index out of range" end
  local row = table.remove(rows, from_i)
  table.insert(rows, to_i, row)
  local ok, werr = write_timeline(path, rows, "edited", 0)
  if not ok then return nil, werr end
  return rows
end

local function emit_sleep(out, ms)
  ms = math.max(0, round(ms))
  while ms > 0 do
    local chunk = math.min(ms, MAX_DELAY_MS)
    out[#out + 1] = string.format("must(nk.sleep(%d))", chunk)
    ms = ms - chunk
  end
end

local function render_lua(timeline_path, out_path)
  local rows, err = read_timeline(timeline_path)
  if not rows then return nil, err end
  local out = {
    "-- Generated by NKTouch Recorder V3 v" .. VERSION,
    "-- Timeline: " .. clean_comment(timeline_path),
    "local nk = require(\"nktouch_v7\")",
    "local function must(value, err)",
    "  if value == nil or value == false then error(err or \"NKTouch action failed\", 2) end",
    "  return value",
    "end",
    "",
  }
  local counts = {tap=0, hold=0, swipe=0}
  for i, g in ipairs(rows) do
    if g.idle_ms > 0 then emit_sleep(out, g.idle_ms) end
    out[#out + 1] = string.format("-- action %d • %s", i, g.action)
    if g.action == "tap" then
      counts.tap = counts.tap + 1
      out[#out + 1] = string.format("must(nk.tap(%.1f, %.1f))", g.x1, g.y1)
    elseif g.action == "hold" then
      counts.hold = counts.hold + 1
      out[#out + 1] = string.format("must(nk.hold(%.1f, %.1f, %d))", g.x1, g.y1, g.duration_ms)
    else
      counts.swipe = counts.swipe + 1
      out[#out + 1] = string.format("must(nk.swipe(%.1f, %.1f, %.1f, %.1f, %d))", g.x1, g.y1, g.x2, g.y2, math.max(32, g.duration_ms))
    end
    out[#out + 1] = ""
  end
  out[#out + 1] = string.format("-- actions=%d tap=%d hold=%d swipe=%d", #rows, counts.tap, counts.hold, counts.swipe)
  local f, ferr = io.open(out_path, "w")
  if not f then return nil, "cannot write Lua file: " .. tostring(ferr) end
  f:write(table.concat(out, "\n"), "\n")
  f:close()
  return {output=out_path, actions=#rows, tap=counts.tap, hold=counts.hold, swipe=counts.swipe}
end

local function print_result(r)
  local keys = {"timeline","output","gestures","actions","tap","hold","swipe","ignored"}
  for _, k in ipairs(keys) do if r[k] ~= nil then print(k .. "=" .. tostring(r[k])) end end
end

local function main(argv)
  local cmd = argv[1]
  if cmd == "version" then print(VERSION); return 0 end
  if cmd == "timeline" and argv[2] and argv[3] and not argv[4] then
    local r, err = timeline_from_raw(argv[2], argv[3]); if not r then io.stderr:write("nkrecorder-v3: ", tostring(err), "\n"); return 3 end
    print_result(r); return 0
  end
  if cmd == "inspect" and argv[2] and not argv[3] then
    local r, err = inspect(argv[2]); if not r then io.stderr:write("nkrecorder-v3: ", tostring(err), "\n"); return 3 end
    return 0
  end
  if cmd == "edit" and argv[2] and argv[3] and argv[4] then
    local assignments = {}; for i=4,#argv do assignments[#assignments+1]=argv[i] end
    local r, err = edit(argv[2], argv[3], assignments); if not r then io.stderr:write("nkrecorder-v3: ", tostring(err), "\n"); return 3 end
    print("updated=" .. argv[3]); return 0
  end
  if cmd == "delete" and argv[2] and argv[3] and not argv[4] then
    local r, err = delete_row(argv[2], argv[3]); if not r then io.stderr:write("nkrecorder-v3: ", tostring(err), "\n"); return 3 end
    print("actions=" .. #r); return 0
  end
  if cmd == "move" and argv[2] and argv[3] and argv[4] and not argv[5] then
    local r, err = move_row(argv[2], argv[3], argv[4]); if not r then io.stderr:write("nkrecorder-v3: ", tostring(err), "\n"); return 3 end
    print("actions=" .. #r); return 0
  end
  if cmd == "render" and argv[2] and argv[3] and not argv[4] then
    local r, err = render_lua(argv[2], argv[3]); if not r then io.stderr:write("nkrecorder-v3: ", tostring(err), "\n"); return 3 end
    print_result(r); return 0
  end
  io.stderr:write("usage: nkrecorder_v3.lua <timeline|inspect|edit|delete|move|render> ...\n")
  return 2
end

local invoked = arg and type(arg[0]) == "string" and arg[0]:match("nkrecorder%.lua$")
if invoked then os.exit(main(arg)) end

return {
  VERSION=VERSION,
  parseRaw=parse_raw,
  readTimeline=read_timeline,
  writeTimeline=write_timeline,
  timelineFromRaw=timeline_from_raw,
  renderLua=render_lua,
  edit=edit,
  delete=delete_row,
  move=move_row,
}
