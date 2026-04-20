# pipeline.py
"""
Prefect orchestration cho Game Data Warehouse pipeline.

Ba flows:
  setup_flow        — chạy một lần khi khởi tạo project
  daily_pipeline    — chạy hàng ngày lúc 2AM, xử lý ngày hôm qua
  backfill_flow     — chạy tay khi cần reprocess một khoảng ngày

Cài đặt:
  pip install prefect

Chạy local (không cần Prefect server):
  python pipeline.py --flow daily --date 2026-03-26
  python pipeline.py --flow setup
  python pipeline.py --flow backfill --start 2026-03-01 --end 2026-03-26

Deploy lên Prefect Cloud / self-hosted:
  prefect deploy pipeline.py:daily_pipeline --name game-dwh-daily --cron "0 2 * * *"
"""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
from datetime import date, timedelta
from pathlib import Path

import mysql.connector
from dotenv import load_dotenv
from prefect import flow, task, get_run_logger
from prefect.task_runners import ConcurrentTaskRunner

load_dotenv()

ROOT = Path(__file__).parent


# ──────────────────────────────────────────────────────────────────
# Config helper
# ──────────────────────────────────────────────────────────────────

def _mysql_conn():
    return mysql.connector.connect(
        host=os.getenv("MYSQL_HOST", "localhost"),
        port=int(os.getenv("MYSQL_PORT", 3306)),
        user=os.getenv("MYSQL_USER", "root"),
        password=os.getenv("MYSQL_PASSWORD", ""),
        database=os.getenv("MYSQL_DB", "game_gold"),
    )


def _split_sql_statements(sql: str) -> list[str]:
    """
    Tách SQL script thành danh sách statements an toàn.

    Dùng regex thay vì split(';') đơn thuần vì:
      - PARTITION BY RANGE chứa ';' bên trong block definition
      - Comment -- và /* */ có thể chứa ';'
      - String literals có thể chứa ';'

    Cách tiếp cận: strip comment trước, sau đó split theo ';'
    ở top-level (không nằm trong parentheses).
    """
    import re

    # Xóa comment -- đến cuối dòng
    sql = re.sub(r"--[^\n]*", "", sql)
    # Xóa comment /* ... */
    sql = re.sub(r"/\*.*?\*/", "", sql, flags=re.DOTALL)

    # Tách theo ';' nhưng theo dõi độ sâu parentheses
    # ';' bên trong (...) như PARTITION block không phải statement terminator
    statements = []
    current = []
    depth = 0

    for char in sql:
        if char == "(":
            depth += 1
        elif char == ")":
            depth -= 1
        elif char == ";" and depth == 0:
            stmt = "".join(current).strip()
            if stmt:
                statements.append(stmt)
            current = []
            continue
        current.append(char)

    # Statement cuối có thể không có ';'
    last = "".join(current).strip()
    if last:
        statements.append(last)

    return statements


def _run_sql_file(conn, path: Path) -> None:
    """
    Trình đọc SQL thông minh: Tự động nhận diện DELIMITER $$
    và xử lý lỗi Unread result found.
    """
    sql_text = path.read_text(encoding="utf-8")
    import re
    sql_text = re.sub(r'(?m)^--.*$', '', sql_text)

    cursor = conn.cursor()

    # --- Hàm phụ trợ để chạy và dọn sạch kết quả ---
    def _execute_and_clear(statement: str):
        if not statement.strip():
            return
        cursor.execute(statement.strip())
        # "Hút" cạn các kết quả ẩn (nếu có) để tránh lỗi Unread result
        while cursor.nextset():
            pass

    # -----------------------------------------------

    try:
        if "DELIMITER $$" in sql_text:
            part1 = sql_text.split("DELIMITER $$")[0]
            for stmt in part1.split(';'):
                _execute_and_clear(stmt)

            part2 = sql_text.split("DELIMITER $$")[1].split("DELIMITER ;")[0]
            for func in part2.split('$$'):
                _execute_and_clear(func)

            if "DELIMITER ;" in sql_text:
                part3 = sql_text.split("DELIMITER ;")[1]
                for stmt in part3.split(';'):
                    _execute_and_clear(stmt)
        else:
            for stmt in sql_text.split(';'):
                _execute_and_clear(stmt)

        conn.commit()
    finally:
        cursor.close()


