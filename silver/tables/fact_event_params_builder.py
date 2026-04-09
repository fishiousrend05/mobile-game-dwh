# silver/tables/fact_event_params_builder.py
from pyspark.sql import DataFrame
from pyspark.sql import functions as F


def build(df: DataFrame) -> DataFrame:
    """
    Output: một row mỗi event — sparse wide table.
    Mỗi event type chỉ điền vào các cột của mình, phần còn lại null.
    Parquet compress null hiệu quả — không tốn storage đáng kể.

    Các event types được handle:
      - account_created
      - login
      - tutorial_completed  (có reward_claimed object)
      - level_up            (resources_spent đã xử lý ở fact_event_items)
      - in_app_purchase     (items_received đã xử lý ở fact_event_items)
    """
    return (
        df.select(
            # --- Identifiers ---
            F.col("event_uuid"),
            F.col("user.user_id").alias("user_id"),
            F.col("event_name"),
            F.col("event_date"),
            F.col("server_timestamp_utc"),

            # ----------------------------------------------------------------
            # account_created
            # ----------------------------------------------------------------
            F.col("event_params.acquisition_channel") .alias("acquisition_channel"),
            F.col("event_params.campaign_id")         .alias("campaign_id"),
            F.col("event_params.device_model")        .alias("device_model"),

            # ----------------------------------------------------------------
            # login
            # ----------------------------------------------------------------
            F.col("event_params.login_method")          .alias("login_method"),
            F.col("event_params.is_first_login_of_day") .alias("is_first_login_of_day"),
            F.col("event_params.days_since_last_login") .alias("days_since_last_login"),
            F.col("event_params.login_streak")          .alias("login_streak"),

            # ----------------------------------------------------------------
            # tutorial_completed
            # reward_claimed là object → flatten với prefix reward_
            # ----------------------------------------------------------------
            F.col("event_params.tutorial_version")        .alias("tutorial_version"),
            F.col("event_params.time_spent_seconds")      .alias("time_spent_seconds"),
            F.col("event_params.dialogue_skipped")        .alias("dialogue_skipped"),
            F.col("event_params.deaths_during_tutorial")  .alias("deaths_during_tutorial"),
            F.col("event_params.reward_claimed.item_id")  .alias("reward_item_id"),
            F.col("event_params.reward_claimed.type")     .alias("reward_item_type"),

            # ----------------------------------------------------------------
            # level_up
            # resources_spent array → đã explode ở fact_event_items_builder
            # chỉ giữ scalar context ở đây
            # ----------------------------------------------------------------
            F.col("event_params.old_level")                .alias("old_level"),
            F.col("event_params.new_level")                .alias("new_level"),
            F.col("event_params.time_to_level_up_seconds") .alias("time_to_level_up_seconds"),
            F.col("event_params.location_id")              .alias("location_id"),

            # ----------------------------------------------------------------
            # in_app_purchase
            # items_received array → đã explode ở fact_event_items_builder
            # chỉ giữ scalar transaction context ở đây
            # ----------------------------------------------------------------
            F.col("event_params.transaction_id")   .alias("transaction_id"),
            F.col("event_params.store")            .alias("store"),
            F.col("event_params.product_id")       .alias("product_id"),
            F.col("event_params.revenue_usd")      .alias("revenue_usd"),
            F.col("event_params.is_first_purchase").alias("is_first_purchase"),
            F.col("event_params.purchase_context") .alias("purchase_context"),
        )
    )