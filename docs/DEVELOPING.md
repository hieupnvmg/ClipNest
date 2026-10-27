# Phát triển ClipNest

## Build và kiểm tra

```sh
./build.sh
../ClipNest.app/Contents/MacOS/ClipNest --self-test
```

Build mặc định theo kiến trúc máy đang dùng, ký ad-hoc. Bản phát hành trong repo là Apple Silicon, chưa notarize. Bộ kiểm tra hiện có 259 kiểm tra tích hợp trên dữ liệu tạm.

## Dữ liệu

Lịch sử ở `~/Library/Application Support/ClipNest/history.sqlite3`. App dùng SQLite có sẵn trên macOS, lưu ảnh và rich text dưới dạng BLOB. JSON của bản cũ được tự nhập một lần, giữ bản `history.json.backup`; Clear cũng xóa bản dự phòng này. Settings tính database, WAL/SHM và bản dự phòng nếu có.

App nạp metadata và text/rich text vào bộ nhớ, chưa phân trang. Từ 0.5.8, ảnh gốc được tải theo nhu cầu từ bảng image_payloads trong SQLite. Lưu nền gộp các thay đổi liên tiếp trong khoảng 150 ms và flush khi thoát bình thường. Force quit trước khi commit có thể làm mất thay đổi cuối chưa ghi.

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

Quy tắc local nằm trong SensitiveContent.swift. Không gọi dịch vụ xác minh token, không tự gửi clipboard ra mạng khi nhận diện, không ghi nội dung phát hiện được vào log. Từ 0.5.3, default bật là mask-only cho cả secret và thông tin cá nhân: raw lưu trong SQLite để dán nguyên bản, presentation che khi nhận diện. Không còn skip theo pattern, kể cả qua editor; personalDataAction của bản cũ không còn được sử dụng. Danh sách app loại trừ và marker clipboard vẫn được giữ riêng.

Kiểm tra cả plain text, nhãn, HTML và RTF. Ảnh không được OCR. Số thẻ cần qua Luhn; regex email/phone có giới hạn, không bảo đảm phát hiện mọi dữ liệu nhạy cảm. Nội dung cũ/migration được che khi trình bày, không âm thầm xóa dữ liệu cũ.

Presentation được cache có giới hạn, bản dùng để render loại bỏ payload gốc khi che; cả nhãn accessibility dùng bản này. Mục đang che không gắn onDrag và không được mở editor trước khi reveal. Copy/paste là thao tác chủ động và dùng nguyên bản. Reveal hết hạn sau 15 giây hoặc khi bảng ẩn; editor đang hiển thị nội dung được bảo vệ cũng đóng và xóa draft khi hết hạn.

Các mẫu credential trong test đều là dữ liệu giả dựng tại runtime. Kiểm tra bao gồm lưu/mở lại secret nguyên bản trong SQLite, dán chính xác khi đang che, không thay clipboard, masking Unicode, Luhn, rich text, cache, preference, thời hạn reveal và editor.

