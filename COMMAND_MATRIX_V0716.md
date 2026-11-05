# NKTouch v0.7.16-dev — Kiểm kê và bằng chứng cho toàn bộ lệnh Lua

**Phạm vi:** 81 mục trong `runtime/nktouch-api.tsv`, lấy từ nhánh phát triển `v0.7.16-command-hardening-dev`. Mục tiêu là rà soát *toàn bộ lệnh đã có* trước khi cho phép build/Sileo. Danh sách này ghi lại **mức kiểm thử**, không tự nhận các lệnh đã hoạt động ổn trên iPhone.

## Quy tắc xác nhận

- **SOURCE:** tên API tồn tại trong Lua/bridge hoặc native; bộ kiểm thử đối chiếu danh mục hai chiều đã chạy trong GitHub Actions.
- **HOST GUARD:** kiểm thử đầu vào sai/đúng ở Lua mock; **không** khẳng định iPhone đã chạm/hiện chữ.
- **HOST MOCK:** kiểm thử mô phỏng JSON, HTTP invalid input, Input Engine v2, legacy color/image replies mà không gọi thiết bị.
- **DEVICE:** có bằng chứng thực tế từ lần test Ghi chú trước đó (mở, đợi, tap và nhập chữ thành công). Không suy rộng sang ứng dụng khác.
- **PENDING DEVICE:** cần kiểm thử thực tế, kể cả khi có SOURCE/HOST PASS.

## Danh sách chi tiết

