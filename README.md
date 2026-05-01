#  Mobile Game Telemetry Data Warehouse

##  Overview

Dự án này là một Data Engineering pipeline end-to-end mô phỏng hệ thống phân tích dữ liệu viễn trắc (telemetry) cho một tựa game mobile. Hệ thống tự động giả lập hành vi người chơi, xử lý dữ liệu qua kiến trúc Medallion (Bronze - Silver - Gold), điều phối tự động và xây dựng các Data Marts sẵn sàng cho phân tích.
- **Vấn đề giải quyết:** Xây dựng một luồng dữ liệu đáng tin cậy để phân tích hành vi người chơi (engagement, retention), theo dõi tiến trình (funnel) và đối soát doanh thu game.
- **Nguồn dữ liệu:** Dữ liệu giả lập (mock data) về users, devices, events (login, tutorial, level_up) và purchases được tạo bằng Python/Faker và lưu trữ thô tại MongoDB.
- **Kết quả đầu ra:** Dữ liệu Parquet được làm sạch (Silver), các bảng Dimension/Fact lưu tại MySQL (Gold), các SQL Views (Data Marts) phân tích chuyên sâu, và một báo cáo Power BI

##  Architecture


Luồng xử lý của hệ thống:

1. Script Python giả lập hành vi người chơi và đẩy dữ liệu JSON thô vào MongoDB (Tầng Bronze)
2. PySpark đọc dữ liệu từ MongoDB, làm sạch, chuẩn hóa và lưu thành các file Parquet phân vùng theo ngày (Tầng Silver).
3. Job load dữ liệu dùng PySpark JDBC để thực hiện UPSERT từ Parquet vào MySQL, kết hợp hàm COALESCE thông minh để bảo toàn dữ liệu lịch sử (Tầng Gold).
4. Các SQL Scripts tự động tổng hợp dữ liệu thành các Data Marts (ví dụ: vw_user_journey, vw_paying_users).
5. Toàn bộ luồng batch daily được điều phối (Orchestration) nhịp nhàng thông qua Prefect.
6. Power BI kết nối trực tiếp vào Tầng Gold để lên biểu đồ trực quan hóa.

##  Chi tiết Pipeline

- **Extract / Ingest:** `bronze/generate_bronze_data.py` chịu trách nhiệm sinh dữ liệu người chơi mới và các sự kiện in-game, sau đó đẩy trực tiếp vào MongoDB.

- **Transform:** `silver/jobs/process_events.py` sử dụng PySpark để đọc dữ liệu thô, bóc tách cấu trúc JSON, ép kiểu dữ liệu và ghi ra định dạng Parquet tại Tầng Silver.

- **Load:** `silver/jobs/load_gold.py` sử dụng kỹ thuật Upsert (INSERT ... ON DUPLICATE KEY UPDATE) để đẩy dữ liệu vào MySQL. Đặc biệt có cơ chế chống đè dữ liệu NULL cho các trường thông tin tĩnh (như platform, country).

- **Orchestration:** DSử dụng Prefect để quản lý các task dependencies, đảm bảo luồng chạy batch hàng ngày diễn ra đúng thứ tự và dễ dàng theo dõi log/lỗi.

- **Data Quality / Validation:** Áp dụng Data Validation ngay tại Tầng Silver để loại bỏ sự kiện lỗi. Tầng Gold xử lý triệt để bài toán SCD Type 1 .



##  Project Structure

```text
mobile-game-dwh/
|-- bronze/                     # Script sinh dữ liệu giả lập & nạp vào MongoDB
|-- silver/                     # Job PySpark xử lý Parquet & Logic Upsert lên Gold
|-- gold/                       # DDL của MySQL & Business Rules cho Data Marts
|-- logs/                       # System logs
|-- utils/                      # Helper functions (Logger, Config)
|-- run_backfill.py             # Script chạy nạp lại dữ liệu lịch sử
|-- run_marts.py                # Script trigger build Data Marts
|-- game_dashboard.pbix         # File báo cáo Power BI
|-- requirements.txt            # Danh sách thư viện Python
`-- README.md
```


##  How to Run

1. Hướng dẫn cài đặt & Chạy dự án

```bash
git clone <repo-url>
cd mobile-game-dwh
```

2. Thiết lập môi trường ảo Conda.

```bash
conda create -n game_dwh python=3.10
conda activate game_dwh
pip install -r requirements.txt
```

3. Cấu hình biến môi trường.

Đổi tên file `.env.example` thành `.env` và điền thông tin kết nối MongoDB, MySQL và thư mục lưu trữ cục bộ.

4. Khởi tạo dữ liệu thô (Bronze).

```bash
python bronze/generate_bronze_data.py
```

5. Chạy luồng xử lý chính.

```bash
# Biến đổi Bronze -> Silver
python -m silver.jobs.process_events

# Load Silver -> Gold
python run_backfill.py --start 2026-01-26 --end 2026-04-17

# Build SQL Marts
python run_marts.py --date 2026-04-17
```

6. Kích hoạt Orchestration với Prefect.

```bash
prefect server start
```


##  Kết quả

- Dữ liệu thô được lưu trữ an toàn dưới định dạng Parquet có phân vùng.
- Bảng Dimension và Fact trong MySQL chuẩn xác, không bị lỗi mất mát thông tin khi Upsert.
- Các View phân tích sẵn sàng trả lời các câu hỏi về DAU, MAU, Retention, Funnel Drop-off và Revenue.
- Bảng điều khiển (Dashboard) trên Power BI hoạt động trơn tru.


##  Bài học kinh nghiệm

- Nắm vững cách thiết kế và triển khai kiến trúc Medallion Data Architecture cho luồng dữ liệu viễn trắc.
- Giải quyết triệt để bài toán Anti-Null Overwrite khi thực hiện thao tác Upsert giữa PySpark và hệ quản trị CSDL quan hệ (MySQL).
- Quản lý và khắc phục hiệu quả các xung đột môi trường (Mismatched Environments) giữa Python, thư viện nội bộ và Java JVM trên môi trường Local.
- Tích hợp và lên lịch tự động thành công toàn bộ Pipeline thông qua Prefect.
