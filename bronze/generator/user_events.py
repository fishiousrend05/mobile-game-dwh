import random
from datetime import datetime
from faker import Faker

# Import hàm tạo khung từ file common.py cùng thư mục
from .common import generate_common_wrapper

# 1. Khởi tạo đối tượng Faker (Bắt buộc để không bị crash)
fake = Faker()

# --- CÁC HẰNG SỐ & DANH MỤC CHO SỰ KIỆN ---
ACQ_CHANNELS = ["facebook_ads", "google_ads", "organic", "tiktok_ads"]
LOGIN_METHODS = ["apple_id", "google_play", "facebook", "guest"]
TUTORIAL_VERSIONS = ["v1_combat_focus", "v2_story_focus"]

# 2. Định nghĩa danh sách Device Model thực tế (Trông "pro" hơn rất nhiều)
REALISTIC_DEVICES = [
    "iPhone 13 Pro Max", "iPhone 14", "iPhone 15 Pro",
    "Samsung Galaxy S23 Ultra", "Samsung Galaxy Z Fold 5", "Samsung Galaxy A54",
    "Xiaomi 13 Pro", "Redmi Note 12",
    "Google Pixel 8 Pro", "Oppo Find X6"
]


def create_account_event(user_state: dict, device_state: dict, event_timestamp: datetime) -> dict:
    """Tạo sự kiện tạo tài khoản (Day 0)"""
    event = generate_common_wrapper("account_created", event_timestamp, user_state, device_state)

    event["event_params"] = {
        "acquisition_channel": random.choice(ACQ_CHANNELS),
        "campaign_id": f"camp_{random.randint(100, 999)}_promo",
        # Sử dụng danh sách thiết bị thực tế thay vì fake.word()
        "device_model": random.choice(REALISTIC_DEVICES)
    }
    return event


def create_login_event(user_state: dict, device_state: dict, event_timestamp: datetime, login_streak: int,
                       days_since_last: int) -> dict:
    """Tạo sự kiện đăng nhập"""
    event = generate_common_wrapper("login", event_timestamp, user_state, device_state)

    event["event_params"] = {
        "login_method": random.choice(LOGIN_METHODS),
        "is_first_login_of_day": True,
        "days_since_last_login": days_since_last,
        "login_streak": login_streak
    }
    return event


def create_tutorial_event(user_state: dict, device_state: dict, event_timestamp: datetime) -> dict:
    """Tạo sự kiện hoàn thành hướng dẫn tân thủ"""
    event = generate_common_wrapper("tutorial_completed", event_timestamp, user_state, device_state)

    event["event_params"] = {
        "tutorial_version": random.choice(TUTORIAL_VERSIONS),
        "time_spent_seconds": random.randint(120, 400),
        "dialogue_skipped": random.choice([True, False]),
        "deaths_during_tutorial": random.randint(0, 2),
        "reward_claimed": {
            "item_id": "wooden_sword",
            "type": "weapon"
        }
    }
    return event


def create_level_up_event(user_state: dict, device_state: dict, event_timestamp: datetime, old_level: int,
                          time_to_level_up: int) -> dict:
    """Tạo sự kiện lên cấp"""
    event = generate_common_wrapper("level_up", event_timestamp, user_state, device_state)

    event["event_params"] = {
        "old_level": old_level,
        "new_level": user_state["current_state"]["level"],
        "time_to_level_up_seconds": time_to_level_up,
        "location_id": f"dungeon_{random.randint(1, 10):02d}",
        "resources_spent": [
            {"item_id": "exp_potion", "quantity": random.randint(1, 5)},
            {"item_id": "gold", "quantity": random.randint(100, 500)}
        ]
    }
    return event