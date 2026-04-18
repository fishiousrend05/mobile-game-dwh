import os
import time
from datetime import date, timedelta


def run_backfill(start_date: date, end_date: date):
    print(f"🚀 BẮT ĐẦU BACKFILL TỪ {start_date} ĐẾN {end_date}")
    print("=" * 50)

    current_date = start_date
    success_count = 0
    fail_count = 0

    start_time = time.time()

    while current_date <= end_date:
        date_str = current_date.strftime("%Y-%m-%d")
        print(f"\n▶️ Đang xử lý Batch: {date_str}...")

        # Kích hoạt luồng Spark y hệt như bạn gõ tay
        exit_code = os.system(f"python -m silver.jobs.load_gold --date {date_str}")

        if exit_code == 0:
            print(f"✅ Xong ngày: {date_str}")
            success_count += 1
        else:
            print(f"❌ CÓ LỖI TẠI NGÀY {date_str}. Dừng toàn bộ hệ thống!")
            fail_count += 1
            break  # Fail-fast: Lỗi ngày nào thì dừng ngay ngày đó để fix, không chạy cố

        current_date += timedelta(days=1)

    elapsed_time = time.time() - start_time
    print("\n" + "=" * 50)
    print(f"🎉 BÁO CÁO KẾT QUẢ BACKFILL")
    print(f"📊 Thành công: {success_count} ngày | Thất bại: {fail_count} ngày.")
    print(f"⏱️ Tổng thời gian chạy: {elapsed_time:.2f} giây.")


if __name__ == "__main__":
    # Bắt đầu từ thư mục cũ nhất trong ảnh của bạn
    START = date(2026, 1, 26)

    # Kết thúc vào ngày 25/03/2026 (Vì ngày 26 bạn đã chạy thành công rồi)
    END = date(2026, 3, 25)

    run_backfill(START, END)