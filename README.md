Mobile Game Telemetry Data Warehouse

Tổng Quan Dự Án (Project Overview)

Dự án này xây dựng một hệ thống Data Pipeline end-to-end để thu thập, xử lý và phân tích hành vi người chơi trong một tựa game mobile giả định. Mục tiêu cốt lõi là chuyển đổi các dòng log sự kiện (event logs) thô ráp thành những chỉ số phân tích kinh doanh (Business Metrics) mang tính quyết định.Hệ thống giúp trả lời hai câu hỏi sống còn của ngành game:

"Người chơi có quay lại không?" 

"Họ nạp tiền ở giai đoạn nào?" 

Dự án mô phỏng sát với thực tế luồng xử lý dữ liệu Batch Processing (xử lý theo lô) thường thấy ở các công ty công nghệ và studio game.

Mục Tiêu Kỹ Thuật (Learning Objectives)Data Engineering:

Ứng dụng mô hình Medallion Architecture (Bronze -> Silver -> Gold).

ETL/ELT Processing: Sử dụng PySpark để xử lý dữ liệu lớn, làm sạch và chuyển đổi định dạng từ NoSQL (JSON) sang Relational Database (Dạng bảng).

Advanced SQL: Áp dụng SQL nâng cao (Window Functions, CTEs, Joins phức tạp) trong MySQL 8.0 để giải quyết các bài toán phân tích đa chiều.

Data Modeling: Tự tay thiết kế Star Schema (Fact & Dimension tables) tối ưu cho việc truy vấn.

Kiến Trúc & Công Nghệ (Tech Stack & Architecture)Luồng dữ liệu di chuyển theo 3 tầng chuẩn mực:

Data Generation: Python (thư viện Faker) giả lập 100,000 sự kiện (login, làm nhiệm vụ, nạp tiền) dưới dạng JSON.

Bronze Layer (Data Lake/Raw): MongoDB tiếp nhận và lưu trữ toàn bộ dữ liệu JSON nguyên bản.

Silver Layer (Processing/Cleansing): PySpark đọc dữ liệu, bóc tách (flatten nested JSON), làm sạch dữ liệu lỗi, map ID và chuẩn hóa kiểu dữ liệu.

Gold Layer (Data Warehouse): MySQL 8.0+ lưu trữ dữ liệu đã được mô hình hóa theo dạng Star Schema.
Visualization: Power BI (Trực quan hóa dữ liệu thông qua Data Marts & Views).


Vòng Đời Cấu Trúc Dữ Liệu (Data Architecture & Schema)

Tầng Bronze (Raw JSON)
Dữ liệu thô gửi về từ Game Client chứa các cấu trúc lồng nhau (nested) phức tạp. 
Ví dụ một Common Wrapper:JSON{
  "event_uuid": "f47ac10b-58cc-4372-a567-0e02b2c3d479",
  "event_name": "tutorial_completed",
  "event_date": "2026-03-26",
  "client_timestamp": 1711442153000,
  "server_timestamp": 1711442154500,
  "app_version": "1.2.4",
  "user": {
    "user_id": "usr_102938",
    "session_id": "sess_abc123",
    "account_created_at": 1710000000000,
    "days_since_install": 3,
    "current_state": {
      "level": 15,
      "power_score": 12500,
      "gold_balance": 45000,
      "gem_balance": 150
    }
  },
  "device": {
    "device_id": "dev_xyz890",
    "platform": "iOS",
    "country": "VN"
  },
  "event_params": {
    "tutorial_version": "v1_combat_focus",
    "time_spent_seconds": 345
  }
}

Tầng Silver (Flattened Parquet)
PySpark làm phẳng dữ liệu JSON và phân tách thành các entity logic:
DIM_USERS: Lưu thông tin tĩnh hoặc thay đổi chậm (ngày tạo, kênh acquisition, thiết bị đầu tiên...).
FACT_EVENTS: Lưu snapshot trạng thái tại thời điểm event (level, power_score, balances).
FACT_EVENT_PARAMS & ITEMS: Chứa các tham số đặc thù theo từng loại event để tránh pha loãng bảng fact chính.

Tầng Gold (Star Schema & Data Marts)
Dữ liệu được tổ chức tối ưu cho BI Tools tại MySQL.
Các Bảng Core (Fact & Dim):
dim_device / dim_users fact_events: Track toàn bộ vòng đời sự kiện.
fact_progression: Track thời gian và chi phí thăng cấp.
fact_purchases: Track doanh thu In-App Purchase.

Các Data Marts (Pre-calculated):
mart_dau_mau / mart_session: Engagement Metrics.
mart_retention: Cohort Retention Heatmap.
mart_funnel / mart_level_progression: Phân tích điểm nghẽn và rơi rụng.
mart_arpu / mart_ltv / mart_revenue_daily: Phân tích Monetization.

Các Chỉ Số Phân Tích Cốt Lõi (Key Metrics Analytics)
Hệ thống Data Marts phục vụ việc tính toán và hiển thị trực tiếp các KPI:
User Engagement: Daily Active Users (DAU) và Monthly Active Users (MAU).C
ohort Retention: Phân tích tỷ lệ giữ chân tại Ngày 1 (D1), Ngày 7 (D7), Ngày 30 (D30).
Conversion Funnel: Tỷ lệ rơi rụng qua các bước: Đăng ký -> Xong Tutorial -> Nạp tiền lần đầu.Monetization: 
ARPU (Doanh thu trung bình trên mỗi User) và ARPPU (Doanh thu trên User nạp tiền).

Cấu Trúc Thư Mục Hệ ThốngPlaintextGame/
├── bronze/                 # Code sinh dữ liệu Faker và kết nối MongoDB
├── data/                   # Chứa file parquet output của Silver layer
├── gold/
│   ├── ddl/                # Khởi tạo Schema MySQL
│   └── mart/               # Chứa SQL logic cho Marts & Views (User, Engagement, Monetization, Progression)
├── silver/                 # Spark Jobs (Làm sạch, Flatten, Chuẩn hóa)
├── .env                    # Environment variables (DB config)
├── build_marts.py          # Orchestration script chạy SQL tự động theo thứ tự Dependency
└── setup.py / requirements.txt
