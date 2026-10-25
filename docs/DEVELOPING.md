# Phát triển ClipNest

## Build và kiểm tra

```sh
./build.sh
../ClipNest.app/Contents/MacOS/ClipNest --self-test
```

Build mặc định theo kiến trúc máy đang dùng, ký ad-hoc. Bản phát hành trong repo là Apple Silicon, chưa notarize. Bộ kiểm tra hiện có 78 kiểm tra tích hợp trên dữ liệu tạm.

## Dữ liệu

Lịch sử ở `~/Library/Application Support/ClipNest/history.sqlite3`. App dùng SQLite có sẵn trên macOS, lưu ảnh và rich text dưới dạng BLOB. JSON của bản cũ được tự nhập một lần, giữ bản `history.json.backup`; Clear cũng xóa bản dự phòng này. Settings tính database, WAL/SHM và bản dự phòng nếu có.

App vẫn nạp lịch sử vào bộ nhớ; chưa phân trang hoặc tải blob theo nhu cầu. Lưu nền gộp các thay đổi liên tiếp trong khoảng 150 ms và flush khi thoát bình thường. Force quit trước khi commit có thể làm mất thay đổi cuối chưa ghi.

## Ảnh minh họa

`docs/preview.png` được render từ giao diện ứng dụng với dữ liệu giả, không chứa lịch sử clipboard cá nhân. Icon ClipNest được tạo bằng công cụ tạo ảnh AI.

## Phát hành OTA

App dùng Sparkle 2.10.0 và feed HTTPS `updates/appcast.xml`. Feed và archive phải có chữ ký Ed25519; archive được xác minh trước khi giải nén. Private key nằm trong login Keychain, account `ClipNest-updates`. Chỉ public key trong `Assets/UpdatePublicKey.txt` được đưa vào repo. Không tạo key mới cho các bản sau; cần giữ Keychain này an toàn để tiếp tục ký cập nhật.

Đổi version/build number trong `build.sh`, version hiển thị và README, thêm ghi chú vào `updates/<version>.md`, rồi chạy:

```sh
./package-release.sh
```

Script build app, đóng gói DMG/ZIP, sinh feed và kiểm tra chữ ký. Upload DMG lên GitHub Release đúng tag trước, sau đó mới push `updates/appcast.xml`. Người dùng bản trước 0.4.0 cần nâng cấp thủ công một lần.

Tự kiểm tra bật mặc định, cài đặt cần người dùng xác nhận. Không bật system profiling. Bản ad-hoc hiện tại vẫn chưa notarize; macOS có thể yêu cầu cấp lại Accessibility sau khi thay app. App chỉ gọi API xin quyền và mở Settings, không tự bật quyền.

## Giao diện

Opacity chỉ áp dụng cho nền NSVisualEffectView, không làm mờ chữ/thẻ. Giá trị 35–100%, mặc định 90%, lưu trong UserDefaults. Settings có thể cuộn trên màn hình nhỏ.
