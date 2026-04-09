import uuid
import random
import copy
import logging
from datetime import datetime

# Import hàm tạo khung từ file common.py cùng thư mục
from .common import generate_common_wrapper

# "Catalogue" map chính xác tên gói, giá, vật phẩm và BỐI CẢNH (Context) hợp lý
PRODUCTS = {
    "starter_pack": {
        "price": 0.99,
        "allowed_contexts": ["limited_offer", "impulse_buy"],  # Tân thủ không thể kẹt ải được
        "items": [
            {"item_id": "gem", "quantity": 100, "type": "currency"},
            {"item_id": "iron_sword", "quantity": 1, "type": "equipment"}
        ]
    },
    "monthly_pass": {
        "price": 4.99,
        "allowed_contexts": ["paywall", "limited_offer"],
        "items": [
            {"item_id": "gem", "quantity": 1500, "type": "currency"},
            {"item_id": "vip_ticket", "quantity": 1, "type": "buff"}
        ]
    },
    "gem_box_large": {
        "price": 9.99,
        "allowed_contexts": ["stuck_progression", "impulse_buy"],  # Hợp lý khi kẹt ải cần mua gem gấp
        "items": [
            {"item_id": "gem", "quantity": 1200, "type": "currency"}
        ]
    },
    "hero_skin_fire_dragon": {
        "price": 14.99,
        "allowed_contexts": ["cosmetic"],  # Chỉ có thể là lý do làm đẹp
        "items": [
            {"item_id": "skin_fire_dragon", "quantity": 1, "type": "cosmetic"}
        ]
    }
}


def create_purchase_event(user_state: dict, device_state: dict, event_timestamp: datetime, is_first_purchase: bool,
                          product_id: str) -> dict:
    """
    Tạo sự kiện nạp tiền (In-App Purchase).
    Lưu ý: Không update state ở đây. Trách nhiệm cộng tiền thuộc về Orchestrator.
    """
    try:
        product_info = PRODUCTS[product_id]
    except KeyError:
        logging.error(f"❌ Lỗi: Mã gói nạp '{product_id}' không tồn tại trong hệ thống!")
        return None  # Trả về None để Orchestrator biết mà bỏ qua

    event = generate_common_wrapper("in_app_purchase", event_timestamp, user_state, device_state)
    store = "app_store" if device_state.get("platform") == "iOS" else "google_play"

    event["event_params"] = {
        "transaction_id": f"txn_{store[:3]}_{uuid.uuid4().hex[:10]}",
        "store": store,
        "product_id": product_id,
        "revenue_usd": product_info["price"],
        "is_first_purchase": is_first_purchase,
        "purchase_context": random.choice(product_info["allowed_contexts"]),  # Giải quyết lỗi Random Context
        "items_received": copy.deepcopy(product_info["items"])  # Giải quyết lỗi Reference
    }

    return event


def get_product_details(product_id: str) -> dict:
    """Hàm tiện ích để Orchestrator lấy thông tin item nhằm update User State"""
    return PRODUCTS.get(product_id)