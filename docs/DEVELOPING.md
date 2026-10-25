# Phát triển ClipNest

## Build và kiểm tra

```sh
./build.sh
../ClipNest.app/Contents/MacOS/ClipNest --self-test
```

Build mặc định theo kiến trúc máy đang dùng, ký ad-hoc. Bản phát hành trong repo là Apple Silicon, chưa notarize. Bộ kiểm tra hiện có 143 kiểm tra tích hợp trên dữ liệu tạm.

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

## Tự bảo vệ nội dung nhạy cảm

Quy tắc local nằm trong SensitiveContent.swift. Không gọi dịch vụ xác minh token, không gửi clipboard ra mạng, không ghi nội dung phát hiện được vào log. Từ 0.5.3, default bật là mask-only cho cả secret và thông tin cá nhân: raw lưu trong SQLite để dán nguyên bản, presentation che khi nhận diện. Không còn skip theo pattern, kể cả qua editor; personalDataAction của bản cũ không còn được sử dụng. Danh sách app loại trừ và marker clipboard vẫn được giữ riêng.

Kiểm tra cả plain text, nhãn, HTML và RTF. Ảnh không được OCR. Số thẻ cần qua Luhn; regex email/phone có giới hạn, không bảo đảm phát hiện mọi dữ liệu nhạy cảm. Nội dung cũ/migration được che khi trình bày, không âm thầm xóa dữ liệu cũ.

Presentation được cache có giới hạn, bản dùng để render loại bỏ payload gốc khi che; cả nhãn accessibility dùng bản này. Mục đang che không gắn onDrag và không được mở editor trước khi reveal. Copy/paste là thao tác chủ động và dùng nguyên bản. Reveal hết hạn sau 15 giây hoặc khi bảng ẩn; editor đang hiển thị nội dung được bảo vệ cũng đóng và xóa draft khi hết hạn.

Các mẫu credential trong test đều là dữ liệu giả dựng tại runtime. Kiểm tra bao gồm lưu/mở lại secret nguyên bản trong SQLite, dán chính xác khi đang che, không thay clipboard, masking Unicode, Luhn, rich text, cache, preference, thời hạn reveal và editor.

Tham khảo định dạng: [GitHub secret-scanning patterns](https://docs.github.com/en/code-security/reference/secret-security/supported-secret-scanning-patterns), [Stripe authentication](https://docs.stripe.com/api/authentication).

## Cache feed OTA

Từ 0.5.4, dùng trực tiếp XML trên raw.githubusercontent.com. Sparkle ghi đè Accept thành `application/rss+xml,*/*;q=0.1`, nên GitHub Contents API trả JSON và không dùng được. Giữ signed-feed bắt buộc. Delegate thêm `clipnest_check` ngẫu nhiên mỗi request để giảm cache. Sau khi publish chạy `scripts/verify-update-feed.sh`: harness dùng chính Sparkle, public key trong app và mạng thật, không mở cửa sổ, tải bộ cài hoặc cài đặt. Nó phải nhận được bản mới và xác thực chữ ký thành công. Kiểm tra curl riêng lẻ không thay thế bước này.

Khi phát hành, upload asset và push feed xong, kiểm tra feed qua đúng endpoint/header app dùng rồi mới thay bản app trong Applications. Không chỉ xác minh bản local hoặc dùng API có đăng nhập của gh để suy ra kết quả client public.
