# silver/spark_setup.py
import os
import sys
import findspark

# 1. Ép PySpark dùng đúng Python của Anaconda Base (nơi bạn chạy thành công)
# Điều này giúp tránh lỗi 'JavaPackage' do sai lệch môi trường
os.environ['PYSPARK_PYTHON'] = r"C:\Users\Msi\anaconda3\python.exe"
os.environ['PYSPARK_DRIVER_PYTHON'] = r"C:\Users\Msi\anaconda3\python.exe"

# 2. Khởi tạo findspark (để chắc chắn)
findspark.init()

from pyspark.sql import SparkSession
# ... các đoạn code phía dưới giữ nguyên
from pyspark.sql import SparkSession

def create_spark_session(app_name: str = "silver_pipeline") -> SparkSession:
    """
    Tạo SparkSession với config tối ưu cho project:
    - MongoDB connector
    - MySQL JDBC driver
    - Timezone UTC để tránh implicit conversion
    - Log level WARN để không bị spam INFO từ Spark internals
    """
    return (
        SparkSession.builder
        .appName(app_name)

        # --- Connectors ---
        .config(
            "spark.jars.packages",
            ",".join([
                "org.mongodb.spark:mongo-spark-connector_2.12:10.4.0",
                "com.mysql:mysql-connector-j:8.3.0",
            ])
        )

        # --- Timezone ---
        # Bắt buộc set UTC để from_utc_timestamp / to_utc_timestamp
        # hoạt động nhất quán bất kể timezone của máy chạy Spark
        .config("spark.sql.session.timeZone", "UTC")

        # --- Parquet ---
        # Ghi đúng timezone metadata vào Parquet file
        .config("spark.sql.parquet.datetimeRebaseModeInWrite", "CORRECTED")
        .config("spark.sql.parquet.int96RebaseModeInWrite",    "CORRECTED")

        # --- Partition overwrite ---
        # Mặc định Spark overwrite toàn bộ bảng khi mode=overwrite
        # Dynamic = chỉ overwrite partition có data mới
        .config("spark.sql.sources.partitionOverwriteMode", "dynamic")

        # --- Performance (local mode) ---
        # shuffle partitions mặc định là 200 — quá nhiều cho 100k rows
        # giảm xuống để tránh tạo hàng trăm file nhỏ
        .config("spark.sql.shuffle.partitions", "8")

        .getOrCreate()
    )

if __name__ == "__main__":
    # Chỉ chạy test nếu gõ: python silver/spark_setup.py
    spark = create_spark_session("test")
    spark.range(1).show()
    spark.stop()