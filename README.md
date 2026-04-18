Mobile Game Telemetry Data Warehouse📌 Tổng quan dự án (Project Overview)Dự án này xây dựng một hệ thống Data Pipeline end-to-end để thu thập, xử lý và phân tích hành vi người chơi trong một tựa game mobile. Hệ thống chuyển đổi các dòng log sự kiện thô (JSON) thành các chỉ số kinh doanh cốt lõi (Business Metrics) như Retention, DAU/MAU, và Conversion Funnel bằng kiến trúc Medallion.🏗️ Kiến trúc hệ thống (Architecture)Dự án tuân thủ mô hình Medallion Architecture:Bronze Layer (Raw): Lưu trữ dữ liệu log nguyên bản dưới dạng NoSQL (JSON) trong MongoDB.Silver Layer (Cleansing): Sử dụng PySpark để làm sạch, bóc tách (flatten) và chuẩn hóa kiểu dữ liệu, lưu trữ dưới dạng Parquet.Gold Layer (Warehouse): Mô hình hóa dữ liệu theo Star Schema trong MySQL để phục vụ phân tích đa chiều và báo cáo.📊 Cấu trúc dữ liệu (Data Structures)🥉 Bronze Layer (Raw JSON)Dữ liệu thô từ Game Client gửi về có cấu trúc lồng nhau (nested):JSON{
  "event_id": "uuid-12345",
  "event_name": "tutorial_completed",
  "user_id": "user_99",
  "timestamp": "2026-04-17T10:00:00Z",
  "properties": {
    "level_reached": 5,
    "device": { "model": "iPhone 15", "platform": "iOS" },
    "location": "map_01"
  }
}
🥈 Silver Layer (Flattened Parquet)Dữ liệu sau khi qua PySpark được làm phẳng và định nghĩa schema chặt chẽ:ColumnTypeDescriptionevent_uuidStringUnique ID cho mỗi sự kiệnuser_idStringID người chơievent_nameStringTên hành động (login, purchase, etc.)server_timestampTimestampThời gian ghi nhận tại serverplatformStringHệ điều hành (iOS/Android)levelIntegerLevel tại thời điểm xảy ra sự kiện🥇 Gold Layer (Star Schema)Dữ liệu được tổ chức thành các bảng Fact và Dimension để tối ưu truy vấn:Bảng Fact: fact_events, fact_purchases, fact_progression.Bảng Dimension: dim_users, dim_device.Data Marts (Views): Các bảng đã tính toán sẵn như mart_retention, mart_funnel, mart_arpu.🚀 Các chỉ số phân tích chính (Key Metrics)User Engagement: DAU/MAU, Stickiness Ratio.Retention Analysis: Tỷ lệ giữ chân người chơi tại các mốc D1, D7, D30.Conversion Funnel: Register → Tutorial → First Purchase.Monetization: ARPU (Average Revenue Per User), ARPPU, LTV.🛠️ Công nghệ sử dụng (Tech Stack)Data Generation: Python (Faker).Storage: MongoDB (Bronze), Parquet/Local (Silver), MySQL 8.0 (Gold).Processing: PySpark (Apache Spark).Orchestration: Python Automation Script (build_marts.py).Visualization: Power BI Dashboard.
