# silver/tables/dim_users_builder.py
from pyspark.sql import DataFrame
from pyspark.sql import functions as F
from pyspark.sql import Window


def build(df: DataFrame) -> DataFrame:
    """
    Output: một row mỗi user — dimension table, không có snapshot state.

    Hai nguồn data cần join:
    1. user object (có trong mọi event)  → identity + account_created_at
    2. event_params của account_created  → acquisition channel, campaign, device_model
       days_since_install lấy từ đây    → phản ánh lúc mới cài, không phải latest

    Nếu user không có account_created event trong batch
    (ví dụ: incremental load, user cũ) → acquisition columns = null,
    vẫn tạo row với LEFT JOIN để không mất user.
    """

    # ----------------------------------------------------------------
    # 1. Base: identity info — lấy từ event mới nhất của mỗi user
    #    để đảm bảo account_created_at nhất quán
    # ----------------------------------------------------------------
    window_latest = Window.partitionBy("user_id").orderBy(
        F.col("server_timestamp_utc").desc()
    )

    df_base = (
        df
        .select(
            F.col("user.user_id").alias("user_id"),
            F.col("user.account_created_at").alias("account_created_at"),
            F.col("server_timestamp_utc"),
            F.col("event_date"),
        )
        .withColumn("_row_num", F.row_number().over(window_latest))
        .filter(F.col("_row_num") == 1)
        .drop("_row_num", "server_timestamp_utc")
    )

    # ----------------------------------------------------------------
    # 2. Acquisition: chỉ có trong account_created event
    #    days_since_install lấy từ đây — gần 0, phản ánh lúc mới cài
    # ----------------------------------------------------------------
    df_acquisition = (
        df
        .filter(F.col("event_name") == "account_created")
        .select(
            F.col("user.user_id").alias("user_id"),
            F.col("user.days_since_install").alias("days_since_install"),
            F.col("event_params.acquisition_channel").alias("acquisition_channel"),
            F.col("event_params.campaign_id").alias("campaign_id"),
            F.col("event_params.device_model").alias("device_model"),
        )
    )

    # ----------------------------------------------------------------
    # 3. Join: LEFT JOIN để giữ user dù không có account_created
    #    trong batch hiện tại (incremental load)
    # ----------------------------------------------------------------
    return df_base.join(df_acquisition, on="user_id", how="left")