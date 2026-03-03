# ZaloBackupPro (Bản Final - Siêu Sạch)

Dylib hỗ trợ Sao lưu (Backup) và Khôi phục (Restore) toàn bộ tin nhắn, hình ảnh, video của Zalo trực tiếp trên iPhone.

## Tính năng nổi bật
- **Hết nháy (No Flickering):** Nút nổi chỉ hiện 1 lần duy nhất khi app sẵn sàng.
- **Mượt mà (No Lag):** Không gây liệt cảm ứng, không chặn các thao tác chat của Zalo.
- **Chống Crash:** Tối ưu bộ nhớ khi xử lý lượng tin nhắn/hình ảnh lớn.
- **Quản lý dễ dàng:** Dữ liệu được lưu trong folder `ZaloBackupPro_Data` tại ứng dụng "Tệp" (Files).

## Cấu trúc Repo chuẩn
- `.github/workflows/main.yml` (Script build tự động)
- `ZaloBackupPro.m` (Code chính)
- `README.md` (Hướng dẫn này)

## Cách Build và Cài đặt
1. **Build:** Push code lên GitHub -> Vào tab **Actions** -> Chọn **Build ZaloBackupPro dylib** -> Chọn **Run workflow**.
2. **Tải file:** Tải file dylib từ mục **Artifacts** sau khi build hoàn tất.
3. **Inject:** Dùng Esign, GBox hoặc Sideloadly để inject dylib vào IPA Zalo.
4. **LƯU Ý QUAN TRỌNG:** Khi ký (Sign) IPA bằng Esign, bạn **PHẢI** bật tùy chọn **"Enable File Sharing"** (Hỗ trợ chia sẻ file) thì folder backup mới hiển thị trong ứng dụng Files.

## Cách sử dụng
- Nhấn nút **ZPRO** nổi trên màn hình để mở Menu.
- **Backup:** Toàn bộ tin nhắn và media sẽ được copy vào folder `ZaloBackupPro_Data`.
- **Restore:** Chọn khôi phục để ghi đè dữ liệu cũ (Zalo sẽ tự thoát để nạp lại dữ liệu).

## Cảnh báo
- Việc khôi phục (Restore) sẽ ghi đè toàn bộ dữ liệu hiện tại của App. Hãy sao lưu kỹ trước khi thực hiện.