# utils/idempotency.py
from __future__ import annotations
import hashlib
from datetime import datetime, timezone
from contextlib import contextmanager
import mysql.connector


def _get_conn(cfg):
    return mysql.connector.connect(
        host=cfg.mysql_host,
        port=cfg.mysql_port,
        database=cfg.mysql_db,
        user=cfg.mysql_user,
        password=cfg.mysql_password,
    )


def ensure_tracking_table(cfg) -> None:
    """
    Tạo bảng pipeline_runs nếu chưa có.
    Chạy một lần khi khởi động pipeline.
    """
    ddl = """
    CREATE TABLE IF NOT EXISTS pipeline_runs (
        id            INT AUTO_INCREMENT PRIMARY KEY,
        pipeline_name VARCHAR(100)  NOT NULL,
        run_key       VARCHAR(64)   NOT NULL,  -- hash của (pipeline + batch window)
        status        ENUM('running', 'success', 'failed') NOT NULL DEFAULT 'running',
        started_at    DATETIME      NOT NULL,
        finished_at   DATETIME,
        rows_processed INT,
        error_message TEXT,
        UNIQUE KEY uq_run_key (run_key)        -- chặn chạy trùng
    );
    """
    with _get_conn(cfg) as conn:
        conn.cursor().execute(ddl)
        conn.commit()


def _make_run_key(pipeline_name: str, batch_date: str) -> str:
    """
    run_key = hash của (pipeline_name + batch_date).
    Cùng pipeline, cùng ngày → cùng key → UNIQUE constraint chặn chạy lại.
    """
    raw = f"{pipeline_name}:{batch_date}"
    return hashlib.sha256(raw.encode()).hexdigest()[:16]


def is_already_run(cfg, pipeline_name: str, batch_date: str) -> bool:
    """Kiểm tra batch này đã chạy thành công chưa."""
    run_key = _make_run_key(pipeline_name, batch_date)
    sql = """
        SELECT 1 FROM pipeline_runs
        WHERE run_key = %s AND status = 'success'
        LIMIT 1
    """
    with _get_conn(cfg) as conn:
        cur = conn.cursor()
        cur.execute(sql, (run_key,))
        return cur.fetchone() is not None


@contextmanager
def pipeline_run(cfg, pipeline_name: str, batch_date: str):
    """
    Context manager đảm bảo idempotency:
    - Chặn nếu batch đã success
    - Ghi status=running khi bắt đầu
    - Cập nhật success/failed khi kết thúc

    Dùng:
        with pipeline_run(cfg, "load_gold", "2026-03-30") as run_id:
            ... logic ...
    """
    run_key = _make_run_key(pipeline_name, batch_date)

    if is_already_run(cfg, pipeline_name, batch_date):
        raise RuntimeError(
            f"[idempotency] {pipeline_name} batch {batch_date} "
            f"already succeeded. Skipping."
        )

    insert_sql = """
        INSERT INTO pipeline_runs (pipeline_name, run_key, status, started_at)
        VALUES (%s, %s, 'running', %s)
        ON DUPLICATE KEY UPDATE
            status = 'running',
            started_at = VALUES(started_at),
            finished_at = NULL,
            error_message = NULL
    """
    with _get_conn(cfg) as conn:
        cur = conn.cursor()
        cur.execute(insert_sql, (pipeline_name, run_key,
                                 datetime.now(timezone.utc)))
        conn.commit()
        run_id = cur.lastrowid

    try:
        yield run_id  # pipeline logic chạy ở đây

        # Success
        update_sql = """
            UPDATE pipeline_runs
            SET status = 'success', finished_at = %s
            WHERE id = %s
        """
        with _get_conn(cfg) as conn:
            conn.cursor().execute(update_sql,
                                  (datetime.now(timezone.utc), run_id))
            conn.commit()

    except Exception as e:
        # Failed — ghi error, KHÔNG raise lại ngay
        # để caller quyết định retry hay alert
        update_sql = """
            UPDATE pipeline_runs
            SET status = 'failed', finished_at = %s, error_message = %s
            WHERE id = %s
        """
        with _get_conn(cfg) as conn:
            conn.cursor().execute(update_sql,
                                  (datetime.now(timezone.utc), str(e), run_id))
            conn.commit()
        raise  # re-raise để job biết mà exit non-zero