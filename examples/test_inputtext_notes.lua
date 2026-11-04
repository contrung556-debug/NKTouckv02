-- NKTouch v0.7.13 - Test InputText voi Apple Notes (Ghi chu).
-- Script co san: Lua Workspace -> Samples -> Test InputText.
-- LUU Y: Se tao mot ghi chu thu nghiem. Neu giao dien Notes khac,
-- sua NEW_NOTE_X/Y va BODY_X/Y; khong thu tren ghi chu quan trong.
-- Bundle ID cua Apple Notes: com.apple.mobilenotes.
local nk = require("nktouch_v7")

local NOTES_ID = "com.apple.mobilenotes"
local TEST_TEXT = "NKTouch InputText Test 12345"

-- Dat toa do cu the neu tap sai vi giao dien Notes phu thuoc iOS.
-- nil = tu tinh theo kich thuoc man hinh.
local NEW_NOTE_X, NEW_NOTE_Y = nil, nil
local BODY_X, BODY_Y = nil, nil
local OCR_CHECK = true  -- Chi de tham khao, OCR co the nham.

local function log(stage, value)
  print("[NKINPUT][NOTES]["..stage.."] "..tostring(value or ""))
end

local function must(stage, ok, err, code)
  if ok == nil or ok == false then
    local message = string.format("%s: %s (%s)", stage,
                                 tostring(err or "failed"), tostring(code or ""))
    log("FAIL", message)
    error(message, 0)
  end
  log(stage, "OK")
  return ok
end

local function dimensions()
  local value, err, code = nk.screen()
  must("SCREEN", value, err, code)
  -- NKTouch device query tra ve chuoi kich thuoc (VD: 390;;844).
  local w, h = tostring(value):match("(%d+)%s*;;%s*(%d+)")
  if not w then w, h = tostring(value):match("(%d+)%D+(%d+)") end
  w, h = tonumber(w), tonumber(h)
  if not w or not h or w < 250 or h < 400 or w > 4000 or h > 5000 or w > h then
    error("SCREEN_FORMAT: Khong doc duoc kich thuoc doc tu nk.screen(): "..tostring(value), 0)
  end
  log("SCREEN_SIZE", w.."x"..h)
  return w, h
end

function testInputTextNotes()
  local w, h = dimensions()
  log("OPEN_APP", NOTES_ID)
  local foreground = nk.foreground()
  if foreground ~= NOTES_ID then
    local ok, err, code = nk.openApp(NOTES_ID)
    must("OPEN_APP", ok, err, code)
  end
  local ready, why, code = nk.waitApp(NOTES_ID, 10000, 250)
  must("WAIT_APP", ready, why, code)
  must("APP_SETTLE", nk.sleep(1200))

  -- Notes o man hinh danh sach: nut tao ghi chu thuong o goc phai duoi.
  -- Giao dien iOS khac nhau: sua 4 toa do neu can.
  local createX = NEW_NOTE_X or math.floor(w * 0.91)
  local createY = NEW_NOTE_Y or math.floor(h * 0.91)
  log("TAP_NEW_NOTE", createX..","..createY)
  local tapOk, tapErr, tapCode = nk.tap(createX, createY)
  must("TAP_NEW_NOTE", tapOk, tapErr, tapCode)
  must("WAIT_NOTE", nk.sleep(900))

  local bodyX = BODY_X or math.floor(w * 0.35)
  local bodyY = BODY_Y or math.floor(h * 0.25)
  log("TAP_EDITOR", bodyX..","..bodyY)
  tapOk, tapErr, tapCode = nk.tap(bodyX, bodyY)
  must("TAP_EDITOR", tapOk, tapErr, tapCode)
  must("WAIT_KEYBOARD", nk.sleep(650))

  local active, activeErr, activeCode = nk.foreground()
  must("CHECK_FOREGROUND", active, activeErr, activeCode)
  if active ~= NOTES_ID then
    error("WRONG_APP: Dang o "..tostring(active)..", dung truoc khi nhap", 0)
  end

  log("INPUT_TEXT", "start")
  local ok, result, inputCode = nk.inputText(TEST_TEXT)
  must("INPUT_TEXT", ok, result, inputCode)
  log("INPUT_DISPATCHED", type(result)=="table" and result.status or "sent")
  must("WAIT_INPUT", nk.sleep(1000))

  -- OCR khong doc mat khau; day chi la chuoi kiem tra cong khai.
  -- Neu OCR khong ho tro hoac sai, khong tu dong nhap lai (tranh trung).
  if OCR_CHECK then
    local top = math.floor(h * 0.12)
    local height = math.floor(h * 0.46)
    local visible, ocrErr, ocrCode = nk.ocr(0, top, w, height, "")
    if visible and visible:find(TEST_TEXT,1,true) then
      log("RESULT", "VERIFIED_BY_OCR")
    else
      log("RESULT", "UNVERIFIED - kiem tra chu trong Notes; OCR="..tostring(ocrCode or ocrErr or "not matched"))
    end
  else
    log("RESULT", "DISPATCHED_ONLY - kiem tra chu trong Notes")
  end
  return true
end

testInputTextNotes()
