from pyspark.sql.types import (
    StructType, StructField,
    StringType, LongType, IntegerType, BooleanType, DoubleType,
    ArrayType, MapType
)

# --- Tầng 3: Nested sâu nhất ---

current_state_schema = StructType([
    StructField("level",         IntegerType(), nullable=True),
    StructField("power_score",   IntegerType(), nullable=True),
    StructField("gold_balance",  IntegerType(), nullable=True),
    StructField("gem_balance",   IntegerType(), nullable=True),
])

# --- Tầng 2: Nested trực tiếp trong wrapper ---

user_schema = StructType([
    StructField("user_id",            StringType(),  nullable=False),
    StructField("session_id",         StringType(),  nullable=True),
    StructField("account_created_at", LongType(),    nullable=True),
    StructField("days_since_install", IntegerType(), nullable=True),
    StructField("current_state",      current_state_schema, nullable=True),
])

device_schema = StructType([
    StructField("device_id",    StringType(), nullable=True),
    StructField("platform",     StringType(), nullable=True),
    StructField("os_version",   StringType(), nullable=True),
    StructField("network_type", StringType(), nullable=True),
    StructField("country",      StringType(), nullable=True),
])

# event_params: mỗi event type có shape khác nhau
# dùng MapType để Bronze → Silver parse được mà không cần biết trước schema
# các builder sẽ cast sang đúng type khi build từng bảng
# silver/schemas/raw_event_schema.py

# Schema cho array items (dùng chung cho cả items_received và resources_spent)
item_schema = StructType([
    StructField("item_id",   StringType(),  nullable=True),
    StructField("quantity",  IntegerType(), nullable=True),
    StructField("type",      StringType(),  nullable=True),  # có trong items_received, không có trong resources_spent
])

# Schema cho reward_claimed (object đơn, không phải array)
reward_claimed_schema = StructType([
    StructField("item_id", StringType(), nullable=True),
    StructField("type",    StringType(), nullable=True),
])

# Sparse struct: gom toàn bộ scalar fields của mọi event type

event_params_schema = StructType([

    # --- account_created ---
    StructField("acquisition_channel", StringType(), nullable=True),
    StructField("campaign_id",         StringType(), nullable=True),
    StructField("device_model",        StringType(), nullable=True),

    # --- login ---
    StructField("login_method",           StringType(),  nullable=True),
    StructField("is_first_login_of_day",  BooleanType(), nullable=True),
    StructField("days_since_last_login",  IntegerType(), nullable=True),
    StructField("login_streak",           IntegerType(), nullable=True),

    # --- tutorial_completed ---
    StructField("tutorial_version",       StringType(),  nullable=True),
    StructField("time_spent_seconds",     IntegerType(), nullable=True),
    StructField("dialogue_skipped",       BooleanType(), nullable=True),
    StructField("deaths_during_tutorial", IntegerType(), nullable=True),
    StructField("reward_claimed",         reward_claimed_schema, nullable=True),  # object → StructType

    # --- level_up ---
    StructField("old_level",                IntegerType(), nullable=True),
    StructField("new_level",                IntegerType(), nullable=True),
    StructField("time_to_level_up_seconds", LongType(),    nullable=True),
    StructField("location_id",              StringType(),  nullable=True),
    StructField("resources_spent",          ArrayType(item_schema), nullable=True),  # array → ArrayType

    # --- in_app_purchase ---
    StructField("transaction_id",   StringType(),  nullable=True),
    StructField("store",            StringType(),  nullable=True),
    StructField("product_id",       StringType(),  nullable=True),
    StructField("revenue_usd",      DoubleType(),  nullable=True),
    StructField("is_first_purchase", BooleanType(), nullable=True),
    StructField("purchase_context", StringType(),  nullable=True),
    StructField("items_received",   ArrayType(item_schema), nullable=True),  # array → ArrayType
])

# --- Tầng 1: Root wrapper ---

RAW_EVENT_SCHEMA = StructType([
    StructField("event_uuid",         StringType(),     nullable=False),
    StructField("event_name",         StringType(),     nullable=False),
    StructField("event_date",         StringType(),     nullable=True),
    StructField("client_timestamp",   LongType(),       nullable=True),
    StructField("server_timestamp",   LongType(),       nullable=True),
    StructField("app_version",        StringType(),     nullable=True),
    StructField("user",               user_schema,      nullable=True),
    StructField("device",             device_schema,    nullable=True),
    StructField("event_params",       event_params_schema, nullable=True),
])