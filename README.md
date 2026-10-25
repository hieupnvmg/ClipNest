<p align="center">
  <img src="Assets/AppIcon.png" width="100" alt="ClipNest icon">
</p>

<h1 align="center">ClipNest</h1>
<p align="center"><strong>Giữ lại những gì bạn copy. Tìm lại ngay khi cần.</strong></p>
<p align="center">Một ứng dụng clipboard gọn gàng dành cho Mac, được tạo bởi <a href="https://github.com/hieupnvmg">hieupn</a>.</p>
<p align="center"><a href="https://github.com/hieupnvmg/ClipNest/releases/latest/download/ClipNest-0.3.0-Apple-Silicon.dmg"><strong>↓ Tải ClipNest cho Mac</strong></a> · Apple Silicon · macOS 13 trở lên</p>

![Giao diện ClipNest với dữ liệu minh họa](docs/preview.png)

Bạn vừa copy một đường link, rồi copy tiếp một đoạn văn và mất nội dung trước đó? ClipNest giữ lại lịch sử để bạn có thể tìm và dùng lại bất cứ lúc nào.

### Có gì trong ClipNest?

- **Lịch sử clipboard:** lưu văn bản, đường link, ảnh, mã màu và tham chiếu file.
- **Tìm kiếm tức thì:** mở bằng `⌘⇧V`, gõ từ khóa và nhấn `Enter` để dán.
- **Pinboard:** gom ghi chú, link và nội dung hay dùng vào từng nhóm riêng.
- **Dán theo cách bạn muốn:** giữ định dạng hoặc dán văn bản thuần.
- **Giao diện gọn:** các thẻ nội dung hiện ở cạnh dưới màn hình; nhấn `Esc` một lần để đóng.
- **Chủ động quản lý:** tạm dừng ghi nhận, loại trừ ứng dụng, xem dung lượng và xóa lịch sử trong Settings.

### Cài đặt

1. [Tải file DMG](https://github.com/hieupnvmg/ClipNest/releases/latest/download/ClipNest-0.3.0-Apple-Silicon.dmg).
2. Mở file, kéo **ClipNest** vào **Applications**.
3. Mở ClipNest và bắt đầu copy. App nằm trên menu bar.
4. Để dán thẳng sang ứng dụng khác, cấp quyền tại **System Settings → Privacy & Security → Accessibility → ClipNest**. Nếu chưa cấp quyền, chọn một mục rồi nhấn `⌘V` để dán.

Bản hiện tại: **0.3.0**, dành cho **Mac M1 trở lên, macOS 13+**. Chưa có bản Mac Intel. App chưa được Apple notarize; nếu macOS chặn do chưa xác minh nhà phát triển, xem [hướng dẫn mở app của Apple](https://support.apple.com/en-au/102445).

### Phím tắt

| Phím | Thao tác |
| --- | --- |
| `⌘⇧V` | Mở / đóng ClipNest |
| Gõ ngay sau khi mở | Tìm trong lịch sử |
| `Enter` | Dán mục đang chọn |
| `↓`, rồi `←` / `→` | Chuyển sang chọn các thẻ |
| `⌘1` đến `⌘9` | Dán nhanh một trong chín mục đầu |
| `⌘F` | Quay lại ô tìm kiếm |
| `Esc` | Đóng bảng clipboard |

### Dữ liệu ở trên máy bạn

ClipNest không cần tài khoản và không đồng bộ iCloud. Lịch sử được lưu cục bộ trên từng Mac, không được app gửi lên máy chủ. App bỏ qua các ứng dụng trong danh sách loại trừ và các nội dung clipboard có đánh dấu bí mật; bạn vẫn nên tạm dừng ghi nhận khi xử lý thông tin nhạy cảm. Lịch sử không có mã hóa riêng ở tầng ứng dụng.

Settings hiển thị dung lượng đang dùng và có nút **Clear**. Clear xóa cả các mục đã ghim sau khi bạn xác nhận. File được lưu dưới dạng tham chiếu; nếu bạn di chuyển hoặc xóa file gốc thì tham chiếu có thể không còn dùng được.

### Góp ý

Bạn gặp lỗi hoặc muốn thêm tính năng? [Tạo một issue](https://github.com/hieupnvmg/ClipNest/issues) để chia sẻ nhé.

<details>
<summary>Dành cho người muốn tự build</summary>

Cần macOS và Apple Command Line Tools có Swift 5.9 trở lên.

```sh
./build.sh
../ClipNest.app/Contents/MacOS/ClipNest --self-test
```

App được tạo ở thư mục bên cạnh repo. Các bài kiểm tra dùng dữ liệu tạm, không thay đổi lịch sử thật. Xem [ghi chú phát triển](docs/DEVELOPING.md) nếu cần thêm thông tin.

</details>
