# silver/common/standardizer.py
import logging
from pyspark.sql import DataFrame
from pyspark.sql import functions as F

logger = logging.getLogger("silver_pipeline")
'''
Standardizer thực hiện ba nhóm chuẩn hóa chính:

Timestamp standardization – Chuyển đổi timestamp từ milliseconds về dạng timestamp, tạo cột UTC và local time dựa theo country code.

Platform standardization – Chuẩn hóa tên nền tảng (ios/android/unknown) bất kể viết hoa hay viết thường.

Country standardization – Chuẩn hóa mã quốc gia thành chữ hoa, loại bỏ khoảng trắng.'''


_COUNTRY_TZ_MAP = {
    "VN": "Asia/Ho_Chi_Minh",
    "US": "America/New_York",
    "TH": "Asia/Bangkok",
    "ID": "Asia/Jakarta",
    "SG": "Asia/Singapore",
}
_DEFAULT_TZ = "UTC"


def _build_tz_expr(country_col: str) -> F.Column:
    expr = F.lit(_DEFAULT_TZ)
    for code, tz in _COUNTRY_TZ_MAP.items():
        expr = F.when(F.col(country_col) == code, F.lit(tz)).otherwise(expr)
    return expr


def _standardize_timestamps(df: DataFrame) -> DataFrame:
    tz_expr = _build_tz_expr("device.country")

    return (
        df
        .withColumn("server_timestamp_utc",
            F.to_timestamp(F.col("server_timestamp") / 1000))
        .withColumn("client_timestamp_utc",
            F.to_timestamp(F.col("client_timestamp") / 1000))
        .withColumn("event_date",
            F.to_date(F.col("server_timestamp_utc")))
        .withColumn("_tz", tz_expr)
        .withColumn("server_timestamp_local",
            F.from_utc_timestamp(F.col("server_timestamp_utc"), F.col("_tz")))
        .withColumn("local_event_date",
            F.to_date(F.col("server_timestamp_local")))
        .drop("_tz", "client_timestamp", "server_timestamp")
    )


def _standardize_platform(df: DataFrame) -> DataFrame:
    """
    withField() sửa field bên trong struct mà không phá vỡ các field khác.
    Spark 3.1+ required.
    """
    normalized = (
        F.when(F.lower(F.col("device.platform")) == "ios",     F.lit("ios"))
         .when(F.lower(F.col("device.platform")) == "android", F.lit("android"))
         .otherwise(F.lit("unknown"))
    )
    return df.withColumn("device", F.col("device").withField("platform", normalized))


def _standardize_country(df: DataFrame) -> DataFrame:
    """
    Uppercase và trim — 'vn', ' VN ', 'Vn' đều về 'VN'.
    Country null giữ nguyên null, không ép thành 'UNKNOWN'.
    """
    normalized = F.upper(F.trim(F.col("device.country")))
    return df.withColumn("device", F.col("device").withField("country", normalized))


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------
def standardize(df: DataFrame) -> DataFrame:
    """
    Áp dụng toàn bộ standardization theo thứ tự:
    1. Timestamps trước — vì _standardize_timestamps cần device.country
       đã được uppercase (để map timezone đúng).
    2. Country trước platform — cùng lý do trên.
    """
    return (
        df
        .transform(_standardize_country)    # uppercase country trước
        .transform(_standardize_timestamps) # dùng country để map TZ
        .transform(_standardize_platform)   # độc lập, order không quan trọng
    )