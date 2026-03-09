# Hướng dẫn Setup Supabase

## Bước 1: Tạo bảng trên Supabase

1. Truy cập [Supabase Dashboard](https://supabase.com/dashboard)
2. Chọn project của bạn: `pzzxyobutvlbmwjtnqpm`
3. Vào **SQL Editor** (biểu tượng database bên trái)
4. Copy toàn bộ nội dung file `supabase_schema.sql` và paste vào
5. Click **Run** để tạo các bảng

## Bước 2: Cài đặt dependencies

Chạy lệnh sau để cài đặt package Supabase:

```bash
flutter pub get
```

## Bước 3: Chạy ứng dụng

```bash
flutter run
```

## Cấu trúc dữ liệu

### Bảng `dht_data` - Dữ liệu nhiệt độ và độ ẩm
- `id`: ID tự động tăng
- `temperature`: Nhiệt độ (°C)
- `humidity`: Độ ẩm (%)
- `created_at`: Thời gian ghi nhận

### Bảng `gas_data` - Dữ liệu cảm biến khí gas
- `id`: ID tự động tăng
- `mq_ao`: Giá trị analog từ cảm biến MQ
- `threshold`: Ngưỡng cảnh báo
- `gas_alarm`: Trạng thái cảnh báo (true/false)
- `created_at`: Thời gian ghi nhận

### Bảng `device_states` - Trạng thái thiết bị
- `id`: ID tự động tăng
- `device_name`: Tên thiết bị ('light' hoặc 'fan')
- `state`: Trạng thái (true = bật, false = tắt)
- `created_at`: Thời gian thay đổi

## Tính năng đã tích hợp

✅ Tự động lưu dữ liệu DHT22 lên Supabase khi nhận từ MQTT
✅ Tự động lưu dữ liệu cảm biến gas lên Supabase
✅ Tự động lưu trạng thái đèn/quạt khi bật/tắt
✅ Có thể truy vấn lịch sử dữ liệu qua các hàm:
  - `SupabaseService.getDhtHistory()`
  - `SupabaseService.getGasHistory()`
  - `SupabaseService.getDeviceHistory()`

## Xem dữ liệu trên Supabase

1. Vào **Table Editor** trên Supabase Dashboard
2. Chọn bảng muốn xem: `dht_data`, `gas_data`, hoặc `device_states`
3. Dữ liệu sẽ tự động cập nhật khi ứng dụng chạy

## Lưu ý bảo mật

- Hiện tại đang dùng `anon key` cho phép public access
- Nếu cần bảo mật cao hơn, hãy cấu hình Row Level Security (RLS) policies
- Có thể thêm authentication để chỉ user đã đăng nhập mới được truy cập
