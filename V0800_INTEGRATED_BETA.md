# NKTouch v0.8.0 Integrated Beta — một đợt build, nhiều lõi

**Nhánh:** `v0.8.0-integrated-beta-dev`. Mục tiêu: tích hợp những phần có thể kiểm tra trên máy chủ trước rồi build rootless một lần để thử trực tiếp trên iPhone. Không tự phát hành Sileo; các kết quả host CI không chứng minh thiết bị hoạt động chính xác.

## Các phần trong gói

- `nktestlab.lua`: Test Lab 5 nhóm mặc định (OCR, Color, Touch, InputText, Memory), các nhóm nâng cao và **Diagnostics & Crash**. Báo cáo PASS/FAIL/WARN/SKIP theo từng phép thử tại `/var/mobile/Library/NKTouch/tmp/testlab-last.json`.
- `nkdiagnostics.lua`: đọc `NKTOUCH_TASK_ID`, state exit_code/signal, tạo proxy ghi checkpoint **chỉ khi bật tracing**. Không ghi tham số input, văn bản OCR, mật khẩu, đường dẫn ảnh, kết quả API. Dữ liệu được ghi theo tên API, trạng thái, mã lỗi. Với `persist=true`, checkpoint ghi vào `/var/mobile/Library/NKTouch/tmp/diagnostics-last.json` để giữ lại lệnh cuối nếu native crash. Nếu không thể ghi checkpoint, proxy không gửi hành động thay đổi trạng thái.
- `nksnapshot.lua`: một ảnh immutable cho danh sách pixel, tìm màu, OCR và tìm mẫu; có `capture()`, `waitText()`, `waitColor()` với retry **chỉ đọc**, giới hạn lần thử và timeout. Tìm màu trả `NOT_FOUND` bình thường nếu không thấy. Nội dung OCR mặc định không được kèm trong dữ liệu, chỉ nhận khi `include_text=true` một cách rõ ràng.
- `nkactions.lua`: wrapper `gesture()`, `typeText()` có `enabled=true` và `confirmed=true`, đúng bundle foreground, tọa độ pixel; không retry HID hoặc nhập liệu. Phản hồi `UNVERIFIED` chỉ là lệnh đã gửi, chưa được xác nhận bằng hình ảnh.
- `nksdk.lua`: lớp tiện ích `local sdk=require("nksdk").new({...})` không thay đổi `nktouch_v7` và API Lua cũ.

## Ví dụ Lua chỉ đọc

```lua
local sdk=assert(require("nksdk").new({trace=true,persist=false}))
local info,err,code=sdk:inspect({
  pixels={{x=120,y=200}},
  ocr={{x=0,y=0,w=750,h=220,language=""}},
})
assert(info, tostring(code).." "..tostring(err))
print("RGB status:",info.pixels[1].status)
print("OCR status:",info.ocr[1].status,"bytes:",info.ocr[1].bytes)
```

Muốn đọc văn bản OCR trong chính script thì truyền `{include_text=true}` vào `sdk:inspect(plan,{include_text=true})`. Không tự gửi hoặc lưu lại văn bản này trong báo cáo.

## Đoạn kiểm tra hành động (không tự chạy)

```lua
-- Chỉ dùng trên ứng dụng/màn hình thử nghiệm không chứa thông tin nhạy cảm.
local sdk=assert(require("nksdk").new())
-- Cấu hình bằng tay khi thử: đổi bundle và vị trí, rồi mới xác nhận:
local ok,meta,code=sdk:gesture({
  enabled=false, confirmed=false,
  bundle="com.apple.mobilenotes",action="tap",x=120,y=200
})
```

Giữ nguyên `enabled=false`, `confirmed=false` mặc định để không thao tác ngoài ý muốn.

## Cách chạy Test Lab trên iPhone

NKTouch → **Test Lab** → **5 lõi** → **Tạo bài kiểm tra → Lua Editor** → **Chạy**. Sau đó trở lại Test Lab → **Báo cáo**. Chọn thêm nhóm **Diagnostics & Crash** nếu muốn xem task signal/exit và xác nhận trace.

## Kiểm tra bắt buộc trước khi phát hành

1. Xcode/UIKit + Theos rootless build/đóng gói thành công; đảm bảo module mới nằm trong `usr/share/nktouch/lua/`.
2. Chạy Test Lab 5 lõi trên iPhone, OCR cả native và live trả văn bản ở màn hình có chữ rõ.
3. Memory: thử 30–100 vòng với thời gian tăng dần; theo dõi RSS và không có crash.
4. Touch/InputText: chỉ chạy trên màn hình thử nghiệm có xác nhận, so sánh tác động trực quan.
5. Sau khi script kết thúc, kiểm tra `state`, `exit_code`, `signal` trong NKTask. Lỗi native có thể không thể khôi phục bằng Lua; checkpoint chỉ là một manh mối.
6. Chạy lại script Facebook v10 và các script cũ để kiểm tra tương thích.

**Không có ở bản beta:** truy cập đầy đủ cây accessibility của app khác hoặc bảo đảm chống crack thương mại. Cần một bước thiết kế/bảo mật riêng và xác minh quyền truy cập trước khi phát hành.
