# ZaloBackupPro

Dylib inject vao Zalo de backup/restore tin nhan, anh, video.

## Tinh nang
- Floating button keo duoc tren man hinh
- Backup: DB + Media -> chon thu muc tuy chinh hoac Files app
- Restore: chon ban backup de khoi phuc

## Cach dung
1. Push code len GitHub
2. Vao tab **Actions** -> chay workflow **Build ZaloBackupPro dylib**
3. Tai file `ZaloBackupPro.dylib` tu Artifacts
4. Inject vao IPA Zalo bang Esign/GBox

## Compile thu cong (can Mac)
```
clang -arch arm64 -isysroot $(xcrun --sdk iphoneos --show-sdk-path) \
  -framework Foundation -framework UIKit -framework UniformTypeIdentifiers \
  -mios-version-min=13.0 -dynamiclib -o ZaloBackupPro.dylib Sources/ZaloBackupPro.m
```
