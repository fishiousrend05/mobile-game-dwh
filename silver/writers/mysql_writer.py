# silver/writers/mysql_writer.py
import logging
from pyspark.sql import DataFrame, SparkSession
from pyspark.sql import functions as F
from utils.logger import get_logger

logger = get_logger("silver.mysql_writer", log_dir="logs/silver")


# ----------------------------------------------------------------
# JDBC properties — dùng chung cho mọi bảng
# ----------------------------------------------------------------

def _jdbc_props(cfg) -> dict:
    return {
        "driver":   "com.mysql.cj.jdbc.Driver",
        "user":     cfg.mysql_user,
        "password": cfg.mysql_password,
        # rewriteBatchedStatements: gom nhiều INSERT thành một batch
        # giảm số round-trip network đáng kể
        "rewriteBatchedStatements": "true",
        # connectTimeout + socketTimeout: tránh treo vô thời hạn
        "connectTimeout":  "30000",
        "socketTimeout":   "120000",
    }


# ----------------------------------------------------------------
# Core writer
# ----------------------------------------------------------------

def write_to_mysql(
    df: DataFrame,
    cfg,
    table_name: str,
    mode: str = "append",
    num_partitions: int = 4,
) -> None:
    """
    Ghi DataFrame vào MySQL qua JDBC.

    num_partitions: số Spark partitions khi ghi.
    Mỗi partition = một JDBC connection đến MySQL.
    4 là safe default cho MySQL single instance —
    tăng lên nếu MySQL có connection pool lớn hơn.
    """
    row_count = df.count()
    logger.info(f"[mysql_writer] Writing {row_count:,} rows to {table_name}")

    (
        df
        .repartition(num_partitions)
        .write
        .format("jdbc")
        .option("url",      cfg.mysql_jdbc_url)
        .option("dbtable",  table_name)
        .options(**_jdbc_props(cfg))
        .mode(mode)
        .save()
    )

    logger.info(f"[mysql_writer] Done → {table_name}")


# ----------------------------------------------------------------
# Upsert — INSERT ... ON DUPLICATE KEY UPDATE
# ----------------------------------------------------------------

# Trong file silver/writers/mysql_writer.py

def upsert_to_mysql(
        df: DataFrame,
        cfg,
        table_name: str,
        unique_key: str,
) -> None:
    import mysql.connector

    staging_table = f"_staging_{table_name}"

    # Step 1: ghi vào staging
    logger.info(f"[mysql_writer] Writing to staging: {staging_table}")
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

    # Xử lý Composite Key: Biến chuỗi "col1,col2" thành list ["col1", "col2"]
    pk_list = [k.strip() for k in unique_key.split(",")]

    # Step 2: upsert từ staging → target
    columns = df.columns
    col_list = ", ".join(columns)

    # Sử dụng cú pháp bí danh NEW chuẩn của MySQL 8+
    # Lọc bỏ TẤT CẢ các cột nằm trong danh sách Primary Key (pk_list)
    update_list = ", ".join(
        f"{c} = NEW.{c}"
        for c in columns
        if c not in pk_list
    )

    # Thêm bí danh "NEW" vào sau staging_table
    upsert_sql = f"""
        INSERT INTO {table_name} ({col_list})
        SELECT {col_list} FROM {staging_table} AS NEW
        ON DUPLICATE KEY UPDATE {update_list}
    """

    logger.info(f"[mysql_writer] Upserting {staging_table} → {table_name}")

    conn = mysql.connector.connect(
        host=cfg.mysql_host,
        port=cfg.mysql_port,
        database=cfg.mysql_db,
        user=cfg.mysql_user,
        password=cfg.mysql_password,
    )

    try:
        cursor = conn.cursor()
        cursor.execute(upsert_sql)
        affected = cursor.rowcount
        conn.commit()
        logger.info(
            f"[mysql_writer] Upsert complete — "
            f"{affected:,} rows affected in {table_name}"
        )
    finally:
        # Step 3: drop staging
        cursor.execute(f"DROP TABLE IF EXISTS {staging_table}")
        conn.commit()
        conn.close()

# ----------------------------------------------------------------
# Convenience functions cho từng bảng Gold
# Đặt tên rõ ràng để load_gold.py dễ đọc
# ----------------------------------------------------------------

def write_fact_events(df: DataFrame, cfg) -> None:
    upsert_to_mysql(df, cfg, "fact_events", unique_key="event_uuid")


def write_dim_users(df: DataFrame, cfg) -> None:
    upsert_to_mysql(df, cfg, "dim_users", unique_key="user_id")


def write_fact_event_params(df: DataFrame, cfg) -> None:
    upsert_to_mysql(df, cfg, "fact_event_params", unique_key="event_uuid")


def write_fact_event_items(df: DataFrame, cfg) -> None:
    """
    fact_event_items không có single unique key —
    một event_uuid có nhiều items (item_index 0,1,2...).
    Composite key: (event_uuid, item_index, direction).
    """
    upsert_to_mysql(df, cfg, "fact_event_items", unique_key="event_uuid,item_index,direction")
