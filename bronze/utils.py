import logging
import sys
import os


def setup_logger(logger_name: str = "bronze_pipeline", log_file: str = "bronze_generation.log") -> logging.Logger:
    """
    Thiết lập hệ thống logging chuẩn.
    Log sẽ được in ra màn hình (Console) VÀ lưu lại vào file (FileHandler).
    """
    logger = logging.getLogger(logger_name)

    # Đảm bảo không bị duplicate log nếu gọi hàm này nhiều lần
    if not logger.handlers:
        logger.setLevel(logging.INFO)

        # Định dạng chuẩn: [YYYY-MM-DD HH:MM:SS] [INFO/ERROR] - Nội dung
        formatter = logging.Formatter(
            fmt="[%(asctime)s] [%(levelname)s] - %(message)s",
            datefmt="%Y-%m-%d %H:%M:%S"
        )

        # 1. In ra màn hình Terminal
        console_handler = logging.StreamHandler(sys.stdout)
        console_handler.setFormatter(formatter)
        logger.addHandler(console_handler)

        # 2. Lưu vào thư mục logs/
        os.makedirs("logs", exist_ok=True)
        file_path = os.path.join("logs", log_file)
        file_handler = logging.FileHandler(file_path, encoding="utf-8")
        file_handler.setFormatter(formatter)
        logger.addHandler(file_handler)

    return logger


def get_current_timestamp_ms() -> int:
    """Hàm tiện ích lấy Unix timestamp hiện tại (millisecond)"""
    import time
    return int(time.time() * 1000)