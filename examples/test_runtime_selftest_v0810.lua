-- NKTouch v0.8.10 Runtime Self-Test (read-only)
-- Compatible target: NKTouch v0.8.9 runtime.
-- No tap, typing, app launch, container create, or container switch.
-- cranectl check is limited to --list; container names are never printed.

local TAG = "[NKRT810]"
local APP_ID = "com.facebook.Facebook"
local CRANECTL = "/var/jb/usr/local/bin/cranectl"

local passCount, warnCount, failCount = 0, 0, 0

local function out(level, name, detail)
    local line = TAG .. "[" .. level .. "] " .. name
    if detail ~= nil and tostring(detail) ~= "" then
        line = line .. " " .. tostring(detail)
    end
    print(line)
end

local function pass(name, detail)
    passCount = passCount + 1
    out("PASS", name, detail)
end

local function warn(name, detail)
    warnCount = warnCount + 1
    out("WARN", name, detail)
end

local function fail(name, detail)
    failCount = failCount + 1
    out("FAIL", name, detail)
end

local function statusIsSuccess(first, kind, code)
    return first == true
        or first == 0
        or (kind == "exit" and tonumber(code) == 0)
end

local function readOnlyCommand(command)
    if type(io) ~= "table" or type(io.popen) ~= "function" then
        return nil, "io.popen unavailable"
    end

    local opened, pipeOrError = pcall(io.popen, command, "r")
    if not opened or not pipeOrError then
        return nil, "io.popen failed: " .. tostring(pipeOrError)
    end

    local pipe = pipeOrError
    local readOK, output = pcall(function()
        return pipe:read("*a")
    end)
    local closeOK, first, kind, code = pcall(function()
        return pipe:close()
    end)

    if not readOK then
        return nil, "pipe read failed: " .. tostring(output)
    end
    if not closeOK then
        return nil, "pipe close failed: " .. tostring(first)
    end

    return {
        output = tostring(output or ""),
        success = statusIsSuccess(first, kind, code),
        status = tostring(first) .. "," .. tostring(kind) .. "," .. tostring(code)
    }
end

local loadOK, nk = pcall(require, "nktouch_v7")
if not loadOK or type(nk) ~= "table" then
    fail("module.require", tostring(nk))
    out("SUMMARY", "PASS=" .. passCount .. " WARN=" .. warnCount .. " FAIL=" .. failCount)
    error(TAG .. " module load failed", 0)
end
pass("module.require", "nktouch_v7 loaded")

if type(nk.runtime) == "function" then
    local ok, value, err, code = pcall(nk.runtime)
    if ok and value ~= nil and value ~= false then
        pass("nk.runtime", "result_type=" .. type(value))
    else
        fail("nk.runtime", ok and (tostring(err) .. " " .. tostring(code)) or tostring(value))
    end
else
    fail("nk.runtime", "function unavailable")
end

if type(nk.screen) == "function" then
    local ok, value, err, code = pcall(nk.screen)
    if ok and type(value) == "string" then
        local width, height = value:match("^%s*(%d+%.?%d*)%s*;;%s*(%d+%.?%d*)%s*$")
        width, height = tonumber(width), tonumber(height)
        if width and height and width > 0 and height > 0 then
            pass("nk.screen", tostring(width) .. "x" .. tostring(height))
        else
            fail("nk.screen", "unexpected response format")
        end
    else
        fail("nk.screen", ok and (tostring(err) .. " " .. tostring(code)) or tostring(value))
    end
else
    fail("nk.screen", "function unavailable")
end

if type(nk.sleep) == "function" then
    local ok, err = pcall(nk.sleep, 20)
    if ok then
        pass("nk.sleep", "20ms")
    else
        fail("nk.sleep", tostring(err))
    end
else
    fail("nk.sleep", "function unavailable")
end

local processResult, processError = readOnlyCommand("printf NKTOUCH_IOPOPEN_OK 2>&1")
if processResult and processResult.success
        and processResult.output == "NKTOUCH_IOPOPEN_OK" then
    pass("io.popen", "shim output and exit status verified")
else
    fail("io.popen", processError or ("exit=" .. tostring(processResult and processResult.status)
        .. " output_bytes=" .. tostring(processResult and #processResult.output or 0)))
end

local cranectlResult, cranectlError = readOnlyCommand(
    CRANECTL .. " --list " .. "'" .. APP_ID .. "'" .. " 2>&1"
)
if not cranectlResult then
    warn("cranectl.list", tostring(cranectlError))
elseif cranectlResult.success then
    pass("cranectl.list", "exit status verified; output_bytes=" .. #cranectlResult.output)
else
    warn("cranectl.list", "exit=" .. cranectlResult.status
        .. " output_bytes=" .. #cranectlResult.output)
end

out("SUMMARY", "PASS=" .. passCount .. " WARN=" .. warnCount .. " FAIL=" .. failCount)
if failCount > 0 then
    error(TAG .. " runtime self-test failed", 0)
end