def _run_python(script: str, *args: str, check: bool = True, use_base_python: bool = False) -> int:
    """
    Chạy Python script.
    Nếu là Spark job (Silver/Gold), ta sẽ mượn Python từ môi trường 'base' vốn đã ổn định.
    """
    # 💥 ĐƯỜNG DẪN PYTHON NGON CỦA BẠN (Lấy từ log dự án cũ của bạn)
    base_python = r"C:\Users\Msi\anaconda3\python.exe"

    python_exe = base_python if use_base_python else sys.executable

    cmd = [python_exe, "-m", script, *args]
    logger = get_run_logger()
    logger.info(f"Running with {('BASE' if use_base_python else 'CURRENT')} Python: {' '.join(cmd)}")

    result = subprocess.run(cmd, cwd=str(ROOT), capture_output=False)
    if check and result.returncode != 0:
        raise RuntimeError(f"{script} exited with code {result.returncode}")
    return result.returncode


# ──────────────────────────────────────────────────────────────────
# SETUP TASKS
# ──────────────────────────────────────────────────────────────────

@task(name="run-ddl-files", log_prints=True)
def run_ddl_files() -> None:
    """Tạo Star Schema tables. Dùng CREATE TABLE IF NOT EXISTS — idempotent."""
    logger = get_run_logger()
    ddl_dir = ROOT / "gold" / "ddl"
    conn = _mysql_conn()
    try:
        for sql_file in sorted(ddl_dir.glob("*.sql")):
            logger.info(f"  DDL: {sql_file.name}")
            _run_sql_file(conn, sql_file)
    finally:
        conn.close()
    logger.info("DDL files done.")


@task(name="run-business-rules", log_prints=True)
def run_business_rules() -> None:
    """Tạo business_config table + stored functions."""
    logger = get_run_logger()
    sql_file = ROOT / "gold"  / "business_rules.sql"
    conn = _mysql_conn()
    try:
        _run_sql_file(conn, sql_file)
    finally:
        conn.close()
    logger.info("Business rules loaded.")


@task(name="ensure-tracking-table", log_prints=True)
def ensure_tracking_table() -> None:
    """Tạo pipeline_runs table cho idempotency tracking."""
    from utils.idempotency import ensure_tracking_table as _ensure
    from config import load_config
    _ensure(load_config())
    get_run_logger().info("pipeline_runs table ready.")


# ──────────────────────────────────────────────────────────────────
# DAILY PIPELINE TASKS
# ──────────────────────────────────────────────────────────────────

@task(name="generate-bronze", log_prints=True)
def generate_bronze(batch_date: str) -> None:
    """
    Sinh dữ liệu Bronze vào MongoDB.
    Với production data thực thì bỏ task này —
    Bronze đã được feed từ game server.
    """
    _run_python("bronze.generate_bronze_data", "--date", batch_date)


@task(
    name="run-silver",
    log_prints=True,
    retries=2,
    retry_delay_seconds=300,  # Spark fail do resource → đợi 5 phút retry
)
@task(name="run-silver", log_prints=True, retries=2, retry_delay_seconds=300)
def run_silver(batch_date: str) -> None:
    # 💥 Ép dùng Python Base ở đây
    _run_python("silver.jobs.process_events", "--date", batch_date, use_base_python=True)

@task(name="run-load-gold", log_prints=True, retries=2, retry_delay_seconds=300)
def run_load_gold(batch_date: str) -> None:
    # 💥 Ép dùng Python Base ở đây
    _run_python("silver.jobs.load_gold", "--date", batch_date, use_base_python=True)


@task(name="build-mart-domain", log_prints=True)
def build_mart_domain(domain: str) -> None:
    """
    Chạy toàn bộ mart_*.sql và vw_*.sql trong một domain.
    Bốn domain chạy song song sau load_gold xong.
    """
    logger = get_run_logger()
    domain_dir = ROOT / "gold" / "mart" / domain
    if not domain_dir.exists():
        raise FileNotFoundError(f"Domain not found: {domain_dir}")

    conn = _mysql_conn()
    try:
        # mart_* trước, vw_* sau
        sql_files = sorted(
            domain_dir.glob("*.sql"),
            key=lambda p: (1 if p.name.startswith("vw_") else 0, p.name),
        )
        for f in sql_files:
            logger.info(f"  [{domain}] {f.name}")
            _run_sql_file(conn, f)
    finally:
        conn.close()

    logger.info(f"Domain '{domain}' done: {len(sql_files)} files.")


@task(name="verify-output", log_prints=True)
def verify_output(batch_date: str) -> None:
    """
    Chạy check_data.py để xác nhận data đã load đúng.
    Fail task nếu có bảng trống hoặc row count bất thường.
    """
    _run_python("check_data", "--date", batch_date, use_base_python=True)


# ──────────────────────────────────────────────────────────────────
# FLOWS
# ──────────────────────────────────────────────────────────────────

