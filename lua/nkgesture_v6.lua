-- NKTouch Recorder V6 Gesture Engine
-- SPDX-License-Identifier: GPL-3.0-or-later
-- Single-finger HID paths: original sampled coordinates and relative timestamps.
-- Overlapping multi-finger gestures are excluded, not silently replayed as taps.
local M = {}
M.VERSION = "0.7.6"
local MAX_COORD, MAX_ACTION_MS, MAX_DELAY_MS = 10000, 300000, 300000
local MAX_POINTS, MAX_ACTIONS, MAX_RAW_LINES = 256, 10000, 2000000
local TAP_DISTANCE, HOLD_MS, DRAG_MS = 18, 450, 600

local function round(n) return math.floor(n + 0.5) end
local function number(v, lo, hi)
  local n = tonumber(v)
  if not n or n ~= n or n == math.huge or n == -math.huge or n < lo or n > hi then return nil end
  return n
end
local function distance(ax, ay, bx, by)
  local x, y = bx-ax, by-ay
  return math.sqrt(x*x + y*y)
end
local function split_tab(s)
  local values = {}
  for part in (s .. "\t"):gmatch("(.-)\t") do values[#values+1] = part end
  return values
end
local function comment(s)
  return tostring(s or ""):gsub("[\r\n\t]", " ")
end

local function decode_path(value, duration)
  if value == nil or value == "" then return {}, nil end
  if type(value) ~= "string" or #value > 16000 then return nil, "invalid path size" end
  local result, last_t = {}, -1
  for token in value:gmatch("[^;]+") do
    local xs, ys, ts = token:match("^([%d%.]+),([%d%.]+),(%d+)$")
    if not xs then return nil, "invalid path point" end
    local x, y, t = number(xs, 0, MAX_COORD), number(ys, 0, MAX_COORD), number(ts, 0, MAX_ACTION_MS)
    if not x or not y or not t or t % 1 ~= 0 then return nil, "path coordinate/time out of range" end
    if #result == 0 and t ~= 0 then return nil, "path must start at t=0" end
    if t <= last_t then return nil, "path timestamps must strictly increase" end
    if duration and t > duration then return nil, "path exceeds action duration" end
    result[#result+1] = {x=x,y=y,t=t}
    if #result > MAX_POINTS then return nil, "too many path points" end
    last_t = t
  end
  if #result < 2 or (value:sub(-1) == ";") then return nil, "path requires at least two points" end
  return result
end
local function encode_path(points)
  local out = {}
  for i, p in ipairs(points) do
    out[i] = string.format("%.1f,%.1f,%d", p.x,p.y,p.t)
  end
  return table.concat(out, ";")
end
M.decodePath = decode_path
M.encodePath = encode_path

function M.normalizeRow(g)
  local kind = tostring(g.action or ""):lower()
  if kind ~= "tap" and kind ~= "hold" and kind ~= "swipe" and kind ~= "drag" then
    return nil, "invalid gesture action"
  end
  local idle = number(g.idle_ms, 0, MAX_DELAY_MS)
  local duration = number(g.duration_ms, 1, MAX_ACTION_MS)
  local x1,y1,x2,y2 = number(g.x1,0,MAX_COORD),number(g.y1,0,MAX_COORD),
                      number(g.x2,0,MAX_COORD),number(g.y2,0,MAX_COORD)
  if not (idle and duration and x1 and y1 and x2 and y2) then return nil, "invalid numeric field" end
  local points, err = decode_path(g.path, round(duration))
  if not points then return nil, err end
  if (kind == "tap" or kind == "hold") and #points > 0 then points = {} end
  if #points > 0 then
    if distance(points[1].x,points[1].y,x1,y1)>0.2 or
       distance(points[#points].x,points[#points].y,x2,y2)>0.2 then
      return nil, "path endpoints do not match row coordinates"
    end
  end
  local finger = tostring(g.finger or "00")
  if not finger:match("^%d%d$") then return nil, "invalid finger id" end
  local samples = number(g.points or (#points>0 and #points or 1), 1, 2000000)
  if not samples then return nil, "invalid sample count" end
  return {action=kind,idle_ms=round(idle),duration_ms=round(duration),
          x1=x1,y1=y1,x2=x2,y2=y2,finger=finger,points=round(samples),
          path=encode_path(points)}
end

local function push_point(g, x, y, t)
  local points = g.samples
  local previous = points[#points]
  t = math.max(previous.t+1, round(t))
  -- Preserve meaningful motion and its timing. Do not fabricate intermediate HID samples.
  if #points >= MAX_POINTS then
    local compact = {points[1]}
    for i=3,#points,2 do compact[#compact+1] = points[i] end
    points = compact
    g.samples = points
  end
  points[#points+1] = {x=x,y=y,t=t}
end

function M.parseRaw(path)
  local f, err = io.open(path, "r")
  if not f then return nil, "cannot open HID recording: "..tostring(err) end
  local active, complete, ignored = {}, {}, 0
  local clock_us, lines = 0, 0
  for raw in f:lines() do
    lines = lines + 1
    if lines > MAX_RAW_LINES then f:close(); return nil, "raw recording exceeds event limit" end
    local line = raw:gsub("%s+$", "")
    local sleep_us = line:match("^18(%d+)$")
    if sleep_us then
      local delay = number(sleep_us, 0, MAX_ACTION_MS*1000)
      if not delay then f:close(); return nil, "invalid HID delay" end
      clock_us = clock_us + delay
    else
      local kind, finger, xs, ys = line:match("^101([012])(%d%d)(%d%d%d%d%d)(%d%d%d%d%d)$")
      if kind then
        local x, y = tonumber(xs)/10, tonumber(ys)/10
        if kind == "1" then
          if active[finger] then ignored = ignored+1 end
          local g = {finger=finger,x1=x,y1=y,x2=x,y2=y,start=clock_us,
                     max_distance=0,samples={{x=x,y=y,t=0}},overlap=false}
          for _, other in pairs(active) do other.overlap=true;g.overlap=true end
          active[finger] = g
        else
          local g = active[finger]
          if not g then ignored=ignored+1
          else
            g.x2,g.y2 = x,y
            g.max_distance = math.max(g.max_distance,distance(g.x1,g.y1,x,y))
            push_point(g,x,y,(clock_us-g.start)/1000)
            if kind == "0" then
              active[finger] = nil
              if g.overlap then
                ignored=ignored+1
              else
                local duration = math.max(1,round((clock_us-g.start)/1000),
                                           g.samples[#g.samples].t)
                if duration > MAX_ACTION_MS then ignored=ignored+1
                else
                  local action = g.max_distance <= TAP_DISTANCE
                    and (duration >= HOLD_MS and "hold" or "tap")
                    or (duration >= DRAG_MS and "drag" or "swipe")
                  complete[#complete+1] = {action=action,x1=g.x1,y1=g.y1,x2=x,y2=y,
                    start=g.start,finish=clock_us,duration_ms=duration,
                    points=#g.samples,finger=finger,
                    path=(action=="tap" or action=="hold") and "" or encode_path(g.samples)}
                  if #complete > MAX_ACTIONS then f:close(); return nil,"too many gestures" end
                end
              end
            end
          end
        end
      elseif line ~= "" then ignored = ignored+1 end
    end
  end
  f:close()
  for _ in pairs(active) do ignored=ignored+1 end
  table.sort(complete,function(a,b) return a.start<b.start end)
  local prev_finish
  for _, g in ipairs(complete) do
    g.idle_ms = prev_finish and math.max(0,round((g.start-prev_finish)/1000)) or 0
    prev_finish = math.max(prev_finish or 0,g.finish)
    g.start,g.finish = nil,nil
  end
  return complete,ignored
end

function M.writeTimeline(path, rows, source, ignored)
  if #rows > MAX_ACTIONS then return nil, "too many timeline actions" end
  local formatted = {}
  for i,g in ipairs(rows) do
    local row,err = M.normalizeRow(g)
    if not row then return nil,"row "..i..": "..tostring(err) end
    formatted[i]=string.format("%d\t%s\t%d\t%d\t%.1f\t%.1f\t%.1f\t%.1f\t%s\t%d\t%s\n",
      i,row.action,row.idle_ms,row.duration_ms,row.x1,row.y1,row.x2,row.y2,row.finger,row.points,row.path)
  end
  local tmp = path..".v6-tmp"
  local f,err = io.open(tmp,"w")
  if not f then return nil,"cannot write timeline: "..tostring(err) end
  f:write("# NKTouch Recorder V6 timeline v",M.VERSION,"\n",
          "# source=",comment(source),"\n",
          "# ignored=",tostring(ignored or 0),"\n",
          "# index\taction\tidle_ms\tduration_ms\tx1\ty1\tx2\ty2\tfinger\tpoints\tpath\n")
  for _,line in ipairs(formatted) do f:write(line) end
  f:close()
  local ok,rename_err = os.rename(tmp,path)
  if not ok then os.remove(tmp);return nil,"cannot replace timeline: "..tostring(rename_err) end
  return true
end

function M.readTimeline(path)
  local f, err = io.open(path,"r")
  if not f then return nil,"cannot open timeline: "..tostring(err) end
  local rows={}
  for line in f:lines() do
    if line~="" and line:sub(1,1)~="#" then
      local p=split_tab(line)
      if #p<10 then f:close();return nil,"malformed timeline row" end
      local row,rerr=M.normalizeRow({action=p[2],idle_ms=p[3],duration_ms=p[4],
        x1=p[5],y1=p[6],x2=p[7],y2=p[8],finger=p[9],points=p[10],path=p[11] or ""})
      if not row then f:close();return nil,rerr end
      rows[#rows+1]=row
      if #rows>MAX_ACTIONS then f:close();return nil,"too many timeline actions" end
    end
  end
  f:close()
  return rows
end

function M.inspect(path)
  local rows,err=M.readTimeline(path)
  if not rows then return nil,err end
  print("index\taction\tidle_ms\tduration_ms\tx1\ty1\tx2\ty2\tfinger\tpoints\tpath")
  for i,row in ipairs(rows) do
    print(string.format("%d\t%s\t%d\t%d\t%.1f\t%.1f\t%.1f\t%.1f\t%s\t%d\t%s",
      i,row.action,row.idle_ms,row.duration_ms,row.x1,row.y1,row.x2,row.y2,
      row.finger,row.points,row.path))
  end
  return rows
end

local function emit_sleep(lines,ms)
  while ms>0 do
    local chunk=math.min(ms,MAX_DELAY_MS)
    lines[#lines+1]=string.format("must(nk.sleep(%d))",chunk)
    ms=ms-chunk
  end
end

function M.renderLua(timeline, output)
  local rows,err=M.readTimeline(timeline)
  if not rows then return nil,err end
  local lines={
    "-- NKTouch Recorder V6 v"..M.VERSION.." (single-finger HID paths)",
    "-- Timeline: "..comment(timeline),
    'local nk = require("nktouch_v7")',
    'local function must(value, err)',
    '  if value == nil or value == false then error(err or "NKTouch action failed", 2) end',
    '  return value',
    'end',
    ""
  }
  local counts={tap=0,hold=0,swipe=0,drag=0}
  for i,row in ipairs(rows) do
    if row.idle_ms>0 then emit_sleep(lines,row.idle_ms) end
    lines[#lines+1]=string.format("-- action %d : %s (%d HID samples)",i,row.action,row.points)
    if row.action=="tap" then
      lines[#lines+1]=string.format("must(nk.tap(%.1f, %.1f))",row.x1,row.y1)
    elseif row.action=="hold" then
      lines[#lines+1]=string.format("must(nk.hold(%.1f, %.1f, %d))",row.x1,row.y1,row.duration_ms)
    else
      local path=assert(decode_path(row.path,row.duration_ms))
      if #path>=3 then
        local points={}
        for _,point in ipairs(path) do
          points[#points+1]=string.format("{x=%.1f,y=%.1f,t=%d}",point.x,point.y,point.t)
        end
        lines[#lines+1]="must(nk.path({"..table.concat(points,",").."}))"
      else
        lines[#lines+1]=string.format("must(nk.swipe(%.1f, %.1f, %.1f, %.1f, %d))",
          row.x1,row.y1,row.x2,row.y2,math.max(32,row.duration_ms))
      end
    end
    counts[row.action]=counts[row.action]+1
    lines[#lines+1]=""
  end
  lines[#lines+1]=string.format("-- actions=%d tap=%d hold=%d swipe=%d drag=%d",
    #rows,counts.tap,counts.hold,counts.swipe,counts.drag)
  local f,ferr=io.open(output,"w")
  if not f then return nil,"cannot write Lua: "..tostring(ferr) end
  f:write(table.concat(lines,"\n"),"\n"); f:close()
  return {output=output,actions=#rows,tap=counts.tap,hold=counts.hold,
          swipe=counts.swipe,drag=counts.drag}
end

return M
