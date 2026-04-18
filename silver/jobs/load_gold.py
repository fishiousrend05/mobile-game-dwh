# silver/jobs/load_gold.py
"""
load_gold.py — ETL job bơm dữ liệu Silver Parquet → Gold MySQL.

Luồng xử lý mỗi batch_date:
  1. Đọc Silver Parquet (partition pruning theo event_date)
  2. Transform: tạo derived columns Gold DDL yêu cầu
  3. Ghi vào Gold MySQL theo thứ tự FK dependency:
       dim_users → dim_device → fact_events
       → fact_purchases → fact_progression

Idempotency:
  - pipeline_run context manager chặn batch đã success.
  - Mỗi writer dùng upsert → re-run cùng batch_date không duplicate.

Chạy:
  python -m silver.jobs.load_gold --date 2026-03-30
"""

from __future__ import annotations

import argparse
from pyspark.sql import SparkSession, DataFrame
from pyspark.sql import functions as F
from pyspark.sql.types import IntegerType

from utils.logger import get_logger
from utils.idempotency import ensure_tracking_table, pipeline_run
from silver.writers.mysql_writer import (
    write_dim_users,
    write_dim_device,
    write_fact_events,
    write_fact_purchases,
    write_fact_progression,
)

logger = get_logger("silver.load_gold", log_dir="logs/silver")

PIPELINE_NAME = "load_gold"


# ──────────────────────────────────────────────────────────────────
# I/O helpers
# ──────────────────────────────────────────────────────────────────

def _read_partition(spark: SparkSession, path, batch_date: str) -> DataFrame:
    """
    Đọc Silver Parquet và filter đúng partition event_date = batch_date.
    Spark tự prune — chỉ scan thư mục event_date=<batch_date>.
    """
    return (
        spark.read
        .parquet(str(path))
        .filter(F.col("event_date") == batch_date)
    )


def _date_key(col_name: str) -> F.Column:
    """DATE/STRING → INT YYYYMMDD. Partition key bắt buộc của fact_events."""
    return F.date_format(F.col(col_name), "yyyyMMdd").cast(IntegerType())


# ──────────────────────────────────────────────────────────────────
# Transform: Silver schema → Gold schema
# Mỗi hàm nhận Silver DataFrame, trả về DataFrame khớp Gold DDL
# ──────────────────────────────────────────────────────────────────

def _build_dim_users(s_dim_users: DataFrame, batch_date: str) -> DataFrame:
    return (
        s_dim_users
        .withColumn(
            "account_created_date",
            F.to_date(F.from_unixtime(F.col("account_created_at") / 1000))
        )
        .withColumn("first_seen_date", F.lit(batch_date).cast("date"))
        .withColumn("updated_at", F.current_timestamp())
        .select(
            "user_id",
            "account_created_at",    # Bơm thẳng số BIGINT vào MySQL
            "account_created_date",
            "days_since_install",
            "acquisition_channel",
            "campaign_id",
            "device_model",          # Không rename nữa
            "first_seen_date",
            "updated_at",
        )
    )


def _build_dim_device(s_fact_events: DataFrame, batch_date: str) -> DataFrame:
    """
    Silver FACT_EVENTS → Gold dim_device.

    Silver không có bảng DIM_DEVICE riêng —
    thông tin device nằm inline trong FACT_EVENTS.
    groupBy device_id + first() để lấy một row đại diện mỗi device.
    first(ignorenulls=True) tránh lấy NULL khi có row khác có giá trị.
    """
    return (
        s_fact_events
        .groupBy("device_id")
        .agg(
            F.first("platform", ignorenulls=True).alias("platform"),
            F.first("os_version", ignorenulls=True).alias("os_version"),
            F.first("network_type", ignorenulls=True).alias("network_type"),
            F.first("country", ignorenulls=True).alias("country"),
        )
        .withColumn("first_seen_date", F.lit(batch_date).cast("date"))
        .withColumn("updated_at", F.current_timestamp())
        .select(
            "device_id",
            "platform",
            "os_version",
            "network_type",
            "country",
            "first_seen_date",
            "updated_at",
        )
    )


