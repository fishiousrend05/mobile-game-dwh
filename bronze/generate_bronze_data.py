import random
from datetime import datetime, timedelta
from faker import Faker
from utils import setup_logger

logger = setup_logger()

# Import kết nối DB
from database import get_collection

# Import các hàm Generator
from generator.common import init_device_state, init_user_state
from generator.user_events import (
    create_account_event, create_login_event,
    create_tutorial_event, create_level_up_event
)
from generator.purchase_events import create_purchase_event, get_product_details

fake = Faker()


def get_user_segment():
    """Phân loại người chơi ngay từ đầu với trọng số thực tế"""
    # 70% chơi cho vui (Casual), 25% cày cuốc (Hardcore), 5% đại gia (Whale)
    return random.choices(["casual", "hardcore", "whale"], weights=[0.7, 0.25, 0.05], k=1)[0]


def simulate_user_flow(start_time: datetime) -> list:
    """Giả lập vòng đời có chiều sâu: Segmentation và Churn rate"""
    events = []
    user_id = f"usr_{fake.unique.random_number(digits=7)}"
    device_state = init_device_state()
    user_state = init_user_state(user_id, start_time)
    current_time = start_time

    # 1. Gán đặc tính nhân vật (Behavior Traits)
    segment = get_user_segment()
    has_bought_starter = False
    has_made_first_purchase = False

    # Xác định ngày bỏ game (Churn Day) - Nhóm Casual dễ bỏ game sớm hơn
    if segment == "casual":
        churn_day = random.randint(1, 10) if random.random() < 0.8 else 31  # 80% bỏ game trước ngày 10
    elif segment == "hardcore":
        churn_day = random.randint(15, 30) if random.random() < 0.4 else 31  # 40% bỏ game nửa sau tháng
    else:  # whale
        churn_day = 31  # Đại gia hiếm khi bỏ game sớm

    # --- DAY 0: ONBOARDING ---
    events.append(create_account_event(user_state, device_state, current_time))

    current_time += timedelta(minutes=random.randint(1, 5))
    events.append(create_login_event(user_state, device_state, current_time, login_streak=1, days_since_last=0))

    if random.random() < (0.9 if segment != "casual" else 0.6):  # Hardcore/Whale ít skip tutorial hơn
        current_time += timedelta(minutes=random.randint(5, 15))
        user_state["current_state"]["gold_balance"] += 500
        events.append(create_tutorial_event(user_state, device_state, current_time))

    # --- DAY 1 đến DAY 30: RETENTION & MONETIZATION LOOP ---
    login_streak = 1
    last_login_day = 0

    for current_day in range(1, 31):
        # 2. Xử lý Churn thực sự (Bỏ game là cắt đứt hoàn toàn)
        if current_day >= churn_day:
            break

            # Xác suất log in phụ thuộc vào Segment
        retention_chance = 0.9 if segment == "hardcore" else (0.7 if segment == "whale" else 0.4)

        if random.random() < retention_chance:
            current_time = start_time + timedelta(days=current_day, hours=random.randint(8, 20))
            user_state["days_since_install"] = current_day

            days_since_last = current_day - last_login_day
            login_streak = login_streak + 1 if days_since_last == 1 else 1
            last_login_day = current_day

            events.append(create_login_event(user_state, device_state, current_time, login_streak, days_since_last))

            # Số lần cày level phụ thuộc vào Segment
            grind_times = random.randint(2, 5) if segment == "hardcore" else (
                random.randint(1, 2) if segment == "whale" else random.randint(0, 1))

            for _ in range(grind_times):
                current_time += timedelta(minutes=random.randint(30, 120))
                old_level = user_state["current_state"]["level"]
                user_state["current_state"]["level"] += 1
                user_state["current_state"]["power_score"] += random.randint(100, 300)
                events.append(create_level_up_event(user_state, device_state, current_time, old_level,
                                                    random.randint(3600, 86400)))

                # 3. Monetization theo Segment
                product_to_buy = None

                # Casual hiếm khi nạp, Hardcore nạp gem khi kẹt, Whale nạp skin/thẻ tháng
                if segment != "casual":
                    if user_state["current_state"]["level"] < 5 and not has_bought_starter and random.random() < 0.3:
                        product_to_buy = "starter_pack"
                        has_bought_starter = True
                    elif random.random() < 0.1:  # Kẹt ải
                        product_to_buy = "gem_box_large"
                    elif segment == "whale" and random.random() < 0.4:
                        product_to_buy = random.choice(["monthly_pass", "hero_skin_fire_dragon"])

                if product_to_buy:
                    current_time += timedelta(minutes=random.randint(1, 5))
                    purchase_event = create_purchase_event(
                        user_state, device_state, current_time,
                        is_first_purchase=not has_made_first_purchase,
                        product_id=product_to_buy
                    )

                    if purchase_event:
                        events.append(purchase_event)
                        has_made_first_purchase = True
                        product_info = get_product_details(product_to_buy)
                        for item in product_info["items"]:
                            if item["item_id"] == "gem":
                                user_state["current_state"]["gem_balance"] += item["quantity"]

    return events


def main():
    logger.info("🚀 Bắt đầu quá trình sinh dữ liệu game (Tối ưu RAM & Hành vi)...")
    num_users = 1000
    batch_size = 5000  # Cứ 5000 events là đẩy lên DB 1 lần

    collection = get_collection()
    if collection is None:
        logger.error("❌ Lỗi kết nối Database. Dừng chương trình.")
        return

    # TUYỆT ĐỐI KHÔNG DÙNG collection.drop() trên Production
    # Nếu đang làm môi trường Dev và muốn xóa data cũ, bạn có thể cân nhắc mở lại.

    event_buffer = []
    total_inserted = 0

    for i in range(num_users):
        start_time = fake.date_time_between(start_date='-60d', end_date='-30d')
        user_events = simulate_user_flow(start_time)
        event_buffer.extend(user_events)

        # In log tiến độ để biết script vẫn đang chạy bình thường
        if (i + 1) % 100 == 0:
            logger.info(f"   Đang xử lý: Đã mô phỏng xong {i + 1}/{num_users} users...")

        # 4. Kiểm soát Memory: Ghi theo Batch
        if len(event_buffer) >= batch_size:
            collection.insert_many(event_buffer)
            total_inserted += len(event_buffer)
            logger.info(f"   [Batch Insert] Đã đẩy thành công lên DB: {total_inserted} events...")
            event_buffer.clear()  # Xóa RAM ngay lập tức

    # Đẩy nốt phần dữ liệu còn sót lại cuối cùng (nếu có)
    if event_buffer:
        collection.insert_many(event_buffer)
        total_inserted += len(event_buffer)
        logger.info(f"   [Final Insert] Đã đẩy nốt {len(event_buffer)} events cuối cùng...")

    logger.info(f"🎉 THÀNH CÔNG! Đã nạp an toàn tổng cộng {total_inserted} sự kiện (Log) vào MongoDB Atlas.")


if __name__ == "__main__":
    main()