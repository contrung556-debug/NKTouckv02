-- NKTouch 0.7.16-dev: compare two Test Lab runs without inventing success.
-- A regression check is diagnostic only; NOT permission to publish to Sileo.
local M={VERSION="0.7.16-dev"}
local severity={PASS=0,WARN=1,SKIP=2,FAIL=3}
local function sameGroups(a,b)
  if type(a)~="table" or type(b)~="table" or #a~=#b then return false end
  for i=1,#a do if a[i]~=b[i] then return false end end
  return true
end
local function finite(n)
  return type(n)=="number" and n==n and n~=math.huge and n~=-math.huge and n>=0
end

function M.compare(current,prior)
  local summary={status="NO_BASELINE",comparable=false,
                 regressions={},improvements={},latency_warnings={},
                 release_ready=false}
  if type(prior)~="table" then return summary end
  if type(current)~="table" or
      not sameGroups(current.selected,prior.selected) then
    summary.status="NOT_COMPARABLE"
    return summary
  end
  if type(current.tests)~="table" or type(prior.tests)~="table" then
    summary.status="NOT_COMPARABLE"
    return summary
  end
  summary.comparable=true
  local previous={}
  for _,record in ipairs(prior.tests) do
    if type(record)=="table" and type(record.group)=="string" and
       type(record.name)=="string" and severity[record.status] then
      previous[record.group.."/"..record.name]=record
    end
  end
  local matches=0
  local observed={}
  for _,record in ipairs(current.tests) do
    if type(record)=="table" then
      local key=tostring(record.group).."/"..tostring(record.name)
      local before=previous[key]
      if before and severity[record.status] then
        matches=matches+1
        observed[key]=true
        local old,new=severity[before.status],severity[record.status]
        if new>old then
          summary.regressions[#summary.regressions+1]={
            check=key,from=before.status,to=record.status
          }
        elseif new<old then
          summary.improvements[#summary.improvements+1]={
            check=key,from=before.status,to=record.status
          }
        end
        -- Only compare identical PASS checks from real monotonic-clock runs.
        -- Aggregate P95 across different checks does not estimate API latency.
        if current.clock_type=="monotonic_native_ms" and
           prior.clock_type=="monotonic_native_ms" and
           record.status=="PASS" and before.status=="PASS" and
           finite(record.ms) and finite(before.ms) and
           record.ms>math.max(before.ms*2, before.ms+25) then
          summary.latency_warnings[#summary.latency_warnings+1]={
            check=key,prior_ms=before.ms,current_ms=record.ms
          }
        end
      end
    end
  end
  -- Missing checks cannot be treated as a clean release comparison.
  -- A previously passing test disappearing is itself a regression.
  for key,before in pairs(previous) do
    if not observed[key] then
      summary.regressions[#summary.regressions+1]={
        check=key,from=before.status,to="MISSING"
      }
    end
  end
  summary.matched_checks=matches
  if matches==0 and #summary.regressions==0 then
    summary.comparable=false
    summary.status="NOT_COMPARABLE"
  elseif #summary.regressions>0 then
    summary.status="REGRESSION"
  elseif #summary.latency_warnings>0 then
    summary.status="LATENCY_WARNING"
  else
    summary.status="NO_REGRESSION_OBSERVED"
  end
  return summary
end
return M
