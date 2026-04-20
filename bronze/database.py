# Gọi hàm load_config thay vì class Config
from config import load_config
from pymongo import MongoClient


def get_collection():
    # 1. Khởi tạo config thực tế
    cfg = load_config()

    # 2. Sử dụng các biến chữ thường đã được định nghĩa trong dataclass
    client = MongoClient(cfg.mongo_uri)
    db = client[cfg.mongo_db]
    return db[cfg.mongo_collection]