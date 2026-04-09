import uuid
import random
import copy
from datetime import datetime

# Hằng số cấu hình Game
APP_VERSION = "1.2.4"
PLATFORMS = ["iOS", "Android"]
COUNTRIES = ["VN", "US", "TH", "ID", "SG"]
NETWORK_TYPES = ["WIFI", "4G", "5G"]


def init_device_state() -> dict:
    """
    Khởi tạo thông tin thiết bị ngẫu nhiên cho một người chơi.
    Thông tin này thường cố định trong suốt vòng đời của một session.
    """
    return {
        "device_id": str(uuid.uuid4())[:8],
        "platform": random.choice(PLATFORMS),
        "os_version": f"{random.randint(14, 17)}.{random.randint(0, 5)}",
        "network_type": random.choice(NETWORK_TYPES),
        "country": random.choice(COUNTRIES)
    }


def init_user_state(user_id: str, account_created_at: datetime) -> dict:
    """
    Khởi tạo trạng thái ban đầu của người chơi (Level 1, 0 Vàng, 0 Kim cương...).
    Trạng thái này sẽ được cập nhật liên tục trong quá trình sinh event.
    """
    return {
        "user_id": user_id,
        "session_id": f"sess_{uuid.uuid4().hex[:10]}",
        "account_created_at": int(account_created_at.timestamp() * 1000),
        "days_since_install": 0,
        "current_state": {
            "level": 1,
            "power_score": 100,
            "gold_balance": 0,
            "gem_balance": 0
        }
    }


def generate_common_wrapper(event_name, event_timestamp, user_state, device_state):
    network_delay_ms = random.randint(50, 800)

    client_ts = int(event_timestamp.timestamp() * 1000)
    server_ts = client_ts + network_delay_ms

    return {
        "event_uuid": str(uuid.uuid4()),
        "event_name": event_name,
        "event_date": event_timestamp.strftime("%Y-%m-%d"),
        "client_timestamp": client_ts,
        "server_timestamp": server_ts,
        "app_version": APP_VERSION,
        "user": {
            "user_id": user_state["user_id"],
            "session_id": user_state["session_id"],
            "account_created_at": user_state["account_created_at"],
            "days_since_install": user_state["days_since_install"],
            "current_state": copy.deepcopy(user_state["current_state"])
        },
        "device": device_state.copy(),
        "event_params": {}
    }