def _build_fact_events(s_fact_events: DataFrame) -> DataFrame:
    """
    Silver FACT_EVENTS → Gold fact_events.
    """
    return (
        s_fact_events
        # CHÍNH LÀ DÒNG NÀY: Phải sửa thành 'event_date_int'
        .withColumn("event_date_int", _date_key("event_date"))
        .select(
            "event_uuid",
            "user_id",
            "device_id",
            "session_id",
            "event_name",
            "app_version",
            "server_timestamp_utc",
            "client_timestamp_utc",
            "server_timestamp_local",
            "local_event_date",
            "snapshot_level",
            "snapshot_power_score",
            "snapshot_gold_balance",
            "snapshot_gem_balance",
            "event_date_int",        # Khớp với dòng trên
            "event_date",
        )
    )

def _build_fact_purchases(
        s_event_params: DataFrame,
        s_fact_events: DataFrame,
) -> DataFrame:
    """
    Silver FACT_EVENT_PARAMS (in_app_purchase) + FACT_EVENTS → Gold fact_purchases.

    Join với FACT_EVENTS để lấy:
      user_id      : denormalized vào fact_purchases — tránh join sau
      purchased_at : server_timestamp_utc của event tương ứng

    is_first_purchase cast Boolean → Int vì Gold DDL dùng TINYINT(1).
    """
    purchases = s_event_params.filter(
        F.col("event_name") == "in_app_purchase"
    )

    # Slim join — chỉ lấy cột cần thêm từ fact_events, KHÔNG lấy user_id/event_date
    # vì purchases đã có sẵn cả hai → join xong sẽ bị ambiguous reference
    events_slim = s_fact_events.select(
        "event_uuid",
        F.col("server_timestamp_utc").alias("purchased_at"),
    )

    return (
        purchases
        .join(events_slim, on="event_uuid", how="inner")
        .withColumn("purchase_date", F.to_date(F.col("purchased_at")))
        .withColumn("is_first_purchase", F.col("is_first_purchase").cast("int"))
        .select(
            "transaction_id",
            "event_uuid",
            "user_id",  # lấy từ purchases (s_event_params)
            "store",
            "product_id",
            "revenue_usd",
            "is_first_purchase",
            "purchase_context",
            "purchased_at",  # lấy từ events_slim
            "purchase_date",
            "event_date",  # lấy từ purchases (s_event_params)
        )
    )


def _build_fact_progression(
        s_event_params: DataFrame,
        s_event_items: DataFrame,
        s_fact_events: DataFrame,
) -> DataFrame:
    """
    Silver FACT_EVENT_PARAMS (level_up) + FACT_EVENT_ITEMS + FACT_EVENTS
    → Gold fact_progression.

    Resources spent (gold, exp_potion) được aggregate ở đây từ FACT_EVENT_ITEMS
    theo direction='spent', tránh để mart tự join sau.

    Left join với resources vì không phải level_up nào cũng tiêu item.
    coalesce(..., 0) đảm bảo NOT NULL DEFAULT 0 của Gold DDL.
    """
    level_ups = s_event_params.filter(F.col("event_name") == "level_up")

    # Aggregate resources spent per event_uuid
    resources = (
        s_event_items
        .filter(F.col("direction") == "spent")
        .groupBy("event_uuid")
        .agg(
            F.coalesce(
                F.sum(F.when(F.col("item_id") == "gold", F.col("quantity"))),
                F.lit(0)
            ).alias("gold_spent"),
            F.coalesce(
                F.sum(F.when(F.col("item_id") == "exp_potion", F.col("quantity"))),
                F.lit(0)
            ).alias("exp_potions_spent"),
        )
    )

    # Chỉ lấy cột cần thêm — KHÔNG lấy user_id/event_date
    # vì level_ups đã có sẵn cả hai, join xong bị ambiguous reference
    events_slim = s_fact_events.select(
        "event_uuid",
        F.col("server_timestamp_utc").alias("leveled_up_at"),
    )

    return (
        level_ups
        .join(events_slim, on="event_uuid", how="inner")
        .join(resources, on="event_uuid", how="left")
        .withColumn("level_up_date", F.to_date(F.col("leveled_up_at")))
        .withColumn("gold_spent", F.coalesce(F.col("gold_spent"), F.lit(0)))
        .withColumn("exp_potions_spent", F.coalesce(F.col("exp_potions_spent"), F.lit(0)))
        # Silver: time_to_level_up_seconds → Gold: time_to_level_up_sec
        .withColumnRenamed("time_to_level_up_seconds", "time_to_level_up_sec")
        .select(
            "event_uuid",
            "user_id",
            "old_level",
            "new_level",
            "time_to_level_up_sec",
            "location_id",
            "gold_spent",
            "exp_potions_spent",
            "leveled_up_at",
            "level_up_date",
            "event_date",
        )
    )


