# Novel App

Ứng dụng ghi chú và viết truyện đơn giản, giao diện tối, viết bằng Flutter thuần
(không dùng thư viện ngoài) do **azrael** thiết kế.

## Tính năng

- Tạo, sửa bài viết với bộ đếm từ theo thời gian thực.
- Ghim bài quan trọng lên đầu; bài sửa gần nhất xếp trước.
- Tìm kiếm theo tiêu đề và nội dung.
- Xem dạng lưới hoặc dạng danh sách.
- Mục tiêu số từ viết mỗi ngày (bấm vào ô mục tiêu để đổi), tự tính lại mỗi ngày.
- Đổi màu chủ đề (bấm biểu tượng ngôi sao).
- Nhấn giữ một bài viết để xóa.
- Nút Back của điện thoại cũng tự lưu bài đang viết.

> Lưu ý: dữ liệu hiện chỉ nằm trong bộ nhớ, thoát hẳn ứng dụng thì bài viết sẽ mất.
> Muốn lưu lâu dài cần thêm thư viện lưu trữ (ví dụ `shared_preferences`).

## Cấu trúc

```
lib/main.dart                       Toàn bộ mã nguồn ứng dụng
test/widget_test.dart               Kiểm thử tự động
pubspec.yaml                        Khai báo dự án
analysis_options.yaml               Quy tắc kiểm tra mã
.github/workflows/build.yml         Tự động build file APK
```

Thư mục `android/` không nằm trong repo, workflow sẽ tạo lại bằng
`flutter create` mỗi lần build.

## Tải file APK từ GitHub

1. Đưa mã lên nhánh `main` (hoặc vào tab **Actions** rồi bấm **Run workflow**).
2. Chờ workflow **Build Android APK** chạy xong.
3. Mở lần chạy đó, kéo xuống mục **Artifacts** và tải `novel-app-release-apk`.
4. Giải nén, cài `app-release.apk` lên điện thoại Android.

## Chạy trên máy tính

Cần cài Flutter 3.22 trở lên.

```bash
flutter create . --project-name=novel_app --platforms=android --org=com.azrael.novelapp
flutter pub get
flutter test
flutter run
```
