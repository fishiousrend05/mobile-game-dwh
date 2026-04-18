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
        allow_local_infile=False,
        use_pure=True
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

def execute_sql_file(conn, file_path: str) -> int:
    with open(file_path, encoding="utf-8") as f:
        sql_script = f.read()

    cursor = conn.cursor()
    count = 0

    try:
        # Tách các lệnh SQL bằng dấu chấm phẩy
        statements = sql_script.split(';')

        for statement in statements:
            # Chỉ chạy những đoạn có chứa chữ (bỏ qua dấu cách/xuống dòng thừa)
            if statement.strip():
                cursor.execute(statement)
                count += 1

        # Commit sau mỗi file
        conn.commit()

    except Exception as e:
        conn.rollback()
        raise RuntimeError(
            f"Lỗi khi chạy '{os.path.basename(file_path)}':\n  {e}"
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