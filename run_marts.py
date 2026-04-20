# gold/run_marts.py
"""
Chạy toàn bộ mart tables và views trong thư mục mart/.

Thứ tự thực thi:
  1. mart_*.sql (CREATE TABLE + REPLACE INTO) — theo domain alphabetically
  2. vw_*.sql   (CREATE OR REPLACE VIEW)      — sau khi mart tables đã có data

Chạy:
  python gold/run_marts.py
  python gold/run_marts.py --dry-run   # chỉ in danh sách file, không chạy
"""

import os
import sys
import argparse
import mysql.connector
from dotenv import load_dotenv


# ──────────────────────────────────────────────────────────────────
# Connection
# ──────────────────────────────────────────────────────────────────

def get_connection():
    load_dotenv()
    return mysql.connector.connect(
        host=os.getenv("MYSQL_HOST", "localhost"),
        port=int(os.getenv("MYSQL_PORT", 3306)),
        user=os.getenv("MYSQL_USER", "root"),
        password=os.getenv("MYSQL_PASSWORD", ""),
        database=os.getenv("MYSQL_DB", "game_gold"),
        # Cho phép nhiều statement trong một execute() call
        # Cần thiết vì mỗi file .sql chứa cả DDL lẫn DML
        allow_local_infile=False,
    )


# ──────────────────────────────────────────────────────────────────
# File discovery & ordering
# ──────────────────────────────────────────────────────────────────

def collect_sql_files(base_dir: str) -> list[str]:
    """
    Walk mart/ và trả về danh sách file .sql đã sắp xếp:
      - mart_*.sql trước  (CREATE TABLE + REPLACE INTO)
      - vw_*.sql   sau   (CREATE OR REPLACE VIEW — phụ thuộc mart table)
      - Trong cùng nhóm: sort alphabetically theo path
    """
    sql_files = []
    for root, _, files in os.walk(base_dir):
        for f in sorted(files):  # sort trong cùng folder
            if f.endswith(".sql"):
                sql_files.append(os.path.join(root, f))

    # mart_* trước, vw_* sau — sort stable giữ thứ tự alphabetical trong mỗi nhóm
    sql_files.sort(key=lambda p: (1 if os.path.basename(p).startswith("vw_") else 0, p))
    return sql_files


# ──────────────────────────────────────────────────────────────────
# SQL execution
# ──────────────────────────────────────────────────────────────────

def _split_sql_statements(sql: str) -> list:
    """
    Tách SQL script thành statements an toàn.
    Không dùng multi=True vì CMySQLCursor không hỗ trợ.
    Theo dõi depth của parentheses để ';' bên trong PARTITION block
    không bị tách nhầm thành statement terminator.
    """
    import re
    sql = re.sub(r"--[^\n]*", "", sql)
    sql = re.sub(r"/\*.*?\*/", "", sql, flags=re.DOTALL)
    statements, current, depth = [], [], 0
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
    last = "".join(current).strip()
    if last:
        statements.append(last)
    return statements


def execute_sql_file(conn, file_path: str) -> int:
    """
    Đọc và thực thi một file .sql.
    Trả về số statements đã chạy thành công.
    """
    with open(file_path, encoding="utf-8") as f:
        sql_script = f.read()

    statements = _split_sql_statements(sql_script)
    cursor = conn.cursor()
    count = 0

    try:
        for stmt in statements:
            cursor.execute(stmt)
            count += 1

        # Commit sau mỗi file
        conn.commit()

    except mysql.connector.Error as e:
        conn.rollback()
        raise RuntimeError(
            f"Lỗi khi chạy '{os.path.basename(file_path)}':\n"
            f"  [MySQL {e.errno}] {e.msg}"
        ) from e
    finally:
        cursor.close()

    return count


# ──────────────────────────────────────────────────────────────────
# Main
# ──────────────────────────────────────────────────────────────────

def main() -> None:
    parser = argparse.ArgumentParser(description="Chạy toàn bộ Gold mart tables và views")
    parser.add_argument(
        "--base-dir", default="gold/mart",
        help="Thư mục gốc chứa các file mart/*.sql (default: gold/mart)",
    )
    parser.add_argument(
        "--dry-run", action="store_true",
        help="Chỉ in danh sách file sẽ chạy, không thực thi",
    )
    args = parser.parse_args()

    # ── Collect files ──────────────────────────────────────────
    sql_files = collect_sql_files(args.base_dir)

    if not sql_files:
        print(f"[run_marts] Không tìm thấy file .sql trong '{args.base_dir}'")
        sys.exit(1)

    print(f"[run_marts] Tìm thấy {len(sql_files)} file SQL:\n")
    mart_files = [f for f in sql_files if not os.path.basename(f).startswith("vw_")]
    view_files = [f for f in sql_files if os.path.basename(f).startswith("vw_")]

    print("  -- mart tables --")
    for f in mart_files:
        print(f"  {f}")
    print("  -- views --")
    for f in view_files:
        print(f"  {f}")
    print()

    if args.dry_run:
        print("[run_marts] Dry-run mode — không thực thi.")
        return

    # ── Connect & run ──────────────────────────────────────────
    print("[run_marts] Kết nối MySQL...")
    try:
        conn = get_connection()
    except mysql.connector.Error as e:
        print(f"[run_marts] Không thể kết nối MySQL: {e}")
        sys.exit(1)

    success = 0
    failed = 0

    try:
        for file_path in sql_files:
            label = os.path.basename(file_path)
            print(f"  → {label} ...", end=" ", flush=True)
            try:
                stmts = execute_sql_file(conn, file_path)
                print(f"OK ({stmts} statements)")
                success += 1
            except RuntimeError as e:
                print("FAILED")
                print(f"     {e}")
                failed += 1
                # Dừng ngay khi có lỗi — không chạy file tiếp theo
                # vì view phụ thuộc mart table: nếu mart lỗi thì view cũng sẽ lỗi
                break

    finally:
        conn.close()

    # ── Summary ────────────────────────────────────────────────
    print()
    if failed == 0:
        print(f"[run_marts] Hoàn thành: {success}/{len(sql_files)} files thành công.")
    else:
        remaining = len(sql_files) - success - failed
        print(
            f"[run_marts] Dừng tại file thứ {success + 1}. "
            f"{success} thành công, {failed} lỗi, {remaining} bị bỏ qua."
        )
        sys.exit(1)  # exit non-zero để CI/scheduler biết có lỗi


if __name__ == "__main__":
    main()
