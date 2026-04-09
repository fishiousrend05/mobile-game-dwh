# silver/writers/parquet_writer.py
from pathlib import Path
from pyspark.sql import DataFrame
from utils.logger import get_logger

logger = get_logger("silver.parquet_writer", log_dir="logs/silver")


def write_parquet(
    df: DataFrame,
    output_path: Path,
    partition_by: list[str] = None,
    num_partitions: int = None,
) -> None:
    """
    Ghi DataFrame ra Parquet với overwrite theo partition.

    num_partitions: số Spark partitions trước khi ghi.
    None = giữ nguyên partition hiện tại của df.
    Nên set = số partition của output để tránh small files:
        100k rows / ~100k rows per file = 1 file là đủ
        num_partitions=1 nếu dataset nhỏ
    """
    partition_by = partition_by or ["event_date"]

    writer = df
    if num_partitions is not None:
        writer = df.repartition(num_partitions, *partition_by)

    (
        writer.write
        .option("partitionOverwriteMode", "dynamic")
        .partitionBy(*partition_by)
        .mode("overwrite")
        .parquet(str(output_path))
    )

    logger.info(f"[parquet_writer] Written → {output_path} (partitioned by {partition_by})")


# ----------------------------------------------------------------
# Convenience functions cho từng bảng Silver
# ----------------------------------------------------------------

def write_fact_events(df: DataFrame, cfg) -> None:
    write_parquet(
        df,
        cfg.fact_events_path,
        partition_by=["event_date"],
        num_partitions=1,   # 100k rows, 1 file per partition là đủ
    )


def write_dim_users(df: DataFrame, cfg) -> None:
    write_parquet(
        df,
        cfg.dim_users_path,
        partition_by=["event_date"],
        num_partitions=1,
    )


def write_fact_event_params(df: DataFrame, cfg) -> None:
    write_parquet(
        df,
        cfg.fact_event_params_path,
        partition_by=["event_date"],
        num_partitions=1,
    )


def write_fact_event_items(df: DataFrame, cfg) -> None:
    write_parquet(
        df,
        cfg.fact_event_items_path,
        partition_by=["event_date"],
        num_partitions=1,
    )