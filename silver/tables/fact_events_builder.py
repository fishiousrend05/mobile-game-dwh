# silver/tables/fact_events_builder.py
from pyspark.sql import DataFrame
from pyspark.sql import functions as F


def build(df: DataFrame) -> DataFrame:
    """
    Output: một row mỗi event.

    Thiết kế:
    - Device info flat trực tiếp — không có dim_device
    - current_state flat vào đây — giữ snapshot tại thời điểm event
      cho phép phân tích progression (gold khi nạp tiền, level khi tutorial...)
    - Chỉ giữ user_id + session_id từ user object
      dim_users_builder chịu trách nhiệm acquisition info
    """
    return (
        df.select(
            # --- Identifiers ---
            F.col("event_uuid"),
            F.col("user.user_id").alias("user_id"),
            F.col("user.session_id").alias("session_id"),

            # --- Event info ---
            F.col("event_name"),
            F.col("event_date"),
            F.col("app_version"),

            # --- Timestamps ---
            F.col("server_timestamp_utc"),
            F.col("client_timestamp_utc"),
            F.col("server_timestamp_local"),
            F.col("local_event_date"),

            # --- Device (flat) ---
            F.col("device.device_id").alias("device_id"),
            F.col("device.platform").alias("platform"),
            F.col("device.os_version").alias("os_version"),
            F.col("device.network_type").alias("network_type"),
            F.col("device.country").alias("country"),

            # --- User state snapshot tại thời điểm event ---
            # Không phải current state của user bây giờ
            # Mà là state CỦA EVENT ĐÓ — dùng prefix "snapshot_" để tránh nhầm
            F.col("user.current_state.level")        .alias("snapshot_level"),
            F.col("user.current_state.power_score")  .alias("snapshot_power_score"),
            F.col("user.current_state.gold_balance") .alias("snapshot_gold_balance"),
            F.col("user.current_state.gem_balance")  .alias("snapshot_gem_balance"),
        )
    )