# silver/common/cleaner.py
import logging
from pyspark.sql import DataFrame, SparkSession, Window
from pyspark.sql import functions as F
from silver.schemas.raw_event_schema import RAW_EVENT_SCHEMA

logger = logging.getLogger("silver_pipeline")


def _read_from_mongo(spark: SparkSession, cfg) -> DataFrame:
    return (
        spark.read
        .format("mongodb")  # Đổi từ "mongo" thành "mongodb"
        .option("connection.uri", cfg.mongo_uri)  # Đổi từ "uri" thành "connection.uri"
        .option("database", cfg.mongo_db)
        .option("collection", cfg.mongo_collection)
        .load()
    )


def _apply_schema(df: DataFrame) -> DataFrame:

    return (
        df
        .withColumn("json_str", F.to_json(F.struct("*")))
        .select(F.from_json(F.col("json_str"), RAW_EVENT_SCHEMA).alias("data"))
        .select("data.*")
    )


def _drop_invalid_rows(df: DataFrame) -> DataFrame:

    window = Window.partitionBy("event_uuid").orderBy(F.col("server_timestamp").desc())
    return (
        df
        .filter(F.col("event_uuid").isNotNull())
        .filter(F.col("event_name").isNotNull())
        .filter(F.col("user.user_id").isNotNull())
        .withColumn("_row_num", F.row_number().over(window))
        .filter(F.col("_row_num") == 1)
        .drop("_row_num")
    )


def _log_dropped_rows(count_before: int, count_after: int) -> None:

    dropped = count_before - count_after
    if dropped > 0:
        logger.warning(
            f"[cleaner] Dropped {dropped}/{count_before} rows "
            f"({dropped/count_before:.1%})"
        )
    else:
        logger.info(f"[cleaner] No rows dropped ({count_before} rows)")


def clean(spark: SparkSession, cfg, *, debug: bool = False) -> DataFrame:
    df_raw   = _read_from_mongo(spark, cfg)
    df_typed = _apply_schema(df_raw)
    df_clean = _drop_invalid_rows(df_typed)

    if debug:
        df_typed.cache()
        _log_dropped_rows(df_typed.count(), df_clean.count())
        df_typed.unpersist()

    return df_clean