# ──────────────────────────────────────────────────────────────────
# Main pipeline
# ──────────────────────────────────────────────────────────────────

def run(spark: SparkSession, cfg, batch_date: str) -> None:
    """
    Điểm vào chính. Gọi từ entrypoint CLI hoặc test.

    Thứ tự ghi bắt buộc theo FK dependency:
      1. dim_users      (không phụ thuộc ai)
      2. dim_device     (không phụ thuộc ai)
      3. fact_events    (FK → dim_users, dim_device)
      4. fact_purchases (FK → dim_users; ref fact_events)
      5. fact_progression (FK → dim_users; ref fact_events)
    """
    ensure_tracking_table(cfg)

    with pipeline_run(cfg, PIPELINE_NAME, batch_date):
        logger.info(f"[load_gold] ── Start batch {batch_date} ──")

        # ── 1. Đọc Silver Parquet ──────────────────────────────
        logger.info("[load_gold] Reading Silver partitions...")
        s_dim_users = _read_partition(spark, cfg.dim_users_path, batch_date)
        s_fact_events = _read_partition(spark, cfg.fact_events_path, batch_date)
        s_event_params = _read_partition(spark, cfg.fact_event_params_path, batch_date)
        s_event_items = _read_partition(spark, cfg.fact_event_items_path, batch_date)

        # Cache hai bảng dùng nhiều lần trong transform
        s_fact_events.cache()
        s_event_params.cache()
        logger.info("[load_gold] Cached: fact_events, event_params")

        # ── 2. Transform Silver → Gold ─────────────────────────
        logger.info("[load_gold] Transforming...")
        dim_users = _build_dim_users(s_dim_users, batch_date)
        dim_device = _build_dim_device(s_fact_events, batch_date)
        fact_events = _build_fact_events(s_fact_events)
        fact_purchases = _build_fact_purchases(s_event_params, s_fact_events)
        fact_progress = _build_fact_progression(s_event_params, s_event_items, s_fact_events)

        # ── 3. Write theo thứ tự FK ────────────────────────────
        logger.info("[load_gold] Writing dim_users...")
        write_dim_users(dim_users, cfg)

        logger.info("[load_gold] Writing dim_device...")
        write_dim_device(dim_device, cfg)

        logger.info("[load_gold] Writing fact_events...")
        write_fact_events(fact_events, cfg)

        logger.info("[load_gold] Writing fact_purchases...")
        write_fact_purchases(fact_purchases, cfg)

        logger.info("[load_gold] Writing fact_progression...")
        write_fact_progression(fact_progress, cfg)

        # ── 4. Cleanup ─────────────────────────────────────────
        s_fact_events.unpersist()
        s_event_params.unpersist()

        logger.info(f"[load_gold] ── Completed batch {batch_date} ──")


# ──────────────────────────────────────────────────────────────────
# CLI entrypoint
# ──────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Load Silver Parquet → Gold MySQL")
    parser.add_argument(
        "--date", required=True,
        help="Batch date YYYY-MM-DD, VD: 2026-03-30",
    )
    args = parser.parse_args()

    from config import load_config

    cfg = load_config()

    spark = (
        SparkSession.builder
        .appName(f"{PIPELINE_NAME}_{args.date}")
        .config("spark.sql.shuffle.partitions", "8")
        .config("spark.jars.packages", "mysql:mysql-connector-java:8.0.33")
        .getOrCreate()
    )
    spark.sparkContext.setLogLevel("WARN")

    try:
        run(spark, cfg, args.date)
    finally:
        spark.stop()