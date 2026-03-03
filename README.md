# ZaloBackupPro
Dylib inject vào Zalo để backup/restore tin nhắn, ảnh, video.

## Tính năng
- Floating button (Nút nổi) có thể kéo thả.
- Backup: DB + Media vào thư mục Documents của App hoặc Files App.
- Restore: Chọn bản backup để khôi phục.

## Cách dùng
1. Push code lên GitHub.
2. Vào tab **Actions** -> Chạy workflow **Build ZaloBackupPro dylib**.
3. Tải file `ZaloBackupPro.dylib` từ Artifacts.
4. Inject vào IPA Zalo bằng Esign, GBox hoặc Sideloadly.

## Compile thủ công (Cần Mac)
```bash
clang -arch arm64 -isysroot $(xcrun --sdk iphoneos --show-sdk-path) \
  -framework Foundation -framework UIKit -framework UniformTypeIdentifiers \
  -mios-version-min=13.0 -dynamiclib -o ZaloBackupPro.dylib ZaloBackupPro.m