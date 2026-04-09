from pyspark.sql import SparkSession

# Khởi tạo session nhỏ nhẹ để test
spark = SparkSession.builder.appName("QA_Parquet").getOrCreate()

print("=== SCHEMA VÀ DỮ LIỆU DIM_USERS ===")
df_users = spark.read.parquet("data/silver_parquet/dim_users")
df_users.printSchema()
df_users.show(5, truncate=False)

print("\n=== DỮ LIỆU FACT EVENT PARAMS ===")
df_params = spark.read.parquet("data/silver_parquet/fact_event_params")
df_params.select("*").show(10, truncate=False)

print("\n=== DỮ LIỆU FACT EVENT ITEMS ===")
df_items = spark.read.parquet("data/silver_parquet/fact_event_items")
df_items.select("*").show(10, truncate=False)

print("\n=== DỮ LIỆU FACT EVENT===")
df_events = spark.read.parquet("data/silver_parquet/fact_events")
df_events.select("*").show(10, truncate=False)

print("\n=== DỮ LIỆU NGÀY 26/01 ===")
df_day = spark.read.parquet("data/silver_parquet/dim_users/event_date=2026-01-26")
df_day.show(5)