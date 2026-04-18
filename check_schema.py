from pyspark.sql import SparkSession

# Khởi tạo Spark nhẹ nhàng
spark = SparkSession.builder.appName("Check_Silver_Schema").getOrCreate()

# Đường dẫn tới thư mục Silver (đảm bảo đường dẫn đúng với máy bạn)
base_path = "data/silver_parquet"

tables = [
    "dim_users",
    "fact_events",
    "fact_event_params",
    "fact_event_items"
]

print("🔍 BẮT ĐẦU QUÉT CẤU TRÚC PARQUET 🔍\n" + "=" * 40)

for table in tables:
    path = f"{base_path}/{table}"
    try:
        # Đọc schema (chỉ đọc metadata, rất nhanh)
        df = spark.read.parquet(path)
        print(f"\n📂 BẢNG: {table.upper()}")
        print("-" * 30)

        # In ra cấu trúc cột và kiểu dữ liệu (thu gọn)
        for field in df.schema.fields:
            # field.name là tên cột, field.dataType là kiểu dữ liệu (String, Integer, Timestamp...)
            print(f"- {field.name}: {field.dataType}")

    except Exception as e:
        print(f"\n❌ LỖI đọc bảng {table}: Không tìm thấy file hoặc lỗi cấu trúc.")
        print(e)

print("\n" + "=" * 40 + "\n✅ KẾT THÚC QUÉT SCHEMA")
spark.stop()