# silver/jobs/process_events.py
import logging
from datetime import datetime, timezone
from pathlib import Path

from pyspark.sql import DataFrame, SparkSession
from pyspark.sql import functions as F

from config import load_config
from silver.common.cleaner import clean
from silver.common.standardizer import standardize
from silver.tables.fact_events_builder import build as build_fact_events
from silver.tables.dim_users_builder import build as build_dim_users
from silver.tables.fact_event_params_builder import build as build_fact_event_params
from silver.tables.fact_event_items_builder import build as build_fact_event_items
from silver.spark_setup import create_spark_session
from silver.writers.parquet_writer import (
    write_fact_events,
    write_dim_users,
    write_fact_event_params,
    write_fact_event_items,
)
from silver.common.validator import validate_all



logger = logging.getLogger("silver_pipeline")


# ---------------------------------------------------------------------------
# Incremental watermark
# ---------------------------------------------------------------------------

def _load_last_watermark(watermark_path: Path) -> int:
    if watermark_path.exists():
        ts = int(watermark_path.read_text().strip())
        logger.info(f"[watermark] Resuming from {datetime.fromtimestamp(ts/1000, tz=timezone.utc)}")
        return ts
    logger.info("[watermark] No watermark found — running full load")
    return 0


def _save_watermark(watermark_path: Path, df: DataFrame) -> None:
    max_ts = df.agg(F.max("server_timestamp")).collect()[0][0]
    if max_ts is not None:
        watermark_path.write_text(str(max_ts))
        logger.info(f"[watermark] Saved {datetime.fromtimestamp(max_ts/1000, tz=timezone.utc)}")


# ---------------------------------------------------------------------------
# Writer
# ---------------------------------------------------------------------------

def _write(df: DataFrame, output_path: Path, partitions: list[str]) -> None:
    (
        df.write
        .option("partitionOverwriteMode", "dynamic")
        .partitionBy(*partitions)
        .mode("overwrite")
        .parquet(str(output_path))
    )
    logger.info(f"[writer] Written to {output_path}")


# ---------------------------------------------------------------------------
# Pipeline
# ---------------------------------------------------------------------------

def _filter_incremental(df: DataFrame, last_watermark_ts: int) -> DataFrame:
    if last_watermark_ts == 0:
        return df
    return df.filter(F.col("server_timestamp") > last_watermark_ts)


# ... (Các phần import và helper functions giữ nguyên) ...

def run(spark: SparkSession) -> None:
    cfg = load_config()
    watermark_path = Path("silver/jobs/.watermark")

    # 1. Watermark
    last_watermark_ts = _load_last_watermark(watermark_path)

    # 2. Clean & Filter
    df_clean = clean(spark, cfg)
    df_incremental = _filter_incremental(df_clean, last_watermark_ts)

    # 3. CACHE NGAY LẬP TỨC để chốt hạ đồ thị thực thi (Execution DAG)
    df_incremental.cache()

    # 4. Gom action đếm và lấy Watermark thành 1 bước để kích hoạt Cache
    # Dùng tuple để chỉ trigger 1 job duy nhất trên Spark thay vì 2 job (count và max)
    stats = df_incremental.select(
        F.count("*").alias("cnt"),
        F.max("server_timestamp").alias("max_ts")
    ).collect()[0]

    record_count = stats["cnt"]
    new_max_ts = stats["max_ts"]

    # 5. Early exit nếu không có data mới
    if record_count == 0:
        logger.info("[pipeline] Không có sự kiện mới nào kể từ lần chạy trước. Thoát.")
        df_incremental.unpersist() # Đừng quên nhả RAM
        return

    logger.info(f"[pipeline] Tìm thấy {record_count} sự kiện mới. Bắt đầu build...")

    # 6. Standardize (Bắt đầu từ dữ liệu đã cache)
    df_standardized = standardize(df_incremental)

    # Build
    df_fact_events       = build_fact_events(df_standardized)
    df_dim_users         = build_dim_users(df_standardized)
    df_fact_event_params = build_fact_event_params(df_standardized)
    df_fact_event_items  = build_fact_event_items(df_standardized)

    # 7. Build & write
    write_fact_events(build_fact_events(df_standardized), cfg)
    write_dim_users(build_dim_users(df_standardized), cfg)
    write_fact_event_params(build_fact_event_params(df_standardized), cfg)
    write_fact_event_items(build_fact_event_items(df_standardized), cfg)

    # Validate — trước khi save watermark
    validate_all(
        fact_events       = df_fact_events,
        dim_users         = df_dim_users,
        fact_event_params = df_fact_event_params,
        fact_event_items  = df_fact_event_items,
        raise_on_failure  = True,
    )

    # 8. Ghi lại Watermark (đã lấy được ở bước 4, không cần quét lại DataFrame)
    if new_max_ts is not None:
        watermark_path.write_text(str(new_max_ts))
        logger.info(f"[watermark] Đã lưu mốc thời gian: {datetime.fromtimestamp(new_max_ts/1000, tz=timezone.utc)}")

    df_incremental.unpersist()
    logger.info("[pipeline] Silver pipeline hoàn thành xuất sắc!")
if __name__ == "__main__":
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s | %(levelname)s | %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )
    spark = create_spark_session("silver_pipeline")
    try:
        run(spark)
    finally:
        spark.stop()