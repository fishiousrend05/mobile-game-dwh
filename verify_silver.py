# D:\Game\verify_silver.py
from silver.spark_setup import create_spark_session
from silver.common.validator import validate_all
from config import load_config

spark = create_spark_session("verify_silver")
cfg   = load_config()

fact_events       = spark.read.parquet(str(cfg.fact_events_path))
dim_users         = spark.read.parquet(str(cfg.dim_users_path))
fact_event_params = spark.read.parquet(str(cfg.fact_event_params_path))
fact_event_items  = spark.read.parquet(str(cfg.fact_event_items_path))

validate_all(
    fact_events       = fact_events,
    dim_users         = dim_users,
    fact_event_params = fact_event_params,
    fact_event_items  = fact_event_items,
    raise_on_failure  = False,  # chỉ log, không raise
)

spark.stop()