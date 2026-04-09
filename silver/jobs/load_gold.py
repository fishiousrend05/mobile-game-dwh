# silver/jobs/load_gold.py
from utils.logger import get_logger
from utils.idempotency import ensure_tracking_table, pipeline_run
from silver.writers.mysql_writer import (
    write_fact_events,
    write_dim_users,
    write_fact_event_params,
    write_fact_event_items,
)

logger = get_logger("silver.load_gold", log_dir="logs/silver")


def run(spark, cfg, batch_date: str) -> None:
    ensure_tracking_table(cfg)

    with pipeline_run(cfg, "load_gold", batch_date):
        logger.info(f"[load_gold] Starting batch {batch_date}")

        # Đọc từ Silver Parquet — chỉ partition của batch_date
        def read(path):
            return (
                spark.read.parquet(str(path))
                .filter(F.col("event_date") == batch_date)
            )

        write_fact_events      (read(cfg.fact_events_path),       cfg)
        write_dim_users        (read(cfg.dim_users_path),         cfg)
        write_fact_event_params(read(cfg.fact_event_params_path), cfg)
        write_fact_event_items (read(cfg.fact_event_items_path),  cfg)

        logger.info(f"[load_gold] Completed batch {batch_date}")