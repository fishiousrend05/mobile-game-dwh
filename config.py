import os
from dataclasses import dataclass
from pathlib import Path
from dotenv import load_dotenv

load_dotenv()


@dataclass(frozen=True)
class Config:
    # MongoDB — dùng chung Bronze & Silver
    mongo_uri: str
    mongo_db: str
    mongo_collection: str

    # Paths
    bronze_path: Path
    silver_path: Path

    # MySQL — dùng cho tầng Gold
    mysql_host: str
    mysql_port: str
    mysql_db: str
    mysql_user: str
    mysql_password: str

    @property
    def fact_events_path(self) -> Path:
        return self.silver_path / "fact_events"

    @property
    def dim_users_path(self) -> Path:
        return self.silver_path / "dim_users"

    @property
    def fact_event_params_path(self) -> Path:
        return self.silver_path / "fact_event_params"

    @property
    def fact_event_items_path(self) -> Path:
        return self.silver_path / "fact_event_items"

    @property
    def mysql_jdbc_url(self) -> str:
        # Chuỗi kết nối JDBC chuẩn cho MySQL
        return f"jdbc:mysql://{self.mysql_host}:{self.mysql_port}/{self.mysql_db}?useSSL=false&allowPublicKeyRetrieval=true"


def load_config() -> Config:
    # Lấy MongoDB vars
    mongo_uri = os.getenv("MONGO_URI")
    db_name = os.getenv("DB_NAME")
    collection_name = os.getenv("COLLECTION_NAME")

    # Lấy MySQL vars
    mysql_host = os.getenv("MYSQL_HOST", "localhost")
    mysql_port = os.getenv("MYSQL_PORT", "3306")
    mysql_db = os.getenv("MYSQL_DB")
    mysql_user = os.getenv("MYSQL_USER")
    mysql_password = os.getenv("MYSQL_PASSWORD")

    # Kích hoạt Fail-fast: Báo lỗi ngay nếu thiếu biến môi trường quan trọng
    if not all([mongo_uri, db_name, collection_name]):
        raise ValueError("❌ Thiếu cấu hình MongoDB! Hãy kiểm tra lại file .env (MONGO_URI, DB_NAME, COLLECTION_NAME).")

    if not all([mysql_db, mysql_user, mysql_password]):
        raise ValueError("❌ Thiếu cấu hình MySQL! Hãy kiểm tra lại file .env.")

    return Config(
        mongo_uri=mongo_uri,
        mongo_db=db_name,
        mongo_collection=collection_name,
        bronze_path=Path(os.getenv("BRONZE_PATH", "data/bronze_parquet")),
        silver_path=Path(os.getenv("SILVER_PATH", "data/silver_parquet")),
        mysql_host=mysql_host,
        mysql_port=mysql_port,
        mysql_db=mysql_db,
        mysql_user=mysql_user,
        mysql_password=mysql_password,
    )