# silver/utils.py
from pyspark.sql import DataFrame
from utils.logger import get_logger

logger = get_logger("silver.utils", log_dir="logs/silver")


def log_df_stats(df: DataFrame, label: str) -> DataFrame:
    """
    Log row count và schema — dùng để debug giữa các bước transform.
    Trả về df để dùng trong chain:

        df = df.transform(some_step)
        df = log_df_stats(df, "after some_step")  # không phá chain
    """
    logger.info(f"[{label}] schema:\n{df._jdf.schema().treeString()}")
    logger.info(f"[{label}] count: {df.count():,} rows")
    return df


def assert_no_nulls(df: DataFrame, columns: list[str], label: str) -> DataFrame:
    """
    Raise lỗi nếu có null trong các cột critical.
    Dùng ở cuối mỗi builder để đảm bảo contract trước khi ghi.

    Ví dụ:
        df = build(df_standardized)
        df = assert_no_nulls(df, ["event_uuid", "user_id"], "fact_events")
    """
    for col in columns:
        null_count = df.filter(df[col].isNull()).count()
        if null_count > 0:
            raise ValueError(
                f"[{label}] Column '{col}' has {null_count:,} null values — "
                f"contract violation, aborting write."
            )
    logger.info(f"[{label}] Null check passed for {columns}")
    return df


def assert_no_duplicates(df: DataFrame, key_columns: list[str], label: str) -> DataFrame:
    """
    Raise lỗi nếu có duplicate trên key_columns.
    Dùng để verify dedup ở cleaner đã hoạt động đúng.
    """
    total    = df.count()
    distinct = df.dropDuplicates(key_columns).count()
    if total != distinct:
        raise ValueError(
            f"[{label}] Found {total - distinct:,} duplicate rows "
            f"on {key_columns} — check cleaner dedup logic."
        )
    logger.info(f"[{label}] Duplicate check passed on {key_columns}")
    return df