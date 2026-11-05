# NKTouch v0.7.19 — Test Lab 5 lõi

**Nhánh:** `v0.7.19-testlab-5core-dev`. **Trạng thái:** beta, cần kiểm tra trên iPhone; workflow chỉ tạo artifact, không tự phát hành Sileo.

## Vào Test Lab
1. NKTouch → **NKTouch Test Lab** ở dashboard; hoặc Lua Library → Samples → **Test Lab • 5 lõi + nâng cao**.
2. Mặc định đã chọn **OCR**, **Color**, **Touch**, **InputText**, **Memory**. Nhấn **5 lõi** để chọn lại preset này. Có thể chọn thêm Lua Runtime, Vision Core, Network & JSON và Task Stability.
3. Nhấn **Tạo bài kiểm tra → Lua Editor**, sau đó nhấn **Chạy** bằng Task Engine hiện có. Không chạy tác vụ ngầm.
4. Trở về Test Lab → **Báo cáo** để xem kết quả từng phép thử, thời gian, PASS/FAIL/WARN/SKIP và sao chép báo cáo. Log đầy đủ có trong Task Center.

## Ý nghĩa các bài thử
- **OCR**: chụp một immutable frame để gọi `frame:ocr`, tiếp tục gọi đường live `nk.ocr` với một ảnh riêng. Nếu frame thất bại nhưng live thành công, báo **FAIL FRAME_OCR_BROKEN**; thông báo lỗi native (nếu có) được ghi lại. Không ghi nội dung OCR để tránh lộ thông tin trên màn hình.
- **Color**: kiểm chứng kích thước physical pixel, mã RGB packed, sai số màu và tìm đúng vị trí 1 pixel.
- **Touch**: mặc định chỉ kiểm tra tọa độ sai bị chặn và đường đi không hợp lệ. Không thực hiện tap, hold hay swipe thật.
- **InputText**: mặc định kiểm tra Unicode, UTF-8, chặn chuỗi rỗng và bảo vệ mật khẩu. Không tự nhập dữ liệu.
- **Memory**: chụp và đóng 10 frame theo mặc định (có thể thay `memory.loops` từ 3 đến 30), kiểm tra lazy RGBA, Lua heap, RSS trước/sau warmup và full Lua GC. Tăng RSS trên 8 MiB sau warmup được đánh dấu WARN để điều tra; không tự kết luận rò rỉ bộ nhớ.

## Tùy chọn thử Touch / InputText thật
Trong Lua Editor, việc tự sửa `enabled=true` **chưa đủ**. Cần đồng thời `confirmed=true`, chính xác bundle ID app foreground và tọa độ pixel hợp lệ. Chỉ thử trên app/màn hình không có dữ liệu nhạy cảm; không dùng mật khẩu thật. Không tự retry lệnh thay đổi trạng thái khi kết quả chưa rõ.

## Báo cáo
- JSON nguyên tử: `/var/mobile/Library/NKTouch/tmp/testlab-last.json`.
- Các log: `[NKLAB][PASS]`, `[NKLAB][FAIL]`, `[NKLAB][WARN]`, `[NKLAB][SKIP]`, `[NKLAB][SUMMARY]`, `[NKLAB][MEM_PROGRESS]`.
- `PASS` thể hiện kiểm tra đã chạy thành công, **không chứng minh touch/InputText tác động chính xác lên giao diện**, không chứng minh OCR nhận diện đúng văn bản nếu nội dung trống.
- `WARN` cho phép kiểm tra có giới hạn bằng chứng hoặc biến động RSS. `SKIP` thể hiện phép thử chưa thực hiện.
- 7 nhóm cũ vẫn được hỗ trợ; mặc định chung `nktestlab.run({})` giữ 7 nhóm để không làm hỏng script trước đó. Preset 5 lõi được chọn từ giao diện.

## Tiêu chí kiểm thử trước khi phát hành chính thức
- Build Objective-C/UI, Lua native, Theos rootless và đóng gói .deb thành công.
- Chạy Test Lab 5 lõi trên iPhone với nội dung OCR nhìn thấy rõ, kiểm tra lại `frame:ocr` thành công.
- Kiểm tra 30 lần frame+OCR, RSS không tăng vô hạn, `exit_code=0` và không có `signal=11`.
- Thử Touch / InputText trên app thử nghiệm riêng với xác nhận của người vận hành.