Tham khảo định dạng: [GitHub secret-scanning patterns](https://docs.github.com/en/code-security/reference/secret-security/supported-secret-scanning-patterns), [Stripe authentication](https://docs.stripe.com/api/authentication).

## Cache feed OTA

Từ 0.5.4, dùng trực tiếp XML trên raw.githubusercontent.com. Sparkle ghi đè Accept thành `application/rss+xml,*/*;q=0.1`, nên GitHub Contents API trả JSON và không dùng được. Giữ signed-feed bắt buộc. Delegate thêm `clipnest_check` ngẫu nhiên mỗi request để giảm cache. Sau khi publish chạy `scripts/verify-update-feed.sh`: harness dùng chính Sparkle, public key trong app và mạng thật, không mở cửa sổ, tải bộ cài hoặc cài đặt. Nó phải nhận được bản mới và xác thực chữ ký thành công. Kiểm tra curl riêng lẻ không thay thế bước này.

Khi phát hành, upload asset và push feed xong, kiểm tra feed qua đúng endpoint/header app dùng rồi mới thay bản app trong Applications. Không chỉ xác minh bản local hoặc dùng API có đăng nhập của gh để suy ra kết quả client public.

## Startup và quyền hệ thống

LoginItemService dùng SMAppService.mainApp, đọc trạng thái thật thay vì lưu một boolean riêng. Không tự register khi mở app; chỉ khi người dùng bật Settings. requiresApproval có nút mở Login Items. Tests dùng service giả để tránh thay đổi Login Items của máy. Chưa kiểm tra qua một phiên đăng nhập macOS thật.

AccessibilityOnboarding lưu việc đã hỏi hoặc đã thấy trusted. Relaunch không hỏi lại khi denied/revoked; nút Settings vẫn chủ động xin quyền. Bản ad-hoc thay binary có thể bị macOS thu hồi trust; không giả lập hoặc bỏ qua trạng thái AXIsProcessTrusted.

## Liquid Glass

InterfaceStyle được lưu trong UserDefaults; mặc định Liquid Glass. ClipboardBackdrop dùng glassEffect chính chủ từ macOS 26, nhánh availability giữ minimum macOS 13. Standard và máy cũ dùng NSVisualEffectView. Reduce Transparency ưu tiên nền đặc cho cả hai style. Chỉ một bề mặt glass cho cửa sổ, nhóm control dùng viền/tint tĩnh, không blur riêng từng thẻ, không shader ngoài, timer hay animation thêm. Slider chỉ tác động backdrop, không làm mờ nội dung.

Self-test kiểm tra persistence, dữ liệu preference lỗi, lựa chọn rendering và accessibility. Preview hỗ trợ --standard-preview, --search-preview, --dark-preview. Bitmap offscreen chỉ kiểm tra bố cục, không thay thế đánh giá glass/GPU trong cửa sổ thật trên desktop. Chưa benchmark GPU hoặc thử runtime trên macOS 13–15.

## README demo GIF

`docs/demo.gif` được ghép từ ảnh preview offscreen của app bằng dữ liệu mẫu, không quay desktop/clipboard thật. `--preview-query <text>` và `--preview-selection <index>` chỉ phục vụ `--render-preview`. Không gọi copy/paste thật. Tạo các ảnh open.png, search.png, query-0.png đến query-5.png (d/de/des/desi/desig/design), selected.png (design, selection 1), sau đó chạy:

```sh
swift scripts/make-demo-gif.swift /path/to/frames docs/demo.gif
```

Script dùng AppKit/ImageIO có sẵn, tạo GIF 1200×420, 24 frame, lặp 8,2 giây. Giữ ảnh tĩnh sáng/tối trong README. Không cần build/phát hành phiên bản app mới cho thay đổi tài liệu này.

## Tối ưu 0.5.7

Capture tạo snapshot hoàn chỉnh rồi publish clips một lần. Retention không cấp phát danh sách mới/publish nếu chưa vượt giới hạn; mục loại bỏ giải phóng thumbnail và privacy cache, hủy reveal nếu có. didWrite và hideReveal bỏ qua Published assignment không đổi. HistoryDatabase bỏ qua transaction khi cả nội dung và thứ tự không đổi, nhưng luôn commit migration/Clear. PanelContent chỉ quan sát visibility; ClipboardContent được unmount khi ẩn, mount lại từ Store hiện tại khi mở. Store và capture timer vẫn hoạt động khi ẩn.

Chạy `../ClipNest.app/Contents/MacOS/ClipNest --performance-check` bằng dữ liệu giả + pasteboard riêng. Đo trên cùng máy, release build, 1.000 mục văn bản (~1 KB/mục):

| Phép đo | Trước | Sau |
| --- | --- | --- |
| 100 lần trim không thay đổi | 100 lần publish clips | 0 |
| Copy lại một mục | 3 lần publish clips | 1 |
| 100 lần save SQLite không thay đổi | 113,20 ms | 68,90 ms |

Đây là microbenchmark một lần, không phải tốc độ toàn app hay đo CPU/GPU khi sử dụng thật. 203 integration checks gồm SQLite no-op/migration, retention, thumbnail eviction và native search field mount/unmount khi panel ẩn/hiện. Chưa đo bằng Instruments.

Giới hạn này đã được xử lý ở 0.5.8: ảnh gốc tải theo nhu cầu từ SQLite, xem phần dưới.

## Ảnh tải theo nhu cầu (0.5.8)

Schema v2 thêm image_digest và bảng image_payloads riêng chứa PNG BLOB. Nâng cấp v1 tạo digest và chuyển từng ảnh trong transaction riêng (atomic/resumable), không gom BLOB vào mảng; bước chỉ mục chạy một lần. JSON legacy vẫn được nhập một lần như trước. Không xóa/mã hóa lại ảnh. Store dùng loadAndMigrate → load(includeImageData: false), SQL CASE bỏ payload ảnh, length(payload) và digest cung cấp reference. Chế độ load mặc định eager chỉ phục vụ kiểm tra/export, không dùng khi app khởi động.

Clip.imageReference chứa SHA-256 và byteCount, data nil khi ảnh đã được lưu. HistoryDatabase.persisted cũng chỉ giữ metadata ảnh. Save trả references; chỉ đúng saveRevision thành công mới bỏ data khỏi Store, pendingSnapshot, pendingSave và privacy cache. Save thất bại giữ data để retry. Ảnh có cùng digest vẫn giữ ID/pin/title khi recapture.

Metadata ảnh ở clips, ảnh gốc ở image_payloads để SQLite không phải dựng lại row chứa BLOB lớn khi đổi tên/ghim. Test ảnh 2 MB xác nhận đổi tên chỉ tạo WAL <128 KiB. Metadata update ảnh dùng UPDATE không có payload; reorder dùng clip_order. Deferred reference chưa tồn tại không được insert với payload NULL. Copy/dán UI và drag provider đọc ảnh gốc ở luồng nền, không re-encode. Copy lỗi không clear pasteboard; callback cũ không ghi đè hành động copy mới hoặc clipboard thay đổi trong lúc đọc. Direct paste ảnh bị hủy nếu panel đã đóng trước callback. writeClipboard đồng bộ được giữ cho tests/đường gọi cần kết quả ngay.

ImagePipeline serial OperationQueue giới hạn một decode thumbnail một lúc. Task cancellation bỏ đọc BLOB đang chờ; đang đọc/decode sẽ dừng ở điểm kiểm tra tiếp theo. Thumbnail tối đa 600 px được vẽ sang bitmap độc lập để không giữ provider PNG gốc, rồi đưa vào NSCache mục tiêu 32 MiB. NSCache là giới hạn mềm; ảnh đang hiện cũng giữ thumbnail riêng. LazyHStack có thể chuẩn bị một số thẻ gần vùng nhìn thấy. Sau await phải kiểm tra item vẫn tồn tại trước khi đưa vào cache. Clear/delete không bị callback thumbnail khôi phục ảnh.

203 integration checks gồm metadata-only startup, nâng cấp schema v1, byte-exact copy/drag, giữ ảnh khi lưu lỗi, dedup, metadata writes, cache reuse, queued cancellation, malformed image và stale copy. Self-test chạy async trên MainActor để không chặn tác vụ UI/timer.

### Đo bộ nhớ

```sh
../ClipNest.app/Contents/MacOS/ClipNest --image-memory-benchmark
```

Fixture gồm 100 PNG mẫu, 1.629.021 byte/ảnh. Mỗi chế độ đọc chạy trong tiến trình mới, không dùng clipboard hay lịch sử thật:

| Chế độ | Bytes ảnh gốc giữ trong Clip | Peak RSS | Thời gian mở + đọc |
| --- | --- | --- | --- |
| Eager | 155,36 MiB | 189,66 MiB | 42,9 ms |
| Metadata/lazy | 0 MiB | 30,95 MiB | 2,3 ms |
| Nâng cấp v1 + lazy | 0 MiB | 44,44 MiB | 836,2 ms |

Đây là phép đo riêng đường đọc lịch sử, không phải RAM của toàn bộ UI; RSS thực tế còn phụ thuộc ảnh đang xem, clipboard hệ thống và cache. Lần đầu nâng cấp v1 cần đọc/hash từng ảnh. Text/RTF/HTML vẫn được nạp như trước; lịch sử văn bản rất lớn chưa chuyển lazy. Chưa profile cuộn bằng Instruments trên nhiều đời Mac.

## Push to pikab.in (0.5.9)

Tham chiếu: form/JavaScript đang chạy tại https://pikab.in/ và mô tả trong chat “Khám phá API Pikab.in”. Đây là endpoint web, không có tài liệu API chính thức được công bố. Không dùng API key. Native URLSession ephemeral lấy cookie + meta csrf-token qua GET /, sau đó POST / với form URL-encoded UTF-8, X-CSRF-Token, X-Requested-With, Accept JSON, Referer. document[expired_at]=604800, syntax=plain, title=ClipNest (ASCII để tránh lỗi server với một số title tiếng Việt). Chỉ gửi text gốc của mục được chọn, không gửi RTF/HTML, tên ứng dụng nguồn, ảnh hay lịch sử.

PikabinClient tắt cache và không theo redirect. Chỉ chấp nhận HTTP201 với uri HTTPS đúng host pikab.in, một path ID, không query/credentials. Lỗi không đưa raw server body vào UI/log. Không tự retry POST, tránh tạo nhiều paste khi response không rõ. Giới hạn client <5 MB phù hợp capture hiện tại, không khẳng định giới hạn dịch vụ. Timeout request30s/resource60s; cookie/token chỉ nằm trong phiên bộ nhớ.

PikabinSharing tách lỗi upload khỏi lỗi history. Mục Text/Link/Color có action; Image/Files không có. Store kiểm tra lại trạng thái masked trước khi gửi; phải reveal chủ động. Sheet hiển thị progress, Cancel, lỗi/Retry hoặc URL + Copy link. Auto-copy chỉ nếu pasteboard changeCount chưa đổi. Hủy hoặc đóng panel tăng generation, cancel Task, bỏ draft; response về muộn không mở lại UI/copy. Link được copy qua writeClipboard để không tái capture link vào history, nguyên bản của mục không đổi.

232 integration checks tổng cộng: encoding tiếng Việt/emoji/+&=, token parsing, expiration, validation URL, bootstrap/POST bằng URLProtocol, error/no automatic retry, duplicate click, cancellation, newer clipboard, explicit retry và masked/reveal guard. `--render-preview path --pikabin-preview` dùng mock, không gửi mạng/clipboard thật.

Live smoke test (chỉ chạy khi cần kiểm tra tích hợp thật):

```sh
../ClipNest.app/Contents/MacOS/ClipNest --pikabin-smoke-test
```

Lệnh tạo một paste từ mẫu cố định không có dữ liệu cá nhân, hết hạn1tuần, đọc .raw và so sánh byte text. Đã xác nhận client Swift tạo link thành công, raw tiếng Việt/emoji/ký tự reserved đúng nguyên bản; trang HTML HTTP200 hiển thị “7 days”. Self-test bình thường dùng stub, không gọi PikaBin.

## Password generator (0.5.10)

Nút Password cố định cạnh vùng pinboard, mở sheet không gọi mạng. SecRandomCopyBytes cung cấp byte CSPRNG của Apple, rejection sampling bỏ modulo bias. Candidate thiếu một nhóm ký tự được tạo lại hoàn toàn, không ép vị trí cố định. Độ dài12–64, default20; luôn có lowercase/uppercase/digit, symbols mặc định bật. RNG lỗi phải fail closed, không fallback Math.random hay giá trị dự đoán được.

Model không lưu preferences hay draft vào disk; hide/regenerate/dismiss xóa/che nội dung tạm trên UI. Chỉ Copy mới ghi vào pasteboard và history. Title `Password: generated` dùng rule contextual-secret hiện có để mục được full-mask mà không cần đổi schema. Original vẫn lưu plaintext như lịch sử hiện tại, không phải password vault. Copy lặp giữ ID/pin. Chưa Copy thì chỉ nằm trong model tạm. Không tự đẩy mật khẩu lên PikaBin.

259 checks gồm các sample12/20/64 ký tự có/không symbols, category coverage, rejection sampling, invalid input/RNG failure, lifecycle model, private pasteboard roundtrip, history mask/restart/dedup. Preview `--render-preview path --password-preview` chỉ dùng dữ liệu tạm và không copy password.