| API | Nhóm | Kết quả hiện tại | Bước còn thiếu |
|---|---|---|---|
| `nk.tap` | Cảm ứng | SOURCE · DEVICE (Notes) | Thử thêm app/màn hình khác |
| `nk.hold` | Cảm ứng | SOURCE · HOST GUARD | Kiểm tra kết quả trên iPhone |
| `nk.swipe` | Cảm ứng | SOURCE · HOST GUARD | Kiểm tra kết quả trên iPhone |
| `nk.path` | Cảm ứng | SOURCE · HOST GUARD | Kiểm tra kết quả trên iPhone |
| `nk.sleep` | Thời gian | SOURCE · HOST GUARD | Kiểm tra kết quả trên iPhone |
| `nk.openApp` | Ứng dụng | SOURCE · DEVICE (Notes) | Thử thêm app/màn hình khác |
| `nk.waitApp` | Ứng dụng | SOURCE · DEVICE (Notes) | Thử thêm app/màn hình khác |
| `nk.foreground` | Ứng dụng | SOURCE | Kiểm tra kết quả trên iPhone |
| `nk.text` | Bàn phím | SOURCE · HOST GUARD | Kiểm tra kết quả trên iPhone |
| `nk.inputTextV2` | Bàn phím | SOURCE · HOST MOCK | Kiểm tra kết quả trên iPhone |
| `nk.inputPassword` | Bàn phím | SOURCE · HOST MOCK | Kiểm tra kết quả trên iPhone |
| `nk.inputText` | Bàn phím | SOURCE · DEVICE (Notes) | Thử thêm app/màn hình khác |
| `nk.showKeyboard` | Bàn phím | SOURCE | Kiểm tra kết quả trên iPhone |
| `nk.hideKeyboard` | Bàn phím | SOURCE | Kiểm tra kết quả trên iPhone |
| `nk.moveCursor` | Bàn phím | SOURCE · HOST GUARD | Kiểm tra kết quả trên iPhone |
| `nk.delete` | Bàn phím | SOURCE · HOST GUARD | Kiểm tra kết quả trên iPhone |
| `nk.paste` | Bàn phím | SOURCE · HOST GUARD | Kiểm tra kết quả trên iPhone |
| `nk.getClipboard` | Clipboard | SOURCE | Kiểm tra kết quả trên iPhone |
| `nk.setClipboard` | Clipboard | SOURCE · HOST GUARD | Kiểm tra kết quả trên iPhone |
| `nk.toast` | Thông báo | SOURCE · HOST GUARD | Kiểm tra kết quả trên iPhone |
| `nk.hideToast` | Thông báo | SOURCE | Kiểm tra kết quả trên iPhone |
| `nk.screenshot` | Màu / ảnh / OCR | SOURCE · HOST GUARD | Kiểm tra kết quả trên iPhone |
| `nk.captureFrame` | Màu / ảnh / OCR | SOURCE | Kiểm tra kết quả trên iPhone |
| `nk.withFrame` | Màu / ảnh / OCR | SOURCE | Kiểm tra kết quả trên iPhone |
| `frame.info` | Màu / ảnh / OCR | SOURCE · native method mapped | Kiểm tra kết quả trên iPhone |
| `frame.getColor` | Màu / ảnh / OCR | SOURCE · native method mapped | Kiểm tra kết quả trên iPhone |
| `frame.findColor` | Màu / ảnh / OCR | SOURCE · native method mapped | Kiểm tra kết quả trên iPhone |
| `frame.findImage` | Màu / ảnh / OCR | SOURCE · native method mapped | Kiểm tra kết quả trên iPhone |
| `frame.ocr` | Màu / ảnh / OCR | SOURCE · native method mapped | Kiểm tra kết quả trên iPhone |
| `frame.save` | Màu / ảnh / OCR | SOURCE · native method mapped | Kiểm tra kết quả trên iPhone |
| `frame.close` | Màu / ảnh / OCR | SOURCE · native method mapped | Kiểm tra kết quả trên iPhone |
| `nk.findImage` | Màu / ảnh / OCR | SOURCE · HOST GUARD | Kiểm tra kết quả trên iPhone |
| `nk.waitImage` | Màu / ảnh / OCR | SOURCE · HOST GUARD | Kiểm tra kết quả trên iPhone |
| `nk.tapImage` | Màu / ảnh / OCR | SOURCE · HOST GUARD | Kiểm tra kết quả trên iPhone |
| `nk.getColor` | Màu / ảnh / OCR | SOURCE · HOST GUARD | Kiểm tra kết quả trên iPhone |
| `nk.matchColor` | Màu / ảnh / OCR | SOURCE | Kiểm tra kết quả trên iPhone |
| `nk.waitColorMatch` | Màu / ảnh / OCR | SOURCE | Kiểm tra kết quả trên iPhone |
| `nk.findColor` | Màu / ảnh / OCR | SOURCE · HOST GUARD | Kiểm tra kết quả trên iPhone |
| `nk.waitColor` | Màu / ảnh / OCR | SOURCE · HOST GUARD | Kiểm tra kết quả trên iPhone |
| `nk.tapColor` | Màu / ảnh / OCR | SOURCE · HOST GUARD | Kiểm tra kết quả trên iPhone |
| `nk.ocr` | Màu / ảnh / OCR | SOURCE · HOST GUARD | Kiểm tra kết quả trên iPhone |
| `nk.waitText` | Màu / ảnh / OCR | SOURCE · HOST GUARD | Kiểm tra kết quả trên iPhone |
| `nk.screen` | Thiết bị | SOURCE | Kiểm tra kết quả trên iPhone |
| `nk.orientation` | Thiết bị | SOURCE | Kiểm tra kết quả trên iPhone |
| `nk.scale` | Thiết bị | SOURCE | Kiểm tra kết quả trên iPhone |
| `nk.device` | Thiết bị | SOURCE | Kiểm tra kết quả trên iPhone |
| `nk.battery` | Thiết bị | SOURCE | Kiểm tra kết quả trên iPhone |
| `nk.runtime` | Thiết bị | SOURCE | Kiểm tra kết quả trên iPhone |
| `nk.ping` | Chẩn đoán | SOURCE | Kiểm tra kết quả trên iPhone |
| `nk.recordStart` | Recorder | SOURCE | Kiểm tra kết quả trên iPhone |
| `nk.recordStop` | Recorder | SOURCE | Kiểm tra kết quả trên iPhone |
| `nk.status` | Trạng thái UI | SOURCE · HOST GUARD | Kiểm tra kết quả trên iPhone |
| `nk.success` | Trạng thái UI | SOURCE | Kiểm tra kết quả trên iPhone |
| `nk.warning` | Trạng thái UI | SOURCE | Kiểm tra kết quả trên iPhone |
| `nk.error` | Trạng thái UI | SOURCE | Kiểm tra kết quả trên iPhone |
| `nk.hide` | Trạng thái UI | SOURCE | Kiểm tra kết quả trên iPhone |
| `nk.log` | Trạng thái UI | SOURCE | Kiểm tra kết quả trên iPhone |
| `nk.heartbeat` | Trạng thái UI | SOURCE | Kiểm tra kết quả trên iPhone |
| `nk.classifyError` | Chẩn đoán | SOURCE | Kiểm tra kết quả trên iPhone |
| `nk.retryConfig` | Chẩn đoán | SOURCE | Kiểm tra kết quả trên iPhone |
| `nk.coreVersion` | Chẩn đoán | SOURCE | Kiểm tra kết quả trên iPhone |
| `nk.isDirect` | Chẩn đoán | SOURCE | Kiểm tra kết quả trên iPhone |
| `nk.benchmark` | Chẩn đoán | SOURCE | Kiểm tra kết quả trên iPhone |
| `nk.stress` | Chẩn đoán | SOURCE | Kiểm tra kết quả trên iPhone |
| `nk.installAutoTouchCompat` | Tương thích | SOURCE | Kiểm tra kết quả trên iPhone |
| `nk.http.request` | HTTP | SOURCE · HOST (invalid requests) | Kiểm tra kết quả trên iPhone |
| `nk.http.get` | HTTP | SOURCE · HOST (invalid requests) | Kiểm tra kết quả trên iPhone |
| `nk.http.post` | HTTP | SOURCE · HOST (invalid requests) | Kiểm tra kết quả trên iPhone |
| `nk.http.download` | HTTP | SOURCE · HOST (invalid requests) | Kiểm tra kết quả trên iPhone |
| `nk.http.upload` | HTTP | SOURCE · HOST (invalid requests) | Kiểm tra kết quả trên iPhone |
| `nk.json.encode` | JSON | SOURCE · HOST MOCK | Kiểm tra kết quả trên iPhone |
| `nk.json.decode` | JSON | SOURCE · HOST MOCK | Kiểm tra kết quả trên iPhone |
| `nk.json.array` | JSON | SOURCE · HOST MOCK | Kiểm tra kết quả trên iPhone |
| `nk.json.object` | JSON | SOURCE · HOST MOCK | Kiểm tra kết quả trên iPhone |
| `nk.stop` | Tác vụ | SOURCE | Kiểm tra kết quả trên iPhone |
| `nk.doctor` | Chẩn đoán | SOURCE | Kiểm tra kết quả trên iPhone |
| `nk.selftest` | Chẩn đoán | SOURCE | Kiểm tra kết quả trên iPhone |
| `nk.cleanup` | Tác vụ | SOURCE | Kiểm tra kết quả trên iPhone |
| `nk.backend` | Chẩn đoán | SOURCE | Kiểm tra kết quả trên iPhone |
| `nk.runScript` | Tác vụ | SOURCE · HOST GUARD | Kiểm tra kết quả trên iPhone |
| `nk.legacyInputText` | Bàn phím | SOURCE · HOST GUARD | Kiểm tra kết quả trên iPhone |