@flow(name="setup-flow", log_prints=True)
def setup_flow() -> None:
    """
    Chạy MỘT LẦN khi khởi tạo project.
    Tạo Star Schema tables, business rules, và tracking table.
    """
    logger = get_run_logger()
    logger.info("=== Setup flow bắt đầu ===")

    run_ddl_files()
    run_business_rules()
    ensure_tracking_table()

    logger.info("=== Setup hoàn thành ===")


@flow(
    name="daily-pipeline",
    log_prints=True,
    # ConcurrentTaskRunner cho phép 4 mart domain tasks chạy song song
    task_runner=ConcurrentTaskRunner(),
)
def daily_pipeline(batch_date: str | None = None) -> None:
    """
    Pipeline chính — chạy hàng ngày lúc 2AM.
    Mặc định xử lý ngày hôm qua nếu không truyền batch_date.

    Thứ tự:
      Bronze → Silver → Gold ETL → [4 mart domains song song] → Verify
    """
    logger = get_run_logger()

    if batch_date is None:
        batch_date = (date.today() - timedelta(days=1)).isoformat()

    logger.info(f"=== daily_pipeline | batch_date={batch_date} ===")

    # ── Stage 1-3: Sequential (phụ thuộc nhau) ────────────────
    generate_bronze(batch_date)
    run_silver(batch_date)
    run_load_gold(batch_date)

    # ── Stage 4: 4 mart domains chạy song song ─────────────────
    # submit() trả về future ngay lập tức → 4 tasks chạy concurrent
    domains = ["user", "engagement", "monetization", "progression"]
    mart_futures = [
        build_mart_domain.submit(domain)
        for domain in domains
    ]

    # Đợi tất cả mart domain xong trước khi verify
    for future in mart_futures:
        future.result()  # raise nếu task fail

    # ── Stage 5: Verify ────────────────────────────────────────
    verify_output(batch_date)

    logger.info(f"=== daily_pipeline hoàn thành | {batch_date} ===")


@flow(name="backfill-flow", log_prints=True)
def backfill_flow(start_date: str, end_date: str) -> None:
    """
    Reprocess một khoảng ngày tuần tự.
    Dùng khi: fix bug trong Silver/Gold transform, hoặc thêm data mới.

    idempotency.py tự động skip ngày đã success —
    chỉ những ngày failed/missing mới được chạy lại.

    Ví dụ:
      prefect run backfill-flow --start 2026-03-01 --end 2026-03-26
    """
    logger = get_run_logger()
    start = date.fromisoformat(start_date)
    end = date.fromisoformat(end_date)

    total = (end - start).days + 1
    logger.info(f"=== Backfill {start_date} → {end_date} ({total} ngày) ===")

    current = start
    success = 0
    skipped = 0

    while current <= end:
        batch = current.isoformat()
        logger.info(f"--- Backfill batch: {batch} ---")
        try:
            # Gọi daily_pipeline như một sub-flow
            # Prefect track từng ngày riêng biệt trong UI
            daily_pipeline(batch_date=batch)
            success += 1
        except Exception as e:
            # Log lỗi nhưng tiếp tục sang ngày tiếp theo
            # để một ngày lỗi không block toàn bộ backfill
            logger.error(f"  Batch {batch} failed: {e}")
            skipped += 1

        current += timedelta(days=1)

    logger.info(
        f"=== Backfill xong: {success} thành công, {skipped} thất bại ==="
    )
    if skipped > 0:
        raise RuntimeError(f"Backfill có {skipped} batch lỗi — kiểm tra logs.")


# ──────────────────────────────────────────────────────────────────
# CLI entrypoint (chạy local không cần Prefect server)
# ──────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Game DWH Pipeline")
    sub = parser.add_subparsers(dest="flow", required=True)

    sub.add_parser("setup", help="Khởi tạo DDL + business rules (chạy 1 lần)")

    p_daily = sub.add_parser("daily", help="Chạy daily pipeline")
    p_daily.add_argument("--date", help="YYYY-MM-DD (default: hôm qua)")

    p_backfill = sub.add_parser("backfill", help="Reprocess khoảng ngày")
    p_backfill.add_argument("--start", required=True, help="YYYY-MM-DD")
    p_backfill.add_argument("--end", required=True, help="YYYY-MM-DD")

    args = parser.parse_args()

    if args.flow == "setup":
        setup_flow()
    elif args.flow == "daily":
        daily_pipeline(batch_date=args.date)
    elif args.flow == "backfill":
        backfill_flow(start_date=args.start, end_date=args.end)