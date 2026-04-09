# silver/tables/fact_event_items_builder.py
from pyspark.sql import DataFrame
from pyspark.sql import functions as F


def build(df: DataFrame) -> DataFrame:
    """
    Output: một row mỗi item trong array — explode từ 2 event types:
      - level_up        → event_params.resources_spent  (items tiêu tốn)
      - in_app_purchase → event_params.items_received   (items nhận được)

    Dùng posexplode để giữ item_index — quan trọng khi cần
    reconstruct lại order hoặc debug "item thứ mấy trong bundle".
    """

    # ----------------------------------------------------------------
    # 1. level_up → resources_spent
    # ----------------------------------------------------------------
    df_resources = (
        df
        .filter(F.col("event_name") == "level_up")
        .select(
            F.col("event_uuid"),
            F.col("user.user_id").alias("user_id"),
            F.col("event_name"),
            F.col("event_date"),
            F.col("server_timestamp_utc"),

            # Context của event — hữu ích khi query
            # "spent bao nhiêu gold để lên level mấy"
            F.col("event_params.old_level").alias("old_level"),
            F.col("event_params.new_level").alias("new_level"),
            F.col("event_params.location_id").alias("location_id"),

            F.col("event_params.resources_spent").alias("items_array"),
        )
        .filter(F.col("items_array").isNotNull())
        .select(
            "*",
            F.posexplode("items_array").alias("item_index", "item"),
        )
        .select(
            F.col("event_uuid"),
            F.col("user_id"),
            F.col("event_name"),
            F.col("event_date"),
            F.col("server_timestamp_utc"),
            F.col("item_index"),
            F.col("item.item_id").alias("item_id"),
            F.col("item.quantity").alias("quantity"),
            F.lit(None).cast("string").alias("item_type"),  # resources_spent không có type
            F.lit("spent").alias("direction"),              # tiêu tốn
            F.col("old_level"),
            F.col("new_level"),
            F.col("location_id"),
            F.lit(None).cast("string").alias("transaction_id"),  # chỉ có ở IAP
            F.lit(None).cast("double").alias("revenue_usd"),
        )
    )

    # ----------------------------------------------------------------
    # 2. in_app_purchase → items_received
    # ----------------------------------------------------------------
    df_items = (
        df
        .filter(F.col("event_name") == "in_app_purchase")
        .select(
            F.col("event_uuid"),
            F.col("user.user_id").alias("user_id"),
            F.col("event_name"),
            F.col("event_date"),
            F.col("server_timestamp_utc"),

            # Context IAP — join về sau để tính revenue per item
            F.col("event_params.transaction_id").alias("transaction_id"),
            F.col("event_params.revenue_usd").alias("revenue_usd"),

            F.col("event_params.items_received").alias("items_array"),
        )
        .filter(F.col("items_array").isNotNull())
        .select(
            "*",
            F.posexplode("items_array").alias("item_index", "item"),
        )
        .select(
            F.col("event_uuid"),
            F.col("user_id"),
            F.col("event_name"),
            F.col("event_date"),
            F.col("server_timestamp_utc"),
            F.col("item_index"),
            F.col("item.item_id").alias("item_id"),
            F.col("item.quantity").alias("quantity"),
            F.col("item.type").alias("item_type"),       # gem/material/buff
            F.lit("received").alias("direction"),         # nhận được
            F.lit(None).cast("integer").alias("old_level"),
            F.lit(None).cast("integer").alias("new_level"),
            F.lit(None).cast("string").alias("location_id"),
            F.col("transaction_id"),
            F.col("revenue_usd"),
        )
    )

    # ----------------------------------------------------------------
    # 3. Union — cùng schema, khác direction
    # ----------------------------------------------------------------
    return df_resources.unionByName(df_items)