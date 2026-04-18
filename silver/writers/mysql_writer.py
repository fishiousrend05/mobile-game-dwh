# silver/writers/mysql_writer.py
from pyspark.sql import DataFrame
from utils.logger import get_logger

logger = get_logger("silver.mysql_writer", log_dir="logs/silver")


# ──────────────────────────────────────────────────────────────────
# JDBC properties — dùng chung cho mọi bảng
# ──────────────────────────────────────────────────────────────────

def _jdbc_props(cfg) -> dict:
    return {
        "driver": "com.mysql.cj.jdbc.Driver",
        "user": cfg.mysql_user,
        "password": cfg.mysql_password,
        # gom nhiều INSERT thành một batch → giảm round-trip network
        "rewriteBatchedStatements": "true",
        "connectTimeout": "30000",
        "socketTimeout": "120000",
    }


# ──────────────────────────────────────────────────────────────────
# Core writer — append only
# ──────────────────────────────────────────────────────────────────

def write_to_mysql(
        df: DataFrame,
        cfg,
        table_name: str,
        mode: str = "append",
        num_partitions: int = 4,
) -> None:
    """
    Ghi DataFrame vào MySQL qua JDBC.
    num_partitions = số Spark partitions = số JDBC connections đồng thời.
    4 là safe default cho MySQL single instance.
    """
    row_count = df.count()
    logger.info(f"[mysql_writer] Writing {row_count:,} rows → {table_name}")

    (
        df
        .repartition(num_partitions)
        .write
        .format("jdbc")
        .option("url", cfg.mysql_jdbc_url)
        .option("dbtable", table_name)
        .options(**_jdbc_props(cfg))
        .mode(mode)
        .save()
    )
    logger.info(f"[mysql_writer] Done → {table_name}")


# ──────────────────────────────────────────────────────────────────
# Upsert — INSERT ... ON DUPLICATE KEY UPDATE via staging table
# ──────────────────────────────────────────────────────────────────

def upsert_to_mysql(
        df: DataFrame,
        cfg,
        table_name: str,
        unique_key: str,
) -> None:
    """
    Pattern:
      1. Spark ghi toàn bộ df vào _staging_{table} (overwrite)
      2. MySQL thực thi INSERT ... ON DUPLICATE KEY UPDATE
         staging → target trong một transaction
      3. DROP staging dù thành công hay thất bại

    unique_key: cột hoặc danh sách cột phân cách bởi dấu phẩy,
                khớp với PRIMARY KEY / UNIQUE KEY của table đích.
    """
    import mysql.connector

    staging_table = f"_staging_{table_name}"
    pk_list = [k.strip() for k in unique_key.split(",")]
    columns = df.columns
    col_list = ", ".join(columns)
    update_list = ", ".join(
        f"{c} = NEW.{c}" for c in columns if c not in pk_list
    )
    upsert_sql = f"""
        INSERT INTO {table_name} ({col_list})
        SELECT {col_list} FROM {staging_table} AS NEW
        ON DUPLICATE KEY UPDATE {update_list}
    """

    # Step 1: Spark write → staging
    logger.info(f"[mysql_writer] Staging: {staging_table} ({len(columns)} cols)")
    (
        df
        .repartition(4)
        .write
        .format("jdbc")
        .option("url", cfg.mysql_jdbc_url)
        .option("dbtable", staging_table)
        .options(**_jdbc_props(cfg))
        .mode("overwrite")
        .save()
    )

    # Step 2: upsert + Step 3: DROP staging
    conn = mysql.connector.connect(
        host=cfg.mysql_host, port=cfg.mysql_port,
        database=cfg.mysql_db,
        user=cfg.mysql_user, password=cfg.mysql_password,
    )
    cursor = conn.cursor()
    try:
        logger.info(f"[mysql_writer] Upserting → {table_name}")
        cursor.execute(upsert_sql)
        affected = cursor.rowcount
        conn.commit()
        logger.info(f"[mysql_writer] {affected:,} rows affected in {table_name}")
    finally:
        cursor.execute(f"DROP TABLE IF EXISTS {staging_table}")
        conn.commit()
        cursor.close()
        conn.close()


# ──────────────────────────────────────────────────────────────────
# Convenience functions — một hàm cho mỗi bảng Gold
# load_gold.py chỉ gọi các hàm này, không quan tâm internals
# ──────────────────────────────────────────────────────────────────

# ── Dimension tables (SCD Type 1 → upsert) ────────────────────────

def write_dim_users(df: DataFrame, cfg) -> None:
    upsert_to_mysql(df, cfg, "dim_users", unique_key="user_id")


def write_dim_device(df: DataFrame, cfg) -> None:
    upsert_to_mysql(df, cfg, "dim_device", unique_key="device_id")


# ── Fact tables (upsert để idempotent khi re-run) ─────────────────

def write_fact_events(df: DataFrame, cfg) -> None:
    """
    PK của fact_events là (event_uuid, event_date_int) vì table được PARTITION.
    """
    upsert_to_mysql(df, cfg, "fact_events", unique_key="event_uuid,event_date_int") # Sửa 'key' thành 'int'


def write_fact_purchases(df: DataFrame, cfg) -> None:
    upsert_to_mysql(df, cfg, "fact_purchases", unique_key="transaction_id")


def write_fact_progression(df: DataFrame, cfg) -> None:
    upsert_to_mysql(df, cfg, "fact_progression", unique_key="event_uuid")


# ── Silver intermediate tables (backward compatible) ──────────────

def write_fact_event_params(df: DataFrame, cfg) -> None:
    upsert_to_mysql(df, cfg, "fact_event_params", unique_key="event_uuid")


def write_fact_event_items(df: DataFrame, cfg) -> None:
    """Composite PK: (event_uuid, item_index, direction)."""
    upsert_to_mysql(
        df, cfg, "fact_event_items",
        unique_key="event_uuid,item_index,direction",
    )