## Mốc chất lượng trước khi build

1. **Hoàn tất static contract:** toàn bộ API trong danh mục tồn tại và không bị lỗi dây chuyền trong Lua; truyền đối số sai phải trả lỗi có mã thay vì thao tác bừa.
2. **Host logic tests:** bảng các nhóm Lua Core, Touch, InputText, Color, Vision, Clipboard, Recorder, HTTP/JSON, diagnostics có ít nhất một bài kiểm thử an toàn. Không gọi mạng thật, không gửi text bí mật khi test trên CI.
3. **Device evidence:** chạy thử từng nhóm trên iPhone rootless (người dùng chủ động bật kiểm tra có tương tác). Đặc biệt cần đo độ lệch tọa độ, RGB/JPEG, OCR, timeout, path gesture, app switch và input trên ứng dụng khác Notes.
4. **Không build sớm:** nhánh `v0.7.16-command-hardening-dev` chỉ có workflow kiểm tra nhanh Ubuntu; **không có workflow rootless/Theos hoặc publish** cho v0.7.16. Chỉ thêm release marker và workflow build khi đã đạt điều kiện chất lượng.

## Những giới hạn cần tách bạch

- `nk.inputText` đã được người dùng xác nhận trên Apple Notes; việc gửi lệnh thành công ở ứng dụng khác vẫn cần xác nhận chữ xuất hiện thật.
- `nk.inputPassword`: base64 trong kiến trúc thông báo phân tán không phải mã hóa. Không dùng thông tin xác thực thật trong test.
- Cảm ứng đơn có `tap/hold/swipe/path`; không suy luận là đã có multi-touch đồng thời.
- `frame.*` có thể dùng lại một ảnh, nhưng ảnh JPEG và màn hình xoay có khác biệt tọa độ/màu so với lấy pixel trực tiếp.
- `nk.http.*` đã qua test đầu vào lỗi trên máy host; kết nối mạng thực tế, TLS và timeout iPhone cần kiểm thử riêng.

**Cập nhật:** thực hiện trên nhánh phát triển; Sileo tiếp tục dùng v0.7.15 cho đến khi chốt kiểm thử toàn bộ.
